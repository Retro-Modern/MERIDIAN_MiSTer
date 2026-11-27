#!/usr/bin/env python3
"""Builds RVDEMO.MER: a small RV32IM program for SCHUB that BASIC calls with
SCHUB(n[,a[,b[,c]]]) (see SCHUB.md, "SCHUB from BASIC").

    schubdemo.py [programme/rvdemo.mer]

Functions:
    0  a * b
    1  number of primes below a (trial division)
    2  fills the 40-column text screen with character a in colour b,
       returns the number of cells (1200)
    other n: -1

No RISC-V toolchain needed: the few instructions it uses are encoded here.
Loaded with BLOAD "RVDEMO" at $040000 (262144), started with SCHUB 262144.
"""
import os
import struct
import sys

LADE = 0x040000                 # load and start address
POST = 0x80FE1800               # mailbox, uncached alias of $FE:1800

REG = {n: i for i, n in enumerate(
    "zero ra sp gp tp t0 t1 t2 s0 s1 a0 a1 a2 a3 a4 a5 a6 a7 "
    "s2 s3 s4 s5 s6 s7 s8 s9 s10 s11 t3 t4 t5 t6".split())}


def _i(op, f3, rd, rs1, imm):
    assert -2048 <= imm < 2048, imm
    return (imm & 0xfff) << 20 | REG[rs1] << 15 | f3 << 12 | REG[rd] << 7 | op


def _s(f3, rs2, rs1, imm):
    assert -2048 <= imm < 2048, imm
    return ((imm >> 5) & 0x7f) << 25 | REG[rs2] << 20 | REG[rs1] << 15 | f3 << 12 | (imm & 0x1f) << 7 | 0x23


def _r(f7, f3, rd, rs1, rs2):
    return f7 << 25 | REG[rs2] << 20 | REG[rs1] << 15 | f3 << 12 | REG[rd] << 7 | 0x33


def _b(f3, rs1, rs2, off):
    assert -4096 <= off < 4096 and off % 2 == 0, off
    o = off & 0x1fff
    return ((o >> 12) & 1) << 31 | ((o >> 5) & 0x3f) << 25 | REG[rs2] << 20 | REG[rs1] << 15 \
        | f3 << 12 | ((o >> 1) & 0xf) << 8 | ((o >> 11) & 1) << 7 | 0x63


def _j(rd, off):
    o = off & 0x1fffff
    return ((o >> 20) & 1) << 31 | ((o >> 1) & 0x3ff) << 21 | ((o >> 11) & 1) << 20 \
        | ((o >> 12) & 0xff) << 12 | REG[rd] << 7 | 0x6f


def _hi_lo(wert):
    """lui/addi pair for a 32-bit constant (addi sign-extends)."""
    lo = ((wert & 0xfff) ^ 0x800) - 0x800
    return ((wert - lo) >> 12) & 0xfffff, lo


BEFEHLE = {
    "addi": lambda rd, rs, imm: _i(0x13, 0, rd, rs, imm),
    "lw":   lambda rd, rs, imm: _i(0x03, 2, rd, rs, imm),
    "sw":   lambda rs2, rs1, imm: _s(2, rs2, rs1, imm),
    "sb":   lambda rs2, rs1, imm: _s(0, rs2, rs1, imm),
    "lui":  lambda rd, imm: imm << 12 | REG[rd] << 7 | 0x37,
    "mul":  lambda rd, a, b: _r(1, 0, rd, a, b),
    "rem":  lambda rd, a, b: _r(1, 6, rd, a, b),
}
SPRUENGE = {"beq": 0, "bne": 1, "blt": 4, "bge": 5}

# (label, instruction, operands...); a branch or "j" names its target label
PROGRAMM = [
    ("start", "lui", "s0", _hi_lo(POST)[0]),
    (None, "addi", "s0", "s0", _hi_lo(POST)[1]),       # s0 = mailbox
    (None, "addi", "s1", "zero", 1),                   # s1 = 1 (request)
    ("warte", "lw", "t0", "s0", 0),                    # wait for a request
    (None, "bne", "t0", "s1", "warte"),
    (None, "lw", "a0", "s0", 4),                       # n
    (None, "lw", "a1", "s0", 8),                       # a
    (None, "lw", "a2", "s0", 12),                      # b
    (None, "lw", "a3", "s0", 16),                      # c
    (None, "beq", "a0", "zero", "f_mal"),
    (None, "beq", "a0", "s1", "f_prim"),
    (None, "addi", "t1", "zero", 2),
    (None, "beq", "a0", "t1", "f_fuell"),
    (None, "addi", "a0", "zero", -1),                  # unknown function
    (None, "j", "fertig"),

    ("f_mal", "mul", "a0", "a1", "a2"),                # 0: a * b
    (None, "j", "fertig"),

    ("f_prim", "addi", "a0", "zero", 0),               # 1: primes below a
    (None, "addi", "t2", "zero", 2),                   # t2 = candidate
    ("p_neu", "bge", "t2", "a1", "fertig"),
    (None, "addi", "t3", "zero", 2),                   # t3 = divisor
    ("p_teil", "mul", "t4", "t3", "t3"),
    (None, "blt", "t2", "t4", "p_prim"),               # divisor^2 > candidate
    (None, "rem", "t5", "t2", "t3"),
    (None, "beq", "t5", "zero", "p_weiter"),
    (None, "addi", "t3", "t3", 1),
    (None, "j", "p_teil"),
    ("p_prim", "addi", "a0", "a0", 1),
    ("p_weiter", "addi", "t2", "t2", 1),
    (None, "j", "p_neu"),

    ("f_fuell", "lui", "t0", 0x80000),                 # 2: text screen
    (None, "addi", "t0", "t0", 0x400),                 # $80000400 = $00:0400
    (None, "addi", "t1", "zero", 1200),
    ("f_zelle", "sb", "a1", "t0", 0),                  # character
    (None, "sb", "a2", "t0", 1),                       # colour
    (None, "addi", "t0", "t0", 2),
    (None, "addi", "t1", "t1", -1),
    (None, "bne", "t1", "zero", "f_zelle"),
    (None, "addi", "a0", "zero", 1200),

    ("fertig", "sw", "a0", "s0", 20),                  # result
    (None, "addi", "t0", "zero", 2),
    (None, "sw", "t0", "s0", 0),                       # done
    (None, "j", "warte"),
]


def uebersetzen():
    marken = {z[0]: 4 * i for i, z in enumerate(PROGRAMM) if z[0]}
    woerter = []
    for i, (_, bef, *ops) in enumerate(PROGRAMM):
        hier = 4 * i
        if bef in SPRUENGE:
            woerter.append(_b(SPRUENGE[bef], ops[0], ops[1], marken[ops[2]] - hier))
        elif bef == "j":
            woerter.append(_j("zero", marken[ops[0]] - hier))
        else:
            woerter.append(BEFEHLE[bef](*ops))
    return woerter


def main():
    ziel = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "..", "programme", "rvdemo.mer")
    daten = b"".join(struct.pack("<I", w) for w in uebersetzen())
    kopf = b"MER\x01" + struct.pack("<I", LADE)[:3] + b"\x00"
    kopf += struct.pack("<I", LADE)[:3] + b"\x00" + struct.pack("<I", len(daten))
    with open(ziel, "wb") as f:
        f.write(kopf + daten)
    print(f"{ziel}: {len(daten)} Bytes ab ${LADE:06X}")


if __name__ == "__main__":
    main()
