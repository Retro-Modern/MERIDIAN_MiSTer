# SID JAM – Schnittstellen

Dieses Blatt hält fest, wie die Teile von SID JAM miteinander reden. Wer
einen Teil ändert, ändert hier zuerst.

```
 .sid (HVSC)          sidkern (C)            Netzdienst (MiSTer)       MERIDIAN
 ───────────► 6502 + C64-Umgebung ──SJE──► ORGEL-Abbildung ──Ring──► App JAM: IRQ schreibt ORGEL
                                      └──SJE──► Browser: SID-Klang (sid-worklet.js)
 Server (retro-modern.net): Uhr, Warteschlange, Abstimmung, Chat, HVSC, sidkern, sidplayfp (Original)
```

## 1. SJE – der Registerstrom („SID JAM Ereignisse“)

`sidkern` lässt die Abspielroutine eines SIDs laufen und schreibt jeden
Schreibzugriff auf ein SID-Register mit seinem Zeitpunkt in Taktzyklen des
C64 heraus.

```
+0   4 Bytes   "SJE1"
+4   2 Bytes   n = Länge des JSON-Kopfs (Little Endian)
+6   n Bytes   JSON-Kopf (UTF-8), siehe unten
danach Datensätze bis zum Ende:
     varint d  Zyklen seit dem vorigen Datensatz (LEB128: 7 Bit je Byte,
               niedrigste zuerst, Bit 7 = es folgt ein Byte)
     byte r    0x00-0x5F: Register. Bit 0-4 Registernummer 0-24,
                          Bit 5-6 Chip 0-2 (0 = erster SID, meist $D400)
               0x7F:      Ende des Stroms (kein Wert, kein weiteres Byte)
     byte v    geschriebener Wert (nur bei Registern)
```

Der erste Datensatz zählt ab dem Startpunkt des Stroms (Zyklus
`start_cycles` im Lied). Mit `--ab` beginnt der Strom mit einem
vollständigen Abbild aller Register (je Chip 0 bis 24 in dieser
Reihenfolge, alle mit d = 0, außer dem ersten), danach geht es normal
weiter. Doppelte Schreibzugriffe mit gleichem Wert bleiben drin
(Gate-Wechsel innerhalb eines Bildes sind wichtig). Liedzeit 0 ist der
Aufruf von init. Die Ende-Marke trägt in d den Abstand vom letzten
Datensatz bis zum Ende des Stroms (`-t` oder Halt der CPU).

JSON-Kopf:

| Feld | |
|---|---|
| `title`, `author`, `released` | aus dem SID-Kopf (Latin-1 → UTF-8) |
| `format` | `"PSID"` oder `"RSID"`, `version` 1–4 |
| `song`, `songs`, `start_song` | Lied (1-basiert), Anzahl, Startlied laut Kopf |
| `clock` | `"PAL"` oder `"NTSC"` (wie gespielt) |
| `cps` | Zyklen je Sekunde (PAL 985248, NTSC 1022727) |
| `model` | `"6581"` oder `"8580"` (wie gespielt) |
| `sids` | Liste der Basisadressen, z. B. `[54272]` oder `[54272, 54304]` |
| `speed` | `"vbi"` oder `"cia"` für das gewählte Lied |
| `load`, `init`, `play` | Adressen (play 0 = eigener Interrupt) |
| `start_cycles` | Zyklus, ab dem der Strom zählt (0 oder `--ab`) |
| `md5` | MD5 der ganzen Datei (Schlüssel in `Songlengths.md5`) |
| `basic` | true, wenn das Lied BASIC braucht (dann nicht spielbar) |

## 2. sidkern – Aufruf

```
sidkern DATEI.sid [-s LIED] [-t SEKUNDEN] [--ab SEKUNDEN] [-o AUS.sje]
                  [--model 6581|8580] [--pal|--ntsc] [--text] [--info]
```

- `-s` Lied (1-basiert, Vorgabe Startlied), `-t` Ende in Liedzeit (Vorgabe 600 s),
  `--ab` stilles Vorspulen, `-o` Datei (Vorgabe stdout), `--text` lesbare Zeilen
  statt SJE, `--info` nur den JSON-Kopf ausgeben.
- Schreibt in Stücken und wartet, wenn die Leitung voll ist – so bremst der Leser.
- `--text`: erste Zeile `# {JSON-Kopf}`, dann je Schreibzugriff
  `ZYKLUS CHIP REG WERT` (Zyklus dezimal, Register und Wert zweistellig hex),
  zum Schluss `# ende ZYKLUS`. `--stat` meldet eine Zusammenfassung auf stderr.
- Rückgabe: 0 gut (auch wenn der Leser die Leitung schließt – dann still),
  1 Aufruf- oder Dateifehler, 2 keine gültige SID-Datei, 3 Lied braucht BASIC
  (Strom nur Kopf und Ende-Marke). Hält die CPU an (JAM), endet der Strom dort
  mit der Ende-Marke (Rückgabe 0).
- Gebaut für macOS, Linux x86_64 (Server) und Linux ARMv7 (MiSTer, statisch).

## 3. Netzdienst ↔ App JAM (DRAHT-Fenster, Bank `$FD`)

Die App schickt Befehle als Text mit der Anfrage-Art 20 (Postfach wie bei
`NET`, siehe KONZEPT „DRAHT“). Der Dienst antwortet sofort und arbeitet sie in
einem eigenen Faden ab; Ergebnisse stehen danach im Fenster.

`START breite` · `STOPP` · `MODUS ALLEIN|GEMEINSAM` · `KLANG ORGEL|ORIGINAL` ·
`WEITER` · `SKIP` · `STIMME n` · `SUCHE text` · `WUNSCH n` · `SPIELE n` ·
`STERN n` · `CHAT text` · `KOPPELN` · `AUTO ZUFALL|STERNE|KOMPONIST x|JAHR x` ·
`HITPARADE` · `WUNSCHLISTE` · `C64U AN|AUS` (n: Eintrag der Liste B, 1-basiert)

**Lebenszeichen:** Der Interrupt-Haken der App zählt `$FD:0020` je Bild hoch.
Steht es 1,5 s (Reset, Absturz), hält der Dienst an. Er schreibt ohnehin nur
durch ein Tor ins Fenster (`tools/draht.py`, Klasse `Tor`), das bei `STOPP`,
Laufwerk 3, RADIO und Netz-Jam schließt und erst mit dem nächsten Befehl der
App wieder aufgeht – sonst schrieben späte Fäden in die Dateidaten von
Laufwerk 3 (`$1000–$FFFF`).

**Stand** ab `$2000` (D = schreibt der Dienst, A = schreibt die App):

| | | |
|---|---|---|
| `+$00` | D | Zustand: 0 aus, 1 lädt, 2 bereit, 3 spielt, 4 Fehler, 5 wartet |
| `+$01` | D | Zähler: Texte zum Stück geändert |
| `+$02` / `+$04` | D / A | Ring der Aufträge: Schreib- / Lesezeiger (16 Bit) |
| `+$06` / `+$08` | D / A | Sample-Ringe: Schreib- / Lesezeiger (16 Bit) |
| `+$0A` | D | Startzähler: ändert er sich, starten beide Wege im selben Augenblick |
| `+$0B` | D | Modus des Laufs: Bit 0 nur Samples (MP3), 1 gemeinsam, 2 ORGEL nur zur Anzeige (Ton aus reSID, Stimmen stumm, Lautstärke fest 15), 3 Samples fein |
| `+$0C` | A | App: 0 aus, 1 füllt vor, 2 bereit, 3 spielt, 4 Ende |
| `+$0E` / `+$0F` | D / A | Nummer des Laufs / angenommen |
| `+$10` | A | Mikrosekunden seit dem Start (32 Bit) |
| `+$14` | D | Länge in ms (32 Bit) |
| `+$18` | D | Hörer (16 Bit) |
| `+$1A` / `+$1B` / `+$25` | D | Zähler: Chat / Liste A / Liste B |
| `+$1C` | D | Verbindung: 0 allein, 1 verbunden, 2 verbindet, 3 kein Server |
| `+$1D` | D | meine Sterne für das Stück |
| `+$1E` / `+$1F` | D | Abstimmung: Restsekunden / meine Stimme |
| `+$20` / `+$21` | D | Skip: Stimmen / nötig |
| `+$22` | D | Sonder: 1 Quiz, 2 Duell, 3 Themenabend, 4 Sendeschluss |
| `+$23` / `+$24` | D | angemeldet / Zähler der Meldung |
| `+$26` / `+$28` | D | Liedzeit beim Start / Länge (Sekunden, 16 Bit) |
| `+$2A` | D | Herzschlag (alle 0,5 s, solange die App offen ist); steht er gut 3 s, schickt die App START neu |
| `+$2B` | D | Wahl: Bit 0 Original, Bit 1 gemeinsam (die App folgt ihr) |
| `+$30` / `+$40` / `+$50` | D | Name / Code zum Koppeln / Meldung (Texte mit 0) |

**Texte:** `$2100` Titel, `$2140` Komponist, `$2180` Jahr, `$21C0` Infozeile,
`$2200` STIL (160), `$22A0` Programm, `$22E0` Nächstes. **Listen:** `$2400` (A:
Abstimmung und Warteschlange bzw. Wunschliste, bis 24) und `$2900` (B: Suche
und Hitparade, bis 40): `+0` Anzahl, ab `+$10` je 48 Bytes: Art (1 Kandidat,
2 Wunsch, 3 Treffer, 4 Hitparade), Stimmen, markiert, frei, Text. **Chat**
`$3100`: `+0` Anzahl, ab `+$10` je 64 Bytes: Art (0 normal, 1 System, 2 ich,
3 Quiz, 4 DJ), Text – auf die Breite aus `START` umbrochen.

**Ring der Aufträge** `$4000–$7FFF`: je Datensatz Abstand in µs zum vorigen
(16 Bit), Anzahl n, n Paare (Register, Wert). Register `$00–$4F` = ORGEL ab
`$C500`; Sonderregister `$FC` Ausblenden (0–15), `$FD` Ende, `$FE` Anfang,
`$FF` „3 OFF“. Die App schreibt sie per Timer A (einmalig, gegen die µs-Uhr)
und hält einen Schatten für die Anzeige.

**Samples** `$8000` (links bzw. oberes Byte) und `$C000` (rechts bzw. Rest),
je 16 KB, 22 050 Hz. Fein (Bit 3): Kanal 6 spielt das obere Byte mit LAUT 63,
Kanal 7 den Rest in 1/63 mit LAUT 1, beide mittig – zusammen gut 14 Bit.

## 4. Server-API (`https://retro-modern.net/api/sidjam/`)

JSON; Fehler als `{"fehler": …}` mit HTTP-Code. Geräte schicken `X-Jam-Token`,
der Browser das Cookie `jam_sitzung`. Geschlossene Probe (`--nur`): alles außer
`/zeit`, `/anmelden*`, `/geraet/*`, `/abmelden` nur für freigegebene Namen.

| | |
|---|---|
| `GET /zeit` | `{jetzt_ms}` – Uhr abgleichen |
| `GET /stand?v=&warten=1&k=` | Long-Poll (bis 25 s): `version, jetzt_ms, hoerer, sonder, programm, laeuft, naechstes, abstimmung, warteschlange, chat, skip, ich` |
| `GET /sid?pfad=` | die SID-Datei (HVSC-Pfad oder `EIGENE/…`) |
| `GET /ereignisse?pfad=&lied=&ab=&t=&modell=` | SJE-Strom (für den Browser) |
| `GET /original?pfad=&lied=&ab=&modell=` | MP3 (sidplayfp/reSIDfp, 96 kbit/s CBR, mono) ab der Stelle |
| `GET /jingle/NAME.mp3` | Jingle |
| `/tak/…` | TAKTSTOCK Netz-Jam (`taktstock/netz/takjam_server.py`, Blatt `taktstock/netz/NETZJAM.md`) |
| `GET /suche?q=` · `/hitparade` · `/zufall` | Treffer · Hitparade (7 Tage) · ein Stück |
| `GET /anmelden[?sprache=en]` | zum Forum (Discourse User-API-Key, nur `session_info`), zurück mit Cookie |
| `POST /geraet/neu` | `{token, code, name}` für einen MERIDIAN. Schickt das Gerät eine Kennung mit, die vom Server stammt (gekoppelt oder mit offenem Code), bleibt es bei ihr: Jeder noch gültige Code (15 min) koppelt dann dieselbe Kennung, `name` ist die bestehende Kopplung |
| `POST /geraet/koppeln {code}` | (angemeldet) Gerät mit dem eigenen Forumsnamen verbinden |
| `POST /chat {text}` | `/`-Befehle: `/help`; Admins `/quiz [n]`, `/theme Name = autor:x jahr:y` \| `off`, `/dj name` \| `off`, `/duel` (6581 gegen 8580) oder `/duel pfadA \| pfadB`, `/skip`, `/delete nr`, `/clear` (Chat leeren: Startmarke, die Zeilen bleiben bis zur Frist), `/mute name`, `/unmute name`, `/sendeschluss`; DJ: `/play suche` |
| `POST /stimme {nr}` · `/skip` · `/wunsch {pfad,lied}` · `/stern {pfad,lied,sterne}` · `/abmelden` | |

**TAKTSTOCK-Songs** (Art `musik`): `EIGENE/NAME.mp3` (CBR, ohne Tags) mit
`NAME.json` (`titel`, `autor`, `jahr`, `laenge`, `kbit`), gemacht mit
`taktstock/netz/sidjam_musik.py`. Sie stehen im Stand mit `art: "musik"`,
gespielt werden sie über `/original?pfad=EIGENE/NAME.mp3&ab=` (Sprung per
Bytes) – im Browser wie das Original, im Netzdienst wie ein Jingle, aber
ab der Liedzeit. Der Server liest `EIGENE/` von selbst neu ein, sobald der
Ordner 2 s ruht. Admin: `/submissions`, `/approve n` (eingereichte Songs
aus dem Netz-Jam).
