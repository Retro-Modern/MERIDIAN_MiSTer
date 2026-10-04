#!/usr/bin/env python3
"""Erzeugt die Daten fuer LADETEST (Etappe 9b): Muster, die BOTE in den
Zusatzspeicher laden soll.

  daten/ladetest_gross.mer   256 KB ab $20:0000 (mitten im Zusatzspeicher)
  daten/ladetest_grenze.mer    8 KB ab $03:F000 (Chip-RAM bis $03:FFFF,
                               dann Zusatzspeicher ab $04:0000)

Muster: Byte i = (i ^ (i >> 8) ^ (i >> 16) ^ $3C) & $FF, je Datei mit
eigenem Startwert (gross: 0, grenze: $55), damit Verwechslungen auffallen.

    python3 programme/ladetest.py
"""
import os
import struct

HIER = os.path.dirname(os.path.abspath(__file__))


def muster(n, start):
    return bytes(((i ^ (i >> 8) ^ (i >> 16) ^ 0x3C) + start) & 0xFF for i in range(n))


def mer(lade, daten, auto=False, start_adr=0):
    kopf = b"MER\x01" + struct.pack("<I", lade)[:3] + bytes([1 if auto else 0])
    kopf += struct.pack("<I", start_adr)[:3] + b"\x00" + struct.pack("<I", len(daten))
    return kopf + daten


for name, lade, n, start in (("ladetest_gross", 0x200000, 262144, 0),
                             ("ladetest_grenze", 0x03F000, 8192, 0x55)):
    pfad = os.path.join(HIER, "daten", name + ".mer")
    with open(pfad, "wb") as f:
        f.write(mer(lade, muster(n, start)))
    print(f"{pfad}: {n} Bytes ab ${lade:06X}")
