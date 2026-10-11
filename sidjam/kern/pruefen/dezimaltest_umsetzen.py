#!/usr/bin/env python3
"""Bruce Clarks Dezimaltest (6502_decimal_test.a65 aus Klaus Dormanns
Sammlung, as65-Syntax) fuer 64tass umsetzen - mit Pruefung von N, V und Z
(NMOS-Verhalten) zusaetzlich zu A und C. Das Testende wird ein JMP *.

Aufruf: dezimaltest_umsetzen.py 6502_decimal_test.a65 dezimal.asm
Dann:   64tass -q -b -o dezimal.bin dezimal.asm   (Bytes ab $0200, Fehlerbyte $000B)
"""
import re
import sys

quelle, ziel = sys.argv[1], sys.argv[2]
aus = []
in_makro = False
for z in open(quelle, encoding="latin-1"):
    z = z.rstrip("\n")
    roh = z.split(";")[0].strip()
    if re.match(r"^end_of_test\s+macro", roh):
        in_makro = True
        continue
    if in_makro:
        if roh == "endm":
            in_makro = False
        continue
    for name in ("chk_n", "chk_v", "chk_z"):
        if re.match(rf"^{name}\s*=", roh):
            z = f"{name} = 1"
    if roh in ("bss", "code"):
        continue
    if roh == "end_of_test":
        aus.append("        jmp *")
        continue
    if re.match(r"^end\b", roh):
        continue
    m = re.match(r"^(\s*)org\s+(\S+)", z)
    if m:
        aus.append(f"* = {m.group(2)}")
        continue
    z = re.sub(r"\bds\s+(\d+)", r".fill \1", z)
    z = re.sub(r"^(\s*)if\s+(\w+)\s*=\s*(\w+)", r"\1.if \2 == \3", z)
    z = re.sub(r"^(\s*)if\s+(\w+)\s*!=\s*(\w+)", r"\1.if \2 != \3", z)
    z = re.sub(r"^(\s*)endif\b", r"\1.fi", z)
    aus.append(z)
open(ziel, "w").write("\n".join(aus) + "\n")
