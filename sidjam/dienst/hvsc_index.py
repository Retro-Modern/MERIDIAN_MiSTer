#!/usr/bin/env python3
"""HVSC-Verzeichnis fuer SID JAM - bauen und lesen

Liest die HVSC (Ordner C64Music) einmal ganz und schreibt ein kleines
Verzeichnis, das der Server und der Allein-Modus auf dem MiSTer benutzen:

    python3 hvsc_index.py bauen  .../C64Music  hvsc_index.tsv.gz
    python3 hvsc_index.py suchen hvsc_index.tsv.gz hubbard commando

Je Zeile (Tabulator, UTF-8, gzip):
    pfad      relativ zu C64Music, mit "/" (MUSICIANS/H/Hubbard_Rob/Commando.sid)
    titel, autor, jahr     aus dem SID-Kopf (released)
    lieder, start          Anzahl der Lieder, Startlied (1-basiert)
    laengen   Laufzeit je Lied in Sekunden (Leerzeichen dazwischen, aus
              Songlengths.md5; 0 = unbekannt)
    modell    6581, 8580, beide oder ?
    takt      PAL, NTSC, beide oder ?
    art       P (PSID) oder R (RSID)
    basic     1, wenn das Stueck BASIC braucht (nicht spielbar)
    sids      Anzahl der SID-Chips (1-3)
    md5       MD5 der ganzen Datei
    stil      Hinweise aus STIL.txt je Lied: "0=Kommentar||2=Cover: ..."
              (0 = fuer die ganze Datei), oder leer

Nur Python-Standardbibliothek (laeuft auch auf dem MiSTer mit Python 3.9).
"""
import gzip
import hashlib
import os
import re
import struct
import sys

FELDER = ["pfad", "titel", "autor", "jahr", "lieder", "start", "laengen",
          "modell", "takt", "art", "basic", "sids", "md5", "stil"]


def kopf_lesen(daten):
    """SID-Kopf -> dict (oder None, wenn es keine SID-Datei ist)"""
    if len(daten) < 0x76 or daten[:4] not in (b"PSID", b"RSID"):
        return None
    art = "R" if daten[:4] == b"RSID" else "P"
    version, versatz, lade, init, play, lieder, start, speed = struct.unpack(">HHHHHHHI", daten[4:22])

    def text(a, b):
        return daten[a:b].split(b"\0")[0].decode("latin-1").strip()
    flags, zweit, dritt = 0, 0, 0
    if version >= 2 and len(daten) >= 0x7C:
        flags = struct.unpack(">H", daten[0x76:0x78])[0]
        zweit = daten[0x7A]
        dritt = daten[0x7B] if version >= 4 else 0
    m = (flags >> 4) & 3
    t = (flags >> 2) & 3
    return {
        "art": art, "version": version, "lade": lade, "init": init, "play": play,
        "lieder": max(1, lieder), "start": max(1, start or 1), "speed": speed,
        "titel": text(0x16, 0x36), "autor": text(0x36, 0x56), "jahr": text(0x56, 0x76),
        "basic": 1 if (art == "R" and flags & 2) else 0,
        "modell": {0: "?", 1: "6581", 2: "8580", 3: "beide"}[m],
        "takt": {0: "?", 1: "PAL", 2: "NTSC", 3: "beide"}[t],
        "sids": 1 + (1 if zweit else 0) + (1 if dritt else 0),
    }


def laengen_lesen(pfad):
    """Songlengths.md5 -> {md5: [sekunden, ...]}"""
    erg = {}
    with open(pfad, encoding="latin-1") as f:
        for z in f:
            if "=" not in z or z.startswith(";") or z.startswith("["):
                continue
            md5, rest = z.strip().split("=", 1)
            werte = []
            for teil in rest.split():
                m = re.match(r"(\d+):(\d+)(?:\.(\d+))?", teil)
                if m:
                    s = int(m.group(1)) * 60 + int(m.group(2))
                    if m.group(3):
                        s += int(m.group(3)) / (10 ** len(m.group(3)))
                    werte.append(round(s, 3))
            erg[md5.lower()] = werte
    return erg


def stil_lesen(pfad):
    """STIL.txt -> {pfad: {lied: Hinweis}}; lied 0 = fuer die ganze Datei.
    Je Abschnitt der erste TITLE (mit ARTIST) als "Cover: ...", sonst der
    Anfang des ersten COMMENT."""
    erg = {}
    aktuell, lied, abschnitte, zuletzt = None, 0, {}, None

    def ablegen():
        if not aktuell:
            return
        texte = {}
        for n, a in abschnitte.items():
            if a.get("titel"):
                t = "Cover: " + a["titel"] + (" (" + a["kuenstler"] + ")" if a.get("kuenstler") else "")
            elif a.get("kommentar"):
                t = a["kommentar"]
            else:
                continue
            texte[n] = re.sub(r"\s+", " ", t).strip()[:160]
        if texte:
            erg[aktuell] = texte
    with open(pfad, encoding="latin-1") as f:
        for z in f:
            z = z.rstrip("\r\n")
            if z.startswith("/"):
                ablegen()
                aktuell, lied, abschnitte, zuletzt = z.strip().lstrip("/"), 0, {}, None
                continue
            m = re.match(r"\(#(\d+)\)", z)
            if m:
                lied, zuletzt = int(m.group(1)), None
                continue
            a = abschnitte.setdefault(lied, {})
            m = re.match(r"\s*(TITLE|ARTIST|COMMENT|NAME|AUTHOR):\s?(.*)", z)
            if m:
                feld, wert = m.group(1), m.group(2).strip()
                zuletzt = None
                if feld == "TITLE" and "titel" not in a:
                    a["titel"], zuletzt = wert, "titel"
                elif feld == "ARTIST" and "kuenstler" not in a and "titel" in a:
                    a["kuenstler"] = wert
                elif feld == "COMMENT" and "kommentar" not in a:
                    a["kommentar"], zuletzt = wert, "kommentar"
            elif z.startswith("         ") and zuletzt and len(a.get(zuletzt, "")) < 160:
                a[zuletzt] += " " + z.strip()
            elif not z.strip():
                zuletzt = None
    ablegen()
    return erg


def stil_text(texte):
    """{lied: text} -> Feld im Verzeichnis: "0=...||2=..." """
    return "||".join("%d=%s" % (n, t.replace("||", "|")) for n, t in sorted(texte.items()))


def bauen(c64music, ziel):
    doku = os.path.join(c64music, "DOCUMENTS")
    laengen = laengen_lesen(os.path.join(doku, "Songlengths.md5"))
    stil = stil_lesen(os.path.join(doku, "STIL.txt"))
    zeilen = []
    for wurzel, ordner, dateien in os.walk(c64music):
        ordner.sort()
        for name in sorted(dateien):
            if not name.lower().endswith(".sid"):
                continue
            p = os.path.join(wurzel, name)
            with open(p, "rb") as f:
                daten = f.read()
            k = kopf_lesen(daten)
            if not k:
                continue
            md5 = hashlib.md5(daten).hexdigest()
            rel = os.path.relpath(p, c64music).replace(os.sep, "/")
            ll = laengen.get(md5, [])
            ll = ll + [0] * (k["lieder"] - len(ll))
            werte = [rel, k["titel"], k["autor"], k["jahr"], str(k["lieder"]), str(k["start"]),
                     " ".join(("%g" % x) for x in ll[:k["lieder"]]),
                     k["modell"], k["takt"], k["art"], str(k["basic"]), str(k["sids"]), md5,
                     stil_text(stil.get(rel, {}))]
            zeilen.append("\t".join(w.replace("\t", " ") for w in werte))
    with gzip.open(ziel, "wt", encoding="utf-8") as f:
        f.write("\t".join(FELDER) + "\n")
        for z in zeilen:
            f.write(z + "\n")
    return len(zeilen)


class Verzeichnis:
    """Das Verzeichnis im Speicher, mit einfacher Suche"""

    def __init__(self, pfad):
        self.eintraege = []
        self.nach_pfad = {}
        with gzip.open(pfad, "rt", encoding="utf-8") as f:
            kopf = f.readline().rstrip("\n").split("\t")
            for z in f:
                w = z.rstrip("\n").split("\t")
                e = dict(zip(kopf, w))
                e["lieder"] = int(e["lieder"])
                e["start"] = int(e["start"])
                e["laengen"] = [float(x) for x in e["laengen"].split()] if e["laengen"] else []
                e["basic"] = e["basic"] == "1"
                e["sids"] = int(e["sids"])
                e["stil"] = dict((int(t.split("=", 1)[0]), t.split("=", 1)[1])
                                 for t in e["stil"].split("||") if "=" in t)
                e["such"] = (e["titel"] + " " + e["autor"] + " " + e["jahr"] + " " + e["pfad"]).lower()
                self.nach_pfad[e["pfad"]] = e
                self.eintraege.append(e)

    def suchen(self, text, hoechstens=40):
        woerter = [w for w in text.lower().split() if w]
        if not woerter:
            return []
        erg = []
        for e in self.eintraege:
            s = e["such"]
            if all(w in s for w in woerter):
                erg.append(e)
                if len(erg) >= hoechstens:
                    break
        return erg

    def stil(self, e, lied):
        """Hinweis aus STIL fuer Lied (1-basiert), sonst der fuer die Datei"""
        return e["stil"].get(lied) or e["stil"].get(0, "")

    def laenge(self, e, lied):
        """Laufzeit von Lied (1-basiert) in Sekunden; unbekannt: 180"""
        if 1 <= lied <= len(e["laengen"]) and e["laengen"][lied - 1] > 0:
            return e["laengen"][lied - 1]
        return 180.0

    def spielbar(self, e, nur_ein_sid=True):
        return not e["basic"] and (e["sids"] == 1 or not nur_ein_sid)


class KleinesVerzeichnis:
    """dasselbe Verzeichnis sparsam (MiSTer): nur die Zeilen als Text, ein
    Eintrag wird erst beim Abruf zerlegt. Gut 30 MB statt 140 MB."""

    def __init__(self, pfad):
        self.zeilen = []
        self.klein = []                     # fuer die Suche: Titel Autor Jahr Pfad
        self.nach_pfad_nr = {}
        with gzip.open(pfad, "rt", encoding="utf-8") as f:
            self.kopf = f.readline().rstrip("\n").split("\t")
            for z in f:
                z = z.rstrip("\n")
                w = z.split("\t", 4)
                self.nach_pfad_nr[w[0]] = len(self.zeilen)
                self.zeilen.append(z)
                self.klein.append((w[1] + " " + w[2] + " " + w[3] + " " + w[0]).lower())

    def __len__(self):
        return len(self.zeilen)

    def zerlegen(self, nr):
        e = dict(zip(self.kopf, self.zeilen[nr].split("\t")))
        e["lieder"] = int(e["lieder"])
        e["start"] = int(e["start"])
        e["laengen"] = [float(x) for x in e["laengen"].split()] if e["laengen"] else []
        e["basic"] = e["basic"] == "1"
        e["sids"] = int(e["sids"])
        e["stil"] = dict((int(t.split("=", 1)[0]), t.split("=", 1)[1])
                         for t in e["stil"].split("||") if "=" in t)
        return e

    def eintrag(self, pfad):
        nr = self.nach_pfad_nr.get(pfad)
        return None if nr is None else self.zerlegen(nr)

    def suchen(self, text, hoechstens=40):
        woerter = [w for w in text.lower().split() if w]
        erg = []
        if woerter:
            for nr, s in enumerate(self.klein):
                if all(w in s for w in woerter):
                    erg.append(self.zerlegen(nr))
                    if len(erg) >= hoechstens:
                        break
        return erg

    def nummern(self, wort):
        """Nummern der Eintraege, deren Suchtext das Wort enthaelt"""
        wort = wort.lower()
        return [nr for nr, s in enumerate(self.klein) if wort in s]

    laenge = Verzeichnis.laenge
    stil = Verzeichnis.stil
    spielbar = Verzeichnis.spielbar


if __name__ == "__main__":
    if len(sys.argv) >= 4 and sys.argv[1] == "bauen":
        n = bauen(sys.argv[2], sys.argv[3])
        print(n, "Stuecke im Verzeichnis", sys.argv[3])
    elif len(sys.argv) >= 3 and sys.argv[1] == "suchen":
        v = Verzeichnis(sys.argv[2])
        for e in v.suchen(" ".join(sys.argv[3:])):
            print(e["pfad"], "|", e["titel"], "|", e["autor"], "|", e["jahr"], "|", e["laengen"], "|", e["stil"])
    else:
        print(__doc__)
