#!/usr/bin/env python3
"""Befehlstabelle des 65C816 fuer den Monitor (Etappe 13).

Erzeugt rom/opcodes.inc: Mnemonics, je Opcode Mnemonic und Adressierungsart,
je Art Vorsatz, Operandengroesse und Nachsatz. Mit --pruefen assembliert es
jeden der 256 Befehle mit 64tass und vergleicht das erste Byte - so stimmt
die Tabelle mit einem Assembler ueberein, dem wir schon vertrauen.

    python3 tools/opcodes.py            rom/opcodes.inc schreiben
    python3 tools/opcodes.py --pruefen  zusaetzlich gegen 64tass pruefen
"""
import os
import subprocess
import sys
import tempfile

HIER = os.path.dirname(os.path.abspath(__file__))
BASIS = os.path.dirname(HIER)

# Adressierungsarten: Name, Vorsatz, Art des Operanden, Nachsatz, 64tass-Muster
#   Art: 0 keiner, 1/2/3 Bytes, 4 nach M, 5 nach X, 6 relativ 8, 7 relativ 16,
#        8 Blockbefehl (zwei Baenke), 9 Akku ("A")
ARTEN = [
    ("IMP",   "",  0, "",       "{m}"),
    ("AKKU",  "",  9, "",       "{m} a"),
    ("IMM_M", "#", 4, "",       "{m} #$12"),
    ("IMM_X", "#", 5, "",       "{m} #$12"),
    ("IMM8",  "#", 1, "",       "{m} #$12"),
    ("DP",    "",  1, "",       "{m} $12"),
    ("DPX",   "",  1, ",X",     "{m} $12,x"),
    ("DPY",   "",  1, ",Y",     "{m} $12,y"),
    ("DPI",   "(", 1, ")",      "{m} ($12)"),
    ("DPIX",  "(", 1, ",X)",    "{m} ($12,x)"),
    ("DPIY",  "(", 1, "),Y",    "{m} ($12),y"),
    ("DPL",   "[", 1, "]",      "{m} [$12]"),
    ("DPLY",  "[", 1, "],Y",    "{m} [$12],y"),
    ("ABS",   "",  2, "",       "{m} $1234"),
    ("ABSX",  "",  2, ",X",     "{m} $1234,x"),
    ("ABSY",  "",  2, ",Y",     "{m} $1234,y"),
    ("LONG",  "",  3, "",       "{m} $123456"),
    ("LONGX", "",  3, ",X",     "{m} $123456,x"),
    ("ABSI",  "(", 2, ")",      "{m} ($1234)"),
    ("ABSIX", "(", 2, ",X)",    "{m} ($1234,x)"),
    ("ABSL",  "[", 2, "]",      "{m} [$1234]"),
    ("REL",   "",  6, "",       "{m} *+2"),
    ("RELL",  "",  7, "",       "{m} *+3"),
    ("SR",    "",  1, ",S",     "{m} $12,s"),
    ("SRIY",  "(", 1, ",S),Y",  "{m} ($12,s),y"),
    ("BLOCK", "",  8, "",       "{m} $12,$34"),
]
NACHSAETZE = ["", ",X", ",Y", ")", ",X)", "),Y", "]", "],Y", ",S", ",S),Y"]

# Der 65C816 Zeile fuer Zeile (WDC W65C816S, Opcode-Matrix)
KARTE = """
BRK IMM8 | ORA DPIX | COP IMM8 | ORA SR | TSB DP | ORA DP | ASL DP | ORA DPL | PHP IMP | ORA IMM_M | ASL AKKU | PHD IMP | TSB ABS | ORA ABS | ASL ABS | ORA LONG
BPL REL | ORA DPIY | ORA DPI | ORA SRIY | TRB DP | ORA DPX | ASL DPX | ORA DPLY | CLC IMP | ORA ABSY | INC AKKU | TCS IMP | TRB ABS | ORA ABSX | ASL ABSX | ORA LONGX
JSR ABS | AND DPIX | JSL LONG | AND SR | BIT DP | AND DP | ROL DP | AND DPL | PLP IMP | AND IMM_M | ROL AKKU | PLD IMP | BIT ABS | AND ABS | ROL ABS | AND LONG
BMI REL | AND DPIY | AND DPI | AND SRIY | BIT DPX | AND DPX | ROL DPX | AND DPLY | SEC IMP | AND ABSY | DEC AKKU | TSC IMP | BIT ABSX | AND ABSX | ROL ABSX | AND LONGX
RTI IMP | EOR DPIX | WDM IMM8 | EOR SR | MVP BLOCK | EOR DP | LSR DP | EOR DPL | PHA IMP | EOR IMM_M | LSR AKKU | PHK IMP | JMP ABS | EOR ABS | LSR ABS | EOR LONG
BVC REL | EOR DPIY | EOR DPI | EOR SRIY | MVN BLOCK | EOR DPX | LSR DPX | EOR DPLY | CLI IMP | EOR ABSY | PHY IMP | TCD IMP | JML LONG | EOR ABSX | LSR ABSX | EOR LONGX
RTS IMP | ADC DPIX | PER RELL | ADC SR | STZ DP | ADC DP | ROR DP | ADC DPL | PLA IMP | ADC IMM_M | ROR AKKU | RTL IMP | JMP ABSI | ADC ABS | ROR ABS | ADC LONG
BVS REL | ADC DPIY | ADC DPI | ADC SRIY | STZ DPX | ADC DPX | ROR DPX | ADC DPLY | SEI IMP | ADC ABSY | PLY IMP | TDC IMP | JMP ABSIX | ADC ABSX | ROR ABSX | ADC LONGX
BRA REL | STA DPIX | BRL RELL | STA SR | STY DP | STA DP | STX DP | STA DPL | DEY IMP | BIT IMM_M | TXA IMP | PHB IMP | STY ABS | STA ABS | STX ABS | STA LONG
BCC REL | STA DPIY | STA DPI | STA SRIY | STY DPX | STA DPX | STX DPY | STA DPLY | TYA IMP | STA ABSY | TXS IMP | TXY IMP | STZ ABS | STA ABSX | STZ ABSX | STA LONGX
LDY IMM_X | LDA DPIX | LDX IMM_X | LDA SR | LDY DP | LDA DP | LDX DP | LDA DPL | TAY IMP | LDA IMM_M | TAX IMP | PLB IMP | LDY ABS | LDA ABS | LDX ABS | LDA LONG
BCS REL | LDA DPIY | LDA DPI | LDA SRIY | LDY DPX | LDA DPX | LDX DPY | LDA DPLY | CLV IMP | LDA ABSY | TSX IMP | TYX IMP | LDY ABSX | LDA ABSX | LDX ABSY | LDA LONGX
CPY IMM_X | CMP DPIX | REP IMM8 | CMP SR | CPY DP | CMP DP | DEC DP | CMP DPL | INY IMP | CMP IMM_M | DEX IMP | WAI IMP | CPY ABS | CMP ABS | DEC ABS | CMP LONG
BNE REL | CMP DPIY | CMP DPI | CMP SRIY | PEI DPI | CMP DPX | DEC DPX | CMP DPLY | CLD IMP | CMP ABSY | PHX IMP | STP IMP | JML ABSL | CMP ABSX | DEC ABSX | CMP LONGX
CPX IMM_X | SBC DPIX | SEP IMM8 | SBC SR | CPX DP | SBC DP | INC DP | SBC DPL | INX IMP | SBC IMM_M | NOP IMP | XBA IMP | CPX ABS | SBC ABS | INC ABS | SBC LONG
BEQ REL | SBC DPIY | SBC DPI | SBC SRIY | PEA ABS | SBC DPX | INC DPX | SBC DPLY | SED IMP | SBC ABSY | PLX IMP | XCE IMP | JSR ABSIX | SBC ABSX | INC ABSX | SBC LONGX
"""


def karte():
    befehle = []
    for zeile in KARTE.strip().splitlines():
        for feld in zeile.split("|"):
            m, art = feld.split()
            befehle.append((m, art))
    assert len(befehle) == 256
    return befehle


def schreiben(befehle):
    namen = sorted({m for m, _ in befehle})
    artnr = {a[0]: i for i, a in enumerate(ARTEN)}
    z = ["; Automatisch erzeugt von tools/opcodes.py - nicht von Hand aendern",
         f"; 65C816: {len(namen)} Mnemonics, 256 Opcodes, {len(ARTEN)} Adressierungsarten", ""]
    for i, a in enumerate(ARTEN):
        z.append(f"A_{a[0]:<6}= {i}")
    z.append(f"MN_ANZAHL = {len(namen)}")
    for m in ("BRK", "COP", "WDM", "JMP", "JSR", "JML", "JSL", "REP", "SEP", "MVN", "MVP", "PER", "BRL"):
        z.append(f"MN_{m} = {namen.index(m)}")
    z += ["", "mo_mnemonics"]
    for i in range(0, len(namen), 8):
        z.append("\t.text " + ", ".join(f'"{m}"' for m in namen[i:i + 8]))
    z += ["", "mo_op_mn                        ; je Opcode: Mnemonic"]
    for i in range(0, 256, 16):
        z.append("\t.byte " + ", ".join(str(namen.index(m)) for m, _ in befehle[i:i + 16]))
    z += ["", "mo_op_art                       ; je Opcode: Adressierungsart"]
    for i in range(0, 256, 16):
        z.append("\t.byte " + ", ".join(f"A_{a}" for _, a in befehle[i:i + 16]))
    z += ["", "; je Art: Vorsatz (0 oder Zeichen), Operand (siehe opcodes.py), Nachsatz",
          "mo_arten"]
    for a in ARTEN:
        vor = f"'{a[1]}'" if a[1] else "0"
        z.append(f"\t.byte {vor}, {a[2]}, {NACHSAETZE.index(a[3])}\t; {a[0]}")
    z += ["", "mo_nachsaetze                   ; Nachsaetze, je mit 0 abgeschlossen"]
    for i, n in enumerate(NACHSAETZE):
        z.append(f'mo_ns{i}\t.text "{n}", 0' if n else f"mo_ns{i}\t.byte 0")
    z.append("mo_ns_tab")
    z.append("\t.word " + ", ".join(f"mo_ns{i}" for i in range(len(NACHSAETZE))))
    pfad = os.path.join(BASIS, "rom", "opcodes.inc")
    open(pfad, "w").write("\n".join(z) + "\n")
    print(f"rom/opcodes.inc: {len(namen)} Mnemonics")
    return namen


def pruefen(befehle):
    zeilen = ['\t.cpu "65816"', "\t.as", "\t.xs", "\t* = $1000"]
    for i, (m, art) in enumerate(befehle):
        muster = next(a[4] for a in ARTEN if a[0] == art)
        zeilen.append(f"o_{i:02x}\t" + muster.format(m=m.lower()))
    with tempfile.TemporaryDirectory() as d:
        q = os.path.join(d, "t.asm")
        open(q, "w").write("\n".join(zeilen) + "\n")
        r = subprocess.run(["64tass", "-q", "-b", "-o", os.path.join(d, "t.bin"), "-L",
                            os.path.join(d, "t.lst"), q], capture_output=True, text=True)
        if r.returncode:
            sys.exit("64tass: " + r.stdout + r.stderr)
        fehler = 0
        for z in open(os.path.join(d, "t.lst")):
            if not z.startswith(".") or "\to_" not in z:
                continue
            teile = z.split("\t")
            marke = [t for t in teile if t.startswith("o_") and len(t) >= 4]
            if not marke:
                continue
            soll = int(marke[0][2:4], 16)
            ist = int(teile[1].split()[0], 16)
            if soll != ist:
                fehler += 1
                print(f"  ${soll:02X} {befehle[soll]}: 64tass erzeugt ${ist:02X}")
        print(f"Pruefung gegen 64tass: {fehler} Abweichungen")
        return fehler == 0


if __name__ == "__main__":
    b = karte()
    schreiben(b)
    if "--pruefen" in sys.argv and not pruefen(b):
        sys.exit(1)
