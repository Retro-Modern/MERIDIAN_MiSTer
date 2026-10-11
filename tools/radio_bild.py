#!/usr/bin/env python3
"""Bilder fuer RADIO (Teil des Netzdiensts, von radio_dienst.py benutzt)

Spektrum: Aus den Samples, die ohnehin in die Ringe gehen, rechnet der Dienst
16 Baender (86 Hz bis 11 kHz, Stufen 0-15) - fuer je vier Bloecke zu 256
Samples einmal (gut 21-mal je Sekunde; eine FFT in reinem Python braucht auf
dem MiSTer rund 5 ms). Sie stehen in 64 Feldern zu 16 Bytes ab $0400 im
DRAHT-Fenster, eines je Block im Ring: Die App liest das Feld der Stelle, die
gerade klingt (Ring-Index / 256), und ist damit genau im Takt der Musik.

Cover: Kommt ein neuer Titel, sucht der Dienst ihn bei iTunes (freie Suche,
der Titel geht dafuer an Apple) und holt das Bild als PNG, 48 x 48 Punkte -
Apples Server rechnet es auf Wunsch um, PNG kann der Dienst ohne
Zusatzbibliotheken lesen. Findet er nichts, zeichnet er ein Senderbild mit dem
Namen des Senders im Zeichensatz des MERIDIAN. Beides auf 32 Farben gebracht
(Median-Cut) und abgelegt:
   $0800 +0   Zaehler (aendert sich, wenn ein neues Bild bereitliegt)
         +1   Art: 0 keins, 1 Cover, 2 Senderbild
         +$10 Palette, 32 Eintraege wie PINSEL sie nimmt (gggg bbbb, ---- rrrr)
   $1000      48 x 48 Punkte, Werte 64-95 (die Palettenplaetze der App)
"""
import cmath
import json
import math
import os
import re
import ssl
import threading
import urllib.parse
import urllib.request
import zlib

SPEKTRUM = 0x400
COVER_KOPF = 0x800
COVER_BILD = 0x1000
CN = 48
CPAL = 64
CFARBEN = 32
RING = 0x4000

HIER = os.path.dirname(os.path.abspath(__file__))
OEFFNER = urllib.request.build_opener(urllib.request.ProxyHandler({}),     # (am Mac: kein _scproxy)
                                      urllib.request.HTTPSHandler(context=ssl.create_default_context()))

# ---------------------------------------------------------------- Spektrum
N, M = 256, 128                 # reelle FFT ueber eine komplexe der halben Groesse
HANN = [0.5 - 0.5 * math.cos(2 * math.pi * i / N) for i in range(N)]
BITREV = [int(format(i, "07b")[::-1], 2) for i in range(M)]
TW = {}
_m = 2
while _m <= M:
    TW[_m] = [cmath.exp(-2j * math.pi * k / _m) for k in range(_m // 2)]
    _m *= 2
TWN = [cmath.exp(-2j * math.pi * k / N) for k in range(M)]
_kanten = [1]
for _i in range(1, 17):         # 16 Baender, logarithmisch (Bin 1-127)
    _kanten.append(max(int(round(2 ** (7 * _i / 16))), _kanten[-1] + 1))
BAENDER = list(zip(_kanten[:-1], _kanten[1:]))
NEIGUNG = 1.4                   # dB je Band (gut 3 dB je Oktave, wie an Hifi-Anzeigen)
SPANNE = 36.0                   # dB zwischen Stufe 0 und 15


def betraege(x):
    w = [x[i] * HANN[i] for i in range(N)]
    a = [complex(w[2 * BITREV[i]], w[2 * BITREV[i] + 1]) for i in range(M)]
    m = 2
    while m <= M:
        h = m // 2
        tw = TW[m]
        for k in range(0, M, m):
            for j in range(h):
                t = tw[j] * a[k + j + h]
                u = a[k + j]
                a[k + j] = u + t
                a[k + j + h] = u - t
        m *= 2
    mag = [0.0] * M
    for k in range(1, M):
        zk, zc = a[k], a[M - k].conjugate()
        mag[k] = abs((zk + zc) * 0.5 - 0.5j * TWN[k] * (zk - zc))
    return mag


class Spektrum:
    def __init__(self, m):
        self.m = m
        self.puffer = []
        self.ref = 60.0                 # lautestes Band, langsam nachgefuehrt
        self.leeren()

    def leeren(self):
        self.m[SPEKTRUM:SPEKTRUM + 64 * 16] = bytes(64 * 16)
        self.puffer = []

    def dazu(self, start, links, rechts):
        """Samples ab Ring-Index start; gerechnet wird je 1024 Samples einmal,
        ueber die letzten 256 davon (nur die werden umgewandelt)"""
        n = len(links)
        i = 0
        while i < n:
            p = (start + i) & (RING - 1)
            in_gruppe = p & 1023
            if in_gruppe < 768:
                i += min(768 - in_gruppe, n - i)
                continue
            k = min(1024 - in_gruppe, n - i)
            ml = memoryview(links[i:i + k]).cast("b")
            mr = memoryview(rechts[i:i + k]).cast("b")
            self.puffer.extend(a + b for a, b in zip(ml, mr))
            i += k
            if in_gruppe + k == 1024:
                if len(self.puffer) == 256:
                    self.rechnen(((p + k - 1) & (RING - 1)) // 256)
                self.puffer = []

    def rechnen(self, block):
        mag = betraege(self.puffer)
        db = [20 * math.log10(max(mag[lo:hi]) + 1) + NEIGUNG * b for b, (lo, hi) in enumerate(BAENDER)]
        self.ref = max(max(db), self.ref - 0.3)
        boden = self.ref - SPANNE
        stufen = bytes(max(0, min(15, int((d - boden) * 15 / SPANNE))) for d in db)
        for j in range(4):                  # die vier Bloecke dieser Gruppe
            f = SPEKTRUM + ((block - j) & 63) * 16
            self.m[f:f + 16] = stufen


# ---------------------------------------------------------------- Cover
def png_rgb(d):
    """kleiner PNG-Leser (8 Bit: Grau, RGB, Palette, mit Alpha) -> (b, h, [(r, g, b)])"""
    if d[:8] != b"\x89PNG\r\n\x1a\n":
        return None
    i, idat, pal = 8, b"", None
    while i < len(d):
        n = int.from_bytes(d[i:i + 4], "big")
        art, inhalt = d[i + 4:i + 8], d[i + 8:i + 8 + n]
        if art == b"IHDR":
            w, h, tiefe, typ, zs = (int.from_bytes(inhalt[0:4], "big"), int.from_bytes(inhalt[4:8], "big"),
                                    inhalt[8], inhalt[9], inhalt[12])
        elif art == b"PLTE":
            pal = [tuple(inhalt[k:k + 3]) for k in range(0, n, 3)]
        elif art == b"IDAT":
            idat += inhalt
        i += 12 + n
    if tiefe != 8 or zs:
        return None
    kan = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[typ]
    roh = zlib.decompress(idat)
    breite = w * kan
    vorher, p, aus = bytearray(breite), 0, []
    for _ in range(h):
        f = roh[p]
        z = bytearray(roh[p + 1:p + 1 + breite])
        p += 1 + breite
        for x in range(breite):
            a = z[x - kan] if x >= kan else 0
            b = vorher[x]
            c = vorher[x - kan] if x >= kan else 0
            if f == 1:
                z[x] = (z[x] + a) & 255
            elif f == 2:
                z[x] = (z[x] + b) & 255
            elif f == 3:
                z[x] = (z[x] + (a + b) // 2) & 255
            elif f == 4:
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                z[x] = (z[x] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        vorher = z
        for x in range(w):
            q = z[x * kan:(x + 1) * kan]
            if typ in (0, 4):
                aus.append((q[0], q[0], q[0]))
            elif typ == 3:
                aus.append(pal[q[0]])
            else:
                aus.append((q[0], q[1], q[2]))
    return w, h, aus


def auf_groesse(w, h, px, n=CN):
    """naechster Nachbar auf n x n"""
    return [px[(y * h // n) * w + (x * w // n)] for y in range(n) for x in range(n)]


def quantisieren(px, n=CFARBEN):
    """Median-Cut: -> Palette (n Farben), Index je Punkt"""
    kisten = [list(px)]
    while len(kisten) < n:
        kisten.sort(key=lambda k: max(max(c[i] for c in k) - min(c[i] for c in k) for i in range(3)) if len(k) > 1 else -1)
        k = kisten.pop()
        if len(k) < 2:
            kisten.append(k)
            break
        kanal = max(range(3), key=lambda i: max(c[i] for c in k) - min(c[i] for c in k))
        k.sort(key=lambda c: c[kanal])
        kisten += [k[:len(k) // 2], k[len(k) // 2:]]
    palette = [tuple(sum(c[i] for c in k) // len(k) for i in range(3)) for k in kisten]
    while len(palette) < n:
        palette.append((0, 0, 0))
    naechste = {}
    index = []
    for c in px:
        if c not in naechste:
            naechste[c] = min(range(len(palette)), key=lambda j: sum((c[i] - palette[j][i]) ** 2 for i in range(3)))
        index.append(naechste[c])
    return palette, index


class Cover:
    def __init__(self, m):
        self.m = m
        self.zaehler = 0
        self.lauf = 0
        self.titel = None
        self.name = ""
        self.zeichen = b""
        for pfad in (os.path.join(HIER, "zeichensatz.bin"), os.path.join(HIER, "..", "rom", "zeichensatz.bin")):
            if os.path.exists(pfad):
                self.zeichen = open(pfad, "rb").read()
                break
        self.leeren()

    def leeren(self):
        self.lauf += 1
        self.titel = None
        self.m[COVER_KOPF + 1] = 0
        self.weiter()

    def weiter(self):
        self.zaehler = (self.zaehler + 1) & 0xFF
        self.m[COVER_KOPF] = self.zaehler       # zuletzt: die App zeichnet neu

    def sender(self, name):
        """neuer Sender: gleich das Senderbild, bis ein Cover da ist"""
        self.lauf += 1
        self.titel = None
        self.name = name
        self.schreiben(self.senderbild(name), 2)

    def titel_neu(self, titel):
        if titel == self.titel:
            return
        self.titel = titel
        self.lauf += 1
        threading.Thread(target=self.suchen, args=(titel, self.lauf), daemon=True).start()

    def suchen(self, titel, lauf):
        bild = None
        try:
            begriff = re.sub(r"\(.*?\)|\[.*?\]", " ", titel)
            begriff = re.sub(r"\s+", " ", begriff).strip()
            if len(begriff) > 2:
                url = "https://itunes.apple.com/search?" + urllib.parse.urlencode(
                    {"term": begriff, "entity": "song", "media": "music", "limit": "1"})
                r = json.loads(OEFFNER.open(url, timeout=8).read())
                if r.get("resultCount"):
                    adresse = r["results"][0].get("artworkUrl100", "")
                    adresse = re.sub(r"/\d+x\d+bb\.\w+$", "/%dx%dbb.png" % (CN, CN), adresse)
                    if adresse.startswith("http"):
                        png = png_rgb(OEFFNER.open(adresse, timeout=8).read())
                        if png:
                            bild = auf_groesse(*png)
        except Exception as e:
            print("Radio: Cover", e, flush=True)
        if lauf != self.lauf:
            return
        if bild:
            print("Radio: Cover zu", titel, flush=True)
            self.schreiben(bild, 1)
        else:
            self.schreiben(self.senderbild(self.name), 2)

    def schreiben(self, px, art):
        palette, index = quantisieren(px)
        p = bytearray()
        for r, g, b in palette:
            p += bytes([(g >> 4) << 4 | b >> 4, r >> 4])
        self.m[COVER_KOPF + 0x10:COVER_KOPF + 0x10 + len(p)] = p
        self.m[COVER_BILD:COVER_BILD + CN * CN] = bytes(CPAL + i for i in index)
        self.m[COVER_KOPF + 1] = art
        self.weiter()

    def senderbild(self, name):
        """48 x 48: Verlauf wie der Himmel des Schreibtischs, das erste Wort gross"""
        name = re.split(r"[:|]| - ", name or "RADIO")[0].strip().upper() or "RADIO"
        woerter = name.split()
        bild = [None] * (CN * CN)
        for y in range(CN):
            t = y / (CN - 1)
            farbe = (int(40 + 170 * t), int(25 + 45 * t), int(100 - 40 * t))
            for x in range(CN):
                bild[y * CN + x] = farbe

        def wort(w, y0, hoch, farbe):
            # bis 6 Buchstaben 8 Punkte breit, laengere Woerter gestaucht
            # (SUNSHINE: 6 Punkte je Zeichen, Spalten weggelassen), hoechstens 9
            w = w[:CN // 5]
            breit = min(8, CN // max(1, len(w)))
            x0 = (CN - breit * len(w)) // 2
            for i, ch in enumerate(w):
                g = self.zeichen[ord(ch) * 8:ord(ch) * 8 + 8] if len(self.zeichen) >= 2048 and ord(ch) < 256 else b""
                for y, bits in enumerate(g):
                    for x in range(breit):
                        if bits & (0x80 >> (x * 8 // breit)):
                            for dy in range(hoch):
                                py = y0 + y * hoch + dy
                                if 0 <= py < CN:
                                    bild[py * CN + x0 + i * breit + x] = farbe

        if woerter and len(woerter[0]) > CN // 5:     # DEUTSCHLANDFUNK: zwei Zeilen
            h = len(woerter[0]) // 2
            wort(woerter[0][:h], 4, 2, (255, 240, 120))
            wort(woerter[0][h:], 22, 2, (255, 240, 120))
        elif woerter:
            wort(woerter[0], 6, 2, (255, 240, 120))
            rest = " ".join(woerter[1:])
            zeilen = [rest[k:k + 6] for k in range(0, len(rest), 6)][:2] if rest else []
            for n, z in enumerate(zeilen):
                wort(z.strip(), 26 + n * 9, 1, (255, 255, 255))
        for x in range(8, 40, 3):           # Lautsprecherschlitze
            for y in range(42, 45):
                bild[y * CN + x] = (20, 10, 40)
        return bild
