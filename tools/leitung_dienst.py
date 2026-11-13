#!/usr/bin/env python3
"""LEITUNG - eine rohe TCP-Verbindung fuer Programme des MERIDIAN (Art 25)

Teil des Netzdiensts (draht.py). Fuer Online-Spiele mit eigenem
Binaerprotokoll, zuerst HANSE&HIEBE: Der Dienst reicht die Bytes
unveraendert durch. NET/CONNECT taugt dafuer nicht - der macht Zeilen
daraus, uebersetzt Umlaute und wirft Telnet-Folgen weg.

Zwei Ringe im DRAHT-Fenster, Stand ab $0300 (D = Dienst, M = MERIDIAN).
Derselbe Bereich gehoert sonst dem Netz-Jam von TAKTSTOCK und dem Spektrum
des Radios; draht.py haelt beide an, sobald die Leitung aufgeht.

  $0300  D  Zustand: 0 zu, 1 verbindet, 2 offen, 3 Gegenseite hat getrennt,
            4 Verbinden ging nicht, 5 Programm schweigt (Herzschlag stand)
  $0301  D  Folge: zaehlt bei jedem Zustandswechsel weiter
  $0302  D  Eingang: Schreibzeiger (16 Bit, 0..$07FF)
  $0304  M  Eingang: Lesezeiger
  $0306  M  Ausgang: Schreibzeiger (16 Bit, 0..$03FF)
  $0308  D  Ausgang: Lesezeiger
  $030A  M  Herzschlag: das Programm zaehlt ihn je Bild weiter
  $0320  D  Meldung: 31 Zeichen + 0
  $0400  Eingang, 2048 Byte (Dienst -> MERIDIAN)
  $0C00  Ausgang, 1024 Byte (MERIDIAN -> Dienst)

Die 16-Bit-Zeiger gehen nicht in einem Zug ueber den Bus: jedes Byte ist
ein eigener Zugriff aufs DDR3. Wer einen Zeiger der Gegenseite liest,
liest ihn deshalb zweimal, bis beide Male dasselbe herauskommt.
Geschrieben wird erst der Inhalt, dann der Zeiger.

Befehle als Text: AUF host:port | ZU | STAND | KLANG

KLANG (ab Netzdienst 2.2): die Musik von HANSE&HIEBE mit reSID. Der Server
schickt die SID-Register je PAL-Bild in K-Nachrichten, wie dem C64. Der
Dienst liest sie beim Durchreichen mit, macht daraus einen Registerstrom fuer
sidton - dasselbe reSID wie "Original" in SID JAM - und legt den Ton in zwei
Sample-Ringe. Das Programm spielt sie mit zwei Samplekanaelen (oberes Byte
bei LAUT 63, der Rest bei LAUT 1, gut 14 Bit). Marcel, 07.11.2026: "resid
nutzen, nicht orgel" - die ORGEL-Fassung klang ihm zu dumpf.

  $1000  D  Folge: zaehlt bei jedem neuen Lauf (Stueck, Sprung, Stille)
  $1001  D  1: Lauf 0 - Stille bis zur naechsten Folge
  $1002  D  Schreibzeiger der Ringe (16 Bit, 0..$3FFF)
  $1004  M  Lesezeiger
  $1006  M  Quittung: die Folge, die das Programm uebernommen hat (Ring
            geleert, Lesezeiger = Schreibzeiger). Erst danach kommt der Ton
            des neuen Laufs - sonst fiele er dem Leeren zum Opfer.
  $8000     oberes Byte je Sample, 16 KB, 22050 Hz
  $C000     Rest darunter (in 1/63)

Ein altes Programm ohne KLANG bekommt keine Musik (es meldet sich ohne das
Merkmal), ein neues an einem alten Dienst (Antwort -4) ebenso.
"""
import json
import os
import queue
import select
import socket
import struct
import subprocess
import threading
import time

L = 0x0300
L_ZUSTAND, L_FOLGE, L_EIN_W, L_EIN_R, L_AUS_W, L_AUS_R, L_HERZ, L_MELDUNG = (
    0x00, 0x01, 0x02, 0x04, 0x06, 0x08, 0x0A, 0x20)
EIN, EIN_GROESSE = 0x0400, 0x0800
AUS, AUS_GROESSE = 0x0C00, 0x0400
Z_ZU, Z_VERBINDET, Z_OFFEN, Z_GETRENNT, Z_FEHLER, Z_SCHWEIGT = 0, 1, 2, 3, 4, 5
HERZ_FRIST = 3.0            # so lange darf der Herzschlag stehen (erst, wenn er einmal gezaehlt hat)
VERBINDEN_FRIST = 10.0

KL = 0x1000
KL_FOLGE, KL_STILL, KL_W, KL_R, KL_QUITT = 0x00, 0x01, 0x02, 0x04, 0x06
KL_HI, KL_REST, KL_GROESSE = 0x8000, 0xC000, 0x4000
KL_RATE = 22050             # wie SID JAM; die App spielt mit SCHRITT 1445
PAL_CPS = 985248
BILD_ZYKLEN = 19656         # ein PAL-Bild, so zaehlt der Server die K-Bilder
STEUER = (4, 11, 18)        # Steuerregister der drei Stimmen (Bit 0 Gate)
QUITT_FRIST = 1.0           # so lange auf die Quittung warten, sonst Ton verwerfen
PROBE_ZYKLEN = 2000         # Stille hinter dem Kopf: ihr erstes Sample heisst "bereit"


def sidton_finden():
    """reSID aus SID JAM (sidjam/ton): im Paket neben diesem Dienst"""
    hier = os.path.dirname(os.path.abspath(__file__))
    for p in (os.environ.get("SIDJAM_SIDTON", ""), os.path.join(hier, "sidton"),
              os.path.join(hier, "..", "sidjam", "ton", "bau", "sidton-macos")):
        if p and os.path.isfile(p) and os.access(p, os.X_OK):
            return p
    return None


class Klang:
    """K-Nachrichten im Eingang -> sidton -> Sample-Ringe ab $8000/$C000.

    Ein sidton fuer alle Laeufe: reSID baut beim Start seine Tabellen (auf
    dem MiSTer gut 3 s). Bis dahin bekommt er nichts: was in der Zeit kam,
    kaeme sonst auf einmal heraus, liefe ueber den Ring und laege danach als
    Vorlauf von 40 statt 24 Bildern im Puffer (am MiSTer gemessen). Ob er
    bereit ist, zeigt ein kurzes Stueck Stille gleich hinter dem Kopf: kommt
    davon das erste Byte, sind die Tabellen fertig.

    Die Zeit im Strom laeuft einfach weiter;
    ein neuer Lauf bekommt ein stilles Bild davor (Gates aus, Lautstaerke 0),
    und was sidton vor dessen Mitte ausgibt, gehoert noch zum alten Lauf und
    wird verworfen. Gezaehlt wird in Samples: Sample k gehoert zum Zyklus
    k * PAL_CPS / KL_RATE."""

    def __init__(self, m):
        self.m = m
        self.lock = threading.Lock()
        self.aktiv = False          # liest K mit und schreibt ins Fenster
        self.proc = None
        self.q = None
        self.folge = 0
        self.still = True
        self.grenze = 0             # Samples davor gehoeren zu einem alten Lauf
        self.gelesen = 0
        self.bereit = False         # sidton hat seine Tabellen gebaut
        self.quittiert = -1
        self.w = 0
        self.t = 0                  # Zyklus, an dem das naechste Bild beginnt
        self.t_letzt = 0            # Zyklus des letzten Datensatzes an sidton
        self.verbindung()

    def verbindung(self):
        """neue Verbindung: Nachrichten von vorn, noch kein Lauf"""
        self.puf = bytearray()
        self.kaputt = False
        self.k_lauf = 0
        self.regs = [0] * 25

    # -------------------------------------------------- an und aus
    def an(self):
        pfad = sidton_finden()
        if not pfad:
            return False
        neu = not (self.proc and self.proc.poll() is None)
        if neu:
            self._starten(pfad)
            for _ in range(10):         # ein alter sidton ohne --sofort endet sofort -
                if self.proc.poll() is not None:     # dann lieber NO SIDTON: HANSE
                    self.aus(toeten=True)            # meldet Merkmal Bit 2 nicht
                    return False
                time.sleep(0.02)
        with self.lock:
            self.k_lauf = 0             # vor aktiv: sonst gaebe ein K dazwischen zwei Laeufe
            self.aktiv = True
            self.folge = (self.folge + 1) & 0xFF
            self.still = True
            self.grenze = self.gelesen if not neu else 0
            m = self.m
            m[KL + KL_QUITT] = (self.folge - 1) & 0xFF
            m[KL + KL_W:KL + KL_W + 2] = struct.pack("<H", self.w)
            m[KL + KL_STILL] = 1
            m[KL + KL_FOLGE] = self.folge
        return True

    def aus(self, toeten=False):
        """nichts mehr ins Fenster. toeten: auch sidton weg (anderer Core,
        Programm weg) - sonst bleibt er fuer die naechste Verbindung warm"""
        with self.lock:
            self.aktiv = False
            p, q = self.proc, self.q
            if toeten:
                self.proc = self.q = None
        if toeten and p:
            q.put(None)
            try:
                p.kill()
                p.wait(timeout=5)
            except (OSError, subprocess.TimeoutExpired):
                pass

    def _starten(self, pfad):
        p = subprocess.Popen([pfad, "--fein", "-r", str(KL_RATE), "--sofort"],
                             stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        kopf = json.dumps({"cps": PAL_CPS, "model": "6581", "sids": [0xD400]}).encode()
        q = queue.Queue()
        probe = bytearray()
        self.t_letzt = 0
        self._reg(probe, PROBE_ZYKLEN, 24, 0)   # Lautstaerke 0: Stille als Lebenszeichen
        q.put(b"SJE1" + struct.pack("<H", len(kopf)) + kopf + bytes(probe))
        with self.lock:
            self.proc, self.q = p, q
            self.gelesen = 0
            self.bereit = False
            self.t = self.t_letzt = PROBE_ZYKLEN
        threading.Thread(target=self._fuettern, args=(p, q), daemon=True).start()
        threading.Thread(target=self._lesen, args=(p,), daemon=True).start()

    # -------------------------------------------------- Eingang mitlesen
    def futtern(self, daten):
        """die Bytes, die gerade in den Eingang gingen (Faden der Leitung).
        Die Nachrichtengrenzen zaehlen immer mit, auch ohne KLANG: sonst
        fiele das Mitlesen mitten in eine Nachricht, wenn der Server vor dem
        Befehl schon etwas geschickt hat."""
        if self.kaputt:
            return
        puf = self.puf
        puf += daten
        i = 0
        while i < len(puf):
            n = puf[i]
            if n < 2 or n > 64:         # nicht im Gleichschritt: das Programm verbindet neu
                self.kaputt = True
                break
            if len(puf) - i < n:
                break
            if puf[i + 1] == 0x4B and self.aktiv:      # K
                self._k(bytes(puf[i:i + n]))
            i += n
        del puf[:i]

    def _k(self, msg):
        if len(msg) < 3:
            return
        lauf = msg[2]
        if lauf != self.k_lauf:
            self._neuer_lauf(lauf)
        if lauf == 0:
            return
        daten = bytearray()
        regs, i, n = self.regs, 3, len(msg)
        while i < n:
            h = msg[i]
            i += 1
            masken = []
            for b in range(4):
                if h >> b & 1:
                    if i >= n:
                        break
                    masken.append(msg[i])
                    i += 1
                else:
                    masken.append(0)
            if len(masken) < 4:
                break
            for r in range(25):
                if masken[r >> 3] >> (r & 7) & 1 and i < n:
                    regs[r] = msg[i]
                    i += 1
            if not self.bereit:         # nur mitfuehren; das erste Bild danach setzt alle 25
                continue
            # wie der C64 (hanse/klang.asm): erst die Gates kurz umschalten,
            # dann alle 25 Register der Reihe nach, je 8 Zyklen. Alle, nicht
            # nur die geaenderten: so kommt in jedem Bild ein Datensatz, und
            # sidton gibt den Ton Bild fuer Bild heraus, auch wenn eine Note
            # lange steht.
            t = self.t
            ums = h >> 4 & 7
            for s in range(3):
                if ums >> s & 1:
                    self._reg(daten, t + 8 * s, STEUER[s], regs[STEUER[s]] ^ 1)
            for r in range(25):
                self._reg(daten, t + 24 + 8 * r, r, regs[r])
            self.t += BILD_ZYKLEN
        self._schicken(daten)

    def _neuer_lauf(self, lauf):
        self.k_lauf = lauf
        t = self.t
        if self.bereit:
            daten = bytearray()
            for i, r in enumerate((4, 11, 18, 24)):
                self._reg(daten, t + 8 * i, r, 0)
            self.t += BILD_ZYKLEN
            self._schicken(daten)
            grenze = (t + BILD_ZYKLEN // 2) * KL_RATE // PAL_CPS
        else:
            grenze = t * KL_RATE // PAL_CPS     # alles bis jetzt ist Probe
        with self.lock:
            self.folge = (self.folge + 1) & 0xFF
            self.still = lauf == 0
            self.grenze = grenze
            if self.aktiv:
                self.m[KL + KL_STILL] = 1 if self.still else 0
                self.m[KL + KL_FOLGE] = self.folge

    def _reg(self, daten, t, r, v):
        d = t - self.t_letzt
        if d < 0:                       # _starten stellte die Uhr zurueck (anderer Faden)
            d, t = 0, self.t_letzt
        self.t_letzt = t
        while d >= 0x80:
            daten.append(d & 0x7F | 0x80)
            d >>= 7
        daten.append(d)
        daten.append(r)
        daten.append(v)

    def _schicken(self, daten):
        q, p = self.q, self.proc
        if daten and q and p and p.poll() is None:  # tot: nichts sammeln (die Schlange
            q.put(bytes(daten))                     # wuechse sonst ohne Ende)

    # -------------------------------------------------- sidton
    def _fuettern(self, p, q):
        """eigener Faden: blockiert sidton, darf die Leitung nicht stehen"""
        try:
            while True:
                d = q.get()
                if d is None:
                    break
                teile = [d]
                while len(teile) < 64:
                    try:
                        x = q.get_nowait()
                    except queue.Empty:
                        break
                    if x is None:
                        return
                    teile.append(x)
                p.stdin.write(b"".join(teile))
                p.stdin.flush()
        except (OSError, ValueError):
            pass

    def _lesen(self, p):
        fd = p.stdout.fileno()
        rest = b""
        while True:
            try:
                d = os.read(fd, 8192)
            except OSError:
                break
            if not d:
                break
            if rest:
                d, rest = rest + d, b""
            if len(d) & 1:
                d, rest = d[:-1], d[-1:]
            n = len(d) // 2
            with self.lock:
                if self.proc is not p:
                    break
                self.bereit = True
                anfang = self.gelesen
                self.gelesen += n
                grenze, folge, still = self.grenze, self.folge, self.still
            weg = min(n, max(0, grenze - anfang))
            if weg == n or still:
                continue
            if weg:
                d = d[2 * weg:]
            if self._quittung(folge):
                self._ring(p, folge, d)
        try:
            p.stdout.close()
        except OSError:
            pass

    def _quittung(self, folge):
        if self.quittiert == folge:
            return True
        ende = time.time() + QUITT_FRIST
        while time.time() < ende:
            if not self.aktiv or self.folge != folge:
                return False
            if self.m[KL + KL_QUITT] == folge:
                self.quittiert = folge
                return True
            time.sleep(0.003)
        return False

    def _ring(self, p, folge, d):
        hi, lo = d[0::2], d[1::2]
        with self.lock:
            if not self.aktiv or self.folge != folge or self.proc is not p:
                return
            m = self.m
            rp = zeiger(m, KL + KL_R) & (KL_GROESSE - 1)
            frei = (rp - self.w - 1) & (KL_GROESSE - 1)
            n = min(len(hi), frei)      # voll: das Programm spielt nicht - Rest weg
            w = self.w
            teil = min(n, KL_GROESSE - w)
            m[KL_HI + w:KL_HI + w + teil] = hi[:teil]
            m[KL_REST + w:KL_REST + w + teil] = lo[:teil]
            if teil < n:
                m[KL_HI:KL_HI + n - teil] = hi[teil:n]
                m[KL_REST:KL_REST + n - teil] = lo[teil:n]
            self.w = (w + n) & (KL_GROESSE - 1)
            m[KL + KL_W:KL + KL_W + 2] = struct.pack("<H", self.w)


def zeiger(m, a):
    """16-Bit-Zeiger der Gegenseite, zweimal gleich gelesen"""
    alt = m[a] | m[a + 1] << 8
    for _ in range(8):
        neu = m[a] | m[a + 1] << 8
        if neu == alt:
            return neu
        alt = neu
    return alt


class Leitung:
    def __init__(self, fenster, zu_meridian, herz_frist=HERZ_FRIST):
        self.m = fenster
        self.zu_meridian = zu_meridian
        self.herz_frist = herz_frist  # im Emulator laenger: der steht zwischen zwei Schritten still
        self.lock = threading.Lock()
        self.lauf = 0               # jede Verbindung hat ihre Nummer; alte Faeden enden von selbst
        self.sock = None
        self.ziel = ""
        self.offen = False          # schreibt der Dienst gerade ins Fenster?
        self.klang = Klang(fenster)

    # -------------------------------------------------- Fenster
    def _w(self, lauf, a, daten):
        """a im Fenster; nur, solange diese Verbindung gilt (stop() kann
        jederzeit dazwischenkommen)"""
        with self.lock:
            if self.lauf != lauf:
                return False
            self.m[a:a + len(daten)] = daten
            return True

    def _zeiger(self, a):
        """16-Bit-Zeiger der Gegenseite, zweimal gleich gelesen"""
        m = self.m
        alt = m[L + a] | m[L + a + 1] << 8
        for _ in range(8):
            neu = m[L + a] | m[L + a + 1] << 8
            if neu == alt:
                return neu
            alt = neu
        return alt

    def _zustand(self, lauf, z, meldung=None):
        if meldung is not None:
            t = self.zu_meridian(meldung)[:31]
            self._w(lauf, L + L_MELDUNG, t + bytes(32 - len(t)))
        if self._w(lauf, L + L_ZUSTAND, bytes([z])):
            self._w(lauf, L + L_FOLGE, bytes([(self.m[L + L_FOLGE] + 1) & 0xFF]))
        print("LEITUNG:", z, meldung or "", flush=True)

    # -------------------------------------------------- Befehle
    def befehl(self, text):
        teile = text.decode("latin-1").strip().split(None, 1)
        wort = teile[0].upper() if teile else ""
        rest = teile[1].strip() if len(teile) > 1 else ""
        if wort == "AUF":
            host, _, port = rest.rpartition(":")
            if not host or not port.isdigit():
                return -4, b"AUF HOST:PORT"
            self.stop()
            with self.lock:
                self.lauf += 1
                lauf = self.lauf
                m = self.m
                m[L:L + 0x20] = bytes([Z_VERBINDET, (m[L + L_FOLGE] + 1) & 0xFF]) + bytes(0x1E)
                self.offen = True
            self.ziel = "%s:%s" % (host, port)
            self.klang.verbindung()
            threading.Thread(target=self.arbeiten, args=(lauf, host, int(port)), daemon=True).start()
            return 0, self.zu_meridian("CONNECTING " + self.ziel)
        if wort == "ZU":
            self.stop()
            return 0, b"CLOSED"
        if wort == "STAND":
            return self.m[L + L_ZUSTAND], self.zu_meridian(self.ziel)
        if wort == "KLANG":
            if not self.klang.an():
                return -6, b"NO SIDTON"
            return 0, b"KLANG"
        return -4, b"AUF HOST:PORT | ZU | STAND | KLANG"

    def klang_halten(self):
        """ein anderer Dienst braucht $1000-$FFFF (Dateien, SID JAM)"""
        self.klang.aus()

    def stop(self, still=False):
        """Verbindung zu. still: kein Byte mehr ins Fenster (anderer Core,
        Netz-Jam, Radio - die brauchen den Bereich selbst)"""
        with self.lock:
            war = self.offen
            self.lauf += 1
            self.offen = False
            s, self.sock = self.sock, None
            if war and not still:
                self.m[L + L_ZUSTAND] = Z_ZU
                self.m[L + L_FOLGE] = (self.m[L + L_FOLGE] + 1) & 0xFF
        self.klang.aus(toeten=still)
        if s:
            try:
                s.close()
            except OSError:
                pass

    # -------------------------------------------------- der Faden
    def arbeiten(self, lauf, host, port):
        try:
            s = socket.create_connection((host, port), timeout=VERBINDEN_FRIST)
        except OSError as e:
            return self._zustand(lauf, Z_FEHLER, "NO CONNECTION: " + str(e))
        s.setblocking(False)
        s.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        s.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 1)
        with self.lock:
            if self.lauf != lauf:
                s.close()
                return
            self.sock = s
        self._zustand(lauf, Z_OFFEN, "CONNECTED TO %s:%d" % (host, port))
        ein_w = 0
        aus_r = 0
        herz = self.m[L + L_HERZ]
        herz_zeit, herz_gezaehlt = time.time(), False
        raus = b""
        while self.lauf == lauf:
            jetzt = time.time()
            # Herzschlag: steht er, ist das Programm weg (Reset, Absturz)
            h = self.m[L + L_HERZ]
            if h != herz:
                herz, herz_zeit, herz_gezaehlt = h, jetzt, True
            elif herz_gezaehlt and jetzt - herz_zeit > self.herz_frist:
                self._zustand(lauf, Z_SCHWEIGT, "PROGRAM SILENT")
                self.klang.aus(toeten=True)
                break
            # Ausgang einsammeln
            aus_w = self._zeiger(L_AUS_W) & (AUS_GROESSE - 1)
            if aus_w != aus_r:
                if aus_w > aus_r:
                    raus += bytes(self.m[AUS + aus_r:AUS + aus_w])
                else:
                    raus += bytes(self.m[AUS + aus_r:AUS + AUS_GROESSE]) + bytes(self.m[AUS:AUS + aus_w])
                aus_r = aus_w
                if not self._w(lauf, L + L_AUS_R, struct.pack("<H", aus_r)):
                    break
            # Platz im Eingang
            ein_r = self._zeiger(L_EIN_R) & (EIN_GROESSE - 1)
            frei = (ein_r - ein_w - 1) & (EIN_GROESSE - 1)
            try:
                lesen = [s] if frei else []
                schreiben = [s] if raus else []
                r, w, _ = select.select(lesen, schreiben, [], 0.002)
                if w:
                    n = s.send(raus)
                    raus = raus[n:]
                if r:
                    daten = s.recv(min(frei, 4096))
                    if not daten:
                        self._zustand(lauf, Z_GETRENNT, "CLOSED BY PEER")
                        break
                    teil = min(len(daten), EIN_GROESSE - ein_w)
                    if not self._w(lauf, EIN + ein_w, daten[:teil]):
                        break
                    if teil < len(daten):
                        self._w(lauf, EIN, daten[teil:])
                    ein_w = (ein_w + len(daten)) & (EIN_GROESSE - 1)
                    if not self._w(lauf, L + L_EIN_W, struct.pack("<H", ein_w)):
                        break
                    self.klang.futtern(daten)
                elif not lesen and not schreiben:
                    time.sleep(0.002)       # Eingang voll, nichts zu senden
            except (BlockingIOError, InterruptedError):
                pass
            except OSError as e:
                self._zustand(lauf, Z_GETRENNT, "CONNECTION LOST: " + str(e))
                break
        try:
            s.close()
        except OSError:
            pass
        with self.lock:
            if self.sock is s:
                self.sock = None
