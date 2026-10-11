#!/usr/bin/env python3
"""Testfaelle der SingleStepTests (github.com/SingleStepTests/65x02, Satz 6502,
eine JSON-Datei je Opcode) in Zeilen fuer einzelschritt.c umwandeln.

Aufruf: einzelschritt_wandeln.py DATEI.json [...] > faelle.txt

Zeile: pc s a x y p n (adr wert)*n  pc s a x y p m (adr wert)*m  k (adr wert schreib)*k
"""
import json
import sys


def zustand(z):
    teile = [z["pc"], z["s"], z["a"], z["x"], z["y"], z["p"], len(z["ram"])]
    for adr, wert in z["ram"]:
        teile += [adr, wert]
    return teile


for name in sys.argv[1:]:
    with open(name) as f:
        faelle = json.load(f)
    aus = []
    for fall in faelle:
        teile = zustand(fall["initial"]) + zustand(fall["final"]) + [len(fall["cycles"])]
        for adr, wert, art in fall["cycles"]:
            teile += [adr, wert, 1 if art == "write" else 0]
        aus.append(" ".join(map(str, teile)))
    sys.stdout.write("\n".join(aus) + "\n")
