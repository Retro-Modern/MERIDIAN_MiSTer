#!/usr/bin/env python3
"""Verpackt ein Binaerprogramm ins MERIDIAN-Format MER (16 Byte Kopf).

    mer.py programm.bin programm.mer --lade 2000 [--start 2000] [--auto]

Kopf: "MER" 01 | Ladeadresse (3) | Flags (Bit 0 Autostart) |
      Startadresse (3) | 00 | Laenge (4)
"""
import argparse
import struct


def main():
    p = argparse.ArgumentParser()
    p.add_argument("ein")
    p.add_argument("aus")
    p.add_argument("--lade", required=True, help="Ladeadresse (hex)")
    p.add_argument("--start", help="Startadresse (hex), Standard = Ladeadresse")
    p.add_argument("--auto", action="store_true", help="nach dem Laden starten")
    a = p.parse_args()
    daten = open(a.ein, "rb").read()
    lade = int(a.lade, 16)
    start = int(a.start, 16) if a.start else lade
    kopf = b"MER\x01" + struct.pack("<I", lade)[:3] + bytes([1 if a.auto else 0])
    kopf += struct.pack("<I", start)[:3] + b"\x00" + struct.pack("<I", len(daten))
    open(a.aus, "wb").write(kopf + daten)
    print(f"{a.aus}: {len(daten)} Bytes ab ${lade:06X}, Start ${start:06X}"
          + (", Autostart" if a.auto else ""))


if __name__ == "__main__":
    main()
