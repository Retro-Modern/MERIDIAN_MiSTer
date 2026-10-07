#!/bin/zsh
# Legt die Disketten fuer den MERIDIAN an: die Vorfuehrdiskette MERIDIAN.DSK
# und zwei leere (BLANK1/BLANK2.DSK), dazu das Testmodul COUNTER.MOD.
# Das Menue des MiSTer kann keine Dateien anlegen - leere Images kommen
# deshalb von hier (oder aus tools/disk.py neu), HEADER formatiert sie neu.
#
#   tools/disketten.sh [ziel]          Standard: medien/disketten
#   tools/disketten.sh --mister        zusaetzlich nach games/MERIDIAN/ kopieren
#                                      (sichert vorher, BLANK1/2 nur, wenn sie fehlen)
set -e
cd ${0:A:h:h}
ZIEL=medien/disketten
MISTER=0
for a in "$@"; do
	if [[ $a == --mister ]]; then MISTER=1; else ZIEL=$a; fi
done
mkdir -p $ZIEL

python3 tools/disk.py neu $ZIEL/MERIDIAN.DSK --mb 8 --name MERIDIAN
python3 tools/disk.py rein $ZIEL/MERIDIAN.DSK programme/krantest.mer
python3 tools/disk.py rein $ZIEL/MERIDIAN.DSK programme/dostest.mer
python3 tools/disk.py rein $ZIEL/MERIDIAN.DSK programme/daten/zusammenspiel_logo.mer ZSLOGO.MER
python3 tools/disk.py rein $ZIEL/MERIDIAN.DSK programme/daten/zusammenspiel_klang.mer ZSKLANG.MER
python3 tools/bas.py rein programme/zusammenspiel.bas ZUSAMMEN.BAS --disk $ZIEL/MERIDIAN.DSK
python3 tools/disk.py rein $ZIEL/MERIDIAN.DSK programme/ladetest.mer
python3 tools/bas.py rein programme/starfall.bas STARFALL.BAS --disk $ZIEL/MERIDIAN.DSK
python3 tools/bas.py rein programme/regenbogen.bas REGENBOG.BAS --disk $ZIEL/MERIDIAN.DSK
python3 tools/bas.py rein programme/chat.bas CHAT.BAS --disk $ZIEL/MERIDIAN.DSK
python3 tools/bas.py rein programme/guess.bas GUESS.BAS --disk $ZIEL/MERIDIAN.DSK
programme/bauen.sh montest >/dev/null && python3 tools/disk.py rein $ZIEL/MERIDIAN.DSK programme/montest.mer
python3 tools/disk.py neu $ZIEL/BLANK1.DSK --mb 8 --name BLANK1
python3 tools/disk.py neu $ZIEL/BLANK2.DSK --mb 8 --name BLANK2
cp programme/counter.mod $ZIEL/COUNTER.MOD
python3 tools/disk.py liste $ZIEL/MERIDIAN.DSK

if (( MISTER )); then
	HOST=${MISTER_HOST:-mister}             # ssh-Name des MiSTer
	# Was auf dem MiSTer schon liegt, kann Gespeichertes enthalten:
	# vorher nach linux/meridian/sicherung/ (im Menue unsichtbar), und die
	# leeren Disketten nur hinlegen, wenn es sie dort noch nicht gibt.
	ssh -o BatchMode=yes $HOST 'cd /media/fat/games/MERIDIAN && mkdir -p /media/fat/linux/meridian/sicherung && z=$(date +%Y%m%d-%H%M) && for d in *.DSK; do [ -f "$d" ] && cp -p "$d" "/media/fat/linux/meridian/sicherung/${d%.DSK}-$z.DSK"; done; ls /media/fat/games/MERIDIAN' 2>/dev/null > /tmp/meridian_da.txt
	scp -q $ZIEL/MERIDIAN.DSK $ZIEL/COUNTER.MOD $HOST:/media/fat/games/MERIDIAN/
	for d in BLANK1.DSK BLANK2.DSK; do
		grep -qx $d /tmp/meridian_da.txt || scp -q $ZIEL/$d $HOST:/media/fat/games/MERIDIAN/
	done
	echo "auf dem MiSTer: games/MERIDIAN/ (alte Images in linux/meridian/sicherung/)"
fi
