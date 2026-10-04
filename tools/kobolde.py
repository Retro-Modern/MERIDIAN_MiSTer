#!/usr/bin/env python3
"""Sprite-Grafik und Tabellen fuer das Vorfuehrprogramm KOBOLDE (Etappe 5).

Muster (16x16, 4 Bit):
   0 Kugel, 1 UFO, 2/3 Vogel (Fluegel oben/unten), 4/5 Explosion,
  10-19 Ziffern 0-9 (aus dem MERIDIAN-Zeichensatz, doppelt gross)
Palettenbaenke: 3-6 Kugeln (rot, blau, gruen, gold), 7 UFO, 8 Vogel,
  9 Explosion, 10 Ziffern
Dazu Sinustabellen fuer die Bahnen.

    ../.venv/bin/python tools/kobolde.py   -> programme/kobolde_daten.inc
"""
import math
import os

from PIL import Image

HIER = os.path.dirname(os.path.abspath(__file__))
BASIS = os.path.join(HIER, "..")


def leer():
    return [[0] * 16 for _ in range(16)]


def kugel():
    m = leer()
    for y in range(16):
        for x in range(16):
            dx, dy = x - 7.5, y - 7.5
            r = math.hypot(dx, dy)
            if r <= 7.6:
                nz = math.sqrt(max(0.0, 1 - (r / 7.6) ** 2))
                licht = (-dx * 0.45 - dy * 0.55 + nz * 0.7) / 1.0
                stufe = max(1, min(12, round(1 + (licht + 0.4) * 9)))
                glanz = math.hypot(dx + 2.6, dy + 2.8)
                if glanz < 1.3:
                    stufe = 15
                elif glanz < 2.2:
                    stufe = 14
                elif glanz < 3.0:
                    stufe = max(stufe, 13)
                m[y][x] = stufe
    return m


def kugel_palette(c):
    p = [(0, 0, 0)]
    for i in range(1, 13):
        t = (i - 1) / 11
        p.append(tuple(round(c[k] * (0.18 + 0.82 * t)) for k in range(3)))
    p += [tuple(min(255, round(c[k] * 0.4 + 160)) for k in range(3)), (235, 235, 245), (255, 255, 255)]
    return p


def ufo():
    m = leer()
    for y in range(16):
        for x in range(16):
            dx = x - 7.5
            if 2 <= y <= 7 and (dx / 4.2) ** 2 + ((y - 7.5) / 5.2) ** 2 <= 1:      # Kuppel
                m[y][x] = 4 if (x < 7 and y < 5) else (3 if x < 9 else 2)
            if 7 <= y <= 11 and (dx / 7.8) ** 2 + ((y - 9) / 2.6) ** 2 <= 1:      # Scheibe
                m[y][x] = 6 if y < 9 else (7 if y < 11 else 8)
            if y == 12 and 4 <= x <= 11:
                m[y][x] = 8
    for x in (2, 6, 10, 13):                                                  # Lichter
        m[9][x] = 10 if x % 4 == 2 else 11
    return m


UFO_PAL = [(0, 0, 0), (0, 0, 0), (40, 140, 180), (90, 200, 230), (200, 245, 255), (0, 0, 0),
           (200, 205, 215), (150, 155, 170), (90, 95, 110), (0, 0, 0), (255, 230, 80), (255, 80, 80),
           (0, 0, 0), (0, 0, 0), (0, 0, 0), (0, 0, 0)]


def vogel(oben):
    m = leer()
    for x in range(16):
        dx = abs(x - 7.5)
        y = 8 + (-round(dx * 0.7) if oben else round(dx * 0.55) - 2)
        y = max(1, min(14, int(y)))
        m[y][x] = 1
        if dx > 1.5:
            m[y + 1][x] = 2
    m[8][7] = m[8][8] = m[9][7] = m[9][8] = 1
    m[8][9] = 3                                                               # Schnabel
    return m


VOGEL_PAL = [(0, 0, 0), (35, 30, 45), (70, 60, 85), (240, 170, 60)] + [(0, 0, 0)] * 12


def explosion(gross):
    m = leer()
    for y in range(16):
        for x in range(16):
            dx, dy = x - 7.5, y - 7.5
            r = math.hypot(dx, dy)
            w = math.atan2(dy, dx)
            strahl = 0.5 + 0.5 * math.cos(w * 8)
            grenze = (7.5 if gross else 4.5) * (0.55 + 0.45 * strahl)
            if r < grenze:
                m[y][x] = 3 if r < grenze * 0.35 else (2 if r < grenze * 0.7 else 1)
    return m


EXPL_PAL = [(0, 0, 0), (240, 90, 30), (255, 200, 60), (255, 255, 230)] + [(0, 0, 0)] * 12


def ziffer(z):
    font = open(os.path.join(BASIS, "rom", "zeichensatz.bin"), "rb").read()
    m = leer()
    code = ord("0") + z
    for y in range(8):
        byte = font[code * 8 + y]
        for x in range(8):
            if byte & (0x80 >> x):
                for dy in (0, 1):
                    for dx in (0, 1):
                        m[y * 2 + dy][x * 2 + dx] = 1
    for y in range(15, -1, -1):                                               # Schatten
        for x in range(15, -1, -1):
            if m[y][x] == 0 and y > 0 and x > 0 and m[y - 1][x - 1] == 1:
                m[y][x] = 2
    return m


ZIFFER_PAL = [(0, 0, 0), (255, 255, 255), (20, 20, 40)] + [(0, 0, 0)] * 13


def rgb12(c):
    return tuple(min(15, round(v / 17)) for v in c)


def pal_zeile(farben):
    out = []
    for c in farben:
        r, g, b = rgb12(c)
        out += [g << 4 | b, r]
    return "\t.byte " + ", ".join(f"${v:02x}" for v in out)


def muster_bytes(m):
    out = []
    for zeile in m:
        for x in range(0, 16, 2):
            out.append(zeile[x] << 4 | zeile[x + 1])
    return out


def main():
    muster = {0: kugel(), 1: ufo(), 2: vogel(True), 3: vogel(False), 4: explosion(True), 5: explosion(False)}
    for z in range(10):
        muster[10 + z] = ziffer(z)
    anzahl = max(muster) + 1
    z = ["; Automatisch erzeugt von tools/kobolde.py", f"MUSTER_ANZAHL = {anzahl}", "muster_daten"]
    for nr in range(anzahl):
        b = muster_bytes(muster.get(nr, leer()))
        for i in range(0, 128, 16):
            z.append("\t.byte " + ", ".join(f"${v:02x}" for v in b[i:i + 16]))
    z.append("sprite_paletten\t\t; Baenke 3-10")
    for farbe in [(255, 60, 50), (70, 120, 255), (60, 220, 80), (255, 200, 40)]:
        z.append(pal_zeile(kugel_palette(farbe)))
    for pal in (UFO_PAL, VOGEL_PAL, EXPL_PAL, ZIFFER_PAL):
        z.append(pal_zeile(pal))
    # Bahnen: Sinus fuer X (+-140) und Y (+-60), 256 Schritte, 16 Bit
    z.append("bahn_x")
    for i in range(0, 256, 8):
        z.append("\t.word " + ", ".join(str(round(140 * math.sin(2 * math.pi * k / 256)) & 0xFFFF)
                                       for k in range(i, i + 8)))
    z.append("bahn_y")
    for i in range(0, 256, 8):
        z.append("\t.word " + ", ".join(str(round(60 * math.sin(2 * math.pi * k / 256)) & 0xFFFF)
                                       for k in range(i, i + 8)))
    with open(os.path.join(BASIS, "programme", "kobolde_daten.inc"), "w") as f:
        f.write("\n".join(z) + "\n")

    # Vorschau aller Muster mit ihren Paletten
    pals = {0: kugel_palette((255, 60, 50)), 1: UFO_PAL, 2: VOGEL_PAL, 3: VOGEL_PAL, 4: EXPL_PAL, 5: EXPL_PAL}
    img = Image.new("RGB", (16 * 16 * 4, 16 * 4), (120, 160, 230))
    for i, nr in enumerate(sorted(muster)):
        pal = pals.get(nr, ZIFFER_PAL)
        for y in range(16):
            for x in range(16):
                v = muster[nr][y][x]
                if v:
                    c = tuple(k * 17 for k in rgb12(pal[v]))
                    for dy in range(4):
                        for dx in range(4):
                            img.putpixel((i * 64 + x * 4 + dx, y * 4 + dy), c)
    img.save(os.path.join(BASIS, "doku", "bilder", "etappe5_sprites_vorschau.png"))
    print(f"{anzahl} Muster, kobolde_daten.inc geschrieben")


if __name__ == "__main__":
    main()
