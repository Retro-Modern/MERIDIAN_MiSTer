#!/usr/bin/env python3
"""Robustheit: sidkern ueber alle .sid-Dateien der HVSC laufen lassen.

Je Datei einmal --info und einmal -t SEK (Startlied, SJE nach /dev/null, mit
--stat). Laeuft parallel, jede Datei hat eine Zeitgrenze. Am Ende eine
Zusammenfassung; mit -o eine Zeile je Datei (JSON) fuer weitere Auswertung.

Aufruf: robust.py [-k sidkern] [-t 5] [-j 16] [--grenze 20] [-o liste.jsonl] HVSC/C64Music
"""
import argparse
import concurrent.futures
import json
import os
import re
import subprocess
import sys
import time

STAT = re.compile(r"(\d+) Schreibzugriffe, Ende bei Zyklus (\d+).*?(- JAM)?, init (zurueck|kehrt nicht zurueck), (\d+) play-Aufrufe, ([\d.]+) s Rechenzeit")


def pruefe(kern, datei, sek, grenze):
    erg = {"datei": datei}
    t0 = time.time()
    try:
        p = subprocess.run([kern, datei, "--info"], capture_output=True, timeout=grenze)
        erg["info_rc"] = p.returncode
        if p.returncode in (0, 3):
            erg["kopf"] = json.loads(p.stdout.decode("utf-8"))
        else:
            erg["info_fehler"] = p.stderr.decode("utf-8", "replace").strip()
    except subprocess.TimeoutExpired:
        erg["info_rc"] = "zeit"
    except (ValueError, UnicodeDecodeError) as e:
        erg["info_rc"] = "json"
        erg["info_fehler"] = str(e)
    try:
        p = subprocess.run([kern, datei, "-t", str(sek), "--stat", "-o", "/dev/null"], capture_output=True, timeout=grenze)
        erg["lauf_rc"] = p.returncode
        m = STAT.search(p.stderr.decode("utf-8", "replace"))
        if m:
            erg["schreib"] = int(m.group(1))
            erg["ende"] = int(m.group(2))
            erg["jam"] = bool(m.group(3))
            erg["init_zurueck"] = m.group(4) == "zurueck"
            erg["play"] = int(m.group(5))
            erg["rechen"] = float(m.group(6))
        elif p.returncode not in (3,):
            erg["lauf_fehler"] = p.stderr.decode("utf-8", "replace").strip()[-300:]
    except subprocess.TimeoutExpired:
        erg["lauf_rc"] = "zeit"
    erg["dauer"] = time.time() - t0
    return erg


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("wurzel")
    ap.add_argument("-k", "--kern", default=os.path.join(os.path.dirname(__file__), "..", "bau", "sidkern-macos"))
    ap.add_argument("-t", type=float, default=5)
    ap.add_argument("-j", type=int, default=os.cpu_count())
    ap.add_argument("--grenze", type=float, default=20)
    ap.add_argument("-o")
    a = ap.parse_args()

    dateien = []
    for wurzel, _, namen in os.walk(a.wurzel):
        dateien += [os.path.join(wurzel, n) for n in namen if n.lower().endswith(".sid")]
    dateien.sort()
    print(f"{len(dateien)} Dateien, {a.j} parallel, je {a.t} s Lied, Zeitgrenze {a.grenze} s", flush=True)

    t0 = time.time()
    ergebnisse = []
    with concurrent.futures.ThreadPoolExecutor(a.j) as pool:
        for i, erg in enumerate(pool.map(lambda d: pruefe(a.kern, d, a.t, a.grenze), dateien)):
            ergebnisse.append(erg)
            if (i + 1) % 5000 == 0:
                print(f"  {i + 1} fertig ({time.time() - t0:.0f} s)", flush=True)
    dauer = time.time() - t0

    if a.o:
        with open(a.o, "w") as f:
            for e in ergebnisse:
                f.write(json.dumps(e, ensure_ascii=False) + "\n")

    def zaehle(bed):
        return sum(1 for e in ergebnisse if bed(e))

    print(f"fertig in {dauer:.0f} s")
    print(f"--info: rc 0: {zaehle(lambda e: e.get('info_rc') == 0)}, rc 3 (BASIC): {zaehle(lambda e: e.get('info_rc') == 3)}, "
          f"andere: {zaehle(lambda e: e.get('info_rc') not in (0, 3))}")
    print(f"-t {a.t}: rc 0: {zaehle(lambda e: e.get('lauf_rc') == 0)}, rc 3: {zaehle(lambda e: e.get('lauf_rc') == 3)}, "
          f"Zeitgrenze: {zaehle(lambda e: e.get('lauf_rc') == 'zeit')}, Absturz/Fehler: "
          f"{zaehle(lambda e: e.get('lauf_rc') not in (0, 3, 'zeit'))}")
    print(f"ohne jeden Schreibzugriff: {zaehle(lambda e: e.get('lauf_rc') == 0 and e.get('schreib') == 0)}, "
          f"JAM: {zaehle(lambda e: e.get('jam'))}, init kehrt nicht zurueck: {zaehle(lambda e: e.get('init_zurueck') is False)}")
    rech = sorted(e.get("rechen", 0) for e in ergebnisse)
    if rech:
        print(f"Rechenzeit je {a.t} s Lied: Median {rech[len(rech) // 2] * 1000:.2f} ms, 99 % {rech[int(len(rech) * 0.99)] * 1000:.1f} ms, "
              f"max {rech[-1] * 1000:.0f} ms")
    for e in ergebnisse:
        if e.get("info_rc") not in (0, 3) or e.get("lauf_rc") not in (0, 3):
            print("  !", e["datei"], e.get("info_rc"), e.get("lauf_rc"), e.get("info_fehler", ""), e.get("lauf_fehler", ""))


if __name__ == "__main__":
    sys.exit(main())
