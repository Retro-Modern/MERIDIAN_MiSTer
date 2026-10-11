/*
 * sidkern - SID-Registerstrom aus .sid-Dateien (Teil von SID JAM)
 * Copyright (c) 2026 retro-modern.net. GPL-3.0-or-later.
 *
 * Gemeinsame Typen und die schnellen Speicherzugriffe (inline), die der
 * CPU-Kern braucht. Die langsamen Wege (Ein-/Ausgabe, Prozessorport) stehen
 * in maschine.c.
 */
#ifndef KERN_H
#define KERN_H

#include <stdint.h>
#include <stddef.h>

#define NIE UINT64_MAX

/* Taktraten (Zyklen je Sekunde) */
#define ZPS_PAL  985248u
#define ZPS_NTSC 1022727u

/* Fangadresse: hier kehren init und play zurueck (wird nie ausgefuehrt,
 * solange der Stapelzeiger passt). */
#define FANG 0xFFFFu

/* ---------------------------------------------------------------- CIA */
typedef struct {
    uint16_t latch;     /* Startwert */
    uint16_t wert;      /* Zaehlerstand zum Zyklus 'stand' */
    uint64_t stand;
    uint8_t  cr;        /* Steuerregister (ohne Bit 4) */
} CiaTimer;

typedef struct {
    CiaTimer ta, tb;
    uint8_t icr_daten, icr_maske;
    uint8_t pra, prb, ddra, ddrb, sdr;
    uint8_t irq;            /* Ausgang aktiv (bleibt, bis ICR gelesen) */
    uint64_t irq_ab;        /* seit wann */
    uint64_t irq_kommt;     /* geht zu diesem Zyklus an (NIE = nichts geplant) */
    uint64_t gelesen;       /* Zyklus des letzten ICR-Lesens */
} Cia;

/* ---------------------------------------------------------------- VIC */
typedef struct {
    uint8_t  reg[0x40];
    uint16_t vergleich;     /* Rasterzeile fuer den Interrupt */
    uint8_t  latch, maske, irq;
    uint64_t irq_ab;
    uint32_t zeilen, zpz;   /* Zeilen je Bild, Zyklen je Zeile */
    uint64_t versatz;       /* Rasterstellung bei Zyklus 0 */
    uint64_t naechster;     /* naechster Vergleichszeitpunkt */
    uint8_t  den_bild;      /* DEN, wie es fuer Bild Nr. den_bild_nr gilt (aus Zeile $30) */
    uint64_t den_bild_nr;
} Vic;

/* ---------------------------------------------------------------- SID */
typedef struct {
    uint8_t  reg[32];       /* Schattenwerte (zuletzt geschrieben) */
    uint8_t  bus;           /* letzter Wert auf dem Datenbus des Chips ... */
    uint64_t bus_zeit;      /* ... und wann (er verblasst nach bus_ttl Takten) */
    /* Stimme 3 fuer $D41B/$D41C (naeherungsweise) */
    uint32_t akku, lfsr;
    uint64_t osz_stand;
    uint8_t  pegel, phase;  /* Huellkurve: 0 Anschlag, 1 Abfall/Halten, 2 Ausklingen */
    uint32_t env_zaehler;
    uint64_t env_stand;
} Sid;

/* ------------------------------------------------------------ Maschine */
typedef struct {
    uint8_t ram[0x10000];
    uint8_t kernal[0x2000], kernal_befehl[0x2000];   /* Daten- und Befehlsansicht */
    uint8_t basic[0x2000], basic_befehl[0x2000];
    uint8_t zeichen[0x1000];
    uint8_t farbram[0x400];
    const uint8_t *lese[256];   /* je Seite: Zeiger auf 256 Bytes, NULL = langsamer Weg */
    const uint8_t *befehl[256]; /* dasselbe fuer das Holen von Befehlen */
    uint8_t *schreibe[256];
    uint8_t port_ddr, port_daten, bankmodus;
    Cia cia1, cia2;
    Vic vic;
    Sid sid[3];
    int anzahl_sids;
    uint32_t bus_ttl;           /* 6581: 7424 Takte, 8580: 663552 */
    uint64_t osz_lesungen;      /* Zahl der Lesezugriffe auf OSC3/ENV3 (fuer --stat) */
    int8_t sid_block[96];       /* 32-Byte-Bloecke $D400-$DFFF: Chip oder -1 */
    uint32_t zps;               /* Zyklen je Sekunde */
    uint64_t naechstes;         /* naechstes Geraeteereignis (Zyklus) */
    uint64_t klau_ab, klau_bis; /* naechstes Badline-Fenster: Lesetakte darin warten bis klau_bis */
    int badlines;               /* Badlines nachbilden (Vorgabe an) */
    uint8_t irq, nmi_pegel, nmi_flanke;
    uint64_t irq_ab, nmi_ab;    /* seit wann die Leitung aktiv ist */
    int flach;                  /* CPU-Test: 64 KB RAM, keine Ein-/Ausgabe */
    /* Fang und Leerlauf (vom Treiber gesetzt) */
    int fang_tiefe;
    uint8_t fang_sp[16];
    int leerlauf;
    int psid_nativ;             /* PSID mit play: IRQ ruft play direkt */
    /* Mitschnitt jedes SID-Schreibzugriffs */
    void (*sid_mitschnitt)(uint64_t zyklus, int chip, int reg, uint8_t wert);
} Maschine;

typedef struct {
    uint16_t pc;
    uint8_t a, x, y, s;
    uint8_t fn, fz, fc, fv, fd, fi;   /* N: Bit 7 von fn, Z: fz == 0 */
    uint8_t i_pruef;                  /* I-Flag fuer die naechste Interruptpruefung */
    uint64_t z;                       /* Zyklus */
    int jam;
} Cpu;

extern Maschine M;
extern Cpu C;

/* maschine.c */
void maschine_anlegen(int ntsc, int flach);
void speicher_abbilden(void);
uint8_t io_lesen(uint16_t adr, uint64_t zyk);
void io_schreiben(uint16_t adr, uint8_t wert, uint64_t zyk);
uint8_t port_lesen(uint16_t adr);
void port_schreiben(uint16_t adr, uint8_t wert);
void ereignisse(uint64_t zyk);
void ereignisse_planen(void);
void klau_planen(uint64_t zyk);
void sid_einrichten(int chip, uint16_t basis);
void vic_einrichten(uint8_t d011, uint8_t d012, uint8_t d01a);
void cia_einrichten(Cia *c, uint16_t ta_latch, int ta_an, uint8_t maske);

/* cpu6510.c */
enum { GRUND_BIS, GRUND_JAM, GRUND_FANG, GRUND_PSID_IRQ };
int cpu_lauf(uint64_t bis);
extern long spur_rest;
uint8_t cpu_p(int b);
void cpu_buszyklen(const char *muster);
void cpu_p_setzen(uint8_t p);

/* ---------------------------------------------------- schnelle Wege */
#ifdef SPION
/* nur fuer die Einzelschritt-Pruefung: jeder echte Buszugriff */
void spion(uint16_t adr, uint8_t wert, uint64_t zyk, int schreib);
#define SPIONIEREN(a, v, z, s) spion((a), (v), (z), (s))
#else
#define SPIONIEREN(a, v, z, s) ((void)0)
#endif

static inline uint8_t lesen(uint16_t adr, uint64_t zyk)
{
    const uint8_t *s = M.lese[adr >> 8];
    uint8_t v = s ? s[adr & 0xFF] : io_lesen(adr, zyk);
    SPIONIEREN(adr, v, zyk, 0);
    return v;
}

static inline void schreiben(uint16_t adr, uint8_t wert, uint64_t zyk)
{
    uint8_t *s = M.schreibe[adr >> 8];
    SPIONIEREN(adr, wert, zyk, 1);
    if (s) s[adr & 0xFF] = wert;
    else io_schreiben(adr, wert, zyk);
}

static inline uint8_t zp_lesen(uint8_t adr)
{
    uint8_t v = adr < 2 ? port_lesen(adr) : M.ram[adr];
    SPIONIEREN(adr, v, C.z, 0);
    return v;
}

static inline void zp_schreiben(uint8_t adr, uint8_t wert)
{
    SPIONIEREN(adr, wert, C.z, 1);
    if (adr < 2) port_schreiben(adr, wert);
    else M.ram[adr] = wert;
}

#endif
