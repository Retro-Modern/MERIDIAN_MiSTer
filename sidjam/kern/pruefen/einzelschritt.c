/*
 * sidkern - Einzelschritt-Pruefung des CPU-Kerns
 * Copyright (c) 2026 retro-modern.net. GPL-3.0-or-later.
 *
 * Liest Testfaelle (umgewandelt aus den SingleStepTests/65x02, Satz 6502, mit
 * einzelschritt_wandeln.py) von stdin, fuehrt je Fall einen Befehl aus und
 * vergleicht Register, Speicher, Zyklenzahl und jeden echten Buszugriff
 * (Adresse, Wert, Lesen/Schreiben, Zyklus). Blindzugriffe macht der Kern nicht;
 * die werden nur ueber die Zyklenzahl geprueft.
 *
 * Bauen: siehe pruefen/pruefen.sh (mit -DSPION).
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "../kern.h"

typedef struct { uint16_t a; uint8_t v; int s; uint64_t z; } Zugriff;
static Zugriff spur[64];
static int n_spur;

void spion(uint16_t adr, uint8_t wert, uint64_t zyk, int schreib)
{
    if (n_spur < 64) { spur[n_spur].a = adr; spur[n_spur].v = wert; spur[n_spur].s = schreib; spur[n_spur].z = zyk; n_spur++; }
}

static long zahl(char **p)
{
    return strtol(*p, p, 10);
}

int main(int argc, char **argv)
{
    static char zeile[1 << 16];
    maschine_anlegen(0, 1);
    long faelle = 0, fehler_reg = 0, fehler_ram = 0, fehler_zyk = 0, fehler_bus = 0, gezeigt = 0;
    int zeigen = argc > 1 ? atoi(argv[1]) : 5;
    while (fgets(zeile, sizeof zeile, stdin)) {
        char *p = zeile;
        uint16_t ram_adr[64]; int n_ram = 0;
        /* Anfang */
        long pc = zahl(&p), s = zahl(&p), a = zahl(&p), x = zahl(&p), y = zahl(&p), pp = zahl(&p);
        long n = zahl(&p);
        for (long i = 0; i < n; i++) {
            long ad = zahl(&p), v = zahl(&p);
            M.ram[ad] = (uint8_t)v;
            if (n_ram < 64) ram_adr[n_ram++] = (uint16_t)ad;
        }
        /* Ziel */
        long epc = zahl(&p), es = zahl(&p), ea = zahl(&p), ex = zahl(&p), ey = zahl(&p), ep = zahl(&p);
        long en = zahl(&p);
        uint16_t e_adr[64]; uint8_t e_wert[64];
        for (long i = 0; i < en && i < 64; i++) { e_adr[i] = (uint16_t)zahl(&p); e_wert[i] = (uint8_t)zahl(&p); }
        long nz = zahl(&p);
        Zugriff erw[64];
        for (long i = 0; i < nz && i < 64; i++) {
            erw[i].a = (uint16_t)zahl(&p); erw[i].v = (uint8_t)zahl(&p); erw[i].s = (int)zahl(&p); erw[i].z = (uint64_t)i;
        }
        memset(&C, 0, sizeof C);
        C.pc = (uint16_t)pc; C.s = (uint8_t)s; C.a = (uint8_t)a; C.x = (uint8_t)x; C.y = (uint8_t)y;
        cpu_p_setzen((uint8_t)pp);
        C.i_pruef = 1;
        n_spur = 0;
        cpu_lauf(1);
        faelle++;

        int f_reg = C.pc != epc || C.s != es || C.a != ea || C.x != ex || C.y != ey || ((cpu_p(0) ^ ep) & 0xCF);
        int f_ram = 0;
        for (long i = 0; i < en && i < 64; i++) if (M.ram[e_adr[i]] != e_wert[i]) f_ram = 1;
        int f_zyk = (long)C.z != nz;
        int f_bus = 0;
        for (int i = 0; i < n_spur; i++) {
            uint64_t k = spur[i].z;
            if ((long)k >= nz || erw[k].a != spur[i].a || erw[k].v != spur[i].v || erw[k].s != spur[i].s) f_bus = 1;
        }
        for (long k = 0; k < nz && k < 64; k++) {
            if (!erw[k].s) continue;
            int da = 0;
            for (int i = 0; i < n_spur; i++) if (spur[i].s && spur[i].z == (uint64_t)k) da = 1;
            if (!da) f_bus = 1;
        }
        fehler_reg += f_reg; fehler_ram += f_ram; fehler_zyk += f_zyk; fehler_bus += f_bus;
        if ((f_reg || f_ram || f_zyk || f_bus) && gezeigt < zeigen) {
            gezeigt++;
            printf("Fehler Fall %ld: op %02X  reg%s ram%s zyk%s bus%s\n", faelle, M.ram[pc] , f_reg ? "!" : "", f_ram ? "!" : "",
                   f_zyk ? "!" : "", f_bus ? "!" : "");
            printf("  erwartet pc=%04lX s=%02lX a=%02lX x=%02lX y=%02lX p=%02lX zyk=%ld\n", epc, es, ea, ex, ey, ep, nz);
            printf("  ist      pc=%04X s=%02X a=%02X x=%02X y=%02X p=%02X zyk=%llu\n", C.pc, C.s, C.a, C.x, C.y,
                   cpu_p(0), (unsigned long long)C.z);
        }
        /* aufraeumen */
        for (int i = 0; i < n_ram; i++) M.ram[ram_adr[i]] = 0;
        for (long i = 0; i < en && i < 64; i++) M.ram[e_adr[i]] = 0;
        for (int i = 0; i < n_spur; i++) M.ram[spur[i].a] = 0;
    }
    printf("%ld Faelle: Register %ld, Speicher %ld, Zyklen %ld, Bus %ld fehlerhaft\n", faelle, fehler_reg, fehler_ram,
           fehler_zyk, fehler_bus);
    return (fehler_reg || fehler_ram || fehler_zyk || fehler_bus) ? 1 : 0;
}
