#!/usr/bin/env python3
"""SID JAM - Teil des Netzdiensts (draht.py) auf dem MiSTer

Die App JAM (horizont/apps/jam.asm) schickt Anfragen der Art 20 mit einem
Befehl als Text. Der Dienst spielt SIDs - allein aus der HVSC auf der
SD-Karte (oder vom Server) oder gemeinsam mit allen anderen Hoerern im
Takt des JAM-Servers - und legt alles, was die App braucht, ins
DRAHT-Fenster (Tabelle in sidjam/SCHNITTSTELLEN.md):

  $2000  Stand (Zustand, Zeiger, Startzaehler, Zaehler fuer Aenderungen)
  $2100  Texte zum laufenden Stueck, $2400/$2900 zwei Listen, $3100 Chat
  $4000  Ring mit ORGEL-Auftraegen (16 KB), die ein Timer-Interrupt der
         App zur richtigen Mikrosekunde in die ORGEL schreibt
  $8000/$C000  Ringe mit 8-Bit-Samples (22 050 Hz) fuer die Samplekanaele:
         Lautstaerke-Digis, Jingles und der Original-Klang (MP3 vom Server)

Klang ORGEL: sidkern (C, 6502 + C64-Umgebung) liefert den Registerstrom
(SJE), orgelwandler.py rechnet ihn fuer die ORGEL um. Klang ORIGINAL: der
Server rechnet das Stueck mit sidplayfp, mpg123 dekodiert es hier.

Befehle (Art 20): START breite | STOPP | MODUS ALLEIN|GEMEINSAM |
KLANG ORGEL|ORIGINAL | WEITER | SKIP | STIMME n | SUCHE text | WUNSCH n |
SPIELE n | STERN n | CHAT text | KOPPELN | AUTO ZUFALL|STERNE|KOMPONIST x|
JAHR x | HITPARADE | WUNSCHLISTE | C64U AN|AUS
"""
import json
import os
import queue
import random
import re
import shutil
import ssl
import struct
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request

import hvsc_index
import orgelwandler as ow

HIER = os.path.dirname(os.path.abspath(__file__))

# ---------------------------------------------------------------- Fenster
J = 0x2000                                  # Stand
J_ZUSTAND, J_INFO, J_RWP, J_RRP, J_PWP, J_PRP = 0x00, 0x01, 0x02, 0x04, 0x06, 0x08
J_LOS, J_MODUS, J_APP, J_APP_LOS, J_LAUF, J_APP_LAUF = 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F
J_ZEIT, J_LAENGE, J_HOERER = 0x10, 0x14, 0x18
J_CHATZ, J_LISTEZ, J_VERB, J_STERNE, J_ABST, J_MEINE = 0x1A, 0x1B, 0x1C, 0x1D, 0x1E, 0x1F
J_SKIPJA, J_SKIPN, J_SONDER, J_ANGEMELDET, J_MELDZ, J_LISTBZ = 0x20, 0x21, 0x22, 0x23, 0x24, 0x25
J_AB = 0x26                                 # Liedzeit beim Start (16 Bit, Sekunden)
J_LSEK = 0x28                               # Laenge des Stuecks (16 Bit, Sekunden)
J_HERZ = 0x2A                               # zaehlt alle 0,5 s, solange die App offen ist
J_WAHL = 0x2B                               # was eingestellt ist: Bit 0 Original, Bit 1 gemeinsam
J_NAME, J_CODE, J_MELDUNG = 0x30, 0x40, 0x50
T_TITEL, T_AUTOR, T_JAHR, T_INFO = 0x2100, 0x2140, 0x2180, 0x21C0
T_STIL, T_PROGRAMM, T_NAECHST = 0x2200, 0x22A0, 0x22E0
L_A, L_B, L_EINTRAG, L_A_MAX, L_B_MAX = 0x2400, 0x2900, 48, 24, 40
C_CHAT, C_ZEILE, C_MAX = 0x3100, 64, 24
R_RING, R_GROESSE = 0x4000, 0x4000
P_LINKS, P_RECHTS, P_GROESSE = 0x8000, 0xC000, 0x4000
VOR = 0x4000                                # so viel fuellt die App vor dem Start vor

# Zustand (Dienst) und Zustand der App
Z_AUS, Z_LAEDT, Z_BEREIT, Z_SPIELT, Z_FEHLER, Z_WARTET = 0, 1, 2, 3, 4, 5
A_AUS, A_FUELLT, A_BEREIT, A_SPIELT, A_ENDE = 0, 1, 2, 3, 4
# J_MODUS: 1 nur Samples (MP3 vom Server), 2 gemeinsam, 4 ORGEL nur fuer die
# Anzeige (stumm; der Ton kommt aus reSID), 8 Samples fein (zwei Kanaele:
# oberes Byte bei LAUT 63, Rest bei LAUT 1 - gut 14 Bit statt 8)
M_ORIGINAL, M_GEMEINSAM, M_ANZEIGE, M_FEIN = 1, 2, 4, 8
V_ALLEIN, V_VERBUNDEN, V_VERBINDET, V_KEIN = 0, 1, 2, 3
SONDER = {"": 0, "quiz": 1, "duell": 2, "thema": 3, "sendeschluss": 4, "sendebeginn": 5}

VORLAUF = 1.2                               # Sekunden im Ring, bevor es losgeht
LADEZEIT = 1.5                              # so lange braucht ein Start hoechstens

# ---------------------------------------------------------------- Orte
MERIDIAN = "/media/fat/games/MERIDIAN"
EINSTELLUNGEN = os.path.join(HIER, "sidjam.json")
CACHE = "/tmp/sidjam"
SERVER = "https://retro-modern.net/api/sidjam"


def sidkern_finden():
    for p in (os.environ.get("SIDJAM_SIDKERN", ""), os.path.join(HIER, "sidkern"),
              os.path.join(HIER, "..", "kern", "bau", "sidkern-macos"),
              os.path.join(HIER, "..", "kern", "bau", "sidkern")):
        if p and os.path.isfile(p) and os.access(p, os.X_OK):
            return p
    return None


def sidton_finden():
    """reSID fuer den Klang "Original" (sidjam/ton)"""
    for p in (os.environ.get("SIDJAM_SIDTON", ""), os.path.join(HIER, "sidton"),
              os.path.join(HIER, "..", "ton", "bau", "sidton-macos")):
        if p and os.path.isfile(p) and os.access(p, os.X_OK):
            return p
    return None


def hvsc_finden():
    """(Quelle, Verzeichnis-Datei): Quelle ist der Ordner C64Music oder
    hvsc.zip - auf der SD-Karte des MiSTer eine einzige Datei, denn exFAT
    blaeht 61 000 kleine Dateien auf Gigabytes auf"""
    for wurzel in (os.environ.get("SIDJAM_HVSC", ""), os.path.join(MERIDIAN, "HVSC"),
                   os.path.join(HIER, "..", "hvsc")):
        if wurzel and os.path.isfile(os.path.join(wurzel, "hvsc_index.tsv.gz")):
            for q in ("hvsc.zip", "C64Music"):
                if os.path.exists(os.path.join(wurzel, q)):
                    return os.path.join(wurzel, q), os.path.join(wurzel, "hvsc_index.tsv.gz")
    return None, None


class Archiv:
    """SID-Dateien aus hvsc.zip (Eintraege "C64Music/...") oder dem Ordner"""

    def __init__(self, quelle):
        self.quelle = quelle
        self.zip = None
        if quelle.endswith(".zip"):
            import zipfile
            self.zip = zipfile.ZipFile(quelle)

    def datei(self, pfad):
        if not self.zip:
            return os.path.join(self.quelle, pfad)
        os.makedirs(CACHE, exist_ok=True)
        ziel = os.path.join(CACHE, re.sub(r"[^A-Za-z0-9_.-]", "_", pfad))
        if not os.path.isfile(ziel):
            with open(ziel + ".neu", "wb") as f:
                f.write(self.zip.read("C64Music/" + pfad))
            os.replace(ziel + ".neu", ziel)
        return ziel


# Dekoder fuer den Original-Klang wie im Radio
if sys.platform == "darwin" and shutil.which("ffmpeg"):
    DEKODER = ["ffmpeg", "-loglevel", "quiet", "-i", "-", "-f", "s16le", "-ac", "2", "-ar", "22050", "-"]
else:
    DEKODER = ["mpg123", "-q", "-s", "-r", "22050", "--stereo", "-"]


def oeffner():
    return urllib.request.build_opener(urllib.request.ProxyHandler({}),
                                       urllib.request.HTTPSHandler(context=ssl.create_default_context()))


# ---------------------------------------------------------------- SJE lesen
class SJELeser:
    """liest den Registerstrom von sidkern stueckweise aus einer Leitung"""

    def __init__(self, f):
        self.f = f
        self.puffer = b""
        self.pos = 0
        self.zyklus = 0
        if self.holen(6) < 6 or self.puffer[:4] != b"SJE1":
            raise ValueError("kein SJE-Strom")
        n = struct.unpack("<H", self.puffer[4:6])[0]
        self.pos = 6
        if self.holen(6 + n) < 6 + n:
            raise ValueError("SJE-Kopf unvollstaendig")
        self.kopf = json.loads(self.puffer[6:6 + n].decode("utf-8"))
        self.pos = 6 + n
        self.zyklus = int(self.kopf.get("start_cycles", 0))

    def holen(self, bis):
        while len(self.puffer) < bis:
            d = self.f.read1(65536) if hasattr(self.f, "read1") else self.f.read(65536)
            if not d:
                break
            self.puffer += d
        return len(self.puffer)

    def ereignisse(self):
        """liefert (zyklus, chip, reg, wert) bis zum Ende"""
        while True:
            if self.pos > 65536:                # Verbrauchtes wegwerfen
                self.puffer = self.puffer[self.pos:]
                self.pos = 0
            if self.holen(self.pos + 16) <= self.pos:
                return
            d, s = 0, 0
            while True:
                if self.holen(self.pos + 1) <= self.pos:
                    return
                b = self.puffer[self.pos]
                self.pos += 1
                d |= (b & 0x7F) << s
                s += 7
                if not b & 0x80:
                    break
            if self.holen(self.pos + 1) <= self.pos:
                return
            r = self.puffer[self.pos]
            self.pos += 1
            self.zyklus += d
            if r == 0x7F:
                return
            if self.holen(self.pos + 1) <= self.pos:
                return
            w = self.puffer[self.pos]
            self.pos += 1
            yield self.zyklus, r >> 5, r & 0x1F, w


def lesen_genau(f, n):
    """n Bytes aus der Leitung (am Ende mit Stille aufgefuellt)"""
    d = b""
    while len(d) < n:
        x = f.read(n - len(d))
        if not x:
            break
        d += x
    return d + bytes(n - len(d))


def fein(stereo16):
    """16 Bit Stereo -> zwei 8-Bit-Kanaele: oberes Byte und Rest in 1/63"""
    import array
    a = array.array("h", stereo16)
    if sys.byteorder == "big":
        a.byteswap()
    hi = bytearray(len(a) // 2)
    lo = bytearray(len(a) // 2)
    for i in range(len(a) // 2):
        v = (a[2 * i] + a[2 * i + 1]) / 512.0
        h = int(round(v))
        h = 127 if h > 127 else (-127 if h < -127 else h)
        l = int(round((v - h) * 63))
        hi[i] = h & 0xFF
        lo[i] = (127 if l > 127 else (-127 if l < -127 else l)) & 0xFF
    return bytes(hi), bytes(lo)


# ---------------------------------------------------------------- Fenster-Helfer
class Fenster:
    def __init__(self, m, zu_meridian):
        self.m = m
        self.zu_meridian = zu_meridian

    def b(self, a, wert=None):
        if wert is None:
            return self.m[J + a]
        self.m[J + a] = wert & 0xFF

    def w16(self, a, wert=None):
        if wert is None:
            return struct.unpack("<H", self.m[J + a:J + a + 2])[0]
        self.m[J + a:J + a + 2] = struct.pack("<H", wert & 0xFFFF)

    def w32(self, a, wert=None):
        if wert is None:
            return struct.unpack("<I", self.m[J + a:J + a + 4])[0]
        self.m[J + a:J + a + 4] = struct.pack("<I", wert & 0xFFFFFFFF)

    def text(self, adr, s, laenge):
        b = self.zu_meridian(s or "")[:laenge - 1] + b"\0"
        self.m[adr:adr + len(b)] = b

    def zaehlen(self, a):
        self.m[J + a] = (self.m[J + a] + 1) & 0xFF


# ---------------------------------------------------------------- Abspielen
class Spieler:
    """eine Leitung von der Quelle bis in die Ringe; je Start ein Lauf"""

    def __init__(self, jam):
        self.jam = jam
        self.f = jam.f
        self.m = jam.f.m
        self.lauf = 0
        self.procs = {}                     # Lauf -> seine Prozesse (sidkern, sidton, mpg123)
        self.auftrag = None

    def start(self, auftrag):
        self.stop()
        self.lauf += 1
        self.auftrag = auftrag
        threading.Thread(target=self.laufen, args=(auftrag, self.lauf), daemon=True).start()

    def stop(self):
        """alle Laeufe anhalten; abgeholt werden ihre Prozesse am Ende des
        jeweiligen Laufs (sonst blieben sie als Zombies stehen)"""
        self.lauf += 1
        self.auftrag = None
        for liste in list(self.procs.values()):
            for p in liste:
                try:
                    p.kill()
                except OSError:
                    pass

    def prozess(self, lauf, p):
        self.procs.setdefault(lauf, []).append(p)
        return p

    def aktiv(self, lauf):
        return lauf == self.lauf

    # ---------------------------------------------- Ringe
    def r_frei(self, wp):
        return (self.f.w16(J_RRP) - wp - 1) & (R_GROESSE - 1)

    def p_frei(self, wp):
        return (self.f.w16(J_PRP) - wp - 1) & (P_GROESSE - 1)

    def warten(self, lauf, bedingung, zeit=None):
        ende = time.time() + zeit if zeit else None
        while self.aktiv(lauf) and not bedingung():
            if ende and time.time() > ende:
                return False
            time.sleep(0.005)
        return self.aktiv(lauf)

    def schreiben(self, lauf, regdaten, pcm_l, pcm_r):
        """Auftraege und Samples in die Ringe, wartet, bis Platz ist"""
        m = self.m
        if regdaten:                            # ganze Datensaetze auf einmal freigeben
            if not self.warten(lauf, lambda: self.r_frei(self.rwp) >= len(regdaten)):
                return False
            i = 0
            while i < len(regdaten):
                n = min(len(regdaten) - i, R_GROESSE - self.rwp)
                m[R_RING + self.rwp:R_RING + self.rwp + n] = regdaten[i:i + n]
                self.rwp = (self.rwp + n) & (R_GROESSE - 1)
                i += n
            self.f.w16(J_RWP, self.rwp)
        i = 0
        while i < len(pcm_l):
            if not self.warten(lauf, lambda: self.p_frei(self.pwp) > 0):
                return False
            n = min(self.p_frei(self.pwp), len(pcm_l) - i, P_GROESSE - self.pwp)
            m[P_LINKS + self.pwp:P_LINKS + self.pwp + n] = pcm_l[i:i + n]
            m[P_RECHTS + self.pwp:P_RECHTS + self.pwp + n] = pcm_r[i:i + n]
            self.pwp = (self.pwp + n) & (P_GROESSE - 1)
            self.f.w16(J_PWP, self.pwp)
            i += n
        return True

    # ---------------------------------------------- Ablauf eines Laufs
    def laufen(self, a, lauf):
        f = self.f
        try:
            f.b(J_ZUSTAND, Z_LAEDT)
            modus = M_GEMEINSAM if a.get("gemeinsam") else 0
            if a.get("resid"):
                modus |= M_ANZEIGE | M_FEIN
            elif a.get("original"):
                modus |= M_ORIGINAL | M_FEIN
            f.b(J_MODUS, modus)
            f.w16(J_RWP, 0)
            f.w16(J_PWP, 0)
            self.rwp = self.pwp = 0
            self.geschrieben = 0.0
            self.fertig = False
            f.w32(J_LAENGE, int((a["laenge"]) * 1000))
            f.w16(J_AB, int(a.get("ab", 0)))
            f.w16(J_LSEK, int(a["laenge"] + 0.5))
            self.jam.info_zeigen(a)
            # neuer Lauf: die App setzt ihre Lesezeiger auf 0 und meldet sich
            f.zaehlen(J_LAUF)
            nr = f.b(J_LAUF)
            if not self.warten(lauf, lambda: f.b(J_APP_LAUF) == nr and f.b(J_APP) == A_FUELLT, 3.0):
                if self.aktiv(lauf):
                    print("JAM: die App meldet sich nicht", flush=True)
                    f.b(J_ZUSTAND, Z_AUS)
                return
            threading.Thread(target=self.waechter, args=(lauf, a), daemon=True).start()
            if a.get("original"):
                self.original(a, lauf)
            else:
                self.orgel(a, lauf)
        except Exception as e:                  # nichts darf den Dienst anhalten
            if self.aktiv(lauf):
                print("JAM:", e, flush=True)
                f.b(J_ZUSTAND, Z_FEHLER)
                self.jam.melden("ERROR: " + str(e))
        finally:
            for p in self.procs.pop(lauf, []):
                try:
                    p.kill()
                    p.wait(timeout=5)
                except (OSError, subprocess.TimeoutExpired):
                    pass

    def vorlauf_pruefen(self, lauf, a, liedzeit):
        """merkt sich, wie viel Lied schon in den Ringen liegt"""
        self.geschrieben = max(self.geschrieben, liedzeit)
        return True

    def waechter(self, lauf, a):
        """eigener Faden: sobald genug in den Ringen liegt (oder sie voll
        sind) und die App vorgefuellt hat, zur Startzeit losschicken - auch
        wenn der Schreiber gerade auf Platz wartet"""
        f = self.f
        while self.aktiv(lauf):
            voll = self.p_frei(self.pwp) < 512
            if f.b(J_APP) == A_BEREIT and (self.geschrieben >= VORLAUF or voll or self.fertig):
                f.b(J_ZUSTAND, Z_BEREIT)
                self.losschicken(lauf, a.get("los"), a)
                return
            time.sleep(0.005)

    def losschicken(self, lauf, los, a):
        f = self.f
        if los:
            while self.aktiv(lauf) and time.time() < los:
                time.sleep(min(0.002, max(0.0, los - time.time())))
        if not self.aktiv(lauf):
            return
        f.zaehlen(J_LOS)
        f.b(J_ZUSTAND, Z_SPIELT)
        self.jam.gestartet(a)

    def orgel(self, a, lauf):
        sk = sidkern_finden()
        if not sk:
            raise RuntimeError("sidkern fehlt")
        ab, laenge = a.get("ab", 0.0), a["laenge"]
        cmd = [sk, a["datei"], "-s", str(a["lied"]), "-t", "%.3f" % (laenge + 0.5)]
        if ab > 0:
            cmd += ["--ab", "%.3f" % ab]
        if a.get("modell"):
            cmd += ["--model", a["modell"]]
        p = self.prozess(lauf, subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL))
        ton = None
        if a.get("resid"):                      # derselbe Strom ein zweites Mal, durch reSID
            p1 = self.prozess(lauf, subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL))
            ton = subprocess.Popen([sidton_finden(), "--fein", "-r", str(ow.PCM_RATE),
                                    "--stumm", str(self.jam.stumm)]
                                   + (["--modell", a["modell"]] if a.get("modell") else []),
                                   stdin=p1.stdout, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
            p1.stdout.close()
            self.prozess(lauf, ton)
        leser = SJELeser(p.stdout)
        k = leser.kopf
        if k.get("basic"):
            raise RuntimeError("needs BASIC")
        cps = float(k.get("cps", 985248))
        start_zyklus = int(k.get("start_cycles", 0))
        w = ow.Orgelwandler(cps, k.get("model", "6581"))
        digi = ow.Digi()
        daten, t_letzt = ow.datensaetze([(0, r, v) for r, v in w.anfang()], 0)
        self.schreiben(lauf, daten, b"", b"")
        ende_us = (laenge - ab) * 1e6
        fade_t, fade_stufe = ende_us - 3e6, 14
        block_anfang, block_ende = 0.0, float(ow.BLOCK_US)
        roh, d418 = [], []

        def leeren():
            nonlocal t_letzt, fade_t, fade_stufe, roh, d418
            ist_digi = len(d418) >= ow.DIGI_JE_BLOCK
            aus = []
            for t, reg, wert in roh:
                for r, v in w.schreiben(reg, wert, ist_digi):
                    aus.append((t, r, v))
            while fade_t < block_ende and fade_stufe >= 0:
                if fade_t >= block_anfang:
                    aus.append((fade_t, ow.S_AUSBLENDEN, fade_stufe))
                fade_t += 200000
                fade_stufe -= 1
            if block_anfang <= ende_us < block_ende:
                aus.append((ende_us, ow.S_ENDE, 0))
            aus.sort(key=lambda x: x[0])
            daten, t_letzt = ow.datensaetze(aus, t_letzt)
            if ton:                             # reSID: oberes Byte und Rest
                n = int(block_ende * ow.PCM_RATE / 1e6) - int(block_anfang * ow.PCM_RATE / 1e6)
                roh2 = lesen_genau(ton.stdout, 2 * n)
                roh, d418 = [], []
                return self.schreiben(lauf, daten, roh2[0::2], roh2[1::2])
            pcm = digi.block(block_anfang, block_ende, [(t, v & 15) for t, v in d418], ist_digi)
            roh, d418 = [], []
            return self.schreiben(lauf, daten, pcm, pcm)

        for zyklus, chip, reg, wert in leser.ereignisse():
            if not self.aktiv(lauf):
                return
            t = (zyklus - start_zyklus) * 1e6 / cps
            while t >= block_ende:
                if not leeren():
                    return
                block_anfang, block_ende = block_ende, block_ende + ow.BLOCK_US
                self.vorlauf_pruefen(lauf, a, block_anfang / 1e6)
                if block_anfang >= ende_us:
                    break
            if block_anfang >= ende_us:
                break
            if chip != 0 or reg > 24:
                continue
            roh.append((t, reg, wert))
            if reg == 24:
                d418.append((t, wert))
        # Rest bis zum Ende (Stille, falls das Stueck frueher aufhoert)
        while self.aktiv(lauf) and block_anfang < ende_us:
            if not leeren():
                return
            block_anfang, block_ende = block_ende, block_ende + ow.BLOCK_US
            self.vorlauf_pruefen(lauf, a, block_anfang / 1e6)
        self.fertig = True                      # kurze Stuecke
        self.nachlauf(lauf, a)

    def original(self, a, lauf):
        """MP3 vom Server ab der Liedzeit, dekodiert wie im Radio"""
        url = a["original"]
        kopf = {"User-Agent": "MERIDIAN-816 JAM"}
        if self.jam.e.get("token"):
            kopf["X-Jam-Token"] = self.jam.e["token"]
        antwort = oeffner().open(urllib.request.Request(url, headers=kopf), timeout=15)
        p = self.prozess(lauf, subprocess.Popen(DEKODER, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                                stderr=subprocess.DEVNULL))

        def zufuehren():
            try:
                while self.aktiv(lauf):
                    d = antwort.read(8192)
                    if not d:
                        break
                    p.stdin.write(d)
            except OSError:
                pass
            finally:
                try:
                    p.stdin.close()
                except OSError:
                    pass
        threading.Thread(target=zufuehren, daemon=True).start()
        ende = (a["laenge"] - a.get("ab", 0.0))
        geschrieben = 0
        rest = b""
        while self.aktiv(lauf) and geschrieben < ende * ow.PCM_RATE:
            d = p.stdout.read(4096)
            if not d:
                break
            d = rest + d
            n = len(d) // 4
            rest = d[4 * n:]
            hi, lo = fein(d[:4 * n])
            if not self.schreiben(lauf, b"", hi, lo):
                return
            geschrieben += n
            self.vorlauf_pruefen(lauf, a, geschrieben / ow.PCM_RATE)
        self.fertig = True
        self.nachlauf(lauf, a)

    def nachlauf(self, lauf, a):
        """warten, bis die App das Ende gespielt hat, dann weiter"""
        f = self.f
        dauer = a["laenge"] - a.get("ab", 0.0)
        self.warten(lauf, lambda: f.b(J_APP) == A_ENDE or
                    (f.b(J_APP) == A_SPIELT and f.w32(J_ZEIT) >= dauer * 1e6 + 300000) or
                    f.b(J_APP) == A_AUS, dauer + 30)
        if self.aktiv(lauf):
            self.auftrag = None
            f.b(J_ZUSTAND, Z_WARTET)
            self.jam.zu_ende(a)


# ---------------------------------------------------------------- Allein
class Allein:
    def __init__(self, jam):
        self.jam = jam
        self.verzeichnis = None
        self.archiv = None
        self.wunsch = []                    # [(pfad, lied)]
        self.treffer = []                   # Eintraege der Liste B
        self.verlauf = []

    def laden(self):
        if self.verzeichnis is None:
            quelle, index = hvsc_finden()
            if index:
                self.verzeichnis = hvsc_index.KleinesVerzeichnis(index)
                self.archiv = Archiv(quelle)
        return self.verzeichnis

    def eintrag(self, pfad):
        v = self.laden()
        return v.eintrag(pfad) if v else None

    def suchen(self, text):
        v = self.laden()
        if v:
            return [{"pfad": e["pfad"], "lied": e["start"], "titel": e["titel"], "autor": e["autor"],
                     "jahr": e["jahr"]} for e in v.suchen(text, L_B_MAX) if v.spielbar(e, False)]
        return self.jam.netz.suchen(text)

    def naechstes(self):
        if self.wunsch:
            return self.wunsch.pop(0)
        v = self.laden()
        art, wert = self.jam.e.get("auto", ["ZUFALL", ""])
        if not v:
            return self.jam.netz.zufall(art, wert)
        sterne = self.jam.e.get("sterne", {})
        nummern = None
        if art in ("KOMPONIST", "JAHR") and wert:
            nummern = v.nummern(wert)
        elif art == "STERNE" and sterne:
            gewichte = {5: 8, 4: 4, 3: 2, 2: 0.3, 1: 0.1}
            paare = [(k, gewichte.get(n, 1)) for k, n in sterne.items()]
            if random.random() < 0.8:
                k = random.choices([p[0] for p in paare], [p[1] for p in paare])[0]
                pfad, lied = k.rsplit("#", 1)
                return pfad, int(lied)
        for _ in range(200):
            nr = random.choice(nummern) if nummern else random.randrange(len(v))
            e = v.zerlegen(nr)
            if v.spielbar(e) and v.laenge(e, e["start"]) >= 45 and e["pfad"] not in self.verlauf[-50:]:
                return e["pfad"], e["start"]
        e = v.zerlegen(random.choice(nummern) if nummern else random.randrange(len(v)))
        return e["pfad"], e["start"]


# ---------------------------------------------------------------- Gemeinsam (Server)
class Netz:
    def __init__(self, jam):
        self.jam = jam
        self.version = 0
        self.versatz = None                 # Serverzeit - lokale Zeit (s)
        self.rtt = 99.0
        self.stand = None
        self.lauf = 0
        self.fehler = 0

    def url(self, weg, **werte):
        u = self.jam.e.get("server", SERVER) + weg
        if werte:
            u += "?" + urllib.parse.urlencode(werte)
        return u

    def anfrage(self, weg, daten=None, zeit=10, **werte):
        kopf = {"User-Agent": "MERIDIAN-816 JAM"}
        if self.jam.e.get("token"):
            kopf["X-Jam-Token"] = self.jam.e["token"]
        roh = None
        if daten is not None:
            roh = json.dumps(daten).encode("utf-8")
            kopf["Content-Type"] = "application/json"
        r = oeffner().open(urllib.request.Request(self.url(weg, **werte), data=roh, headers=kopf), timeout=zeit)
        return json.loads(r.read().decode("utf-8") or "{}")

    def jetzt(self):
        return time.time() + (self.versatz or 0.0)

    def starten(self):
        self.lauf += 1
        threading.Thread(target=self.schleife, args=(self.lauf,), daemon=True).start()

    def stoppen(self):
        self.lauf += 1

    def schleife(self, lauf):
        j = self.jam
        j.f.b(J_VERB, V_VERBINDET)
        uhr_zeit = 0.0
        while lauf == self.lauf:
            try:
                if time.time() - uhr_zeit > 60:  # Uhr abgleichen: kurze Anfragen
                    self.uhr_stellen()
                    uhr_zeit = time.time()
                s = self.anfrage("/stand", zeit=40, v=self.version, warten=1 if self.stand else 0)
                if lauf != self.lauf:
                    return
                self.fehler = 0
                j.f.b(J_VERB, V_VERBUNDEN)
                self.version = s.get("version", 0)
                self.stand = s
                j.stand_neu(s)
            except Exception as e:
                if lauf != self.lauf:
                    return
                self.fehler += 1
                print("JAM-Server:", e, flush=True)
                j.f.b(J_VERB, V_KEIN)
                j.melden("NO CONNECTION TO JAM SERVER")
                time.sleep(min(30, 2 * self.fehler))

    def uhr_stellen(self):
        """Versatz zur Serveruhr aus der schnellsten von fuenf Anfragen"""
        beste = None
        for _ in range(5):
            t0 = time.time()
            s = self.anfrage("/zeit", zeit=5)
            t1 = time.time()
            if beste is None or t1 - t0 < beste[0]:
                beste = (t1 - t0, s["jetzt_ms"] / 1000.0 - (t0 + t1) / 2)
        self.rtt, self.versatz = beste
        print("JAM: Uhr %+.3f s (Laufzeit %.0f ms)" % (self.versatz, self.rtt * 1000), flush=True)

    def suchen(self, text):
        try:
            return self.anfrage("/suche", q=text).get("treffer", [])[:L_B_MAX]
        except Exception:
            return []

    def zufall(self, art, wert):
        s = self.anfrage("/zufall", art=art, wert=wert)
        return s["pfad"], s["lied"]

    def sid_holen(self, pfad, md5=None):
        """die SID-Datei: aus der HVSC auf der SD-Karte, sonst vom Server"""
        j = self.jam
        e = j.allein.eintrag(pfad)
        if e and (not md5 or e["md5"] == md5):
            return j.allein.archiv.datei(pfad)
        os.makedirs(CACHE, exist_ok=True)
        ziel = os.path.join(CACHE, re.sub(r"[^A-Za-z0-9_.-]", "_", pfad))
        if not os.path.isfile(ziel):
            kopf = {"User-Agent": "MERIDIAN-816 JAM"}
            if j.e.get("token"):
                kopf["X-Jam-Token"] = j.e["token"]
            r = oeffner().open(urllib.request.Request(self.url("/sid", pfad=pfad), headers=kopf), timeout=15)
            daten = r.read()
            with open(ziel + ".neu", "wb") as f:
                f.write(daten)
            os.replace(ziel + ".neu", ziel)
        return ziel


# ---------------------------------------------------------------- C64 Ultimate als Lautsprecher
class Lautsprecher:
    """spielt das laufende Stueck zusaetzlich auf einer Ultimate im Heimnetz
    (FTP nach /USB2/, dann PUT runners:sidplay - beides ohne HTTP-Rumpf,
    an dem sich die REST-Schnittstelle der U64 verklemmen kann)"""

    def __init__(self, jam):
        self.jam = jam
        self.adresse = None

    def finden(self):
        import socket
        if self.adresse:
            return self.adresse
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.connect(("192.0.2.1", 9))
            netz = s.getsockname()[0].rsplit(".", 1)[0]
            s.close()
        except OSError:
            return None
        gefunden = []

        def probe(ip):
            try:
                r = urllib.request.urlopen("http://%s/v1/version" % ip, timeout=0.6)
                if b"version" in r.read(200):
                    gefunden.append(ip)
            except Exception:
                pass
        fs = [threading.Thread(target=probe, args=("%s.%d" % (netz, i),), daemon=True) for i in range(1, 255)]
        for t in fs:
            t.start()
        for t in fs:
            t.join(1.0)
        self.adresse = gefunden[0] if gefunden else None
        return self.adresse

    def spielen(self, datei, lied):
        def los():
            import ftplib
            ip = self.finden()
            if not ip:
                self.jam.melden("NO C64 ULTIMATE FOUND")
                return
            try:
                ftp = ftplib.FTP(ip, timeout=5)
                ftp.login()
                with open(datei, "rb") as f:
                    ftp.storbinary("STOR /USB2/SIDJAM.SID", f)
                ftp.quit()
                q = urllib.request.Request("http://%s/v1/runners:sidplay?file=/USB2/SIDJAM.SID&songnr=%d"
                                           % (ip, lied), method="PUT")
                urllib.request.urlopen(q, timeout=5).read()
            except Exception as e:
                print("JAM C64U:", e, flush=True)
                self.adresse = None
        threading.Thread(target=los, daemon=True).start()


# ---------------------------------------------------------------- der Dienst
class Jam:
    def __init__(self, fenster, zu_meridian):
        self.f = Fenster(fenster, zu_meridian)
        self.zu_meridian = zu_meridian
        self.e = self.einstellungen_laden()
        self.spieler = Spieler(self)
        self.allein = Allein(self)
        self.netz = Netz(self)
        self.lautsprecher = Lautsprecher(self)
        self.breite = 34
        self.laeuft = None                  # (pfad, lied, start_ms) gemeinsam
        self.aktuell = None                 # Auftrag, der gerade spielt
        self.offen = False                  # App ist offen
        self.abst_ende = 0
        self.stumm = 0                      # Stimmen stumm (Bit 0-2), fuer reSID
        self.herz_laeuft = False
        self.lock = threading.RLock()
        self.auftraege = queue.Queue()
        self.arbeiter = None

    # ---------------------------------------------- Einstellungen
    def einstellungen_laden(self):
        try:
            with open(EINSTELLUNGEN) as f:
                return json.load(f)
        except (OSError, ValueError):
            return {"modus": "ALLEIN", "klang": "ORIGINAL", "auto": ["ZUFALL", ""], "sterne": {}}

    def sichern(self):
        try:
            with open(EINSTELLUNGEN + ".neu", "w") as f:
                json.dump(self.e, f)
            os.replace(EINSTELLUNGEN + ".neu", EINSTELLUNGEN)
        except OSError as e:
            print("JAM: Einstellungen nicht gesichert:", e, flush=True)

    # ---------------------------------------------- Anzeige
    def melden(self, text):
        self.f.text(J + J_MELDUNG, text, 48)
        self.f.zaehlen(J_MELDZ)

    def info_zeigen(self, a):
        f = self.f
        f.text(T_TITEL, a.get("titel", ""), 64)
        f.text(T_AUTOR, a.get("autor", ""), 64)
        f.text(T_JAHR, a.get("jahr", ""), 64)
        teile = []
        if a.get("lieder", 1) > 1:
            teile.append("Song %d/%d" % (a["lied"], a["lieder"]))
        if a.get("modell_text"):
            teile.append(a["modell_text"])
        teile.append("reSID" if a.get("resid") else "MP3" if a.get("original") else "ORGEL")
        f.text(T_INFO, "  ".join(teile), 64)
        f.text(T_STIL, a.get("stil", ""), 160)
        f.zaehlen(J_INFO)

    def liste_schreiben(self, basis, eintraege, hoechstens, zaehler):
        m = self.f.m
        n = min(len(eintraege), hoechstens)
        for i in range(n):
            art, stimmen, markiert, text = eintraege[i]
            a = basis + 0x10 + i * L_EINTRAG
            m[a:a + 4] = bytes((art, min(255, stimmen), markiert, 0))
            self.f.text(a + 4, text, L_EINTRAG - 4)
        m[basis] = n
        self.f.zaehlen(zaehler)

    def chat_schreiben(self, zeilen):
        """zeilen: [(art, text)] - auf die Breite der App umbrochen, die
        letzten C_MAX Zeilen"""
        aus = []
        for art, text in zeilen:
            while True:
                if len(text) <= self.breite:
                    aus.append((art, text))
                    break
                k = text.rfind(" ", 0, self.breite + 1)
                if k <= 0:
                    k = self.breite
                aus.append((art, text[:k]))
                text = "  " + text[k:].lstrip()
        aus = aus[-C_MAX:]
        m = self.f.m
        for i, (art, text) in enumerate(aus):
            a = C_CHAT + 0x10 + i * C_ZEILE
            m[a] = art
            self.f.text(a + 1, text, C_ZEILE - 1)
        m[C_CHAT] = len(aus)
        self.f.zaehlen(J_CHATZ)

    @staticmethod
    def zeile(e):
        t = e.get("titel") or "?"
        if e.get("autor"):
            t += " - " + e["autor"]
        return t

    # ---------------------------------------------- Anfragen der App
    def anfrage(self, art, text):
        """Befehl der App: sofort beantworten, im Arbeitsfaden ausfuehren
        (Netz und Laden duerfen den Netzdienst nicht aufhalten)"""
        befehl = text.decode("latin-1").strip()
        wort, _, rest = befehl.partition(" ")
        fn = getattr(self, "b_" + wort.lower(), None)
        if not fn:
            return -6, b"UNKNOWN JAM COMMAND"
        if wort.upper() == "START":
            self.offen = True                   # sofort: der Stand gilt ab jetzt
        self.auftraege.put((befehl, fn, rest.strip()))
        if not self.arbeiter:
            self.arbeiter = threading.Thread(target=self.arbeiten, daemon=True)
            self.arbeiter.start()
        return 0, b""

    def arbeiten(self):
        while True:
            befehl, fn, rest = self.auftraege.get()
            print("JAM:", befehl, flush=True)
            try:
                with self.lock:
                    erg = fn(rest)
                if erg and erg[0] < 0 and erg[1]:
                    self.melden(erg[1])
            except Exception as e:              # nichts darf den Dienst anhalten
                print("JAM:", befehl, "->", e, flush=True)
                self.melden("ERROR: " + str(e)[:40])

    def b_start(self, rest):
        self.offen = True
        if not self.herz_laeuft:
            self.herz_laeuft = True
            threading.Thread(target=self.herz, daemon=True).start()
        try:
            self.breite = max(20, min(60, int(rest or 34)))
        except ValueError:
            pass
        f = self.f
        f.b(J_ZUSTAND, Z_AUS)
        f.b(J_VERB, V_ALLEIN)
        f.b(J_ANGEMELDET, 1 if self.e.get("name") else 0)
        f.text(J + J_NAME, self.e.get("name", ""), 16)
        f.text(J + J_CODE, "", 16)
        self.liste_schreiben(L_A, [], L_A_MAX, J_LISTEZ)
        self.liste_schreiben(L_B, [], L_B_MAX, J_LISTBZ)
        self.chat_schreiben([])
        if self.e.get("modus") == "GEMEINSAM":
            return self.b_modus("GEMEINSAM")
        return self.b_modus("ALLEIN")

    def herz(self):
        """die App merkt am Stillstand, dass der Dienst neu gestartet wurde,
        und schickt dann START noch einmal"""
        while self.offen:
            self.f.zaehlen(J_HERZ)
            time.sleep(0.5)
        self.herz_laeuft = False

    def wahl_zeigen(self):
        self.f.b(J_WAHL, (1 if self.e.get("klang") == "ORIGINAL" else 0) |
                 (2 if self.e.get("modus") == "GEMEINSAM" else 0))

    def b_stopp(self, rest):
        self.offen = False
        self.spieler.stop()
        self.netz.stoppen()
        self.aktuell = None
        self.laeuft = None
        self.f.b(J_ZUSTAND, Z_AUS)

    def b_modus(self, rest):
        modus = rest.upper()
        if modus not in ("ALLEIN", "GEMEINSAM"):
            return -1, "ALLEIN OR GEMEINSAM"
        self.e["modus"] = modus
        self.sichern()
        self.wahl_zeigen()
        self.spieler.stop()
        self.aktuell = None
        self.laeuft = None
        f = self.f
        f.b(J_SONDER, 0)
        f.b(J_ABST, 0)
        f.w16(J_HOERER, 0)
        self.liste_schreiben(L_A, [], L_A_MAX, J_LISTEZ)
        if modus == "GEMEINSAM":
            f.b(J_MODUS, f.b(J_MODUS) | M_GEMEINSAM)
            self.chat_schreiben([(1, "Connecting to the JAM server ...")])
            self.netz.version = 0
            self.netz.stand = None
            self.abst_ende = 0
            self.netz.starten()
            threading.Thread(target=self.sekunden, args=(self.netz.lauf,), daemon=True).start()
        else:
            self.netz.stoppen()
            f.b(J_VERB, V_ALLEIN)
            f.b(J_MODUS, f.b(J_MODUS) & ~M_GEMEINSAM)
            if not self.allein.laden():
                self.chat_schreiben([(1, "No HVSC on the SD card - tunes come from the JAM server.")])
            else:
                self.chat_schreiben([(1, "Solo: %d tunes from the HVSC." % len(self.allein.verzeichnis)),
                                     (1, "Search with the field above, F2 adds to the wish list.")])
            self.wunsch_zeigen()
            self.allein_weiter()
        return None

    def b_klang(self, rest):
        k = rest.upper()
        if k not in ("ORGEL", "ORIGINAL"):
            return -1, "ORGEL OR ORIGINAL"
        self.e["klang"] = k
        self.sichern()
        self.wahl_zeigen()
        a = self.aktuell
        if a:                                   # an derselben Stelle weiter
            neu = dict(a)
            if self.e["modus"] == "GEMEINSAM" and self.laeuft:
                self.gemeinsam_starten(self.netz.stand["laeuft"])
                return None
            neu["ab"] = a.get("ab", 0) + self.f.w32(J_ZEIT) / 1e6 + LADEZEIT
            if neu["ab"] >= neu["laenge"] - 2:
                return None
            neu["los"] = None
            self.auftrag_starten(neu)
        return None

    def b_stumm(self, rest):
        """Stimmen stumm (Bit 0-2): reSID rechnet ohne sie - an derselben
        Stelle neu starten (die ORGEL schaltet die App selbst)"""
        try:
            self.stumm = int(rest) & 7
        except ValueError:
            return -1, "0-7"
        a = self.aktuell
        if a and a.get("resid"):
            if self.e.get("modus") == "GEMEINSAM" and self.laeuft and self.netz.stand:
                self.gemeinsam_starten(self.netz.stand["laeuft"])
                return None
            neu = dict(a)
            neu["ab"] = a.get("ab", 0) + self.f.w32(J_ZEIT) / 1e6 + LADEZEIT
            neu["los"] = None
            if neu["ab"] < neu["laenge"] - 2:
                self.auftrag_starten(neu)
        return None

    def b_weiter(self, rest):
        if self.e.get("modus") == "GEMEINSAM":
            return self.b_skip(rest)
        self.allein_weiter()

    def b_skip(self, rest):
        if self.e.get("modus") != "GEMEINSAM":
            return self.allein_weiter()
        return self.senden("/skip", {})

    def b_stimme(self, rest):
        return self.senden("/stimme", {"nr": int(rest or 0)})

    def b_suche(self, rest):
        self.allein.treffer = self.allein.suchen(rest) if rest else []
        eintraege = [(3, 0, 0, self.zeile(t) + (" (%s)" % t["jahr"][:4] if t.get("jahr") else ""))
                     for t in self.allein.treffer]
        self.liste_schreiben(L_B, eintraege, L_B_MAX, J_LISTBZ)
        if not eintraege:
            self.melden("NOTHING FOUND" if rest else "")
        return None

    def b_hitparade(self, rest):
        try:
            h = self.netz.anfrage("/hitparade").get("liste", [])
        except Exception:
            h = []
            sterne = self.e.get("sterne", {})
            for k, n in sorted(sterne.items(), key=lambda x: -x[1])[:L_B_MAX]:
                pfad, lied = k.rsplit("#", 1)
                e = self.allein.eintrag(pfad) or {"titel": pfad.rsplit("/", 1)[-1], "autor": ""}
                h.append({"pfad": pfad, "lied": int(lied), "titel": e["titel"], "autor": e["autor"], "punkte": n})
        self.allein.treffer = h
        self.liste_schreiben(L_B, [(4, t.get("punkte", 0), 0, "%2d. %s" % (i + 1, self.zeile(t)))
                                   for i, t in enumerate(h)], L_B_MAX, J_LISTBZ)

    def treffer(self, rest):
        try:
            n = int(rest)
        except ValueError:
            return None
        if 1 <= n <= len(self.allein.treffer):
            return self.allein.treffer[n - 1]
        return None

    def b_wunsch(self, rest):
        t = self.treffer(rest)
        if not t:
            return -1, "NO SUCH ENTRY"
        if self.e.get("modus") == "GEMEINSAM":
            return self.senden("/wunsch", {"pfad": t["pfad"], "lied": t.get("lied", 1)})
        self.allein.wunsch.append((t["pfad"], t.get("lied", 1)))
        self.wunsch_zeigen()
        self.melden("ADDED TO WISH LIST")

    def b_spiele(self, rest):
        t = self.treffer(rest)
        if not t:
            return -1, "NO SUCH ENTRY"
        if self.e.get("modus") == "GEMEINSAM":
            return self.b_wunsch(rest)
        self.allein_spielen(t["pfad"], t.get("lied", 1))

    def b_stern(self, rest):
        try:
            n = max(0, min(5, int(rest)))
        except ValueError:
            return -1, "1-5"
        a = self.aktuell or {}
        if not a.get("pfad"):
            return -1, "NOTHING PLAYING"
        self.e.setdefault("sterne", {})["%s#%d" % (a["pfad"], a["lied"])] = n
        self.sichern()
        self.f.b(J_STERNE, n)
        self.f.zaehlen(J_INFO)
        if self.e.get("modus") == "GEMEINSAM":
            return self.senden("/stern", {"pfad": a["pfad"], "lied": a["lied"], "sterne": n})

    def b_chat(self, rest):
        if not rest:
            return None
        if self.e.get("modus") != "GEMEINSAM":
            return -1, "CHAT ONLY TOGETHER"
        return self.senden("/chat", {"text": rest[:200]})

    def b_koppeln(self, rest):
        try:
            s = self.netz.anfrage("/geraet/neu", {})
        except Exception as e:
            return -1, "SERVER: " + str(e)[:40]
        self.e["token"] = s["token"]
        self.e.pop("name", None)
        self.sichern()
        self.f.text(J + J_CODE, s["code"], 16)
        self.f.b(J_ANGEMELDET, 0)
        self.f.zaehlen(J_INFO)
        return 0, s["code"]

    def b_auto(self, rest):
        art, _, wert = rest.partition(" ")
        art = art.upper()
        if art not in ("ZUFALL", "STERNE", "KOMPONIST", "JAHR"):
            return -1, "ZUFALL STERNE KOMPONIST JAHR"
        self.e["auto"] = [art, wert.strip()]
        self.sichern()
        self.melden("AUTO-DJ: " + art + (" " + wert if wert else ""))

    def b_wunschliste(self, rest):
        self.wunsch_zeigen()

    def b_c64u(self, rest):
        self.e["c64u"] = rest.upper() == "AN"
        self.sichern()
        if self.e["c64u"] and self.aktuell and self.aktuell.get("datei"):
            self.lautsprecher.spielen(self.aktuell["datei"], self.aktuell["lied"])
        self.melden("C64 ULTIMATE " + ("ON" if self.e["c64u"] else "OFF"))

    def senden(self, pfad, daten):
        if self.e.get("modus") != "GEMEINSAM":
            return -1, "ONLY TOGETHER"
        try:
            s = self.netz.anfrage(pfad, daten)
        except urllib.error.HTTPError as e:
            try:
                meldung = json.loads(e.read().decode("utf-8")).get("fehler", str(e.code))
            except Exception:
                meldung = "SERVER %d" % e.code
            self.melden(meldung)
            return -1, meldung
        except Exception as e:
            self.melden("NO CONNECTION")
            return -1, "NO CONNECTION: " + str(e)[:40]
        if s.get("meldung"):
            self.melden(s["meldung"])
        return None

    # ---------------------------------------------- Allein
    def wunsch_zeigen(self):
        if self.e.get("modus") == "GEMEINSAM":
            return
        eintraege = []
        for pfad, lied in self.allein.wunsch:
            e = self.allein.eintrag(pfad) or {"titel": pfad.rsplit("/", 1)[-1]}
            eintraege.append((2, 0, 0, self.zeile(e)))
        self.liste_schreiben(L_A, eintraege, L_A_MAX, J_LISTEZ)

    def allein_weiter(self):
        try:
            pfad, lied = self.allein.naechstes()
        except Exception as e:
            self.melden("NO TUNE: " + str(e)[:30])
            return
        self.wunsch_zeigen()
        self.allein_spielen(pfad, lied)

    def allein_spielen(self, pfad, lied):
        v = self.allein.laden()
        e = self.allein.eintrag(pfad)
        try:
            datei = self.netz.sid_holen(pfad)
        except Exception as x:
            self.melden("LOAD FAILED: " + str(x)[:30])
            return
        if e:
            laenge = v.laenge(e, lied)
            info = {"titel": e["titel"], "autor": e["autor"], "jahr": e["jahr"], "lieder": e["lieder"],
                    "stil": v.stil(e, lied), "modell_text": e["modell"] + " " + e["takt"]}
        else:
            laenge, info = 180.0, {"titel": pfad.rsplit("/", 1)[-1]}
        self.allein.verlauf.append(pfad)
        a = dict(info, pfad=pfad, lied=lied, datei=datei, laenge=laenge, ab=0.0, los=None)
        if self.e.get("klang") == "ORIGINAL":
            if sidton_finden():
                a["resid"] = True
            else:
                a["original"] = self.netz.url("/original", pfad=pfad, lied=lied, ab=0)
        self.f.b(J_STERNE, self.e.get("sterne", {}).get("%s#%d" % (pfad, lied), 0))
        self.auftrag_starten(a)

    def auftrag_starten(self, a):
        self.aktuell = a
        self.spieler.start(a)

    def gestartet(self, a):
        """die App spielt: Ultimate mitnehmen (nur am Anfang eines Stuecks)"""
        if self.e.get("c64u") and a.get("datei") and a.get("ab", 0) < 1.0:
            self.lautsprecher.spielen(a["datei"], a["lied"])

    def zu_ende(self, a):
        if not self.offen or a is not self.aktuell:
            return
        if self.e.get("modus") == "GEMEINSAM":
            self.aktuell = None                 # der Server sagt, was kommt
            n = (self.netz.stand or {}).get("naechstes")
            if n:
                self.gemeinsam_starten(n)
            return
        self.allein_weiter()

    # ---------------------------------------------- Gemeinsam
    def stand_neu(self, s):
        with self.lock:
            if not self.offen:
                return
            f = self.f
            ich = s.get("ich", {})
            if ich.get("name") and ich["name"] != self.e.get("name"):
                self.e["name"] = ich["name"]
                self.sichern()
            f.text(J + J_NAME, self.e.get("name", ""), 16)
            f.b(J_ANGEMELDET, 1 if ich.get("angemeldet") else 0)
            if ich.get("angemeldet"):
                f.text(J + J_CODE, "", 16)
            f.w16(J_HOERER, s.get("hoerer", 0))
            f.b(J_SONDER, SONDER.get(s.get("sonder", ""), 0))
            f.text(T_PROGRAMM, s.get("programm", ""), 64)
            n = s.get("naechstes")
            f.text(T_NAECHST, ("Next: " + self.zeile(n)) if n else "", 64)
            ab = s.get("abstimmung") or {}
            self.abst_ende = ab.get("ende_ms", 0) / 1000.0 if ab else 0
            self.abst_zeigen()
            f.b(J_MEINE, ab.get("meine", 0))
            sk = s.get("skip", {})
            f.b(J_SKIPJA, sk.get("ja", 0))
            f.b(J_SKIPN, sk.get("noetig", 0))
            eintraege = []
            for k in ab.get("kandidaten", []):
                eintraege.append((1, k.get("stimmen", 0), 1 if ab.get("meine") == k.get("nr") else 0,
                                  "%d %s" % (k.get("nr", 0), self.zeile(k))))
            for w in s.get("warteschlange", []):
                eintraege.append((2, 0, 1 if w.get("von") == self.e.get("name") else 0,
                                  self.zeile(w) + (" <" + w["von"] + ">" if w.get("von") else "")))
            self.liste_schreiben(L_A, eintraege, L_A_MAX, J_LISTEZ)
            self.chat_schreiben([(c.get("art", 0) if c.get("name") != self.e.get("name") else 2,
                                  (c["name"] + ": " if c.get("name") else "") + c.get("text", ""))
                                 for c in s.get("chat", [])])
            l = s.get("laeuft")
            if not l:
                if self.aktuell:
                    self.spieler.stop()
                    self.aktuell = None
                f.b(J_ZUSTAND, Z_WARTET)
                return
            schluessel = (l["pfad"], l["lied"], l["start_ms"], self.e.get("klang"))
            if schluessel != self.laeuft:
                self.gemeinsam_starten(l)
            f.b(J_STERNE, ich.get("sterne", 0))   # Sterne gelten je Stueck

    def abst_zeigen(self):
        rest = max(0, int(self.abst_ende - self.netz.jetzt() + 0.5)) if self.abst_ende else 0
        self.f.b(J_ABST, min(255, rest))

    def sekunden(self, lauf):
        """gemeinsam: Restzeit der Abstimmung jede halbe Sekunde"""
        while lauf == self.netz.lauf:
            self.abst_zeigen()
            time.sleep(0.5)

    def gemeinsam_starten(self, l):
        self.laeuft = (l["pfad"], l["lied"], l["start_ms"], self.e.get("klang"))
        jetzt = self.netz.jetzt()
        start = l["start_ms"] / 1000.0
        laenge = l["laenge_ms"] / 1000.0
        ab = 0.0
        if jetzt + LADEZEIT > start:            # schon unterwegs: einsteigen
            ab = jetzt + LADEZEIT - start
        if ab >= laenge - 3:
            return
        los = start + ab - (self.netz.versatz or 0.0)
        if l.get("art") == "jingle":            # Jingle: MP3 vom Server
            self.auftrag_starten({"pfad": "", "lied": 0, "laenge": laenge, "ab": ab, "los": los,
                                  "titel": l.get("titel", "SID JAM"), "autor": l.get("autor", ""),
                                  "gemeinsam": True, "original": self.jam_url(l["url"])})
            return
        if l.get("art") == "musik":             # TAKTSTOCK-Song: MP3 vom Server ab der Liedzeit
            self.auftrag_starten({"pfad": l["pfad"], "lied": 1, "laenge": laenge, "ab": ab, "los": los,
                                  "titel": l.get("titel", ""), "autor": l.get("autor", ""),
                                  "jahr": l.get("jahr", ""), "modell_text": "TAKTSTOCK", "gemeinsam": True,
                                  "original": self.netz.url("/original", pfad=l["pfad"], lied=1,
                                                            ab="%.3f" % ab)})
            return
        try:
            datei = self.netz.sid_holen(l["pfad"], l.get("md5"))
        except Exception as e:
            self.melden("LOAD FAILED: " + str(e)[:30])
            return
        a = {"pfad": l["pfad"], "lied": l["lied"], "datei": datei, "laenge": laenge, "ab": ab, "los": los,
             "titel": l.get("titel", ""), "autor": l.get("autor", ""), "jahr": l.get("jahr", ""),
             "lieder": l.get("lieder", 1), "stil": l.get("stil", ""), "modell": l.get("modell_zwang"),
             "modell_text": l.get("modell_text", ""), "gemeinsam": True}
        if self.e.get("klang") == "ORIGINAL":
            if sidton_finden():
                a["resid"] = True
            else:
                a["original"] = self.netz.url("/original", pfad=l["pfad"], lied=l["lied"], ab="%.3f" % ab,
                                              modell=l.get("modell_zwang") or "")
        self.auftrag_starten(a)

    def jam_url(self, pfad):
        return self.e.get("server", SERVER) + pfad

    def stop(self, still=False):
        """anderer Core: nichts mehr ins Fenster"""
        self.offen = False
        self.spieler.stop()
        self.netz.stoppen()


if __name__ == "__main__":                 # Probe ohne MERIDIAN: Allein-Modus, App simuliert
    fenster = bytearray(0x10000)
    jam = Jam(fenster, lambda s: s.encode("latin-1", "replace"))
    f = jam.f
    jam.anfrage(20, b"START 34")
    time.sleep(1.0)
    print(bytes(fenster[T_TITEL:T_TITEL + 64]).split(b"\0")[0], bytes(fenster[T_AUTOR:T_AUTOR + 40]).split(b"\0")[0])
    # die App: Lauf annehmen, vorfuellen, losgehen, in Echtzeit lesen
    t0 = None
    rp = pp = 0
    app_lauf = None
    gelesen_r = gelesen_p = 0
    ende = time.time() + float(sys.argv[1] if len(sys.argv) > 1 else 6)
    while time.time() < ende:
        time.sleep(0.01)
        if f.b(J_LAUF) != app_lauf:
            app_lauf = f.b(J_LAUF)
            rp = pp = 0
            f.w16(J_RRP, 0)
            f.w16(J_PRP, 0)
            f.b(J_APP_LAUF, app_lauf)
            f.b(J_APP, A_FUELLT)
            los_alt = f.b(J_LOS)
            t0 = None
        if f.b(J_APP) == A_FUELLT:
            wp = f.w16(J_PWP)
            n = (wp - pp) & (P_GROESSE - 1)
            pp = (pp + n) & (P_GROESSE - 1)
            gelesen_p += n
            f.w16(J_PRP, pp)
            if gelesen_p >= VOR:
                f.b(J_APP, A_BEREIT)
        elif f.b(J_APP) == A_BEREIT and f.b(J_LOS) != los_alt:
            f.b(J_APP, A_SPIELT)
            t0 = time.time()
            print("los", flush=True)
        if t0:
            f.w32(J_ZEIT, int((time.time() - t0) * 1e6))
            # Auftraege bis "jetzt" verbrauchen (grob, ohne Zeitpruefung)
            wp = f.w16(J_RWP)
            gelesen_r += (wp - rp) & (R_GROESSE - 1)
            rp = wp
            f.w16(J_RRP, rp)
            wp = f.w16(J_PWP)
            gelesen_p += (wp - pp) & (P_GROESSE - 1)
            pp = wp
            f.w16(J_PRP, pp)
    print("Zustand", f.b(J_ZUSTAND), "Auftraege", gelesen_r, "Bytes, Samples", gelesen_p)
    jam.anfrage(20, b"STOPP")
