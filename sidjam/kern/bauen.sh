#!/bin/sh
# sidkern bauen: macOS (nativ), Linux x86_64 und Linux ARMv7 (MiSTer), beide statisch.
# Aufruf: ./bauen.sh            alle drei
#         ./bauen.sh mac        nur macOS
# Ergebnisse in bau/: sidkern-macos, sidkern-linux-x86_64, sidkern-linux-armv7
set -e
cd "$(dirname "$0")"
mkdir -p bau
QUELLEN="sidkern.c cpu6510.c maschine.c siddatei.c"
WARN="-Wall -Wextra -Wno-unused-parameter"
ZIG=${ZIG:-/opt/homebrew/bin/zig}
ziel=${1:-alle}

if [ "$ziel" = alle ] || [ "$ziel" = mac ]; then
    clang -O2 $WARN -o bau/sidkern-macos $QUELLEN
    echo "bau/sidkern-macos"
fi
if [ "$ziel" = alle ] || [ "$ziel" = linux ]; then
    "$ZIG" cc -target x86_64-linux-musl -O2 -static -s $WARN -o bau/sidkern-linux-x86_64 $QUELLEN
    echo "bau/sidkern-linux-x86_64"
fi
if [ "$ziel" = alle ] || [ "$ziel" = arm ]; then
    "$ZIG" cc -target arm-linux-musleabihf -mcpu=cortex_a9 -O2 -static -s $WARN -o bau/sidkern-linux-armv7 $QUELLEN
    echo "bau/sidkern-linux-armv7"
fi
rm -f bau/*.o
