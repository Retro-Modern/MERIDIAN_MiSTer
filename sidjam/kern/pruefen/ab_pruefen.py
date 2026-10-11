#!/usr/bin/env python3
"""--ab pruefen: der Strom ab SEK muss mit einem Abbild aller Register
(Stand genau bei SEK) beginnen und danach Datensatz fuer Datensatz dem
vollen Strom ab SEK gleichen.

Aufruf: ab_pruefen.py [-k sidkern] DATEI.sid AB_SEK BIS_SEK
"""
import argparse
import json
import os
import subprocess
import sys

HIER = os.path.dirname(os.path.abspath(__file__))


def zeilen(kern, args):
    aus = subprocess.run([kern] + args + ["--text"], capture_output=True, check=True).stdout.decode("utf-8")
    kopf, ds, ende = None, [], None
    for z in aus.split("\n"):
        if z.startswith("# {"):
            kopf = json.loads(z[2:])
        elif z.startswith("# ende"):
            ende = int(z.split()[2])
        elif z:
            t, c, r, v = z.split()
            ds.append((int(t), int(c), int(r, 16), int(v, 16)))
    return kopf, ds, ende


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("datei")
    ap.add_argument("ab", type=float)
    ap.add_argument("bis", type=float)
    ap.add_argument("-k", "--kern", default=os.path.join(HIER, "..", "bau", "sidkern-macos"))
    a = ap.parse_args()

    kopf, voll, ende_voll = zeilen(a.kern, [a.datei, "-t", str(a.bis)])
    kopf2, teil, ende_teil = zeilen(a.kern, [a.datei, "-t", str(a.bis), "--ab", str(a.ab)])
    start = kopf2["start_cycles"]
    chips = len(kopf2["sids"])
    schatten = [[0] * 25 for _ in range(chips)]
    for t, c, r, v in voll:
        if t < start:
            schatten[c][r] = v
    abbild = [(start, c, r, schatten[c][r]) for c in range(chips) for r in range(25)]
    gut = True
    if teil[:len(abbild)] != abbild:
        print("Abbild falsch")
        gut = False
    rest_soll = [x for x in voll if x[0] >= start]
    if teil[len(abbild):] != rest_soll:
        print(f"Datensaetze nach dem Abbild weichen ab ({len(teil) - len(abbild)} statt {len(rest_soll)})")
        gut = False
    if ende_teil != ende_voll:
        print(f"Ende-Marke {ende_teil} statt {ende_voll}")
        gut = False
    print(f"{os.path.basename(a.datei)}: --ab {a.ab} (Zyklus {start}): Abbild {len(abbild)} Datensaetze, "
          f"danach {len(teil) - len(abbild)} - {'gleich' if gut else 'FEHLER'}")
    return 0 if gut else 1


if __name__ == "__main__":
    sys.exit(main())
