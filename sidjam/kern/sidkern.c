/*
 * sidkern - SID-Registerstrom aus .sid-Dateien (Teil von SID JAM)
 * Copyright (c) 2026 retro-modern.net. GPL-3.0-or-later.
 *
 * Laesst die Abspielroutine eines SIDs auf einem nachgebauten 6510 mit
 * C64-Umgebung laufen und schreibt jeden Schreibzugriff auf ein SID-Register
 * mit seinem Zyklus heraus (SJE, siehe ../SCHNITTSTELLEN.md). Ton entsteht
 * hier keiner.
 *
 *   sidkern DATEI.sid [-s LIED] [-t SEK] [--ab SEK] [-o AUS.sje]
 *                     [--model 6581|8580] [--pal|--ntsc] [--text] [--info]
 *   sidkern --cputest DATEI.bin [--laden ADR] [--start ADR] [--erfolg ADR] [--fehlerbyte ADR]
 *
 * Rueckgabe: 0 gut (auch: Leser hat die Leitung geschlossen), 1 Aufruf- oder
 * Dateifehler, 2 keine gueltige SID-Datei, 3 Lied braucht BASIC (nicht spielbar).
 *
 * Der PSID-Treiber steckt im Programm, nicht im C64-Speicher: init wird wie
 * mit JSR aufgerufen und kehrt auf eine Fangadresse zurueck; play laeuft wie
 * eine Interruptroutine (IRQ von VIC oder CIA 1 wie beim echten Treiber).
 */
#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include "kern.h"
#include "siddatei.h"

/* ============================================================ Ausgabe */

static FILE *aus;
static uint8_t puffer[4096];
static size_t fuell;
static int text_modus;
static uint64_t start_zyklus, ende_zyklus, letzter_zyklus;
static int abbild_noetig;
static uint64_t anzahl_schreib;

static void schreibfehler(void)
{
    if (errno == EPIPE) exit(0);            /* Leser ist weg: still beenden */
    fprintf(stderr, "sidkern: Schreibfehler: %s\n", strerror(errno));
    exit(1);
}

static void spuelen(void)
{
    if (!fuell) return;
    errno = 0;
    if (fwrite(puffer, 1, fuell, aus) != fuell || fflush(aus) != 0) schreibfehler();
    fuell = 0;
}

static void raus(const void *p, size_t n)
{
    const uint8_t *q = p;
    while (n) {
        size_t k = sizeof puffer - fuell;
        if (k > n) k = n;
        memcpy(puffer + fuell, q, k);
        fuell += k; q += k; n -= k;
        if (fuell == sizeof puffer) spuelen();
    }
}

static size_t varint(uint8_t *b, uint64_t d)
{
    size_t n = 0;
    do {
        uint8_t x = d & 0x7F;
        d >>= 7;
        if (d) x |= 0x80;
        b[n++] = x;
    } while (d);
    return n;
}

static void datensatz(uint64_t zyk, int chip, int reg, uint8_t wert)
{
    anzahl_schreib++;
    if (text_modus) {
        char z[64];
        int n = snprintf(z, sizeof z, "%llu %d %02X %02X\n", (unsigned long long)zyk, chip, reg, wert);
        raus(z, (size_t)n);
        return;
    }
    uint8_t b[16];
    size_t n = varint(b, zyk - letzter_zyklus);
    letzter_zyklus = zyk;
    b[n++] = (uint8_t)((chip << 5) | reg);
    b[n++] = wert;
    raus(b, n);
}

static void abbild_schreiben(void)
{
    abbild_noetig = 0;
    for (int chip = 0; chip < M.anzahl_sids; chip++)
        for (int reg = 0; reg <= 24; reg++)
            datensatz(start_zyklus, chip, reg, M.sid[chip].reg[reg]);
}

static void mitschnitt(uint64_t zyk, int chip, int reg, uint8_t wert)
{
    if (zyk < start_zyklus || zyk >= ende_zyklus) return;
    if (abbild_noetig) abbild_schreiben();
    datensatz(zyk, chip, reg, wert);
}

static void strom_beenden(uint64_t zyk)
{
    if (abbild_noetig) abbild_schreiben();
    if (text_modus) {
        char z[64];
        int n = snprintf(z, sizeof z, "# ende %llu\n", (unsigned long long)zyk);
        raus(z, (size_t)n);
    } else {
        uint8_t b[16];
        size_t n = varint(b, zyk - letzter_zyklus);
        b[n++] = 0x7F;
        raus(b, n);
    }
    spuelen();
}

/* ============================================================ Treiber */

static SidKopf K;
static int lied, cia_tempo, ntsc, modell8580;
static uint8_t play_bank;
enum { FANG_INIT = 1, FANG_PLAY = 2 };
static uint8_t fang_art[16];
static uint64_t init_zurueck = NIE, play_aufrufe;

static uint8_t bank_fuer(uint16_t adr)
{
    if (adr < 0xA000) return 0x37;
    if (adr < 0xD000) return 0x36;
    if (adr >= 0xE000) return 0x35;
    return 0x34;
}

static void stapel(uint8_t v) { M.ram[0x100 | C.s] = v; C.s--; }
static uint8_t holen(void) { C.s++; return M.ram[0x100 | C.s]; }

static void fang_setzen(int art)
{
    uint8_t sp = C.s;
    stapel((uint8_t)((FANG - 1) >> 8));
    stapel((uint8_t)(FANG - 1));
    fang_art[M.fang_tiefe] = (uint8_t)art;
    M.fang_sp[M.fang_tiefe++] = sp;
}

static void quittieren(void)
{
    /* wie der Treiber nach play: DEC $D019 (schreibt erst den alten Wert
     * zurueck, quittiert also alles) und LDA $DC0D */
    uint8_t v = io_lesen(0xD019, C.z);
    io_schreiben(0xD019, v, C.z);
    (void)io_lesen(0xDC0D, C.z);
}

/* IRQ ist faellig und landet ueber $FFFE/$0314 beim Treiber: play rufen */
static void psid_play_rufen(void)
{
    if (M.fang_tiefe >= 16) {               /* play unterbricht sich selbst: Bild auslassen */
        quittieren();
        return;
    }
    stapel((uint8_t)(C.pc >> 8));
    stapel((uint8_t)C.pc);
    stapel(cpu_p(0));
    C.fi = 1;
    stapel(C.a); stapel(C.x); stapel(C.y);
    stapel(port_lesen(1));
    port_schreiben(1, play_bank);
    C.a = 0;
    fang_setzen(FANG_PLAY);
    C.pc = K.play;
    C.i_pruef = 1;
    /* Zeit wie beim Treiber von sidplayfp: Interruptfolge, Register retten,
     * JMP ($0314), $01 retten und setzen, LDA #0, JSR play (46 Takte) */
    cpu_buszyklen("RRWWWRR" "RRW" "RR" "RRW" "RR" "RRW" "RRRRR" "RRR" "RRW" "RRRR" "RRW" "RR" "RRRWWR");
    play_aufrufe++;
}

static void fang_bearbeiten(void)
{
    int art = fang_art[--M.fang_tiefe];
    if (art == FANG_INIT) {
        if (!K.rsid) {
            if (K.play) port_schreiben(1, 0x37);
            C.fi = 0;                       /* CLI */
        }
        C.i_pruef = C.fi;
        M.leerlauf = 1;
        if (init_zurueck == NIE) init_zurueck = C.z;
        return;
    }
    port_schreiben(1, holen());
    quittieren();
    C.y = holen(); C.x = holen(); C.a = holen();
    cpu_p_setzen(holen());
    uint16_t lo = holen();
    uint16_t hi = holen();
    C.pc = (uint16_t)(lo | (hi << 8));
    C.i_pruef = C.fi;
    /* Treiberende: PLA, STA $01, DEC $D019, LDA $DC0D, Register zurueck, RTI (39 Takte) */
    cpu_buszyklen("RRRR" "RRW" "RRRRWW" "RRRR" "RRRR" "RR" "RRRR" "RR" "RRRR" "RRRRRR");
}

static void w16(uint16_t adr, uint16_t wert) { M.ram[adr] = (uint8_t)wert; M.ram[adr + 1] = (uint8_t)(wert >> 8); }

static void ram_vorbelegen(void)
{
    /* Einschaltmuster wie bei einem C64 (und wie in sidplayfp): je 16 KB ein
     * Grundwert ($00, $FF, $00, $FF), in jedem 8-Byte-Abschnitt die Bytes 2-5
     * umgekehrt. Manche Stuecke lesen Speicher, den sie nie beschrieben haben. */
    for (unsigned a = 0; a < 0x10000; a++) {
        uint8_t grund = ((a >> 14) & 1) ? 0xFF : 0x00;
        M.ram[a] = ((a & 7) >= 2 && (a & 7) <= 5) ? (uint8_t)~grund : grund;
    }
    memset(M.ram, 0, 0x400);
    M.ram[0] = 0x2F;
    M.ram[1] = 0x37;

    /* Vektoren wie nach dem Einschalten */
    static const uint16_t vek300[] = { 0xE38B, 0xA483, 0xA57C, 0xA71A, 0xA7E4, 0xAE86 };
    static const uint16_t vek314[] = {
        0xEA31, 0xFE66, 0xFE47, 0xF34A, 0xF291, 0xF20E, 0xF250, 0xF333,
        0xF157, 0xF1CA, 0xF6ED, 0xF13E, 0xF32F, 0xFE66, 0xF4A5, 0xF5ED
    };
    for (int i = 0; i < 6; i++) w16((uint16_t)(0x300 + 2 * i), vek300[i]);
    for (int i = 0; i < 16; i++) w16((uint16_t)(0x314 + 2 * i), vek314[i]);
    M.ram[0x02A6] = ntsc ? 0 : 1;           /* PAL-Kennung */
    if (!K.rsid) return;

    /* RSID: Zustand nach dem Start bis zum READY (wie bei sidplayfp nur fuer
     * RSID). Manche Stuecke benutzen Nullseiten-Zellen, ohne sie zu setzen. */
    w16(0x03, 0xB1AA); w16(0x05, 0xB391);   /* Umrechnungsvektoren */
    M.ram[0x16] = 0x19; M.ram[0x17] = 0x16; /* Stringstapel */
    w16(0x2B, 0x0801);                      /* BASIC-Programm ab $0801 ... */
    w16(0x2D, 0x0803); w16(0x2F, 0x0803); w16(0x31, 0x0803);
    w16(0x33, 0xA000); w16(0x37, 0xA000);   /* ... Speicher bis $A000 */
    M.ram[0x53] = 0x03; M.ram[0x54] = 0x4C;
    M.ram[0x91] = 0xFF;                     /* keine STOP-Taste */
    M.ram[0x9A] = 0x03;                     /* Ausgabe auf den Bildschirm */
    w16(0xB2, 0x033C);                      /* Kassettenpuffer */
    M.ram[0xC5] = 0x01; M.ram[0xCB] = 0x01;
    M.ram[0xC8] = 0x03; M.ram[0xC9] = 0x03; M.ram[0xCA] = 0x03; M.ram[0xCC] = 0x01;
    M.ram[0xCE] = 0x20;
    w16(0xD1, 0x0518);                      /* Cursor in Zeile 7 (nach READY.) */
    M.ram[0xD5] = 0x27; M.ram[0xD6] = 0x07; M.ram[0xD7] = 0x0D;
    for (int i = 0; i <= 25; i++)           /* Zeilenverknuepfung: High-Bytes der Bildschirmzeilen */
        M.ram[0xD9 + i] = (uint8_t)(0x80 | ((0x0400 + 40 * (i < 25 ? i : 24)) >> 8));
    w16(0xF3, 0xD918);                      /* Farbzeiger der Cursorzeile */
    w16(0xF5, 0xEB81);                      /* Tastaturtabelle */
    M.ram[0x0282] = 0x08; M.ram[0x0284] = 0xA0;
    M.ram[0x0286] = 0x0E;                   /* Schriftfarbe */
    M.ram[0x0288] = 0x04;                   /* Bildschirm ab $0400 */
    M.ram[0x0289] = 0x0A; M.ram[0x028B] = 0x04; M.ram[0x028C] = 0x10;
    w16(0x028F, 0xEB48);                    /* Tastaturdekodierung */
    M.ram[0x0310] = 0x4C; w16(0x0311, 0xB248);   /* USR */
}

static void umgebung_einrichten(void)
{
    maschine_anlegen(ntsc, 0);
    M.bus_ttl = modell8580 ? 663552 : 7424;
    for (int i = 1; i < K.anzahl_sids; i++) sid_einrichten(i, K.sid_adr[i]);
    M.sid_mitschnitt = mitschnitt;
    ram_vorbelegen();
    memcpy(&M.ram[K.load], K.daten, K.laenge);

    /* CIA 1 Timer A laeuft mit dem KERNAL-Wert; Interrupt an fuer RSID und
     * fuer PSID mit CIA-Tempo. Die Ports bleiben wie nach einem Reset
     * (Eingang, lesen $FF) - so liest auch sidplayfp, und manche Stuecke
     * warten auf "keine Taste". */
    int psid = !K.rsid;
    uint16_t ta = ntsc ? 0x4295 : 0x4025;
    cia_einrichten(&M.cia1, ta, 1, (K.rsid || cia_tempo) ? 0x01 : 0x00);
    /* Phase wie bei sidplayfp: dort startet der Treiber den Timer 38 (PSID)
     * bzw. 41 (RSID) Takte vor init; mit Startverzoegerung steht der Zaehler
     * bei Zyklus 0 schon 36 bzw. 39 Schritte weiter */
    M.cia1.ta.wert = (uint16_t)(ta - (K.rsid ? 39 : 36));
    cia_einrichten(&M.cia2, 0xFFFF, 0, 0);

    /* VIC: RSID Zeile 311 (aus), PSID Zeile 0, an bei VBI-Tempo. Passt
     * die Uhr des Stuecks nicht zur Maschine, wie beim Treiber Zeile 0. */
    int uhr = sid_kopf_uhr(&K);
    int passt = uhr == 0 || uhr == 3 || (uhr == 1 && !ntsc) || (uhr == 2 && ntsc);
    if (K.rsid && passt) vic_einrichten(0x9B, 0x37, 0x00);
    else vic_einrichten(0x1B, 0x00, (psid && !cia_tempo) ? 0x01 : 0x00);

    /* init wie mit JSR, Ruecksprung auf die Fangadresse */
    memset(&C, 0, sizeof C);
    C.s = 0xFF;
    fang_setzen(FANG_INIT);
    C.pc = K.init;
    C.a = (uint8_t)(lied - 1);
    /* X und Y wie beim Treiber von sidplayfp (manche unsauberen Rips lesen
     * sie): RSID X=$01, Y=$37 (bei passender Uhr); PSID Y=$00 und X=$01 (CIA),
     * $A8 (VBI mit play, Low-Byte des IRQ-Einsprungs) oder $1B (play = 0) */
    if (K.rsid) { C.x = 0x01; C.y = passt ? 0x37 : 0x00; }
    else { C.x = cia_tempo ? 0x01 : (K.play ? 0xA8 : 0x1B); C.y = 0x00; }
    cpu_p_setzen(psid ? 0x24 : 0x20);
    C.i_pruef = C.fi;
    if (psid) port_schreiben(1, bank_fuer(K.init));
    play_bank = bank_fuer(K.play);
    M.psid_nativ = psid && K.play != 0;
    M.leerlauf = 0;
    ereignisse(0);
}

/* ============================================================ CPU-Test */

static int cpu_test(const char *datei, long laden, long start, long erfolg, long fehlerbyte)
{
    FILE *f = fopen(datei, "rb");
    if (!f) { fprintf(stderr, "sidkern: %s: %s\n", datei, strerror(errno)); return 1; }
    maschine_anlegen(0, 1);
    size_t n = fread(&M.ram[laden], 1, (size_t)(0x10000 - laden), f);
    fclose(f);
    memset(&C, 0, sizeof C);
    C.pc = (uint16_t)start;
    C.s = 0xFF;
    cpu_p_setzen(0x24);
    C.i_pruef = 1;
    clock_t t0 = clock();
    /* Befehl fuer Befehl, bis der PC auf sich selbst stehen bleibt */
    uint64_t befehle = 0;
    while (C.z < 20000000000ull) {
        uint16_t pc = C.pc;
        if (cpu_lauf(C.z + 1) == GRUND_JAM) break;
        befehle++;
        if (C.pc == pc) break;
    }
    double sek = (double)(clock() - t0) / CLOCKS_PER_SEC;
    printf("%zu Bytes ab $%04lX geladen, Start $%04lX\n", n, laden, start);
    printf("steht bei PC=$%04X nach %llu Befehlen und %llu Zyklen (%.2f s, %.0f MHz)%s\n", C.pc,
           (unsigned long long)befehle, (unsigned long long)C.z, sek, sek > 0 ? C.z / sek / 1e6 : 0.0,
           C.jam ? " - JAM" : "");
    int gut = 1;
    if (erfolg >= 0) {
        gut = C.pc == erfolg;
        printf("Erfolgsadresse $%04lX: %s\n", erfolg, gut ? "erreicht" : "NICHT erreicht");
    }
    if (fehlerbyte >= 0) {
        int g = M.ram[fehlerbyte] == 0;
        printf("Fehlerbyte $%04lX = $%02X: %s\n", fehlerbyte, M.ram[fehlerbyte], g ? "bestanden" : "FEHLER");
        gut = gut && g;
    }
    return gut ? 0 : 1;
}

/* ================================================================ main */

static void aufruf(void)
{
    fprintf(stderr,
            "Aufruf: sidkern DATEI.sid [-s LIED] [-t SEK] [--ab SEK] [-o AUS.sje]\n"
            "                [--model 6581|8580] [--pal|--ntsc] [--text] [--info] [--stat]\n"
            "        sidkern --cputest DATEI.bin [--laden ADR] [--start ADR] [--erfolg ADR] [--fehlerbyte ADR]\n");
    exit(1);
}

static long zahl(const char *s)
{
    char *e;
    long v = (*s == '$') ? strtol(s + 1, &e, 16) : strtol(s, &e, 0);
    if (*e) aufruf();
    return v;
}

static double sekunden(const char *s)
{
    char *e;
    double v = strtod(s, &e);
    if (*e || v < 0 || v > 1e6) aufruf();
    return v;
}

int main(int argc, char **argv)
{
    const char *datei = NULL, *ausdatei = NULL, *modell = NULL;
    double t_sek = 600, ab_sek = 0;
    int ab_gesetzt = 0, info = 0, stat = 0, uhr_zwang = 0;  /* 1 PAL, 2 NTSC */
    long lied_wunsch = 0;
    const char *cputest = NULL;
    long laden = 0, start = 0x400, erfolg = -1, fehlerbyte = -1;

    for (int i = 1; i < argc; i++) {
        const char *a = argv[i];
        int weiter = i + 1 < argc;
        if (!strcmp(a, "-s") && weiter) lied_wunsch = zahl(argv[++i]);
        else if (!strcmp(a, "-t") && weiter) t_sek = sekunden(argv[++i]);
        else if (!strcmp(a, "--ab") && weiter) { ab_sek = sekunden(argv[++i]); ab_gesetzt = 1; }
        else if (!strcmp(a, "-o") && weiter) ausdatei = argv[++i];
        else if (!strcmp(a, "--model") && weiter) modell = argv[++i];
        else if (!strcmp(a, "--pal")) uhr_zwang = 1;
        else if (!strcmp(a, "--ntsc")) uhr_zwang = 2;
        else if (!strcmp(a, "--text")) text_modus = 1;
        else if (!strcmp(a, "--info")) info = 1;
        else if (!strcmp(a, "--stat")) stat = 1;
        else if (!strcmp(a, "--spur") && weiter) spur_rest = zahl(argv[++i]);
        else if (!strcmp(a, "--cputest") && weiter) cputest = argv[++i];
        else if (!strcmp(a, "--laden") && weiter) laden = zahl(argv[++i]) & 0xFFFF;
        else if (!strcmp(a, "--start") && weiter) start = zahl(argv[++i]) & 0xFFFF;
        else if (!strcmp(a, "--erfolg") && weiter) erfolg = zahl(argv[++i]) & 0xFFFF;
        else if (!strcmp(a, "--fehlerbyte") && weiter) fehlerbyte = zahl(argv[++i]) & 0xFFFF;
        else if (a[0] == '-' || datei) aufruf();
        else datei = a;
    }
    if (cputest) return cpu_test(cputest, laden, start, erfolg, fehlerbyte);
    if (!datei) aufruf();
    if (modell && strcmp(modell, "6581") && strcmp(modell, "8580")) aufruf();

    /* Datei lesen */
    FILE *f = fopen(datei, "rb");
    if (!f) { fprintf(stderr, "sidkern: %s: %s\n", datei, strerror(errno)); return 1; }
    static uint8_t inhalt[0x20000];
    size_t groesse = fread(inhalt, 1, sizeof inhalt, f);
    fclose(f);
    const char *fehler = NULL;
    if (sid_kopf_lesen(inhalt, groesse, &K, &fehler)) {
        fprintf(stderr, "sidkern: %s: %s\n", datei, fehler);
        return 2;
    }
    lied = lied_wunsch ? (int)lied_wunsch : K.start_song;
    if (lied < 1 || lied > K.songs) {
        fprintf(stderr, "sidkern: Lied %d gibt es nicht (1-%d)\n", lied, K.songs);
        return 1;
    }
    int uhr = sid_kopf_uhr(&K);
    ntsc = uhr_zwang ? uhr_zwang == 2 : uhr == 2;
    int m8580 = modell ? !strcmp(modell, "8580") : sid_kopf_modell(&K) == 2;
    modell8580 = m8580;
    cia_tempo = sid_tempo_cia(&K, lied);
    uint32_t zps = ntsc ? ZPS_NTSC : ZPS_PAL;
    start_zyklus = ab_gesetzt ? (uint64_t)(ab_sek * zps + 0.5) : 0;
    ende_zyklus = (uint64_t)(t_sek * zps + 0.5);
    if (ende_zyklus < start_zyklus) ende_zyklus = start_zyklus;

    SpielInfo si = { lied, ntsc, m8580, cia_tempo, start_zyklus };
    char kopf[2048];
    size_t kopf_n = json_kopf(&K, &si, kopf, sizeof kopf);
    if (kopf_n >= sizeof kopf) kopf_n = sizeof kopf - 1;

    signal(SIGPIPE, SIG_IGN);
    aus = stdout;
    if (ausdatei && !info) {
        aus = fopen(ausdatei, "wb");
        if (!aus) { fprintf(stderr, "sidkern: %s: %s\n", ausdatei, strerror(errno)); return 1; }
    }
    setvbuf(aus, NULL, _IOFBF, sizeof puffer);

    if (info) {
        raus(kopf, kopf_n);
        raus("\n", 1);
        spuelen();
        return K.basic ? 3 : 0;
    }
    if (text_modus) {
        raus("# ", 2);
        raus(kopf, kopf_n);
        raus("\n", 1);
    } else {
        uint8_t vor[6] = { 'S', 'J', 'E', '1', (uint8_t)kopf_n, (uint8_t)(kopf_n >> 8) };
        raus(vor, 6);
        raus(kopf, kopf_n);
    }
    letzter_zyklus = start_zyklus;
    abbild_noetig = ab_gesetzt;

    if (K.basic) {                          /* BASIC-Lied: nur die Ende-Marke */
        abbild_noetig = 0;
        strom_beenden(start_zyklus);
        if (aus != stdout) fclose(aus);
        return 3;
    }

    clock_t t0 = clock();
    umgebung_einrichten();
    int jam = 0;
    while (C.z < ende_zyklus) {
        int g = cpu_lauf(ende_zyklus);
        if (g == GRUND_JAM) { jam = 1; break; }
        if (g == GRUND_FANG) fang_bearbeiten();
        else if (g == GRUND_PSID_IRQ) psid_play_rufen();
    }
    uint64_t schluss = ende_zyklus;
    if (jam) schluss = C.z < start_zyklus ? start_zyklus : C.z;
    strom_beenden(schluss);
    if (aus != stdout && fclose(aus) != 0) schreibfehler();

    if (stat) {
        double sek = (double)(clock() - t0) / CLOCKS_PER_SEC;
        fprintf(stderr, "sidkern: %llu Schreibzugriffe, Ende bei Zyklus %llu (%.1f s Lied)%s, init %s, %llu play-Aufrufe, "
                "%.4f s Rechenzeit (%.0fx Echtzeit), %llu OSC3/ENV3-Lesungen\n",
                (unsigned long long)anzahl_schreib, (unsigned long long)schluss, (double)schluss / zps,
                jam ? " - JAM" : "", init_zurueck == NIE ? "kehrt nicht zurueck" : "zurueck",
                (unsigned long long)play_aufrufe, sek, sek > 0 ? ((double)C.z / zps) / sek : 0.0,
                (unsigned long long)M.osz_lesungen);
    }
    return 0;
}
