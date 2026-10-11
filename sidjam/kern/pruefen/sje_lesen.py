#!/usr/bin/env python3
"""SJE-Strom (SCHNITTSTELLEN.md, Abschnitt 1) lesen und pruefen.

Aufruf: sje_lesen.py [DATEI.sje]      (ohne Datei: stdin)
Gibt den JSON-Kopf als "# {...}" aus, dann je Datensatz eine Zeile
"zyklus chip reg wert" (wie sidkern --text) und am Ende "# ende ZYKLUS".
Rueckgabe 1, wenn der Strom nicht dem Format entspricht.
"""
import json
import sys


def fehler(text):
    print(f"FEHLER: {text}", file=sys.stderr)
    sys.exit(1)


def main():
    daten = open(sys.argv[1], "rb").read() if len(sys.argv) > 1 else sys.stdin.buffer.read()
    if daten[:4] != b"SJE1":
        fehler("Kennung SJE1 fehlt")
    n = daten[4] | (daten[5] << 8)
    kopf = json.loads(daten[6:6 + n].decode("utf-8"))
    print("# " + json.dumps(kopf, ensure_ascii=False, separators=(",", ":")))
    zyklus = kopf["start_cycles"]
    i = 6 + n
    aus = []
    while True:
        if i >= len(daten):
            fehler("Strom endet ohne Ende-Marke")
        d = 0
        schieben = 0
        while True:
            b = daten[i]
            i += 1
            d |= (b & 0x7F) << schieben
            schieben += 7
            if not b & 0x80:
                break
        zyklus += d
        r = daten[i]
        i += 1
        if r == 0x7F:
            break
        if r > 0x5F or (r & 0x1F) > 24:
            fehler(f"Registerbyte {r:#04x} ungueltig")
        aus.append(f"{zyklus} {r >> 5} {r & 0x1F:02X} {daten[i]:02X}")
        i += 1
    if i != len(daten):
        fehler(f"{len(daten) - i} Bytes nach der Ende-Marke")
    sys.stdout.write("\n".join(aus) + ("\n" if aus else ""))
    print(f"# ende {zyklus}")


if __name__ == "__main__":
    main()
