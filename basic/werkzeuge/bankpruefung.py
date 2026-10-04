#!/usr/bin/env python3
"""Prueft das BASIC-Listing auf Zugriffe, die vom Datenbankregister abhaengen,
aber nicht in BASICs Datenbank gehoeren.

BASIC laeuft mit Datenbank 1: absolute Adressen (und (zp),y) zielen auf
Bank 1. Dort spiegelt $0000-$1FFF die Bank 0 (Zeropage, Stapel, Puffer),
ab $2000 steht eine Kopie des BASIC-Codes, ab RAMLOC liegen die Daten.
Fehler sind deshalb:
  - absolute Zugriffe ab $C000: in Bank 0 Chips und Kern, in Bank 1 Daten
    (Chipregister nur mit langer Adresse ansprechen);
  - Schreibzugriffe in den Code ($2000 bis RAMLOC): die Kopie in Bank 1
    wuerde geaendert, ausgefuehrt wird aber Bank 0;
  - absolute Zugriffe in die Erweiterung ($B800-$BFFF, Etappe 13): sie
    steht nur in Bank 0, in Bank 1 liegen dort Programmdaten.

    python3 bankpruefung.py basic.lst
"""
import re
import sys

LESEN = {0x0D, 0x19, 0x1D, 0x2C, 0x2D, 0x39, 0x3C, 0x3D, 0x4D, 0x59, 0x5D,
         0x6D, 0x79, 0x7D, 0xAC, 0xAD, 0xAE, 0xB9, 0xBC, 0xBD, 0xBE, 0xCC,
         0xCD, 0xD9, 0xDD, 0xEC, 0xED, 0xF9, 0xFD}
SCHREIBEN = {0x0C, 0x0E, 0x1C, 0x1E, 0x2E, 0x3E, 0x4E, 0x5E, 0x6E, 0x7E, 0x8C,
             0x8D, 0x8E, 0x99, 0x9C, 0x9D, 0x9E, 0xCE, 0xDE, 0xEE, 0xFE}
# CHRGET: "lda $ea60" ist ein Platzhalter, die Adresse ist TXTPTR (Programm)
ERLAUBT = {(0xAD, 0xEA60)}
RAMLOC = 0x4800
ERWEITERUNG = 0xB800        # Etappe 13: Code nur in Bank 0, ohne Kopie in Bank 1

zeile = re.compile(r"^\.([0-9a-f]{4})\t([0-9a-f]{2}) ([0-9a-f]{2}) ([0-9a-f]{2})\t")
fehler = 0
for z in open(sys.argv[1], encoding="latin-1"):
    m = zeile.match(z)
    if not m:
        continue
    op = int(m.group(2), 16)
    adr = int(m.group(3), 16) | int(m.group(4), 16) << 8
    if (op, adr) in ERLAUBT:
        continue
    if (op in LESEN or op in SCHREIBEN) and adr >= 0xC000:
        fehler += 1
        print("Chip/Kern:", z.rstrip())
    elif op in SCHREIBEN and 0x2000 <= adr < RAMLOC:
        fehler += 1
        print("in den Code:", z.rstrip())
    elif (op in LESEN or op in SCHREIBEN) and ERWEITERUNG <= adr < 0xC000:
        fehler += 1                 # die Erweiterung gibt es nur in Bank 0
        print("in die Erweiterung:", z.rstrip())
print(f"Bankpruefung: {fehler} Fehler", file=sys.stderr)
sys.exit(1 if fehler else 0)
