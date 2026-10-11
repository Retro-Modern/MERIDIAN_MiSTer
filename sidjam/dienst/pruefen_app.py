#!/usr/bin/env python3
"""Probe des Diensts ohne MERIDIAN: eine nachgebaute App liest die Ringe
in Echtzeit wie jam.asm (Auftraege zur Mikrosekunde, Samples mit 22 050 Hz)
und prueft, ob alles sauber ankommt.

    python3 pruefen_app.py [SEKUNDEN] [PFAD [LIED]]

Meldet: Datensaetze, Auftraege je Register, zu spaet angewandte Datensaetze,
Leerlaeufe des Rings, Rechenzeit des Diensts je Sekunde Lied.
"""
import collections
import os
import sys
import time

import sidjam_dienst as sd

dauer = float(sys.argv[1]) if len(sys.argv) > 1 else 10
pfad = sys.argv[2] if len(sys.argv) > 2 else "MUSICIANS/H/Hubbard_Rob/Commando.sid"
lied = int(sys.argv[3]) if len(sys.argv) > 3 else 1

fenster = bytearray(0x10000)
jam = sd.Jam(fenster, lambda s: s.encode("latin-1", "replace"))
f = jam.f
jam.e["modus"] = "ALLEIN"
jam.e["klang"] = os.environ.get("KLANG", "ORGEL")
jam.offen = True
cpu0 = time.process_time()
jam.allein_spielen(pfad, lied)

app_lauf = None
rp = pp = 0
t0 = None
faellig = None
datensaetze = 0
regs = collections.Counter()
spaet = []
leer = 0
samples = 0
nicht_null = 0
ende_gesehen = False
vorsprung_min = 99.0
start = time.time()
while time.time() - start < dauer + 3:
    time.sleep(0.001)
    if f.b(sd.J_LAUF) != app_lauf:
        app_lauf = f.b(sd.J_LAUF)
        rp = pp = 0
        f.w16(sd.J_RRP, 0)
        f.w16(sd.J_PRP, 0)
        f.b(sd.J_APP_LAUF, app_lauf)
        f.b(sd.J_APP, sd.A_FUELLT)
        los_alt = f.b(sd.J_LOS)
        vor = 0
    zustand = f.b(sd.J_APP)
    if zustand == sd.A_FUELLT:
        n = (f.w16(sd.J_PWP) - pp) & (sd.P_GROESSE - 1)
        n = min(n, sd.VOR - vor)
        pp = (pp + n) & (sd.P_GROESSE - 1)
        vor += n
        f.w16(sd.J_PRP, pp)
        if vor >= sd.VOR:
            f.b(sd.J_APP, sd.A_BEREIT)
    elif zustand == sd.A_BEREIT and f.b(sd.J_LOS) != los_alt:
        f.b(sd.J_APP, sd.A_SPIELT)
        t0 = time.time()
        faellig = 0.0
        dt_da = False
    elif zustand == sd.A_SPIELT and t0:
        jetzt = (time.time() - t0) * 1e6
        f.w32(sd.J_ZEIT, int(jetzt))
        # Auftraege: alle faelligen anwenden (wie takte in jam.asm)
        while True:
            wp = f.w16(sd.J_RWP)
            da = (wp - rp) & (sd.R_GROESSE - 1)
            ring = lambda i: fenster[sd.R_RING + ((rp + i) & (sd.R_GROESSE - 1))]
            if da < 3:
                if t0 and jetzt > faellig + 50000 and not ende_gesehen:
                    leer += 1
                break
            dt = ring(0) | ring(1) << 8
            n = ring(2)
            if da < 3 + 2 * n:
                break
            if faellig + dt > jetzt:
                break
            faellig += dt
            spaet.append(jetzt - faellig)
            for i in range(n):
                r, w = ring(3 + 2 * i), ring(4 + 2 * i)
                regs[r] += 1
                if r == 0xFD:
                    ende_gesehen = True
            rp = (rp + 3 + 2 * n) & (sd.R_GROESSE - 1)
            f.w16(sd.J_RRP, rp)
            datensaetze += 1
        # Samples mit 22 050 Hz verbrauchen (vorgefuellte Schleife: VOR voraus)
        soll = int(jetzt / 1e6 * 22050) - samples
        n = min(soll, (f.w16(sd.J_PWP) - pp) & (sd.P_GROESSE - 1))
        for i in range(n):
            if fenster[sd.P_LINKS + ((pp + i) & (sd.P_GROESSE - 1))]:
                nicht_null += 1
        pp = (pp + n) & (sd.P_GROESSE - 1)
        f.w16(sd.J_PRP, pp)
        samples += n
        vorsprung = jam.spieler.geschrieben - jetzt / 1e6
        vorsprung_min = min(vorsprung_min, vorsprung) if jetzt > 2e6 else vorsprung_min
        if jetzt > dauer * 1e6:
            break
cpu = time.process_time() - cpu0
jam.b_stopp("")
gespielt = (time.time() - t0) if t0 else 0
print("Stueck:", bytes(fenster[sd.T_TITEL:sd.T_TITEL + 40]).split(b"\0")[0].decode("latin-1"),
      "-", bytes(fenster[sd.T_AUTOR:sd.T_AUTOR + 40]).split(b"\0")[0].decode("latin-1"))
print("gespielt %.1f s, Datensaetze %d (%.0f/s)" % (gespielt, datensaetze, datensaetze / max(gespielt, 0.1)))
print("Register:", ", ".join("%02X:%d" % kv for kv in sorted(regs.items())))
if spaet:
    spaet.sort()
    print("zu spaet: Median %.0f us, 99%% %.0f us, max %.0f us" % (
        spaet[len(spaet) // 2], spaet[int(len(spaet) * 0.99)], spaet[-1]))
print("kleinster Vorsprung des Diensts: %.2f s" % vorsprung_min)
print("Ring leer gelaufen: %d mal; Samples %d (davon nicht still %d)" % (leer, samples, nicht_null))
print("Rechenzeit Dienst+Probe: %.2f s CPU fuer %.1f s Lied (%.0f %%)" % (cpu, gespielt, 100 * cpu / max(gespielt, 0.1)))
