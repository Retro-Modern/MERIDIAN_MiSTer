/*
 * refmitschnitt - SID-Schreibzugriffe mit libsidplayfp mitschneiden (Referenz)
 * Copyright (c) 2026 retro-modern.net. GPL-3.0-or-later.
 *
 * Eigene sidbuilder-/sidemu-Klasse: jeder write() wird mit dem Zyklus aus dem
 * EventScheduler der Bibliothek protokolliert, Lesezugriffe ($D41B/$D41C)
 * beantwortet ein mitlaufender SIDLite-Chip der Bibliothek.
 *
 * Ausgabe wie "sidkern --text": "zyklus chip reg wert" (reg/wert hex).
 * Der Zyklus zaehlt ab dem Einschalten der emulierten Maschine; die Pruefung
 * richtet die Stroeme selbst aufeinander aus.
 *
 * Aufruf: refmitschnitt DATEI.sid LIED SEKUNDEN
 * Bauen:  siehe pruefen/pruefen.sh (braucht die Quellen von libsidplayfp
 *         3.1.1 fuer die nicht installierten Kopfdateien sidemu.h usw.)
 */
#include <cstdio>
#include <cstdlib>
#include <cstdint>

#include <sidplayfp/sidplayfp.h>
#include <sidplayfp/SidTune.h>
#include <sidplayfp/SidTuneInfo.h>
#include <sidplayfp/SidConfig.h>
#include <sidplayfp/SidInfo.h>
#include <sidplayfp/sidbuilder.h>
#include <sidplayfp/builders/sidlite.h>

#include "sidemu.h"

static uint64_t jetzt = 0;

class MitschnittEmu : public libsidplayfp::sidemu
{
    libsidplayfp::sidemu *innen = nullptr;
    SIDLiteBuilder &lite;
    int chip;

public:
    MitschnittEmu(sidbuilder *b, SIDLiteBuilder &l, int nr) : sidemu(b), lite(l), chip(nr) {}

    bool lock(libsidplayfp::EventScheduler *s) override
    {
        if (!sidemu::lock(s)) return false;
        innen = lite.lock(s, SidConfig::MOS6581, false);
        return innen != nullptr;
    }
    void unlock() override
    {
        if (innen) { lite.unlock(innen); innen = nullptr; }
        sidemu::unlock();
    }
    /* Lesen wie bei reSIDfp: OSC3/ENV3 vom mitlaufenden SIDLite, Paddles $FF,
     * sonst der letzte Buswert, der nach einer Weile verblasst (SIDLite
     * allein liefert dort immer 0) */
    uint8_t bus = 0;
    uint64_t bus_zeit = 0, bus_ttl = 7424;
    uint8_t read(uint_least8_t adr) override
    {
        uint64_t z = eventScheduler->getTime(libsidplayfp::EVENT_CLOCK_PHI1);
        switch (adr) {
        case 0x19: case 0x1A: bus = 0xFF; break;
        case 0x1B: case 0x1C: bus = innen ? innen->peek(adr) : 0; break;
        default: return z - bus_zeit <= bus_ttl ? bus : 0;
        }
        bus_zeit = z;
        return bus;
    }
    void write(uint_least8_t adr, uint8_t wert) override
    {
        uint64_t z = eventScheduler->getTime(libsidplayfp::EVENT_CLOCK_PHI1);
        bus = wert;
        bus_zeit = z;
        if (adr <= 24) printf("%llu %d %02X %02X\n", (unsigned long long)z, chip, adr, wert);
        if (innen) innen->poke(adr, wert);
    }
    void reset(uint8_t) override { if (innen) innen->reset(); }
    void clock() override
    {
        jetzt = eventScheduler->getTime(libsidplayfp::EVENT_CLOCK_PHI1);
        if (innen) { innen->clock(); innen->bufferpos(0); }
    }
    void model(SidConfig::sid_model_t m, bool d) override
    {
        bus_ttl = m == SidConfig::MOS8580 ? 663552 : 7424;
        if (innen) innen->model(m, d);
    }
    void sampling(float sf, float of, SidConfig::sampling_method_t me) override { if (innen) innen->sampling(sf, of, me); }
};

class MitschnittBuilder : public sidbuilder
{
    SIDLiteBuilder lite{"lite"};
    int naechster = 0;

protected:
    libsidplayfp::sidemu *create() override
    {
        if (usedDevices() == 0) naechster = 0;
        return new MitschnittEmu(this, lite, naechster++);
    }
    const char *getCredits() const override { return "Mitschnitt"; }

public:
    MitschnittBuilder() : sidbuilder("Mitschnitt") {}
    ~MitschnittBuilder() override { remove(); }
};

int main(int argc, char **argv)
{
    if (argc < 4) { fprintf(stderr, "Aufruf: refmitschnitt DATEI.sid LIED SEKUNDEN\n"); return 1; }
    SidTune tune(argv[1]);
    if (!tune.getStatus()) { fprintf(stderr, "refmitschnitt: %s\n", tune.statusString()); return 2; }
    tune.selectSong(atoi(argv[2]));
    double sek = atof(argv[3]);

    sidplayfp spieler;
    /* Fehlersuche: Befehlsspur der Referenz-CPU in die Datei $REF_SPUR */
    if (const char *spur = getenv("REF_SPUR")) spieler.debug(true, fopen(spur, "w"));
    MitschnittBuilder baumeister;
    SidConfig cfg;
    cfg.sidEmulation = &baumeister;
    cfg.frequency = 48000;
    cfg.powerOnDelay = 0;
    cfg.defaultC64Model = SidConfig::PAL;
    cfg.defaultSidModel = SidConfig::MOS6581;
    if (!spieler.config(cfg)) { fprintf(stderr, "refmitschnitt: %s\n", spieler.error()); return 1; }
    if (!spieler.load(&tune)) { fprintf(stderr, "refmitschnitt: %s\n", spieler.error()); return 1; }

    const SidTuneInfo *ti = tune.getInfo();
    bool ntsc = ti->clockSpeed() == SidTuneInfo::CLOCK_NTSC;
    double zps = ntsc ? 1022727.0 : 985248.0;
    printf("# start %llu %s\n", (unsigned long long)jetzt, ntsc ? "NTSC" : "PAL");
    uint64_t anfang = jetzt;
    uint64_t ende = anfang + (uint64_t)(sek * zps);
    while (jetzt < ende) {
        if (spieler.play(2000) < 0) { printf("# halt %s\n", spieler.error()); break; }
    }
    printf("# ende %llu\n", (unsigned long long)jetzt);
    return 0;
}
