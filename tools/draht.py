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
import time
import unicodedata
import urllib.error
import urllib.request

FENSTER = 0x3E100000
POSTFACH = 0x3E000000           # BOTE: Programme und Daten in den Speicher
HIER = os.path.dirname(os.path.abspath(__file__))

# Fenster
ANR, ANTW, ART, KANAL, LEN, STATUS, ALEN, HERZ = 0, 1, 2, 3, 4, 6, 8, 0x10
TEXT, ANTWORT = 0x100, 0x200


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


class Dienst:
    def __init__(self, fenster, postfach, ordner, nur_meridian):
        self.m = fenster
        self.nur_meridian = nur_meridian
        self.aktiv = None if nur_meridian else True   # None: noch nicht geprueft
        self.pruef_zeit = 0.0
        self.postfach = postfach
        self.ordner = ordner
        self.kanaele = [None] + [Kanal() for _ in range(4)]
        self.meldungen = collections.deque(maxlen=200)
        self.status = 0
        self.herz = 0
        self.herz_zeit = 0.0

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
            print("MERIDIAN laeuft", flush=True)
        if not aktiv and self.aktiv is not False:
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
        else:
            self.antworten(nr, -6, b"BAD REQUEST")

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
    print("DRAHT bereit", "(Datei " + o.datei + ")" if o.datei else "(DDR3 $3E100000)", flush=True)
    while True:
        if not d.kern_pruefen():
            time.sleep(0.5)
            continue
        d.anfrage()
        d.bedienen()
        time.sleep(0.001)


if __name__ == "__main__":
    main()
