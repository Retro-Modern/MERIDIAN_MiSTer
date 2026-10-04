#!/usr/bin/env python3
"""Wandelt einen Klang (WAV, MP3 ...) in ein MERIDIAN-Sample: mono, 8 Bit mit
Vorzeichen, angegebene Abspielrate, auf Spitze normiert - als MER-Datei fuer
eine Ladeadresse (auch im Zusatzspeicher). Gibt die Laenge fuer SAMPLE aus.

    python3 tools/sample2mer.py klang.mp3 ziel.mer --adresse 210000
        [--hz 22050] [--sekunden 0.4] [--pegel 0.95]

In BASIC dann:  SAMPLE kanal, 65536*$21, laenge, hz
(Aus dem Zusatzspeicher holt SAMPLE bis 12 KB selbst ins Chip-RAM.)
"""
import argparse
import array
import struct
import subprocess


def main():
    a = argparse.ArgumentParser()
    a.add_argument("quelle")
    a.add_argument("ziel")
    a.add_argument("--adresse", required=True, help="Ladeadresse hex, z.B. 210000")
    a.add_argument("--hz", type=int, default=22050)
    a.add_argument("--sekunden", type=float, default=None)
    a.add_argument("--pegel", type=float, default=0.95)
    o = a.parse_args()

    befehl = ["ffmpeg", "-v", "error", "-i", o.quelle, "-ac", "1", "-ar", str(o.hz)]
    if o.sekunden:
        befehl += ["-t", str(o.sekunden)]
    roh = subprocess.run(befehl + ["-f", "s16le", "-"], capture_output=True, check=True).stdout
    werte = array.array("h")
    werte.frombytes(roh)
    spitze = max(1, max(abs(v) for v in werte))
    faktor = o.pegel * 127 / spitze
    daten = bytes((max(-127, min(127, round(v * faktor))) & 0xFF) for v in werte)

    lade = int(o.adresse, 16)
    kopf = b"MER\x01" + struct.pack("<I", lade)[:3] + b"\x00"
    kopf += struct.pack("<I", lade)[:3] + b"\x00" + struct.pack("<I", len(daten))
    with open(o.ziel, "wb") as f:
        f.write(kopf + daten)
    print(f"{o.ziel}: {len(daten)} Bytes ab ${lade:06X}, {o.hz} Hz, "
          f"{len(daten) / o.hz:.2f} s")


if __name__ == "__main__":
    main()
