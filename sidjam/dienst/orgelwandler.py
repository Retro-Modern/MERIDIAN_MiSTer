#!/usr/bin/env python3
"""SID -> ORGEL: Registerstrom (SJE) in Auftraege fuer den MERIDIAN umrechnen

Die ORGEL hat vier Synthesestimmen mit der Registerfolge des SID (+0..+6),
dazu Filter und Lautstaerke fast wie $D415-$D418. Was anders ist, gleicht
diese Umrechnung aus:

- Stimmen: SID-Stimme 1-3 -> ORGEL-Stimme 1-3. ORGEL-Stimme 0 bekommt eine
  stumme Kopie von SID-Stimme 3: Sync und Ring nehmen in der ORGEL die
  vorige Stimme im Ring ueber vier (Stimme 1 die 0), im SID die vorige im
  Ring ueber drei (Stimme 1 die 3).
- FREQ: ORGEL zaehlt mit 1 MHz, der SID mit dem C64-Takt -> mal cps/1e6
  (PAL 0,985, NTSC 1,023).
- Eckfrequenz: SID $15 (Bits 0-2) und $16 (Bits 3-10), ORGEL $40 (Bits 0-7)
  und $41 (Bits 8-10). Die ORGEL ist linear (~29 Hz + 6 Hz je Schritt bis
  12,3 kHz) wie ein 8580; fuer den 6581 gilt eine eigene Kurve.
- $17: Filterstimmen Bit 0-2 -> ORGEL Bit 1-3 (Stimme 0 bleibt draussen).
- $18: Modus und Lautstaerke wie im SID; Bit 7 ("3 OFF") gibt es in der
  ORGEL nicht -> Sonderauftrag $FF fuer die App (sie setzt LAUT).
- Lautstaerke-Digis ($D418 tausende Male je Sekunde): Die ORGEL hat keinen
  Gleichspannungsversatz, also hoert man sie nicht. Erkannt je Block und
  als 8-Bit-Samples ausgegeben, die die App auf einem Samplekanal spielt.

Auftraege fuer den Ring (je Datensatz): dt (16 Bit, Mikrosekunden seit dem
vorigen Datensatz), n, dann n Paare (Register, Wert). Register $00-$4F sind
ORGEL-Register ab $C500; Sonderregister: $FC Ausblenden (Wert 0-15),
$FD Ende des Stuecks, $FE Stimmen zuruecksetzen (Anfang), $FF "3 OFF".
"""

PCM_RATE = 22050
BLOCK_US = 20000                    # Bloecke zu 20 ms Liedzeit
GRUPPE_US = 400                     # Schreibzugriffe so dicht = ein Datensatz
DIGI_JE_BLOCK = 20                  # ab so vielen $D418-Zugriffen je Block (1 kHz)

S_AUSBLENDEN, S_ENDE, S_ANFANG, S_DREI_AUS = 0xFC, 0xFD, 0xFE, 0xFF

# 6581: Eckfrequenz (Hz) ueber dem 11-Bit-Wert, grob gemittelt ueber
# typische Chips (der 6581 streut stark). Zwischenwerte linear.
KURVE_6581 = [(0, 210), (256, 250), (384, 300), (512, 420), (640, 760), (768, 1500),
              (896, 3000), (1024, 4600), (1152, 7000), (1280, 9300), (1408, 11600),
              (1536, 13500), (2047, 16000)]


def ecke_6581(fc):
    for (x0, y0), (x1, y1) in zip(KURVE_6581, KURVE_6581[1:]):
        if fc <= x1:
            return y0 + (y1 - y0) * (fc - x0) / (x1 - x0)
    return KURVE_6581[-1][1]


def hz_zu_orgel(hz):
    """Eckfrequenz in Hz -> ORGEL-Wert (F = 12 + w*632/256 in Q16 bei 1 MHz)"""
    w = (hz * 6.283185307 / 1e6 * 65536 - 12) * 256 / 632
    return max(0, min(2047, int(round(w))))


class Orgelwandler:
    def __init__(self, cps, modell="6581"):
        self.cps = cps
        self.fmal = cps / 1e6
        self.modell = modell
        self.sid = [0] * 32
        self.vol = 15
        self.modus = 0
        self.drei_aus = 0
        self.tabelle = [hz_zu_orgel(ecke_6581(fc)) if modell == "6581" else
                        hz_zu_orgel(29 + fc * 5.995) for fc in range(2048)]

    def anfang(self):
        """Auftraege fuer den Anfang eines Stuecks: alle vier Oszillatoren
        per Test-Bit auf null (damit die Kopie fuer Sync/Ring im Takt ist),
        Filter aus, Lautstaerke voll"""
        a = [(S_ANFANG, 0)]
        for st in range(4):
            a.append((st * 16 + 4, 0x08))
        for st in range(4):
            for o in (0, 1, 2, 3, 5, 6):
                a.append((st * 16 + o, 0))
            a.append((st * 16 + 4, 0))
        a += [(0x40, 0), (0x41, 0), (0x42, 0), (0x43, 0x0F), (S_DREI_AUS, 0)]
        return a

    def schreiben(self, reg, wert, digi=False):
        """ein SID-Schreibzugriff (Chip 0) -> Liste von (Register, Wert)"""
        self.sid[reg] = wert
        a = []
        if reg < 21:
            st, o = divmod(reg, 7)
            ziele = [(st + 1) * 16] + ([0] if st == 2 else [])
            if o <= 1:
                f = self.sid[st * 7] | self.sid[st * 7 + 1] << 8
                f = min(0xFFFF, int(f * self.fmal + 0.5))
                for z in ziele:
                    a += [(z, f & 0xFF), (z + 1, f >> 8)]
            else:
                for z in ziele:
                    a.append((z + o, wert))
        elif reg in (21, 22):
            fc = (self.sid[22] << 3) | (self.sid[21] & 7)
            w = self.tabelle[fc]
            a += [(0x40, w & 0xFF), (0x41, w >> 8)]
        elif reg == 23:
            a.append((0x42, (wert & 0xF0) | ((wert & 7) << 1)))
        elif reg == 24:
            modus, vol, aus = wert & 0x70, wert & 0x0F, wert >> 7
            if digi:
                if modus != self.modus:
                    self.modus = modus
                    a.append((0x43, modus | self.vol))
            else:
                if modus != self.modus or vol != self.vol:
                    self.modus, self.vol = modus, vol
                    a.append((0x43, modus | vol))
            if aus != self.drei_aus:
                self.drei_aus = aus
                a.append((S_DREI_AUS, aus))
        return a


def datensaetze(schreibe, t_vorher):
    """[(t_us, reg, wert), ...] (schon umgerechnet, t aufsteigend) -> Bytes
    fuer den Ring und die Zeit des letzten Datensatzes. Zugriffe innerhalb
    von GRUPPE_US bilden einen Datensatz zur Zeit des ersten."""
    aus = bytearray()
    i = 0
    while i < len(schreibe):
        t0 = schreibe[i][0]
        j = i
        while j < len(schreibe) and schreibe[j][0] - t0 <= GRUPPE_US and j - i < 120:
            j += 1
        dt = int(round(t0 - t_vorher))
        while dt > 60000:                   # lange Pause: leere Datensaetze
            aus += bytes((60000 & 0xFF, 60000 >> 8, 0))
            dt -= 60000
            t_vorher += 60000
        dt = max(0, dt)
        aus += bytes((dt & 0xFF, dt >> 8, j - i))
        for _, r, w in schreibe[i:j]:
            aus += bytes((r, w))
        t_vorher += dt
        i = j
    return bytes(aus), t_vorher


class Digi:
    """$D418-Lautstaerke als 8-Bit-Samples (22 050 Hz), mit Hochpass gegen
    den Gleichanteil (sonst knackt es beim Ein- und Ausschalten)"""

    def __init__(self):
        self.wert = 15
        self.x1 = 0.0
        self.y1 = 0.0

    def block(self, t0, t1, aenderungen, aktiv):
        """Samples fuer [t0, t1) us; aenderungen = [(t_us, vol), ...]"""
        n0 = int(t0 * PCM_RATE / 1e6)
        n1 = int(t1 * PCM_RATE / 1e6)
        if not aktiv and abs(self.y1) < 0.5:   # still: schnell (meist so)
            if aenderungen:
                self.wert = aenderungen[-1][1]
            self.x1 = self.y1 = 0.0
            return bytes(n1 - n0)
        aus = bytearray(n1 - n0)
        k = 0
        for i in range(n1 - n0):
            t = (n0 + i) * 1e6 / PCM_RATE
            while k < len(aenderungen) and aenderungen[k][0] <= t:
                self.wert = aenderungen[k][1]
                k += 1
            x = (self.wert - 7.5) * 14.0 if aktiv else 0.0
            y = x - self.x1 + 0.995 * self.y1
            self.x1, self.y1 = x, y
            aus[i] = int(max(-127, min(127, y))) & 0xFF
        while k < len(aenderungen):
            self.wert = aenderungen[k][1]
            k += 1
        return bytes(aus)


if __name__ == "__main__":
    w = Orgelwandler(985248, "6581")
    print("A-4 (PAL 7493) ->", w.schreiben(0, 7493 & 255), w.schreiben(1, 7493 >> 8))
    print("Ecke 6581 0/1024/2047:", w.tabelle[0], w.tabelle[1024], w.tabelle[2047])
    w8 = Orgelwandler(985248, "8580")
    print("Ecke 8580 0/1024/2047:", w8.tabelle[0], w8.tabelle[1024], w8.tabelle[2047])
    b, t = datensaetze([(0, 4, 1), (100, 5, 2), (20000, 4, 0)], 0)
    print("Datensaetze:", b.hex(), t)
