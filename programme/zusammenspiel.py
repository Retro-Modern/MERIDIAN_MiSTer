#!/usr/bin/env python3
"""Daten fuer ZUSAMMENSPIEL (Etappe 9c): alles, was BASIC aus dem
Zusatzspeicher holt - geladen per Netz (BOTE, Etappe 9b).

  daten/zusammenspiel_logo.mer    "MERIDIAN" 256 x 32, ab $20:0000 (STEMPEL)
  daten/zusammenspiel_klang.mer   Ball-Aufprall (ElevenLabs), ab $21:0000 (SAMPLE)
  zusammenspiel.bas               das BASIC-Programm
  ../doku/bilder/etappe9c_logo.png  Vorschau

    ../.venv/bin/python programme/zusammenspiel.py
"""
import os
import subprocess
import sys

HIER = os.path.dirname(os.path.abspath(__file__))
BASIS = os.path.join(HIER, "..")
sys.path.insert(0, os.path.join(BASIS, "tools"))
from bild2mer import mer, startpalette      # noqa: E402

LOGO, KLANG = 0x200000, 0x210000


def logo():
    """MERIDIAN aus dem Zeichensatz des Kerns, vierfach, Sonnenuntergang"""
    font = open(os.path.join(BASIS, "rom", "zeichensatz.bin"), "rb").read()
    w, h = 256, 32
    bild = [[0] * w for _ in range(h)]
    for i, ch in enumerate("MERIDIAN"):
        for y in range(8):
            byte = font[ord(ch) * 8 + y]
            for x in range(8):
                if byte & (0x80 >> x):
                    for dy in range(4):
                        for dx in range(4):
                            yy, xx = y * 4 + dy, i * 32 + x * 4 + dx
                            bild[yy][xx] = 56 - yy                 # gelb oben, rot unten
    for y in range(h - 1, 0, -1):                                  # Schatten
        for x in range(w - 1, 0, -1):
            if bild[y][x] == 0 and 16 <= bild[y - 1][x - 1] <= 56:
                bild[y][x] = 11
    return w, h, bytes(v for zeile in bild for v in zeile)


def main():
    daten = os.path.join(HIER, "daten")
    w, h, pix = logo()
    with open(os.path.join(daten, "zusammenspiel_logo.mer"), "wb") as f:
        f.write(mer(LOGO, pix))
    try:
        from PIL import Image
        pal = startpalette()
        bild = Image.new("RGB", (w, h))
        bild.putdata([pal[v] if v else (16, 24, 64) for v in pix])
        bild.resize((w * 3, h * 3), Image.NEAREST).save(
            os.path.join(BASIS, "doku", "bilder", "etappe9c_logo.png"))
    except ImportError:
        pass
    aus = subprocess.run([sys.executable, os.path.join(BASIS, "tools", "sample2mer.py"),
                          os.path.join(BASIS, "klaenge", "roh", "ball_boing.mp3"),
                          os.path.join(daten, "zusammenspiel_klang.mer"),
                          "--adresse", f"{KLANG:06X}", "--hz", "22050", "--sekunden", "0.4"],
                         capture_output=True, text=True, check=True).stdout
    print(aus.strip())
    laenge = int(aus.split(": ")[1].split(" ")[0])
    with open(os.path.join(HIER, "zusammenspiel.bas.vorlage")) as f:
        prog = f.read().replace("@LAENGE@", str(laenge))
    with open(os.path.join(HIER, "zusammenspiel.bas"), "w") as f:
        f.write(prog)
    print(f"Logo {w} x {h} ab ${LOGO:06X}, Programm zusammenspiel.bas")


if __name__ == "__main__":
    main()
