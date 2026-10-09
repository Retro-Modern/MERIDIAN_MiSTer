#!/usr/bin/env python3
"""Tastaturtabellen fuer das Kern-ROM: PS/2-Scancode (Satz 2) -> Zeichen.

Deutsches Layout, Zeichen in Latin-1 (wie der MERIDIAN-Zeichensatz).
Fuenf Tabellen zu je 128 Byte: normal, Umschalt, AltGr (PC), Option (Mac),
Umschalt+Option (Mac). 0 = keine Taste.

Steuercodes des Kerns: $01 Pos1, $03 Stopp, $08 Rueckschritt, $09 Tab,
$0D Return, $0E Einfuegen, $7F Entf, $1C rechts, $1D links, $1E hoch,
$1F runter.

    python3 tools/tastatur.py   -> rom/tastatur.inc, rom/tastatur_m65.inc

MEGA65-Belegung (PFORTE $C10C Bit 1, nur der MEGA65-Port): Der Wandler im
Port schickt Buchstaben und Ziffern nach Beschriftung, die uebrigen Tasten
auf festen Scancodes (meridian_m65/CORE/rtl/m65_tasten.sv). Die Listen hier
sagen nur, wo die MEGA65-Tasten etwas anderes zeigen als das deutsche Layout:
Zeichen wie auf den Tasten und in matrix_to_ascii.vhdl des MEGA65-Kerns
(Umschalt+3 = #, +7 = ', +0 = {, +: = [ ...; MEGA-Taste fuer | { } ~ Rueckstrich `),
ALT fuer die Umlaute. Je Liste Paare (Scancode, Zeichen), Ende mit 0;
Zeichen 0 = die Taste zeigt nichts.
"""
import os

ZIEL = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "rom", "tastatur.inc")

# Scancode: (normal, umschalt)
GRUND = {
    0x0E: ("^", "°"), 0x16: ("1", "!"), 0x1E: ("2", '"'), 0x26: ("3", "§"),
    0x25: ("4", "$"), 0x2E: ("5", "%"), 0x36: ("6", "&"), 0x3D: ("7", "/"),
    0x3E: ("8", "("), 0x46: ("9", ")"), 0x45: ("0", "="), 0x4E: ("ß", "?"),
    0x55: ("'", "`"),
    0x15: ("q", "Q"), 0x1D: ("w", "W"), 0x24: ("e", "E"), 0x2D: ("r", "R"),
    0x2C: ("t", "T"), 0x35: ("z", "Z"), 0x3C: ("u", "U"), 0x43: ("i", "I"),
    0x44: ("o", "O"), 0x4D: ("p", "P"), 0x54: ("ü", "Ü"), 0x5B: ("+", "*"),
    0x1C: ("a", "A"), 0x1B: ("s", "S"), 0x23: ("d", "D"), 0x2B: ("f", "F"),
    0x34: ("g", "G"), 0x33: ("h", "H"), 0x3B: ("j", "J"), 0x42: ("k", "K"),
    0x4B: ("l", "L"), 0x4C: ("ö", "Ö"), 0x52: ("ä", "Ä"), 0x5D: ("#", "'"),
    0x61: ("<", ">"), 0x1A: ("y", "Y"), 0x22: ("x", "X"), 0x21: ("c", "C"),
    0x2A: ("v", "V"), 0x32: ("b", "B"), 0x31: ("n", "N"), 0x3A: ("m", "M"),
    0x41: (",", ";"), 0x49: (".", ":"), 0x4A: ("-", "_"),
    0x29: (" ", " "), 0x0D: ("\x09", "\x09"), 0x66: ("\x08", "\x08"),
    0x5A: ("\x0d", "\x0d"), 0x76: ("\x03", "\x03"),
    # Ziffernblock (ohne Num-Lock-Logik: immer Ziffern)
    0x70: ("0", "0"), 0x69: ("1", "1"), 0x72: ("2", "2"), 0x7A: ("3", "3"),
    0x6B: ("4", "4"), 0x73: ("5", "5"), 0x74: ("6", "6"), 0x6C: ("7", "7"),
    0x75: ("8", "8"), 0x7D: ("9", "9"), 0x71: (".", "."), 0x79: ("+", "+"),
    0x7B: ("-", "-"), 0x7C: ("*", "*"),
}

# MEGA65: Abweichungen vom deutschen Layout (Scancodes aus m65_tasten.sv)
M65_NORMAL = {0x4C: ":", 0x52: ";", 0x54: "@", 0x55: "=", 0x61: "_"}   # £ gibt es im Zeichensatz nicht: #
M65_SHIFT = {0x26: "#", 0x3D: "'", 0x45: "{", 0x5B: "", 0x4A: "", 0x49: ">",
             0x41: "<", 0x4C: "[", 0x52: "]", 0x54: "", 0x55: "_", 0x5D: "",
             0x7C: "", 0x0E: "", 0x61: "`", 0x66: "\x0e"}   # Umschalt+INST/DEL = Einfuegen
M65_MEGA = {0x49: "|", 0x4C: "{", 0x41: "~", 0x52: "}", 0x61: "`"}
M65_ALT = {0x1C: "ä", 0x44: "ö", 0x3C: "ü", 0x1B: "ß"}
M65_ALTSHIFT = {0x1C: "Ä", 0x44: "Ö", 0x3C: "Ü"}
# E0-Tasten: Umschalt + / = ?, Umschalt + CRSR rechts/runter = links/hoch; MEGA + / = \
M65_E0SHIFT = {0x4A: "?", 0x74: "\x1d", 0x72: "\x1e"}
M65_E0MEGA = {0x4A: "\\"}
# Umschalt + F1/F3/F5/F7/F9/F11/F13 = F2/F4/.../F14 (Scancodes)
M65_FTASTEN = {0x05: 0x06, 0x04: 0x0C, 0x03: 0x0B, 0x83: 0x0A, 0x01: 0x09, 0x78: 0x07, 0x08: 0x10}

ALTGR_PC = {0x15: "@", 0x3D: "{", 0x3E: "[", 0x46: "]", 0x45: "}", 0x4E: "\\",
            0x5B: "~", 0x61: "|"}
OPTION_MAC = {0x4B: "@", 0x2E: "[", 0x36: "]", 0x3D: "|", 0x3E: "{", 0x46: "}",
              0x31: "~"}
OPTION_SHIFT_MAC = {0x3D: "\\"}


def tabelle(name, eintraege):
    t = [0] * 128
    for code, zeichen in eintraege.items():
        b = ord(zeichen)
        assert b < 256, zeichen
        t[code] = b
    zeilen = [f"{name}"]
    for i in range(0, 128, 16):
        zeilen.append("\t.byte " + ",".join(f"${b:02x}" for b in t[i:i + 16]))
    return "\n".join(zeilen)


def liste(name, eintraege):
    b = []
    for code, z in eintraege.items():
        w = z if isinstance(z, int) else (ord(z) if z else 0)
        assert w < 256 and code != 0, (name, code)
        b += [code, w]
    b.append(0)
    return f"{name}\n\t.byte " + ",".join(f"${x:02x}" for x in b)


def main_m65():
    teile = [
        "; Automatisch erzeugt von tools/tastatur.py - nicht von Hand aendern.",
        "; MEGA65-Belegung: Paare (Scancode, Zeichen), Ende mit 0",
        "m65_listen",
        liste("m65_l_normal", M65_NORMAL),
        liste("m65_l_shift", M65_SHIFT),
        liste("m65_l_mega", M65_MEGA),
        liste("m65_l_alt", M65_ALT),
        liste("m65_l_altshift", M65_ALTSHIFT),
        liste("m65_l_e0shift", M65_E0SHIFT),
        liste("m65_l_e0mega", M65_E0MEGA),
        liste("m65_l_ftasten", M65_FTASTEN),
    ]
    ziel = os.path.join(os.path.dirname(ZIEL), "tastatur_m65.inc")
    with open(ziel, "w", encoding="ascii") as f:
        f.write("\n".join(teile) + "\n")


def main():
    teile = [
        "; Automatisch erzeugt von tools/tastatur.py - nicht von Hand aendern.",
        tabelle("tab_normal", {c: n for c, (n, s) in GRUND.items()}),
        tabelle("tab_shift", {c: s for c, (n, s) in GRUND.items()}),
        tabelle("tab_altgr", ALTGR_PC),
        tabelle("tab_mac", OPTION_MAC),
        tabelle("tab_macshift", OPTION_SHIFT_MAC),
    ]
    with open(ZIEL, "w", encoding="ascii") as f:
        f.write("\n\n".join(teile) + "\n")
    print(f"rom/tastatur.inc: {len(GRUND)} Tasten")
    main_m65()


if __name__ == "__main__":
    main()
