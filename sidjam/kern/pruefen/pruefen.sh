#!/bin/bash
# sidkern pruefen. Fremde Testdaten kommen nach $ARBEIT (Vorgabe: ein
# Ordner unter /tmp), nie ins Repo.
#
#   pruefen/pruefen.sh                  CPU-Tests (Klaus Dormann), SJE/--ab, Vergleich mit libsidplayfp
#   EINZELSCHRITT=1 pruefen/pruefen.sh  dazu die SingleStepTests (laedt ca. 450 MB)
#   ROBUST=1 pruefen/pruefen.sh         dazu alle HVSC-Dateien (--info und -t 5, ca. 4 min)
#
# Braucht: clang, python3, curl, 64tass, brew-Paket libsidplayfp (Referenz).
set -e
KERN=$(cd "$(dirname "$0")/.." && pwd)
HVSC=${HVSC:-$KERN/../hvsc/C64Music}
ARBEIT=${ARBEIT:-${TMPDIR:-/tmp}/sidkern-pruefen}
mkdir -p "$ARBEIT"
cd "$KERN"

echo "== bauen"
./bauen.sh mac
clang -O2 -DSPION -Wall -o bau/einzelschritt pruefen/einzelschritt.c cpu6510.c maschine.c

echo "== Klaus Dormann: 6502 functional test und Dezimaltest (Bruce Clark, mit N/V/Z)"
K=https://raw.githubusercontent.com/Klaus2m5/6502_65C02_functional_tests/master
[ -f "$ARBEIT/6502_functional_test.bin" ] || curl -sfL -o "$ARBEIT/6502_functional_test.bin" $K/bin_files/6502_functional_test.bin
[ -f "$ARBEIT/6502_decimal_test.a65" ] || curl -sfL -o "$ARBEIT/6502_decimal_test.a65" $K/6502_decimal_test.a65
python3 -I pruefen/dezimaltest_umsetzen.py "$ARBEIT/6502_decimal_test.a65" "$ARBEIT/dezimal.asm"
64tass -q -b -o "$ARBEIT/dezimal.bin" "$ARBEIT/dezimal.asm"
bau/sidkern-macos --cputest "$ARBEIT/6502_functional_test.bin" --start 0x400 --erfolg 0x3469
bau/sidkern-macos --cputest "$ARBEIT/dezimal.bin" --laden 0x200 --start 0x200 --erfolg 0x24b --fehlerbyte 0x0b

if [ -n "$EINZELSCHRITT" ]; then
    echo "== SingleStepTests 6502 (alle Opcodes ausser JAM, Register/Speicher/Zyklen/Buszugriffe)"
    mkdir -p "$ARBEIT/sst"
    for i in $(seq 0 255); do
        o=$(printf '%02x' $i)
        case $o in 02|12|22|32|42|52|62|72|92|b2|d2|f2) continue ;; esac
        [ -f "$ARBEIT/sst/$o.txt" ] && continue
        echo "https://raw.githubusercontent.com/SingleStepTests/65x02/main/6502/v1/$o.json"
    done | xargs -P 8 -I{} sh -c 'f=$(basename {} .json); curl -sfL -o "'"$ARBEIT"'/sst/$f.json" {} && python3 -I "'"$KERN"'/pruefen/einzelschritt_wandeln.py" "'"$ARBEIT"'/sst/$f.json" > "'"$ARBEIT"'/sst/$f.txt" && rm "'"$ARBEIT"'/sst/$f.json"'
    cat "$ARBEIT"/sst/*.txt | bau/einzelschritt 5 | tail -6
fi

echo "== SJE-Format und --ab"
D=$HVSC/MUSICIANS/H/Hubbard_Rob/Commando.sid
bau/sidkern-macos "$D" -t 20 > "$ARBEIT/a.sje"
bau/sidkern-macos "$D" -t 20 --text | grep -v '^#' > "$ARBEIT/a.txt"
python3 -I pruefen/sje_lesen.py "$ARBEIT/a.sje" | grep -v '^#' | cmp - "$ARBEIT/a.txt" && echo "SJE = --text"
python3 -I pruefen/ab_pruefen.py "$D" 7.5 15
python3 -I pruefen/ab_pruefen.py "$HVSC/DEMOS/A-F/Devils_ReSIDence_3SID.sid" 7.5 15

echo "== Referenz (libsidplayfp) bauen und vergleichen"
LSP=$(brew --prefix libsidplayfp)
VER=$(brew list --versions libsidplayfp | awk '{print $2}')
if [ ! -d "$ARBEIT/libsidplayfp-$VER" ]; then
    curl -sfL -o "$ARBEIT/lsp.tar.gz" "https://github.com/libsidplayfp/libsidplayfp/releases/download/v$VER/libsidplayfp-$VER.tar.gz"
    tar xzf "$ARBEIT/lsp.tar.gz" -C "$ARBEIT"
fi
clang++ -std=c++17 -O2 -DHAVE_CXX17 -w -I"$LSP/include" -I"$ARBEIT/libsidplayfp-$VER/src" \
    -o bau/refmitschnitt pruefen/refmitschnitt.cpp "$LSP/lib/libsidplayfp.a"
python3 -I pruefen/vergleich.py -t 60 pruefen/stuecke.txt

if [ -n "$ROBUST" ]; then
    echo "== Robustheit: alle HVSC-Dateien"
    python3 -I pruefen/robust.py -t 5 -o "$ARBEIT/robust.jsonl" "$HVSC"
fi
