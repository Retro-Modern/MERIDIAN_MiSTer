#!/usr/bin/env python3
"""Wandelt ein Bild (PNG mit Durchsicht) in eine MERIDIAN-Bitmap fuer STEMPEL:
ein Byte je Pixel, Farben aus der Startpalette des Kerns (MERIDIAN-256,
tools/farben.py), durchsichtige Pixel = Farbe 0. Als MER-Datei fuer eine
Ladeadresse (auch im Zusatzspeicher).

    ../.venv/bin/python tools/bild2mer.py bild.png ziel.mer --adresse 200000

In BASIC dann:  STEMPEL 65536*$20, x, y, breite, hoehe

Als Modul: startpalette() liefert die 256 Startfarben als (r, g, b) 0-255.
"""
import argparse
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from farben import startpalette        # noqa: E402  (MERIDIAN-256 wie im Kern)


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
