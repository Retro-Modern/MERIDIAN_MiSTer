#!/usr/bin/env python3
"""Farbtabelle fuer die Rasterbalken: 64 Eintraege im PINSEL-Format
(gggg bbbb, ---- rrrr). Drei weiche Balken auf dunkelblauem Grund."""
import math

BALKEN = [(1.0, 0.3, 0.3), (1.0, 0.85, 0.2), (0.3, 0.8, 1.0)]  # rot, gold, himmelblau
GRUND = (0x2 / 15, 0x3 / 15, 0x8 / 15)


def farbe(i):
    teil = (i % 64) / 64 * len(BALKEN)
    b = int(teil)
    t = teil - b                       # 0..1 innerhalb eines Balkens
    k = max(0.0, math.sin(math.pi * t)) ** 1.5
    r, g, bl = BALKEN[b]
    glanz = max(0.0, k - 0.8) * 2.5    # weisse Mitte
    rgb = [GRUND[j] * (1 - k) + c * k + glanz for j, c in enumerate((r, g, bl))]
    return [min(15, max(0, round(v * 15))) for v in rgb]


zeilen = ["farben"]
for i in range(64):
    r, g, b = farbe(i)
    zeilen.append(f"\t.byte ${g << 4 | b:02x}, ${r:02x}")
open("farben.inc", "w").write("\n".join(zeilen) + "\n")
