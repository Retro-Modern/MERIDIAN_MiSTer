#!/bin/zsh
# Baut ein MERIDIAN-Modul: programme/modul.sh counter -> programme/counter.mod
# Die Quelle beginnt bei * = $400000 mit dem Modulkopf (siehe counter.asm).
set -e
cd ${0:A:h}
NAME=${1:?Modulname fehlt}
iconv -f UTF-8 -t ISO-8859-1 $NAME.asm > $NAME.latin1.asm
64tass --long-branch -b -q -o $NAME.mod -L $NAME.lst $NAME.latin1.asm
rm $NAME.latin1.asm
python3 ../tools/modul.py $NAME.mod
