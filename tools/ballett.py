#!/usr/bin/env python3
"""Grafik und Tabellen fuer das Vorfuehrprogramm BALLETT (Etappe 7).

  programme/daten/ballett_grafik.mer  ab $01:C000:
      $01:C000  vier Baelle 16x16 (256 Farben, 0 = durchsichtig), je 256 Byte
      $01:C400  Kacheln fuers Logo (128 Kacheln zu 32 Byte)
      $01:E000  Kachelkarte 64x32 (Logo in Kachelzeilen 1-4)
  programme/ballett_daten.inc  Palette, Himmelsverlauf, Rasterbalken,
      Sinustabellen, Bahnen der Baelle

    ../.venv/bin/python tools/ballett.py
"""
import math
import os

from PIL import Image

from kobolde import kugel

HIER = os.path.dirname(os.path.abspath(__file__))
BASIS = os.path.join(HIER, "..")

GRAFIK = 0x01C000
KACHELN = 0x01C400
KARTE = 0x01E000
HOEHE = 176                         # Bitmap-Zeilen, darunter Text


def rgb12(c):
    return tuple(min(15, max(0, round(v / 17))) for v in c)


def pal_bytes(c):
    r, g, b = rgb12(c)
    return [g << 4 | b, r]


def mischen(a, b, t):
    return tuple(a[k] + (b[k] - a[k]) * t for k in range(3))


# Palette: 0 Himmel/Raster (setzt LOTSE), 1-15 Text, 16-75 Baelle, 80-95 Logo
TEXT = [(0, 0, 0), (255, 255, 255), (175, 185, 215), (255, 205, 60), (90, 220, 255),
        (255, 150, 50), (100, 235, 110), (60, 120, 255), (90, 90, 130), (255, 110, 200),
        (80, 230, 100), (170, 240, 80), (255, 230, 60), (255, 160, 40), (255, 90, 40), (255, 40, 60)]
BALLFARBEN = [(255, 60, 50), (70, 120, 255), (60, 220, 80), (255, 200, 40)]
LOGO = [(0, 0, 0)] + [mischen((255, 250, 220), (200, 90, 20), t / 7) for t in range(8)] + \
       [(40, 10, 50)] + [(0, 0, 0)] * 6


def kugel_palette(c):
    """wie bei KOBOLDE, aber die Schattenseite heller (vor dunklem Himmel)"""
    p = [(0, 0, 0)]
    for i in range(1, 13):
        t = (i - 1) / 11
        p.append(tuple(round(c[k] * (0.38 + 0.62 * t)) for k in range(3)))
    p += [tuple(min(255, round(c[k] * 0.4 + 160)) for k in range(3)), (235, 235, 245), (255, 255, 255)]
    return p


def palette():
    p = [(0, 0, 0)] * 96
    for i, c in enumerate(TEXT):
        p[i] = c
    for b, farbe in enumerate(BALLFARBEN):
        kp = kugel_palette(farbe)
        for s in range(1, 16):
            p[16 + b * 15 + s - 1] = kp[s]
    for i, c in enumerate(LOGO):
        p[80 + i] = c
    return p


def baelle():
    m = kugel()
    out = bytearray()
    for b in range(4):
        for y in range(16):
            for x in range(16):
                s = m[y][x]
                out.append(0 if s == 0 else 16 + b * 15 + s - 1)
    return out


def logo():
    """MERIDIAN aus dem Zeichensatz, vierfach, als 4-Bit-Kacheln mit Bank 5"""
    font = open(os.path.join(BASIS, "rom", "zeichensatz.bin"), "rb").read()
    w, h = 8 * 32, 32
    bild = [[0] * w for _ in range(h)]
    for i, ch in enumerate("MERIDIAN"):
        for y in range(8):
            byte = font[ord(ch) * 8 + y]
            for x in range(8):
                if byte & (0x80 >> x):
                    for dy in range(4):
                        for dx in range(4):
                            yy, xx = y * 4 + dy, i * 32 + x * 4 + dx
                            bild[yy][xx] = 1 + min(7, yy * 8 // 28)      # Chromverlauf
    # dunkle Kante rechts unten
    for y in range(h - 1, -1, -1):
        for x in range(w - 1, -1, -1):
            if bild[y][x] == 0 and x > 0 and y > 0 and 1 <= bild[y - 1][x - 1] <= 8:
                bild[y][x] = 9
    kacheln = [bytes(32)]                                   # Kachel 0: leer
    karte = [[0] * 64 for _ in range(32)]
    for ty in range(4):
        for tx in range(32):
            k = bytearray()
            for y in range(8):
                for x in range(0, 8, 2):
                    a, b = bild[ty * 8 + y][tx * 8 + x], bild[ty * 8 + y][tx * 8 + x + 1]
                    k.append(a << 4 | b)
            if any(k):
                karte[1 + ty][12 + tx] = len(kacheln) | (5 << 12)   # bei SX = 64 ab x = 32
                kacheln.append(bytes(k))
    assert len(kacheln) <= 128
    karte_b = bytearray()
    for zeile in karte:
        for e in zeile:
            karte_b += bytes([e & 0xFF, e >> 8])
    return b"".join(kacheln), karte_b, bild


def zeile(werte, art=".byte"):
    return f"\t{art} " + ", ".join(werte)


def main():
    pal = palette()
    ball = baelle()
    kach, karte, bild = logo()
    daten = bytearray(KARTE + len(karte) - GRAFIK)
    daten[0:len(ball)] = ball
    daten[KACHELN - GRAFIK:KACHELN - GRAFIK + len(kach)] = kach
    daten[KARTE - GRAFIK:] = karte
    kopf = b"MER\x01" + GRAFIK.to_bytes(3, "little") + b"\x00" + GRAFIK.to_bytes(3, "little") + \
        b"\x00" + len(daten).to_bytes(4, "little")
    os.makedirs(os.path.join(BASIS, "programme", "daten"), exist_ok=True)
    with open(os.path.join(BASIS, "programme", "daten", "ballett_grafik.mer"), "wb") as f:
        f.write(kopf + daten)

    z = ["; Automatisch erzeugt von tools/ballett.py - nicht von Hand aendern", ""]
    z.append(f"HOEHE = {HOEHE}")
    z.append("palette\t\t\t; Eintraege 0-95: gggg bbbb, ---- rrrr")
    for i in range(0, 96, 8):
        z.append(zeile([f"${v:02x}" for c in pal[i:i + 8] for v in pal_bytes(c)]))
    # Himmel: Farbe 0 je Bitmapzeile
    himmel = []
    for y in range(HOEHE):
        if y < 110:
            c = mischen((15, 10, 70), (120, 30, 160), y / 110)
        else:
            c = mischen((120, 30, 160), (255, 120, 70), (y - 110) / (HOEHE - 110))
        himmel.append(c)
    z.append("himmel\t\t\t; je Zeile lo, hi")
    for i in range(0, HOEHE, 8):
        z.append(zeile([f"${v:02x}" for c in himmel[i:i + 8] for v in pal_bytes(c)]))
    # Rasterbalken im Textbereich: Grund und drei Balken zu 11 Zeilen
    grund = (12, 12, 40)
    z.append("raster_grund")
    z.append(zeile([f"${v:02x}" for v in pal_bytes(grund)]))
    profil = [0.25, 0.45, 0.65, 0.85, 1, 1, 1, 0.85, 0.65, 0.45, 0.25]
    for n, farbe in enumerate([(255, 60, 60), (60, 230, 90), (70, 120, 255)]):
        z.append(f"balken{n}")
        z.append(zeile([f"${v:02x}" for p in profil for v in pal_bytes(mischen(grund, farbe, p))]))
    # Sinus: Balkenposition 0..53, Wellen +-32 (mit Vorzeichen)
    z.append("sin_balken")
    for i in range(0, 256, 16):
        z.append(zeile([str(round(26.5 + 26.5 * math.sin(2 * math.pi * k / 256))) for k in range(i, i + 16)]))
    z.append("sin_welle")
    for i in range(0, 256, 16):
        z.append(zeile([str(round(32 * math.sin(2 * math.pi * k / 256)) & 0xFF) for k in range(i, i + 16)]))
    # Bahnen der Baelle: X 0..304, Y-Versatz (Zeile * 320) fuer Y 0..160
    z.append("bahn_x")
    for i in range(0, 256, 8):
        z.append(zeile([str(round(152 + 152 * math.sin(2 * math.pi * k / 256))) for k in range(i, i + 8)], ".word"))
    z.append("bahn_y")
    for i in range(0, 256, 8):
        z.append(zeile([str(round(80 + 80 * math.sin(2 * math.pi * k / 256)) * 320) for k in range(i, i + 8)], ".word"))
    with open(os.path.join(BASIS, "programme", "ballett_daten.inc"), "w", encoding="latin-1") as f:
        f.write("\n".join(z) + "\n")

    # Vorschau: Logo und Baelle
    img = Image.new("RGB", (256 * 3, 56 * 3), (20, 10, 60))
    for y in range(32):
        for x in range(256):
            v = bild[y][x]
            if v:
                c = tuple(k * 17 for k in rgb12(pal[80 + v]))
                for d in range(9):
                    img.putpixel((x * 3 + d % 3, y * 3 + d // 3), c)
    for b in range(4):
        for y in range(16):
            for x in range(16):
                v = ball[b * 256 + y * 16 + x]
                if v:
                    c = tuple(k * 17 for k in rgb12(pal[v]))
                    for d in range(9):
                        img.putpixel((b * 60 + x * 3 + d % 3, 36 * 3 + y * 3 + d // 3 - 4), c)
    img.save(os.path.join(BASIS, "doku", "bilder", "etappe7_grafik_vorschau.png"))
    print(f"ballett_grafik.mer: {len(daten)} Bytes ab ${GRAFIK:06X}, {len(kach) // 32} Kacheln")


if __name__ == "__main__":
    main()
