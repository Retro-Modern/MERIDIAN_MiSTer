// Simulation des MERIDIAN-Kerns mit Verilator.
//
//   obj_dir/meridian_sim <sekunden> <ordner> [pal] [bilder...]
//
// Schreibt die angegebenen Bilder als PPM (640x240 Punkte) und meldet
// Bild- und Zeilenfrequenz. Mit MERIDIAN_SPUR=n (ab MERIDIAN_SPUR_AB)
// werden Buszyklen der CPU ausgegeben.
//
// MERIDIAN_TIPPEN="text" tippt ab Bild MERIDIAN_TIPP_AB (Standard 50) mit
// deutschem PS/2-Layout. Zeilenumbruch oder \n = Return, Sondertasten in
// geschweiften Klammern: {HOCH} {RUNTER} {LINKS} {RECHTS} {POS1} {ENTF}
// {RUECK} {CLR} {EINFG} {ESC} {STRG1}..{STRG9}.
//
// MERIDIAN_MENUE=datei.mer laedt ab Bild MERIDIAN_MENUE_AB (Standard 60)
// wie aus dem MiSTer-Menue (ioctl): ein Byte alle MERIDIAN_MENUE_ABSTAND
// Takte (Standard 6), beachtet ioctl_wait. MERIDIAN_MENUE_INDEX=2 laedt die
// Datei als Modul (*.MOD, Menue-Eintrag 2), sonst als Programm (1).
// MERIDIAN_MODUL_AUS=1: Menue-Schalter "Modulstart: aus";
// MERIDIAN_MODUL_RAUS=n: "Modul auswerfen" in Bild n.
//
// MERIDIAN_MAUS="bild:dx:dy:tasten[:rad];..." spielt Mausereignisse ein (dy
// positiv = nach oben, wie PS/2). Die Uhr wird in Bild 2 gestellt, auf die
// Ortszeit des Macs oder MERIDIAN_RTC="JJJJ-MM-TT hh:mm:ss".
//
// MERIDIAN_DRAHT=datei blendet das DDR3-Fenster von DRAHT (64 KB, Bank $FD)
// aus einer Datei ein (mmap): tools/draht.py --datei datei antwortet darauf
// wie auf dem MiSTer.
//
// MERIDIAN_DISK0/1/2=image haengt Images in die Laufwerke von TRUHE (wie das
// Rahmenwerk des MiSTer); geschriebene Bloecke landen am Ende in der Datei.
//
// MERIDIAN_SENDEN=datei.mer legt ab Bild MERIDIAN_SENDEN_AB (Standard 60)
// ein Programm ins nachgebildete DDR3-Postfach, wie tools/senden.py es auf
// dem MiSTer tut.
//
// MERIDIAN_TON=datei.raw schneidet den Ton von ORGEL mit: Stereo, 16 Bit mit
// Vorzeichen, 48 kHz (ffmpeg -f s16le -ar 48000 -ac 2 -i datei.raw).

#include "Vmeridian_core.h"
#include "verilated.h"

#include <cstdio>
#include <cstdlib>
#include <set>
#include <string>
#include <vector>
#include <deque>
#include <cstring>
#include <ctime>
#include <fcntl.h>
#include <sys/mman.h>
#include <unistd.h>

// Ein Tastendruck: Scancode, E0, Umschalt, Strg
struct Taste { int code, e0, umsch, strg; };

static bool zeichen_taste(unsigned char c, Taste& t) {
    static const char* klein = "abcdefghijklmnopqrstuvwxyz";
    static const int code_bst[26] = {0x1C,0x32,0x21,0x23,0x24,0x2B,0x34,0x33,0x43,0x3B,0x42,0x4B,0x3A,
                                     0x31,0x44,0x4D,0x15,0x2D,0x1B,0x2C,0x3C,0x2A,0x1D,0x22,0x1A,0x35};  // deutsch: y und z getauscht
    static const int code_zif[10] = {0x45,0x16,0x1E,0x26,0x25,0x2E,0x36,0x3D,0x3E,0x46};
    t = {0, 0, 0, 0};
    if (c >= 'a' && c <= 'z') { t.code = code_bst[c - 'a']; return true; }
    if (c >= 'A' && c <= 'Z') { t.code = code_bst[c - 'A']; t.umsch = 1; return true; }
    if (c >= '0' && c <= '9') { t.code = code_zif[c - '0']; return true; }
    switch (c) {
        case ' ': t.code = 0x29; return true;
        case '\n': t.code = 0x5A; return true;
        case '.': t.code = 0x49; return true;
        case ',': t.code = 0x41; return true;
        case '-': t.code = 0x4A; return true;
        case ':': t.code = 0x49; t.umsch = 1; return true;
        case '?': t.code = 0x4E; t.umsch = 1; return true;
        case '!': t.code = 0x16; t.umsch = 1; return true;
        case '(': t.code = 0x3E; t.umsch = 1; return true;
        case ')': t.code = 0x46; t.umsch = 1; return true;
        case '/': t.code = 0x3D; t.umsch = 1; return true;
        case '=': t.code = 0x45; t.umsch = 1; return true;
        case '+': t.code = 0x5B; return true;
        case '#': t.code = 0x5D; return true;
        case '"': t.code = 0x1E; t.umsch = 1; return true;
        case ';': t.code = 0x41; t.umsch = 1; return true;
        case '*': t.code = 0x5B; t.umsch = 1; return true;
        case '$': t.code = 0x25; t.umsch = 1; return true;
        case '%': t.code = 0x2E; t.umsch = 1; return true;
        case '&': t.code = 0x36; t.umsch = 1; return true;
        case '<': t.code = 0x61; return true;
        case '>': t.code = 0x61; t.umsch = 1; return true;
        case '_': t.code = 0x4A; t.umsch = 1; return true;
        case '\'': t.code = 0x5D; t.umsch = 1; return true;
        case '^': t.code = 0x0E; return true;
        // Umlaute (Latin-1, aus UTF-8 umgesetzt)
        case 0xE4: t.code = 0x52; return true;          // ä
        case 0xF6: t.code = 0x4C; return true;          // ö
        case 0xFC: t.code = 0x54; return true;          // ü
        case 0xC4: t.code = 0x52; t.umsch = 1; return true;
        case 0xD6: t.code = 0x4C; t.umsch = 1; return true;
        case 0xDC: t.code = 0x54; t.umsch = 1; return true;
        case 0xDF: t.code = 0x4E; return true;          // ß
    }
    return false;
}

static std::deque<Taste> tipp_folge(const char* text) {
    std::deque<Taste> f;
    for (const char* p = text; *p; p++) {
        Taste t;
        if (p[0] == '\\' && p[1] == 'n') { zeichen_taste('\n', t); f.push_back(t); p++; continue; }
        if (*p == '{') {
            const char* e = strchr(p, '}');
            std::string w(p + 1, e - p - 1);
            t = {0, 1, 0, 0};
            if (w == "HOCH") t.code = 0x75; else if (w == "RUNTER") t.code = 0x72;
            else if (w == "LINKS") t.code = 0x6B; else if (w == "RECHTS") t.code = 0x74;
            else if (w == "POS1") t.code = 0x6C; else if (w == "ENTF") t.code = 0x71;
            else if (w == "EINFG") t.code = 0x70;
            else if (w == "CLR") { t.code = 0x6C; t.umsch = 1; }
            else if (w == "RUECK") { t = {0x66, 0, 0, 0}; }
            else if (w == "ESC") { t = {0x76, 0, 0, 0}; }
            else if (w.rfind("STRG", 0) == 0) { zeichen_taste(w[4], t); t.strg = 1; }
            f.push_back(t);
            p = e;
            continue;
        }
        unsigned char c = (unsigned char)*p;
        if (c == 0xC3 && p[1]) { c = (unsigned char)p[1] + 0x40; p++; }   // UTF-8 -> Latin-1
        if (zeichen_taste(c, t)) f.push_back(t);
    }
    return f;
}

// SDRAM-Modell fuer den Zusatzspeicher: wird an jeder fallenden Flanke des
// 48-MHz-Takts aufgerufen (dort hat das SDRAM wegen des invertierten Takts
// seine steigende Flanke). CAS-Latenz 2, Burst 1, prueft die Zeitvorgaben.
struct Sdram {
    std::vector<uint16_t> mem;
    bool aktiv[4] = {false, false, false, false};
    int zeile[4] = {0, 0, 0, 0};
    long t_act[4] = {0, 0, 0, 0};
    long n = 0, lese_bei = -1, t_ref = -100;
    uint16_t lese_wert = 0;
    bool modus = false;
    long fehler = 0, lesen = 0, schreiben = 0, auffr = 0;
    Sdram() : mem(1 << 23) { for (size_t i = 0; i < mem.size(); i++) mem[i] = (uint16_t)(i * 2654435761u >> 16); }
    void meldung(const char* text) { if (fehler++ < 10) printf("SDRAM-Fehler (Flanke %ld): %s\n", n, text); }
    template <class T> void flanke(T* t) {
        n++;
        if (n == lese_bei) t->sd_dq_i = lese_wert;
        int cmd = (t->sd_ncs << 3) | (t->sd_nras << 2) | (t->sd_ncas << 1) | t->sd_nwe;
        int ba = t->sd_ba, a = t->sd_a;
        switch (cmd) {
            case 0b0011:                                    // ACTIVE
                if (aktiv[ba]) meldung("ACTIVE auf offene Bank");
                if (n - t_ref < 5) meldung("ACTIVE zu frueh nach REFRESH");
                aktiv[ba] = true; zeile[ba] = a & 0x1FFF; t_act[ba] = n; break;
            case 0b0101: case 0b0100: {                     // READ / WRITE
                if (!modus) meldung("Zugriff vor LOAD MODE");
                if (!aktiv[ba]) { meldung("READ/WRITE auf geschlossene Bank"); break; }
                if (n - t_act[ba] < 2) meldung("tRCD verletzt");
                uint32_t w = ((uint32_t)zeile[ba] << 11) | (ba << 9) | (a & 0x1FF);
                w &= (1u << 23) - 1;
                if (cmd == 0b0101) { lese_wert = mem[w]; lese_bei = n + 3; lesen++; }
                else {
                    if (!t->sd_dq_oe) meldung("WRITE ohne Daten");
                    uint16_t d = t->sd_dq_o;
                    // wie auf dem MiSTer-Modul: DQML an A11, DQMH an A12
                    bool dqml = (a >> 11) & 1, dqmh = (a >> 12) & 1;
                    if (!dqml) mem[w] = (mem[w] & 0xFF00) | (d & 0x00FF);
                    if (!dqmh) mem[w] = (mem[w] & 0x00FF) | (d & 0xFF00);
                    schreiben++;
                }
                if (a & 0x400) aktiv[ba] = false;            // automatisch vorladen
                break;
            }
            case 0b0010:                                    // PRECHARGE
                if (a & 0x400) for (int b = 0; b < 4; b++) aktiv[b] = false;
                else aktiv[ba] = false;
                break;
            case 0b0001:                                    // AUTO REFRESH
                for (int b = 0; b < 4; b++) if (aktiv[b]) meldung("REFRESH bei offener Bank");
                if (n - t_ref < 5) meldung("tRFC verletzt");
                t_ref = n; auffr++; break;
            case 0b0000:                                    // LOAD MODE
                if ((a & 0xFFF) != 0x220) meldung("unerwarteter Modus");
                modus = true; break;
            default: break;
        }
    }
};

static const int W = 640, H = 240;
static const uint64_t TAKT = 24000000ULL;

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    if (argc < 3) {
        fprintf(stderr, "aufruf: %s <sekunden> <ordner> [pal] [bilder...]\n", argv[0]);
        return 1;
    }
    double sekunden = atof(argv[1]);
    std::string ordner = argv[2];
    int pal = argc > 3 ? atoi(argv[3]) : 0;
    std::set<int> bilder;
    for (int i = 4; i < argc; i++) bilder.insert(atoi(argv[i]));
    long spur = getenv("MERIDIAN_SPUR") ? atol(getenv("MERIDIAN_SPUR")) : 0;
    long spur_ab = getenv("MERIDIAN_SPUR_AB") ? atol(getenv("MERIDIAN_SPUR_AB")) : 0;
    // MERIDIAN_SCHREIBSPUR=von-bis (hex, 24 Bit): Schreibzugriffe der CPU dort zeigen
    unsigned long sspur_von = 1, sspur_bis = 0;
    if (getenv("MERIDIAN_SCHREIBSPUR")) sscanf(getenv("MERIDIAN_SCHREIBSPUR"), "%lx-%lx", &sspur_von, &sspur_bis);
    std::deque<Taste> tippen = tipp_folge(getenv("MERIDIAN_TIPPEN") ? getenv("MERIDIAN_TIPPEN") : "");
    int tipp_ab = getenv("MERIDIAN_TIPP_AB") ? atoi(getenv("MERIDIAN_TIPP_AB")) : 50;
    // Ereignisse: (Takt, Code, E0, gedrueckt)
    struct Ereignis { uint64_t t; int code, e0, gedr; };
    std::deque<Ereignis> ereignisse;
    uint16_t ps2 = 0;

    // DDR3-Postfach (physisch $3E000000 = Wortadresse $07C00000)
    const uint32_t POSTFACH = 0x07C00000;
    std::vector<uint8_t> ddr(512 * 1024, 0);
    // mehrere Dateien mit Komma getrennt, im Abstand von 12 Bildern
    std::vector<std::vector<uint8_t>> sendungen;
    if (getenv("MERIDIAN_SENDEN")) {
        std::string liste = getenv("MERIDIAN_SENDEN");
        size_t a = 0;
        while (a <= liste.size()) {
            size_t e = liste.find(',', a);
            if (e == std::string::npos) e = liste.size();
            std::vector<uint8_t> d;
            FILE* f = fopen(liste.substr(a, e - a).c_str(), "rb");
            if (f) { int c; while ((c = fgetc(f)) != EOF) d.push_back(c); fclose(f); }
            if (!d.empty()) sendungen.push_back(d);
            a = e + 1;
        }
    }
    std::vector<uint8_t> menue;
    if (getenv("MERIDIAN_MENUE")) {
        FILE* f = fopen(getenv("MERIDIAN_MENUE"), "rb");
        if (f) { int c; while ((c = fgetc(f)) != EOF) menue.push_back(c); fclose(f); }
    }
    int menue_ab = getenv("MERIDIAN_MENUE_AB") ? atoi(getenv("MERIDIAN_MENUE_AB")) : 60;
    int menue_abstand = getenv("MERIDIAN_MENUE_ABSTAND") ? atoi(getenv("MERIDIAN_MENUE_ABSTAND")) : 6;
    size_t m_pos = 0;
    int m_pause = 0;
    bool m_an = false, m_fertig = false;
    long m_gewartet = 0;

    // Laufwerke: Images wie vom Rahmenwerk
    struct Disk { std::vector<uint8_t> d; std::string pfad; bool da = false, geaendert = false; };
    Disk disks[3];
    for (int n = 0; n < 3; n++) {
        char var[20]; snprintf(var, sizeof var, "MERIDIAN_DISK%d", n);
        if (getenv(var)) {
            disks[n].pfad = getenv(var);
            FILE* f = fopen(disks[n].pfad.c_str(), "rb");
            if (f) { int c; while ((c = fgetc(f)) != EOF) disks[n].d.push_back(c); fclose(f); }
            disks[n].da = true;
        }
    }
    int sd_zustand = 0, sd_n = 0, sd_i = 0, sd_warte = 0, sd_meldung = 0, sd_len = 512;
    bool sd_schreiben = false;
    uint32_t sd_block = 0;
    long sd_auftraege = 0, sd_bloecke = 0;

    std::vector<uint8_t> senden;
    size_t naechste = 0;
    int senden_ab = getenv("MERIDIAN_SENDEN_AB") ? atoi(getenv("MERIDIAN_SENDEN_AB")) : 60;
    int nochmal_ab = getenv("MERIDIAN_SENDEN_NOCHMAL") ? atoi(getenv("MERIDIAN_SENDEN_NOCHMAL")) : -1;
    bool gesendet = false;
    std::deque<std::pair<uint64_t, uint32_t>> ddr_antworten;   // (Takt, Wortadresse)
    // DRAHT-Fenster: 64 KB ab Wort $07C20000, auf Wunsch aus einer Datei
    const uint32_t FENSTER = 0x07C20000;
    uint8_t* fenster = nullptr;
    if (getenv("MERIDIAN_DRAHT")) {
        int fd = open(getenv("MERIDIAN_DRAHT"), O_RDWR | O_CREAT, 0644);
        if (fd >= 0 && ftruncate(fd, 65536) == 0)
            fenster = (uint8_t*)mmap(nullptr, 65536, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
        if (fenster == MAP_FAILED) fenster = nullptr;
    }
    static uint8_t fenster_ram[65536];
    if (!fenster) fenster = fenster_ram;

    FILE* ton = getenv("MERIDIAN_TON") ? fopen(getenv("MERIDIAN_TON"), "wb") : nullptr;
    long ton_werte = 0;

    Sdram sdram;
    Vmeridian_core* top = new Vmeridian_core;
    top->pal = pal;
    top->ps2_key = 0;
    top->ps2_mouse = 0;
    top->ps2_mouse_ext = 0;
    top->rtc[0] = top->rtc[1] = top->rtc[2] = 0;
    struct MausEreignis { int bild, dx, dy, tasten, rad; };
    std::deque<MausEreignis> maus;
    if (getenv("MERIDIAN_MAUS")) {
        std::string l = getenv("MERIDIAN_MAUS");
        size_t a = 0;
        while (a < l.size()) {
            size_t e = l.find(';', a);
            if (e == std::string::npos) e = l.size();
            MausEreignis m = {0, 0, 0, 0, 0};
            sscanf(l.substr(a, e - a).c_str(), "%d:%d:%d:%d:%d", &m.bild, &m.dx, &m.dy, &m.tasten, &m.rad);
            maus.push_back(m);
            a = e + 1;
        }
    }
    bool rtc_gestellt = false;
    top->joy0 = 0;
    top->joy1 = 0;
    top->layout_mac = 0;
    top->ioctl_download = 0;
    top->ioctl_index = getenv("MERIDIAN_MENUE_INDEX") ? atoi(getenv("MERIDIAN_MENUE_INDEX")) : 1;
    top->modul_aus = getenv("MERIDIAN_MODUL_AUS") ? 1 : 0;
    top->modul_raus = 0;
    int raus_ab = getenv("MERIDIAN_MODUL_RAUS") ? atoi(getenv("MERIDIAN_MODUL_RAUS")) : -1;
    top->ioctl_wr = 0;
    top->ioctl_addr = 0;
    top->ioctl_dout = 0;
    top->ddr_busy = 0;
    top->ddr_dout = 0;
    top->ddr_dout_ready = 0;
    top->sd_dq_i = 0;
    top->img_mounted = 0;
    top->img_readonly = 0;
    top->img_size = 0;
    top->sd_ack = 0;
    top->sd_buff_addr = 0;
    top->sd_buff_dout = 0;
    top->sd_buff_wr = 0;
    top->reset = 1;
    top->clk = 0;
    top->clk48 = 0;
    top->eval();

    std::vector<uint8_t> bild(W * H * 3, 0);
    int x = 0, y = 0, frame = 0;
    int prev_hbl = 1, prev_vbl = 1, prev_hs = 0, prev_vs = 0, hs_pulse = 0;
    uint64_t letzte_vs = 0, vs_abstand = 0;
    long zyklen = 0;

    uint64_t takte = (uint64_t)(sekunden * TAKT);
    for (uint64_t t = 0; t < takte; t++) {
        if (t == 50) top->reset = 0;

        // Tippen: ab dem Startbild alle Tasten als Ereignisfolge einplanen
        if (frame == tipp_ab && !tippen.empty() && ereignisse.empty()) {
            uint64_t z = t;
            const uint64_t MS = getenv("MERIDIAN_TIPP_MS") ? atoi(getenv("MERIDIAN_TIPP_MS")) : 30;
            const uint64_t H = TAKT * MS / 1000;   // halten, dann Pause
            for (auto& k : tippen) {
                if (k.umsch) { ereignisse.push_back({z, 0x12, 0, 1}); z += H / 2; }
                if (k.strg)  { ereignisse.push_back({z, 0x14, 0, 1}); z += H / 2; }
                ereignisse.push_back({z, k.code, k.e0, 1}); z += H;
                ereignisse.push_back({z, k.code, k.e0, 0}); z += H / 2;
                if (k.strg)  { ereignisse.push_back({z, 0x14, 0, 0}); z += H / 2; }
                if (k.umsch) { ereignisse.push_back({z, 0x12, 0, 0}); z += H / 2; }
                z += H;
            }
            tippen.clear();
        }
        // Uhr stellen (wie der MiSTer beim Start des Cores): BCD-Ortszeit
        if (frame == 2 && !rtc_gestellt) {
            rtc_gestellt = true;
            struct tm tm;
            time_t jetzt = time(nullptr);
            localtime_r(&jetzt, &tm);
            if (getenv("MERIDIAN_RTC")) {
                memset(&tm, 0, sizeof tm);
                sscanf(getenv("MERIDIAN_RTC"), "%d-%d-%d %d:%d:%d", &tm.tm_year, &tm.tm_mon, &tm.tm_mday,
                       &tm.tm_hour, &tm.tm_min, &tm.tm_sec);
                tm.tm_year -= 1900; tm.tm_mon -= 1;
                tm.tm_isdst = -1;                           // Sommerzeit selbst bestimmen
                mktime(&tm);                                // ergaenzt den Wochentag
            }
            auto bcd = [](int v) { return (uint32_t)(((v / 10) % 10) << 4 | (v % 10)); };
            top->rtc[0] = bcd(tm.tm_sec) | bcd(tm.tm_min) << 8 | bcd(tm.tm_hour) << 16 | bcd(tm.tm_mday) << 24;
            top->rtc[1] = bcd(tm.tm_mon + 1) | bcd(tm.tm_year) << 8 | (uint32_t)tm.tm_wday << 16 | 0x40u << 24;
            top->rtc[2] = 1;
        }
        // Mausereignisse
        if (!maus.empty() && frame >= maus.front().bild) {
            auto& m = maus.front();
            uint32_t st = 0x08 | (m.tasten & 7) | (m.dx < 0 ? 0x10 : 0) | (m.dy < 0 ? 0x20 : 0);
            uint32_t kipp = (top->ps2_mouse ^ (1u << 24)) & (1u << 24);
            top->ps2_mouse = kipp | ((uint32_t)(m.dy & 0xFF) << 16) | ((uint32_t)(m.dx & 0xFF) << 8) | st;
            top->ps2_mouse_ext = (uint8_t)m.rad;
            maus.pop_front();
        }
        if (!ereignisse.empty() && t >= ereignisse.front().t) {
            auto& e = ereignisse.front();
            ps2 = (ps2 ^ 0x400) & 0x400;
            ps2 |= (e.gedr << 9) | (e.e0 << 8) | e.code;
            top->ps2_key = ps2;
            ereignisse.pop_front();
        }

        // Programm ins Postfach legen: Daten, Kopf, zuletzt die Folgenummer
        if (naechste < sendungen.size() && frame == senden_ab + (int)naechste * 12) {
            senden = sendungen[naechste++];
            if (ddr.size() < senden.size() + 64) ddr.resize(senden.size() + 64, 0);
            for (size_t i = 16; i < senden.size(); i++) ddr[24 + i - 16] = senden[i];
            for (int i = 0; i < 16; i++) ddr[8 + i] = senden[i];
            ddr[0]++;
            gesendet = true;
            printf("Bild %d: Datei %zu ins Postfach gelegt (%zu Bytes)\n", frame, naechste, senden.size() - 16);
        }
        if (gesendet && frame == nochmal_ab) {           // noch einmal, waehrend es laeuft
            ddr[0]++;
            nochmal_ab = -1;
            printf("Bild %d: Programm erneut geschickt\n", frame);
        }

        // Laufwerke: Images anmelden (Bild 3), dann Auftraege beantworten
        top->img_mounted = 0;
        top->sd_buff_wr = 0;
        if (frame == 3 && sd_meldung < 3) {
            int n = sd_meldung++;
            if (disks[n].da) {
                top->img_mounted = 1 << n;
                top->img_size = disks[n].d.size();
                top->img_readonly = 0;
            }
        }
        switch (sd_zustand) {
        case 0:
            if (top->sd_rd || top->sd_wr) {
                int bits = top->sd_rd | top->sd_wr;
                sd_n = (bits & 1) ? 0 : (bits & 2) ? 1 : 2;
                sd_schreiben = (top->sd_wr >> sd_n) & 1;
                sd_block = top->sd_lba;
                sd_len = (top->sd_blk_cnt + 1) * 512;   // mehrere Bloecke je Auftrag
                sd_warte = 40;
                sd_zustand = 1;
                sd_auftraege++;
                sd_bloecke += top->sd_blk_cnt + 1;
            }
            break;
        case 1:
            if (--sd_warte == 0) {
                top->sd_ack = 1 << sd_n;
                top->sd_buff_addr = 0;
                sd_i = 0; sd_warte = 0;
                sd_zustand = sd_schreiben ? 3 : 2;
            }
            break;
        case 2:                                         // Image -> Puffer
            if (sd_warte == 0) {
                size_t p = (size_t)sd_block * 512 + sd_i;
                top->sd_buff_addr = sd_i;
                top->sd_buff_dout = p < disks[sd_n].d.size() ? disks[sd_n].d[p] : 0;
                top->sd_buff_wr = 1;
                sd_warte = 3;
                if (++sd_i == sd_len) sd_zustand = 4;
            } else sd_warte--;
            break;
        case 3:                                         // Puffer -> Image
            if (sd_warte == 0) { top->sd_buff_addr = sd_i; sd_warte = 3; }
            else if (--sd_warte == 0) {
                size_t p = (size_t)sd_block * 512 + sd_i;
                // wie der MiSTer: nur der Speicherstand (Laufwerk 0) waechst
                if (p >= disks[sd_n].d.size() && sd_n == 0) disks[sd_n].d.resize(p + 1, 0);
                if (p < disks[sd_n].d.size()) {
                    disks[sd_n].d[p] = top->sd_buff_din;
                    disks[sd_n].geaendert = true;
                }
                if (++sd_i == sd_len) sd_zustand = 4;
            }
            break;
        case 4:
            top->sd_ack = 0;
            sd_zustand = 0;
            break;
        }

        // Modul auswerfen (Menue-Taste, ein paar Bilder lang)
        top->modul_raus = (raus_ab >= 0 && frame >= raus_ab && frame < raus_ab + 3);

        // Laden aus dem Menue (ioctl), wartet wie der MiSTer auf ioctl_wait
        top->ioctl_wr = 0;
        if (!menue.empty() && frame >= menue_ab && !m_fertig) {
            if (!m_an) { top->ioctl_download = 1; m_an = true; m_pause = 20; }
            else if (m_pause > 0) m_pause--;
            else if (m_pos < menue.size()) {
                if (top->ioctl_wait) m_gewartet++;
                else {
                    top->ioctl_addr = m_pos;
                    top->ioctl_dout = menue[m_pos];
                    top->ioctl_wr = 1;
                    m_pos++;
                    m_pause = menue_abstand - 1;
                }
            }
            else {
                top->ioctl_download = 0;
                m_fertig = true;
                printf("Bild %d: Menue-Laden fertig (%zu Bytes, %ld Takte gewartet)\n", frame, menue.size(), m_gewartet);
            }
        }

        top->clk = 0;                                   // 24 MHz faellt, 48 MHz steigt
        top->clk48 = 1;
        top->eval();
        sdram.flanke(top);                              // 48 MHz faellt
        top->clk48 = 0;
        top->eval();

        // DDR3: Anfrage wird angenommen (nie beschaeftigt), Antwort 8 Takte spaeter
        top->ddr_dout_ready = 0;
        if (!ddr_antworten.empty() && t >= ddr_antworten.front().first) {
            uint32_t wa = ddr_antworten.front().second;
            if (wa >= FENSTER && wa < FENSTER + 8192) {
                uint64_t d = 0;
                for (int i = 7; i >= 0; i--) d = (d << 8) | fenster[(wa - FENSTER) * 8 + i];
                top->ddr_dout = d;
                top->ddr_dout_ready = 1;
                ddr_antworten.pop_front();
            } else {
            uint32_t w = wa - POSTFACH;
            uint64_t d = 0;
            for (int i = 7; i >= 0; i--) d = (d << 8) | ((w * 8 + i < ddr.size()) ? ddr[w * 8 + i] : 0);
            top->ddr_dout = d;
            top->ddr_dout_ready = 1;
            ddr_antworten.pop_front();
            }
        }
        if (top->ddr_rd) ddr_antworten.push_back({t + 8, top->ddr_addr});
        if (top->ddr_we && top->ddr_addr >= FENSTER && top->ddr_addr < FENSTER + 8192) {
            for (int i = 0; i < 8; i++)
                if ((top->ddr_be >> i) & 1)
                    fenster[(top->ddr_addr - FENSTER) * 8 + i] = (uint8_t)(top->ddr_din >> (8 * i));
        }

        if (top->dbg_ce && zyklen >= spur_ab && zyklen < spur_ab + spur) {
            printf("%6ld  %06x\n", zyklen, top->dbg_addr);
        }
        if (top->dbg_we && top->dbg_addr >= sspur_von && top->dbg_addr <= sspur_bis)
            printf("Bild %d (%ld): W %06x = %02x\n", frame, zyklen, top->dbg_addr, top->dbg_dout);
        if (top->dbg_ce) zyklen++;

        if (top->ce_pix) {
            int hbl = top->hblank, vbl = top->vblank;
            if (!hbl && !vbl) {
                if (x < W && y < H) {
                    uint8_t* p = &bild[(y * W + x) * 3];
                    p[0] = top->r; p[1] = top->g; p[2] = top->b;
                }
                x++;
            }
            if (hbl && !prev_hbl) { if (!vbl) y++; x = 0; }
            if (vbl && !prev_vbl) {
                if (bilder.count(frame)) {
                    char name[256];
                    snprintf(name, sizeof name, "%s/bild_%04d.ppm", ordner.c_str(), frame);
                    FILE* f = fopen(name, "wb");
                    fprintf(f, "P6\n%d %d\n255\n", W, H);
                    fwrite(bild.data(), 1, bild.size(), f);
                    fclose(f);
                }
                if (frame == 2) printf("Bild 2: %d sichtbare Zeilen\n", y);
                frame++;
                y = 0;
            }
            if (top->hsync && !prev_hs) hs_pulse++;
            if (top->vsync && !prev_vs) {
                if (letzte_vs) vs_abstand = t - letzte_vs;
                letzte_vs = t;
            }
            prev_hbl = hbl; prev_vbl = vbl;
            prev_hs = top->hsync; prev_vs = top->vsync;
        }

        if (ton && t % 500 == 0) {                       // 24 MHz / 500 = 48 kHz
            int16_t w[2] = {(int16_t)top->audio_l, (int16_t)top->audio_r};
            fwrite(w, 2, 2, ton);
            ton_werte++;
        }

        top->clk = 1;                                   // beide steigen
        top->clk48 = 1;
        top->eval();
        sdram.flanke(top);
        top->clk48 = 0;
        top->eval();
    }
    if (ton) { fclose(ton); printf("Ton: %ld Werte (%.2f s)\n", ton_werte, ton_werte / 48000.0); }

    printf("Bilder: %d, CPU-Buszyklen: %ld (%.2f MHz)\n", frame, zyklen, zyklen / sekunden / 1e6);
    if (vs_abstand)
        printf("Bildfrequenz: %.3f Hz, Zeilenfrequenz: %.1f Hz\n",
               (double)TAKT / vs_abstand, hs_pulse / sekunden);
    if (sdram.lesen || sdram.schreiben || sdram.fehler)
        printf("SDRAM: %ld gelesen, %ld geschrieben, %ld aufgefrischt, %ld Fehler\n",
               sdram.lesen, sdram.schreiben, sdram.auffr, sdram.fehler);
    for (int n = 0; n < 3; n++)
        if (disks[n].geaendert) {
            FILE* f = fopen(disks[n].pfad.c_str(), "wb");
            if (f) { fwrite(disks[n].d.data(), 1, disks[n].d.size(), f); fclose(f); }
        }
    if (sd_auftraege) printf("Laufwerke: %ld Auftraege, %ld Bloecke\n", sd_auftraege, sd_bloecke);
    top->final();
    delete top;
    return 0;
}
