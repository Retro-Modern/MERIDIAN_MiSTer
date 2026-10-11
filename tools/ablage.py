#!/usr/bin/env python3
"""Dateien zwischen Mac und MERIDIAN austauschen - ueber die Browser-Ablage
des Netzdienstes (Laufwerk 3, Ordner games/MERIDIAN/files, Port 816).

    ablage.py mister SPIEL.BAS bild.bmp      hochladen (ATLAS zeigt den Empfang)
    ablage.py mister --liste                 was liegt dort (mit Namen am MERIDIAN)
    ablage.py mister --holen ABEND.BAS [ziel]
    ablage.py mister --weg ALT.BAS

Statt "mister" geht jede Adresse; ein Name aus ~/.ssh/config wird
aufgeloest wie bei ssh.
"""
import argparse
import json
import os
import socket
import subprocess
import sys
import urllib.parse
import urllib.request

PORT = 816


def adresse(host):
    try:
        socket.gethostbyname(host)
        return host
    except OSError:
        pass
    try:                                    # Name aus ~/.ssh/config
        aus = subprocess.run(["ssh", "-G", host], capture_output=True, text=True, timeout=5).stdout
        for z in aus.splitlines():
            if z.startswith("hostname "):
                return z.split()[1]
    except (OSError, subprocess.SubprocessError):
        pass
    return host


def url(basis, name=""):
    return basis + ("/datei/" + urllib.parse.quote(name) if name else "")


def main():
    a = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    a.add_argument("host")
    a.add_argument("dateien", nargs="*")
    a.add_argument("--liste", action="store_true")
    a.add_argument("--holen", nargs="+", metavar=("NAME", "ZIEL"))
    a.add_argument("--weg", metavar="NAME")
    a.add_argument("--port", type=int, default=PORT)
    o = a.parse_args()
    basis = "http://%s:%d" % (adresse(o.host), o.port)
    absender = socket.gethostname().split(".")[0].replace("-", " ")[:16]
    try:
        if o.liste:
            for d in json.load(urllib.request.urlopen(basis + "/liste", timeout=10)):
                print("%-14s %10d  %s" % (d["meridian"], d["groesse"], d["name"]))
        elif o.holen:
            name = o.holen[0]
            ziel = o.holen[1] if len(o.holen) > 1 else name
            daten = urllib.request.urlopen(url(basis, name), timeout=60).read()
            open(ziel, "wb").write(daten)
            print(f"{ziel}: {len(daten)} Bytes")
        elif o.weg:
            urllib.request.urlopen(urllib.request.Request(url(basis, o.weg), method="DELETE"), timeout=10)
            print(o.weg, "geloescht")
        else:
            if not o.dateien:
                a.error("welche Dateien?")
            for p in o.dateien:
                daten = open(p, "rb").read()
                r = urllib.request.Request(url(basis, os.path.basename(p)), data=daten, method="PUT",
                                           headers={"X-Absender": absender})
                urllib.request.urlopen(r, timeout=120)
                print(f"{os.path.basename(p)}: {len(daten)} Bytes gesendet")
    except OSError as e:
        sys.exit(f"{basis}: {e}")


if __name__ == "__main__":
    main()
