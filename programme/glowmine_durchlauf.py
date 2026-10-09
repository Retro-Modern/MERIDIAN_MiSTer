#!/usr/bin/env python3
"""GLOWMINE durchspielen lassen: die Spiellogik in Python und ein geplanter Weg.

Ein Lauf mit dem Joystick des Simulators haengt am Takt - braucht ein
Schritt einmal drei Bilder statt zwei, verrutscht alles danach. Deshalb
rechnet dieses Werkzeug die Hauptschleife von GLOWMINE nach (dieselben
Zahlen, dieselbe Reihenfolge) und spielt damit einen Weg, der in Schritten
angegeben ist. Es prueft, ob er alle Muenzen holt und den Ausgang erreicht,
auch wenn die Fledermaeuse ein paar Schritte frueher oder spaeter kommen,
und schreibt auf Wunsch eine Testfassung des Spiels, die die Eingaben aus
DATA liest statt vom Joystick.

    python3 programme/glowmine_durchlauf.py                pruefen
    python3 programme/glowmine_durchlauf.py --test GMTEST.BAS [--disk BILD.DSK]
        Testfassung schreiben; im Simulator: LOAD "GMTEST", RUN, Feuer
        (z. B. MERIDIAN_JOY="300:16;310:0")

Weg: Paare j:n - n Schritte lang die Eingabe j (Bits wie JOY(1): 1 rechts,
2 links, 16 Feuer = Sprung).
"""
import argparse
import math
import os
import sys

HIER = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HIER)
sys.path.insert(0, os.path.join(HIER, "..", "tools"))
import glowmine     # noqa: E402

WEG = ("1:10 17:1 1:13 2:4 1:8 2:8 18:1 2:16 2:3 1:13 17:1 1:14 0:3 2:5 18:1 2:20 2:6 0:3 1:30 0:2 "
       "1:5 17:1 1:14 0:3 1:10 0:12 1:24 0:2 2:10 0:24 17:1 1:16 0:2 1:2 0:2 1:2 17:1 1:5 0:10 1:4 "
       "0:6 1:12 0:2 1:26 17:1 1:16 0:2 1:16 0:4 2:20 18:1 2:16 0:4 2:5 16:1 0:20 2:6 0:2 1:8 17:1 "
       "1:12 0:6 1:6 0:20 17:1 1:12 0:4 1:2 0:2 1:2 0:60 17:1 1:10 0:6 1:2 0:2 1:6 0:10")

C, MUENZEN, FLEDER, TUER, START = glowmine.bauen()
Z = [0] * 256                               # wie Z() im Programm
for _t in range(1, 19):
    Z[_t] = 1
for _t in range(32, 35):
    Z[_t] = 2
Z[40], Z[41], Z[42] = 8, 4, 4
for _t in range(50, 56):
    Z[_t] = 16
D = [int(6 * math.sin(i * .3927) + .5) for i in range(16)]


def maske(bild):
    return {(x, y) for y, z in enumerate(bild) for x, ch in enumerate(z) if ch != "."}


KNAPPE = {0: maske(glowmine.KNAPPE_STEHT), 1: maske(glowmine.KNAPPE_GEHT1),
          5: maske(glowmine.KNAPPE_GEHT2), 3: maske(glowmine.KNAPPE_SPRINGT)}
FLEDERMAUS = {8: maske(glowmine.FLEDER_OBEN), 12: maske(glowmine.FLEDER_UNTEN)}


class Spiel:
    """Die Zeilen 340-580 und 600-740 von glowmine.bas"""

    def __init__(self, versatz=0):
        self.karte = bytearray(C.karten[1])
        self.x, self.y = START[0] * 8, START[1] * 8
        self.xt, self.yt = self.x * .125, self.y * .125
        self.w = self.g = self.yf = self.vt = self.vu = 0
        self.tf = .5
        self.nc, self.mn, self.lv, self.q, self.schritt = 0, len(MUENZEN), 3, 0, 0
        self.kx, self.ky = self.x, self.y
        self.tod = []
        self.b = [[f[0] * 8, r, f[2] * 8, f[3] * 8 - 16, f[1] * 8] for f, r in zip(FLEDER, (1.5, -1.5))]
        for b in self.b:                    # Fledermaeuse frueher (+) oder spaeter (-) unterwegs
            if versatz < 0:
                b[1] = -b[1]
            for _ in range(abs(versatz)):
                self.fliegen(b)
            if versatz < 0:
                b[1] = -b[1]

    @staticmethod
    def fliegen(b):
        b[0] += b[1]
        if b[0] < b[2] or b[0] > b[3]:
            b[1] = -b[1]

    def kachel(self, x, y):
        x, y = int(x), int(y)
        if not (0 <= x < 64 and 0 <= y < 32):
            return 0
        return int.from_bytes(self.karte[(y * 64 + x) * 2:(y * 64 + x) * 2 + 2], "little") & 0x3FF

    def setze(self, x, y, t):
        i = (int(y) * 64 + int(x)) * 2
        self.karte[i:i + 2] = (t | C.kachel_bank[t] << 12).to_bytes(2, "little")

    def getroffen(self, warum):
        self.tod.append((self.schritt, warum, self.x, self.y))
        self.lv -= 1
        if self.lv == 0:
            self.q = 1
            return
        self.x, self.y = self.kx, self.ky
        self.xt, self.yt = self.x * .125, self.y * .125
        self.w = self.g = 0

    def landen(self, a, u):
        if a & 4:
            return self.getroffen("Lava")
        if (a & 3) == 0:
            return
        n = int(u) * 8
        if (a & 1) == 0 and self.y - self.w + 16 > n:
            return
        self.y = n - 16
        self.yt = self.y * .125
        self.yf = self.yt + 2
        self.w, self.g = 0, 1
        if a & 1 and self.x > self.kx + 96:
            self.kx, self.ky = self.x, self.y

    def schritt_tun(self, j):
        self.schritt += 1
        k = self.kachel
        v = self.vt = 0
        if j & 1:
            v, self.vt, self.vu, self.tf = 2.5, .3125, 1.8125, .5
        if j & 2:
            v, self.vt, self.vu, self.tf = -2.5, -.3125, .0625, 1.375
        if v:
            u = self.xt + self.vu
            if (Z[k(u, self.yt + .375)] | Z[k(u, self.yt + 1.625)]) & 1:
                v = self.vt = 0
        self.x += v
        self.xt += self.vt
        if not self.g:
            self.w = min(self.w + .65, 6)
            self.y += self.w
            self.yt = self.y * .125
            if self.w < 0:
                u = self.yt + .25
                if (Z[k(self.xt + .5, u)] | Z[k(self.xt + 1.375, u)]) & 1:
                    self.y = int(u) * 8 + 6
                    self.yt = self.y * .125
                    self.w = 0
            if self.w > 0:
                u = self.yt + 2
                a = Z[k(self.xt + .5, u)] | Z[k(self.xt + 1.375, u)]
                if a:
                    self.landen(a, u)
                    if self.q:
                        return
        else:
            if v and (Z[k(self.xt + self.tf, self.yf)] & 3) == 0:
                self.g = self.w = 0
            if j & 24 and self.g:
                self.g, self.w = 0, -6.5
        a = k(self.xt + 1, self.yt + 1)
        if Z[a] == 16:
            self.q = 2
            return
        if Z[a] == 8:
            self.setze(self.xt + 1, self.yt + 1, 0)
            self.nc += 1
            if self.nc == self.mn:
                for yy in range(3):
                    for xx in range(2):
                        self.setze(TUER[0] + xx, TUER[1] + yy, 50 + yy * 2 + xx)
        p = 3
        if self.g:
            p = 1 + (int(self.x) & 4) if v else 0
        for b in self.b:
            self.fliegen(b)
        for b in self.b:                    # HIT(0): Punkte beruehren sich (1 Punkt Zugabe)
            bx, by = int(b[0]), b[4] + D[int(b[0]) & 15]
            px, py = int(self.x), int(self.y)
            if abs(bx - px) < 18 and abs(by - py) < 18:
                fm = FLEDERMAUS[8 + (int(b[0]) & 4)]
                for sx, sy in KNAPPE[p]:
                    dx, dy = px + sx - bx, py + sy - by
                    if {(dx, dy), (dx + 1, dy), (dx - 1, dy), (dx, dy + 1), (dx, dy - 1)} & fm:
                        return self.getroffen("Fledermaus")


def spielen(weg, versatz=0):
    s = Spiel(versatz)
    for teil in weg.split():
        j, n = map(int, teil.split(":"))
        for _ in range(n):
            if not s.q:
                s.schritt_tun(j)
    return s


def testfassung(weg):
    """glowmine.bas mit Eingaben aus DATA statt vom Joystick"""
    text = open(os.path.join(HIER, "glowmine.bas"), encoding="utf-8").read()
    zeile = next(z for z in text.splitlines() if z.startswith("350 "))
    text = text.replace(zeile, "350 if rn<1 then read j,rn\n355 rn=rn-1")
    werte = [w for teil in weg.split() for w in teil.split(":")]
    daten = [f"{9500 + i // 20 * 10} data " + ",".join(werte[i:i + 20]) for i in range(0, len(werte), 20)]
    return text.rstrip("\n") + "\n" + "\n".join(daten) + "\n"


def main():
    a = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    a.add_argument("--test", help="Testfassung als Cartridge schreiben (z. B. GMTEST.BAS)")
    a.add_argument("--disk", help="... direkt auf diese Diskette")
    o = a.parse_args()
    s = spielen(WEG)
    print(f"{s.schritt} Schritte ({s.schritt / 30:.0f} s), Gold {s.nc}/{s.mn}, Leben {s.lv}, "
          f"{'Ausgang erreicht' if s.q == 2 else 'NICHT am Ziel'}" + (f", Treffer {s.tod}" if s.tod else ""))
    gut = [v for v in range(-4, 5) if (lambda t: t.q == 2 and t.lv == 3)(spielen(WEG, v))]
    print(f"Fledermaeuse -4 bis +4 Schritte versetzt: {len(gut)} von 9 Laeufen ohne Treffer am Ziel")
    if o.test:
        import tempfile
        import bas
        with tempfile.NamedTemporaryFile("w", suffix=".bas", encoding="utf-8") as f:
            f.write(testfassung(WEG))
            f.flush()
            daten = C.datei(bas.rein(f.name))
        if o.disk:
            import disk
            fs = disk.Fat16(o.disk)
            fs.schreiben(o.test, daten)
            fs.speichern()
            print(f"{o.test.upper()} auf {o.disk}: {len(daten)} Byte")
        else:
            open(o.test, "wb").write(daten)
            print(f"{o.test}: {len(daten)} Byte")
    return 0 if s.q == 2 else 1


if __name__ == "__main__":
    sys.exit(main())
