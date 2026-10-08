#!/usr/bin/env python3
"""Die Startpalette MERIDIAN-256 (MERIDIAN 1.0, PINSEL-Look).

  0-15    MERIDIAN-16 (wie seit Etappe 1)
  16-255  30 Farbfamilien zu 8 Stufen: Familie f liegt ab 16 + 8 * f, Stufe 0
          ist die dunkelste. Dunkle Stufen sind Richtung Blauviolett gedreht,
          helle Richtung Gelb - so schattieren Pixelkuenstler von Hand. Eine
          Palettenbank (16 Farben) enthaelt genau zwei Familien.

Gerechnet in OKLCH und auf 4 Bit je Kanal gerundet. Als Skript schreibt es
rom/farben.inc fuer den Kern (rom/bauen.sh), als Modul liefert startpalette()
die 256 Farben als (r, g, b) 0-255 fuer die Bildwandler.

    python3 tools/farben.py            rom/farben.inc schreiben
    python3 tools/farben.py --liste    Familien mit ihren Nummern
"""
import math
import os
import sys

MERIDIAN16 = ["000", "FFF", "D33", "5DD", "A4D", "4C4", "238", "FE5",
              "F92", "952", "F88", "444", "888", "9F9", "8BF", "CCC"]

FAMILIEN = [  # Name, Farbton (Grad), Buntheit, hellste Stufe (OKLCH)
    ("rot", 25, .19, .93), ("karmin", 5, .17, .93), ("orange", 55, .16, .95),
    ("gold", 85, .15, .97), ("ocker", 75, .10, .93), ("holz", 55, .07, .90),
    ("haut", 50, .08, .95), ("pfirsich", 40, .11, .95), ("oliv", 115, .10, .93),
    ("gras", 135, .15, .95), ("wald", 150, .10, .90), ("smaragd", 165, .14, .93),
    ("tuerkis", 190, .12, .96), ("petrol", 210, .09, .92), ("himmel", 235, .12, .96),
    ("blau", 260, .17, .92), ("indigo", 275, .14, .90), ("violett", 295, .16, .93),
    ("purpur", 320, .16, .93), ("magenta", 340, .18, .94), ("grau", 0, .0, .97),
    ("stein", 250, .025, .95), ("warmgrau", 60, .025, .95), ("sand", 80, .06, .97),
    ("ziegel", 35, .12, .90), ("lavendel", 290, .07, .96), ("mint", 160, .07, .97),
    ("neonpink", 350, .24, .97), ("neoncyan", 200, .15, .98), ("neongruen", 125, .22, .98),
]


def _oklch_rgb(L, C, h):
    a, b = C * math.cos(math.radians(h)), C * math.sin(math.radians(h))
    l_ = L + 0.3963377774 * a + 0.2158037573 * b
    m_ = L - 0.1055613458 * a - 0.0638541728 * b
    s_ = L - 0.0894841775 * a - 1.2914855480 * b
    l, m, s = l_ ** 3, m_ ** 3, s_ ** 3
    lin = (4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
           -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
           -0.0041960863 * l - 0.7034186147 * m + 1.7076126812 * s)

    def gamma(x):
        x = min(max(x, 0.0), 1.0)
        return 12.92 * x if x <= 0.0031308 else 1.055 * x ** (1 / 2.4) - 0.055
    return tuple(gamma(c) for c in lin)


def _drehe(h, ziel, anteil):
    d = (ziel - h + 540) % 360 - 180
    return h + d * anteil


def stufe(familie, k):
    """Farbe der Stufe k (0-7) einer Familie, 4 Bit je Kanal (0-15)"""
    _n, h, C, Lmax = FAMILIEN[familie]
    t = k / 7
    L = 0.16 + (Lmax - 0.16) * t
    if t < 0.5:
        hh = _drehe(h, 275, 0.22 * (1 - t) ** 1.5)
    else:
        hh = _drehe(h, 85, 0.18 * ((t - 0.5) * 2) ** 1.5)
    cc = max(C * (1 - 0.55 * ((t - 0.55) / 0.6) ** 2), 0)
    return tuple(round(c * 15) for c in _oklch_rgb(L, cc, hh))


def palette16():
    """Alle 256 Startfarben, 4 Bit je Kanal"""
    pal = [tuple(int(c, 16) for c in f) for f in MERIDIAN16]
    for f in range(len(FAMILIEN)):
        for k in range(8):
            pal.append(stufe(f, k))
    assert len(pal) == 256
    return pal


def startpalette():
    """Wie der Kern sie setzt, (r, g, b) 0-255"""
    return [tuple(c * 17 for c in f) for f in palette16()]


def nummer(name, k):
    """Palettennummer einer Familie und Stufe, z. B. nummer("gold", 6)"""
    return 16 + 8 * [n for n, *_r in FAMILIEN].index(name) + k


def main():
    if "--liste" in sys.argv:
        for i, (n, *_r) in enumerate(FAMILIEN):
            print(f"{16 + 8 * i:3d}-{23 + 8 * i:3d}  {n}")
        return
    pal = palette16()[16:]
    ziel = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "rom", "farben.inc")
    with open(ziel, "w") as f:
        f.write("; Automatisch erzeugt von tools/farben.py: Farben 16-255 der Startpalette\n")
        f.write("; MERIDIAN-256, 30 Familien zu 8 Stufen (gggg bbbb, ---- rrrr)\n")
        f.write("farben256\n")
        for i, (n, *_r) in enumerate(FAMILIEN):
            werte = ", ".join(f"${g << 4 | b:02x},${r:x}" for r, g, b in pal[i * 8:i * 8 + 8])
            f.write(f"\t.byte {werte}   ; {16 + 8 * i} {n}\n")
    print(f"rom/farben.inc: {len(pal)} Farben in {len(FAMILIEN)} Familien")


if __name__ == "__main__":
    main()
