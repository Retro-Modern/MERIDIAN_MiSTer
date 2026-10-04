#!/bin/zsh
# Baut ein MERIDIAN-Programm: programme/bauen.sh rasterbalken [ladeadresse]
# -> programme/<name>.mer (mit Autostart)
set -e
cd ${0:A:h}
NAME=${1:?Programmname fehlt}
LADE=${2:-2000}
[[ -f farben.py ]] && python3 farben.py
iconv -f UTF-8 -t ISO-8859-1 $NAME.asm > $NAME.latin1.asm
64tass --long-branch -b -q -o $NAME.bin -L $NAME.lst $NAME.latin1.asm
rm $NAME.latin1.asm
python3 ../tools/mer.py $NAME.bin $NAME.mer --lade $LADE --auto
