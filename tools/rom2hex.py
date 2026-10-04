#!/usr/bin/env python3
"""kern.bin ($D000-$FFFF) -> kern.hex fuer $readmemh (16 KB ab $C000)."""
import os, sys
basis = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "rom")
daten = open(os.path.join(basis, "kern.bin"), "rb").read()
assert len(daten) == 0x3000, len(daten)
bild = bytes(0x1000) + daten
with open(os.path.join(basis, "kern.hex"), "w") as f:
    f.write("\n".join(f"{b:02x}" for b in bild) + "\n")
print(f"rom/kern.hex: {len(bild)} Bytes")
