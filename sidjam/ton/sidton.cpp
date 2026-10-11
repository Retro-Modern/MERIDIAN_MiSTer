// ---------------------------------------------------------------------------
//  sidton - SID JAM: Registerstrom (SJE) -> Ton mit reSID
//
//  Liest den Strom von sidkern (stdin) und laesst die Schreibzugriffe zur
//  richtigen Zeit auf einen bis drei reSID-Chips los (reSID von Dag Lem,
//  GPL-2 oder spaeter, in resid/). Heraus kommt Mono-Ton fuer den MERIDIAN
//  (8 Bit mit Vorzeichen, wie die Samplekanaele der ORGEL ihn spielen) oder
//  zum Pruefen 16 Bit.
//
//    sidkern X.sid -s 1 -t 180 | sidton [-r 22050] [--s16|--fein] [--fast|--interp]
//                                       [--modell 6581|8580] [--verstaerkung 1.0]
//
//  --fein: je Sample zwei Bytes fuer zwei Samplekanaele der ORGEL - das obere
//  (bei Lautstaerke 63) und den Rest darunter in 1/63 (bei Lautstaerke 1).
//  Zusammen gut 14 Bit statt 8, ohne das Rauschen von 8-Bit-Samples.
//
//  Die Zeit des Tons beginnt beim ersten Datensatz des Stroms (mit --ab also
//  an der Stelle, ab der sidkern liefert): Sample k gehoert zur Liedzeit
//  start + k / rate. So bleibt der Ton im Takt mit den Auftraegen fuer die
//  ORGEL, die der Netzdienst aus demselben Strom macht.
//
//  Teil von MERIDIAN 816 (GPL-3). reSID: GPL-2 oder spaeter.
// ---------------------------------------------------------------------------
#include "resid/sid.h"

#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

using namespace reSID;

static FILE *ein = stdin;

static int lies_byte() { return fgetc(ein); }

// Wert einer Zahl im JSON-Kopf ("cps": 985248) - ein kleiner Leser genuegt
static double json_zahl(const std::string &j, const char *name, double vorgabe)
{
    std::string such = std::string("\"") + name + "\"";
    size_t p = j.find(such);
    if (p == std::string::npos) return vorgabe;
    p = j.find(':', p);
    if (p == std::string::npos) return vorgabe;
    return atof(j.c_str() + p + 1);
}

static std::string json_text(const std::string &j, const char *name)
{
    std::string such = std::string("\"") + name + "\"";
    size_t p = j.find(such);
    if (p == std::string::npos) return "";
    p = j.find(':', p);
    size_t a = j.find('"', p + 1);
    size_t e = j.find('"', a + 1);
    if (a == std::string::npos || e == std::string::npos) return "";
    return j.substr(a + 1, e - a - 1);
}

static int json_anzahl_sids(const std::string &j)
{
    size_t p = j.find("\"sids\"");
    if (p == std::string::npos) return 1;
    size_t a = j.find('[', p), e = j.find(']', p);
    if (a == std::string::npos || e == std::string::npos) return 1;
    int n = 1;
    for (size_t i = a; i < e; i++)
        if (j[i] == ',') n++;
    return n < 1 ? 1 : (n > 3 ? 3 : n);
}

int main(int argc, char **argv)
{
    double rate = 22050;
    bool s16 = false, fein = false;
    // Vorgabe: reSID "fast" mit 4-facher Rate, danach ein eigenes FIR-Filter
    // herunter - auf dem MiSTer-ARM schafft SAMPLE_RESAMPLE keine Echtzeit
    sampling_method art = SAMPLE_FAST;
    int ueber = 4;
    std::string modell_zwang;
    double verstaerkung = 1.0;
    int stumm = 0;                      // Bit 0-2: Stimme 1-3 stumm (auf allen Chips)
    for (int i = 1; i < argc; i++) {
        std::string a = argv[i];
        if (a == "-r" && i + 1 < argc) rate = atof(argv[++i]);
        else if (a == "--s16") s16 = true;
        else if (a == "--fein") fein = true;
        else if (a == "--fast") { art = SAMPLE_FAST; ueber = 1; }
        else if (a == "--interp") { art = SAMPLE_INTERPOLATE; ueber = 1; }
        else if (a == "--resample") { art = SAMPLE_RESAMPLE; ueber = 1; }
        else if (a == "--ueber" && i + 1 < argc) ueber = atoi(argv[++i]);
        else if (a == "--modell" && i + 1 < argc) modell_zwang = argv[++i];
        else if (a == "--verstaerkung" && i + 1 < argc) verstaerkung = atof(argv[++i]);
        else if (a == "--stumm" && i + 1 < argc) stumm = atoi(argv[++i]) & 7;
        else {
            fprintf(stderr, "sidton: unbekannt: %s\n", a.c_str());
            return 2;
        }
    }

    // Kopf
    char kennung[4];
    for (int i = 0; i < 4; i++) {
        int c = lies_byte();
        if (c < 0) return 1;
        kennung[i] = (char)c;
    }
    if (memcmp(kennung, "SJE1", 4) != 0) {
        fprintf(stderr, "sidton: kein SJE-Strom\n");
        return 1;
    }
    int n0 = lies_byte(), n1 = lies_byte();
    if (n0 < 0 || n1 < 0) return 1;
    std::string kopf((size_t)(n0 | n1 << 8), '\0');
    for (size_t i = 0; i < kopf.size(); i++) {
        int c = lies_byte();
        if (c < 0) return 1;
        kopf[i] = (char)c;
    }
    double cps = json_zahl(kopf, "cps", 985248);
    std::string modell = modell_zwang.empty() ? json_text(kopf, "model") : modell_zwang;
    int chips = json_anzahl_sids(kopf);

    static SID sid[3];
    for (int c = 0; c < chips; c++) {
        sid[c].set_chip_model(modell == "8580" ? MOS8580 : MOS6581);
        sid[c].enable_filter(true);
        sid[c].enable_external_filter(true);
        sid[c].set_voice_mask((reg4)(0x0f & ~stumm));
        if (!sid[c].set_sampling_parameters(cps, art, rate * ueber)) {
            fprintf(stderr, "sidton: Abtastrate %g geht nicht\n", rate);
            return 1;
        }
    }
    // mehrere Chips: zusammen etwas leiser, damit nichts uebersteuert
    double faktor = verstaerkung * (chips == 1 ? 1.0 : 0.7);

    // Tiefpass zum Herunterrechnen: gefensterter Sinus (Blackman), Ecke
    // 10 kHz, 32 Abgriffe je Faktor der Ueberabtastung
    int abgriffe = ueber > 1 ? 32 * ueber : 1;
    std::vector<float> h(abgriffe, 1.0f), verlauf(abgriffe, 0.0f);
    if (ueber > 1) {
        double fc = (rate < 22050 ? rate * 0.45 : 10000.0) / (rate * ueber), summe = 0;
        for (int k = 0; k < abgriffe; k++) {
            double x = k - (abgriffe - 1) / 2.0;
            double si = x == 0 ? 2 * fc : sin(2 * M_PI * fc * x) / (M_PI * x);
            double w = 0.42 - 0.5 * cos(2 * M_PI * k / (abgriffe - 1)) + 0.08 * cos(4 * M_PI * k / (abgriffe - 1));
            h[k] = (float)(si * w);
            summe += si * w;
        }
        for (int k = 0; k < abgriffe; k++) h[k] = (float)(h[k] / summe);
    }
    int pos = 0, zaehler = 0;

    enum { PUF = 4096 };
    static short puf[3][PUF];
    static signed char aus8[2 * PUF];
    static short aus16[PUF];

    // Takte bis zum naechsten Ereignis abarbeiten und den Ton herausschreiben
    auto takten = [&](cycle_count dt) -> bool {
        while (dt > 0) {
            int n = 0;
            for (int c = 0; c < chips; c++) {
                cycle_count d = dt;
                n = sid[c].clock(d, puf[c], PUF);
                if (c == chips - 1) dt = d;
            }
            int m = 0;                       // Ausgabewerte in diesem Durchgang
            for (int i = 0; i < n; i++) {
                int s = 0;
                for (int c = 0; c < chips; c++) s += puf[c][i];
                double v = s * faktor;
                if (ueber > 1) {             // in den Verlauf, jeder ueber-te Wert raus
                    verlauf[pos] = (float)v;
                    pos = pos + 1 == abgriffe ? 0 : pos + 1;
                    if (++zaehler < ueber) continue;
                    zaehler = 0;
                    float acc = 0;
                    int q = pos;
                    for (int k = 0; k < abgriffe; k++) {
                        acc += h[k] * verlauf[q];
                        q = q + 1 == abgriffe ? 0 : q + 1;
                    }
                    v = acc;
                }
                int i2 = m++;
                if (s16) {
                    if (v > 32767) v = 32767;
                    if (v < -32768) v = -32768;
                    aus16[i2] = (short)v;
                } else if (fein) {
                    v /= 256.0;
                    double hi = nearbyint(v);
                    if (hi > 127) hi = 127;
                    if (hi < -127) hi = -127;
                    double lo = nearbyint((v - hi) * 63.0);
                    if (lo > 127) lo = 127;
                    if (lo < -127) lo = -127;
                    aus8[2 * i2] = (signed char)hi;
                    aus8[2 * i2 + 1] = (signed char)lo;
                } else {
                    v /= 256.0;
                    if (v > 127) v = 127;
                    if (v < -127) v = -127;
                    aus8[i2] = (signed char)lrint(v);
                }
            }
            size_t w = s16 ? fwrite(aus16, 2, m, stdout) : fein ? fwrite(aus8, 2, m, stdout)
                                                               : fwrite(aus8, 1, m, stdout);
            if ((int)w != m) return false;   // Leser weg (Leitung zu)
        }
        return true;
    };

    for (;;) {
        // varint: Zyklen seit dem vorigen Datensatz
        unsigned long d = 0;
        int s = 0, c;
        do {
            c = lies_byte();
            if (c < 0) goto ende;
            d |= (unsigned long)(c & 0x7f) << s;
            s += 7;
        } while (c & 0x80);
        int r = lies_byte();
        if (r < 0 || r == 0x7f) {
            if (!takten((cycle_count)d)) return 0;
            goto ende;
        }
        int v = lies_byte();
        if (v < 0) goto ende;
        if (!takten((cycle_count)d)) return 0;
        int chip = (r >> 5) & 3, reg = r & 0x1f;
        if (chip < chips && reg <= 24) sid[chip].write((reg8)reg, (reg8)v);
    }
ende:
    // Nachklang: eine halbe Sekunde (Release, Echo der Filter)
    takten((cycle_count)(cps / 2));
    fflush(stdout);
    return 0;
}
