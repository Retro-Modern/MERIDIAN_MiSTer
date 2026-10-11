#!/usr/bin/env python3
"""Internetradio fuer den MERIDIAN - Teil des Netzdiensts (draht.py)

Die App RADIO (horizont/apps/radio.asm) schickt eine Anfrage Art 12 mit der
Adresse eines Senders (MP3, http oder https) und Art 13 zum Anhalten. Der
Dienst holt den Strom selbst (mit Icy-MetaData, so kommt der laufende Titel
mit), gibt ihn an mpg123 (22 050 Hz, Stereo, 16 Bit; am Mac ffmpeg) und legt die oberen
Bytes - 8 Bit mit Vorzeichen, wie ORGEL sie spielt - in zwei Ringpuffer im
DRAHT-Fenster: links ab $8000,
rechts ab $C000, je 16 KB. Die App kopiert von dort in eine Sample-
Schleife, die ORGEL spielt, und meldet, wie weit sie gelesen hat; der Dienst
schreibt nie ueber diese Stelle hinaus (ist der Ring voll, wartet er - und
mit ihm mpg123 und der Strom).

Stand im Fenster ab $80:
   +0    Zustand: 0 aus, 1 verbindet, 2 spielt, 3 Fehler
   +2/+3 Schreibzeiger (Dienst), +4/+5 Lesezeiger (App), je 0-$3FFF
   +6/+7 kbit/s des Senders
   +8    laufender Titel (StreamTitle, mit 0, bis 56 Bytes)
   +$40  Name des Senders oder Fehlertext (mit 0, bis 64 Bytes)
   +1    zaehlt bei jeder Aenderung von Titel, Name oder Zustand
Spektrum und Cover: radio_bild.py (ab $0400, $0800 und $1000 im Fenster).
"""
import re
import shutil
import ssl
import struct
import subprocess
import threading
import sys
import time
import urllib.request

import radio_bild

STAND = 0x80
RING = 0x4000
LINKS, RECHTS = 0x8000, 0xC000
RATE = 22050

# Dekoder: mpg123 (auf dem MiSTer, 1.25); am Mac stuerzt mpg123 1.33 bei
# manchen Stroemen in der Pipe ab, dort nimmt der Dienst ffmpeg. Beide liefern
# 16 Bit mit Vorzeichen, Stereo, 22 050 Hz.
if sys.platform == "darwin" and shutil.which("ffmpeg"):
    DEKODER = ["ffmpeg", "-loglevel", "quiet", "-i", "-", "-f", "s16le", "-ac", "2", "-ar", str(RATE), "-"]
else:
    DEKODER = ["mpg123", "-q", "-s", "-r", str(RATE), "--stereo", "-"]


class Radio:
    def __init__(self, fenster, zu_meridian):
        self.m = fenster
        self.zu_meridian = zu_meridian
        self.lauf = 0                       # jeder Start bekommt eine neue Nummer
        self.proc = None
        self.wp = 0
        self.zaehler = 0
        self.m[STAND:STAND + 0x80] = bytes(0x80)
        self.spektrum = radio_bild.Spektrum(fenster)
        self.cover = radio_bild.Cover(fenster)

    # -------------------------------------------------- Stand im Fenster
    def zustand(self, z, name=None):
        self.m[STAND] = z
        if name is not None:
            self.text(0x40, name, 64)
        self.geaendert()

    def text(self, versatz, s, laenge):
        b = self.zu_meridian(s)[:laenge - 1] + b"\0"
        self.m[STAND + versatz:STAND + versatz + len(b)] = b

    def geaendert(self):
        self.zaehler = (self.zaehler + 1) & 0xFF
        self.m[STAND + 1] = self.zaehler

    def lesezeiger(self):
        return struct.unpack("<H", self.m[STAND + 4:STAND + 6])[0] & (RING - 1)

    # -------------------------------------------------- Anfragen
    def anfrage(self, art, text):
        if art == 12:
            url = text.decode("latin-1").strip()
            if not re.match(r"https?://", url):
                return -1, b"ONLY HTTP AND HTTPS"
            self.start(url)
            return 0, b""
        self.stop()                         # Art 13
        return 0, b""

    def start(self, url):
        self.stop()
        self.lauf += 1
        self.wp = 0
        self.m[STAND + 2:STAND + 6] = bytes(4)     # Schreib- und Lesezeiger auf 0
        self.spektrum.leeren()
        self.cover.leeren()
        self.m[STAND + 6:STAND + 8] = bytes(2)
        self.text(8, "", 56)
        self.zustand(1, "")
        print("Radio:", url, flush=True)
        threading.Thread(target=self.holen, args=(url, self.lauf), daemon=True).start()

    def stop(self, still=False):
        """anhalten; still: nichts mehr ins Fenster schreiben (anderer Core)"""
        self.lauf += 1
        p, self.proc = self.proc, None
        if p:
            try:
                p.kill()
            except OSError:
                pass
        if not still:
            self.cover.leeren()
            if self.m[STAND] != 0:
                self.zustand(0)

    # -------------------------------------------------- Strom und mpg123
    def holen(self, url, lauf):
        antwort = None
        try:
            kopf = {"Icy-MetaData": "1", "User-Agent": "MERIDIAN-816 RADIO"}
            # ohne Proxy-Abfrage: am Mac ruft urllib dafuer das System
            # (_scproxy), und danach stuerzt jeder neu gestartete Prozess ab
            oeffner = urllib.request.build_opener(urllib.request.ProxyHandler({}),
                                                  urllib.request.HTTPSHandler(context=ssl.create_default_context()))
            antwort = oeffner.open(urllib.request.Request(url, headers=kopf), timeout=10)
            metaint = int(antwort.headers.get("icy-metaint") or 0)
            name = antwort.headers.get("icy-name") or ""
            try:
                self.m[STAND + 6:STAND + 8] = struct.pack("<H", int(antwort.headers.get("icy-br") or 0))
            except ValueError:
                pass
            if lauf != self.lauf:
                return
            self.zustand(1, name)
            self.cover.sender(name)
            # 16 Bit; die oberen Bytes sind das 8-Bit-Sample fuer ORGEL
            proc = subprocess.Popen(DEKODER,
                                    stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                    stderr=subprocess.DEVNULL)
            self.proc = proc
            threading.Thread(target=self.schreiben, args=(proc, lauf), daemon=True).start()
            while lauf == self.lauf:
                daten = antwort.read(metaint if metaint else 4096)
                if not daten:
                    raise ConnectionError("stream ended")
                proc.stdin.write(daten)
                if metaint:
                    n = antwort.read(1)
                    if n and n[0]:
                        meta = antwort.read(n[0] * 16)
                        t = re.search(rb"StreamTitle='(.*?)';", meta, re.S)
                        if t:
                            titel = t.group(1).decode("utf-8", "replace")
                            self.text(8, titel, 56)
                            self.geaendert()
                            self.cover.titel_neu(titel)
                            print("Radio:", titel, flush=True)
        except Exception as e:              # nichts darf den Dienst anhalten
            if lauf == self.lauf:
                print("Radio:", e, flush=True)
                self.zustand(3, "ERROR: " + str(e))
        finally:
            if antwort:
                antwort.close()
            if lauf == self.lauf and self.proc:
                try:
                    self.proc.stdin.close()
                except OSError:
                    pass

    def schreiben(self, proc, lauf):
        """PCM von mpg123 in die beiden Ringe, nie ueber den Lesezeiger"""
        m = self.m
        rest = b""
        while lauf == self.lauf:
            daten = proc.stdout.read(4096)
            if not daten:
                return
            daten = rest + daten            # je Bild 4 Bytes: L tief, L hoch, R tief, R hoch
            n = len(daten) // 4
            rest = daten[4 * n:]
            links, rechts = daten[1:4 * n:4], daten[3:4 * n:4]
            i = 0
            while i < n and lauf == self.lauf:
                frei = (self.lesezeiger() - self.wp - 1) & (RING - 1)
                if frei == 0:
                    time.sleep(0.01)
                    continue
                k = min(frei, n - i, RING - self.wp)
                m[LINKS + self.wp:LINKS + self.wp + k] = links[i:i + k]
                m[RECHTS + self.wp:RECHTS + self.wp + k] = rechts[i:i + k]
                self.spektrum.dazu(self.wp, links[i:i + k], rechts[i:i + k])
                self.wp = (self.wp + k) & (RING - 1)
                m[STAND + 2:STAND + 4] = struct.pack("<H", self.wp)
                i += k
            if m[STAND] != 2 and lauf == self.lauf:
                self.zustand(2)


if __name__ == "__main__":                 # Probe ohne MERIDIAN: Strom holen, App spielen
    import sys
    fenster = bytearray(0x10000)
    r = Radio(fenster, lambda s: s.encode("latin-1", "replace"))
    r.start(sys.argv[1] if len(sys.argv) > 1 else "http://ice1.somafm.com/groovesalad-128-mp3")
    gelesen, t0 = 0, time.time()
    while time.time() - t0 < 8:             # wie die App: in Echtzeit lesen
        time.sleep(0.1)
        wp = struct.unpack("<H", fenster[STAND + 2:STAND + 4])[0]
        rp = struct.unpack("<H", fenster[STAND + 4:STAND + 6])[0]
        n = min((wp - rp) & (RING - 1), RATE // 10)
        fenster[STAND + 4:STAND + 6] = struct.pack("<H", (rp + n) & (RING - 1))
        gelesen += n
        print("Zustand", fenster[STAND], "gelesen", gelesen, "Titel",
              bytes(fenster[STAND + 8:STAND + 64]).split(b"\0")[0], flush=True)
    r.stop()
