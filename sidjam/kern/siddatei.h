/*
 * sidkern - SID-Registerstrom aus .sid-Dateien (Teil von SID JAM)
 * Copyright (c) 2026 retro-modern.net. GPL-3.0-or-later.
 *
 * Kopf einer .sid-Datei (PSID/RSID v1-v4), MD5 und JSON-Kopf.
 */
#ifndef SIDDATEI_H
#define SIDDATEI_H

#include <stdint.h>
#include <stddef.h>

typedef struct {
    int rsid;                   /* 0 = PSID, 1 = RSID */
    int version;
    uint16_t load, init, play;
    int songs, start_song;
    uint32_t speed;
    uint16_t flags;
    char name[33], autor[33], released[33];
    uint16_t sid_adr[3];        /* Basisadressen, 0 = nicht da */
    int anzahl_sids;
    const uint8_t *daten;       /* C64-Daten ohne Ladeadresse */
    size_t laenge;
    int basic;                  /* RSID mit C64BASIC-Flag */
    char md5[33];
} SidKopf;

/* 0 = gut, sonst Fehlertext in 'fehler' */
int sid_kopf_lesen(const uint8_t *datei, size_t groesse, SidKopf *k, const char **fehler);

/* 1 = CIA, 0 = VBI fuer Lied 'lied' (1-basiert) */
int sid_tempo_cia(const SidKopf *k, int lied);

/* Uhr laut Kopf: 0 unbekannt, 1 PAL, 2 NTSC, 3 beide */
int sid_kopf_uhr(const SidKopf *k);
/* Modell laut Kopf: 0 unbekannt, 1 6581, 2 8580, 3 beide */
int sid_kopf_modell(const SidKopf *k);

void md5_text(const uint8_t *daten, size_t n, char aus[33]);

/* JSON-Kopf schreiben; gibt die Laenge zurueck (ohne 0) */
typedef struct {
    int lied, ntsc, modell8580, cia;
    uint64_t start_zyklen;
} SpielInfo;
size_t json_kopf(const SidKopf *k, const SpielInfo *s, char *aus, size_t platz);

#endif
