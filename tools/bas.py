#!/usr/bin/env python3
"""BASIC-Programme fuer den MERIDIAN am Mac schreiben: Text <-> .BAS

    bas.py rein spiel.bas SPIEL.BAS [--disk BILD.DSK]
        Text in ein Programm wandeln (wie LOAD es erwartet); mit --disk
        gleich auf die Diskette legen
    bas.py liste SPIEL.BAS                Programm als Text zeigen
    bas.py liste BILD.DSK SPIEL.BAS       ... direkt von der Diskette

Das Umwandeln macht es wie Microsofts CRUNCH im MERIDIAN: Schluesselwoerter
werden ueberall erkannt, auch mitten in Namen (SCORE wird zu SC + OR + E).
Das Werkzeug warnt dann. Ausserhalb von Anfuehrungszeichen gilt Gross-
schreibung (auch nach REM, wie beim Eintippen); nach REM und in DATA wird
nichts umgewandelt. Vor ELSE setzt es wie der Rechner ein ":" ein, wenn
keins dasteht (Etappe 13).

Die Wortlisten liest es aus dem gebauten BASIC-ROM (rom/basic.hex,
basic/basic.lbl) - sie stimmen also immer mit dem Rechner ueberein.
"""
import argparse
import os
import re
import sys

HIER = os.path.dirname(os.path.abspath(__file__))
BASIS = os.path.dirname(HIER)
TXTTAB = 0x4801                 # erste Programmzeile (LOAD verkettet neu)


def wortlisten():
    lbl = {}
    for z in open(os.path.join(BASIS, "basic", "basic.lbl")):
        m = re.match(r"(\w+)\s*=\s*\$?([0-9a-fA-F]+)", z)
        if m:
            w = m.group(2)
            lbl[m.group(1)] = int(w, 16) if "$" in z.split("=")[1] else int(w)
    rom = bytes(int(z, 16) for z in open(os.path.join(BASIS, "rom", "basic.hex")) if z.strip())
    basis = 0x2000

    def liste(adr):
        woerter, w, i = [], b"", adr - basis
        while rom[i]:
            c = rom[i]
            w += bytes([c & 0x7F])
            if c & 0x80:
                woerter.append(w.decode("ascii"))
                w = b""
            i += 1
        return woerter
    ms = liste(lbl["RESLST"])
    eigene = liste(lbl["M_RESLST"])
    tokens = {w: lbl["ENDTK"] + i for i, w in enumerate(ms)}
    tokens.update({w: lbl["GOTK"] + 1 + i for i, w in enumerate(eigene)})
    return ms + eigene, tokens


def crunch(text, woerter, tokens, zeile, warnen):
    aus = bytearray()
    i = 0
    while i < len(text) and text[i] == " ":
        i += 1
    rem = data = False
    while i < len(text):
        c = text[i]
        if rem:
            aus += c.upper().encode("latin-1"); i += 1; continue
        if c == '"':                                    # Text bis zum naechsten "
            j = text.find('"', i + 1)
            j = len(text) if j < 0 else j + 1
            aus += text[i:j].encode("latin-1"); i = j; continue
        if data:
            if c == ":":
                data = False
            aus += c.upper().encode("latin-1"); i += 1; continue
        if c == "?":
            aus.append(tokens["PRINT"]); i += 1; continue
        gross = text[i:].upper()
        for w in woerter:
            if gross.startswith(w):
                if warnen and i > 0 and text[i - 1].isalpha() and w[0].isalpha():
                    print(f"  Zeile {zeile}: {w} steckt in einem Namen ({text[max(0, i - 3):i + len(w) + 2].strip()})",
                          file=sys.stderr)
                if w == "ELSE" and aus.rstrip(b" ") and not aus.rstrip(b" ").endswith(b":"):
                    aus += b":"                         # wie der Rechner: ELSE beginnt einen Befehl
                aus.append(tokens[w])
                i += len(w)
                if w == "REM":
                    rem = True
                elif w == "DATA":
                    data = True
                break
        else:
            aus += c.upper().encode("latin-1")
            i += 1
    return bytes(aus)


def rein(quelle, warnen=True):
    woerter, tokens = wortlisten()
    prog = bytearray()
    adr = TXTTAB
    letzte = -1
    for nr, z in enumerate(open(quelle, encoding="utf-8").read().splitlines(), 1):
        z = z.rstrip()
        if not z.strip():
            continue
        m = re.match(r"\s*(\d+)\s?(.*)", z)
        if not m:
            sys.exit(f"{quelle}:{nr}: keine Zeilennummer")
        n = int(m.group(1))
        if n <= letzte or n > 63999:
            sys.exit(f"{quelle}:{nr}: Zeilennummer {n} nicht aufsteigend")
        letzte = n
        rumpf = crunch(m.group(2), woerter, tokens, n, warnen)
        if len(rumpf) > 250:
            sys.exit(f"{quelle}:{nr}: Zeile zu lang")
        naechste = adr + 4 + len(rumpf) + 1
        prog += naechste.to_bytes(2, "little") + n.to_bytes(2, "little") + rumpf + b"\0"
        adr = naechste
    prog += b"\0\0"
    return bytes(prog)


def liste(daten):
    woerter, tokens = wortlisten()
    namen = {v: k for k, v in tokens.items()}
    i = 0
    zeilen = []
    while i + 1 < len(daten) and (daten[i] or daten[i + 1]):
        n = int.from_bytes(daten[i + 2:i + 4], "little")
        j = i + 4
        s, text = "", False
        while daten[j]:
            c = daten[j]
            if c == 0x22:
                text = not text
            s += namen.get(c, chr(c)) if (c >= 0x80 and not text) else chr(c)
            j += 1
        zeilen.append(f"{n} {s}")
        i = j + 1
    return "\n".join(zeilen)


def main():
    a = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    u = a.add_subparsers(dest="befehl", required=True)
    b = u.add_parser("rein"); b.add_argument("quelle"); b.add_argument("ziel"); b.add_argument("--disk")
    b = u.add_parser("liste"); b.add_argument("datei"); b.add_argument("name", nargs="?")
    o = a.parse_args()
    if o.befehl == "rein":
        prog = rein(o.quelle)
        if o.disk:
            sys.path.insert(0, HIER)
            import disk
            fs = disk.Fat16(o.disk)
            fs.schreiben(os.path.basename(o.ziel), prog)
            fs.speichern()
            print(f"{os.path.basename(o.ziel).upper()} auf {o.disk}: {len(prog)} Bytes")
        else:
            open(o.ziel, "wb").write(prog)
            print(f"{o.ziel}: {len(prog)} Bytes")
    else:
        if o.name:
            sys.path.insert(0, HIER)
            import disk
            daten = disk.Fat16(o.datei).lesen(o.name)
        else:
            daten = open(o.datei, "rb").read()
        print(liste(daten))


if __name__ == "__main__":
    main()
