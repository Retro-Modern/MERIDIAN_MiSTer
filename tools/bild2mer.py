#!/usr/bin/env python3
"""Wandelt ein Bild (PNG mit Durchsicht) in eine MERIDIAN-Bitmap fuer STEMPEL:
ein Byte je Pixel, Farben aus der Startpalette des Kerns (0-15 MERIDIAN-16,
16-255 Farbkreis), durchsichtige Pixel = Farbe 0. Als MER-Datei fuer eine
Ladeadresse (auch im Zusatzspeicher).

    ../.venv/bin/python tools/bild2mer.py bild.png ziel.mer --adresse 200000

In BASIC dann:  STEMPEL 65536*$20, x, y, breite, hoehe

Als Modul: startpalette() liefert die 256 Startfarben als (r, g, b) 0-255.
"""
import argparse
import struct

MERIDIAN16 = ["000", "FFF", "D33", "5DD", "A4D", "4C4", "238", "FE5",
              "F92", "952", "F88", "444", "888", "9F9", "8BF", "CCC"]
RB_ART = [(1, 2, 0), (3, 1, 0), (0, 1, 2), (0, 3, 1), (2, 0, 1), (1, 0, 3)]


def startpalette():
    """Wie der Kern sie setzt (rom/kern.asm: palette, regenbogen)"""
    pal = [tuple(int(c, 16) * 17 for c in f) for f in MERIDIAN16]
    rb_auf = [0, 0, 1, 1, 2, 2, 2, 3, 3, 3, 4, 4, 4, 5, 5, 6, 6, 6, 7, 7,
              8, 8, 8, 9, 9, 9, 10, 10, 10, 11, 11, 12, 12, 12, 13, 13, 14, 14, 14, 15]
    for art in RB_ART:
        for k in range(40):
            u = rb_auf[k]
            wert = {0: 0, 1: 15, 2: u, 3: 15 - u}
            pal.append(tuple(wert[a] * 17 for a in art))
    return pal


def naechste(rgb, pal):
    r, g, b = rgb
    best, bi = None, 1
    for i in range(1, 256):                     # 0 ist durchsichtig
        pr, pg, pb = pal[i]
        d = 2 * (r - pr) ** 2 + 4 * (g - pg) ** 2 + 3 * (b - pb) ** 2
        if best is None or d < best:
            best, bi = d, i
    return bi


def wandeln(bild):
    pal = startpalette()
    bild = bild.convert("RGBA")
    merk = {}
    daten = bytearray()
    for y in range(bild.height):
        for x in range(bild.width):
            r, g, b, a = bild.getpixel((x, y))
            if a < 128:
                daten.append(0)
            else:
                k = (r, g, b)
                if k not in merk:
                    merk[k] = naechste(k, pal)
                daten.append(merk[k])
    return bytes(daten)


def mer(lade, daten):
    kopf = b"MER\x01" + struct.pack("<I", lade)[:3] + b"\x00"
    kopf += struct.pack("<I", lade)[:3] + b"\x00" + struct.pack("<I", len(daten))
    return kopf + daten


def main():
    from PIL import Image
    a = argparse.ArgumentParser()
    a.add_argument("quelle")
    a.add_argument("ziel")
    a.add_argument("--adresse", required=True, help="Ladeadresse hex, z.B. 200000")
    o = a.parse_args()
    bild = Image.open(o.quelle)
    daten = wandeln(bild)
    lade = int(o.adresse, 16)
    with open(o.ziel, "wb") as f:
        f.write(mer(lade, daten))
    print(f"{o.ziel}: {bild.width} x {bild.height} ab ${lade:06X} "
          f"-> STEMPEL {lade},x,y,{bild.width},{bild.height}")


if __name__ == "__main__":
    main()
