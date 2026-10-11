/*
 * sidkern - SID-Registerstrom aus .sid-Dateien (Teil von SID JAM)
 * Copyright (c) 2026 retro-modern.net. GPL-3.0-or-later.
 *
 * Die C64-Umgebung ohne CPU: Speicher mit Prozessorport und Banking,
 * Ersatz-KERNAL, CIA 1/2 (Timer, ICR), VIC-II (Rasterzaehler, Raster-
 * Interrupt und Badlines, keine Sprites), SID (Schreibzugriffe mitschneiden,
 * OSC3/ENV3 naeherungsweise).
 *
 * Alle Geraete werden "faul" gefuehrt: sie rechnen ihren Zustand erst nach,
 * wenn jemand zugreift oder wenn ein vorausberechnetes Ereignis (Unterlauf,
 * Rasterzeile) faellig ist. So kostet ein laufender Timer nichts.
 */
#include <string.h>
#include "kern.h"

Maschine M;

static uint64_t min64(uint64_t a, uint64_t b) { return a < b ? a : b; }

/* ===================================================== Ersatz-KERNAL */

static uint8_t *k_ziel;

static void k_setzen(uint16_t adr, const uint8_t *b, size_t n)
{
    memcpy(&k_ziel[adr - 0xE000], b, n);
}

/* Ein eigenes, kleines KERNAL (die echten ROMs haben wir nicht). Es gibt
 * zwei Ansichten: was die CPU als Befehl holt (ueberall RTS, damit ein JSR in
 * eine fehlende Routine sofort zurueckkehrt) und was sie als Daten liest
 * (ueberall $EA wie bei sidplayfp ohne ROM - manche Stuecke lesen ROM-Bytes). */
static void kernal_bauen(uint8_t *ziel, uint8_t fuell)
{
    k_ziel = ziel;
    memset(ziel, fuell, 0x2000);

    /* IRQ-Ende ab $EA31: gleich weiter zu $EA7E. Dazwischen NOPs, damit
     * auch ein Sprung mitten hinein (JMP $EA34 o. ae.) dort ankommt. */
    memset(&ziel[0xEA31 - 0xE000], 0xEA, 0xEA7E - 0xEA31);
    static const uint8_t ea31[] = { 0x4C, 0x7E, 0xEA };                 /* JMP $EA7E */
    k_setzen(0xEA31, ea31, sizeof ea31);
    static const uint8_t ea7e[] = {
        0xAD, 0x0D, 0xDC,                   /* $EA7E LDA $DC0D  CIA 1 quittieren */
        0x68, 0xA8, 0x68, 0xAA, 0x68,       /* $EA81 PLA TAY PLA TAX PLA */
        0x40                                /*       RTI */
    };
    k_setzen(0xEA7E, ea7e, sizeof ea7e);

    /* NMI: $FE43 SEI, JMP ($0318); Vorgabe $FE47 rettet die Register,
     * quittiert CIA 2 und springt nach $FEBC. Zwischen $FE52 und $FEBB
     * NOPs (BRK-Vorgabe $FE66 rutscht so ebenfalls nach $FEBC). */
    static const uint8_t fe43[] = { 0x78, 0x6C, 0x18, 0x03 };
    k_setzen(0xFE43, fe43, sizeof fe43);
    memset(&ziel[0xFE47 - 0xE000], 0xEA, 0xFEBC - 0xFE47);
    static const uint8_t fe47[] = {
        0x48, 0x8A, 0x48, 0x98, 0x48,       /* PHA TXA PHA TYA PHA */
        0xAD, 0x0D, 0xDD,                   /* LDA $DD0D */
        0x4C, 0xBC, 0xFE                    /* JMP $FEBC */
    };
    k_setzen(0xFE47, fe47, sizeof fe47);
    static const uint8_t febc[] = { 0x68, 0xA8, 0x68, 0xAA, 0x68, 0x40 };
    k_setzen(0xFEBC, febc, sizeof febc);

    /* IRQ/BRK-Einsprung $FF48: Register retten, B-Bit pruefen, ueber
     * $0316 (BRK) oder $0314 (IRQ) weiter. */
    static const uint8_t ff48[] = {
        0x48, 0x8A, 0x48, 0x98, 0x48,       /* PHA TXA PHA TYA PHA */
        0xBA,                               /* TSX */
        0xBD, 0x04, 0x01,                   /* LDA $0104,X */
        0x29, 0x10,                         /* AND #$10 */
        0xF0, 0x03,                         /* BEQ +3 */
        0x6C, 0x16, 0x03,                   /* JMP ($0316) */
        0x6C, 0x14, 0x03                    /* JMP ($0314) */
    };
    k_setzen(0xFF48, ff48, sizeof ff48);

    /* Sprungleiste $FF81-$FFF3: RTS */
    for (unsigned a = 0xFF81; a <= 0xFFF3; a += 3) ziel[a - 0xE000] = 0x60;

    /* Reset: CPU anhalten (Strom endet) */
    ziel[0xFCE2 - 0xE000] = 0x02;

    static const uint8_t vektoren[] = { 0x43, 0xFE, 0xE2, 0xFC, 0x48, 0xFF };
    k_setzen(0xFFFA, vektoren, sizeof vektoren);
}

/* ======================================================= Speicherbild */

void speicher_abbilden(void)
{
    int s;
    if (M.flach) {
        for (s = 0; s < 256; s++) {
            M.lese[s] = M.befehl[s] = &M.ram[s << 8];
            M.schreibe[s] = &M.ram[s << 8];
        }
        return;
    }
    int pins = (M.port_daten | (uint8_t)~M.port_ddr) & 7;
    M.bankmodus = (uint8_t)pins;
    int basic = (pins & 3) == 3;
    int kernal = (pins & 2) != 0;
    int io = (pins & 3) && (pins & 4);
    int zeichen = (pins & 3) && !(pins & 4);

    for (s = 0; s < 256; s++) {
        M.lese[s] = &M.ram[s << 8];
        M.schreibe[s] = &M.ram[s << 8];
    }
    /* Seite 0: Prozessorport $00/$01 */
    M.lese[0] = NULL;
    M.schreibe[0] = NULL;
    if (basic)
        for (s = 0xA0; s < 0xC0; s++) M.lese[s] = &M.basic[(s - 0xA0) << 8];
    if (io)
        for (s = 0xD0; s < 0xE0; s++) { M.lese[s] = NULL; M.schreibe[s] = NULL; }
    else if (zeichen)
        for (s = 0xD0; s < 0xE0; s++) M.lese[s] = &M.zeichen[(s - 0xD0) << 8];
    if (kernal)
        for (s = 0xE0; s < 0x100; s++) M.lese[s] = &M.kernal[(s - 0xE0) << 8];
    /* Befehle holen: wie Lesen, nur im ROM die Befehlsansicht */
    for (s = 0; s < 256; s++) M.befehl[s] = M.lese[s];
    if (basic)
        for (s = 0xA0; s < 0xC0; s++) M.befehl[s] = &M.basic_befehl[(s - 0xA0) << 8];
    if (kernal)
        for (s = 0xE0; s < 0x100; s++) M.befehl[s] = &M.kernal_befehl[(s - 0xE0) << 8];
}

uint8_t port_lesen(uint16_t adr)
{
    if (M.flach) return M.ram[adr];
    if (adr == 0) return M.port_ddr;
    /* Eingaenge: Bit 0-2 und 4 hochgezogen */
    return (uint8_t)((M.port_daten & M.port_ddr) | (~M.port_ddr & 0x17));
}

void port_schreiben(uint16_t adr, uint8_t wert)
{
    M.ram[adr] = wert;
    if (M.flach) return;
    if (adr == 0) M.port_ddr = wert;
    else M.port_daten = wert;
    int pins = (M.port_daten | (uint8_t)~M.port_ddr) & 7;
    if (pins != M.bankmodus) speicher_abbilden();
}

/* ================================================================ CIA */
/*
 * Zeitverhalten wie beim alten 6526 (so wie es auch libsidplayfp/VICE
 * nachbilden):
 *  - Zaehlerstand 'wert' gilt ab Zyklus 'stand'; der erste Abzug kommt im
 *    Zyklus danach. Erreicht der Zaehler 0, ist im selben Zyklus der Unterlauf
 *    (Flag im ICR sichtbar), der Zaehler wird neu geladen und setzt einen Takt
 *    aus: Periode = latch + 1.
 *  - START schreiben im Zyklus t: erster Abzug bei t+3; mit Force-Load bei t+4.
 *    Anhalten: noch zwei Abzuege (t+1, t+2).
 *  - Der Interrupt-Ausgang geht einen Takt nach dem Unterlauf an, es sei denn,
 *    das ICR wurde genau im Unterlauf-Takt gelesen.
 */

static int ta_laeuft(const Cia *c) { return (c->ta.cr & 0x21) == 0x01; }

/* 0 = steht, 1 = zaehlt Takte, 2 = zaehlt Unterlaeufe von Timer A */
static int tb_modus(const Cia *c)
{
    if (!(c->tb.cr & 1)) return 0;
    switch ((c->tb.cr >> 5) & 3) {
    case 0: return 1;
    case 1: return 0;           /* CNT-Flanken: es gibt keine */
    default: return 2;          /* CNT ist in Ruhe hoch, also auch bei 3 */
    }
}

/* Timer bis 'bis' weiterzaehlen; Zahl der Unterlaeufe, *erster = Zyklus des ersten */
static uint64_t timer_takte(CiaTimer *t, uint64_t bis, uint64_t *erster)
{
    if (bis <= t->stand) return 0;
    uint64_t u1 = t->stand + t->wert;
    if (bis < u1) {
        t->wert -= (uint16_t)(bis - t->stand);
        t->stand = bis;
        return 0;
    }
    *erster = u1;
    uint64_t n = 1, un = u1;
    if (t->cr & 0x08) {                     /* Einmal: anhalten */
        t->cr &= (uint8_t)~1;
    } else {
        uint64_t periode = (uint64_t)t->latch + 1;
        n += (bis - u1) / periode;
        un = u1 + (n - 1) * periode;
    }
    t->wert = t->latch;                     /* neu geladen, ein Takt Pause */
    t->stand = un + 1;
    if ((t->cr & 1) && bis > t->stand) {
        t->wert -= (uint16_t)(bis - t->stand);
        t->stand = bis;
    }
    return n;
}

/* Timer B im Modus "zaehlt Unterlaeufe von A": n Schritte. Der Unterlauf
 * kommt mit dem Schritt, der den Zaehler schon auf 0 antrifft (Periode latch+1);
 * *index = Nummer dieses Schritts. */
static uint64_t timer_zaehlen(CiaTimer *t, uint64_t n, uint64_t *index)
{
    uint64_t k = (uint64_t)t->wert + 1;
    if (n < k) { t->wert -= (uint16_t)n; return 0; }
    *index = k;
    if (t->cr & 0x08) { t->wert = t->latch; t->cr &= (uint8_t)~1; return 1; }
    uint64_t periode = (uint64_t)t->latch + 1;
    uint64_t rest = n - k;
    t->wert = (uint16_t)(t->latch - rest % periode);
    return 1 + rest / periode;
}

static void cia_aufholen(Cia *c, uint64_t bis)
{
    uint64_t na = 0, nb = 0, ua = NIE, ub = NIE;
    uint16_t ta_latch = c->ta.latch;
    int ta_einmal = (c->ta.cr & 0x08) != 0;
    if (ta_laeuft(c)) na = timer_takte(&c->ta, bis, &ua);
    else if (c->ta.stand < bis) c->ta.stand = bis;
    int mb = tb_modus(c);
    if (mb == 1) nb = timer_takte(&c->tb, bis, &ub);
    else {
        if (mb == 2 && na) {
            uint64_t k = 0;
            nb = timer_zaehlen(&c->tb, na, &k);
            if (nb) ub = (ta_einmal ? ua : ua + (k - 1) * ((uint64_t)ta_latch + 1)) + 1;
        }
        if (c->tb.stand < bis) c->tb.stand = bis;
    }
    if (na) c->icr_daten |= 1;
    if (nb) c->icr_daten |= 2;
    if (!c->irq) {
        uint64_t t = NIE;
        if (na && (c->icr_maske & 1)) t = ua;
        if (nb && (c->icr_maske & 2)) t = min64(t, ub);
        if (t != NIE) c->irq_kommt = min64(c->irq_kommt, t + 1);
        if (c->irq_kommt <= bis) {
            c->irq = 1;
            c->irq_ab = c->irq_kommt;
            c->irq_kommt = NIE;
        }
    }
}

/* Zeitpunkt, an dem diese CIA ihren Interrupt-Ausgang setzen wird */
static uint64_t cia_naechstes(const Cia *c)
{
    if (c->irq) return NIE;
    uint64_t n = c->irq_kommt;
    if ((c->icr_maske & 1) && ta_laeuft(c))
        n = min64(n, c->ta.stand + c->ta.wert + 1);
    if (c->icr_maske & 2) {
        int mb = tb_modus(c);
        if (mb == 1) n = min64(n, c->tb.stand + c->tb.wert + 1);
        else if (mb == 2 && ta_laeuft(c)) {
            uint64_t ta1 = c->ta.stand + c->ta.wert;
            uint64_t k = (uint64_t)c->tb.wert + 1;
            if (c->ta.cr & 0x08) { if (k == 1) n = min64(n, ta1 + 2); }
            else n = min64(n, ta1 + (k - 1) * ((uint64_t)c->ta.latch + 1) + 2);
        }
    }
    return n;
}

static uint8_t bcd(unsigned v) { return (uint8_t)(((v / 10) << 4) | (v % 10)); }

static uint8_t cia_lesen(Cia *c, int reg, uint64_t zyk)
{
    cia_aufholen(c, zyk);
    switch (reg) {
    case 0x0: return (uint8_t)((c->pra & c->ddra) | ~c->ddra);   /* keine Taste, kein Joystick */
    case 0x1: return (uint8_t)((c->prb & c->ddrb) | ~c->ddrb);
    case 0x2: return c->ddra;
    case 0x3: return c->ddrb;
    case 0x4: return (uint8_t)c->ta.wert;
    case 0x5: return (uint8_t)(c->ta.wert >> 8);
    case 0x6: return (uint8_t)c->tb.wert;
    case 0x7: return (uint8_t)(c->tb.wert >> 8);
    case 0x8: case 0x9: case 0xA: case 0xB: {
        /* Uhrzeit: laeuft ab 1:00:00.0 mit dem Systemtakt */
        uint64_t zehntel = zyk * 10 / M.zps;
        switch (reg) {
        case 0x8: return (uint8_t)(zehntel % 10);
        case 0x9: return bcd((unsigned)((zehntel / 10) % 60));
        case 0xA: return bcd((unsigned)((zehntel / 600) % 60));
        default: { unsigned h = (unsigned)((zehntel / 36000 + 1) % 12); return bcd(h ? h : 12); }
        }
    }
    case 0xC: return c->sdr;
    case 0xD: {
        uint8_t v = (uint8_t)(c->icr_daten | (c->irq ? 0x80 : 0));
        c->icr_daten = 0;
        c->irq = 0;
        c->irq_kommt = NIE;     /* Unterlauf genau jetzt: Ausgang bleibt aus */
        c->gelesen = zyk;
        return v;
    }
    case 0xE: return c->ta.cr;
    default:  return c->tb.cr;
    }
}

static void cia_steuern(Cia *c, CiaTimer *t, uint8_t wert, uint64_t zyk)
{
    int war_an = t->cr & 1;
    if (war_an && !(wert & 1)) {
        /* anhalten: zwei Abzuege kommen noch */
        uint64_t u = NIE;
        uint8_t bit = (t == &c->ta) ? 1 : 2;
        if (timer_takte(t, zyk + 2, &u)) {
            c->icr_daten |= bit;
            if (!c->irq && (c->icr_maske & bit)) c->irq_kommt = min64(c->irq_kommt, u + 1);
        }
    }
    if (wert & 0x10) { t->wert = t->latch; t->stand = zyk + 3; }
    else if (!war_an && (wert & 1)) t->stand = zyk + 2;
    t->cr = wert & (uint8_t)~0x10;
}

static void cia_schreiben(Cia *c, int reg, uint8_t wert, uint64_t zyk)
{
    cia_aufholen(c, zyk);
    switch (reg) {
    case 0x0: c->pra = wert; break;
    case 0x1: c->prb = wert; break;
    case 0x2: c->ddra = wert; break;
    case 0x3: c->ddrb = wert; break;
    case 0x4: c->ta.latch = (uint16_t)((c->ta.latch & 0xFF00) | wert); break;
    case 0x5:
        c->ta.latch = (uint16_t)((c->ta.latch & 0x00FF) | (wert << 8));
        if (!(c->ta.cr & 1)) c->ta.wert = c->ta.latch;
        break;
    case 0x6: c->tb.latch = (uint16_t)((c->tb.latch & 0xFF00) | wert); break;
    case 0x7:
        c->tb.latch = (uint16_t)((c->tb.latch & 0x00FF) | (wert << 8));
        if (!(c->tb.cr & 1)) c->tb.wert = c->tb.latch;
        break;
    case 0x8: case 0x9: case 0xA: case 0xB: break;   /* Uhr stellen: egal */
    case 0xC: c->sdr = wert; break;
    case 0xD:
        if (wert & 0x80) c->icr_maske |= wert & 0x1F;
        else c->icr_maske &= (uint8_t)~(wert & 0x1F);
        /* anstehendes Flag neu freigegeben: Ausgang einen Takt spaeter
         * (nicht, wenn das ICR im Takt davor gelesen wurde) */
        if (!c->irq && (c->icr_daten & c->icr_maske & 0x1F) && c->gelesen + 1 != zyk)
            c->irq_kommt = min64(c->irq_kommt, zyk + 1);
        break;
    case 0xE: cia_steuern(c, &c->ta, wert, zyk); break;
    default:  cia_steuern(c, &c->tb, wert, zyk); break;
    }
}

void cia_einrichten(Cia *c, uint16_t ta_latch, int ta_an, uint8_t maske)
{
    memset(c, 0, sizeof *c);
    c->ta.latch = c->ta.wert = ta_latch;
    c->ta.cr = ta_an ? 1 : 0;
    c->tb.latch = c->tb.wert = 0xFFFF;
    c->icr_maske = maske & 0x1F;
    c->irq_kommt = NIE;
    c->gelesen = NIE - 1;
}

/* ================================================================ VIC */

static uint32_t vic_zeile(uint64_t zyk)
{
    return (uint32_t)(((zyk + M.vic.versatz) / M.vic.zpz) % M.vic.zeilen);
}

static void vic_planen(uint64_t zyk)
{
    Vic *v = &M.vic;
    if (v->vergleich >= v->zeilen) { v->naechster = NIE; return; }
    uint64_t bild = (uint64_t)v->zeilen * v->zpz;
    uint64_t pos = (zyk + v->versatz) % bild;
    uint64_t ziel = (uint64_t)v->vergleich * v->zpz + (v->vergleich == 0 ? 1 : 0);
    uint64_t delta = ziel > pos ? ziel - pos : ziel + bild - pos;
    v->naechster = zyk + delta;
}

static void vic_irq_neu(uint64_t ab)
{
    Vic *v = &M.vic;
    uint8_t neu = (v->latch & v->maske & 0x0F) != 0;
    if (neu && !v->irq) v->irq_ab = ab;
    v->irq = neu;
}

static void vic_aufholen(uint64_t bis)
{
    Vic *v = &M.vic;
    if (v->naechster <= bis) {
        uint64_t bild = (uint64_t)v->zeilen * v->zpz;
        uint64_t erster = v->naechster;
        v->latch |= 1;
        v->naechster += ((bis - v->naechster) / bild + 1) * bild;
        vic_irq_neu(erster);
    }
}

static void vic_vergleich_setzen(uint16_t neu, uint64_t zyk)
{
    Vic *v = &M.vic;
    if (neu == v->vergleich) return;
    v->vergleich = neu;
    /* Wird die laufende Zeile eingestellt, loest der VIC sofort aus */
    if (vic_zeile(zyk) == neu) v->latch |= 1;
    vic_planen(zyk);
}

/* Badlines: in den Zeilen $30-$F7, deren untere drei Bits gleich YSCROLL sind,
 * holt der VIC bei eingeschaltetem Bild (DEN) 40 Zeichen und haelt die CPU an.
 * BA geht im Zeilentakt 12 (Zaehlung 1-63) auf low; ab da wartet jeder
 * Lesetakt der CPU bis Takt 55. Hier: Zeilentakt 0 = Takt 1, also Fenster
 * 11..53, weiter bei 54. */
#define KLAU_AB  11
#define KLAU_BIS 54

void klau_planen(uint64_t zyk)
{
    Vic *v = &M.vic;
    if (!M.badlines || M.flach) { M.klau_ab = M.klau_bis = NIE; return; }
    int64_t bild = (int64_t)v->zeilen * v->zpz;
    uint64_t bild_nr = (zyk + v->versatz) / (uint64_t)bild;
    int64_t pos = (int64_t)((zyk + v->versatz) % (uint64_t)bild);
    int64_t basis = (int64_t)zyk - pos;         /* Bildanfang (darf vor Zyklus 0 liegen) */
    uint32_t ys = v->reg[0x11] & 7;
    uint32_t zeile = (uint32_t)(pos / v->zpz);
    for (int runde = 0; runde < 2; runde++) {
        /* DEN zaehlt so, wie es in Zeile $30 dieses Bildes stand */
        int den = (v->den_bild_nr == bild_nr + runde) ? v->den_bild : (v->reg[0x11] & 0x10) != 0;
        if (!den) { basis += bild; zeile = 0; continue; }
        /* erste Badline-Zeile >= zeile in diesem Bild */
        uint32_t l = zeile < 0x30 ? 0x30 : zeile;
        l += (ys - (l & 7)) & 7;
        for (; l <= 0xF7; l += 8) {
            int64_t ab = basis + (int64_t)l * v->zpz + KLAU_AB;
            int64_t bis = basis + (int64_t)l * v->zpz + KLAU_BIS;
            if (bis > (int64_t)zyk) {
                M.klau_ab = ab < 0 ? 0 : (uint64_t)ab;
                M.klau_bis = (uint64_t)bis;
                return;
            }
        }
        basis += bild;
        zeile = 0;
    }
    M.klau_ab = M.klau_bis = NIE;
}

static uint8_t vic_lesen(int reg, uint64_t zyk)
{
    Vic *v = &M.vic;
    vic_aufholen(zyk);
    uint32_t zeile = vic_zeile(zyk);
    switch (reg) {
    case 0x11: return (uint8_t)((v->reg[0x11] & 0x7F) | ((zeile & 0x100) >> 1));
    case 0x12: return (uint8_t)zeile;
    case 0x13: case 0x14: return 0;
    case 0x16: return v->reg[0x16] | 0xC0;
    case 0x18: return v->reg[0x18] | 0x01;
    case 0x19: return (uint8_t)(v->latch | 0x70 | (v->irq ? 0x80 : 0));
    case 0x1A: return v->maske | 0xF0;
    case 0x1E: case 0x1F: return 0;
    default:
        if (reg >= 0x2F) return 0xFF;
        if (reg >= 0x20) return v->reg[reg] | 0xF0;
        return v->reg[reg];
    }
}

static void vic_schreiben(int reg, uint8_t wert, uint64_t zyk)
{
    Vic *v = &M.vic;
    vic_aufholen(zyk);
    uint8_t alt11 = v->reg[0x11];
    v->reg[reg] = wert;
    switch (reg) {
    case 0x11: {
        vic_vergleich_setzen((uint16_t)((v->vergleich & 0xFF) | ((wert & 0x80) << 1)), zyk);
        /* DEN wirkt erst ab Zeile $30: spaeter im Bild geaendert, bleibt das
         * laufende Bild, wie es war (in Zeile $30 genuegt ein Takt mit DEN) */
        uint64_t bild = (uint64_t)v->zeilen * v->zpz;
        uint64_t nr = (zyk + v->versatz) / bild;
        uint32_t zeile = vic_zeile(zyk);
        int den_alt = (v->den_bild_nr == nr) ? v->den_bild : (alt11 & 0x10) != 0;
        if (zeile > 0x30) { v->den_bild = (uint8_t)den_alt; v->den_bild_nr = nr; }
        else if (zeile == 0x30) { v->den_bild = (uint8_t)(den_alt | ((wert & 0x10) != 0)); v->den_bild_nr = nr; }
        else v->den_bild_nr = NIE;
        klau_planen(zyk);
        break;
    }
    case 0x12: vic_vergleich_setzen((uint16_t)((v->vergleich & 0x100) | wert), zyk); break;
    case 0x19: v->latch &= (uint8_t)~wert & 0x0F; break;
    case 0x1A: v->maske = wert & 0x0F; break;
    }
    vic_irq_neu(zyk);
}

void vic_einrichten(uint8_t d011, uint8_t d012, uint8_t d01a)
{
    Vic *v = &M.vic;
    v->reg[0x11] = d011;
    v->reg[0x12] = d012;
    v->vergleich = (uint16_t)(d012 | ((d011 & 0x80) << 1));
    v->maske = d01a & 0x0F;
    v->reg[0x1A] = d01a;
    v->latch = 0;
    vic_planen(0);
    klau_planen(0);
    ereignisse(0);
}

/* ================================================================ SID */

/* Schritte des Huellkurvenzaehlers (Takte je Stufe) fuer die Raten 0-15 */
static const uint16_t ADSR_TAKTE[16] = {
    9, 32, 63, 95, 149, 220, 267, 313, 392, 977, 1954, 3126, 3907, 11720, 19532, 31251
};

static uint32_t exp_faktor(uint8_t pegel)
{
    if (pegel > 93) return 1;
    if (pegel > 54) return 2;
    if (pegel > 26) return 4;
    if (pegel > 14) return 8;
    if (pegel > 6) return 16;
    return 30;
}

static void lfsr_schritt(Sid *s)
{
    uint32_t b = ((s->lfsr >> 22) ^ (s->lfsr >> 17)) & 1;
    s->lfsr = ((s->lfsr << 1) | b) & 0x7FFFFF;
}

static void osz_aufholen(Sid *s, uint64_t zyk)
{
    if (zyk <= s->osz_stand) return;
    uint64_t dt = zyk - s->osz_stand;
    s->osz_stand = zyk;
    if (s->reg[0x12] & 0x08) { s->akku = 0; s->lfsr = 0x7FFFFF; return; }
    uint64_t freq = s->reg[0x0E] | (s->reg[0x0F] << 8);
    if (!freq) return;
    uint64_t alt = s->akku;
    uint64_t neu = alt + freq * dt;
    /* Rauschen: ein Schritt je steigender Flanke von Bit 19 */
    uint64_t flanken = ((neu + 0x80000) >> 20) - ((alt + 0x80000) >> 20);
    flanken %= 0x7FFFFF;
    while (flanken--) lfsr_schritt(s);
    s->akku = (uint32_t)(neu & 0xFFFFFF);
}

static uint8_t osz3(Sid *s)
{
    uint8_t w = s->reg[0x12] >> 4;
    uint32_t a = s->akku;
    uint8_t v = 0xFF;
    if (!w) return 0;
    if (w & 1) { uint32_t t = (a & 0x800000) ? ~a : a; v &= (uint8_t)(t >> 15); }
    if (w & 2) v &= (uint8_t)(a >> 16);
    if (w & 4) {
        uint32_t pw = s->reg[0x10] | ((s->reg[0x11] & 0x0F) << 8);
        if (!((s->reg[0x12] & 0x08) || (a >> 12) >= pw)) v = 0;
    }
    if (w & 8) {
        uint32_t l = s->lfsr;
        v &= (uint8_t)(((l >> 15) & 0x80) | ((l >> 14) & 0x40) | ((l >> 11) & 0x20) | ((l >> 9) & 0x10) |
                       ((l >> 8) & 0x08) | ((l >> 5) & 0x04) | ((l >> 3) & 0x02) | ((l >> 2) & 0x01));
    }
    return v;
}

static void env_aufholen(Sid *s, uint64_t zyk)
{
    if (zyk <= s->env_stand) return;
    uint64_t dt = zyk - s->env_stand;
    s->env_stand = zyk;
    while (dt) {
        uint32_t periode;
        uint8_t ad = s->reg[0x13], sr = s->reg[0x14];
        if (s->phase == 0) {
            if (s->pegel == 0xFF) { s->phase = 1; continue; }
            periode = ADSR_TAKTE[ad >> 4];
        } else if (s->phase == 1) {
            if (s->pegel <= (sr >> 4) * 17) break;      /* Halten */
            periode = ADSR_TAKTE[ad & 15] * exp_faktor(s->pegel);
        } else {
            if (s->pegel == 0) break;
            periode = ADSR_TAKTE[sr & 15] * exp_faktor(s->pegel);
        }
        uint64_t braucht = s->env_zaehler >= periode ? 1 : periode - s->env_zaehler;
        if (dt < braucht) { s->env_zaehler += (uint32_t)dt; break; }
        dt -= braucht;
        s->env_zaehler = 0;
        if (s->phase == 0) { s->pegel++; if (s->pegel == 0xFF) s->phase = 1; }
        else s->pegel--;
    }
}

static int sid_chip(uint16_t adr)
{
    if (adr < 0xD400 || adr >= 0xE000) return -1;
    return M.sid_block[(adr - 0xD400) >> 5];
}

static uint8_t sid_lesen(uint16_t adr, uint64_t zyk)
{
    int chip = sid_chip(adr);
    if (chip < 0) return 0xFF;
    Sid *s = &M.sid[chip];
    uint8_t v;
    switch (adr & 0x1F) {
    case 0x19: case 0x1A: v = 0xFF; break;             /* keine Paddles */
    case 0x1B:
        M.osz_lesungen++;
        /* beim 6581 zeigt OSC3 den Stand vom Takt davor (bekannter Unterschied
         * zum 8580, mit dem manche Spieler das Modell erkennen) */
        osz_aufholen(s, M.bus_ttl == 7424 && zyk ? zyk - 1 : zyk);
        v = osz3(s);
        break;
    case 0x1C: M.osz_lesungen++; env_aufholen(s, zyk); v = s->pegel; break;
    default:
        /* nur beschreibbar: es kommt der letzte Buswert, solange er nicht
         * verblasst ist (Fred Gray z. B. setzt Gate mit INC $D40B) */
        return zyk - s->bus_zeit <= M.bus_ttl ? s->bus : 0;
    }
    s->bus = v;
    s->bus_zeit = zyk;
    return v;
}

static void sid_schreiben(uint16_t adr, uint8_t wert, uint64_t zyk)
{
    int chip = sid_chip(adr);
    if (chip < 0) return;
    Sid *s = &M.sid[chip];
    int reg = adr & 0x1F;
    s->bus = wert;
    s->bus_zeit = zyk;
    if (reg > 24) return;
    if (reg >= 0x0E && reg <= 0x14) {
        osz_aufholen(s, zyk);
        env_aufholen(s, zyk);
        if (reg == 0x12) {
            uint8_t alt = s->reg[0x12];
            if (!(alt & 1) && (wert & 1)) s->phase = 0;
            if ((alt & 1) && !(wert & 1)) s->phase = 2;
            if (wert & 0x08) { s->akku = 0; s->lfsr = 0x7FFFFF; }
        }
    }
    /* erst mitschneiden (ein Abbild davor zeigt noch den alten Stand) */
    if (M.sid_mitschnitt) M.sid_mitschnitt(zyk, chip, reg, wert);
    s->reg[reg] = wert;
}

void sid_einrichten(int chip, uint16_t basis)
{
    Sid *s = &M.sid[chip];
    memset(s, 0, sizeof *s);
    s->lfsr = 0x7FFFF8;
    if (chip == 0) {
        for (int b = 0; b < 32; b++) M.sid_block[b] = 0;     /* $D400-$D7FF gespiegelt */
    }
    if (basis >= 0xD400 && basis < 0xE000) M.sid_block[(basis - 0xD400) >> 5] = (int8_t)chip;
    if (chip + 1 > M.anzahl_sids) M.anzahl_sids = chip + 1;
}

/* ========================================================= Ereignisse */

static void interrupts_neu(void)
{
    M.irq = M.cia1.irq | M.vic.irq;
    if (M.irq) M.irq_ab = min64(M.cia1.irq ? M.cia1.irq_ab : NIE, M.vic.irq ? M.vic.irq_ab : NIE);
    uint8_t nmi = M.cia2.irq;
    if (nmi && !M.nmi_pegel) { M.nmi_flanke = 1; M.nmi_ab = M.cia2.irq_ab; }
    M.nmi_pegel = nmi;
}

void ereignisse_planen(void)
{
    uint64_t n = min64(cia_naechstes(&M.cia1), cia_naechstes(&M.cia2));
    if (!M.vic.irq && (M.vic.maske & 1)) n = min64(n, M.vic.naechster);
    M.naechstes = n;
}

void ereignisse(uint64_t zyk)
{
    if (M.flach) { M.naechstes = NIE; return; }
    cia_aufholen(&M.cia1, zyk);
    cia_aufholen(&M.cia2, zyk);
    vic_aufholen(zyk);
    interrupts_neu();
    ereignisse_planen();
}

/* ====================================================== Ein-/Ausgabe */

uint8_t io_lesen(uint16_t adr, uint64_t zyk)
{
    if (adr < 0x100) return adr < 2 ? port_lesen(adr) : M.ram[adr];
    if (adr < 0xD000 || adr >= 0xE000) return M.ram[adr];
    if (adr < 0xD400) {
        uint8_t v = vic_lesen(adr & 0x3F, zyk);
        interrupts_neu(); ereignisse_planen();
        return v;
    }
    if (adr < 0xD800) return sid_lesen(adr, zyk);
    if (adr < 0xDC00) return M.farbram[adr & 0x3FF];
    if (adr < 0xDE00) {
        Cia *c = adr < 0xDD00 ? &M.cia1 : &M.cia2;
        cia_aufholen(c, zyk);
        interrupts_neu();               /* eine NMI-Flanke zaehlt, auch wenn gleich quittiert wird */
        uint8_t v = cia_lesen(c, adr & 0x0F, zyk);
        interrupts_neu();
        ereignisse_planen();
        return v;
    }
    return sid_lesen(adr, zyk);     /* $DE00-$DFFF: zusaetzlicher SID oder offen */
}

void io_schreiben(uint16_t adr, uint8_t wert, uint64_t zyk)
{
    if (adr < 0x100) {
        if (adr < 2) port_schreiben(adr, wert);
        else M.ram[adr] = wert;
        return;
    }
    if (adr < 0xD000 || adr >= 0xE000) { M.ram[adr] = wert; return; }
    if (adr < 0xD400) {
        vic_schreiben(adr & 0x3F, wert, zyk);
    } else if (adr < 0xD800 || adr >= 0xDE00) {
        sid_schreiben(adr, wert, zyk);
        return;
    } else if (adr < 0xDC00) {
        M.farbram[adr & 0x3FF] = wert & 0x0F;
        return;
    } else {
        Cia *c = adr < 0xDD00 ? &M.cia1 : &M.cia2;
        cia_aufholen(c, zyk);
        interrupts_neu();
        cia_schreiben(c, adr & 0x0F, wert, zyk);
    }
    interrupts_neu();
    ereignisse_planen();
}

/* ============================================================ Anlegen */

void maschine_anlegen(int ntsc, int flach)
{
    memset(&M, 0, sizeof M);
    M.flach = flach;
    M.zps = ntsc ? ZPS_NTSC : ZPS_PAL;
    M.vic.zeilen = ntsc ? 263 : 312;
    M.vic.zpz = ntsc ? 65 : 63;
    /* Rasterstellung bei Zyklus 0 (Beginn von init): so wie bei sidplayfp
     * ohne Einschaltverzoegerung (PAL Zeile 169, NTSC Zeile 32) - dann
     * stimmen die Phasen von Raster-Interrupts mit der Referenz ueberein */
    M.vic.versatz = ntsc ? 2090 : 10672;
    M.vic.vergleich = 0x1FF;                /* aus, bis jemand einstellt */
    M.vic.naechster = NIE;
    M.vic.den_bild_nr = NIE;
    kernal_bauen(M.kernal, 0xEA);
    kernal_bauen(M.kernal_befehl, 0x60);
    /* BASIC fehlt: liest sich als 0 (wie bei sidplayfp), als Befehl RTS */
    memset(M.basic, 0x00, sizeof M.basic);
    memset(M.basic_befehl, 0x60, sizeof M.basic_befehl);
    memset(M.sid_block, -1, sizeof M.sid_block);
    M.port_ddr = 0x2F;
    M.port_daten = 0x37;
    M.ram[0] = 0x2F;
    M.ram[1] = 0x37;
    M.bankmodus = 0xFF;
    speicher_abbilden();
    cia_einrichten(&M.cia1, 0xFFFF, 0, 0);
    cia_einrichten(&M.cia2, 0xFFFF, 0, 0);
    sid_einrichten(0, 0xD400);
    M.anzahl_sids = 1;
    M.naechstes = flach ? NIE : 0;
    M.badlines = 1;
    M.bus_ttl = 7424;
    M.klau_ab = M.klau_bis = NIE;
}
