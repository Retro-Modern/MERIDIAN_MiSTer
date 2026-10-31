#!/bin/zsh
# Bringt den Netzdienst DRAHT auf den Bastel-MiSTer und startet ihn neu
# (Etappe 12). Er liegt dann in /media/fat/linux/meridian/ (nicht in
# /media/fat/MERIDIAN: einen Ordner mit dem Namen des Cores nimmt das Menue
# als Heimatordner) und schreibt nach /tmp/draht.log. Beim Einschalten
# startet ihn /media/fat/linux/user-startup.sh (Sicherung des alten Stands:
# user-startup.sh.vor-draht); er arbeitet nur, solange der MERIDIAN-Core
# laeuft.
#
#   tools/drahtdienst.sh          kopieren und (neu) starten
#   tools/drahtdienst.sh stopp    anhalten
#   tools/drahtdienst.sh log      Protokoll zeigen
#   tools/drahtdienst.sh hvsc     HVSC fuer SID JAM (allein) auf die SD-Karte
#
# Der MiSTer ist per ssh als "mister" erreichbar (~/.ssh/config), sonst
# MISTER=root@192.168.178.20 tools/drahtdienst.sh
set -e
cd ${0:A:h}
MISTER=${MISTER:-mister}
ssh_m() { ssh -o BatchMode=yes $MISTER "$@" 2>&1 | grep -v 'post-quantum\|store now\|openssh.com/pq' || true; }
case "$1" in
	stopp) ssh_m 'kill $(cat /tmp/draht.pid) 2>/dev/null && echo angehalten' ;;
	log)   ssh_m 'tail -30 /tmp/draht.log' ;;
	hvsc)  # eine Datei: exFAT blaeht 61 000 kleine Dateien auf Gigabytes auf
		[ -f ../sidjam/hvsc/hvsc.zip ] || (cd ../sidjam/hvsc && find C64Music -name '*.sid' | zip -q -9 hvsc.zip -@)
		ssh_m 'mkdir -p /media/fat/games/MERIDIAN/HVSC'
		scp -q ../sidjam/hvsc/hvsc.zip ../sidjam/hvsc/hvsc_index.tsv.gz $MISTER:/media/fat/games/MERIDIAN/HVSC/ 2>&1 | grep -v 'post-quantum\|store now\|openssh.com/pq' || true
		ssh_m 'du -sh /media/fat/games/MERIDIAN/HVSC; ls /media/fat/games/MERIDIAN/HVSC' ;;
	*)
		ssh_m 'mkdir -p /media/fat/linux/meridian'
		# erst anhalten: laufende Programme (sidkern, sidton) lassen sich nicht ueberschreiben
		ssh_m 'kill $(cat /tmp/draht.pid) 2>/dev/null; sleep 0.5'
		scp -q draht.py ablage_seite.py radio_dienst.py radio_bild.py wetter_dienst.py nachrichten_dienst.py bild_dienst.py druck_dienst.py disk.py ../rom/zeichensatz.bin \
			../sidjam/dienst/sidjam_dienst.py ../sidjam/dienst/orgelwandler.py ../sidjam/dienst/hvsc_index.py \
			../taktstock/netz/takjam_dienst.py \
			$MISTER:/media/fat/linux/meridian/ 2>&1 | grep -v 'post-quantum\|store now\|openssh.com/pq' || true
		# SID JAM: sidkern fuer ARMv7 (sidjam/kern/bauen.sh arm), falls gebaut
		SIDKERN=${SIDKERN:-../sidjam/kern/bau/sidkern-linux-armv7}
		[ -f $SIDKERN ] && scp -q $SIDKERN $MISTER:/media/fat/linux/meridian/sidkern 2>&1 | grep -v 'post-quantum\|store now\|openssh.com/pq' || true
		# reSID fuer den Klang "Original" (sidjam/ton/bauen.sh arm)
		SIDTON=${SIDTON:-../sidjam/ton/bau/sidton-linux-armv7}
		[ -f $SIDTON ] && scp -q $SIDTON $MISTER:/media/fat/linux/meridian/sidton 2>&1 | grep -v 'post-quantum\|store now\|openssh.com/pq' || true
		# Bilder fuer PICTURES und PAINT (bildwandler/bauen.sh arm)
		BILDWANDLER=${BILDWANDLER:-../bildwandler/bau/bildwandler-linux-armv7}
		[ -f $BILDWANDLER ] && scp -q $BILDWANDLER $MISTER:/media/fat/linux/meridian/bildwandler 2>&1 | grep -v 'post-quantum\|store now\|openssh.com/pq' || true
		# (nicht per ps suchen: die Befehlszeile dieser Sitzung enthaelt selbst
		# den Namen des Dienstes)
		ssh_m 'kill $(cat /tmp/draht.pid) 2>/dev/null; sleep 0.3; cd /media/fat/linux/meridian; setsid nohup python3 -u draht.py > /tmp/draht.log 2>&1 < /dev/null & echo $! > /tmp/draht.pid; sleep 1; cat /tmp/draht.log'
		;;
esac
