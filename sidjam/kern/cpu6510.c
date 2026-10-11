/*
 * sidkern - SID-Registerstrom aus .sid-Dateien (Teil von SID JAM)
 * Copyright (c) 2026 retro-modern.net. GPL-3.0-or-later.
 *
 * NMOS 6510 mit allen Befehlen (auch den undokumentierten). Jeder Buszugriff
 * und jeder interne Takt zaehlt einen Zyklus weiter; so stimmen die Zeiten
 * je Befehl (Seitenueberschreitung, Verzweigung) von selbst, und jeder
 * Schreibzugriff traegt den Zyklus, in dem er wirklich passiert (bei
 * Lesen-Aendern-Schreiben zweimal: erst der alte Wert, dann der neue).
 * Blindlesezugriffe (Folgebefehl, unfertige indizierte Adresse) gehen wirklich
 * auf den Bus, Ein-/Ausgabe merkt sie; nur die auf Stapel und Nullseite
 * zaehlen bloss den Takt. Jeder Lesetakt wartet in Badline-Fenstern.
 * Geprueft mit Klaus Dormanns Tests und den SingleStepTests (pruefen/).
 */
#include <stdio.h>
#include "kern.h"

Cpu C;

static uint64_t lauf_bis;

/* Befehlsspur fuer die Fehlersuche (sidkern --spur N) */
long spur_rest;
static void spur_zeile(void)
{
    spur_rest--;
    const uint8_t *s = M.befehl[C.pc >> 8];
    uint8_t b0 = s ? s[C.pc & 0xFF] : M.ram[C.pc];
    uint16_t p1 = (uint16_t)(C.pc + 1), p2 = (uint16_t)(C.pc + 2);
    const uint8_t *s1 = M.lese[p1 >> 8], *s2 = M.lese[p2 >> 8];
    fprintf(stderr, "%10llu %04X  %02X %02X %02X  A=%02X X=%02X Y=%02X S=%02X P=%02X $01=%02X\n",
            (unsigned long long)C.z, C.pc, b0, s1 ? s1[p1 & 0xFF] : M.ram[p1], s2 ? s2[p2 & 0xFF] : M.ram[p2],
            C.a, C.x, C.y, C.s, cpu_p(0), M.port_daten);
}

/* ------------------------------------------------------- Buszugriffe */
/* Lesetakt in einem Badline-Fenster: warten, bis der VIC den Bus freigibt */
static void klau(void)
{
    if (C.z >= M.klau_bis) klau_planen(C.z);
    if (C.z >= M.klau_ab && C.z < M.klau_bis) C.z = M.klau_bis;
}
#define LESETAKT() do { if (C.z >= M.klau_ab) klau(); } while (0)

static inline uint8_t LES(uint16_t a) { LESETAKT(); uint8_t v = lesen(a, C.z); C.z++; return v; }
static inline void SCHR(uint16_t a, uint8_t v) { schreiben(a, v, C.z); C.z++; }
static inline uint8_t HOL(void) { LESETAKT(); uint8_t v = lesen(C.pc, C.z); C.pc++; C.z++; return v; }
/* Befehl holen (im ROM aus der Befehlsansicht) */
static inline uint8_t HOL_BEFEHL(void)
{
    LESETAKT();
    const uint8_t *s = M.befehl[C.pc >> 8];
    uint8_t v = s ? s[C.pc & 0xFF] : io_lesen(C.pc, C.z);
    SPIONIEREN(C.pc, v, C.z, 0);
    C.pc++; C.z++;
    return v;
}
/* interner Takt: auf dem Bus ein Blindlesen ohne Wirkung (Stapel, Nullseite) */
static inline void TAKT(void) { LESETAKT(); C.z++; }
/* Blindlesen: der Wert zaehlt nicht, aber Ein-/Ausgabe merkt den Zugriff
 * (z. B. quittiert ein Blindlesen von $DD0D den NMI) */
static inline void BLIND(uint16_t a) { LESETAKT(); (void)lesen(a, C.z); C.z++; }
static inline uint8_t ZL(uint8_t a) { LESETAKT(); uint8_t v = zp_lesen(a); C.z++; return v; }
static inline void ZS(uint8_t a, uint8_t v) { zp_schreiben(a, v); C.z++; }
static inline void push(uint8_t v)
{
    SPIONIEREN(0x100 | C.s, v, C.z, 1);
    M.ram[0x100 | C.s] = v; C.s--; C.z++;
}
static inline uint8_t pull(void)
{
    LESETAKT();
    C.s++;
    SPIONIEREN(0x100 | C.s, M.ram[0x100 | C.s], C.z, 0);
    C.z++;
    return M.ram[0x100 | C.s];
}

/* Buszyklen ohne Wirkung verstreichen lassen (fuer den eingebauten
 * PSID-Treiber): 'R' = Lesetakt (wartet in Badlines), 'W' = Schreibtakt */
void cpu_buszyklen(const char *muster)
{
    for (; *muster; muster++) {
        if (*muster == 'R') LESETAKT();
        C.z++;
    }
}

uint8_t cpu_p(int b)
{
    return (uint8_t)((C.fn & 0x80) | (C.fv ? 0x40 : 0) | 0x20 | (b ? 0x10 : 0) |
                     (C.fd ? 0x08 : 0) | (C.fi ? 0x04 : 0) | (C.fz ? 0 : 0x02) | (C.fc ? 1 : 0));
}

void cpu_p_setzen(uint8_t p)
{
    C.fn = p;
    C.fv = (p >> 6) & 1;
    C.fd = (p >> 3) & 1;
    C.fi = (p >> 2) & 1;
    C.fz = !(p & 2);
    C.fc = p & 1;
}

/* ------------------------------------------------------- Adressierung */
static inline uint8_t a_zp(void)  { return HOL(); }
static inline uint8_t a_zpx(void) { uint8_t b = HOL(); TAKT(); return (uint8_t)(b + C.x); }
static inline uint8_t a_zpy(void) { uint8_t b = HOL(); TAKT(); return (uint8_t)(b + C.y); }
static inline uint16_t a_abs(void) { uint16_t lo = HOL(); uint16_t hi = HOL(); return (uint16_t)(lo | (hi << 8)); }
static inline uint16_t unfertig(uint16_t b, uint16_t e) { return (uint16_t)((b & 0xFF00) | (e & 0x00FF)); }
static inline uint16_t idx_l(uint16_t b, uint8_t i)
{
    uint16_t e = (uint16_t)(b + i);
    if ((b ^ e) & 0xFF00) BLIND(unfertig(b, e));
    return e;
}
static inline uint16_t idx_s(uint16_t b, uint8_t i)
{
    uint16_t e = (uint16_t)(b + i);
    BLIND(unfertig(b, e));
    return e;
}
static inline uint16_t a_abx_l(void) { return idx_l(a_abs(), C.x); }
static inline uint16_t a_aby_l(void) { return idx_l(a_abs(), C.y); }
static inline uint16_t a_abx_s(void) { return idx_s(a_abs(), C.x); }
static inline uint16_t a_aby_s(void) { return idx_s(a_abs(), C.y); }
static inline uint16_t a_izx(void)
{
    uint8_t z = HOL(); TAKT(); z = (uint8_t)(z + C.x);
    uint16_t lo = ZL(z); uint16_t hi = ZL((uint8_t)(z + 1));
    return (uint16_t)(lo | (hi << 8));
}
static inline uint16_t a_izy_basis(void)
{
    uint8_t z = HOL();
    uint16_t lo = ZL(z); uint16_t hi = ZL((uint8_t)(z + 1));
    return (uint16_t)(lo | (hi << 8));
}
static inline uint16_t a_izy_l(void) { return idx_l(a_izy_basis(), C.y); }
static inline uint16_t a_izy_s(void) { return idx_s(a_izy_basis(), C.y); }

/* Werte holen */
static inline uint8_t v_imm(void) { return HOL(); }
static inline uint8_t v_zp(void)  { return ZL(a_zp()); }
static inline uint8_t v_zpx(void) { return ZL(a_zpx()); }
static inline uint8_t v_zpy(void) { return ZL(a_zpy()); }
static inline uint8_t v_abs(void) { return LES(a_abs()); }
static inline uint8_t v_abx(void) { return LES(a_abx_l()); }
static inline uint8_t v_aby(void) { return LES(a_aby_l()); }
static inline uint8_t v_izx(void) { return LES(a_izx()); }
static inline uint8_t v_izy(void) { return LES(a_izy_l()); }

/* Werte ablegen */
static inline void s_zp(uint8_t v)  { ZS(a_zp(), v); }
static inline void s_zpx(uint8_t v) { ZS(a_zpx(), v); }
static inline void s_zpy(uint8_t v) { ZS(a_zpy(), v); }
static inline void s_abs(uint8_t v) { SCHR(a_abs(), v); }
static inline void s_abx(uint8_t v) { SCHR(a_abx_s(), v); }
static inline void s_aby(uint8_t v) { SCHR(a_aby_s(), v); }
static inline void s_izx(uint8_t v) { SCHR(a_izx(), v); }
static inline void s_izy(uint8_t v) { SCHR(a_izy_s(), v); }

/* ------------------------------------------------------------- Rechnen */
static inline void nz(uint8_t v) { C.fn = C.fz = v; }
static inline void ora(uint8_t v) { C.a |= v; nz(C.a); }
static inline void und(uint8_t v) { C.a &= v; nz(C.a); }
static inline void eor(uint8_t v) { C.a ^= v; nz(C.a); }
static inline void vgl(uint8_t r, uint8_t v) { C.fc = r >= v; nz((uint8_t)(r - v)); }
static inline void bit(uint8_t v) { C.fn = v; C.fv = (v >> 6) & 1; C.fz = C.a & v; }

static void adc(uint8_t v)
{
    unsigned c = C.fc;
    if (!C.fd) {
        unsigned s = C.a + v + c;
        C.fv = ((~(C.a ^ v) & (C.a ^ s)) & 0x80) != 0;
        C.fc = s > 0xFF;
        C.a = (uint8_t)s;
        nz(C.a);
        return;
    }
    /* Dezimal wie beim NMOS-6502: Z aus der binaeren Summe, N und V aus
     * dem Zwischenergebnis nach der unteren Korrektur */
    unsigned al = (C.a & 0x0F) + (v & 0x0F) + c;
    if (al >= 0x0A) al = ((al + 0x06) & 0x0F) + 0x10;
    int sv = (int)(int8_t)(C.a & 0xF0) + (int)(int8_t)(v & 0xF0) + (int)al;
    unsigned au = (C.a & 0xF0) + (v & 0xF0) + al;
    C.fz = (uint8_t)(C.a + v + c);
    C.fn = (uint8_t)sv;
    C.fv = sv < -128 || sv > 127;
    if (au >= 0xA0) au += 0x60;
    C.fc = au >= 0x100;
    C.a = (uint8_t)au;
}

static void sbc(uint8_t v)
{
    int borg = C.fc ? 0 : 1;
    int d = C.a - v - borg;
    uint8_t r = (uint8_t)d;
    uint8_t a = C.a;
    /* Flags immer binaer (NMOS) */
    C.fv = (((a ^ v) & (a ^ r)) & 0x80) != 0;
    C.fc = d >= 0;
    nz(r);
    if (!C.fd) { C.a = r; return; }
    int al = (a & 0x0F) - (v & 0x0F) - borg;
    if (al < 0) al = ((al - 0x06) & 0x0F) - 0x10;
    int ag = (a & 0xF0) - (v & 0xF0) + al;
    if (ag < 0) ag -= 0x60;
    C.a = (uint8_t)ag;
}

static inline uint8_t asl_w(uint8_t v) { C.fc = v >> 7; v = (uint8_t)(v << 1); nz(v); return v; }
static inline uint8_t lsr_w(uint8_t v) { C.fc = v & 1; v >>= 1; nz(v); return v; }
static inline uint8_t rol_w(uint8_t v) { uint8_t c = C.fc; C.fc = v >> 7; v = (uint8_t)((v << 1) | c); nz(v); return v; }
static inline uint8_t ror_w(uint8_t v) { uint8_t c = C.fc; C.fc = v & 1; v = (uint8_t)((v >> 1) | (c << 7)); nz(v); return v; }
static inline uint8_t inc_w(uint8_t v) { v++; nz(v); return v; }
static inline uint8_t dec_w(uint8_t v) { v--; nz(v); return v; }
static inline uint8_t slo_w(uint8_t v) { v = asl_w(v); ora(v); return v; }
static inline uint8_t rla_w(uint8_t v) { v = rol_w(v); und(v); return v; }
static inline uint8_t sre_w(uint8_t v) { v = lsr_w(v); eor(v); return v; }
static inline uint8_t rra_w(uint8_t v) { v = ror_w(v); adc(v); return v; }
static inline uint8_t dcp_w(uint8_t v) { v--; vgl(C.a, v); return v; }
static inline uint8_t isc_w(uint8_t v) { v++; sbc(v); return v; }

static void arr(uint8_t v)
{
    uint8_t t = C.a & v;
    uint8_t r = (uint8_t)((t >> 1) | (C.fc << 7));
    if (!C.fd) {
        nz(r);
        C.fc = (r >> 6) & 1;
        C.fv = ((r >> 6) ^ (r >> 5)) & 1;
        C.a = r;
        return;
    }
    C.fn = (uint8_t)(C.fc << 7);
    C.fz = r;
    C.fv = ((t ^ r) & 0x40) != 0;
    if ((t & 0x0F) + (t & 0x01) > 5) r = (uint8_t)((r & 0xF0) | ((r + 6) & 0x0F));
    if ((t & 0xF0) + (t & 0x10) > 0x50) { C.fc = 1; r = (uint8_t)(r + 0x60); }
    else C.fc = 0;
    C.a = r;
}

/* SHA/SHX/SHY/TAS: Wert UND (oberes Adressbyte + 1); bei Seitenwechsel
 * wird das obere Adressbyte durch den Wert ersetzt */
static inline void sh_ablegen(uint16_t basis, uint8_t index, uint8_t wert)
{
    uint16_t e = (uint16_t)(basis + index);
    uint8_t v = wert & (uint8_t)((basis >> 8) + 1);
    BLIND(unfertig(basis, e));
    if ((basis ^ e) & 0xFF00) e = (uint16_t)((e & 0x00FF) | (v << 8));
    SCHR(e, v);
}

#define RMW_Z(adrfn, f) { uint8_t a_ = adrfn(); uint8_t v_ = ZL(a_); ZS(a_, v_); v_ = f(v_); ZS(a_, v_); } break
#define RMW_A(adrfn, f) { uint16_t a_ = adrfn(); uint8_t v_ = LES(a_); SCHR(a_, v_); v_ = f(v_); SCHR(a_, v_); } break

/* Naechster Zyklus, an dem sich etwas tun kann: Geraeteereignis, Ende des
 * Laufs oder ein anstehender Interrupt, der erkannt wird (zwei Takte nach
 * dem Setzen der Leitung, wie beim 6510) */
static inline uint64_t weckzeit(uint64_t bis, uint8_t i)
{
    uint64_t z = M.naechstes < bis ? M.naechstes : bis;
    if (M.nmi_flanke && M.nmi_ab + 2 < z) z = M.nmi_ab + 2;
    if (M.irq && !i && M.irq_ab + 2 < z) z = M.irq_ab + 2;
    return z;
}

/* Endlosschleife auf sich selbst (JMP *, Bxx *): bis zum naechsten Ereignis
 * vorspulen, in ganzen Umlaeufen (so wie die echte Schleife) */
static void selbstschleife(unsigned periode)
{
    uint64_t ziel = weckzeit(lauf_bis, C.fi);
    if (ziel > C.z) C.z += (ziel - C.z + periode - 1) / periode * periode;
}

static inline void verzweige(int bed, uint16_t pc0)
{
    int8_t d = (int8_t)HOL();
    if (!bed) return;
    BLIND(C.pc);
    uint16_t ziel = (uint16_t)(C.pc + d);
    unsigned periode = 3;
    if ((ziel ^ C.pc) & 0xFF00) { BLIND(unfertig(C.pc, ziel)); periode = 4; }
    C.pc = ziel;
    if (ziel == pc0) selbstschleife(periode);
}

static void unterbrechung(uint16_t vektor)
{
    BLIND(C.pc); BLIND(C.pc);
    push((uint8_t)(C.pc >> 8));
    push((uint8_t)C.pc);
    push(cpu_p(0));
    C.fi = 1;
    uint16_t lo = LES(vektor);
    uint16_t hi = LES((uint16_t)(vektor + 1));
    C.pc = (uint16_t)(lo | (hi << 8));
}

static int psid_nativ_moeglich(void)
{
    const uint8_t *s = M.lese[0xFF];
    if (!s) return 0;
    return s[0xFE] == 0x48 && s[0xFF] == 0xFF && M.ram[0x314] == 0x31 && M.ram[0x315] == 0xEA;
}

/* ------------------------------------------------------- Hauptschleife */
int cpu_lauf(uint64_t bis)
{
    lauf_bis = bis;
    while (C.z < bis) {
        if (C.z >= M.naechstes) ereignisse(C.z);
        if (M.nmi_flanke && M.nmi_ab + 2 <= C.z) {
            M.nmi_flanke = 0;
            unterbrechung(0xFFFA);
            C.i_pruef = 1;
            continue;
        }
        if (M.irq && !C.i_pruef && M.irq_ab + 2 <= C.z) {
            if (M.psid_nativ && psid_nativ_moeglich()) return GRUND_PSID_IRQ;
            unterbrechung(0xFFFE);
            C.i_pruef = 1;
            continue;
        }
        if (C.pc == FANG) {
            if (M.fang_tiefe > 0 && C.s == M.fang_sp[M.fang_tiefe - 1]) return GRUND_FANG;
            if (M.leerlauf) {
                /* Leerlauf: bis zum naechsten Ereignis schlafen */
                uint64_t ziel = weckzeit(bis, C.i_pruef);
                if (ziel > C.z) C.z = ziel;
                else C.z++;
                continue;
            }
        }

        uint16_t pc0 = C.pc;
        if (spur_rest) spur_zeile();
        uint8_t op = HOL_BEFEHL();
        uint8_t i_vorher = C.fi;
        switch (op) {
        /* ---- Laden, Speichern */
        case 0xA9: C.a = v_imm(); nz(C.a); break;
        case 0xA5: C.a = v_zp();  nz(C.a); break;
        case 0xB5: C.a = v_zpx(); nz(C.a); break;
        case 0xAD: C.a = v_abs(); nz(C.a); break;
        case 0xBD: C.a = v_abx(); nz(C.a); break;
        case 0xB9: C.a = v_aby(); nz(C.a); break;
        case 0xA1: C.a = v_izx(); nz(C.a); break;
        case 0xB1: C.a = v_izy(); nz(C.a); break;
        case 0xA2: C.x = v_imm(); nz(C.x); break;
        case 0xA6: C.x = v_zp();  nz(C.x); break;
        case 0xB6: C.x = v_zpy(); nz(C.x); break;
        case 0xAE: C.x = v_abs(); nz(C.x); break;
        case 0xBE: C.x = v_aby(); nz(C.x); break;
        case 0xA0: C.y = v_imm(); nz(C.y); break;
        case 0xA4: C.y = v_zp();  nz(C.y); break;
        case 0xB4: C.y = v_zpx(); nz(C.y); break;
        case 0xAC: C.y = v_abs(); nz(C.y); break;
        case 0xBC: C.y = v_abx(); nz(C.y); break;
        case 0x85: s_zp(C.a); break;
        case 0x95: s_zpx(C.a); break;
        case 0x8D: s_abs(C.a); break;
        case 0x9D: s_abx(C.a); break;
        case 0x99: s_aby(C.a); break;
        case 0x81: s_izx(C.a); break;
        case 0x91: s_izy(C.a); break;
        case 0x86: s_zp(C.x); break;
        case 0x96: s_zpy(C.x); break;
        case 0x8E: s_abs(C.x); break;
        case 0x84: s_zp(C.y); break;
        case 0x94: s_zpx(C.y); break;
        case 0x8C: s_abs(C.y); break;

        /* ---- Rechnen und Logik */
        case 0x09: ora(v_imm()); break;
        case 0x05: ora(v_zp()); break;
        case 0x15: ora(v_zpx()); break;
        case 0x0D: ora(v_abs()); break;
        case 0x1D: ora(v_abx()); break;
        case 0x19: ora(v_aby()); break;
        case 0x01: ora(v_izx()); break;
        case 0x11: ora(v_izy()); break;
        case 0x29: und(v_imm()); break;
        case 0x25: und(v_zp()); break;
        case 0x35: und(v_zpx()); break;
        case 0x2D: und(v_abs()); break;
        case 0x3D: und(v_abx()); break;
        case 0x39: und(v_aby()); break;
        case 0x21: und(v_izx()); break;
        case 0x31: und(v_izy()); break;
        case 0x49: eor(v_imm()); break;
        case 0x45: eor(v_zp()); break;
        case 0x55: eor(v_zpx()); break;
        case 0x4D: eor(v_abs()); break;
        case 0x5D: eor(v_abx()); break;
        case 0x59: eor(v_aby()); break;
        case 0x41: eor(v_izx()); break;
        case 0x51: eor(v_izy()); break;
        case 0x69: adc(v_imm()); break;
        case 0x65: adc(v_zp()); break;
        case 0x75: adc(v_zpx()); break;
        case 0x6D: adc(v_abs()); break;
        case 0x7D: adc(v_abx()); break;
        case 0x79: adc(v_aby()); break;
        case 0x61: adc(v_izx()); break;
        case 0x71: adc(v_izy()); break;
        case 0xE9: case 0xEB: sbc(v_imm()); break;
        case 0xE5: sbc(v_zp()); break;
        case 0xF5: sbc(v_zpx()); break;
        case 0xED: sbc(v_abs()); break;
        case 0xFD: sbc(v_abx()); break;
        case 0xF9: sbc(v_aby()); break;
        case 0xE1: sbc(v_izx()); break;
        case 0xF1: sbc(v_izy()); break;
        case 0xC9: vgl(C.a, v_imm()); break;
        case 0xC5: vgl(C.a, v_zp()); break;
        case 0xD5: vgl(C.a, v_zpx()); break;
        case 0xCD: vgl(C.a, v_abs()); break;
        case 0xDD: vgl(C.a, v_abx()); break;
        case 0xD9: vgl(C.a, v_aby()); break;
        case 0xC1: vgl(C.a, v_izx()); break;
        case 0xD1: vgl(C.a, v_izy()); break;
        case 0xE0: vgl(C.x, v_imm()); break;
        case 0xE4: vgl(C.x, v_zp()); break;
        case 0xEC: vgl(C.x, v_abs()); break;
        case 0xC0: vgl(C.y, v_imm()); break;
        case 0xC4: vgl(C.y, v_zp()); break;
        case 0xCC: vgl(C.y, v_abs()); break;
        case 0x24: bit(v_zp()); break;
        case 0x2C: bit(v_abs()); break;

        /* ---- Schieben, Zaehlen (Lesen-Aendern-Schreiben) */
        case 0x0A: BLIND(C.pc); C.a = asl_w(C.a); break;
        case 0x4A: BLIND(C.pc); C.a = lsr_w(C.a); break;
        case 0x2A: BLIND(C.pc); C.a = rol_w(C.a); break;
        case 0x6A: BLIND(C.pc); C.a = ror_w(C.a); break;
        case 0x06: RMW_Z(a_zp, asl_w);
        case 0x16: RMW_Z(a_zpx, asl_w);
        case 0x0E: RMW_A(a_abs, asl_w);
        case 0x1E: RMW_A(a_abx_s, asl_w);
        case 0x46: RMW_Z(a_zp, lsr_w);
        case 0x56: RMW_Z(a_zpx, lsr_w);
        case 0x4E: RMW_A(a_abs, lsr_w);
        case 0x5E: RMW_A(a_abx_s, lsr_w);
        case 0x26: RMW_Z(a_zp, rol_w);
        case 0x36: RMW_Z(a_zpx, rol_w);
        case 0x2E: RMW_A(a_abs, rol_w);
        case 0x3E: RMW_A(a_abx_s, rol_w);
        case 0x66: RMW_Z(a_zp, ror_w);
        case 0x76: RMW_Z(a_zpx, ror_w);
        case 0x6E: RMW_A(a_abs, ror_w);
        case 0x7E: RMW_A(a_abx_s, ror_w);
        case 0xE6: RMW_Z(a_zp, inc_w);
        case 0xF6: RMW_Z(a_zpx, inc_w);
        case 0xEE: RMW_A(a_abs, inc_w);
        case 0xFE: RMW_A(a_abx_s, inc_w);
        case 0xC6: RMW_Z(a_zp, dec_w);
        case 0xD6: RMW_Z(a_zpx, dec_w);
        case 0xCE: RMW_A(a_abs, dec_w);
        case 0xDE: RMW_A(a_abx_s, dec_w);
        case 0xE8: BLIND(C.pc); C.x++; nz(C.x); break;
        case 0xCA: BLIND(C.pc); C.x--; nz(C.x); break;
        case 0xC8: BLIND(C.pc); C.y++; nz(C.y); break;
        case 0x88: BLIND(C.pc); C.y--; nz(C.y); break;

        /* ---- Uebertragen */
        case 0xAA: BLIND(C.pc); C.x = C.a; nz(C.x); break;
        case 0x8A: BLIND(C.pc); C.a = C.x; nz(C.a); break;
        case 0xA8: BLIND(C.pc); C.y = C.a; nz(C.y); break;
        case 0x98: BLIND(C.pc); C.a = C.y; nz(C.a); break;
        case 0xBA: BLIND(C.pc); C.x = C.s; nz(C.x); break;
        case 0x9A: BLIND(C.pc); C.s = C.x; break;

        /* ---- Flags */
        case 0x18: BLIND(C.pc); C.fc = 0; break;
        case 0x38: BLIND(C.pc); C.fc = 1; break;
        case 0xD8: BLIND(C.pc); C.fd = 0; break;
        case 0xF8: BLIND(C.pc); C.fd = 1; break;
        case 0xB8: BLIND(C.pc); C.fv = 0; break;
        case 0x58: BLIND(C.pc); C.fi = 0; C.i_pruef = i_vorher; continue;
        case 0x78: BLIND(C.pc); C.fi = 1; C.i_pruef = i_vorher; continue;

        /* ---- Stapel */
        case 0x48: BLIND(C.pc); push(C.a); break;
        case 0x08: BLIND(C.pc); push(cpu_p(1)); break;
        case 0x68: BLIND(C.pc); TAKT(); C.a = pull(); nz(C.a); break;
        case 0x28: BLIND(C.pc); TAKT(); cpu_p_setzen(pull()); C.i_pruef = i_vorher; continue;

        /* ---- Spruenge */
        case 0x4C: {
            uint16_t ziel = a_abs();
            C.pc = ziel;
            if (ziel == pc0) selbstschleife(3);
            break;
        }
        case 0x6C: {
            uint16_t p = a_abs();
            uint16_t lo = LES(p);
            uint16_t hi = LES((uint16_t)((p & 0xFF00) | ((p + 1) & 0xFF)));
            C.pc = (uint16_t)(lo | (hi << 8));
            break;
        }
        case 0x20: {
            uint16_t lo = HOL();
            TAKT();
            push((uint8_t)(C.pc >> 8));
            push((uint8_t)C.pc);
            uint16_t hi = LES(C.pc);
            C.pc = (uint16_t)(lo | (hi << 8));
            break;
        }
        case 0x60: {
            BLIND(C.pc); TAKT();
            uint16_t lo = pull();
            uint16_t hi = pull();
            C.pc = (uint16_t)(lo | (hi << 8));
            BLIND(C.pc);
            C.pc++;
            break;
        }
        case 0x40: {
            BLIND(C.pc); TAKT();
            cpu_p_setzen(pull());
            uint16_t lo = pull();
            uint16_t hi = pull();
            C.pc = (uint16_t)(lo | (hi << 8));
            break;
        }
        case 0x00: {
            HOL();
            push((uint8_t)(C.pc >> 8));
            push((uint8_t)C.pc);
            push(cpu_p(1));
            C.fi = 1;
            uint16_t lo = LES(0xFFFE);
            uint16_t hi = LES(0xFFFF);
            C.pc = (uint16_t)(lo | (hi << 8));
            break;
        }
        case 0x10: verzweige(!(C.fn & 0x80), pc0); break;
        case 0x30: verzweige(C.fn & 0x80, pc0); break;
        case 0x50: verzweige(!C.fv, pc0); break;
        case 0x70: verzweige(C.fv, pc0); break;
        case 0x90: verzweige(!C.fc, pc0); break;
        case 0xB0: verzweige(C.fc, pc0); break;
        case 0xD0: verzweige(C.fz != 0, pc0); break;
        case 0xF0: verzweige(C.fz == 0, pc0); break;

        /* ---- NOP in allen Laengen */
        case 0xEA: case 0x1A: case 0x3A: case 0x5A: case 0x7A: case 0xDA: case 0xFA:
            BLIND(C.pc); break;
        case 0x80: case 0x82: case 0x89: case 0xC2: case 0xE2:
            HOL(); break;
        case 0x04: case 0x44: case 0x64:
            (void)v_zp(); break;
        case 0x14: case 0x34: case 0x54: case 0x74: case 0xD4: case 0xF4:
            (void)v_zpx(); break;
        case 0x0C:
            (void)v_abs(); break;
        case 0x1C: case 0x3C: case 0x5C: case 0x7C: case 0xDC: case 0xFC:
            (void)v_abx(); break;

        /* ---- JAM: CPU steht */
        case 0x02: case 0x12: case 0x22: case 0x32: case 0x42: case 0x52:
        case 0x62: case 0x72: case 0x92: case 0xB2: case 0xD2: case 0xF2:
            C.pc = pc0;
            C.jam = 1;
            return GRUND_JAM;

        /* ---- Undokumentierte Befehle */
        case 0x07: RMW_Z(a_zp, slo_w);
        case 0x17: RMW_Z(a_zpx, slo_w);
        case 0x0F: RMW_A(a_abs, slo_w);
        case 0x1F: RMW_A(a_abx_s, slo_w);
        case 0x1B: RMW_A(a_aby_s, slo_w);
        case 0x03: RMW_A(a_izx, slo_w);
        case 0x13: RMW_A(a_izy_s, slo_w);
        case 0x27: RMW_Z(a_zp, rla_w);
        case 0x37: RMW_Z(a_zpx, rla_w);
        case 0x2F: RMW_A(a_abs, rla_w);
        case 0x3F: RMW_A(a_abx_s, rla_w);
        case 0x3B: RMW_A(a_aby_s, rla_w);
        case 0x23: RMW_A(a_izx, rla_w);
        case 0x33: RMW_A(a_izy_s, rla_w);
        case 0x47: RMW_Z(a_zp, sre_w);
        case 0x57: RMW_Z(a_zpx, sre_w);
        case 0x4F: RMW_A(a_abs, sre_w);
        case 0x5F: RMW_A(a_abx_s, sre_w);
        case 0x5B: RMW_A(a_aby_s, sre_w);
        case 0x43: RMW_A(a_izx, sre_w);
        case 0x53: RMW_A(a_izy_s, sre_w);
        case 0x67: RMW_Z(a_zp, rra_w);
        case 0x77: RMW_Z(a_zpx, rra_w);
        case 0x6F: RMW_A(a_abs, rra_w);
        case 0x7F: RMW_A(a_abx_s, rra_w);
        case 0x7B: RMW_A(a_aby_s, rra_w);
        case 0x63: RMW_A(a_izx, rra_w);
        case 0x73: RMW_A(a_izy_s, rra_w);
        case 0xC7: RMW_Z(a_zp, dcp_w);
        case 0xD7: RMW_Z(a_zpx, dcp_w);
        case 0xCF: RMW_A(a_abs, dcp_w);
        case 0xDF: RMW_A(a_abx_s, dcp_w);
        case 0xDB: RMW_A(a_aby_s, dcp_w);
        case 0xC3: RMW_A(a_izx, dcp_w);
        case 0xD3: RMW_A(a_izy_s, dcp_w);
        case 0xE7: RMW_Z(a_zp, isc_w);
        case 0xF7: RMW_Z(a_zpx, isc_w);
        case 0xEF: RMW_A(a_abs, isc_w);
        case 0xFF: RMW_A(a_abx_s, isc_w);
        case 0xFB: RMW_A(a_aby_s, isc_w);
        case 0xE3: RMW_A(a_izx, isc_w);
        case 0xF3: RMW_A(a_izy_s, isc_w);

        case 0x87: s_zp(C.a & C.x); break;
        case 0x97: s_zpy(C.a & C.x); break;
        case 0x8F: s_abs(C.a & C.x); break;
        case 0x83: s_izx(C.a & C.x); break;

        case 0xA7: C.a = C.x = v_zp();  nz(C.a); break;
        case 0xB7: C.a = C.x = v_zpy(); nz(C.a); break;
        case 0xAF: C.a = C.x = v_abs(); nz(C.a); break;
        case 0xBF: C.a = C.x = v_aby(); nz(C.a); break;
        case 0xA3: C.a = C.x = v_izx(); nz(C.a); break;
        case 0xB3: C.a = C.x = v_izy(); nz(C.a); break;

        case 0x0B: case 0x2B: und(v_imm()); C.fc = C.a >> 7; break;            /* ANC */
        case 0x4B: und(v_imm()); C.a = lsr_w(C.a); break;                     /* ALR */
        case 0x6B: arr(v_imm()); break;                                       /* ARR */
        case 0x8B: C.a = (uint8_t)((C.a | 0xEE) & C.x & v_imm()); nz(C.a); break;   /* ANE */
        case 0xAB: C.a = C.x = (uint8_t)((C.a | 0xEE) & v_imm()); nz(C.a); break;   /* LXA */
        case 0xCB: {                                                          /* SBX */
            uint8_t v = v_imm();
            uint8_t t = C.a & C.x;
            C.fc = t >= v;
            C.x = (uint8_t)(t - v);
            nz(C.x);
            break;
        }
        case 0xBB: {                                                          /* LAS */
            uint8_t v = (uint8_t)(v_aby() & C.s);
            C.a = C.x = C.s = v;
            nz(v);
            break;
        }
        case 0x9F: { uint16_t b = a_abs(); sh_ablegen(b, C.y, C.a & C.x); break; }   /* SHA abs,Y */
        case 0x93: { uint16_t b = a_izy_basis(); sh_ablegen(b, C.y, C.a & C.x); break; } /* SHA (zp),Y */
        case 0x9E: { uint16_t b = a_abs(); sh_ablegen(b, C.y, C.x); break; }         /* SHX */
        case 0x9C: { uint16_t b = a_abs(); sh_ablegen(b, C.x, C.y); break; }         /* SHY */
        case 0x9B: { uint16_t b = a_abs(); C.s = C.a & C.x; sh_ablegen(b, C.y, C.s); break; } /* TAS */
        }
        C.i_pruef = C.fi;
    }
    return GRUND_BIS;
}
