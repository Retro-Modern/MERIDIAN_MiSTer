# sidkern – SID-Registerstrom aus .sid-Dateien

`sidkern` lässt die Abspielroutine eines C64-SIDs (PSID/RSID v1–v4 aus der
HVSC) auf einem nachgebauten 6510 mit C64-Umgebung laufen und schreibt jeden
Schreibzugriff auf ein SID-Register mit seinem Zyklus heraus – als SJE-Strom
(`../SCHNITTSTELLEN.md`, Abschnitte 1 und 2). Ton entsteht hier keiner; den
Strom spielen ORGEL (MERIDIAN) und der Browser (`../web`). Lizenz
GPL-3.0-or-later, eigener Code, keine Abhängigkeiten außer libc.

## Dateien

| Datei | Zweck |
|---|---|
| `sidkern.c` | Aufruf, eingebauter PSID-Treiber (init/play ohne Code im C64-Speicher), Ausgabe SJE/Text |
| `cpu6510.c` | NMOS 6510, alle 256 Opcodes, jeder Buszugriff im richtigen Takt (auch Blindzugriffe) |
| `maschine.c` | Speicher/Banking, Ersatz-KERNAL, CIA 1/2, VIC-II (Raster, Raster-IRQ, Badlines), SID-Mitschnitt, OSC3/ENV3 |
| `siddatei.c/.h` | SID-Kopf, MD5 (eigene Umsetzung), JSON-Kopf |
| `kern.h` | gemeinsame Typen, schnelle Speicherwege |
| `bauen.sh` | baut nach `bau/` (gitignoriert) |
| `pruefen/` | Prüfungen, siehe unten |

## Bauen

```
./bauen.sh          # alle drei: bau/sidkern-macos, -linux-x86_64, -linux-armv7
./bauen.sh mac      # nur macOS (clang -O2)
./bauen.sh linux    # zig cc -target x86_64-linux-musl -O2 -static
./bauen.sh arm      # zig cc -target arm-linux-musleabihf -mcpu=cortex_a9 -O2 -static (MiSTer)
```

Größe (gestrippt): macOS 120 KB, Linux x86_64 104 KB, ARMv7 136 KB, statisch.

## Aufruf

```
sidkern DATEI.sid [-s LIED] [-t SEK] [--ab SEK] [-o AUS.sje]
                  [--model 6581|8580] [--pal|--ntsc] [--text] [--info] [--stat]
sidkern --cputest DATEI.bin [--laden ADR] [--start ADR] [--erfolg ADR] [--fehlerbyte ADR]
```

- Liedzeit 0 = Aufruf von init; `-t` Ende (Vorgabe 600 s), `--ab` still vorspulen
  und mit einem Abbild aller Register (Schattenwerte, je Chip 0–24) beginnen.
- Ausgabe in 4-KB-Stücken (fwrite + fflush): ein langsamer Leser bremst
  `sidkern` über die volle Leitung. Schließt der Leser, endet `sidkern` still
  mit 0 (SIGPIPE ignoriert, EPIPE abgefangen).
- Rückgabe: 0 gut, 1 Aufruf-/Dateifehler, 2 keine SID-Datei, 3 Lied braucht
  BASIC (Kopf `basic: true`, Strom nur Ende-Marke). Hält die CPU an (JAM), endet
  der Strom dort.
- `--stat`: Zusammenfassung auf stderr (Schreibzugriffe, play-Aufrufe,
  Rechenzeit, OSC3/ENV3-Lesungen). `--spur N`: die ersten N Befehle als
  Spur auf stderr (Fehlersuche).

## Was nachgebildet ist

- 6510 mit allen undokumentierten Befehlen (SHA/SHX/SHY/TAS/ANE/LXA wie die
  SingleStepTests), NMOS-Dezimalmodus mit N/V/Z, IRQ pegel-, NMI
  flankengesteuert, Erkennung zwei Takte vor Befehlsende, CLI/SEI/PLP verzögert.
- Speicher mit Prozessorport und allen Banking-Arten; RAM mit Einschaltmuster.
  Ersatz-KERNAL: $FF48 (Register retten, BRK prüfen, JMP ($0314)), $EA31/$EA7E/
  $EA81, $FE43/$FE47/$FEBC, Sprungleiste als RTS, Reset = JAM. Als Befehl holt
  die CPU aus ROM-Lücken RTS, als Daten liest sie $EA (KERNAL) bzw. 0 (BASIC).
- CIA 1/2: Timer A/B (Einmal/Dauer, Force-Load, B zählt A), ICR mit den
  Verzögerungen des alten 6526 (Start +2/+3, IRQ einen Takt nach dem Unterlauf),
  Uhr läuft mit, Ports lesen $FF. CIA 2 löst NMI aus.
- VIC-II: Rasterzähler (PAL 312×63, NTSC 263×65), Raster-IRQ, Badlines (DEN aus
  Zeile $30, YSCROLL). Keine Sprites.
- SID: Schreibzugriffe $D400–$D7FF (gespiegelt) und zweiter/dritter SID nach
  Kopf; OSC3 (Zähler, Wellenformen, Rauschen; 6581 einen Takt verzögert), ENV3
  (ADSR mit Zählerperioden), Paddles $FF, sonst Buswert mit Verblassen.
- PSID-Treiber eingebaut: $01 nach PSID-Regel, init mit I=1 per „JSR“ auf eine
  Fangadresse (Stapelzeiger muss passen), danach CLI und Leerlauf bis zum
  nächsten Interrupt. play läuft als Interrupt (VIC Zeile 0 oder CIA 1 Timer A),
  solange $0314 noch auf $EA31 zeigt; Takte wie der Treiber von sidplayfp.
  Rasterlage, CIA-Phase und X/Y bei init wie bei sidplayfp (gleiche Ausgangslage
  macht die Vergleiche aussagekräftig).

## Prüfungen (`pruefen/pruefen.sh`)

Fremde Testdaten lädt das Skript nach `$ARBEIT` (Vorgabe `/tmp/sidkern-pruefen`).

| Prüfung | Ergebnis |
|---|---|
| Klaus Dormann, 6502 functional test | bestanden, 30 646 177 Befehle, 96 241 364 Zyklen bis $3469 (bekannter Sollwert) |
| Dezimaltest (Bruce Clark, aus derselben Sammlung, A/C und N/V/Z) | bestanden |
| SingleStepTests 6502 (`EINZELSCHRITT=1`) | 1 333 893 Fälle über alle 244 Nicht-JAM-Opcodes (undokumentierte je 10 000, dokumentierte je ~1 750), 0 Fehler in Registern, Speicher, Zyklen und jedem Buszugriff |
| SJE = `--text`, `--ab` = voller Strom ab Zeitpunkt | gleich |
| Vergleich mit libsidplayfp 3.1.1 (`refmitschnitt`), 31 Stücke × 60 s (`stuecke.txt`) | 23 exakt gleiche Folge, 8 fast (≥ 99 % gleiche Datensätze, nur Reihenfolge Digi/Musik verschoben), 0 abweichend |
| Zufallsauswahl 2000 HVSC-Stücke × 20 s | 1923 exakt (96,2 %), 64 fast, 13 abweichend (12 lesen OSC3/ENV3, 1 liest die Seite, auf der sidplayfp seinen Treiber ablegt) |
| Zeit (exakte Stücke) | bei 84 % liegt jeder Datensatz innerhalb ±2 Takten (nach Abzug des festen Versatzes), bei 98 % mindestens 90 % der Datensätze |
| Robustheit, alle 61 157 Dateien, `--info` und `-t 5` (`ROBUST=1`) | 0 Abstürze, 0 Zeitüberschreitungen; 589 BASIC-RSIDs (Rückgabe 3); 1 Stück ohne Schreibzugriff (auch in der Referenz stumm), 1 JAM (Sprite-Timing, s. u.) |
| Geschwindigkeit (M5 Max, 3 min Lied) | PSID 0,02–0,08 s (2 300–10 000× Echtzeit), Digis/RSIDs 0,17–0,53 s (340–1 000×) |
| Geschwindigkeit MiSTer (Cortex-A9, 800 MHz) | geschätzt 15–25× langsamer: PSIDs > 100×, schwerste NMI-Digis ~15× Echtzeit (nicht auf dem Gerät gemessen) |

`refmitschnitt.cpp` ist eine eigene `sidbuilder`/`sidemu`-Klasse für
libsidplayfp: sie protokolliert jedes `write()` mit der Zeit aus dem
EventScheduler. Lesen beantwortet sie wie reSIDfp (OSC3/ENV3 von SIDLite,
Paddles $FF, sonst der verblassende Buswert). Gebaut gegen die statische
Homebrew-Bibliothek; die nicht installierten Kopfdateien (`sidemu.h` usw.)
kommen aus dem Quellpaket derselben Version.

## Grenzen

- Keine Sprite-DMA: Stücke, die ihren Takt über Sprites stabilisieren, laufen
  um wenige Takte anders (in der HVSC fällt so ein Stück aus:
  `Jammer/Muddy_Racers_intro.sid` landet nach 1,5 s im JAM).
- OSC3/ENV3 sind Modelle, keine Analog-Emulation: Zufall aus OSC3 und
  Modellerkennung können vom echten Chip (und von SIDLite in der Referenz)
  abweichen; kombinierte Wellenformen sind ein UND.
- sidplayfp legt seinen Treiber in eine freie Seite des C64-Speichers (meist
  $0400); `sidkern` braucht dort nichts. Unsaubere Rips, die diese Seite lesen,
  laufen deshalb anders als in sidplayfp (z. B. `Eclipse/Farewell.sid`).
- Kein echtes BASIC/KERNAL: RSIDs mit BASIC-Teil werden nicht gespielt (Rückgabe 3),
  Aufrufe in ROM-Routinen kehren sofort zurück.
- Kein Sprite-, Lichtgriffel-, TOD-Alarm- oder Seriell-Interrupt; Ports ohne
  Tasten/Joystick.
- Interleaving von Digi-Schreibzugriffen (NMI) und Musik (IRQ) kann sich bei
  zeitkritischen RSIDs um einzelne Takte verschieben (siehe Vergleich: „fast“).
