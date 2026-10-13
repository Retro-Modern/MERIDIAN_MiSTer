#!/usr/bin/env python3
"""DRAHT - der Netzdienst des MERIDIAN (Etappe 12)

Laeuft auf dem Linux-Teil des MiSTer und beantwortet die Anfragen, die der
MERIDIAN in sein DDR3-Fenster (Bank $FD, physisch $3E100000) schreibt.

    python3 draht.py                      auf dem MiSTer (/dev/mem); arbeitet nur,
                                          solange der MERIDIAN-Core laeuft
    python3 draht.py --datei FENSTER      gegen die Simulation (MERIDIAN_DRAHT)

Befehle aus BASIC: NET "befehl"[,kanal]
    CONNECT host[:port]   TCP-Verbindung auf Kanal 1-4 (Port ohne Angabe: 23)
    LISTEN port           auf eine Verbindung warten (fuer Mehrspieler)
    SEND text             eine Zeile senden
    CLOSE                 Verbindung schliessen
    GET url               Webseite holen (http/https), Zeilen auf den Kanal
    FETCH url [adresse]   Datei holen und per BOTE in den Speicher laden
                          (MER-Dateien an ihre Adresse, sonst nach adresse)
    DISK name [mb]        neues leeres Diskettenbild auf der SD-Karte
    FILES                 Dateien in games/MERIDIAN
    HELP                  diese Liste
NET(0) Status des letzten Befehls, NET(k) wartende Zeilen (0 keine,
-1 keine Verbindung, -2 wartet auf Verbindung); NET$(0) Meldungen,
NET$(k) naechste Zeile von Kanal k.

Laufwerk 3 (Etappe 14): der Ordner games/MERIDIAN/files als Laufwerk des
DOS. Anfragen 4-8 (Eintrag, Lesen, Schreiben, Entfernen, Frei), die Daten
stueckweise im Fenster ab $1000. Lange Dateinamen bekommen ein 8.3-Kuerzel
(SPACED~1.MOD); Antwort-Status = Fehlernummer des DOS.
Fuer ATLAS (HORIZONT): Art 5 mit Byte 17 = 1 liefert eine MER-Datei roh,
mit Kopf; Art 9 benennt um (alter Name 8.3 in Byte 0-10, neuer in 18-28);
Art 10 meldet eine Datei (8.3 in Byte 0-10) der Browser-Seite (SEND), Art 11
holt eine Datei aus dem Netz nach files (Adresse ab Byte 0, http/https).
Internetradio (App RADIO, radio_dienst.py): Art 12 spielt den Sender mit der
Adresse im Text (MP3, http/https), Art 13 haelt an; Stand ab $80, Samples in
zwei Ringen ab $8000 (links) und $C000 (rechts).
SID JAM (App JAM, sidjam_dienst.py): Art 20 mit einem Befehl als Text; Stand
ab $2000, Auftraege fuer die ORGEL im Ring ab $4000, Samples wie beim Radio
(Tabelle: sidjam/SCHNITTSTELLEN.md).
Wetter (App WEATHER, wetter_dienst.py): Art 14 mit einem Befehl als Text;
die Kurzform fuer die Menueleiste von HORIZONT schreibt der Dienst ab $22.
TAKTSTOCK Netz-Jam (takjam_dienst.py): Art 21 mit einem Befehl als Text; Stand
ab $0300, Aenderungen in zwei Ringen ab $0400 und $0800 (taktstock/netz/NETZJAM.md).
RADIO und SID JAM schreiben nur durch ein Tor ins Fenster (Klasse Tor): Es
oeffnet sich mit ihrer Anfrage (Art 12 bzw. 20) und schliesst sich bei
Stopp, Laufwerk 3, Netz-Jam, anderem Core - und wenn das Lebenszeichen der
App ($20 JAM, $21 RADIO; ihr Interrupt zaehlt es hoch) 1,5 s steht, etwa
nach einem Reset (erst, wenn es einmal gezaehlt hat: aeltere Apps kennen es
nicht). Sonst schrieben ihre Faeden weiter in $1000-$FFFF, wo
Laufwerk 3 seine Dateidaten hat.

Browser-Ablage (ATLAS, Teil E): http://mister:816/ zeigt den Ordner files
zum Hoch- und Herunterladen (ablage_seite.py, --port 0 schaltet sie ab).
Den Stand (empfaengt gerade, Ordner geaendert) liest ATLAS ab $40 im Fenster.
"""
import argparse
import collections
import mmap
import os
import select
import socket
import ssl
import struct
import sys
import threading
import time
import unicodedata
import urllib.error
import urllib.request

try:
    import ablage_seite
except ImportError:                     # die Seite ist kein Muss
    ablage_seite = None
try:
    import radio_dienst
except ImportError:                     # das Radio auch nicht
    radio_dienst = None
try:
    import wetter_dienst                # Wetter (App WEATHER, Menueleiste)
except ImportError:
    wetter_dienst = None
try:
    import sidjam_dienst                # SID JAM (sidjam/dienst/)
except ImportError:
    sidjam_dienst = None
sys.path.append(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "taktstock", "netz"))
try:
    import takjam_dienst                # TAKTSTOCK Netz-Jam (taktstock/netz/; auf dem MiSTer daneben)
except ImportError:
    takjam_dienst = None

FENSTER = 0x3E100000
POSTFACH = 0x3E000000           # BOTE: Programme und Daten in den Speicher
HIER = os.path.dirname(os.path.abspath(__file__))

# Fenster
ANR, ANTW, ART, KANAL, LEN, STATUS, ALEN, HERZ = 0, 1, 2, 3, 4, 6, 8, 0x10
TEXT, ANTWORT = 0x100, 0x200
NETZ = 0x40                         # Stand der Browser-Ablage fuer ATLAS (bis $7F)
LEBEN_JAM, LEBEN_RADIO = 0x20, 0x21 # Lebenszeichen der Apps JAM und RADIO (je Bild)
LEBEN_FRIST = 1.5                   # so lange darf es stehen
DATEN, STUECK = 0x1000, 0xF000      # Laufwerk 3: Daten im Fenster
D_GUT, D_UNGUELTIG, D_FEHLT, D_VOLL, D_SCHUTZ = 0, 1, 2, 3, 6


# Typografische Zeichen, die oft vorkommen
ERSATZ = {"\u2018": "'", "\u2019": "'", "\u201a": "'", "\u201c": '"', "\u201d": '"',
          "\u201e": '"', "\u2013": "-", "\u2014": "-", "\u2026": "...", "\u00a0": " "}


def zu_meridian(s):
    """Unicode -> Zeichensatz des MERIDIAN (ASCII, Umlaute, ß, °, §)"""
    aus = []
    for ch in s:
        if 32 <= ord(ch) < 127 or ch in "äöüÄÖÜß°§":
            aus.append(ch)
        elif ch == "\t":
            aus.append(" ")
        elif ch == "€":
            aus.append("EUR")
        elif ch in ERSATZ:
            aus.append(ERSATZ[ch])
        else:
            n = unicodedata.normalize("NFKD", ch).encode("ascii", "ignore").decode()
            if n:
                aus.append(n)
            elif unicodedata.category(ch) not in ("Cc", "Cf", "Mn", "So", "Sk", "Cs"):
                aus.append("?")
    return "".join(aus).encode("latin-1")


# Hilfe auf dem MERIDIAN (englisch, hoechstens 39 Zeichen je Zeile)
HILFE = [
    "CONNECT host:port  open TCP, chan 1-4",
    "LISTEN port        wait for a caller",
    "SEND text          send one line",
    "CLOSE              close the channel",
    "GET url            fetch a web page",
    "FETCH url [addr]   load a file to RAM",
    "DISK name [mb]     new disk image",
    "FILES              files on the SD card",
    "NET(k)  lines waiting, -1 not open",
    "NET$(k) next line, NET$(0) messages",
]


class Kanal:
    def __init__(self):
        self.sock = None
        self.server = None
        self.puffer = b""
        self.zeit = 0.0
        self.zeilen = collections.deque(maxlen=2000)

    def zustand(self):
        if self.zeilen:
            return len(self.zeilen)
        if self.sock:
            return 0
        return -2 if self.server else -1

    def zeile_rein(self, roh):
        text = zu_meridian(roh.decode("utf-8", "replace"))
        while len(text) > 255:
            self.zeilen.append(text[:255])
            text = text[255:]
        self.zeilen.append(text)

    def schliessen(self):
        for s in (self.sock, self.server):
            if s:
                try:
                    s.close()
                except OSError:
                    pass
        self.sock = self.server = None
        self.puffer = b""


class Tor:
    """Schreibzugang eines Diensts (RADIO, SID JAM) zum Fenster. Ist das Tor
    zu, kommt kein Byte mehr hinein - auch nicht aus einem Faden, der noch
    arbeitet (Antwort vom Server, Cover, Ring). Lesen geht immer. Das Schloss
    sorgt dafuer, dass nach zu() kein Schreibzugriff mehr unterwegs ist."""
    def __init__(self, m):
        self.m = m
        self.offen = False
        self.lock = threading.Lock()

    def __len__(self):
        return len(self.m)

    def __getitem__(self, i):
        return self.m[i]

    def __setitem__(self, i, wert):
        with self.lock:
            if self.offen:
                self.m[i] = wert

    def auf(self):
        with self.lock:
            self.offen = True

    def zu(self):
        with self.lock:
            self.offen = False


class Dienst:
    def __init__(self, fenster, postfach, ordner, nur_meridian):
        self.m = fenster
        self.nur_meridian = nur_meridian
        self.aktiv = None if nur_meridian else True   # None: noch nicht geprueft
        self.pruef_zeit = 0.0
        self.postfach = postfach
        self.ordner = ordner
        self.dateien = os.path.join(ordner, "files")    # Laufwerk 3
        os.makedirs(self.dateien, exist_ok=True)
        self.kanaele = [None] + [Kanal() for _ in range(4)]
        self.meldungen = collections.deque(maxlen=200)
        self.status = 0
        self.herz = 0
        self.herz_zeit = 0.0
        self.ablage = None              # Browser-Ablage (ablage_seite)
        self.radio = None               # Internetradio (radio_dienst), beim ersten Sender
        self.jam = None                 # SID JAM (sidjam_dienst), beim ersten Befehl
        self.takjam = None              # TAKTSTOCK Netz-Jam (takjam_dienst), beim ersten Befehl
        self.wetter = wetter_dienst.Wetter(fenster, zu_meridian, ordner) if wetter_dienst else None
        self.tor_radio = Tor(fenster)
        self.tor_jam = Tor(fenster)
        self.leben = {}                 # Adresse -> (Wert, seit wann, schon gezaehlt)
        self.wach_zeit = 0.0
        self.port = 0
        self.adresse_zeit = 0.0

    # -------------------------------------------------- Welcher Core?
    def kern_pruefen(self):
        """Auf dem MiSTer nur arbeiten, solange der MERIDIAN-Core laeuft:
        andere Cores benutzen dasselbe DDR3 und duerfen nichts abbekommen."""
        if not self.nur_meridian:
            return True
        jetzt = time.time()
        if jetzt - self.pruef_zeit < 0.5:
            return self.aktiv
        self.pruef_zeit = jetzt
        try:
            name = open("/tmp/CORENAME").read().strip().upper()
        except OSError:
            name = ""
        aktiv = name == "MERIDIAN"
        if aktiv and not self.aktiv:                # MERIDIAN geladen: alte Reste
            self.m[ANTW] = self.m[ANR]              # im Fenster gelten als erledigt
            self.status = 0
            self.meldungen.clear()
            if self.wetter:
                self.wetter.kurz_alt = None             # Kurzform neu schreiben
            print("MERIDIAN laeuft", flush=True)
        if not aktiv and self.aktiv is not False:
            self.radio_halten(still=True)           # nichts mehr ins Fenster
            self.jam_halten(still=True)
            if self.takjam:
                self.takjam.stop(still=True)
            for kanal in self.kanaele[1:]:
                kanal.schliessen()
                kanal.zeilen.clear()
            print("anderer Core:", name or "?", "- DRAHT ruht", flush=True)
        self.aktiv = aktiv
        return aktiv

    # -------------------------------------------------- Wechselspiel
    def antworten(self, nr, status, text=b""):
        text = text[:255]
        m = self.m
        m[ANTWORT:ANTWORT + len(text)] = text
        m[ALEN] = len(text)
        m[STATUS:STATUS + 2] = struct.pack("<h", max(-32768, min(32767, status)))
        m[ANTW] = nr                                # zuletzt

    def anfrage(self):
        m = self.m
        nr = m[ANR]
        if nr == m[ANTW]:
            return
        art, k, n = m[ART], m[KANAL], m[LEN]
        text = bytes(m[TEXT:TEXT + n])
        if k > 4:
            return self.antworten(nr, -7, b"BAD CHANNEL")
        if art == 1:
            self.meldungen.clear()
            try:
                status, meldung = self.befehl(text.decode("latin-1").strip(), k)
            except Exception as e:                  # nichts darf den Dienst anhalten
                status, meldung = -1, "ERROR: " + str(e)
            self.status = status
            self.meldungen.appendleft(zu_meridian(meldung))
            print(f"[{k}] {text.decode('latin-1')!r} -> {status} {meldung}", flush=True)
            self.antworten(nr, status, zu_meridian(meldung))
        elif art == 2:
            q = self.meldungen if k == 0 else self.kanaele[k].zeilen
            zeile = q.popleft() if q else b""
            self.antworten(nr, len(q), zeile)
        elif art == 3:
            self.antworten(nr, self.status if k == 0 else self.kanaele[k].zustand())
        elif art in (12, 13):
            if not radio_dienst:
                return self.antworten(nr, -6, b"NO RADIO")
            self.jam_halten()                       # dieselben Sample-Ringe
            if self.takjam:                         # Spektrum und Cover liegen in den Ringen des Netz-Jams
                self.takjam.stop()
            if art == 12:
                self.tor_oeffnen(self.tor_radio, LEBEN_RADIO)
            if not self.radio:
                self.radio = radio_dienst.Radio(self.tor_radio, zu_meridian)
            try:
                status, antwort = self.radio.anfrage(art, text)
            except Exception as e:
                status, antwort = -1, zu_meridian("ERROR: " + str(e))
            if art == 13:
                self.tor_radio.zu()
            self.antworten(nr, status, antwort)
        elif art == 14:                             # Wetter (App WEATHER)
            if not self.wetter:
                return self.antworten(nr, -6, b"NO WEATHER")
            try:
                status, antwort = self.wetter.anfrage(text)
            except Exception as e:
                status, antwort = 2, zu_meridian("ERROR: " + str(e))
            self.antworten(nr, status, antwort)
        elif art == 20:
            if not sidjam_dienst:
                return self.antworten(nr, -6, b"NO SID JAM")
            self.radio_halten()                     # dieselben Sample-Ringe
            stopp = text.split(None, 1)[:1] == [b"STOPP"]
            if not stopp:
                self.tor_oeffnen(self.tor_jam, LEBEN_JAM)
            if not self.jam:
                self.jam = sidjam_dienst.Jam(self.tor_jam, zu_meridian)
            try:
                status, antwort = self.jam.anfrage(art, text)
            except Exception as e:
                status, antwort = -1, zu_meridian("ERROR: " + str(e))
            if stopp:                               # die App geht: auch spaete Faeden schweigen
                self.tor_jam.zu()
            self.antworten(nr, status, antwort)
        elif art == 21:                             # TAKTSTOCK Netz-Jam (Stand ab $0300)
            if not takjam_dienst:
                return self.antworten(nr, -6, b"NO NETZJAM")
            if not self.takjam:
                self.takjam = takjam_dienst.NetzJam(m, zu_meridian, self.dateien)
            self.radio_halten()                     # Radio und SID JAM nutzen $0300-$0FFF mit
            self.jam_halten()
            try:
                status, antwort = self.takjam.befehl(text)
            except Exception as e:
                status, antwort = -1, zu_meridian("ERROR: " + str(e))
            self.antworten(nr, status, antwort)
        elif 4 <= art <= 11:
            self.radio_halten()                     # sie schrieben sonst in die Dateidaten
            self.jam_halten()
            try:
                status, antwort = self.laufwerk(art, bytes(m[TEXT:TEXT + max(17, n)]))
            except Exception as e:
                print("Laufwerk 3:", e, flush=True)
                status, antwort = D_UNGUELTIG, b""
            self.antworten(nr, status, antwort)
        else:
            self.antworten(nr, -6, b"BAD REQUEST")

    # -------------------------------------------------- Tore
    def tor_oeffnen(self, tor, leben):
        """vor einer Anfrage der App: ab jetzt zaehlt ihr Lebenszeichen"""
        if not tor.offen:
            self.leben[leben] = (self.m[leben], time.time(), False)
        tor.auf()

    def radio_halten(self, still=False):
        if self.tor_radio.offen and self.radio:
            self.radio.stop(still=still)
        self.tor_radio.zu()

    def jam_halten(self, still=False):
        if self.tor_jam.offen and self.jam:
            self.jam.stop(still=still)
        self.tor_jam.zu()

    def wachen(self):
        """Steht das Lebenszeichen einer App mit offenem Tor laenger als
        LEBEN_FRIST, ist sie weg (Reset, Absturz, ohne Stopp verlassen). Erst
        wenn es einmal gezaehlt hat - aeltere Apps kennen es nicht."""
        jetzt = time.time()
        if jetzt - self.wach_zeit < 0.25:
            return
        self.wach_zeit = jetzt
        for name, tor, leben, halten in (("RADIO", self.tor_radio, LEBEN_RADIO, self.radio_halten),
                                         ("SID JAM", self.tor_jam, LEBEN_JAM, self.jam_halten)):
            if not tor.offen:
                continue
            w = self.m[leben]
            alt = self.leben.get(leben)
            if not alt:
                self.leben[leben] = (w, jetzt, False)
            elif alt[0] != w:
                self.leben[leben] = (w, jetzt, True)
            elif alt[2] and jetzt - alt[1] > LEBEN_FRIST:
                print(name + ": kein Lebenszeichen der App - angehalten", flush=True)
                halten()

    # -------------------------------------------------- Befehle
    def befehl(self, text, k):
        teile = text.split(None, 1)
        if not teile:
            return -6, "EMPTY COMMAND"
        wort = teile[0].upper()
        rest = teile[1] if len(teile) > 1 else ""
        kanal = self.kanaele[k] if k else None
        if wort in ("CONNECT", "LISTEN", "SEND", "CLOSE") and not kanal:
            return -7, "USE A CHANNEL 1-4: NET \"" + wort + " ...\",1"
        if wort == "CONNECT":
            host, _, port = rest.strip().rpartition(":") if ":" in rest else (rest.strip(), "", "23")
            kanal.schliessen()
            kanal.zeilen.clear()
            try:
                kanal.sock = socket.create_connection((host, int(port)), timeout=10)
            except socket.gaierror:
                return -4, "HOST NOT FOUND"
            except ConnectionRefusedError:
                return -5, "CONNECTION REFUSED"
            except (socket.timeout, OSError) as e:
                return -3, "NO CONNECTION: " + str(e)
            kanal.sock.setblocking(False)
            return 0, f"CONNECTED TO {host}:{port}"
        if wort == "LISTEN":
            kanal.schliessen()
            kanal.zeilen.clear()
            s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            s.bind(("0.0.0.0", int(rest)))
            s.listen(1)
            s.setblocking(False)
            kanal.server = s
            return 0, f"WAITING ON PORT {int(rest)} ({self.eigene_adresse()})"
        if wort == "SEND":
            if not kanal.sock:
                return -2, "NOT CONNECTED"
            daten = rest.encode("utf-8") + b"\r\n"
            kanal.sock.setblocking(True)
            kanal.sock.sendall(daten)
            kanal.sock.setblocking(False)
            return 0, "SENT"
        if wort == "CLOSE":
            kanal.schliessen()
            return 0, "CLOSED"
        if wort == "GET":
            return self.holen(rest.strip(), kanal)
        if wort == "FETCH":
            return self.laden(rest.split())
        if wort == "DISK":
            return self.diskette(rest.split())
        if wort == "FILES":
            namen = sorted(os.listdir(self.ordner))
            for n in namen:
                p = os.path.join(self.ordner, n)
                if os.path.isfile(p):
                    self.meldungen.append(zu_meridian(f"{n:<16}{os.path.getsize(p):>10}"))
            return len(namen), f"{len(namen)} FILES IN {self.ordner}"
        if wort == "HELP":
            for z in HILFE:
                self.meldungen.append(zu_meridian(z))
            return 0, "COMMANDS (READ THEM WITH NET$(0)):"
        return -6, "UNKNOWN COMMAND " + wort

    # -------------------------------------------------- Laufwerk 3
    def verzeichnis(self, dazu=None):
        """[(Kurzname, Endung, Dateiname)], sortiert; 8.3-Kuerzel wie NAME~1.
        dazu: ein Name, als gaebe es ihn schon (Browser-Ablage: wie wird die
        Datei heissen, die gerade ankommt?)"""
        namen = [n for n in os.listdir(self.dateien)
                 if not n.startswith(".") and os.path.isfile(os.path.join(self.dateien, n))]
        if dazu and dazu not in namen:
            namen.append(dazu)
        namen.sort(key=str.upper)

        def zeichen(t):
            return "".join(c for c in t.upper() if (c.isascii() and c.isalnum()) or c in "_-")

        liste, belegt = [], set()
        for n in namen:
            stamm, punkt, end = n.rpartition(".")
            if not punkt:
                stamm, end = n, ""
            s, e = zeichen(stamm) or "DATEI", zeichen(end)[:3]
            if len(s) <= 8 and s == stamm.upper() and e == end.upper() and (s, e) not in belegt:
                kurz = s
            else:
                for k in range(1, 1000):
                    kurz = s[:7 - len(str(k))] + "~" + str(k)
                    if (kurz, e) not in belegt:
                        break
            belegt.add((kurz, e))
            liste.append((kurz, e, n))
        return liste

    def suchen(self, name83):
        name, end = name83[:8].decode("latin-1").strip(), name83[8:11].decode("latin-1").strip()
        for kurz, e, n in self.verzeichnis():
            if kurz == name and e == end:
                return os.path.join(self.dateien, n), name, end
        return None, name, end

    def laufwerk(self, art, text):
        if art == 4:                                    # Eintrag Nummer i
            i = struct.unpack("<H", text[:2])[0]
            liste = self.verzeichnis()
            if i >= len(liste):
                return D_FEHLT, b""
            kurz, e, n = liste[i]
            name = (kurz + ("." + e if e else "")).encode("latin-1")
            groesse = min(os.path.getsize(os.path.join(self.dateien, n)), 0xFFFFFFFF)
            return D_GUT, struct.pack("<HIB", i + 1, groesse, len(name)) + name
        if art == 8:                                    # freie Bytes
            st = os.statvfs(self.dateien)
            return D_GUT, struct.pack("<I", min(st.f_bavail * st.f_frsize, 99999999))   # DIR: 8 Stellen
        if art == 11:                                   # ATLAS: Datei aus dem Netz nach files
            url = text.split(b"\0")[0].decode("latin-1").strip()
            if self.ablage and url and self.ablage.herunterladen(url, self.oeffnen):
                return D_GUT, b""
            return D_UNGUELTIG, b""
        pfad, name, end = self.suchen(text[:11])
        if art == 10:                                   # SEND: der Browser-Seite melden
            if not pfad:
                return D_FEHLT, b""
            if self.ablage:
                self.ablage.senden(os.path.basename(pfad))
            return D_GUT, b""
        if art == 9:                                    # umbenennen (ATLAS)
            if not pfad:
                return D_FEHLT, b""
            neu_pfad, neu_name, neu_end = self.suchen(text[18:29])
            if neu_pfad:
                return D_UNGUELTIG, b""                 # den Namen gibt es schon
            os.rename(pfad, os.path.join(self.dateien, neu_name + ("." + neu_end if neu_end else "")))
            return D_GUT, b""
        versatz, laenge = struct.unpack("<IH", text[11:17])
        roh = len(text) > 17 and text[17] & 1            # ATLAS: MER-Kopf nicht abtrennen
        if art == 5:                                    # lesen
            if not pfad:
                return D_FEHLT, b""
            daten = open(pfad, "rb").read()
            mer, adr = 0, b"\0\0\0"
            if daten[:4] == b"MER\x01" and len(daten) >= 16 and not roh:
                mer, adr, daten = 1, daten[4:7], daten[16:]
            stueck = daten[versatz:versatz + min(laenge, STUECK)]
            self.m[DATEN:DATEN + len(stueck)] = stueck
            return D_GUT, struct.pack("<IHB", len(daten), len(stueck), mer) + adr
        if art == 6:                                    # schreiben (Versatz 0: neu)
            if not pfad:
                pfad = os.path.join(self.dateien, name + ("." + end if end else ""))
            try:
                with open(pfad, "r+b" if versatz else "wb") as f:
                    f.seek(versatz)
                    f.write(bytes(self.m[DATEN:DATEN + min(laenge, STUECK)]))
                    f.flush()
                    os.fsync(f.fileno())
            except OSError as e:
                print("schreiben:", e, flush=True)
                return {28: D_VOLL, 30: D_SCHUTZ, 13: D_SCHUTZ}.get(e.errno, D_UNGUELTIG), b""
            return D_GUT, b""
        if art == 7:                                    # entfernen
            if not pfad:
                return D_FEHLT, b""
            os.remove(pfad)
            return D_GUT, b""
        return D_UNGUELTIG, b""

    def oeffnen(self, url):
        if "://" not in url:
            url = "http://" + url
        anfrage = urllib.request.Request(url, headers={"User-Agent": "curl/8 (MERIDIAN 816)"})
        try:
            return urllib.request.urlopen(anfrage, timeout=15)
        except urllib.error.URLError as e:
            if isinstance(e.reason, ssl.SSLCertVerificationError):
                # MiSTer hat nicht immer aktuelle Zertifikate: dann ohne Pruefung
                return urllib.request.urlopen(anfrage, timeout=15, context=ssl._create_unverified_context())
            raise

    def holen(self, url, kanal):
        try:
            with self.oeffnen(url) as r:
                daten = r.read(256 * 1024)
                code = r.status
                zeichen = r.headers.get_content_charset() or "utf-8"
        except urllib.error.HTTPError as e:
            return e.code, f"HTTP {e.code}"
        except Exception as e:
            return -3, "NO CONNECTION: " + str(getattr(e, "reason", e))
        ziel = kanal.zeilen if kanal else self.meldungen
        if kanal:
            kanal.schliessen()
            ziel.clear()
        for z in daten.decode(zeichen, "replace").splitlines():
            text = zu_meridian(z)
            while len(text) > 255:
                ziel.append(text[:255])
                text = text[255:]
            ziel.append(text)
        return code, f"HTTP {code}, {len(ziel)} LINES"

    def laden(self, teile):
        if not teile:
            return -6, "FETCH URL [ADDRESS]"
        if self.postfach is None:
            return -1, "FETCH ONLY ON THE MISTER"
        try:
            with self.oeffnen(teile[0]) as r:
                daten = r.read(1000 * 1024)
        except Exception as e:
            return -3, "NO CONNECTION: " + str(getattr(e, "reason", e))
        if len(teile) > 1:
            adr = int(teile[1], 0)
            kopf = b"MER\x01" + adr.to_bytes(3, "little") + b"\0" + adr.to_bytes(3, "little") + b"\0" \
                + len(daten).to_bytes(4, "little")
            daten = kopf + daten
        elif daten[:4] != b"MER\x01":
            return -6, "NOT A MER FILE - GIVE AN ADDRESS"
        p = self.postfach
        folge = struct.unpack("<I", p[0:4])[0]
        p[24:24 + len(daten) - 16] = daten[16:]
        p[8:24] = daten[:16]
        p[0:4] = struct.pack("<I", (folge + 1) & 0xFFFFFFFF or 1)
        adr = int.from_bytes(daten[4:7], "little")
        return len(daten) - 16, f"LOADED {len(daten) - 16} BYTES TO ${adr:06X}"

    def diskette(self, teile):
        if not teile:
            return -6, "DISK NAME [MB]"
        name = teile[0].upper()
        if not name.endswith((".DSK", ".IMG", ".HDF")):
            name += ".DSK"
        mb = int(teile[1]) if len(teile) > 1 else 8
        if not 3 <= mb <= 2000:
            return -6, "SIZE 3-2000 MB"
        pfad = os.path.join(self.ordner, name)
        if os.path.exists(pfad):
            return -1, name + " EXISTS"
        sys.path.insert(0, HIER)
        import disk
        disk.formatieren(pfad, mb, name.split(".")[0][:11])
        return 0, f"{name} CREATED ({mb} MB) - MOUNT IT IN THE MENU"

    def eigene_adresse(self):
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.connect(("192.0.2.1", 9))
            a = s.getsockname()[0]
            s.close()
            return a
        except OSError:
            return "?"

    # -------------------------------------------------- Verbindungen
    def bedienen(self):
        jetzt = time.time()
        for kanal in self.kanaele[1:]:
            if kanal.server and not kanal.sock:
                try:
                    s, adr = kanal.server.accept()
                    s.setblocking(False)
                    kanal.sock = s
                    kanal.server.close()
                    kanal.server = None
                    print("Verbindung von", adr, flush=True)
                except (BlockingIOError, OSError):
                    pass
            if not kanal.sock:
                continue
            try:
                daten = kanal.sock.recv(4096)
                if daten == b"":
                    raise ConnectionResetError
                kanal.puffer += telnet_weg(daten, kanal.sock)
                kanal.zeit = jetzt
            except BlockingIOError:
                pass
            except OSError:
                if kanal.puffer:
                    kanal.zeile_rein(kanal.puffer)
                kanal.schliessen()
                continue
            while b"\n" in kanal.puffer:
                z, kanal.puffer = kanal.puffer.split(b"\n", 1)
                kanal.zeile_rein(z.rstrip(b"\r"))
            # Eingabeaufforderungen ohne Zeilenende ("login:") nach kurzer Ruhe
            if kanal.puffer and jetzt - kanal.zeit > 0.3:
                kanal.zeile_rein(kanal.puffer.rstrip(b"\r"))
                kanal.puffer = b""
        if jetzt - self.herz_zeit > 0.05:
            self.herz = (self.herz + 1) & 0xFF
            self.m[HERZ] = self.herz
            self.herz_zeit = jetzt
            if self.ablage:
                if jetzt - self.adresse_zeit > 10:      # die Adresse kann wechseln
                    self.adresse_zeit = jetzt
                    self.ablage.adresse = "%s:%d" % (self.eigene_adresse(), self.port)
                self.ablage.ordner_pruefen()
                b = self.ablage.block()
                self.m[NETZ:NETZ + len(b)] = b


def telnet_weg(daten, sock):
    """Telnet-Verhandlungen (IAC ...) entfernen und alles ablehnen"""
    if b"\xff" not in daten:
        return daten
    aus, i = bytearray(), 0
    while i < len(daten):
        b = daten[i]
        if b == 0xFF and i + 1 < len(daten):
            c = daten[i + 1]
            if c in (0xFB, 0xFC, 0xFD, 0xFE) and i + 2 < len(daten):
                antwort = {0xFB: 0xFE, 0xFD: 0xFC}.get(c)
                if antwort:
                    try:
                        sock.send(bytes([0xFF, antwort, daten[i + 2]]))
                    except OSError:
                        pass
                i += 3
                continue
            if c == 0xFF:
                aus.append(0xFF)
            i += 2
            continue
        aus.append(b)
        i += 1
    return bytes(aus)


def main():
    a = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    a.add_argument("--datei", help="Fenster aus einer Datei (Simulation)")
    a.add_argument("--ordner", default="/media/fat/games/MERIDIAN", help="Ordner fuer DISK und FILES")
    a.add_argument("--port", type=int, default=816, help="Browser-Ablage (0: aus)")
    o = a.parse_args()
    postfach = None
    if o.datei:
        fd = os.open(o.datei, os.O_RDWR | os.O_CREAT)
        os.ftruncate(fd, 65536)
        fenster = mmap.mmap(fd, 65536)
    else:
        fd = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
        fenster = mmap.mmap(fd, 65536, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE, offset=FENSTER)
        postfach = mmap.mmap(fd, 1024 * 1024, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE, offset=POSTFACH)
    os.makedirs(o.ordner, exist_ok=True)
    d = Dienst(fenster, postfach, o.ordner, nur_meridian=not o.datei)
    if o.port and ablage_seite:
        try:
            d.ablage = ablage_seite.Ablage(d.dateien, d.verzeichnis, zu_meridian)
            d.ablage.starten(o.port)
            d.port = o.port
            print("Browser-Ablage auf Port", o.port, flush=True)
        except OSError as e:
            d.ablage = None
            print("Browser-Ablage nicht moeglich:", e, flush=True)
    print("DRAHT bereit", "(Datei " + o.datei + ")" if o.datei else "(DDR3 $3E100000)", flush=True)
    while True:
        if not d.kern_pruefen():
            time.sleep(0.5)
            continue
        d.anfrage()
        d.bedienen()
        d.wachen()
        if d.wetter:
            d.wetter.pflegen()
        time.sleep(0.001)


if __name__ == "__main__":
    main()
