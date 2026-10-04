#!/usr/bin/env python3
"""MERIDIAN-Module pruefen: modul.py SPIEL.MOD [...]

Ein Modul ist ein ROM-Abbild, das ab $40:0000 im Zusatzspeicher liegt
(hoechstens 4 MB, im MiSTer-Menue "Modul einstecken"). Kopf, 32 Byte:
   0-7   "MODUL816"          8  Version (1)       9  Flags (0)
  10-12  Startadresse        13-15 frei           16-31 Name (Latin-1, 0 = Ende)
Der Kern ruft die Startadresse beim Einschalten und nach jedem Reset per
JSL auf (nativ, Akku 8 / Index 16 Bit); mit RTL geht es weiter ins BASIC.
"""
import sys

GROESSE = 4 * 1024 * 1024


def pruefen(pfad):
    d = open(pfad, "rb").read()
    fehler = []
    if len(d) < 32 or d[:8] != b"MODUL816":
        return [f"{pfad}: kein MERIDIAN-Modul (Kennung MODUL816 fehlt)"]
    start = d[10] | d[11] << 8 | d[12] << 16
    name = d[16:32].split(b"\0")[0].decode("latin-1")
    print(f"{pfad}: \"{name}\", Version {d[8]}, Start ${start >> 16:02X}:{start & 0xFFFF:04X}, {len(d)} Bytes")
    if len(d) > GROESSE:
        fehler.append(f"zu gross: {len(d)} Bytes (hoechstens {GROESSE})")
    if not 0x400000 <= start < 0x400000 + len(d) and start >= 0x040000:
        fehler.append("Startadresse liegt weder im Modul noch im Chip-RAM")
    if d[8] != 1:
        fehler.append(f"unbekannte Version {d[8]}")
    return fehler


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    alle = []
    for pfad in sys.argv[1:]:
        alle += pruefen(pfad)
    for f in alle:
        print("  Fehler:", f)
    sys.exit(1 if alle else 0)


if __name__ == "__main__":
    main()
