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
	*)
		ssh_m 'mkdir -p /media/fat/linux/meridian'
		scp -q draht.py disk.py $MISTER:/media/fat/linux/meridian/ 2>&1 | grep -v 'post-quantum\|store now\|openssh.com/pq' || true
		# (nicht per ps suchen: die Befehlszeile dieser Sitzung enthaelt selbst
		# den Namen des Dienstes)
		ssh_m 'kill $(cat /tmp/draht.pid) 2>/dev/null; sleep 0.3; cd /media/fat/linux/meridian; setsid nohup python3 -u draht.py > /tmp/draht.log 2>&1 < /dev/null & echo $! > /tmp/draht.pid; sleep 1; cat /tmp/draht.log'
		;;
esac
