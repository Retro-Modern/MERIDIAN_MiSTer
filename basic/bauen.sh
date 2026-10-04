#!/bin/zsh
# Baut MERIDIAN BASIC: Microsoft-Quelle (MACRO-10) -> 64tass -> BASIC-ROM
#   basic/bauen.sh  ->  rom/basic.hex (16 KB, Bank $FF) und rom/basic_sym.inc
set -e
cd ${0:A:h}
python3 werkzeuge/m10.py quelle/m6502.asm einstellungen.txt > m6502.s
python3 werkzeuge/anpassen.py m6502.s basic.s
iconv -f UTF-8 -t ISO-8859-1 meridian.s > meridian.latin1.s
64tass --long-branch -q -b -o basic_voll.bin -l basic.lbl -L basic.lst meridian.latin1.s
rm meridian.latin1.s
python3 werkzeuge/bankpruefung.py basic.lst
python3 - <<'PY'
import re
lbl = {}
for z in open("basic.lbl"):
    m = re.match(r"^(\S+)\s*=\s*\$?([0-9a-fA-F]+)", z)
    if m:
        lbl[m.group(1).upper()] = int(m.group(2), 16)
voll = open("basic_voll.bin", "rb").read()
anfang = min(v for v in lbl.values() if v >= 0x55) if False else 0x55
# 64tass schreibt ab der niedrigsten Adresse: der Zeropage ($55)
von, bis = lbl["ROMLOC"], lbl["BASIC_ENDE"]
code = voll[von - 0x55:bis - 0x55]
assert bis <= lbl["RAMLOC"], f"BASIC reicht bis ${bis:04X}, in den Programmspeicher"
# Etappe 13: die Erweiterung (nur Bank 0, ab ERWEITERUNG) folgt im ROM ab
# $2800 - dahinter, wo der Hauptteil hoechstens enden kann
evon, ebis = lbl["ERWEITERUNG"], lbl["ERW_ENDE"]
erw = voll[evon - 0x55:ebis - 0x55]
ERW_ROM = lbl["RAMLOC"] - von
rom = code + b"\xff" * (ERW_ROM - len(code)) + erw
rom += b"\xff" * (16384 - len(rom))
with open("../rom/basic.hex", "w") as f:
    f.write("\n".join(f"{b:02x}" for b in rom) + "\n")
with open("../rom/basic_sym.inc", "w") as f:
    f.write("; Automatisch erzeugt von basic/bauen.sh\n")
    for n in ("ROMLOC", "RAMLOC", "INIT", "START", "READY", "BUF", "BASIC_ENDE", "DATENBANK"):
        f.write(f"B_{n} = ${lbl[n]:04x}\n")
    f.write(f"B_LAENGE = ${bis - von:04x}\n")
    f.write(f"B_ERW = ${evon:04x}\nB_ERW_ROM = ${ERW_ROM:04x}\nB_ERW_LAENGE = ${ebis - evon:04x}\n")
print(f"MERIDIAN BASIC: ${von:04X}-${bis - 1:04X}, {bis - von} Bytes, Reserve bis ${lbl['RAMLOC']:04X}: {lbl['RAMLOC'] - bis}")
print(f"Erweiterung: ${evon:04X}-${ebis - 1:04X}, {ebis - evon} Bytes, frei bis $C000: {0xC000 - ebis}")
PY
