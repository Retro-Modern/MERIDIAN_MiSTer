#!/usr/bin/env python3
"""Grafikdaten fuer die MERIDIAN-Grafikdemo erzeugen und umrechnen.

Erzeugt alles selbst (keine fremden Bilder):
  - ein Synthwave-Bild 320x240, umgerechnet auf 240 Farben aus 4096
    (Palettenplaetze 16-255; 0-15 bleiben fuer Text frei)
  - zwei nahtlos kachelbare Landschaftsebenen 512x256 fuer Parallax-
    Scrolling, zerlegt in 8x8-Kacheln mit je 15 Farben (+ durchsichtig)

Ausgabe:
  programme/daten/bild.mer      Bitmap ($01:0000) + Palette ($02:2C00)
  programme/daten/ebene_b.mer   Karte B ($02:4000) + Muster B ($02:5000)
  programme/daten/ebene_a.mer   Karte A ($03:0000) + Muster A ($03:1000)
  programme/grafik_daten.inc    Kachelpaletten fuer das Programm
  doku/bilder/etappe4_*.png     Vorschau

    ../.venv/bin/python tools/grafik.py
"""
import math
import os
import random
import struct

from PIL import Image, ImageDraw, ImageFilter

HIER = os.path.dirname(os.path.abspath(__file__))
BASIS = os.path.join(HIER, "..")
DATEN = os.path.join(BASIS, "programme", "daten")
BILDER = os.path.join(BASIS, "doku", "bilder")

ADR_BILD, ADR_BILDPAL = 0x010000, 0x022C00
ADR_KARTE_B, ADR_MUSTER_B = 0x024000, 0x025000
ADR_KARTE_A, ADR_MUSTER_A = 0x030000, 0x031000
HIMMEL_ZEILEN = 176


def mer(name, lade, daten, start=None, auto=False):
    start = lade if start is None else start
    kopf = b"MER\x01" + struct.pack("<I", lade)[:3] + bytes([1 if auto else 0])
    kopf += struct.pack("<I", start)[:3] + b"\x00" + struct.pack("<I", len(daten))
    with open(os.path.join(DATEN, name), "wb") as f:
        f.write(kopf + daten)
    print(f"{name}: {len(daten)} Bytes ab ${lade:06X}")


def rgb12(c):
    return tuple(min(15, round(v / 17)) for v in c)


def pal_bytes(farben):
    """Liste von (r,g,b) 0-15 -> PINSEL-Format gggg bbbb, ---- rrrr"""
    out = bytearray()
    for r, g, b in farben:
        out += bytes([g << 4 | b, r])
    return bytes(out)


def mischen(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


#############################################################################
# Synthwave-Bild

def synthwave():
    W, H = 320, 240
    hor = 150
    im = Image.new("RGB", (W, H))
    px = im.load()
    himmel = [(12, 6, 40), (60, 14, 90), (170, 40, 140), (250, 110, 90), (255, 190, 110)]
    for y in range(hor):
        t = y / hor * (len(himmel) - 1)
        i = min(int(t), len(himmel) - 2)
        c = mischen(himmel[i], himmel[i + 1], t - i)
        for x in range(W):
            px[x, y] = c
    rnd = random.Random(816)
    for _ in range(90):
        x, y = rnd.randrange(W), rnd.randrange(0, 80)
        h = rnd.randrange(150, 256)
        px[x, y] = (h, h, min(255, h + 20))
    d = ImageDraw.Draw(im)
    # Sonne mit Streifen
    cx, cy, rad = 160, 105, 52
    for y in range(cy - rad, cy + rad + 1):
        if y >= hor:
            break
        t = (y - (cy - rad)) / (2 * rad)
        c = mischen((255, 240, 120), (255, 60, 150), t)
        w = int(math.sqrt(max(0, rad * rad - (y - cy) ** 2)))
        streifen = y > cy - 5 and ((y - cy) // 3) % (2 + (y - cy) // 14) == 0
        if not streifen:
            d.line([(cx - w, y), (cx + w, y)], fill=c)
    # Berge
    for ebene, (farbe, rand, hoehe, phase) in enumerate([((40, 10, 70), (120, 40, 160), 55, 0.0),
                                                          ((20, 5, 45), (200, 60, 200), 35, 1.7)]):
        for x in range(W):
            h = hoehe * (0.55 + 0.25 * math.sin(x / 23 + phase) + 0.2 * math.sin(x / 9.3 + 2 * phase)
                         + 0.08 * math.sin(x / 3.1 + phase))
            top = int(hor - h)
            for y in range(max(0, top), hor):
                px[x, y] = rand if y < top + 2 else farbe
    # Boden mit Gitter
    for y in range(hor, H):
        t = (y - hor) / (H - hor)
        c = mischen((25, 5, 45), (60, 10, 80), t)
        for x in range(W):
            px[x, y] = c
    gitter = (255, 60, 220)
    for i in range(-14, 15):
        x0 = 160 + i * 6
        x1 = 160 + i * 48
        d.line([(x0, hor), (x1, H)], fill=gitter)
    z = 1.0
    while True:
        y = hor + int(90 / z)
        if y >= H:
            z += 0.5
            continue
        if z > 30:
            break
        d.line([(0, y), (W, y)], fill=gitter)
        z += 0.6 + z * 0.35
    d.line([(0, hor), (W, hor)], fill=(255, 150, 240))
    return im


def bild_umrechnen(im):
    """auf 240 Farben aus 4096 (Plaetze 16-255), mit Fehlerverteilung"""
    q = im.quantize(colors=240, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    pal = q.getpalette()[:240 * 3]
    farben12 = [rgb12(pal[i * 3:i * 3 + 3]) for i in range(240)]
    palbild = Image.new("P", (1, 1))
    flach = []
    for r, g, b in farben12:
        flach += [r * 17, g * 17, b * 17]
    palbild.putpalette(flach + [0] * (768 - len(flach)))
    q2 = im.quantize(palette=palbild, dither=Image.Dither.FLOYDSTEINBERG)
    idx = bytes(i + 16 for i in q2.tobytes())
    vorschau = Image.new("RGB", im.size)
    vorschau.putdata([tuple(v * 17 for v in farben12[i - 16]) for i in idx])
    return idx, farben12, vorschau


#############################################################################
# Landschaft in zwei Ebenen, nahtlos ueber 512 Pixel

def welle(x, terme):
    return sum(a * math.sin(2 * math.pi * (k * x / 512) + p) for a, k, p in terms_of(terme))


def terms_of(terme):
    return terme


def ebene_hinten():
    """Ferne Berge und Wolken, 512x256, Farbe 0 = durchsichtig (Himmel)"""
    W, H = 512, 256
    farben = [(0, 0, 0), (60, 40, 110), (80, 55, 140), (105, 75, 165), (140, 110, 200),
              (190, 170, 230), (235, 225, 250), (255, 255, 255), (45, 30, 85),
              (210, 200, 240), (170, 150, 215)]
    im = Image.new("P", (W, H), 0)
    px = im.load()
    for x in range(W):
        h1 = 70 + welle(x, [(22, 3, 0.4), (12, 7, 1.1), (5, 17, 2.0), (2, 41, 0.3)])
        h2 = 45 + welle(x, [(16, 5, 2.2), (8, 11, 0.7), (3, 29, 1.4)])
        for y in range(H):
            hy = 190 - y
            if hy < h2:
                px[x, y] = 1 if hy < h2 - 6 else 8
            elif hy < h1:
                schnee = hy > h1 - 9 and h1 > 85
                px[x, y] = 6 if schnee else (3 if (x + y) % 9 < 5 else 2)
            elif hy < h1 + 2:
                px[x, y] = 4
    rnd = random.Random(5)
    for _ in range(9):
        cx, cy = rnd.randrange(W), rnd.randrange(30, 80)
        for k in range(7):
            ox, oy = rnd.randrange(-26, 26), rnd.randrange(-5, 6)
            r = rnd.randrange(8, 15)
            for y in range(cy + oy - r, cy + oy + r):
                for x in range(cx + ox - 2 * r, cx + ox + 2 * r):
                    if ((x - cx - ox) / 2) ** 2 + (y - cy - oy) ** 2 < r * r and 0 <= y < H:
                        hell = 7 if y < cy + oy - r / 3 else (9 if y < cy + oy + r / 3 else 10)
                        px[x % W, y] = hell
    return im, farben


def ebene_vorn():
    """Nahe Huegel mit Baeumen, 512x256, Farbe 0 = durchsichtig"""
    W, H = 512, 256
    farben = [(0, 0, 0), (20, 70, 30), (30, 100, 40), (45, 135, 50), (70, 170, 60),
              (110, 200, 80), (160, 230, 110), (60, 40, 25), (90, 60, 35), (15, 45, 20),
              (230, 240, 140), (120, 80, 45)]
    im = Image.new("P", (W, H), 0)
    px = im.load()
    for x in range(W):
        h = 62 + welle(x, [(18, 2, 0.9), (10, 5, 2.4), (4, 13, 0.2), (2, 31, 1.7)])
        for y in range(H):
            hy = 240 - y
            if hy < h:
                tiefe = h - hy
                if tiefe < 3:
                    px[x, y] = 6
                elif tiefe < 8:
                    px[x, y] = 5
                else:
                    stufe = 4 - min(3, int(tiefe / 14))
                    px[x, y] = stufe if (x // 4 + y // 3) % 7 else stufe - 1
    rnd = random.Random(9)
    for _ in range(26):
        bx = rnd.randrange(W)
        boden = 240 - int(62 + welle(bx, [(18, 2, 0.9), (10, 5, 2.4), (4, 13, 0.2), (2, 31, 1.7)]))
        hoehe = rnd.randrange(16, 30)
        for y in range(boden - 6, boden + 2):           # Stamm
            for dx in (0, 1):
                px[(bx + dx) % W, y] = 8 if dx else 7
        for k in range(hoehe):                          # Krone (Tanne)
            y = boden - 6 - k
            breite = int((hoehe - k) * 0.45) + 1
            for dx in range(-breite, breite + 1):
                px[(bx + dx) % W, y] = 9 if dx < 0 else (2 if dx < breite // 2 else 3)
    return im, farben


def kacheln(im, bank, karte_adr):
    """512x256 Bild -> (Karte 4 KB, Muster, Anzahl); doppelte Kacheln
    (auch gespiegelt) werden nur einmal gespeichert"""
    px = im.load()
    muster = []
    index = {}
    karte = bytearray()
    for ty in range(32):
        for tx in range(64):
            zeilen = tuple(tuple(px[tx * 8 + x, ty * 8 + y] for x in range(8)) for y in range(8))
            eintrag = None
            for fx in (0, 1):
                for fy in (0, 1):
                    z = zeilen[::-1] if fy else zeilen
                    z = tuple(r[::-1] for r in z) if fx else z
                    if z in index:
                        eintrag = index[z] | fx << 10 | fy << 11
                        break
                if eintrag is not None:
                    break
            if eintrag is None:
                nr = len(muster)
                index[zeilen] = nr
                muster.append(zeilen)
                eintrag = nr
            karte += struct.pack("<H", eintrag | bank << 12)
    daten = bytearray()
    for z in muster:
        for zeile in z:
            for x in range(0, 8, 2):
                daten.append(zeile[x] << 4 | zeile[x + 1])
    assert len(muster) <= 1024, len(muster)
    return bytes(karte), bytes(daten), len(muster)


def main():
    os.makedirs(DATEN, exist_ok=True)
    os.makedirs(BILDER, exist_ok=True)

    sw = synthwave()
    idx, farben, vorschau = bild_umrechnen(sw)
    vorschau.resize((640, 480), Image.NEAREST).save(os.path.join(BILDER, "etappe4_synthwave_vorschau.png"))
    daten = idx + bytes(ADR_BILDPAL - ADR_BILD - len(idx)) + pal_bytes(farben)
    mer("bild.mer", ADR_BILD, daten)

    zeilen = ["; Automatisch erzeugt von tools/grafik.py"]
    gesamt = Image.new("RGB", (512, 256), (120, 160, 230))
    for name, (im, farben), bank, k_adr, m_adr in (("a", ebene_hinten(), 1, ADR_KARTE_A, ADR_MUSTER_A),
                                                   ("b", ebene_vorn(), 2, ADR_KARTE_B, ADR_MUSTER_B)):
        karte, muster, anzahl = kacheln(im, bank, k_adr)
        mer(f"ebene_{name}.mer", k_adr, karte + bytes(m_adr - k_adr - len(karte)) + muster)
        print(f"  Ebene {name.upper()}: {anzahl} verschiedene Kacheln")
        f12 = [rgb12(c) for c in farben] + [(0, 0, 0)] * (16 - len(farben))
        zeilen.append(f"pal_ebene_{name}\t; Palettenbank {bank}")
        zeilen.append("\t.byte " + ", ".join(f"${b:02x}" for b in pal_bytes(f12)))
        zeilen.append(f"KACHELN_{name.upper()} = {anzahl}")
        rgb = im.convert("RGB")
        maske = Image.frombytes("L", im.size, bytes(255 if v else 0 for v in im.tobytes()))
        flach = []
        for c in f12:
            flach += [c[0] * 17, c[1] * 17, c[2] * 17]
        im2 = im.copy()
        im2.putpalette(flach + [0] * (768 - len(flach)))
        gesamt.paste(im2.convert("RGB"), (0, 0), maske)
    gesamt.save(os.path.join(BILDER, "etappe4_landschaft_vorschau.png"))
    # Himmelsverlauf fuer Szene 2: Farbe 0 Zeile fuer Zeile (Rasterinterrupt)
    stufen = [(10, 20, 70), (40, 80, 170), (110, 160, 230), (200, 210, 240), (250, 220, 200)]
    himmel = []
    for y in range(HIMMEL_ZEILEN):
        t = y / (HIMMEL_ZEILEN - 1) * (len(stufen) - 1)
        i = min(int(t), len(stufen) - 2)
        himmel.append(rgb12(mischen(stufen[i], stufen[i + 1], t - i)))
    zeilen.append(f"HIMMEL_ZEILEN = {HIMMEL_ZEILEN}")
    zeilen.append("himmel_tab")
    hb = pal_bytes(himmel)
    for i in range(0, len(hb), 16):
        zeilen.append("\t.byte " + ", ".join(f"${b:02x}" for b in hb[i:i + 16]))
    with open(os.path.join(BASIS, "programme", "grafik_daten.inc"), "w") as f:
        f.write("\n".join(zeilen) + "\n")


if __name__ == "__main__":
    main()
