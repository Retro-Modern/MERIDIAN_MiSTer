#!/bin/sh
# sidton bauen (reSID, siehe resid/QUELLE.txt): macOS, Linux ARMv7 (MiSTer),
# Linux x86_64 (Server). Die Wellenform-Tabellen (*.h) erzeugt dieses Skript
# aus den .dat-Dateien von reSID, wie dessen samp2src.pl.
#   ./bauen.sh          alle drei
#   ./bauen.sh mac|arm|linux
# Ergebnisse in bau/: sidton-macos, sidton-linux-armv7, sidton-linux-x86_64
set -e
cd "$(dirname "$0")"
mkdir -p bau
for d in resid/*.dat; do
    h=${d%.dat}.h
    [ -f "$h" ] && [ "$h" -nt "$d" ] && continue
    python3 - "$d" "$h" <<'EOF'
import sys
daten = open(sys.argv[1], "rb").read()
with open(sys.argv[2], "w") as f:
    f.write("// erzeugt aus %s (reSID, Dag Lem, GPL-2 oder spaeter)\n{\n" % sys.argv[1].split("/")[-1])
    for i in range(0, len(daten), 8):
        f.write("/* 0x%03x: */ " % i + "".join(" 0x%03x," % (b << 4) for b in daten[i:i + 8]) + "\n")
    f.write("},\n")
EOF
done
QUELLEN="sidton.cpp resid/sid.cc resid/voice.cc resid/wave.cc resid/envelope.cc resid/filter.cc resid/dac.cc resid/extfilt.cc resid/pot.cc resid/version.cc"
ZIG=${ZIG:-/opt/homebrew/bin/zig}
ziel=${1:-alle}
OPT="-O2 -std=c++11 -Iresid -w -DVERSION=\"1.0-sidjam\""
if [ "$ziel" = alle ] || [ "$ziel" = mac ]; then
    clang++ $OPT -o bau/sidton-macos $QUELLEN
    echo bau/sidton-macos
fi
if [ "$ziel" = alle ] || [ "$ziel" = arm ]; then
    "$ZIG" c++ -target arm-linux-musleabihf -mcpu=cortex_a9 $OPT -static -s -o bau/sidton-linux-armv7 $QUELLEN
    echo bau/sidton-linux-armv7
fi
if [ "$ziel" = alle ] || [ "$ziel" = linux ]; then
    "$ZIG" c++ -target x86_64-linux-musl $OPT -static -s -o bau/sidton-linux-x86_64 $QUELLEN
    echo bau/sidton-linux-x86_64
fi
