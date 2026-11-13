#!/usr/bin/env python3
"""Schickt Programme ueber das Netz an den MERIDIAN auf einem MiSTer und
startet sie - ohne Umweg ueber das OSD-Menue.

    senden.py 192.168.1.50 programm.mer
    senden.py 192.168.1.50 programm.bin --lade 2000 --start 2000
    senden.py 192.168.1.50 grafik.mer musik.mer programm.mer   (nacheinander)

Ziel ist die IP-Adresse oder der ssh-Name des MiSTer. Angemeldet wird als
root (Passwort ab Werk "1"); mit einem ssh-Schluessel entfaellt die Abfrage.

MER-Dateien bringen Lade- und Startadresse im Kopf mit (siehe mer.py).
Rohe Binaerdateien, etwa aus 64tass oder ca65, bekommen beides von hier:
--lade und --start in hex, Start ohne Angabe = Ladeadresse. Solche
Programme startet der MERIDIAN gleich nach dem Laden (mit --kein-start
nicht), per JSL - mit RTL geht es zurueck zu READY.

Der Weg: ssh zum MiSTer; dort schreibt ein kleines Python-Skript jede Datei
in ein Postfach im DDR3 (physisch $3E000000), zuletzt eine neue
Folgenummer. Der Chip BOTE im Core bemerkt sie, haelt die CPU an, kopiert
die Daten per DMA und startet das Programm bei gesetztem Autostart-Bit ueber
einen NMI. Laeuft auf dem MiSTer gerade ein anderer Core, schreibt das
Skript nichts.

Braucht nur Python 3 und ssh (unter Windows 10/11 eingebaut).
"""
import argparse
import base64
import struct
import subprocess
import sys

AUF_DEM_MISTER = r'''
import mmap, os, struct, sys, time
POSTFACH = 0x3E000000
try:
    core = open("/tmp/CORENAME").read().strip()
except OSError:
    core = "?"
if core != "MERIDIAN":
    print("Auf dem MiSTer laeuft der Core " + core + ", nicht MERIDIAN - nichts geschickt.")
    sys.exit(2)
roh = sys.stdin.buffer.read()
dateien = []
while roh:
    n = struct.unpack("<I", roh[:4])[0]
    dateien.append(roh[4:4 + n])
    roh = roh[4 + n:]
fd = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
for i, daten in enumerate(dateien):
    if i:
        # BOTE schaut alle 2,7 ms nach und kopiert mit gut 2 MB/s - so lange
        # warten, bevor das Postfach neu beschrieben wird
        time.sleep(0.2 + len(dateien[i - 1]) / 2000000)
    groesse = (len(daten) + 24 + 4095) & ~4095
    m = mmap.mmap(fd, groesse, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE, offset=POSTFACH)
    folge = struct.unpack("<I", m[0:4])[0]
    m[24:24 + len(daten) - 16] = daten[16:]        # Daten ab Wort 3
    m[8:24] = daten[:16]                           # MER-Kopf in Wort 1-2
    folge = (folge + 1) & 0xFFFFFFFF or 1
    m[0:4] = struct.pack("<I", folge)              # zuletzt: Folgenummer
    m.close()
    print("Folge %d: %d Bytes" % (folge, len(daten) - 16), flush=True)
os.close(fd)
'''


def mer_kopf(daten, lade, start, auto):
    """16 Byte Kopf: "MER" 01 | Lade (3) | Flags | Start (3) | 00 | Laenge (4)"""
    return (b"MER\x01" + struct.pack("<I", lade)[:3] + bytes([1 if auto else 0])
            + struct.pack("<I", start)[:3] + b"\x00" + struct.pack("<I", len(daten)))


# Das Postfach endet nach 1 MB: ab $3E100000 liegt das DRAHT-Fenster, in das
# draht.py alle 50 ms Herzschlag und Ablage-Stand schreibt. Was laenger ist,
# reichte hinein, und BOTE kopierte DRAHTs Bytes mit in den Speicher (Paket
# fuer meridian-scummvm, 13 MB: Palette und ein Skript in $14:0000 kaputt).
# Darum gehen grosse Dateien in Stuecken; nur das letzte startet.
STUECK = 0xF0000


def zerlegen(mer):
    """MER-Datei -> Liste von MER-Dateien, die einzeln ins Postfach passen"""
    daten = mer[16:]
    if len(daten) <= STUECK:
        return [mer]
    lade = struct.unpack("<I", mer[4:8])[0] & 0xFFFFFF
    aus = []
    for a in range(0, len(daten), STUECK):
        teil = daten[a:a + STUECK]
        flags = mer[7] if a + STUECK >= len(daten) else 0
        aus.append(b"MER\x01" + struct.pack("<I", lade + a)[:3] + bytes([flags])
                   + mer[8:12] + struct.pack("<I", len(teil)) + teil)
    return aus


def adresse(text):
    wert = int(text.lstrip("$"), 16)
    if not 0 <= wert <= 0xFFFFFF:
        raise argparse.ArgumentTypeError(f"{text}: Adresse ausserhalb von $000000-$FFFFFF")
    return wert


def main():
    p = argparse.ArgumentParser(description="Programme per Netz an den MERIDIAN schicken",
                                epilog=__doc__.split("\n\n")[1],
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("ziel", help="IP-Adresse oder ssh-Name des MiSTer")
    p.add_argument("dateien", nargs="+", help="MER-Dateien oder eine Binaerdatei")
    p.add_argument("--lade", type=adresse, help="Ladeadresse einer Binaerdatei (hex)")
    p.add_argument("--start", type=adresse, help="Startadresse (hex), Vorgabe: Ladeadresse")
    p.add_argument("--kein-start", action="store_true", help="Binaerdatei nur laden")
    p.add_argument("--benutzer", default="root", help="Benutzer auf dem MiSTer (Vorgabe root)")
    a = p.parse_args()

    pakete = []
    namen = []
    roh = 0
    for name in a.dateien:
        daten = open(name, "rb").read()
        if daten[:4] == b"MER\x01":
            if len(daten) < 16 or struct.unpack("<I", daten[12:16])[0] != len(daten) - 16:
                p.error(f"{name}: MER-Kopf passt nicht zur Dateilaenge")
            kopf = daten
        else:
            roh += 1
            if a.lade is None:
                p.error(f"{name} ist keine MER-Datei - dafuer braucht es --lade")
            if roh > 1:
                p.error("nur eine Binaerdatei je Aufruf (weitere als MER, siehe mer.py)")
            start = a.lade if a.start is None else a.start
            kopf = mer_kopf(daten, a.lade, start, not a.kein_start) + daten
            print(f"{name}: {len(daten)} Bytes ab ${a.lade:06X}"
                  + ("" if a.kein_start else f", Start ${start:06X}"))
        if (struct.unpack("<I", kopf[4:8])[0] & 0xFFFFFF) + len(kopf) - 16 > 0xFF0000:
            p.error(f"{name}: reicht in Bank $FF (ROM) - die beschreibt BOTE nicht")
        kurz = name.replace(chr(92), '/').split('/')[-1]
        stuecke = zerlegen(kopf)
        for i, s in enumerate(stuecke):
            pakete.append(struct.pack("<I", len(s)) + s)
            namen.append(kurz if len(stuecke) == 1 else f"{kurz} ({i + 1}/{len(stuecke)})")

    ziel = a.ziel if "@" in a.ziel else f"{a.benutzer}@{a.ziel}"
    skript = base64.b64encode(AUF_DEM_MISTER.encode()).decode()
    befehl = f"python3 -c \"import base64;exec(base64.b64decode('{skript}'))\""
    r = subprocess.run(["ssh", ziel, befehl], input=b"".join(pakete),
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    ausgabe = r.stdout.decode(errors="replace").splitlines()
    if r.returncode == 0:
        for name, zeile in zip(namen, ausgabe):
            print(f"{name}: {zeile}")
    else:
        print("\n".join(ausgabe))
    fehler = [z for z in r.stderr.decode(errors="replace").splitlines()
              if "post-quantum" not in z and "store now" not in z and "openssh.com/pq" not in z]
    if fehler:
        print("\n".join(fehler), file=sys.stderr)
    return r.returncode


if __name__ == "__main__":
    sys.exit(main())
