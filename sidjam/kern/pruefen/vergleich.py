#!/usr/bin/env python3
"""sidkern gegen die Referenz (libsidplayfp, refmitschnitt) vergleichen.

Je Stueck die ersten SEK Sekunden beider Stroeme holen und vergleichen:
  - Folge der (Chip, Register, Wert): gemeinsamer Anfang, Anteil gleicher
    Datensaetze (Reihenfolge egal), Stelle der ersten Abweichung
  - Zeit: auf dem gemeinsamen Anfang den Versatz Referenz - sidkern je
    Datensatz; berichtet wird, wie weit er um seinen Median streut, und wie
    gut die Abstaende von Datensatz zu Datensatz uebereinstimmen.

Die Referenz schreibt vor init einmal $D418=$0F (ihr Treiber); dieser
Datensatz wird weggelassen.

Aufruf: vergleich.py [-k sidkern] [-r refmitschnitt] [-t 60] [-j N] LISTE
        LISTE: je Zeile "Pfad [Lied] # Bemerkung" (Pfad relativ zu --hvsc)
"""
import argparse
import bisect
import concurrent.futures
import os
import statistics
import subprocess
import sys
from collections import Counter

HIER = os.path.dirname(os.path.abspath(__file__))


def lies(text, ref):
    start = 0
    ds = []
    for z in text.split("\n"):
        if not z.strip():
            continue
        if z.startswith("#"):
            if z.startswith("# start "):
                start = int(z.split()[2])
            continue
        t, chip, reg, wert = z.split()
        ds.append((int(t) - start, int(chip), int(reg, 16), int(wert, 16)))
    if ref and ds and ds[0][1:] == (0, 0x18, 0x0F) and ds[0][0] < 200:
        ds = ds[1:]
    return ds


def vergleiche(kern, refp, datei, lied, sek):
    a = subprocess.run([kern, datei, "-s", str(lied), "-t", str(sek), "--text"], capture_output=True, text=True,
                       encoding="latin-1")
    b = subprocess.run([refp, datei, str(lied), str(sek)], capture_output=True, text=True, encoding="latin-1")
    ich = lies(a.stdout, False)
    ref = lies(b.stdout, True)
    cps = 1022727 if "NTSC" in b.stdout.split("\n", 1)[0] else 985248
    erg = {"ich": len(ich), "ref": len(ref), "halt": "# halt" in b.stdout}
    sa = [x[1:] for x in ich]
    sb = [x[1:] for x in ref]
    n = 0
    m = min(len(sa), len(sb))
    while n < m and sa[n] == sb[n]:
        n += 1
    erg["praefix"] = n
    # Abweichung erst in der letzten Sekunde (Schnittkante) zaehlt als gleich
    rand = (sek - 1) * cps
    erg["exakt"] = n == m and len(sa) == len(sb) or (
        n < len(sa) and ich[n][0] >= rand or n == len(sa)) and (n < len(sb) and ref[n][0] >= rand or n == len(sb))
    erg["abweichung_s"] = None if n >= m else ich[n][0] / cps
    ca, cb = Counter(sa), Counter(sb)
    gleich = sum(min(v, cb[k]) for k, v in ca.items())
    erg["anteil"] = gleich / max(len(sa), len(sb), 1)
    # Zeit auf dem gemeinsamen Anfang
    if n > 1:
        vers = [ref[i][0] - ich[i][0] for i in range(n)]
        med = statistics.median(vers)
        abw = sorted(abs(v - med) for v in vers)
        erg["zeit_0"] = bisect.bisect_right(abw, 0) / n
        erg["zeit_2"] = bisect.bisect_right(abw, 2) / n
        erg["zeit_10"] = bisect.bisect_right(abw, 10) / n
        erg["zeit_max"] = abw[-1]
        erg["zeit_p99"] = abw[int(0.99 * (n - 1))]
        schritt = sorted(abs((ref[i][0] - ref[i - 1][0]) - (ich[i][0] - ich[i - 1][0])) for i in range(1, n))
        erg["schritt_0"] = bisect.bisect_right(schritt, 0) / len(schritt)
        erg["schritt_2"] = bisect.bisect_right(schritt, 2) / len(schritt)
    return erg


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("liste")
    ap.add_argument("-k", "--kern", default=os.path.join(HIER, "..", "bau", "sidkern-macos"))
    ap.add_argument("-r", "--ref", default=os.path.join(HIER, "..", "bau", "refmitschnitt"))
    ap.add_argument("--hvsc", default=os.path.join(HIER, "..", "..", "hvsc", "C64Music"))
    ap.add_argument("-t", type=float, default=60)
    ap.add_argument("-j", type=int, default=os.cpu_count(), help="parallel")
    a = ap.parse_args()

    zeilen = []
    for z in open(a.liste, encoding="utf-8"):
        z, _, bem = z.partition("#")
        teile = z.split()
        if teile:
            zeilen.append((teile[0], int(teile[1]) if len(teile) > 1 else 0, bem.strip()))

    def eins(zeile):
        pfad, lied, bem = zeile
        datei = os.path.join(a.hvsc, pfad)
        if not lied:
            kopf = subprocess.run([a.kern, datei, "--info"], capture_output=True, text=True).stdout
            lied = int(kopf.split('"start_song":')[1].split(",")[0])
        return pfad, lied, bem, vergleiche(a.kern, a.ref, datei, lied, a.t)

    exakt = fast = 0
    print(f"{'Stueck':52} {'Lied':>4} {'sidkern':>8} {'Ref':>8} {'gleich':>7} {'Anfang':>7} {'Zeit<=2':>8} {'Schr<=2':>8}  Befund")
    with concurrent.futures.ThreadPoolExecutor(a.j) as pool:
        for pfad, lied, bem, e in pool.map(eins, zeilen):
            if e["exakt"]:
                befund = "exakt"
                exakt += 1
            elif e["anteil"] >= 0.99:
                befund = f"fast (ab {e['abweichung_s']:.2f} s)"
                fast += 1
            else:
                befund = f"weicht ab ab {e['abweichung_s']:.2f} s" if e["abweichung_s"] is not None else "weicht ab"
            if e.get("halt"):
                befund += ", Referenz haelt an"
            zeit = f"{e['zeit_2'] * 100:7.1f}%" if "zeit_2" in e else "      -"
            schritt = f"{e['schritt_2'] * 100:7.1f}%" if "schritt_2" in e else "      -"
            print(f"{pfad[-52:]:52} {lied:4} {e['ich']:8} {e['ref']:8} {e['anteil'] * 100:6.1f}% "
                  f"{e['praefix'] / max(e['ref'], 1) * 100:6.1f}% {zeit} {schritt}  {befund}"
                  + (f"  [{bem}]" if bem else "") + (f"  max {e['zeit_max']}" if "zeit_max" in e else ""), flush=True)
    print(f"\n{len(zeilen)} Stuecke: {exakt} exakt, {fast} fast (>= 99 % gleiche Datensaetze), "
          f"{len(zeilen) - exakt - fast} weichen ab")


if __name__ == "__main__":
    sys.exit(main())
