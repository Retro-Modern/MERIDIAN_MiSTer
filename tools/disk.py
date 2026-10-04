#!/usr/bin/env python3
"""MERIDIAN-Disketten und -Platten am Mac: Images mit FAT16 (ohne
Partitionstabelle, wie eine grosse Diskette) anlegen und Dateien hinein-
und herauskopieren. macOS kann die Images auch selbst einhaengen:
    hdiutil attach -imagekey diskimage-class=CRawDiskImage SPIELE.DSK

    disk.py neu SPIELE.DSK [--mb 8] [--name SPIELE]
    disk.py liste SPIELE.DSK
    disk.py rein SPIELE.DSK datei.mer [ZIELNAME.MER]
    disk.py raus SPIELE.DSK NAME.BAS [ziel]
    disk.py weg SPIELE.DSK NAME.BAS

Nur das Hauptverzeichnis, Namen 8.3 in Grossbuchstaben - so, wie der
MERIDIAN sie liest und schreibt.
"""
import argparse
import os
import struct
import sys
import time

SEKTOR = 512
ROOT_EINTRAEGE = 512


class Fat16:
    def __init__(self, pfad):
        self.pfad = pfad
        self.d = bytearray(open(pfad, "rb").read())
        bs = self.d[:SEKTOR]
        if bs[510:512] != b"\x55\xaa":
            sys.exit(f"{pfad}: kein Bootsektor (nicht formatiert?)")
        (self.bps, self.spc, self.res, self.nfat, self.nroot, ts16, _media,
         self.spf) = struct.unpack_from("<HBHBHHBH", bs, 11)
        ts32 = struct.unpack_from("<I", bs, 32)[0]
        self.sektoren = ts16 or ts32
        if self.bps != SEKTOR:
            sys.exit("nur 512 Byte je Sektor")
        self.fat_start = self.res
        self.root_start = self.res + self.nfat * self.spf
        self.root_sek = self.nroot * 32 // SEKTOR
        self.daten_start = self.root_start + self.root_sek
        self.cluster = (self.sektoren - self.daten_start) // self.spc

    def speichern(self):
        open(self.pfad, "wb").write(self.d)

    # FAT
    def fat(self, c):
        return struct.unpack_from("<H", self.d, self.fat_start * SEKTOR + 2 * c)[0]

    def fat_setzen(self, c, w):
        for i in range(self.nfat):
            struct.pack_into("<H", self.d, (self.fat_start + i * self.spf) * SEKTOR + 2 * c, w)

    def kette(self, c):
        while 2 <= c < 0xFFF8:
            yield c
            c = self.fat(c)

    def cluster_adr(self, c):
        return (self.daten_start + (c - 2) * self.spc) * SEKTOR

    # Verzeichnis
    def eintraege(self):
        for i in range(self.nroot):
            p = self.root_start * SEKTOR + 32 * i
            yield i, p, self.d[p:p + 32]

    @staticmethod
    def name83(name):
        name = name.upper()
        n, _, e = name.partition(".")
        if not n or len(n) > 8 or len(e) > 3:
            sys.exit(f"Name nicht 8.3: {name}")
        return (n.ljust(8) + e.ljust(3)).encode("ascii")

    @staticmethod
    def lesbar(roh):
        n, e = roh[:8].decode("latin-1").rstrip(), roh[8:11].decode("latin-1").rstrip()
        return n + ("." + e if e else "")

    def finden(self, name):
        roh = self.name83(name)
        for i, p, e in self.eintraege():
            if e[0] == 0:
                break
            if e[0] != 0xE5 and e[11] & 0x18 == 0 and e[:11] == roh:
                return p
        return None

    def liste(self):
        dateien = []
        for i, p, e in self.eintraege():
            if e[0] == 0:
                break
            if e[0] == 0xE5 or e[11] == 0x0F or e[11] & 0x08:
                continue
            dateien.append((self.lesbar(e[:11]), struct.unpack_from("<I", e, 28)[0]))
        frei = sum(1 for c in range(2, self.cluster + 2) if self.fat(c) == 0)
        return dateien, frei * self.spc * SEKTOR

    def lesen(self, name):
        p = self.finden(name)
        if p is None:
            sys.exit(f"nicht gefunden: {name}")
        start, groesse = struct.unpack_from("<H", self.d, p + 26)[0], struct.unpack_from("<I", self.d, p + 28)[0]
        aus = bytearray()
        for c in self.kette(start):
            a = self.cluster_adr(c)
            aus += self.d[a:a + self.spc * SEKTOR]
        return bytes(aus[:groesse])

    def loeschen(self, name):
        p = self.finden(name)
        if p is None:
            return False
        start = struct.unpack_from("<H", self.d, p + 26)[0]
        for c in list(self.kette(start)):
            self.fat_setzen(c, 0)
        self.d[p] = 0xE5
        return True

    def schreiben(self, name, daten):
        self.loeschen(name)
        groesse_c = self.spc * SEKTOR
        noetig = (len(daten) + groesse_c - 1) // groesse_c
        frei = [c for c in range(2, self.cluster + 2) if self.fat(c) == 0][:noetig]
        if len(frei) < noetig:
            sys.exit("Diskette voll")
        for i, c in enumerate(frei):
            self.fat_setzen(c, frei[i + 1] if i + 1 < len(frei) else 0xFFFF)
            a = self.cluster_adr(c)
            stueck = daten[i * groesse_c:(i + 1) * groesse_c]
            self.d[a:a + groesse_c] = stueck.ljust(groesse_c, b"\x00")
        for i, p, e in self.eintraege():
            if e[0] in (0, 0xE5):
                t = time.localtime()
                zeit = (t.tm_hour << 11) | (t.tm_min << 5) | (t.tm_sec // 2)
                datum = ((t.tm_year - 1980) << 9) | (t.tm_mon << 5) | t.tm_mday
                eintrag = self.name83(name) + bytes([0x20]) + bytes(10)
                eintrag += struct.pack("<HHHI", zeit, datum, frei[0] if frei else 0, len(daten))
                self.d[p:p + 32] = eintrag
                return
        sys.exit("Verzeichnis voll")


def formatieren(pfad, mb, name):
    sektoren = mb * 1024 * 1024 // SEKTOR
    root_sek = ROOT_EINTRAEGE * 32 // SEKTOR
    spc = 1
    while True:
        spf = 1
        while True:                                 # Groesse der FAT einpendeln
            cluster = (sektoren - 1 - root_sek - 2 * spf) // spc
            neu = ((cluster + 2) * 2 + SEKTOR - 1) // SEKTOR
            if neu <= spf:
                break
            spf = neu
        if cluster <= 65524:
            break
        spc *= 2
    if cluster < 4085:
        sys.exit("zu klein fuer FAT16 (mindestens 3 MB)")
    d = bytearray(sektoren * SEKTOR)
    bs = bytearray(SEKTOR)
    bs[0:3] = b"\xeb\x3c\x90"
    bs[3:11] = b"MERIDIAN"
    struct.pack_into("<HBHBHHBHHHII", bs, 11, SEKTOR, spc, 1, 2, ROOT_EINTRAEGE,
                     sektoren if sektoren < 65536 else 0, 0xF8, spf, 32, 64, 0,
                     sektoren if sektoren >= 65536 else 0)
    bs[36] = 0x80
    bs[38] = 0x29
    struct.pack_into("<I", bs, 39, int(time.time()) & 0xFFFFFFFF)
    bs[43:54] = name.upper()[:11].ljust(11).encode("ascii")
    bs[54:62] = b"FAT16   "
    bs[510:512] = b"\x55\xaa"
    d[0:SEKTOR] = bs
    for i in range(2):
        f = (1 + i * spf) * SEKTOR
        d[f:f + 4] = b"\xf8\xff\xff\xff"
    r = (1 + 2 * spf) * SEKTOR
    d[r:r + 11] = name.upper()[:11].ljust(11).encode("ascii")
    d[r + 11] = 0x08                                # Datentraegername
    open(pfad, "wb").write(d)
    print(f"{pfad}: {mb} MB, FAT16, {cluster} Cluster zu {spc * SEKTOR} Byte, Name {name.upper()}")


def main():
    a = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    u = a.add_subparsers(dest="befehl", required=True)
    b = u.add_parser("neu"); b.add_argument("image"); b.add_argument("--mb", type=int, default=8); b.add_argument("--name", default="MERIDIAN")
    b = u.add_parser("liste"); b.add_argument("image")
    b = u.add_parser("rein"); b.add_argument("image"); b.add_argument("quelle"); b.add_argument("ziel", nargs="?")
    b = u.add_parser("raus"); b.add_argument("image"); b.add_argument("name"); b.add_argument("ziel", nargs="?")
    b = u.add_parser("weg"); b.add_argument("image"); b.add_argument("name")
    o = a.parse_args()
    if o.befehl == "neu":
        formatieren(o.image, o.mb, o.name)
        return
    fs = Fat16(o.image)
    if o.befehl == "liste":
        dateien, frei = fs.liste()
        for n, g in dateien:
            print(f"  {n:<12} {g:>9}")
        print(f"{len(dateien)} Dateien, {frei} Bytes frei")
    elif o.befehl == "rein":
        ziel = o.ziel or os.path.basename(o.quelle)
        fs.schreiben(ziel, open(o.quelle, "rb").read())
        fs.speichern()
        print(f"{ziel.upper()} geschrieben")
    elif o.befehl == "raus":
        open(o.ziel or o.name, "wb").write(fs.lesen(o.name))
    elif o.befehl == "weg":
        print("geloescht" if fs.loeschen(o.name) else "nicht gefunden")
        fs.speichern()


if __name__ == "__main__":
    main()
