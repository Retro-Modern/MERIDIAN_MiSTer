/*
 * sidkern - SID-Registerstrom aus .sid-Dateien (Teil von SID JAM)
 * Copyright (c) 2026 retro-modern.net. GPL-3.0-or-later.
 *
 * Kopf einer .sid-Datei lesen (nach DOCUMENTS/SID_file_format.txt der HVSC),
 * MD5 nach RFC 1321 (eigene Umsetzung) und den JSON-Kopf fuer SJE bauen.
 */
#include <stdio.h>
#include <string.h>
#include "siddatei.h"

static uint16_t be16(const uint8_t *p) { return (uint16_t)((p[0] << 8) | p[1]); }
static uint32_t be32(const uint8_t *p) { return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) | ((uint32_t)p[2] << 8) | p[3]; }

static void text_holen(char *ziel, const uint8_t *quelle)
{
    memcpy(ziel, quelle, 32);
    ziel[32] = 0;
}

static uint16_t zusatz_sid(uint8_t b)
{
    if (b & 1) return 0;
    if ((b >= 0x42 && b <= 0x7F) || (b >= 0xE0 && b <= 0xFE)) return (uint16_t)(0xD000 | (b << 4));
    return 0;
}

int sid_kopf_lesen(const uint8_t *d, size_t n, SidKopf *k, const char **fehler)
{
    memset(k, 0, sizeof *k);
    if (n < 0x76) { *fehler = "Datei zu kurz"; return 1; }
    if (!memcmp(d, "PSID", 4)) k->rsid = 0;
    else if (!memcmp(d, "RSID", 4)) k->rsid = 1;
    else { *fehler = "kein PSID/RSID"; return 1; }
    k->version = be16(d + 4);
    uint16_t daten_ab = be16(d + 6);
    k->load = be16(d + 8);
    k->init = be16(d + 10);
    k->play = be16(d + 12);
    k->songs = be16(d + 14);
    k->start_song = be16(d + 16);
    k->speed = be32(d + 18);
    text_holen(k->name, d + 0x16);
    text_holen(k->autor, d + 0x36);
    text_holen(k->released, d + 0x56);
    if (k->version >= 2 && n >= 0x7C) {
        k->flags = be16(d + 0x76);
        if (k->version >= 3) k->sid_adr[1] = zusatz_sid(d[0x7A]);
        if (k->version >= 4) {
            k->sid_adr[2] = zusatz_sid(d[0x7B]);
            if (k->sid_adr[2] == k->sid_adr[1]) k->sid_adr[2] = 0;
        }
    }
    k->sid_adr[0] = 0xD400;
    k->anzahl_sids = 1;
    if (k->sid_adr[1]) k->anzahl_sids = 2;
    if (k->sid_adr[2]) {
        if (!k->sid_adr[1]) { k->sid_adr[1] = k->sid_adr[2]; k->sid_adr[2] = 0; k->anzahl_sids = 2; }
        else k->anzahl_sids = 3;
    }
    if (k->songs < 1) k->songs = 1;
    if (k->songs > 256) k->songs = 256;
    if (k->start_song < 1 || k->start_song > k->songs) k->start_song = 1;
    if (daten_ab < 0x76 || daten_ab > n) { *fehler = "Datenbeginn falsch"; return 1; }
    k->daten = d + daten_ab;
    k->laenge = n - daten_ab;
    if (k->load == 0) {
        if (k->laenge < 2) { *fehler = "keine Ladeadresse"; return 1; }
        k->load = (uint16_t)(k->daten[0] | (k->daten[1] << 8));
        k->daten += 2;
        k->laenge -= 2;
    }
    if (k->load + k->laenge > 0x10000) k->laenge = 0x10000 - k->load;   /* Rest passt nicht */
    if (k->init == 0) k->init = k->load;
    k->basic = k->rsid && (k->flags & 2);
    md5_text(d, n, k->md5);
    return 0;
}

int sid_tempo_cia(const SidKopf *k, int lied)
{
    if (k->rsid) return 1;
    int bit = lied - 1;
    if (bit > 31) {
        int playsid = k->version == 1 || (k->flags & 2);
        bit = playsid ? bit % 32 : 31;
    }
    return (k->speed >> bit) & 1;
}

int sid_kopf_uhr(const SidKopf *k) { return k->version >= 2 ? (k->flags >> 2) & 3 : 0; }
int sid_kopf_modell(const SidKopf *k) { return k->version >= 2 ? (k->flags >> 4) & 3 : 0; }

/* ================================================================ MD5 */

typedef struct {
    uint32_t h[4];
    uint64_t laenge;
    uint8_t block[64];
    size_t fuell;
} Md5;

static uint32_t links(uint32_t x, int n) { return (x << n) | (x >> (32 - n)); }

static void md5_block(Md5 *m, const uint8_t *b)
{
    /* Verschiebungen je Runde und die Sinus-Konstanten (RFC 1321) */
    static const int r[64] = {
        7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
        5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
        4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
        6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21
    };
    /* t[i] = floor(2^32 * |sin(i + 1)|), Werte aus dem RFC */
    static const uint32_t t[64] = {
        0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee, 0xf57c0faf, 0x4787c62a, 0xa8304613, 0xfd469501,
        0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be, 0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821,
        0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa, 0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8,
        0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed, 0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a,
        0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c, 0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70,
        0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05, 0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665,
        0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039, 0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1,
        0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1, 0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391
    };
    uint32_t w[16];
    for (int i = 0; i < 16; i++)
        w[i] = (uint32_t)b[i * 4] | ((uint32_t)b[i * 4 + 1] << 8) | ((uint32_t)b[i * 4 + 2] << 16) | ((uint32_t)b[i * 4 + 3] << 24);
    uint32_t a = m->h[0], bb = m->h[1], c = m->h[2], d = m->h[3];
    for (int i = 0; i < 64; i++) {
        uint32_t f; int g;
        if (i < 16)      { f = (bb & c) | (~bb & d); g = i; }
        else if (i < 32) { f = (d & bb) | (~d & c); g = (5 * i + 1) & 15; }
        else if (i < 48) { f = bb ^ c ^ d;          g = (3 * i + 5) & 15; }
        else             { f = c ^ (bb | ~d);       g = (7 * i) & 15; }
        uint32_t neu = bb + links(a + f + t[i] + w[g], r[i]);
        a = d; d = c; c = bb; bb = neu;
    }
    m->h[0] += a; m->h[1] += bb; m->h[2] += c; m->h[3] += d;
}

static void md5_dazu(Md5 *m, const uint8_t *p, size_t n)
{
    m->laenge += n;
    while (n) {
        size_t k = 64 - m->fuell;
        if (k > n) k = n;
        memcpy(m->block + m->fuell, p, k);
        m->fuell += k; p += k; n -= k;
        if (m->fuell == 64) { md5_block(m, m->block); m->fuell = 0; }
    }
}

void md5_text(const uint8_t *daten, size_t n, char aus[33])
{
    Md5 m = { { 0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476 }, 0, { 0 }, 0 };
    md5_dazu(&m, daten, n);
    uint64_t bits = m.laenge * 8;
    uint8_t ende[72] = { 0x80 };
    size_t pad = (m.fuell < 56) ? 56 - m.fuell : 120 - m.fuell;
    for (int i = 0; i < 8; i++) ende[pad + i] = (uint8_t)(bits >> (8 * i));
    md5_dazu(&m, ende, pad + 8);
    static const char hex[] = "0123456789abcdef";
    for (int i = 0; i < 16; i++) {
        uint8_t b = (uint8_t)(m.h[i / 4] >> (8 * (i % 4)));
        aus[i * 2] = hex[b >> 4];
        aus[i * 2 + 1] = hex[b & 15];
    }
    aus[32] = 0;
}

/* =============================================================== JSON */

/* Windows-1252 0x80-0x9F als Unicode (0 = nicht belegt) */
static const uint16_t CP1252[32] = {
    0x20AC, 0, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, 0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0, 0x017D, 0,
    0, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014, 0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0, 0x017E, 0x0178
};

typedef struct { char *p; size_t platz, n; } Puffer;

static void p_zeichen(Puffer *b, char c) { if (b->n + 1 < b->platz) b->p[b->n] = c; b->n++; }
static void p_text(Puffer *b, const char *s) { while (*s) p_zeichen(b, *s++); }

static void p_json_text(Puffer *b, const char *s)
{
    p_zeichen(b, '"');
    for (const uint8_t *q = (const uint8_t *)s; *q; q++) {
        unsigned u = *q;
        if (u >= 0x80 && u < 0xA0) { u = CP1252[u - 0x80]; if (!u) u = '?'; }
        if (u == '"' || u == '\\') { p_zeichen(b, '\\'); p_zeichen(b, (char)u); }
        else if (u < 0x20) { char t[8]; snprintf(t, sizeof t, "\\u%04x", u); p_text(b, t); }
        else if (u < 0x80) p_zeichen(b, (char)u);
        else if (u < 0x800) { p_zeichen(b, (char)(0xC0 | (u >> 6))); p_zeichen(b, (char)(0x80 | (u & 0x3F))); }
        else {
            p_zeichen(b, (char)(0xE0 | (u >> 12)));
            p_zeichen(b, (char)(0x80 | ((u >> 6) & 0x3F)));
            p_zeichen(b, (char)(0x80 | (u & 0x3F)));
        }
    }
    p_zeichen(b, '"');
}

size_t json_kopf(const SidKopf *k, const SpielInfo *s, char *aus, size_t platz)
{
    Puffer b = { aus, platz, 0 };
    char t[256];
    p_text(&b, "{\"title\":"); p_json_text(&b, k->name);
    p_text(&b, ",\"author\":"); p_json_text(&b, k->autor);
    p_text(&b, ",\"released\":"); p_json_text(&b, k->released);
    snprintf(t, sizeof t, ",\"format\":\"%s\",\"version\":%d,\"song\":%d,\"songs\":%d,\"start_song\":%d",
             k->rsid ? "RSID" : "PSID", k->version, s->lied, k->songs, k->start_song);
    p_text(&b, t);
    snprintf(t, sizeof t, ",\"clock\":\"%s\",\"cps\":%u,\"model\":\"%s\",\"sids\":[",
             s->ntsc ? "NTSC" : "PAL", s->ntsc ? 1022727u : 985248u, s->modell8580 ? "8580" : "6581");
    p_text(&b, t);
    for (int i = 0; i < k->anzahl_sids; i++) {
        snprintf(t, sizeof t, "%s%u", i ? "," : "", k->sid_adr[i]);
        p_text(&b, t);
    }
    snprintf(t, sizeof t, "],\"speed\":\"%s\",\"load\":%u,\"init\":%u,\"play\":%u,\"start_cycles\":%llu,\"md5\":\"%s\",\"basic\":%s}",
             s->cia ? "cia" : "vbi", k->load, k->init, k->play, (unsigned long long)s->start_zyklen, k->md5,
             k->basic ? "true" : "false");
    p_text(&b, t);
    if (b.n < platz) aus[b.n] = 0;
    else if (platz) aus[platz - 1] = 0;
    return b.n;
}
