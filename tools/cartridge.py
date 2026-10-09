#!/usr/bin/env python3
"""Cartridges fuer die Werkstatt (MERIDIAN 1.0) am Mac bauen und pruefen.

Eine Cartridge ist das, was SAVE "name" schreibt, wenn die Werkstatt Daten
hat (rom/ws_datei.asm): das BASIC-Programm, dahinter Abschnitte (Art 1 Byte,
Laenge 3 Byte, Daten), am Ende die Laenge des Programms (3 Byte) und "MWS1".

    cartridge.py liste SPIEL.BAS [--disk BILD.DSK]   Programm und Abschnitte
    cartridge.py bilder SPIEL.BAS ziel/ [--disk BILD.DSK]
                                Sprites, Kacheln, Karten, Look und Zeichensatz
                                als PNG (mit der Palette der Cartridge)

Als Modul: Cartridge() sammelt, was die Werkstatt haelt - 128 Spritemuster,
256 Kacheln, zwei Karten, 64 Klaenge, den Look und den Zeichensatz -, datei()
setzt Programm und Daten zusammen, lesen() nimmt eine Datei wieder
auseinander. Gemalt wird mit Zeichenketten und einer Legende (Zeichen ->
Wert 0-15, "." = 0 = durchsichtig), so wie man es von Hand zeichnet.
"""
import argparse
import os
import sys

HIER = os.path.dirname(os.path.abspath(__file__))
BASIS = os.path.dirname(HIER)
sys.path.insert(0, HIER)
from farben import palette16    # noqa: E402

KENNUNG = b"MWS1"
SPRITES, KACHELN, KARTEN, KLAENGE, LOOK, FONT = 1, 2, 3, 4, 5, 6
NAMEN = {SPRITES: "Sprites", KACHELN: "Kacheln", KARTEN: "Karten",
         KLAENGE: "Klaenge", LOOK: "Look", FONT: "Zeichensatz"}
LAENGEN = {SPRITES: 0x4080, KACHELN: 0x2100, KARTEN: 0x2000,
           KLAENGE: 64 * 132, LOOK: 0x240, FONT: 0x800}
WELLEN = ["dreieck", "saege", "rechteck", "puls25", "puls12", "rauschen", "dreieck+saege", "saege+puls"]
EFFEKTE = ["", "gleiten", "vibrato", "fallen", "einblenden", "ausblenden", "arp", "arp_langsam"]
NOTEN = {"C": 0, "C#": 1, "D": 2, "D#": 3, "E": 4, "F": 5, "F#": 6, "G": 7,
         "G#": 8, "A": 9, "A#": 10, "B": 11}


def note(text):
    """'C-3', 'F#4' oder 'A4' -> 0-83 (C-0 bis B-6, wie im Reiter SOUNDS)"""
    text = text.upper().replace("-", "")
    return NOTEN[text[:-1]] + 12 * int(text[-1])


def malen(zeilen, legende, breite, hoehe):
    """Zeichenketten -> Liste von Werten 0-15 (Zeile fuer Zeile)"""
    if len(zeilen) != hoehe:
        raise ValueError(f"{len(zeilen)} Zeilen statt {hoehe}")
    werte = []
    for z in zeilen:
        if len(z) != breite:
            raise ValueError(f"Zeile '{z}' ist {len(z)} statt {breite} breit")
        for c in z:
            werte.append(0 if c == "." else legende[c])
    return werte


def halbbytes(werte):
    """linkes Pixel ins obere Halbbyte (wie KOBOLD und PINSEL lesen)"""
    return bytes(werte[i] << 4 | werte[i + 1] for i in range(0, len(werte), 2))


class Cartridge:
    def __init__(self):
        self.muster = bytearray(128 * 128)          # 16 Zeilen zu 8 Byte
        self.muster_bank = bytearray(128)
        self.kacheln = bytearray(256 * 32)          # 8 Zeilen zu 4 Byte
        self.kachel_bank = bytearray(256)
        self.karten = [bytearray(64 * 32 * 2), bytearray(64 * 32 * 2)]
        self.klaenge = bytearray(64 * 132)
        self.palette = list(palette16())            # 256 x (r, g, b) 0-15
        self.leuchten = set()
        self.staerke = 0
        self.tinte, self.dx, self.dy, self.ebene_b = 0, 2, 2, False
        self.look_geaendert = False
        self.font = bytearray(open(os.path.join(BASIS, "rom", "zeichensatz.bin"), "rb").read()[:2048])
        self.font_geaendert = False

    # --- malen -----------------------------------------------------------
    def sprite(self, n, zeilen, legende, bank):
        """Muster n (0-127): 16 Zeichenketten zu 16 Zeichen"""
        self.muster[n * 128:(n + 1) * 128] = halbbytes(malen(zeilen, legende, 16, 16))
        self.muster_bank[n] = bank

    def kachel(self, n, zeilen, legende, bank):
        """Kachel n (1-255, 0 bleibt leer): 8 Zeichenketten zu 8 Zeichen"""
        if not 1 <= n <= 255:
            raise ValueError("Kachel 0 bleibt leer")
        self.kacheln[n * 32:(n + 1) * 32] = halbbytes(malen(zeilen, legende, 8, 8))
        self.kachel_bank[n] = bank

    def kachel_werte(self, n, werte, bank):
        """Kachel n aus 64 Werten (0-15)"""
        self.kacheln[n * 32:(n + 1) * 32] = halbbytes(werte)
        self.kachel_bank[n] = bank

    def setze(self, karte, x, y, kachel, bank=None, fx=False, fy=False):
        """Feld x (0-63), y (0-31) der Karte 1/2: Kachel, ohne Bank die der Kachel"""
        if bank is None:
            bank = self.kachel_bank[kachel]
        w = kachel & 0x3FF | fx << 10 | fy << 11 | bank << 12
        i = (y * 64 + x) * 2
        self.karten[karte - 1][i:i + 2] = w.to_bytes(2, "little")

    def feld(self, karte, x, y):
        i = (y * 64 + x) * 2
        return int.from_bytes(self.karten[karte - 1][i:i + 2], "little") & 0x3FF

    def klang(self, n, schritte, tempo=0, schleife=False):
        """Klang n (0-63): bis 32 Schritte (Note, Welle, Lautstaerke, Effekt);
        Note als Zahl oder 'C-3', Welle/Effekt als Zahl oder Name; None = Pause"""
        if len(schritte) > 32:
            raise ValueError("hoechstens 32 Schritte")
        k = bytearray(132)
        k[0], k[1] = tempo, 1 if schleife else 0
        for s, schritt in enumerate(schritte):
            if schritt is None:
                continue
            nt, welle, laut, fx = schritt
            nt = note(nt) if isinstance(nt, str) else nt
            welle = WELLEN.index(welle) if isinstance(welle, str) else welle
            fx = EFFEKTE.index(fx) if isinstance(fx, str) else fx
            if not (0 <= nt <= 83 and 0 <= welle <= 7 and 0 <= laut <= 15 and 0 <= fx <= 7):
                raise ValueError(f"Klang {n}, Schritt {s}: {schritt}")
            k[4 + s * 4:8 + s * 4] = bytes((nt, welle, laut, fx))
        self.klaenge[n * 132:(n + 1) * 132] = k

    def farbe(self, i, r, g, b):
        """Farbe i (0-255) der Cartridge-Palette, Anteile 0-15"""
        self.palette[i] = (r, g, b)
        self.look_geaendert = True

    def leuchte(self, farben, staerke=None):
        self.leuchten.update(farben)
        if staerke is not None:
            self.staerke = staerke
        self.look_geaendert = True

    def tusche(self, tinte, dx=2, dy=2, ebene_b=False):
        self.tinte, self.dx, self.dy, self.ebene_b = tinte, dx, dy, ebene_b
        self.look_geaendert = True

    def zeichen(self, code, zeilen):
        """Zeichen code (0-255): 8 Zeichenketten zu 8, '#' gesetzt, '.' leer"""
        for y, z in enumerate(zeilen):
            if len(z) != 8:
                raise ValueError(f"Zeichen {code}: Zeile '{z}'")
            self.font[code * 8 + y] = sum(0x80 >> x for x, c in enumerate(z) if c != ".")
        self.font_geaendert = True

    # --- Datei -----------------------------------------------------------
    def look_bytes(self):
        d = bytearray(0x240)
        d[0] = (1 if self.look_geaendert else 0) | (2 if self.font_geaendert else 0)
        d[1], d[2], d[3], d[4], d[5] = self.staerke, self.tinte, self.dx, self.dy, 1 if self.ebene_b else 0
        for f in self.leuchten:
            d[16 + f // 8] |= 1 << (f % 8)
        for i, (r, g, b) in enumerate(self.palette):
            d[64 + 2 * i] = g << 4 | b
            d[65 + 2 * i] = r
        return bytes(d)

    def abschnitte(self):
        """wie SAVE: nur, was nicht leer ist; Look und Zeichensatz nur geaendert"""
        teile = []
        if any(self.muster) or any(self.muster_bank):
            teile.append((SPRITES, bytes(self.muster) + bytes(self.muster_bank)))
        if any(self.kacheln) or any(self.kachel_bank):
            teile.append((KACHELN, bytes(self.kacheln) + bytes(self.kachel_bank)))
        if any(self.karten[0]) or any(self.karten[1]):
            teile.append((KARTEN, bytes(self.karten[0]) + bytes(self.karten[1])))
        if any(self.klaenge):
            teile.append((KLAENGE, bytes(self.klaenge)))
        if self.look_geaendert or self.font_geaendert:
            teile.append((LOOK, self.look_bytes()))
        if self.font_geaendert:
            teile.append((FONT, bytes(self.font)))
        return teile

    def datei(self, programm):
        teile = self.abschnitte()
        if not teile:
            return bytes(programm)
        aus = bytearray(programm)
        for art, daten in teile:
            assert len(daten) == LAENGEN[art], (art, len(daten))
            aus += bytes([art]) + len(daten).to_bytes(3, "little") + daten
        aus += len(programm).to_bytes(3, "little") + KENNUNG
        if len(aus) > 128 * 1024:
            raise ValueError(f"Datei {len(aus)} Byte, LOAD nimmt hoechstens 128 KB")
        return bytes(aus)


def lesen(daten):
    """Datei -> (Programm, Cartridge, [(Art, Laenge), ...]) wie LOAD sie verteilt"""
    c = Cartridge()
    c.palette = list(palette16())
    if len(daten) < 7 or daten[-4:] != KENNUNG:
        return daten, c, []
    plen = int.from_bytes(daten[-7:-4], "little")
    prog, i, ende, liste = daten[:plen], plen, len(daten) - 7, []
    while i < ende:
        art, n = daten[i], int.from_bytes(daten[i + 1:i + 4], "little")
        d = daten[i + 4:i + 4 + n]
        liste.append((art, n))
        if LAENGEN.get(art) == n:
            if art == SPRITES:
                c.muster[:], c.muster_bank[:] = d[:0x4000], d[0x4000:]
            elif art == KACHELN:
                c.kacheln[:], c.kachel_bank[:] = d[:0x2000], d[0x2000:]
            elif art == KARTEN:
                c.karten = [bytearray(d[:0x1000]), bytearray(d[0x1000:])]
            elif art == KLAENGE:
                c.klaenge[:] = d
            elif art == LOOK:
                c.look_geaendert, c.font_geaendert = bool(d[0] & 1), bool(d[0] & 2)
                c.staerke, c.tinte, c.dx, c.dy, c.ebene_b = d[1], d[2], d[3], d[4], bool(d[5])
                c.leuchten = {f for f in range(256) if d[16 + f // 8] >> (f % 8) & 1}
                c.palette = [(d[65 + 2 * f] & 15, d[64 + 2 * f] >> 4, d[64 + 2 * f] & 15) for f in range(256)]
            elif art == FONT:
                c.font[:] = d
        i += 4 + n
    return prog, c, liste


# --- Bilder zum Pruefen ------------------------------------------------------
def rgb(c, f):
    r, g, b = c.palette[f]
    return (r * 17, g * 17, b * 17)


def bild_kachel(c, n, bank=None, flip=0):
    """8 x 8 Werte -> Farben (None = durchsichtig)"""
    bank = c.kachel_bank[n] if bank is None else bank
    px = []
    for y in range(8):
        for x in range(8):
            xx = 7 - x if flip & 1 else x
            yy = 7 - y if flip & 2 else y
            b = c.kacheln[n * 32 + yy * 4 + xx // 2]
            v = b >> 4 if xx % 2 == 0 else b & 15
            px.append(None if v == 0 else bank * 16 + v)
    return px


def bild_karte(c, karte, grund=None):
    """ganze Karte 512 x 256 als Liste von Palettennummern (None = leer)"""
    bild = [grund] * (512 * 256)
    for ty in range(32):
        for tx in range(64):
            i = (ty * 64 + tx) * 2
            w = int.from_bytes(c.karten[karte - 1][i:i + 2], "little")
            n = w & 0x3FF
            if n == 0 or n > 255:
                continue
            px = bild_kachel(c, n, w >> 12, (w >> 10) & 3)
            for y in range(8):
                for x in range(8):
                    if px[y * 8 + x] is not None:
                        bild[(ty * 8 + y) * 512 + tx * 8 + x] = px[y * 8 + x]
    return bild


def bild_muster(c, n, bank=None):
    bank = c.muster_bank[n] if bank is None else bank
    px = []
    for i in range(256):
        b = c.muster[n * 128 + i // 2]
        v = b >> 4 if i % 2 == 0 else b & 15
        px.append(None if v == 0 else bank * 16 + v)
    return px


def bilder(c, ziel, zoom=3):
    from PIL import Image
    os.makedirs(ziel, exist_ok=True)
    grund = (24, 24, 32)

    def speichern(name, w, h, px, z=zoom):
        im = Image.new("RGB", (w, h))
        im.putdata([grund if f is None else rgb(c, f) for f in px])
        im.resize((w * z, h * z), Image.NEAREST).save(os.path.join(ziel, name))

    # Sprites: 16 x 8 Muster
    px = [None] * (256 * 128)
    for n in range(128):
        m = bild_muster(c, n)
        ox, oy = (n % 16) * 16, (n // 16) * 16
        for i, f in enumerate(m):
            px[(oy + i // 16) * 256 + ox + i % 16] = f
    speichern("sprites.png", 256, 128, px)
    # Kacheln: 16 x 16
    px = [None] * (128 * 128)
    for n in range(1, 256):
        k = bild_kachel(c, n)
        ox, oy = (n % 16) * 8, (n // 16) * 8
        for i, f in enumerate(k):
            px[(oy + i // 8) * 128 + ox + i % 8] = f
    speichern("kacheln.png", 128, 128, px, zoom * 2)
    # Karten einzeln und uebereinander (Karte 2 vor Karte 1)
    k1, k2 = bild_karte(c, 1), bild_karte(c, 2)
    speichern("karte1.png", 512, 256, k1, 2)
    speichern("karte2.png", 512, 256, k2, 2)
    speichern("karten.png", 512, 256, [b if b is not None else a for a, b in zip(k1, k2)], 2)
    # Palette 16 x 16, leuchtende Farben mit Rahmen
    im = Image.new("RGB", (16 * 12, 16 * 12), grund)
    for f in range(256):
        x, y = (f % 16) * 12, (f // 16) * 12
        for yy in range(10):
            for xx in range(10):
                rand = f in c.leuchten and (xx in (0, 9) or yy in (0, 9))
                im.putpixel((x + 1 + xx, y + 1 + yy), (255, 255, 255) if rand else rgb(c, f))
    im.resize((16 * 24, 16 * 24), Image.NEAREST).save(os.path.join(ziel, "palette.png"))
    # Zeichensatz 32 x 8
    px = []
    for y in range(64):
        for x in range(256):
            code = (y // 8) * 32 + x // 8
            px.append(1 if c.font[code * 8 + y % 8] & (0x80 >> (x % 8)) else 0)
    im = Image.new("RGB", (256, 64))
    im.putdata([(240, 240, 240) if p else (20, 20, 40) for p in px])
    im.resize((256 * zoom, 64 * zoom), Image.NEAREST).save(os.path.join(ziel, "font.png"))


def datei_holen(name, disk):
    if disk:
        import disk as d
        return d.Fat16(disk).lesen(name)
    return open(name, "rb").read()


def main():
    a = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    u = a.add_subparsers(dest="befehl", required=True)
    b = u.add_parser("liste"); b.add_argument("datei"); b.add_argument("--disk")
    b = u.add_parser("bilder"); b.add_argument("datei"); b.add_argument("ziel"); b.add_argument("--disk")
    o = a.parse_args()
    daten = datei_holen(o.datei, o.disk)
    prog, c, liste = lesen(daten)
    if o.befehl == "liste":
        print(f"{o.datei}: {len(daten)} Byte, Programm {len(prog)} Byte")
        if not liste:
            print("  keine Werkstatt-Daten (kein MWS1)")
        for art, n in liste:
            print(f"  Abschnitt {art} {NAMEN.get(art, '?'):12s} {n:6d} Byte"
                  + ("" if LAENGEN.get(art) == n else "  (unbekannt oder falsche Laenge: LOAD ueberspringt)"))
        if liste:
            belegt = sum(1 for n in range(128) if any(c.muster[n * 128:(n + 1) * 128]))
            kach = sum(1 for n in range(256) if any(c.kacheln[n * 32:(n + 1) * 32]))
            kl = sum(1 for n in range(64) if any(c.klaenge[n * 132:(n + 1) * 132]))
            print(f"  {belegt} Muster, {kach} Kacheln, {kl} Klaenge, {len(c.leuchten)} leuchtende Farben "
                  f"(Staerke {c.staerke}), Tusche {c.tinte} ({c.dx},{c.dy}{', Ebene B' if c.ebene_b else ''})")
    else:
        bilder(c, o.ziel)
        print(f"Bilder in {o.ziel}")


if __name__ == "__main__":
    main()
