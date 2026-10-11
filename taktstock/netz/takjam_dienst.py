#!/usr/bin/env python3
"""TAKTSTOCK Netz-Jam - Teil des Netzdiensts (draht.py) auf dem MiSTer

TAKTSTOCK schickt Befehle mit der Anfrage-Art 21 (Text, wie SID JAM mit
20). Der Dienst verbindet den Song mit einem Raum auf dem Server
(taktstock/netz/takjam_server.py, im SID-JAM-Server unter /tak/) und
reicht Aenderungen in beide Richtungen weiter - ueber zwei Ringe im
DRAHT-Fenster (Tabelle in taktstock/netz/NETZJAM.md):

  $0300  Stand: Zustand, Raum-Code, Zaehler, Ringzeiger, Cursor,
         Meldung, Teilnehmer (8 x 8 Byte) und ihre Namen
  $0400  Eingang: 128 Datensaetze zu 8 Byte (Dienst -> TAKTSTOCK)
  $0800  Ausgang: 256 Datensaetze zu 8 Byte (TAKTSTOCK -> Dienst)
  Datensatz: Versatz in der Arbeitskopie (3 Byte, Vielfaches von 4),
  Maske (Bit n = Byte n gilt), 4 Bytes

Der Song selbst reist als NETZJAM.TAK ueber Laufwerk 3 (games/MERIDIAN/
files): TAKTSTOCK speichert ihn dort, der Dienst laedt ihn hoch (Raum
oeffnen, neue Samples); beim Beitreten und bei einer neuen Basis legt der
Dienst ihn dort ab, und TAKTSTOCK laedt ihn.

Befehle: OEFFNEN | BEITRETEN code | GELADEN | PAUSE | BASIS |
VERLASSEN | SPIELEN SONG|PATTERN pos | STOPP | VERSIONEN | ZURUECK n |
EINREICHEN | RAUS nr | RUHE (nichts; draht.py haelt bei jeder Anfrage der
Art 21 SID JAM und Radio an - die schrieben sonst mitten in die Dateidaten
von Laufwerk 3)
"""
import json
import os
import queue
import ssl
import struct
import threading
import time
import urllib.error
import urllib.request

HIER = os.path.dirname(os.path.abspath(__file__))
SERVER = os.environ.get("TAKJAM_SERVER", "https://retro-modern.net/api/sidjam")
SIDJAM_EINSTELLUNGEN = os.path.join(HIER, "sidjam.json")      # Kennung der Kopplung (SID JAM, F8)
DATEI = "NETZJAM.TAK"

# Fenster
N = 0x0300
N_ZUSTAND, N_ROLLE, N_CODE, N_ANZAHL, N_TN_Z, N_MELD_Z = 0x00, 0x01, 0x02, 0x06, 0x07, 0x08
N_TR_Z, N_TR_ART, N_TR_POS, N_LADEN_Z, N_FARBE = 0x09, 0x0A, 0x0B, 0x0C, 0x0D
N_EIN_W, N_EIN_R, N_AUS_W, N_AUS_R, N_HERZ, N_HERZ_D = 0x0E, 0x0F, 0x10, 0x11, 0x12, 0x13
N_CURSOR, CURSOR_B = 0x14, 7
N_MELDUNG, N_TN, N_NAMEN = 0x20, 0x40, 0x80
EIN, EIN_ANZ = 0x0400, 128
AUS, AUS_ANZ = 0x0800, 256
Z_AUS, Z_ARBEITET, Z_RAUM, Z_LADEN, Z_FEHLER, Z_WEG = 0, 1, 2, 3, 4, 5
TR = {"stopp": 0, "song": 1, "pattern": 2}
HERZ_FRIST = 600.0                          # so lange ohne Herzschlag von TAKTSTOCK: Raum verlassen


def oeffner():
    return urllib.request.build_opener(urllib.request.ProxyHandler({}),
                                       urllib.request.HTTPSHandler(context=ssl.create_default_context()))


class Fehler(Exception):
    pass


class NetzJam:
    def __init__(self, fenster, zu_meridian, ordner_dateien):
        self.m = fenster
        self.zu_meridian = zu_meridian
        self.dateien = ordner_dateien
        self.lock = threading.RLock()
        self.lauf = 0               # zaehlt jede Verbindung; alte Faeden enden von selbst
        self.code = None
        self.id = None
        self.seq = 0                # hoechster empfangener Stand
        self.basis = 0
        self.geschrieben_seq = 0    # bis hier liegt alles im Eingang (bzw. ist dort gelesen)
        self.ein = queue.deque()    # (seq, versatz, maske, bytes) fuer den Eingang
        self.pause = True           # nichts in den Eingang (Laden, Basis)
        self.m_nr = 0
        self.t_nr = -1
        self.tn = ""
        self.cursor = None
        self.cursor_zeit = 0.0
        self.auftraege = queue.Queue()
        threading.Thread(target=self.arbeiten, daemon=True).start()

    # -------------------------------------------------- Fenster
    def b(self, a, wert=None):
        if wert is None:
            return self.m[N + a]
        self.m[N + a] = wert & 0xFF

    def text(self, a, s, laenge):
        t = self.zu_meridian(s)[:laenge - 1]
        self.m[N + a:N + a + laenge] = t + bytes(laenge - len(t))

    def zaehlen(self, a):
        self.b(a, self.b(a) + 1)

    def melden(self, text):
        print("NETZ-JAM:", text, flush=True)
        self.text(N_MELDUNG, text, 32)
        self.zaehlen(N_MELD_Z)

    def zustand(self, z):
        self.b(N_ZUSTAND, z)

    # -------------------------------------------------- Netz
    def kopf(self):
        k = {"User-Agent": "MERIDIAN-816 TAKTSTOCK"}
        try:
            with open(SIDJAM_EINSTELLUNGEN) as f:
                token = json.load(f).get("token")
            if token:
                k["X-Jam-Token"] = token
        except (OSError, ValueError):
            pass
        if os.environ.get("TAKJAM_NAME"):
            k["X-Tak-Name"] = os.environ["TAKJAM_NAME"]
        if self.id:
            k["X-Tak-Id"] = self.id
        return k

    def anfrage(self, weg, daten=None, json_=None, zeit=30, roh=False):
        k = self.kopf()
        if json_ is not None:
            daten = json.dumps(json_).encode()
            k["Content-Type"] = "application/json"
        elif daten is not None:
            k["Content-Type"] = "application/octet-stream"
        r = urllib.request.Request(SERVER + (weg if weg.startswith("/") else "/tak/" + weg), data=daten, headers=k,
                                   method="POST" if daten is not None else "GET")
        try:
            with oeffner().open(r, timeout=zeit) as a:
                inhalt = a.read()
                if roh:
                    return inhalt, a.headers
                return json.loads(inhalt or b"{}")
        except urllib.error.HTTPError as e:
            try:
                text = json.loads(e.read()).get("fehler", "")
            except ValueError:
                text = ""
            raise Fehler(text or "HTTP %d" % e.code)
        except (urllib.error.URLError, OSError) as e:
            raise Fehler("NO SERVER: %s" % getattr(e, "reason", e))

    # -------------------------------------------------- Befehle (Art 21)
    def befehl(self, text):
        """sofort beantworten; was dauert, macht der Arbeitsfaden"""
        befehl = text.decode("latin-1").strip()
        wort, _, rest = befehl.partition(" ")
        wort = wort.upper()
        if wort == "VERSIONEN":                     # die Antwort ist die Liste
            try:
                return 0, self.versionen()
            except Fehler as e:
                return -1, self.zu_meridian(str(e))[:60]
        if wort == "PAUSE":
            with self.lock:
                self.pause = True
            return 0, b""
        if wort == "RUHE":                          # TAKTSTOCK startet: draht.py haelt dafuer SID JAM
            return 0, b""                           # und Radio an (sie schrieben sonst in Laufwerk 3)
        fn = getattr(self, "b_" + wort.lower(), None)
        if not fn:
            return -6, b"UNKNOWN NETZJAM COMMAND"
        self.auftraege.put((befehl, fn, rest.strip()))
        return 0, b""

    def arbeiten(self):
        while True:
            befehl, fn, rest = self.auftraege.get()
            print("NETZ-JAM:", befehl, flush=True)
            try:
                fn(rest)
            except Fehler as e:
                self.melden(str(e))
                if self.b(N_ZUSTAND) == Z_ARBEITET:
                    self.zustand(Z_FEHLER if not self.code else Z_RAUM)
            except Exception as e:                  # nichts darf den Dienst anhalten
                print("NETZ-JAM:", befehl, "->", repr(e), flush=True)
                self.melden("ERROR: " + str(e)[:24])
                if self.b(N_ZUSTAND) == Z_ARBEITET:
                    self.zustand(Z_FEHLER)

    def datei(self):
        for n in os.listdir(self.dateien):          # Gross/klein wie Laufwerk 3
            if n.upper() == DATEI:
                return os.path.join(self.dateien, n)
        return os.path.join(self.dateien, DATEI)

    def b_oeffnen(self, rest):
        self.trennen()
        self.zustand(Z_ARBEITET)
        daten = open(self.datei(), "rb").read()
        a = self.anfrage("raum", daten=daten, zeit=120)
        with self.lock:
            self.verbunden(a)
            self.pause = False
        self.zustand(Z_RAUM)
        self.melden("ROOM %s OPEN" % self.code)

    def b_beitreten(self, rest):
        code = "".join(c for c in rest.upper() if c.isalnum())[:4]
        self.trennen()
        self.zustand(Z_ARBEITET)
        a = self.anfrage("raum/%s/beitreten" % code, json_={})
        with self.lock:
            self.verbunden(a)
        self.song_holen()
        self.melden("JOINED %s" % self.code)

    def verbunden(self, a):
        self.lauf += 1
        self.code, self.id = a["code"], a["id"]
        self.seq = self.geschrieben_seq = a["seq"]
        self.basis = a["basis"]
        self.ein.clear()
        self.m_nr, self.t_nr, self.tn = 0, -1, ""
        self.text(N_CODE, self.code, 5)
        ich = a.get("ich", {})
        self.b(N_ROLLE, 1 if ich.get("gastgeber") else 0)
        self.b(N_FARBE, ich.get("farbe", 0))
        self.m[N + N_TN:N + N_NAMEN + 8 * 12] = bytes(8 * 8 + 8 * 12)
        self.b(N_EIN_W, 0)
        self.b(N_AUS_R, self.b(N_AUS_W))            # was TAKTSTOCK vorher schrieb, gilt nicht
        self.uhr_stellen()
        lauf = self.lauf
        threading.Thread(target=self.abfragen, args=(lauf,), daemon=True).start()
        threading.Thread(target=self.pumpen, args=(lauf,), daemon=True).start()

    def song_holen(self):
        """aktuellen Song nach Laufwerk 3; TAKTSTOCK laedt ihn und meldet GELADEN.
        Was die Abfrage inzwischen brachte, steckt im Song oder kommt mit der
        naechsten Abfrage (ab dem Stand des Songs) noch einmal."""
        with self.lock:
            self.pause = True
        inhalt, kopf = self.anfrage("raum/%s/song" % self.code, zeit=120, roh=True)
        with open(self.datei() + ".neu", "wb") as f:
            f.write(inhalt)
        os.replace(self.datei() + ".neu", self.datei())
        with self.lock:
            self.ein.clear()
            self.seq = self.geschrieben_seq = int(kopf["X-Tak-Seq"])
            self.basis = int(kopf["X-Tak-Basis"])
        self.zustand(Z_LADEN)
        self.zaehlen(N_LADEN_Z)

    def b_geladen(self, rest):
        with self.lock:
            self.b(N_EIN_W, 0)                      # TAKTSTOCK hat seine Zeiger auf 0
            self.b(N_AUS_R, 0)
            self.pause = False
        self.zustand(Z_RAUM)

    def b_basis(self, rest):
        """TAKTSTOCK hat NETZJAM.TAK gespeichert (neue Samples): hochladen"""
        if not self.code:
            return
        self.zustand(Z_ARBEITET)
        daten = open(self.datei(), "rb").read()
        with self.lock:
            seit = self.geschrieben_seq
        a = self.anfrage("raum/%s/basis?seit=%d" % (self.code, seit), daten=daten, zeit=120)
        with self.lock:
            self.basis = a["basis"]
            self.pause = False
        self.zustand(Z_RAUM)

    def b_verlassen(self, rest):
        war = self.code
        if war:
            try:
                self.anfrage("raum/%s/verlassen" % war, json_={}, zeit=5)
            except Fehler:
                pass
        self.trennen()
        if war:                                     # (TAKTSTOCK fragt beim Start auch so nach)
            self.melden("LEFT ROOM %s" % war)

    def trennen(self):
        with self.lock:
            self.lauf += 1
            self.code = self.id = None
            self.pause = True
            self.ein.clear()
        self.zustand(Z_AUS)
        self.b(N_ANZAHL, 0)
        self.m[N + N_TN:N + N_NAMEN] = bytes(8 * 8)
        self.zaehlen(N_TN_Z)

    def b_spielen(self, rest):
        art, _, pos = rest.partition(" ")
        self.anfrage("raum/%s/transport" % self.code,
                     json_={"art": "pattern" if art.upper() == "PATTERN" else "song", "pos": int(pos or 0)})

    def b_stopp(self, rest):
        self.anfrage("raum/%s/transport" % self.code, json_={"art": "stopp"})

    def versionen(self):
        a = self.anfrage("raum/%s/versionen" % self.code, zeit=10)
        zeilen = []
        for v in a["versionen"][-9:]:
            t = time.localtime(v["zeit"])
            zeilen.append("%d %02d:%02d %s" % (v["nr"], t.tm_hour, t.tm_min, ", ".join(v["wer"])[:22]))
        return self.zu_meridian("|".join(reversed(zeilen)))[:255]

    def b_zurueck(self, rest):
        self.anfrage("raum/%s/zurueck" % self.code, json_={"nr": int(rest or 0)})

    def b_einreichen(self, rest):
        a = self.anfrage("raum/%s/einreichen" % self.code, json_={})
        self.melden("SUBMITTED TO SID JAM (NO. %d)" % a["nr"])

    def b_raus(self, rest):
        self.anfrage("raum/%s/raus" % self.code, json_={"nr": int(rest or 0)})

    # -------------------------------------------------- Faeden im Raum
    def aktiv(self, lauf):
        return lauf == self.lauf

    def abfragen(self, lauf):
        """Long-Poll: Aenderungen der anderen, Teilnehmer, Transport, Meldungen"""
        fehler = 0
        while self.aktiv(lauf):
            try:
                with self.lock:
                    weg = "raum/%s/stand?seit=%d&basis=%d&m=%d&t=%d&tn=%s&warten=1" % (
                        self.code, self.seq, self.basis, self.m_nr, self.t_nr, self.tn)
                s = self.anfrage(weg, zeit=40)
                fehler = 0
            except Fehler as e:
                if not self.aktiv(lauf):
                    return
                fehler += 1
                if "Removed" in str(e) or "Unknown room" in str(e):
                    self.melden(str(e)[:31])
                    self.trennen()
                    return
                self.zustand(Z_WEG)
                time.sleep(min(10, fehler * 2))
                continue
            if not self.aktiv(lauf):
                return
            self.stand_neu(s)

    def stand_neu(self, s):
        if self.b(N_ZUSTAND) == Z_WEG:
            self.zustand(Z_RAUM)
        for text in s.get("meldungen", []):
            self.melden(text)
        self.m_nr = s.get("meldung_nr", self.m_nr)
        self.tn = s.get("tn", "")
        self.teilnehmer(s.get("teilnehmer", []))
        tr = s.get("transport", {})
        if tr.get("nr", 0) != self.t_nr:
            erstes = self.t_nr < 0
            self.t_nr = tr.get("nr", 0)
            if not erstes and tr.get("start_ms"):
                threading.Thread(target=self.transport, args=(tr, s["jetzt_ms"]), daemon=True).start()
        if s.get("neu_laden"):
            self.melden("NEW SONG FROM THE ROOM")
            self.song_holen()
            return
        with self.lock:
            for v, m, h in s.get("ops", []):
                self.ein.append((s["seq"], v, m, bytes.fromhex(h)))
            self.seq = s["seq"]

    def teilnehmer(self, liste):
        tn = bytearray(8 * 8)
        namen = bytearray(8 * 12)
        k = 0
        for x in liste:
            if k >= 8:
                break
            c = x.get("cursor") or [0, 0xFF, 0, 0, 0, 0, 0]
            # Cursor: Modus, Pattern, Zeile, Spur, Feld, Instrument, Position
            tn[k * 8:k * 8 + 8] = bytes([1, x["farbe"] & 7, c[0], c[1], c[2], c[3], c[4],
                                         (1 if x.get("gastgeber") else 0) | (2 if x.get("ich") else 0)])
            n = self.zu_meridian(x["name"])[:11]
            namen[k * 12:k * 12 + len(n)] = n
            k += 1
        alt = bytes(self.m[N + N_TN:N + N_TN + 64]) + bytes(self.m[N + N_NAMEN:N + N_NAMEN + 96])
        if alt != bytes(tn) + bytes(namen):
            self.m[N + N_TN:N + N_TN + 64] = bytes(tn)
            self.m[N + N_NAMEN:N + N_NAMEN + 96] = bytes(namen)
            self.b(N_ANZAHL, k)
            self.zaehlen(N_TN_Z)

    def uhr_stellen(self):
        """Versatz zur Serveruhr: die schnellste von drei Abfragen"""
        beste = None
        for _ in range(3):
            try:
                t0 = time.time()
                a = self.anfrage("/zeit", zeit=5)
                t1 = time.time()
            except Fehler:
                continue
            if beste is None or t1 - t0 < beste[0]:
                beste = (t1 - t0, a["jetzt_ms"] / 1000.0 + (t1 - t0) / 2 - t1)
        self.versatz = beste[1] if beste else None

    def transport(self, tr, jetzt_server):
        """zur Serverzeit start_ms den Zaehler stellen"""
        versatz = getattr(self, "versatz", None)
        if versatz is None:
            versatz = jetzt_server / 1000.0 - time.time()
        los = tr["start_ms"] / 1000.0 - versatz
        if los < time.time() - 2:                       # verpasst
            return
        while time.time() < los:
            time.sleep(min(0.002, max(0.0, los - time.time())))
        self.b(N_TR_ART, TR.get(tr.get("art"), 0))
        self.b(N_TR_POS, tr.get("pos", 0))
        self.zaehlen(N_TR_Z)

    def pumpen(self, lauf):
        """alle 10 ms: Ausgang lesen und schicken, Eingang fuellen, Cursor"""
        m = self.m
        letzt_senden = 0.0
        herz, herz_zeit = -1, time.time()
        while self.aktiv(lauf):
            time.sleep(0.01)
            self.zaehlen(N_HERZ_D)
            if self.b(N_HERZ) != herz:              # TAKTSTOCK lebt (zaehlt je Bild)
                herz, herz_zeit = self.b(N_HERZ), time.time()
            elif time.time() - herz_zeit > HERZ_FRIST:
                print("NETZ-JAM: TAKTSTOCK meldet sich nicht mehr - Raum verlassen", flush=True)
                self.auftraege.put(("VERLASSEN", self.b_verlassen, ""))
                return
            # Eingang fuellen
            with self.lock:
                if not self.pause:
                    w = self.b(N_EIN_W)
                    while self.ein and (w + 1) % EIN_ANZ != self.b(N_EIN_R):
                        seq, v, mk, b = self.ein.popleft()
                        a = EIN + w * 8
                        m[a:a + 8] = struct.pack("<I", v)[:3] + bytes([mk]) + b
                        w = (w + 1) % EIN_ANZ
                        self.b(N_EIN_W, w)
                        if not self.ein or self.ein[0][0] != seq:
                            self.geschrieben_seq = seq
                    if not self.ein:
                        self.geschrieben_seq = max(self.geschrieben_seq, self.seq)
            if self.b(N_ZUSTAND) not in (Z_RAUM, Z_WEG) or self.pause:
                continue
            # Ausgang lesen
            ops = []
            r = self.b(N_AUS_R)
            w = self.b(N_AUS_W)
            while r != w and len(ops) < 1024:
                a = AUS + r * 8
                d = bytes(m[a:a + 8])
                ops.append([d[0] | d[1] << 8 | d[2] << 16, d[3], d[4:8].hex()])
                r = (r + 1) % AUS_ANZ
            cursor = list(m[N + N_CURSOR:N + N_CURSOR + CURSOR_B])
            jetzt = time.time()
            cursor_neu = cursor != self.cursor and jetzt - self.cursor_zeit > 0.1
            if not ops and not cursor_neu:
                continue
            if not ops and jetzt - letzt_senden < 0.1:
                continue
            d = {"ops": ops, "basis": self.basis}
            if cursor_neu:
                d["cursor"] = cursor
            try:
                self.anfrage("raum/%s/ops" % self.code, json_=d, zeit=15)
            except Fehler as e:
                if "Old base" in str(e):            # die Basis wechselte: Abfrage laedt neu
                    self.b(N_AUS_R, w)
                    continue
                self.zustand(Z_WEG)
                time.sleep(1)
                continue
            letzt_senden = jetzt
            if cursor_neu:
                self.cursor, self.cursor_zeit = cursor, jetzt
            self.b(N_AUS_R, r)

    def stop(self, still=False):
        """anderer Core: nichts mehr ins Fenster"""
        with self.lock:
            self.lauf += 1
            self.pause = True
