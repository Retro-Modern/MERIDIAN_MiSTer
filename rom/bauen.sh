#!/bin/zsh
# Baut das KERN-ROM: Zeichensatz und Tastaturtabellen erzeugen, nach Latin-1
# wandeln (Umlaute in Texten), assemblieren, Hex fuer Quartus/Verilator
set -e
HIER=${0:A:h}/..
cd $HIER
basic/bauen.sh
cd $HIER
python3 tools/zeichensatz.py
python3 tools/tastatur.py
python3 tools/farben.py
iconv -f UTF-8 -t ISO-8859-1 rom/kern.asm > rom/kern.latin1.asm
( cd rom && 64tass --long-branch -b -q -o kern.bin -L kern.lst -l kern.lbl kern.latin1.asm )
rm rom/kern.latin1.asm
python3 tools/rom2hex.py
# Adressen im Kern fuer DOS (Fernstart) und Werkstatt (MERIDIAN 1.0)
python3 - <<'PY'
import re
lbl = {}
for z in open("rom/kern.lbl"):
    m = re.match(r"^(\S+)\s*=\s*\$?([0-9a-fA-F]+)", z)
    if m:
        lbl[m.group(1)] = int(m.group(2), 16)
with open("rom/kern_sym.inc", "w") as f:
    f.write("; Automatisch erzeugt von rom/bauen.sh: Adressen im Kern fuer DOS und Werkstatt\n")
    for n in ("l_befehl", "l_funktion", "l_getin", "palette", "zeichensatz", "baenke", "nmi"):
        f.write(f"K_{n.upper()} = ${lbl[n]:06x}\n")
PY
# Kopfzeilen fuer die DATA-Zeilen der Werkstatt (rom/spritedata.asm), mit
# denselben Woertern umgewandelt wie im gebauten BASIC
python3 - <<'PY2'
import re, sys
sys.path.insert(0, "tools")
import bas
woerter, tokens = bas.wortlisten()
# Byte n (1-31) = Zeilennummer Anfang + (n - 1) x 10 (setzt das ROM ein)
zeilen = ["REM SPRITE PATTERNS FROM THE WORKSHOP - GOSUB \x01", "DIM PB(127):RESTORE",
          'READ A$:IF A$<>"SPRITEDATA" THEN \x03', "READ M:IF M<0 THEN RETURN",
          "READ PB(M):FOR Z=0 TO 15:READ A$:PATTERN M,Z,A$:NEXT:GOTO \x04", "DATA SPRITEDATA"]
with open("rom/sprite_kopf.inc", "w") as f:
    f.write("; Automatisch erzeugt von rom/bauen.sh (tools/bas.py): die Kopfzeilen\n")
    f.write(f"SX_DATATK = {tokens['DATA']}\nsx_kopf\n")
    for z in zeilen:
        b = bas.crunch(z, woerter, tokens, 0, False)
        f.write(f"\t.byte {len(b)}, " + ", ".join(f"${x:02x}" for x in b) + f"\t; {re.sub(r'[\x01-\x1f]', lambda m: '*+%d' % (10 * (ord(m.group()) - 1)), z)}\n")
    f.write("\t.byte 0\n")
PY2
( cd rom && 64tass --long-branch -b -q -o dos.bin -L dos.lst dos.asm )
python3 - <<'PY'
d = open("rom/dos.bin", "rb").read()
assert len(d) <= 16384, "DOS-ROM zu gross"
open("rom/dos.hex", "w").write("\n".join(f"{b:02x}" for b in d + b"\xff" * (16384 - len(d))) + "\n")
print(f"rom/dos.hex: DOS {len(d)} Bytes, frei {16384 - len(d)}")
PY
( cd rom && 64tass --long-branch -b -q -o song.bin -L song.lst song.asm )
python3 - <<'PY'
d = open("rom/song.bin", "rb").read()
assert len(d) <= 16384, "SONG-ROM zu gross"
open("rom/song.hex", "w").write("\n".join(f"{b:02x}" for b in d + b"\xff" * (16384 - len(d))) + "\n")
print(f"rom/song.hex: SONG {len(d)} Bytes, frei {16384 - len(d)}")
PY
( cd rom && 64tass --long-branch -b -q -o werkstatt.bin -L werkstatt.lst werkstatt.asm )
python3 - <<'PY'
d = open("rom/werkstatt.bin", "rb").read()
assert len(d) <= 16384, "Werkstatt-ROM zu gross"
open("rom/werkstatt.hex", "w").write("\n".join(f"{b:02x}" for b in d + b"\xff" * (16384 - len(d))) + "\n")
print(f"rom/werkstatt.hex: WERKSTATT {len(d)} Bytes, frei {16384 - len(d)}")
PY
