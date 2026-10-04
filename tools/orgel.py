#!/usr/bin/env python3
"""Klaenge, Musik und Tabellen fuer das Vorfuehrprogramm ORGEL (Etappe 6).

Samples: die ElevenLabs-Aufnahmen aus klaenge/roh/*.mp3 werden auf ihre
  Abspielrate gebracht, zugeschnitten, ausgeblendet, auf 8 Bit mit
  Vorzeichen normalisiert und hintereinander ab $01:0000 abgelegt
  -> programme/daten/orgel_klaenge.mer

Musik: ein kleiner Tracker. Er rechnet fuer jeden Takt des 50-Hz-Spielers
  aus, welchen Wert jedes ORGEL-Register haben soll (Arpeggio, Pulsbreite,
  Vibrato, Filterhuellkurve des Basses ...), und schreibt nur die
  Aenderungen in einen Strom ab $02:0000:
     3 Byte  Adresse der Schleifenmarke
     dann je Takt: Register, Wert, Register, Wert ... $FF
     $FD n   Teil n beginnt (fuer die Anzeige)
     $FE     zurueck zur Schleifenmarke
  -> programme/daten/orgel_musik.mer (und ballett_musik.mer ab $00:4000)

Tabellen fuer die Anzeige -> programme/orgel_daten.inc

    ../.venv/bin/python tools/orgel.py
"""
import math
import os
import struct
import subprocess

import numpy as np

HIER = os.path.dirname(os.path.abspath(__file__))
BASIS = os.path.join(HIER, "..")
ROH = os.path.join(BASIS, "klaenge", "roh")
DATEN = os.path.join(BASIS, "programme", "daten")

TAKT = 1_000_000                    # ORGEL zaehlt in Mikrosekunden
KLANG_ADR = 0x010000
MUSIK_ADR = 0x020000
BALLETT_MUSIK = 0x004000


def freq_reg(hz):
    return min(65535, round(hz * (1 << 24) / TAKT))


def midi_hz(m):
    return 440.0 * 2 ** ((m - 69) / 12)


def schritt(rate):
    return round(rate * 65536 / TAKT)


NAMEN = ["C-", "C#", "D-", "D#", "E-", "F-", "F#", "G-", "G#", "A-", "A#", "B-"]


def note(name):
    """'G#5' -> MIDI-Nummer"""
    ton = name[:-1].replace("-", "")
    return 12 * (int(name[-1]) + 1) + [n.replace("-", "") for n in NAMEN].index(ton)


def mer(lade, daten, auto=False):
    kopf = b"MER\x01" + struct.pack("<I", lade)[:3] + bytes([1 if auto else 0])
    kopf += struct.pack("<I", lade)[:3] + b"\x00" + struct.pack("<I", len(daten))
    return kopf + bytes(daten)


#############################################################  Samples  #####

# Name, Datei, Abspielrate, hoechstens Sekunden, Anzeigename, Saettigung (0 = keine)
SAMPLES = [
    # kick.mp3 ging unter (62 Hz Schwerpunkt); kick_b ist knackiger, und die
    # Saettigung gibt ihr Obertoene, die auch kleine Lautsprecher wiedergeben
    ("kick", "kick_b.mp3", 22050, 0.25, "Kick", 3.0),
    ("snare", "snare_a.mp3", 22050, 0.25, "Snare", 0),
    ("klatsch", "snare_b.mp3", 22050, 0.30, "Clap", 0),
    ("hihat", "hihat.mp3", 22050, 0.10, "Hi-Hat", 0),
    ("becken", "becken.mp3", 16000, 1.00, "Cymbal", 0),
    ("meridian", "meridian.mp3", 16000, 0.70, "MERIDIAN", 0),
    ("orgel", "orgel.mp3", 16000, 0.75, "ORGEL", 0),
]


def lade_sample(datei, rate):
    roh = subprocess.run(["ffmpeg", "-v", "error", "-i", os.path.join(ROH, datei), "-ac", "1",
                          "-ar", str(rate), "-f", "f32le", "-"], capture_output=True, check=True).stdout
    return np.frombuffer(roh, dtype="<f4").astype(float)


def zuschneiden(x, rate, hoechstens, saettigung=0):
    a = np.abs(x)
    spitze = a.max()
    ein = max(0, int(np.argmax(a > 0.02 * spitze)) - int(0.001 * rate))
    x = x[ein:ein + int(hoechstens * rate)].copy()
    a = np.abs(x)
    ende = len(a) - int(np.argmax(a[::-1] > 0.01 * spitze))
    x = x[:ende]
    if saettigung:
        x = np.tanh(saettigung * x / np.abs(x).max())
    n = min(len(x), int(0.005 * rate))
    x[-n:] *= np.linspace(1, 0, n)
    x = x / np.abs(x).max() * 127
    return np.clip(np.round(x), -127, 127).astype(np.int8)


def samples_bauen():
    klaenge = bytearray()
    tab = {}
    for name, datei, rate, dauer, anzeige, satt in SAMPLES:
        s = zuschneiden(lade_sample(datei, rate), rate, dauer, satt)
        # Huellkurve fuer die Pegelanzeige: Spitze je 256-Byte-Block, 0..255
        huelle = [min(255, int(np.abs(s[i:i + 256].astype(int)).max()) * 2) for i in range(0, len(s), 256)]
        tab[name] = dict(start=KLANG_ADR + len(klaenge), laenge=len(s), rate=rate,
                         schritt=schritt(rate), anzeige=anzeige, huelle=huelle)
        klaenge += s.tobytes()
        print(f"  {name:9s} {len(s):6d} Bytes  {rate} Hz  {len(s) / rate * 1000:5.0f} ms")
    assert len(klaenge) <= 0x10000, "Samples passen nicht in Bank 1"
    return klaenge, tab


###########################################################  Musikstueck  ####

TPZ = 6                             # Takte je Zeile: 50 Hz / 6 / 4 Zeilen = 125 BPM
ZPT = 16                            # Zeilen je Takt (Musik)

# Akkorde: Grundton des Basses (MIDI), Arpeggio-Lage um E3-E4
AKKORDE = {
    "Am": (33, [57, 60, 64]),
    "F":  (29, [53, 57, 60]),
    "C":  (36, [60, 64, 67]),
    "G":  (31, [55, 59, 62]),
    "E":  (28, [52, 56, 59]),
}

MEL_A = [   # Am F C G
    [(0, "E5", 6), (6, "D5", 2), (8, "C5", 4), (12, "B4", 2), (14, "C5", 2)],
    [(0, "A4", 8), (8, "C5", 4), (12, "F5", 4)],
    [(0, "E5", 6), (6, "G5", 2), (8, "E5", 4), (12, "D5", 2), (14, "C5", 2)],
    [(0, "D5", 8), (8, "B4", 4), (12, "G4", 4)],
]
MEL_A2 = [  # Am F C G, zweite Fassung fuers Finale
    [(0, "E5", 4), (4, "A5", 4), (8, "G5", 2), (10, "E5", 2), (12, "C5", 4)],
    [(0, "F5", 6), (6, "E5", 2), (8, "C5", 4), (12, "A4", 4)],
    [(0, "G5", 4), (4, "E5", 4), (8, "C5", 4), (12, "E5", 2), (14, "G5", 2)],
    [(0, "D5", 6), (6, "B4", 2), (8, "D5", 2), (10, "E5", 2), (12, "B4", 4)],
]
MEL_B = [   # F G Am Am F G E E
    [(0, "A5", 8), (8, "G5", 4), (12, "F5", 4)],
    [(0, "G5", 6), (6, "F5", 2), (8, "E5", 4), (12, "D5", 4)],
    [(0, "E5", 12), (12, "C5", 2), (14, "D5", 2)],
    [(0, "E5", 4), (4, "A4", 4), (8, "C5", 4), (12, "E5", 4)],
    [(0, "F5", 6), (6, "E5", 2), (8, "F5", 4), (12, "A5", 4)],
    [(0, "G5", 6), (6, "D5", 2), (8, "B4", 4), (12, "D5", 4)],
    [(0, "E5", 8), (8, "G#5", 4), (12, "E5", 4)],
    [(0, "G#4", 4), (4, "B4", 4), (8, "D5", 4), (12, "E5", 4)],
]

# Teile: Name, Akkorde je Takt, Filter (Basis von, bis, Huellkurve, Resonanz)
TEILE = [
    ("Intro",       ["Am", "G"],                                  (10, 80, 250, 12)),
    ("Verse",       ["Am", "F", "C", "G", "Am", "F", "C", "G"],   (40, 40, 380, 10)),
    ("Chorus",      ["F", "G", "Am", "Am", "F", "G", "E", "E"],   (60, 60, 480, 9)),
    ("Filter sweep",["Am", "Am"],                                 (20, 900, 100, 15)),
    ("Finale",      ["Am", "F", "C", "G"],                        (50, 50, 420, 11)),
]
SCHLEIFE_TEIL = 1                   # nach dem Finale zurueck zur Strophe

PAN = [0xFF, 0xF4, 0xFC, 0x4F]      # Bass Mitte, Akkorde links, Melodie, Echo rechts
ECHO_VERZUG = 3 * TPZ               # punktierte Achtel


class Note:
    def __init__(self, start, dauer, art, midi=0, akk=None, laut=None):
        self.start, self.dauer, self.art, self.midi, self.akk, self.laut = start, dauer, art, midi, akk, laut


def pwm(t, mitte, tiefe, periode):
    return int(mitte + tiefe * math.sin(2 * math.pi * t / periode)) & 0xFFF


def klang(n, rel, t):
    """Registerwerte einer Stimme rel Takte nach dem Anschlag"""
    if n.art == "bass":
        return dict(freq=freq_reg(midi_hz(n.midi)), pw=0x800, wave=0x20, ad=0x05, sr=0xC3,
                    laut=n.laut or 15)
    if n.art == "stich":            # Akkordstich: Arpeggio mit 50 Hz
        m = n.akk[rel % 3]
        return dict(freq=freq_reg(midi_hz(m)), pw=pwm(t, 0x800, 0x300, 150), wave=0x40,
                    ad=0x04, sr=0x63, laut=11)
    if n.art == "flaeche":          # Auftakt: weiches Arpeggio, wird lauter
        m = n.akk[rel % 3]
        return dict(freq=freq_reg(midi_hz(m)), pw=pwm(t, 0x800, 0x380, 220), wave=0x40,
                    ad=0x88, sr=0xA9, laut=min(11, 5 + rel // 30))
    if n.art == "arp":              # Refrain: vier Toene mit Oktave
        folge = n.akk + [n.akk[0] + 12]
        m = folge[rel % 4]
        return dict(freq=freq_reg(midi_hz(m)), pw=pwm(t, 0x600, 0x280, 200), wave=0x40,
                    ad=0x00, sr=0x94, laut=9)
    if n.art in ("melodie", "echo"):
        hz = midi_hz(n.midi)
        if rel >= 10:               # Vibrato setzt verzoegert ein
            tiefe = min(1.0, (rel - 10) / 15) * 20
            hz *= 2 ** (tiefe * math.sin(2 * math.pi * (rel - 10) / 9) / 1200)
        return dict(freq=freq_reg(hz), pw=pwm(t, 0x700, 0x200, 120), wave=0x40,
                    ad=0x09, sr=0xD5, laut=9 if n.art == "melodie" else 5)
    raise ValueError(n.art)


def song_bauen(smp):
    stimmen = [[] for _ in range(4)]
    proben = []                     # (Takt, Kanal, Sample, Laut, Pan)
    marken = {}                     # Takt -> Teil
    filter_teil = []                # (von, bis, Teil-Filter)
    takt = 0                        # Musiktakt

    def T(tk, zeile=0):
        return (tk * ZPT + zeile) * TPZ

    def probe(tk, zeile, kanal, name, laut, pan=0xFF):
        proben.append((T(tk, zeile), kanal, name, laut, pan))

    def melodie(tk0, mel):
        for i, takt_noten in enumerate(mel):
            for zeile, name, laenge in takt_noten:
                s, d = T(tk0 + i, zeile), laenge * TPZ
                stimmen[2].append(Note(s, d, "melodie", note(name)))
                stimmen[3].append(Note(s + ECHO_VERZUG, d, "echo", note(name)))

    schleife_takt = None
    for nr, (name, akkorde, filt) in enumerate(TEILE):
        tk0 = takt
        marken[T(tk0)] = nr
        if nr == SCHLEIFE_TEIL:
            schleife_takt = T(tk0)
        filter_teil.append((T(tk0), T(tk0 + len(akkorde)), filt))
        for i, a in enumerate(akkorde):
            tk = tk0 + i
            grund, akk = AKKORDE[a]
            # Bass
            if name == "Auftakt":
                if i == 1:
                    for z in range(0, 16, 2):
                        stimmen[0].append(Note(T(tk, z), 2 * TPZ, "bass", grund))
            elif name == "Filterfahrt":
                for z in range(16):
                    stimmen[0].append(Note(T(tk, z), TPZ, "bass", grund, laut=12))
            else:
                muster = [0, 12, 0, 12, 0, 12, 0, 12] if name == "Refrain" else [0, 0, 12, 0, 0, 0, 12, 0]
                for k, o in enumerate(muster):
                    stimmen[0].append(Note(T(tk, 2 * k), 2 * TPZ, "bass", grund + o))
            # Akkorde
            if name == "Auftakt":
                stimmen[1].append(Note(T(tk), 16 * TPZ, "flaeche", akk=akk))
            elif name == "Refrain":
                stimmen[1].append(Note(T(tk), 16 * TPZ, "arp", akk=akk))
            elif name != "Filterfahrt":
                for z in (2, 6, 10, 14):
                    stimmen[1].append(Note(T(tk, z), 2 * TPZ, "stich", akk=akk))
            # Schlagzeug
            if name == "Auftakt":
                if i == 0:
                    probe(tk, 0, 3, "meridian", 63)
                else:
                    for z in range(16):
                        probe(tk, z, 2, "hihat", 10 + z * 2, 0x6F)
                    probe(tk, 8, 0, "kick", 50)
                    probe(tk, 12, 0, "kick", 58)
                    probe(tk, 14, 1, "snare", 44, 0xFE)
                    probe(tk, 15, 1, "snare", 56, 0xFE)
            elif name == "Filterfahrt":
                if i == 0:
                    probe(tk, 0, 3, "orgel", 63)
                for z in range(0, 16, 2):
                    probe(tk, z, 2, "hihat", 36 if z % 4 == 2 else 20, 0x6F)
                if i == 1:
                    probe(tk, 0, 0, "kick", 56)
                    probe(tk, 8, 0, "kick", 60)
                    for z in range(8, 16):
                        probe(tk, z, 1, "snare", 22 + (z - 8) * 5, 0xFE)
            else:
                refrain = name == "Refrain"
                for z in (0, 4, 8, 12):
                    probe(tk, z, 0, "kick", 63)
                if refrain and i % 2 == 1:
                    probe(tk, 14, 0, "kick", 48)
                for z in (4, 12):
                    probe(tk, z, 1, "klatsch" if refrain else "snare", 56 if refrain else 52,
                          0xEF if refrain else 0xFE)
                for z in range(0, 16, 1 if refrain else 2):
                    if z % 4 == 0 and not refrain:     # Strophe: nur die Achtel dazwischen
                        continue
                    laut = 40 if z % 4 == 2 else 18
                    probe(tk, z, 2, "hihat", laut, 0x6F)
                if i % 4 == 0:
                    probe(tk, 0, 3, "becken", 44)
        # Melodie
        if name == "Strophe":
            melodie(tk0 + 4, MEL_A)
        elif name == "Refrain":
            melodie(tk0, MEL_B)
        elif name == "Finale":
            melodie(tk0, MEL_A2)
        takt += len(akkorde)

    gesamt = T(takt)
    return stimmen, proben, marken, filter_teil, schleife_takt, gesamt


def aktiv(noten, t):
    best = None
    for n in noten:
        if n.start <= t < n.start + n.dauer:
            best = n
    return best


def strom_bauen(smp):
    stimmen, proben, marken, filter_teil, schleife_takt, gesamt = song_bauen(smp)
    for s in stimmen:
        s.sort(key=lambda n: n.start)
    probe_tab = {}
    for p in proben:
        probe_tab.setdefault(p[0], []).append(p)
    # Der Bass macht der Kick kurz Platz ("Pumpen"), sonst geht sie unter
    kicks = sorted(p[0] for p in proben if p[2] == "kick")
    DUCKEN = [5, 7, 9, 11, 13, 14]
    welle = [0x20, 0x40, 0x40, 0x40]
    akt = {}                        # Registerstand im Chip, soweit bekannt
    strom = bytearray()
    schleife_ofs = None
    schreibe_anzahl = 0
    # Zeiger auf die zuletzt aktive Note je Stimme (schneller als jedes Mal suchen)
    idx = [0, 0, 0, 0]
    for t in range(gesamt):
        if t == schleife_takt:
            schleife_ofs = len(strom)
            akt = {}                # nach dem Ruecksprung ist nichts mehr sicher
        if t in marken:
            strom += bytes([0xFD, marken[t]])
        soll = []
        # Stimmen
        steuer = []
        bass = None
        for v in range(4):
            noten = stimmen[v]
            while idx[v] + 1 < len(noten) and noten[idx[v] + 1].start <= t:
                idx[v] += 1
            n = noten[idx[v]] if noten and noten[idx[v]].start <= t < noten[idx[v]].start + noten[idx[v]].dauer else None
            b = v * 16
            if n:
                rel = t - n.start
                k = klang(n, rel, t)
                if v == 0:
                    alter = min((t - kt for kt in kicks if 0 <= t - kt < len(DUCKEN)), default=None)
                    if alter is not None:
                        k["laut"] = min(k["laut"], DUCKEN[alter])
                welle[v] = k["wave"]
                gate = 1 if rel < n.dauer - 1 else 0
                soll += [(b + 0, k["freq"] & 0xFF), (b + 1, k["freq"] >> 8),
                         (b + 2, k["pw"] & 0xFF), (b + 3, k["pw"] >> 8),
                         (b + 5, k["ad"]), (b + 6, k["sr"]), (b + 7, k["laut"]), (b + 8, PAN[v])]
                steuer.append((b + 4, welle[v] | gate))
                if v == 0:
                    bass = (n, rel)
            else:
                steuer.append((b + 4, welle[v]))
        # Filter: Basis je Teil (bei der Filterfahrt exponentiell), Huellkurve je Bassnote
        for von, bis, (b0, b1, amp, res) in filter_teil:
            if von <= t < bis:
                f = (t - von) / (bis - von)
                basis = b0 * (b1 / b0) ** f if b1 != b0 else b0
                ecke = basis + (amp * math.exp(-bass[1] / 4) if bass else 0)
                ecke = max(0, min(2047, round(ecke)))
                soll += [(0x40, ecke & 0xFF), (0x41, ecke >> 8), (0x42, res << 4 | 0x01), (0x43, 0x1F)]
        soll += steuer
        # Samples
        for _, kanal, name, laut, pan in probe_tab.get(t, []):
            s = smp[name]
            if name == "kick" and os.environ.get("ORGEL_OHNE_KICK"):
                laut = 0
            b = 0x80 + kanal * 16
            soll += [(b + 0, s["start"] & 0xFF), (b + 1, (s["start"] >> 8) & 0xFF), (b + 2, s["start"] >> 16),
                     (b + 3, s["laenge"] & 0xFF), (b + 4, s["laenge"] >> 8),
                     (b + 7, s["schritt"] & 0xFF), (b + 8, s["schritt"] >> 8),
                     (b + 9, laut), (b + 10, pan), (b + 11, 0x01)]
        for reg, wert in soll:
            if akt.get(reg) != wert or (reg >= 0x80 and reg & 0x0F == 0x0B):
                strom += bytes([reg, wert])
                akt[reg] = wert
                schreibe_anzahl += 1
        strom.append(0xFF)
    strom.append(0xFE)
    kopf = (MUSIK_ADR + 3 + schleife_ofs).to_bytes(3, "little")
    daten = kopf + strom
    assert len(daten) <= 0x20000, "Musik passt nicht in die Baenke 2 und 3"
    print(f"  Musik: {gesamt} Takte = {gesamt / 50:.1f} s, {schreibe_anzahl} Registerzugriffe, "
          f"{len(daten)} Bytes ({len(daten) / (gesamt / 50):.0f} Bytes/s), Schleife ab {schleife_takt / 50:.2f} s")
    return daten


############################################################  Tabellen  #####

def zeile(werte, art=".byte"):
    return f"\t{art} " + ", ".join(werte)


def text(s, laenge):
    s = (s + " " * laenge)[:laenge]
    return '\t.text "' + s + '"'


def tabellen(smp):
    z = ["; Automatisch erzeugt von tools/orgel.py - nicht von Hand aendern", ""]
    # Notennamen: Mittelpunkte zwischen benachbarten Frequenzregistern
    erste, letzte = 24, 106
    regs = [freq_reg(midi_hz(m)) for m in range(erste, letzte + 1)]
    mitten = [(regs[i] + regs[i + 1] + 1) // 2 for i in range(len(regs) - 1)]
    z.append(f"NOTEN_MITTEN = {len(mitten)}")
    z.append("noten_mitte")
    for i in range(0, len(mitten), 8):
        z.append(zeile([str(v) for v in mitten[i:i + 8]], ".word"))
    z.append("noten_namen\t\t; 4 Byte je Note")
    for m in range(erste, letzte + 1):
        z.append(f'\t.text "{NAMEN[m % 12]}{m // 12 - 1}", 0')
    # Wellenformen nach STEUER Bits 4-7
    namen = {0: "-", 1: "Triangle", 2: "Saw", 4: "Pulse", 8: "Noise", 3: "Tri+Saw", 5: "Tri+Puls",
             6: "Saw+Puls", 7: "T+S+P"}
    z.append("wellen_namen\t\t; 8 Zeichen je Eintrag")
    for i in range(16):
        z.append(text(namen.get(i, "Mix"), 8))
    # Filterarten nach Modus Bits 4-6
    fnamen = ["off", "Low pass", "Band pass", "Low+Band", "High pass", "Notch", "Band+High", "all three"]
    z.append("filter_namen\t\t; 10 Zeichen je Eintrag")
    for n in fnamen:
        z.append(text(n, 10))
    # Panorama -> Position 0..6 der Anzeige
    pos = []
    for p in range(256):
        l, r = p >> 4, p & 15
        pos.append(3 if l + r == 0 else round(3 + 3 * (r - l) / max(l, r)))
    z.append("pan_pos")
    for i in range(0, 256, 16):
        z.append(zeile([str(v) for v in pos[i:i + 16]]))
    # Teile
    z.append(f"TEILE = {len(TEILE)}")
    z.append("teil_namen\t\t; 12 Zeichen je Teil")
    for name, _, _ in TEILE:
        z.append(text(name, 12))
    # Samples
    namen = [s[0] for s in SAMPLES]
    z.append(f"SAMPLES = {len(namen)}")
    z.append("smp_start\t\t; untere 16 Bit der Startadresse")
    z.append(zeile([f"${smp[n]['start'] & 0xFFFF:04x}" for n in namen], ".word"))
    z.append("smp_bloecke\t\t; Laenge der Huellkurve (256-Byte-Bloecke), Index = Sample * 2")
    z.append(zeile([str(len(smp[n]["huelle"])) for n in namen], ".word"))
    z.append("smp_huelle\t\t; Zeiger auf die Huellkurven")
    z.append(zeile([f"huelle_{n}" for n in namen], ".word"))
    z.append("smp_namen\t\t; 8 Zeichen je Sample")
    for n in namen:
        z.append(text(smp[n]["anzeige"], 8))
    z.append("smp_raten\t\t; 6 Zeichen je Sample")
    for n in namen:
        z.append(text(f"{smp[n]['rate'] / 1000:.0f} kHz", 6))
    for n in namen:
        z.append(f"huelle_{n}")
        h = smp[n]["huelle"]
        for i in range(0, len(h), 16):
            z.append(zeile([str(v) for v in h[i:i + 16]]))
    # Latin-1 wie die Quelltexte nach iconv: so landen die Umlaute als MERIDIAN-Codes
    with open(os.path.join(BASIS, "programme", "orgel_daten.inc"), "w", encoding="latin-1") as f:
        f.write("\n".join(z) + "\n")


def main():
    os.makedirs(DATEN, exist_ok=True)
    print("Samples:")
    klaenge, smp = samples_bauen()
    with open(os.path.join(DATEN, "orgel_klaenge.mer"), "wb") as f:
        f.write(mer(KLANG_ADR, klaenge))
    print(f"  zusammen {len(klaenge)} Bytes ab ${KLANG_ADR:06X}")
    musik = strom_bauen(smp)
    with open(os.path.join(DATEN, "orgel_musik.mer"), "wb") as f:
        f.write(mer(MUSIK_ADR, musik))
    # Dieselbe Musik fuer BALLETT (Etappe 7), dort in Bank 0 ab $4000, weil
    # die Baenke 2 und 3 die beiden Bildpuffer tragen
    schleife = int.from_bytes(musik[:3], "little") - MUSIK_ADR
    umgezogen = (BALLETT_MUSIK + schleife).to_bytes(3, "little") + musik[3:]
    assert BALLETT_MUSIK + len(umgezogen) <= 0xC000, "Musik passt nicht unter $C000"
    with open(os.path.join(DATEN, "ballett_musik.mer"), "wb") as f:
        f.write(mer(BALLETT_MUSIK, umgezogen))
    tabellen(smp)
    print("programme/orgel_daten.inc geschrieben")


if __name__ == "__main__":
    main()
