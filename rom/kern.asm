;============================================================================
;  MERIDIAN 816 - KERN-ROM, auf dem Bildschirm "OS 1.0" (seit Etappe 10;
;  alle Texte auf dem Bildschirm englisch, die Quelle bleibt deutsch)
;
;  Start, Bildschirmausgabe, Tastaturtreiber (deutsches Layout, PC oder
;  Mac), Bildschirmeditor nach C64-Art, Maschinensprache-Monitor,
;  Interrupt-Haken fuer Programme, Fernstart ueber BOTE, Startklang und
;  Klingel auf ORGEL; Copper LOTSE und Blitter KRAN werden bei jedem Start
;  angehalten. Nach dem Einschalten startet MERIDIAN BASIC (Microsoft BASIC
;  1.1, aus dem BASIC-ROM in Bank $FF nach $9800 kopiert, laeuft im
;  Emulationsmodus); Bruecken dafuer ab $FFA0.
;
;  Konvention: Indexregister immer 16 Bit, Akku meist 8 Bit, direkte
;  Seite $0000, Datenbank 0. Alle Einsprungpunkte erwarten Akku 8 Bit.
;  Assemblieren: rom/bauen.sh
;============================================================================

	.cpu "65816"

; Texte mit Umlauten: rom/bauen.sh wandelt diese Datei vor dem Assemblieren
; nach Latin-1, so landen Ä Ö Ü ä ö ü ß direkt mit ihren MERIDIAN-Codes im ROM.

akku8	.macro
	sep #$20
	.as
	.endm

akku16	.macro
	rep #$20
	.al
	.endm

; PINSEL (Grafik)
PIN_A_TYP  = $C000
PIN_A_OPT  = $C001
PIN_SCR    = $C002              ; Ebene A: Daten
PIN_CHR    = $C005              ; Ebene A: Muster
PIN_A_SX   = $C010
PIN_A_SY   = $C012
PIN_B_TYP  = $C020
PIN_B_OPT  = $C021
PIN_B_DATEN = $C022
KOB_STEUER = $C403              ; KOBOLD: Sprites an/aus
PIN_PIDX   = $C008
PIN_PLO    = $C009
PIN_PHI    = $C00A
PIN_IRQEN  = $C00B
PIN_IRQST  = $C00C
PIN_TUSCHE = $C034              ; MERIDIAN 1.0: Kontur/Schatten, Tinte, Versatz X/Y
PIN_GLANZ  = $C040              ; Glanz: NR, Kanal $41-$4C, AN $4D/$4E
PIN_GL_AN  = $C04D
PIN_LM_IDX = $C050              ; Leuchten: Maske (Index, Daten), Staerke
PIN_LEUCHT = $C052

; PFORTE (Ein-/Ausgabe)
PFO_TASTE  = $C100
PFO_INFO   = $C101
PFO_WEITER = $C102
PFO_IRQST  = $C104
PFO_IRQEN  = $C105
PFO_LAYOUT = $C10C
PFO_TASTEU = $C116              ; Timer A Steuerung
PFO_TBSTEU = $C11A

; BOTE (Programmlader)
BOT_STATUS = $C200
MODUL      = $400000            ; Modul (ROM-Abbild, Etappe 10)
BOT_LADE   = $C201
BOT_START  = $C204
BOT_LAENGE = $C208
BOT_QUELLE = $C20B

; ORGEL (Klang)
ORG        = $C500              ; Stimme n ab ORG + n*$10
MUSIK      = $FF4003            ; ROM Bank $FF: A = 0 PLAY starten, 1 alles still
MUSIK_TAKT = $FF4006            ;   einmal je Bild aus dem Interrupt
NETZ       = $FF4009            ; ROM Bank $FF: NET (Etappe 12), A = Teilbefehl
MON_BEFEHL = $FF400C            ; Monitor (Etappe 13): Zeile in EINGABE ausfuehren
MON_HALT   = $FF400F            ;   nach BRK/Einzelschritt (Register auf dem Stapel)
MON_ANFANG = $FF4012            ;   Abzug der Register beim Einschalten
SONG_BEFEHL = $FF8000           ; ROM Bank $FF (MERIDIAN 1.0): A = 0 Song laden
SONG_TAKT  = $FF8004            ;   und spielen, 1 anhalten; Takt bei Timer A;
SONG_FUNKTION = $FF8008         ;   SONG(n)
SONG_AN    = $02E0              ; 1: ein Song laeuft (SONG im ROM setzt ihn)
WERKSTATT  = $FFC000            ; ROM Bank $FF (MERIDIAN 1.0): A = Reiter 0-5
WS_SICHERN = $FFC004            ;   SAVE: Programm + Daten der Werkstatt
WS_LADEN   = $FFC008            ;   LOAD: aus WS_PUFFER verteilen
WS_PUFFER  = $FB0000            ;   Puffer fuer LOAD/SAVE (bis $FC:FFFF)
WS_BASIC   = $FFC00C            ;   A = 0 MAP, 1 TILE, 2 TILE(), 3 Direktmodus, 4 Kaltstart
KA_ZUSTAND = $F84300            ;   BASIC MAP: welche Karte gerade zu sehen ist
SFX_AN     = $02F4              ;   SFX: Bit v = Stimme v spielt einen Klang ($02F5-$02FF Abspieler)
KART_MUSTER = $F80000           ; Werkstatt: Kopie der 128 Spritemuster (KOBOLD
                                ; ist nicht lesbar; PATTERN schreibt mit)
ORG_FILTER = $C540
ORG_KANAL  = $C580              ; Samplekanal k ab ORG_KANAL + k*$10
ORG_ECHO   = $C550              ; Echo: Zeit (2), Rueckkopplung, Anteil, Bank
ORG_FX     = $C5C0              ; Effekte der Samplekanaele 0-3 (4-7: +$700)
ORG_KANAL2 = $CC80              ; Samplekanaele 4-7 (Etappe 17)

; KRAN (Blitter) und LOTSE (Copper)
KRAN_REG   = $C600
SYS_STEUER = $C800              ; SYSTEM: Bit 0 SPIEGEL (Bank 1 $0000-$1FFF = Bank 0)
KRAN_BEF   = $C610
KRAN_STEU  = $C614
LOT_STEUER = $C703
LOT_STATUS = $C704

; BASIC (Symbole aus basic/bauen.sh)
	.include "basic_sym.inc"

; Interrupt-Haken: Adresse einer Routine in Bank 0, aufgerufen bei jedem
; Interrupt mit A (8 Bit) = PINSEL-IRQ-Status, X/Y 16 Bit. Sie muss ihre
; Interruptquellen selbst quittieren und mit RTS enden.
BENUTZER_IRQ = $0300

BILDSCHIRM = $0400              ; bis $16BF bei 80 Zeichen
ZEICHEN    = $1800
ZEILEN     = 30

; Direkte Seite
cur_x      = $10
cur_y      = $11
farbe      = $12                ; Hintergrund * 16 + Vordergrund
blink      = $13
blinkon    = $14
spalten    = $15                ; 40 oder 80
zeiger     = $16                ; 3 Byte
zahl       = $1A                ; 16 Bit
ziff       = $1C                ; 16 Bit
hilf       = $1E                ; 16 Bit
baenke     = $20                ; 16 Bit
umsch      = $22                ; Bit 0 Umschalt, 1 Strg, 2 Alt/AltGr
tb_rd      = $23
tb_wr      = $24
wdh        = $25                ; Taste fuer die Wiederholung
wdh_z      = $26
ev_info    = $27
ev_code    = $28
blink_frei = $29                ; Cursor blinkt nur beim Warten auf Eingabe (Etappe 11)
ein_pos    = $2A                ; 16 Bit
arg1       = $2C                ; 3 Byte
arg2       = $30                ; 3 Byte
arg3       = $34                ; 3 Byte
zbytes     = $38                ; 16 Bit: Bytes pro Bildschirmzeile
anzahl     = $3A                ; 16 Bit
tmp        = $3C                ; 16 Bit
sprung     = $3E                ; 3 Byte
wert       = $42                ; 3 Byte
spalt16    = $46                ; 16 Bit: Spalten
bpz        = $48                ; 16 Bit: Bytes pro Monitorzeile (8/16)
ende_ofs   = $4A                ; 16 Bit
zz         = $4C                ; Zeichenzaehler fuer Z
irq_pin    = $4E                ; PINSEL-IRQ-Status im Interrupt
irq_pfo    = $4F                ; PFORTE-IRQ-Status im Interrupt
bilder     = $50                ; 3 Byte: Bildzaehler
klang_zeit = $53                ; Bilder, bis der Kern seine Toene loslaesst
klang_maske = $54               ; welche Stimmen der Kern angeschlagen hat
; unter $10 (BASIC beginnt erst bei $55, seine Ergaenzungen nutzen $00-$04)
ein_x      = $0A                ; Zeileneingabe fuer BASIC: Startspalte,
ein_y      = $0B                ;   Startzeile,
basic_da   = $0C                ; BASIC eingerichtet (warm startbar)
ein_s      = $0D                ;   erste gelesene Spalte,
ein_q      = $0E                ;   in Anfuehrungszeichen?,
ein_n      = $0F                ;   Zeichen noch zu lesen
ein_a      = $08                ;   erste und
ein_e      = $09                ;   letzte Bildschirmzeile der logischen Zeile
ein_modus  = $0387              ;   0: Grossbuchstaben (Befehle), sonst wie getippt (INPUT)
DOS_LAEUFT = $0388              ; MERIDIAN 1.0: das DOS arbeitet (setzt es selbst)
START_WARTET = $0389            ;   ein Fernstart kam waehrenddessen und wartet

TPUFFER    = $0200              ; 16 Tasten
EINGABE    = $0210              ; 81 Byte
KOPIER     = $0270              ; MVN/MVP-Stummel
VERBUND    = $0290              ; 32 Byte: Zeile setzt die vorige fort (logische Zeilen)

STANDARD   = $6E                ; hellblau auf blau
TITEL      = $67                ; gelb auf blau

;============================================================================

	* = $D000
zeichensatz
	.binary "zeichensatz.bin"

palette                         ; MERIDIAN-16: gggg bbbb, ---- rrrr
	.byte $00,$0, $ff,$f, $33,$d, $dd,$5, $4d,$a, $c4,$4, $38,$2, $e5,$f
	.byte $92,$f, $52,$9, $88,$f, $44,$4, $88,$8, $f9,$9, $bf,$8, $cc,$c
	.include "farben.inc"           ; 16-255 (tools/farben.py)

	.include "tastatur.inc"

;============================================================================
; Kaltstart

start
	sei
	clc
	xce                         ; nativer Modus
	rep #$38
	.al
	.xl
	ldx #$01ff
	txs
	lda #$0000
	tcd
	#akku8
	lda #0
	pha
	plb
	stz SYS_STEUER              ; Spiegel aus
	stz SONG_AN                 ; kein Song (der Timer ist nach dem Reset aus)
	stz DOS_LAEUFT              ; kein DOS-Aufruf, kein wartender Fernstart
	stz START_WARTET
	lda #1                      ; Laufwerk 1, wenn keins angegeben ist
	sta STD_LW
	jsl MON_ANFANG              ; Register-Abzug des Monitors (Etappe 13)
	#akku16                     ; keine Taste gedrueckt (KEY)
	ldx #254
-	lda #0
	sta @l TASTEN_AN,x
	dex
	dex
	bpl -
	#akku8
	jsr treffer_leeren

	#akku16                     ; Zeichensatz mit einem Befehl ins RAM
	lda #2048-1
	ldx #zeichensatz
	ldy #ZEICHEN
	mvn #0,#0
	#akku8

	lda #40
	sta spalten
	jsr anzeige_zuruecksetzen

	#akku16
	lda #irq_standard
	sta BENUTZER_IRQ
	stz bilder
	#akku8
	stz bilder+2
	stz tb_rd
	stz tb_wr
	stz umsch
	stz wdh
	stz blink
	stz blinkon
	stz blink_frei
	lda #STANDARD
	sta farbe
	lda #40
	jsr modus_setzen

	jsr ram_zaehlen
	lda #4                      ; Werkstatt: Cartridge, Kacheln und Karten leeren
	jsl WS_BASIC                ; (erst jetzt: ohne Zusatzspeicher nichts)

	lda #TITEL
	sta farbe
	ldx #meldung1
	jsr print
	jsr farbbalken
	lda #STANDARD
	sta farbe
	ldx #meldung2
	jsr print
	#akku16
	lda baenke
	cmp #16                     ; ab 1 MB in MB anzeigen (aufgerundet:
	bcc +                       ; Bank $FF ist das BASIC-ROM)
	clc
	adc #15
	lsr a
	lsr a
	lsr a
	lsr a
	sta zahl
	#akku8
	jsr print_dez
	ldx #t_mb
	bra ++
+	.al
	asl a
	asl a
	asl a
	asl a
	asl a
	asl a
	sta zahl
	#akku8
	jsr print_dez
	ldx #t_kb
+	jsr print
	ldx #meldung3
	jsr print
	jsr startklang

	lda #$01                    ; Bildende-Interrupt
	sta PIN_IRQST
	sta PIN_IRQEN
	cli

	; Steckt ein Modul (und ist es im Menue nicht abgeschaltet), ruft der
	; Kern es jetzt auf: per JSL, nativ, Akku 8 / Index 16 Bit, direkte
	; Seite 0, Datenbank 0, Interrupts an. Kehrt es mit RTL zurueck, geht
	; es weiter ins BASIC.
	lda BOT_STATUS
	and #$0c
	cmp #$04                    ; Bit 2 steckt, Bit 3 nicht starten
	bne _basic
	ldx #0
-	lda @l MODUL,x              ; Kennung "MODUL816"
	cmp modul_kennung,x
	bne _basic
	inx
	cpx #8
	bne -
	ldx #t_modul
	jsr print
	ldx #16
-	lda @l MODUL,x              ; Name (16 Zeichen ab Byte 16)
	beq +
	jsr chrout
	inx
	cpx #32
	bne -
+	lda #13
	jsr chrout
	#akku16
	lda @l MODUL+10             ; Startadresse
	sta zeiger
	#akku8
	lda @l MODUL+12
	sta zeiger+2
	jsl _modul
	sei                         ; aufraeumen, was das Modul verstellt hat
	clc
	xce
	rep #$38
	.al
	.xl
	ldx #$01ff
	txs
	lda #$0000
	tcd
	#akku8
	lda #0
	pha
	plb
	cli
_basic
	jmp basic_kalt              ; wie beim C64: gleich ins BASIC
_modul
	jml [zeiger]

haupt
	lda #1                      ; der Monitor wartet auf Eingaben
	sta blink_frei
	wai
	lda BOT_STATUS              ; neues Programm per BOTE?
	and #$01
	beq +
	jsr lade_meldung
+
-	jsr getin
	beq haupt
	jsr taste_verarbeiten
	#akku8
	lda #19                     ; Cursor beim naechsten Bild wieder zeigen
	sta blink                   ; (wie in zeile_lesen)
	bra -

; "GELADEN $aaaaaa-$eeeeee" nach einem Ladevorgang ohne Autostart
lade_meldung
	lda #$01
	sta BOT_STATUS
	jsr cursor_aus
	lda cur_x
	beq +
	lda #13
	jsr chrout
+	ldx #t_geladen
	jsr print
	lda BOT_LADE+2
	jsr hex8
	lda BOT_LADE+1
	jsr hex8
	lda BOT_LADE
	jsr hex8
	lda #'-'
	jsr chrout
	lda #'$'
	jsr chrout
	#akku16                     ; Ende = Lade + Laenge - 1
	lda BOT_LADE
	clc
	adc BOT_LAENGE
	sta arg1
	#akku8
	lda BOT_LADE+2
	adc BOT_LAENGE+2
	sta arg1+2
	#akku16
	lda arg1
	sec
	sbc #1
	sta arg1
	#akku8
	lda arg1+2
	sbc #0
	jsr hex8
	lda arg1+1
	jsr hex8
	lda arg1
	jsr hex8
	ldx #t_quelle_menue
	lda BOT_QUELLE
	cmp #2
	bne +
	ldx #t_quelle_netz
+	jsr print
	rts

;============================================================================
; Bildschirm

; A = 40 oder 80: Textmodus umschalten und Bildschirm loeschen
modus_setzen
	#akku8
	sta spalten
	cmp #80
	beq +
	stz PIN_A_OPT
	lda #8
	bra ++
+	lda #1
	sta PIN_A_OPT
	lda #16
+	sta bpz
	stz bpz+1
	lda spalten
	sta spalt16
	stz spalt16+1
	#akku16
	lda spalt16
	asl a
	sta zbytes
	#akku8
	jmp loeschen

; Anzeige in den Grundzustand: Standardpalette, Ebene A Text (mit der
; aktuellen Spaltenzahl), Ebene B aus, kein Scrolling
anzeige_zuruecksetzen
	#akku8
	stz LOT_STEUER              ; Copper aus, Blitter anhalten
	lda #$01
	sta LOT_STATUS
	stz KRAN_STEU
	lda #$0c
	sta KRAN_BEF
	stz PIN_PIDX
	ldx #0
-	lda palette,x
	sta PIN_PLO
	lda palette+1,x
	sta PIN_PHI
	inx
	inx
	cpx #32
	bne -
	ldx #0                      ; 16-255: MERIDIAN-256, 30 Farbfamilien
-	lda farben256,x             ; (der Index zaehlt von 16 weiter)
	sta PIN_PLO
	lda farben256+1,x
	sta PIN_PHI
	inx
	inx
	cpx #480
	bne -
	stz PIN_TUSCHE              ; PINSEL-Look aus: keine Kontur, kein Schatten,
	stz PIN_GL_AN               ; keine Glanzkanaele, kein Leuchten - ein
	stz PIN_GL_AN+1             ; Programm findet PINSEL wie vor MERIDIAN 1.0
	stz PIN_LEUCHT
	stz PIN_LM_IDX
	ldx #32
-	stz PIN_LM_IDX+1            ; Leuchtmaske leeren (zaehlt selbst weiter)
	dex
	bne -
	lda #0                      ; keine Glanzpunkte (SHINE)
	sta @l GL_TAB
	sta @l KA_ZUSTAND           ; keine Karten (MAP), die Ebenen setzt es hier
	stz SFX_AN                  ; keine Klaenge (SFX), still macht orgel_still
	lda #1
	sta PIN_A_TYP
	lda spalten
	cmp #80
	lda #0
	bcc +
	lda #1
+	sta PIN_A_OPT
	lda #<BILDSCHIRM
	sta PIN_SCR
	lda #>BILDSCHIRM
	sta PIN_SCR+1
	stz PIN_SCR+2
	lda #<ZEICHEN
	sta PIN_CHR
	lda #>ZEICHEN
	sta PIN_CHR+1
	stz PIN_CHR+2
	stz PIN_A_SX
	stz PIN_A_SX+1
	stz PIN_A_SY
	stz PIN_B_TYP
	stz KOB_STEUER
	stz SP_AN                   ; BASIC: Sprites und Verlauf aus
	stz VL_AN
	lda #$ff                    ; Mauszeiger aus
	sta MZ_SPRITE
	jmp orgel_still

loeschen
	php
	sei
	#akku16
	lda farbe
	and #$00ff
	xba
	ora #$0020
	ldx #0
-	sta BILDSCHIRM,x
	inx
	inx
	cpx #80*ZEILEN*2
	bne -
	#akku8
	ldx #31
-	stz VERBUND,x
	dex
	bpl -
	stz cur_x
	stz cur_y
	stz blinkon
	plp
	rts

; A16 = Zeile -> A16 = Zeile * zbytes
mal_zbytes
	.al
	asl a
	asl a
	asl a
	asl a
	sta tmp
	asl a
	asl a
	clc
	adc tmp                     ; * 80
	sta tmp
	lda zbytes
	cmp #160
	lda tmp
	bcc +
	asl a                       ; 80 Zeichen: * 160
+	rts

; X = Offset der Cursorzelle
cursor_adr
	#akku16
	lda cur_y
	and #$00ff
	jsr mal_zbytes
	sta hilf
	lda cur_x
	and #$00ff
	asl a
	clc
	adc hilf
	tax
	#akku8
	rts

; X = Offset der letzten Zelle in der Cursorzeile
zeilenende_adr
	#akku16
	lda cur_y
	and #$00ff
	jsr mal_zbytes
	clc
	adc zbytes
	dec a
	dec a
	tax
	#akku8
	rts

; Zeichen in A ausgeben. Steuercodes: $01 Pos1, $08 Rueckschritt,
; $0C loeschen, $0D Return, $0E Einfuegen, $10-$19 Farbe, $1C-$1F Cursor,
; $7F Entf. Alle anderen Codes ab $20 sind Zeichen.
chrout
	php
	sei
	rep #$10
	.xl
	phx
	phy
	#akku8
	pha
	jsr cursor_aus
	pla
	cmp #$20
	bcc _steuer
	cmp #$7f
	beq _entf
	pha
	jsr cursor_adr
	pla
	sta BILDSCHIRM,x
	lda farbe
	sta BILDSCHIRM+1,x
	jsr cur_rechts
	lda cur_x                   ; umgebrochen: neue Zeile setzt die alte fort
	bne _ende
	jsr verbund_x
	lda #1
	sta VERBUND,x
	bra _ende
_entf
	jsr loesch_rechts
	bra _ende
_steuer
	cmp #$10
	bcc _tabelle
	cmp #$1a
	bcs _tabelle
	sec                         ; $10-$19: Vordergrundfarbe
	sbc #$10
	sta tmp
	lda farbe
	and #$f0
	ora tmp
	sta farbe
	bra _ende
_tabelle
	#akku16
	and #$001f
	asl a
	tax
	#akku8
	jsr (steuertab,x)
_ende
	ply
	plx
	plp
	rts

steuertab
	.word nichts_rts, pos1, nichts_rts, nichts_rts      ; $00-$03
	.word nichts_rts, nichts_rts, nichts_rts, klingel   ; $04-$07
	.word rueckschritt, nichts_rts, nichts_rts, nichts_rts ; $08-$0B
	.word loeschen, neue_zeile, einfuegen, nichts_rts   ; $0C-$0F
	.word nichts_rts, nichts_rts, nichts_rts, nichts_rts ; $10-$13
	.word nichts_rts, nichts_rts, nichts_rts, nichts_rts ; $14-$17
	.word nichts_rts, nichts_rts, nichts_rts, nichts_rts ; $18-$1B
	.word cur_rechts, cur_links, cur_hoch, cur_runter   ; $1C-$1F

nichts_rts
	rts

pos1
	stz cur_x
	stz cur_y
	rts

neue_zeile
	stz cur_x
	jsr cur_runter
	jsr verbund_x               ; hier beginnt eine neue logische Zeile
	stz VERBUND,x
	rts

; X = cur_y (16 Bit) fuer VERBUND
verbund_x
	pha
	lda cur_y
	#akku16
	and #$00ff
	tax
	#akku8
	pla
	rts

cur_rechts
	inc cur_x
	lda cur_x
	cmp spalten
	bcc +
	stz cur_x
	jmp cur_runter
+	rts

cur_links
	lda cur_x
	beq +
	dec cur_x
	rts
+	lda cur_y
	beq +
	dec cur_y
	lda spalten
	dec a
	sta cur_x
+	rts

cur_hoch
	lda cur_y
	beq +
	dec cur_y
+	rts

cur_runter
	inc cur_y
	lda cur_y
	cmp #ZEILEN
	bcc +
	jsr rollen
	lda #ZEILEN-1
	sta cur_y
+	rts

rueckschritt
	lda cur_x
	beq +
	dec cur_x
	jmp loesch_rechts
+	rts

; Zeichen unter dem Cursor loeschen, Rest der Zeile nachruecken (MVN)
loesch_rechts
	jsr cursor_adr
	lda spalten
	sec
	sbc cur_x
	dec a                       ; Zellen rechts vom Cursor
	beq _letzte
	#akku16
	and #$00ff
	asl a
	dec a
	pha
	txa
	clc
	adc #BILDSCHIRM
	tay
	clc
	adc #2
	tax
	pla
	mvn #0,#0
	#akku8
_letzte
	jsr zeilenende_adr
	lda #' '
	sta BILDSCHIRM,x
	lda farbe
	sta BILDSCHIRM+1,x
	rts

; Leerzeichen am Cursor einfuegen, Rest der Zeile nach rechts (MVP)
einfuegen
	jsr zeilenende_adr
	stx ende_ofs
	jsr cursor_adr
	lda spalten
	sec
	sbc cur_x
	dec a
	beq _leeren
	#akku16
	and #$00ff
	asl a
	dec a
	pha
	lda ende_ofs
	clc
	adc #BILDSCHIRM+1
	tay
	sec
	sbc #2
	tax
	pla
	mvp #0,#0
	#akku8
	jsr cursor_adr
_leeren
	lda #' '
	sta BILDSCHIRM,x
	lda farbe
	sta BILDSCHIRM+1,x
	rts

; Bildschirm eine Zeile hoch (MVN), unterste Zeile leeren
rollen
	#akku16
	lda #ZEILEN-1
	jsr mal_zbytes
	dec a
	pha
	lda zbytes
	clc
	adc #BILDSCHIRM
	tax
	ldy #BILDSCHIRM
	pla
	mvn #0,#0
	lda #ZEILEN-1
	jsr mal_zbytes
	tax
	clc
	adc zbytes
	sta tmp
	lda farbe
	and #$00ff
	xba
	ora #$0020
-	sta BILDSCHIRM,x
	inx
	inx
	cpx tmp
	bne -
	#akku8
	ldx #0                      ; Verknuepfungen mitrollen
-	lda VERBUND+1,x
	sta VERBUND,x
	inx
	cpx #ZEILEN-1
	bne -
	stz VERBUND+ZEILEN-1
	lda ein_y                   ; Beginn einer laufenden Eingabe rollt mit
	beq +
	dec ein_y
+	rts

; Cursor: Vorder- und Hintergrund der Zelle tauschen
cursor_umschalten
	jsr cursor_adr
	lda BILDSCHIRM+1,x
	asl a
	adc #$80
	rol a
	asl a
	adc #$80
	rol a
	sta BILDSCHIRM+1,x
	lda blinkon
	eor #$01
	sta blinkon
	rts

cursor_aus
	lda blinkon
	beq +
	jsr cursor_umschalten
+	stz blink
	rts

; Leere Zelle unter dem Cursor bekommt die aktuelle Vordergrundfarbe, bevor
; er dort eingeschaltet wird - so zeigt er eine neue Farbe sofort
cursor_farbe
	jsr cursor_adr
	lda BILDSCHIRM,x
	cmp #' '
	bne +
	lda BILDSCHIRM+1,x
	and #$f0
	pha
	lda farbe
	and #$0f
	ora 1,s
	sta BILDSCHIRM+1,x
	pla
+	rts

;============================================================================
; Ausgabehilfen

; Text ab X (Bank 0, mit 0 abgeschlossen)
print
	#akku8
-	lda $0000,x
	beq +
	jsr chrout
	inx
	bra -
+	rts

; 16-Bit-Zahl in 'zahl' dezimal, ohne fuehrende Nullen
print_dez
	#akku16
	stz ziff
	ldx #0
_stelle
	ldy #0
_abziehen
	lda zahl
	sec
	sbc zehner,x
	bcc _ziffer
	sta zahl
	iny
	bra _abziehen
_ziffer
	tya
	ora ziff
	beq _weiter
	tya
	clc
	adc #'0'
	sta ziff
	#akku8
	jsr chrout
	#akku16
_weiter
	inx
	inx
	cpx #10
	bne _stelle
	lda ziff
	bne +
	#akku8
	lda #'0'
	jsr chrout
+	#akku8
	rts

zehner	.word 10000, 1000, 100, 10, 1

; A als zwei Hexziffern
hex8
	#akku8
	pha
	lsr a
	lsr a
	lsr a
	lsr a
	jsr _ziffer
	pla
	and #$0f
_ziffer
	cmp #10
	bcc +
	adc #'A'-10-1
	bra ++
+	adc #'0'
+	jmp chrout

;============================================================================
; RAM zaehlen: in jeder 64-KB-Bank $8000 und $8002 beschreiben und $8000
; zuruecklesen. Zwei Stellen im Wechsel: Ohne SDRAM-Modul haelt der offene
; Datenbus den zuletzt geschriebenen Wert noch eine Weile - wer dieselbe
; Stelle gleich wieder liest, saehe Speicher, wo keiner ist (MERIDIAN 1.0).

ram_zaehlen                     ; je Bank ein Byte pruefen, Inhalt bleibt
	#akku16
	stz baenke
	lda #$8000
	sta zeiger
	#akku8
	stz zeiger+2
_bank
	lda zeiger+2                ; steckt ein Modul, ist $40-$7F ROM:
	cmp #$40                    ; nicht beschreiben, gilt als vorhanden
	bcc _pruefen
	cmp #$80
	bcs _pruefen
	lda BOT_STATUS
	and #$04
	bne _da
_pruefen
	ldy #2
	lda [zeiger]
	sta tmp
	lda [zeiger],y
	sta tmp+1
	lda #$5a
	sta [zeiger]
	lda #$a5
	sta [zeiger],y
	lda [zeiger]
	cmp #$5a
	bne _fertig
	lda #$a5
	sta [zeiger]
	lda #$5a
	sta [zeiger],y
	lda [zeiger]
	cmp #$a5
	bne _fertig
	lda tmp+1
	sta [zeiger],y
	lda tmp
	sta [zeiger]
_da
	#akku16
	inc baenke
	#akku8
	inc zeiger+2                ; alle 256 Baenke (Zusatzspeicher ab Bank 4)
	bne _bank
_fertig
	rts

farbbalken
	lda #13
	jsr chrout
	ldy #0
-	tya
	ora #$60
	sta farbe
	lda #$8b
	jsr chrout
	lda #$8b
	jsr chrout
	iny
	cpy #16
	bne -
	lda #13
	jmp chrout

;============================================================================
; Tastatur

; Naechste Taste aus dem Puffer, 0 wenn keine (Z-Flag passend)
getin
	#akku8
	php
	sei
	lda tb_rd
	cmp tb_wr
	beq _leer
	#akku16
	and #$000f
	tax
	#akku8
	lda TPUFFER,x
	pha
	lda tb_rd
	inc a
	and #$0f
	sta tb_rd
	pla
	plp
	cmp #0
	rts
_leer
	plp
	lda #0
	rts

; Taste in A in den Puffer (verwirft sie, wenn er voll ist)
puffer_rein
	pha
	#akku16
	lda tb_wr
	and #$000f
	tax
	#akku8
	pla
	pha
	sta TPUFFER,x
	inx
	txa
	and #$0f
	cmp tb_rd
	beq +
	sta tb_wr
+	pla
	rts

; Alle Ereignisse aus PFORTE abholen (im Bildende-Interrupt)
tastatur
	#akku8
-	lda PFO_INFO
	bpl +
	sta ev_info
	lda PFO_TASTE
	sta ev_code
	sta PFO_WEITER
	jsr ereignis
	bra -
+	rts

ereignis
	jsr m65_ereignis            ; fuer KEY() (Etappe 11); MEGA65-Tastatur davor
	lda ev_code
	cmp #$12
	beq _umschalt
	cmp #$59
	beq _umschalt
	cmp #$14
	beq _strg
	cmp #$11
	beq _alt
	lda ev_info
	and #$01
	bne _los
	jsr uebersetzen
	beq +
	jsr puffer_rein
	sta wdh
	lda #25
	sta wdh_z
+	rts
_los
	stz wdh
	rts
_umschalt
	lda #$01
	bra _modbit
_strg
	lda #$02
	bra _modbit
_alt
	lda #$04
_modbit
	sta tmp
	lda ev_info
	and #$01
	bne +
	lda umsch
	ora tmp
	sta umsch
	rts
+	lda tmp
	eor #$ff
	and umsch
	sta umsch
	rts

; Scancode -> Zeichen oder Steuercode (0 = nichts)
uebersetzen
	lda ev_info
	and #$02
	bne _e0
	lda ev_code
	bmi _nichts
	#akku16
	and #$00ff
	tax
	#akku8
	lda umsch
	and #$04
	bne _alt
	lda umsch
	and #$01
	bne _gross
	jsr m65_normal              ; lda tab_normal,x (MEGA65: eigene Liste)
	bra _strg
_gross
	jsr m65_shift               ; lda tab_shift,x (MEGA65: eigene Liste)
_strg
	pha
	lda umsch
	and #$02
	beq _ohne
	pla                         ; Strg + Ziffer = Farbe $10-$19
	cmp #'0'
	bcc _nichts
	cmp #'9'+1
	bcs _nichts
	sec
	sbc #'0'-$10
	rts
_ohne
	pla
	rts
_alt
	jsr m65_alt                 ; lda PFO_LAYOUT (MEGA65: ALT = Umlaute)
	and #$01
	bne _mac
	lda tab_altgr,x
	rts
_mac
	lda umsch
	and #$01
	bne +
	lda tab_mac,x
	rts
+	lda tab_macshift,x
	rts
_nichts
	lda #0
	rts
_e0
	jsr m65_e0                  ; lda ev_code / cmp #$6c (MEGA65: Umschalt/MEGA + E0)
	nop
	                            ; Umschalt + Pos1 = Bildschirm loeschen
	bne +
	lda umsch
	and #$01
	beq +
	lda #$0c
	rts
+	ldx #0
-	lda e0_tab,x
	beq _nichts
	cmp ev_code
	beq +
	inx
	inx
	bra -
+	lda e0_tab+1,x
	rts

e0_tab
	.byte $75,$1e, $72,$1f, $6b,$1d, $74,$1c, $6c,$01, $71,$7f
	.byte $70,$0e, $5a,$0d, $4a,'/', 0

; Tastenwiederholung: nach 25 Bildern alle 3 Bilder
wiederholung
	lda wdh
	beq +
	dec wdh_z
	bne +
	lda #3
	sta wdh_z
	lda wdh
	jsr puffer_rein
+	rts

;============================================================================
; Editor und Monitor

taste_verarbeiten
	cmp #$0d
	beq zeile_ausfuehren
	cmp #$03
	beq +
	jmp chrout
+	rts

; Cursorzeile lesen und als Befehl ausfuehren (wie beim C64)
zeile_ausfuehren
	#akku16
	lda cur_y
	and #$00ff
	jsr mal_zbytes
	tax
	#akku8
	ldy #0
-	lda BILDSCHIRM,x
	cmp #'a'
	bcc +
	cmp #'z'+1
	bcs +
	and #$df                    ; Kleinbuchstaben gross
+	sta EINGABE,y
	inx
	inx
	iny
	cpy spalt16
	bne -
-	dey                         ; Leerzeichen am Ende abschneiden
	bmi _leer
	lda EINGABE,y
	cmp #' '
	beq -
	iny
	lda #0
	sta EINGABE,y
	lda #13
	jsr chrout
	jsl MON_BEFEHL              ; Monitor im System-ROM (Etappe 13)
	rts
_leer
	lda #13
	jmp chrout

; Die Befehle des Monitors stehen seit Etappe 13 im System-ROM (Bank $FF,
; rom/monitor.asm); hier bleiben Bildschirmeditor und Hauptschleife.

;============================================================================
; BASIC

; Interrupt-Eingaenge: nativ und im Emulationsmodus (BASIC). Im
; Emulationsmodus hat die CPU nur PC und P gestapelt; der Kern laeuft nativ
; und kehrt vor dem RTI in den Emulationsmodus zurueck.
irq
	jsr irq_kern
	rti
irq_emu
	pha                         ; BRK? (B-Bit im gestapelten P)
	lda 2,s
	and #$10
	bne brk_emu
	pla
	clc
	xce
	jsr irq_kern
	sec
	xce
	rti

;----------------------------------------------------------------------------
; Halt fuer den Monitor (Etappe 13): BRK und Einzelschritt. Alle Register
; auf den Stapel, dazu der Grund (0 BRK, 1 Schritt, +$80 im Emulations-
; modus: dann ohne PBR), weiter im System-ROM (MON_HALT).

brk_emu
	pla
	clc
	xce
	rep #$30
	.al
	.xl
	pha
	lda #$0080
	bra halt
nmi_emu                         ; NMI im Emulationsmodus: Schritt oder Fernstart
	.as
	pha
	lda @l SYS_STEUER
	and #$02
	bne +
	pla
	jmp nmi
+	pla
	clc
	xce
	rep #$30
	.al
	pha
	lda #$0081
	bra halt
nmi_nativ                       ; NMI nativ: Schritt oder Fernstart
	rep #$30
	.al
	.xl
	pha
	lda @l SYS_STEUER
	and #$0002
	bne +
	pla
	jmp nmi
+	lda #$0001
	bra halt
brk_nativ
	rep #$30
	pha
	lda #$0000
halt
	phx
	phy
	phb
	phd
	pha
	pea 0
	pld
	#akku8
	lda #0
	pha
	plb
	#akku16
	jml MON_HALT

; BASIC aus dem BASIC-ROM (Bank $FF) holen und kalt starten.
;
; BASIC laeuft im Emulationsmodus mit Datenbank B_DATENBANK (Bank 1): Der
; Code steht in Bank 0 (dort laeuft er) und als Kopie in Bank 1 (dort liest
; er seine Tabellen), Programm, Variablen und Zeichenketten liegen in Bank 1.
; Der Spiegel blendet Zeropage, Stapel und Eingabepuffer aus Bank 0 in Bank 1
; ein - so findet Microsofts Code alles, wo er es erwartet.
basic_kalt
	sei
	rep #$30
	.al
	.xl
	ldx #$01ff
	txs
	jsr basic_kopieren
	#akku8
	lda #1
	sta basic_da
	jsr basic_bank
	cli
	sec                         ; Emulationsmodus: die CPU ist ein 6502
	xce
	jmp B_INIT

; BASIC warm starten (READY., Programm bleibt). Der Code wird neu kopiert:
; ein Maschinenprogramm darf seinen Platz in Bank 0 benutzt haben.
basic_warm
	sei
	rep #$30
	.al
	.xl
	ldx #$01fb
	txs
	jsr basic_kopieren
	#akku8
	jsr basic_bank
	cli
	sec
	xce
	jmp (B_START+1)

; BASIC-Code aus dem ROM: Hauptteil nach Bank 0 und (fuer die Tabellen)
; Bank 1, die Erweiterung (Etappe 13, ab $B800) nur nach Bank 0.
; Akku 16 Bit; zurueck mit Datenbank 0.
basic_kopieren
	.al
	lda #B_LAENGE-1
	ldx #$0000
	ldy #B_ROMLOC
	mvn #$ff,#$00
	lda #B_ERW_LAENGE-1
	ldx #B_ERW_ROM
	ldy #B_ERW
	mvn #$ff,#$00
	lda #B_LAENGE-1
	ldx #$0000
	ldy #B_ROMLOC
	mvn #$ff,#B_DATENBANK
	phk
	plb
	rts

basic_bank                      ; Spiegel an, Datenbank = BASICs Bank
	.as
	lda #$01
	sta SYS_STEUER
	lda #B_DATENBANK
	pha
	plb
	rts

bef_basic
	lda basic_da
	beq +
	jmp basic_warm
+	jmp basic_kalt

; Bruecken: im Emulationsmodus gerufen, nativ ausgefuehrt, X und Y bleiben.
; Der Kern arbeitet mit Datenbank 0, BASIC mit seiner eigenen.
b_ein	.macro
	php
	clc
	xce
	rep #$10
	.xl
	phx
	phy
	phb
	phk
	plb
	.endm

b_aus	.macro
	plb
	ply
	plx
	sec
	xce
	plp
	rts
	.endm

b_chrout
	#b_ein
	pha
	jsr chrout
	pla
	#b_aus

b_zeile
	#b_ein
	jsr zeile_lesen
	#b_aus

b_getin
	#b_ein
	jsr getin
	#b_aus

b_stopp
	#b_ein
	jsr stopp_pruefen
	#b_aus

b_monitor
	clc
	xce
	rep #$10
	.xl
	ldx #$01ff
	txs
	#akku8
	phk                         ; Datenbank 0, Spiegel aus
	plb
	stz SYS_STEUER
	jsr cursor_aus
	ldx #t_monitor              ; (geht nahtlos in "READY." ueber)
	jsr print
	cli
	jmp haupt

b_modus
	#b_ein
	jsr modus_setzen
	#b_aus

b_grafik
	#b_ein
	jsr grafik_setzen
	#b_aus

b_punkt
	#b_ein
	jsr punkt
	#b_aus

b_linie
	#b_ein
	jsr linie
	#b_aus

b_befehl                        ; KOPIERE, STEMPEL, SPRITE, MUSTER, SAMPLE, VERLAUF
	#b_ein
	jsr bb_befehl
	#b_aus

; Grafik fuer BASIC: Bitmap 256 Farben auf Ebene B ab $02:0000, Farbe 0
; durchsichtig (der Text darunter bleibt sichtbar). Werte ab $0380.
GP_X       = $0380              ; 2 Byte
GP_Y       = $0382
GP_X2      = $0383              ; 2 Byte
GP_Y2      = $0385
GP_F       = $0386
L_DX       = arg1               ; Linie: Monitor-Variablen sind waehrend
L_DY       = arg2               ; BASIC frei
L_SX       = arg3
L_SY       = wert
L_ERR      = anzahl
L_E2       = ende_ofs
L_Y        = sprung
L_Y2       = ziff

; A = 0: aus; sonst an und mit KRAN loeschen
grafik_setzen
	cmp #0
	bne +
	stz PIN_B_TYP
	rts
+	ldx #0
-	lda grafik_loeschen,x
	sta KRAN_REG,x
	inx
	cpx #16
	bne -
	lda #$01
	sta KRAN_BEF
-	lda KRAN_BEF
	and #$01
	bne -
	stz PIN_B_OPT
	stz PIN_B_DATEN
	stz PIN_B_DATEN+1
	lda #2
	sta PIN_B_DATEN+2
	lda #4
	sta PIN_B_TYP
	rts

grafik_loeschen                 ; KRAN-Auftrag: 320 x 240 ab $02:0000 mit 0 fuellen
	.byte 0, 0, 0, 0, 0, 2, <320, >320, 240, 0, 0, 0, <320, >320, 0, 1

; Punkt GP_X, GP_Y in Farbe GP_F (ausserhalb: nichts)
punkt
	#akku16
	lda GP_X
	cmp #320
	bcs _raus
	lda GP_Y
	and #$00ff
	cmp #240
	bcs _raus
	xba                         ; y * 256
	sta zeiger
	lda GP_Y
	and #$00ff
	asl a                       ; + y * 64 = y * 320
	asl a
	asl a
	asl a
	asl a
	asl a
	clc
	adc zeiger
	sta zeiger
	#akku8
	lda #2                      ; Uebertrag in die Bank
	adc #0
	sta zeiger+2
	#akku16
	lda zeiger
	clc
	adc GP_X
	sta zeiger
	#akku8
	lda zeiger+2
	adc #0
	sta zeiger+2
	lda GP_F
	sta [zeiger]
	rts
_raus
	#akku8
	rts

; Linie von GP_X,GP_Y nach GP_X2,GP_Y2 (Bresenham, mit Vorzeichen)
linie
	#akku16
	lda GP_X2                   ; dx = |x2 - x1|, sx = Richtung
	sec
	sbc GP_X
	ldx #1
	bcs +
	eor #$ffff
	inc a
	ldx #$ffff
+	sta L_DX
	stx L_SX
	lda GP_Y
	and #$00ff
	sta L_Y
	lda GP_Y2
	and #$00ff
	sta L_Y2
	sec                         ; dy = -|y2 - y1|, sy = Richtung
	sbc L_Y
	ldx #1
	bcs +
	eor #$ffff
	inc a
	ldx #$ffff
+	eor #$ffff
	inc a
	sta L_DY
	stx L_SY
	lda L_DX
	clc
	adc L_DY
	sta L_ERR
_schleife
	#akku8
	lda L_Y
	sta GP_Y
	jsr punkt
	#akku16
	lda GP_X
	cmp GP_X2
	bne +
	lda L_Y
	cmp L_Y2
	beq _fertig
+	lda L_ERR
	asl a
	sta L_E2
	sec                         ; e2 >= dy?  -> x weiter
	sbc L_DY
	bvc +
	eor #$8000
+	bmi +
	lda L_ERR
	clc
	adc L_DY
	sta L_ERR
	lda GP_X
	clc
	adc L_SX
	sta GP_X
+	lda L_DX                    ; e2 <= dx?  -> y weiter
	sec
	sbc L_E2
	bvc +
	eor #$8000
+	bmi _schleife
	lda L_ERR
	clc
	adc L_DX
	sta L_ERR
	lda L_Y
	clc
	adc L_SY
	sta L_Y
	bra _schleife
_fertig
	#akku8
	rts

	.include "befehle.asm"
	.include "eingabe.asm"

; Esc als naechste Taste? Dann verbrauchen und A = 3, sonst A = 0
stopp_pruefen
	php
	sei
	lda tb_rd
	cmp tb_wr
	beq _nein
	#akku16
	and #$000f
	tax
	#akku8
	lda TPUFFER,x
	cmp #$03
	bne _nein
	lda tb_rd
	inc a
	and #$0f
	sta tb_rd
	plp
	lda #3
	rts
_nein
	plp
	lda #0
	rts

; F1-F6 gedrueckt? Dann die Werkstatt mit diesem Reiter (sie stellt beim
; Verlassen Schirm, Chips und Speicher wieder her). Die Tasten kommen roh aus
; der Tastentabelle - GETIN liefert keine F-Tasten, Programme sehen nichts.
werkstatt_pruefen
	.as
	jsr zusatz_da               ; ihre Daten liegen im Zusatzspeicher
	bcc _nein
	ldy #0
-	#akku16
	lda ws_tasten,y
	and #$00ff
	tax
	#akku8
	lda @l TASTEN_AN,x
	bne +
	iny
	cpy #6
	bne -
	rts
+	jsr cursor_aus
	tya                         ; Reiter 0-5
	jsl WERKSTATT
_nein
	rts

zusatz_da                       ; C = 1: Zusatzspeicher bis Bank $FC (SDRAM-Modul steckt)
	.as
	#akku16
	lda baenke
	cmp #$fd
	#akku8
	rts
ws_tasten
	.byte $05, $06, $04, $0c, $03, $0b      ; F1-F6 (Scancodes)

; Eine Zeile mit dem Bildschirmeditor holen und nach BASICs Eingabepuffer
; legen (mit 0 abgeschlossen). Wie beim C64: In der Zeile, in der die
; Eingabe begann, zaehlt erst ab der Startspalte (die Eingabeaufforderung
; bleibt draussen). A = 0: ausserhalb von Anfuehrungszeichen Grossbuchstaben
; (Befehle), sonst bleibt alles, wie es getippt wurde (Antworten auf INPUT).
zeile_lesen
	sta ein_modus
	cmp #0                      ; BASIC wartet auf einen Befehl: ein Programm
	bne +                       ; ist zu Ende, MAP zeigt wieder den Text
	lda #3                      ; (MERIDIAN 1.0)
	jsl WS_BASIC
+	lda #1
	sta blink_frei
	lda cur_x
	sta ein_x
	lda cur_y
	sta ein_y
_warten
	wai
	lda ein_modus               ; BASIC wartet auf einen Befehl: F1-F6 oeffnen
	bne +                       ; die Werkstatt (MERIDIAN 1.0)
	jsr werkstatt_pruefen
+	lda BOT_STATUS              ; per Netz geladen (ohne Autostart)?
	and #$01
	beq +
	jsr lade_meldung
+	jsr getin
	beq _warten
	cmp #$0d
	beq _fertig
	cmp #$03                    ; Esc in der Eingabe: nichts
	beq _warten
	jsr chrout
	lda #19                     ; Cursor beim naechsten Bild wieder zeigen: so
	sta blink                   ; bleibt er sichtbar, waehrend man ihn bewegt
	bra _warten                 ; (wie beim C64)
_fertig
	stz blink_frei
	jsr cursor_aus
	lda cur_y                   ; logische Zeile: erste Bildschirmzeile ...
	sta ein_a
-	lda ein_a
	beq +
	#akku16
	and #$00ff
	tax
	#akku8
	lda VERBUND,x
	beq +
	dec ein_a
	bra -
+	lda cur_y                   ; ... und letzte
	sta ein_e
-	lda ein_e
	inc a
	cmp #ZEILEN
	bcs +
	#akku16
	and #$00ff
	tax
	#akku8
	lda VERBUND,x
	beq +
	inc ein_e
	bra -
+	stz ein_s                   ; begann die Eingabe in dieser logischen Zeile?
	lda ein_y                   ; dann ab dort (ohne Eingabeaufforderung),
	cmp ein_a                   ; sonst ab Spalte 0 der ersten Zeile
	bcc +
	lda ein_e
	cmp ein_y
	bcc +
	lda ein_x
	sta ein_s
	bra ++
+	lda ein_a
	sta ein_y
+	#akku16                     ; Zellen = Zeilen * Spalten - Startspalte, hoechstens 80
	lda ein_e
	sec
	sbc ein_y
	and #$00ff
	inc a
	tax
	lda #0
-	clc
	adc spalt16
	dex
	bne -
	sec
	sbc ein_s
	and #$00ff
	cmp #80
	bcc +
	lda #80
+	sta hilf
	#akku8
	lda hilf
	sta ein_n
	#akku16
	lda ein_y                   ; Bildschirmadresse der Startzelle
	and #$00ff
	jsr mal_zbytes
	sta hilf
	lda ein_s
	and #$00ff
	asl a
	clc
	adc hilf
	tax
	#akku8
	lda ein_e                   ; Cursor ans Ende der logischen Zeile
	sta cur_y
	lda ein_modus               ; INPUT: nie gross (wie in Anfuehrungszeichen)
	beq +
	lda #$80
+	sta ein_q
	ldy #0
	lda ein_n
	beq _ende
_kopie
	lda BILDSCHIRM,x
	cmp #'"'
	bne _kein_qu
	pha
	lda ein_q
	eor #$01
	sta ein_q
	pla
	bra _ablegen
_kein_qu
	pha
	lda ein_q
	beq _gross
	pla
	bra _ablegen
_gross
	pla
	cmp #'a'
	bcc _ablegen
	cmp #'z'+1
	bcs _ablegen
	and #$df
_ablegen
	sta B_BUF,y
	inx
	inx
	iny
	dec ein_n
	bne _kopie
_ende
-	dey                         ; Leerzeichen am Ende weg
	bmi +
	lda B_BUF,y
	cmp #' '
	beq -
+	iny
	lda #0
	sta B_BUF,y
	lda #13
	jmp chrout

;============================================================================
; Texte

meldung1
	.text "         **** MERIDIAN 816 ****", 13, 0
meldung2
	.text 13, " 65C816 / 8 MHz / ", 0
t_kb
	.text " KB", 0
t_mb
	.text " MB", 0
meldung3
	.text " RAM / OS 1.0", 13, 0
t_modul
	.text 13, "CARTRIDGE ", 0
modul_kennung
	.text "MODUL816"
t_monitor
	.text 13, "Monitor ready, ? for help", 13
t_bereit
	.text "READY.", 13, 0
t_geladen
	.text "LOADED $", 0
t_quelle_menue
	.text " (menu)", 13, 0
t_quelle_netz
	.text " (network)", 13, 0
t_fernstart
	.text 13, "REMOTE START $", 0
;============================================================================
; Klang

; ORGEL in den Grundzustand: alle Stimmen und Samplekanaele still,
; Lautstaerke und Panorama auf Anfang, Filter aus
orgel_still
	#akku8
	lda #1                      ; PLAY anhalten (Etappe 11)
	jsl MUSIK
	ldx #0
-	stz ORG+4,x                 ; kein Gate, keine Welle
	lda #15
	sta ORG+7,x
	lda #$ff
	sta ORG+8,x
	stz ORG_KANAL+$b,x          ; Samplekanal anhalten
	lda #63
	sta ORG_KANAL+9,x
	lda #$ff
	sta ORG_KANAL+$a,x
	#akku16
	txa
	clc
	adc #$10
	tax
	#akku8
	cpx #$40
	bne -
	stz ORG_FILTER+2            ; keine Stimme durchs Filter
	lda #$0f
	sta ORG_FILTER+3            ; Filter aus, volle Lautstaerke
	stz klang_zeit
	stz klang_maske
	rts

; Klingel (Steuercode 7): kurzer Ton auf Stimme 4
klingel
	#akku8
	lda #$10
	sta ORG+$34                 ; Gate aus, damit es neu anschlaegt
	lda #<14764                 ; 880 Hz
	sta ORG+$30
	lda #>14764
	sta ORG+$31
	lda #$08                    ; Attack 2 ms, Decay 300 ms
	sta ORG+$35
	stz ORG+$36                 ; Sustain 0
	lda #$ff
	sta ORG+$38
	lda #15
	sta ORG+$37
	lda #$11                    ; Dreieck, Gate an
	sta ORG+$34
	lda klang_maske
	ora #$08
	sta klang_maske
	lda #30
	sta klang_zeit
	rts

; Startklang: C4 G4 D5 E5 als Dreiecke, nacheinander angeschlagen
startklang
	ldx #0
	ldy #0
-	lda klang_tab,y
	sta ORG+0,x
	lda klang_tab+1,y
	sta ORG+1,x
	lda klang_tab+2,y
	sta ORG+8,x
	lda #$2b                    ; Attack 16 ms, Decay 2,4 s
	sta ORG+5,x
	stz ORG+6,x
	lda #12
	sta ORG+7,x
	lda #$11
	sta ORG+4,x
	jsr warten_40ms
	iny
	iny
	iny
	#akku16
	txa
	clc
	adc #$10
	tax
	#akku8
	cpx #$40
	bne -
	lda #$0f
	sta klang_maske
	lda #180
	sta klang_zeit
	rts

klang_tab                       ; Frequenz (f * 16,777), Panorama
	.word 4389
	.byte $ff
	.word 6577
	.byte $f7
	.word 9854
	.byte $7f
	.word 11061
	.byte $bb

; 65536 Durchlaeufe zu 5 Takten: 41 ms bei 8 MHz
warten_40ms
	phx
	ldx #0
-	dex
	bne -
	plx
	rts

; Gates der vom Kern angeschlagenen Stimmen schliessen
klang_los
	lda #$10
	lsr klang_maske
	bcc +
	sta ORG+$04
+	lsr klang_maske
	bcc +
	sta ORG+$14
+	lsr klang_maske
	bcc +
	sta ORG+$24
+	lsr klang_maske
	bcc +
	sta ORG+$34
+	rts

;============================================================================
; Interrupt: Bildende -> Tastatur, Wiederholung, Cursor, Bildzaehler;
; danach fuer jeden Interrupt der Benutzer-Haken (Standard: alles quittieren)
; (als Unterprogramm; Eingaenge irq und irq_emu im Abschnitt BASIC)

irq_kern
	rep #$30
	.al
	.xl
	pha
	phx
	phy
	phb
	phd                         ; direkte Seite 0 (das DOS arbeitet mit eigener)
	lda #$0000
	tcd
	lda tmp                     ; Hilfsvariablen des Hauptprogramms retten
	pha
	lda hilf
	pha
	#akku8
	lda #0
	pha
	plb
	lda PFO_IRQST
	sta irq_pfo
	lda PIN_IRQST
	sta irq_pin
	and #$01
	beq _haken
	sta PIN_IRQST
	jsr tastatur
	jsr wiederholung
	jsr maus_zeiger
	jsl MUSIK_TAKT              ; PLAY im Hintergrund
	lda SFX_AN                  ; SFX aus der Werkstatt (MERIDIAN 1.0)
	beq +
	lda #6
	jsl WS_BASIC
+	inc bilder
	bne +
	inc bilder+1
	bne +
	inc bilder+2
+	lda klang_zeit              ; Kern-Klaenge nach Ablauf loslassen
	beq +
	dec klang_zeit
	bne +
	jsr klang_los
+	lda blink_frei              ; laeuft ein Programm, blinkt nichts
	bne +
	jsr cursor_aus
	bra _haken
+	inc blink
	lda blink
	cmp #20
	bcc _haken
	stz blink
	lda blinkon                 ; wird er eingeschaltet: leere Zelle in der
	bne _blink_an               ; aktuellen Farbe
	jsr cursor_farbe
_blink_an
	jsr cursor_umschalten
_haken
	lda SONG_AN                 ; SONG: Timer A gibt den Takt - nur mit dem
	beq _benutzer               ; Standard-Haken (ein eigener Haken, etwa der
	lda irq_pfo                 ; von TAKTSTOCK, bekommt Timer A selbst)
	and #$02
	beq _benutzer
	#akku16
	lda BENUTZER_IRQ
	cmp #irq_standard
	#akku8
	bne _benutzer
	jsl SONG_TAKT
_benutzer
	lda irq_pin
	ldx #0
	jsr (BENUTZER_IRQ,x)
	rep #$30
	.al
	pla
	sta hilf
	pla
	sta tmp
	pld
	plb
	ply
	plx
	pla
	rts

; Standard-Haken: Rasterzeile, Timer, Copper-Signal und Blitter quittieren
irq_standard
	.as
	lda #$02
	sta PIN_IRQST
	lda #$06
	sta PFO_IRQST
	lda #$01
	sta LOT_STATUS
	lda #$08
	sta KRAN_BEF
	rts

;----------------------------------------------------------------------------
; NMI: Fernstart durch BOTE. Egal, was gerade lief: alles neu aufsetzen,
; Programm per JSL starten, danach zurueck in den Monitor. Nur ein DOS-
; Aufruf darf zu Ende laufen (MERIDIAN 1.0): Mitten im Schreiben abgebrochen,
; bliebe die Diskette halb geaendert zurueck. Dann merkt sich der NMI den
; Start, und das DOS springt an seinem Ende hierher (K_NMI).

nmi
	pha                         ; (Breite wie beim Unterbrochenen)
	php
	sep #$20
	lda @l DOS_LAEUFT
	beq +
	sta @l START_WARTET
	plp
	pla
	rti
+	plp
	pla
	sei
	clc
	xce
	stz basic_da                ; ein fremdes Programm: BASIC neu einrichten
	rep #$38
	.al
	.xl
	ldx #$01ff
	txs
	lda #$0000
	tcd
	lda #irq_standard           ; Haken zuruecksetzen
	sta BENUTZER_IRQ
	#akku8
	lda #0
	pha
	plb
	stz SYS_STEUER              ; Spiegel aus (BASIC laeuft nicht mehr)
	stz blink_frei              ; ein Programm laeuft: Cursor still
	lda #$01                    ; nur Bildende-Interrupt
	sta PIN_IRQEN
	lda #$03
	sta PIN_IRQST
	stz PFO_IRQEN
	stz PFO_TASTEU
	stz PFO_TBSTEU
	lda SONG_AN                 ; lief ein Song: alles still, Echo und Effekte
	beq +                       ; aus - ohne den Abspieler (das neue Programm
	stz SONG_AN                 ; liegt vielleicht schon ueber seinen Feldern)
	jsr orgel_still
	stz ORG_FILTER+5            ; Filterausgang: kein Echo, nicht verzerrt
	stz ORG_FILTER+6
	stz ORG_ECHO+4              ; Echo aus (es schriebe weiter in Bank $EC)
	ldx #$3f
-	stz ORG_FX,x
	stz ORG_FX+$700,x
	dex
	bpl -
	stz ORG_KANAL2+$0b          ; Samplekanaele 4-7 anhalten
	stz ORG_KANAL2+$1b
	stz ORG_KANAL2+$2b
	stz ORG_KANAL2+$3b
+
	lda #$07
	sta PFO_IRQST
	jsr anzeige_zuruecksetzen
	lda BOT_STATUS
	and #$02
	beq _monitor
	lda #$03
	sta BOT_STATUS
	cli
	ldx #t_fernstart
	jsr print
	lda BOT_START+2
	sta sprung+2
	jsr hex8
	lda BOT_START+1
	sta sprung+1
	jsr hex8
	lda BOT_START
	sta sprung
	jsr hex8
	lda #13
	jsr chrout
	phk
	pea _zurueck-1
	jml [sprung]
_zurueck
	rep #$10
	.xl
	#akku8
	lda #0
	pha
	plb
	jsr anzeige_zuruecksetzen
_monitor
	jmp basic_kalt
	cli
	jmp haupt

nichts
	rti

; RTI im Emulationsmodus holt die Programmbank nicht vom Stapel, sie bleibt,
; wie sie ist - deshalb muss er aus Bank 0 kommen, nicht aus dem System-ROM
emu_rti
	sec
	xce
	rti

; Lange Einspruenge (Etappe 13) fuer Code im System-ROM
l_chrout
	jsr chrout
	rtl
l_getin
	jsr getin
	rtl
l_modus
	jsr modus_setzen
	rtl
l_anzeige
	jsr anzeige_zuruecksetzen
	rtl
l_befehl                        ; fuer die Werkstatt (MERIDIAN 1.0): Kern-Befehl A
	jsr bb_befehl               ; mit Werten ab P_WERT, wie aus BASIC
	rtl
l_funktion                      ;   Kern-Funktion A, Wert/Ergebnis in $00-$02
	jsr bb_funktion
	rtl
l_cursor_aus
	jsr cursor_aus
	rtl
l_stopp
	jsr stopp_pruefen
	rtl
l_katalog
	jsr d_katalog
	rtl
l_dostext
	sta P_WERT
	jsr dos_fehlertext
	rtl

;============================================================================
; MEGA65-Tastatur (PFORTE $C10C Bit 1 - setzt nur der MEGA65-Port, am MiSTer
; ist es 0). Eingehaengt an vier Stellen von ereignis und uebersetzen, die
; dafuer je einen Befehl gleicher Laenge hergeben; ohne das Bit laeuft dort
; alles wie bisher. Die Listen erzeugt tools/tastatur.py (tastatur_m65.inc).
;  - Zeichen wie auf den MEGA65-Tasten: Umschalt+3 = #, +7 = ', +0 = {,
;    +: = [, +; = ], +, = <, +. = >, +/ = ?, +Pfeil links = `, = ungeschaltet, Pfund = #
;  - MEGA-Taste (E0 1F) als Umschalter, Bit 3 von umsch: | { } ~ \ `
;  - ALT: ä ö ü ß, mit Umschalt Ä Ö Ü
;  - Umschalt + F1/F3/.../F13 = F2/F4/.../F14 (auch fuer KEY() und die
;    Werkstatt); Umschalt + INST/DEL = Einfuegen, Umschalt + CRSR rechts/
;    runter = links/hoch

m65_an                          ; Z = 0: MEGA65-Belegung an
	.as
	.xl
	lda PFO_LAYOUT
	and #$02
	rts

; Liste ab m65_listen+Y nach ev_code durchsuchen: C = 1 gefunden, A = Zeichen
m65_suche
	.as
	.xl
-	lda m65_listen,y
	beq _nein
	cmp ev_code
	beq _ja
	iny
	iny
	bra -
_ja
	lda m65_listen+1,y
	sec
	rts
_nein
	clc
	rts

; in ereignis statt "jsr taste_merken": MEGA-Taste merken, F-Tasten mit
; Umschalt umsetzen; beim Loslassen beide (F1 und F2) loslassen
m65_ereignis
	.as
	.xl
	jsr m65_an
	beq _merken
	lda ev_info
	and #$02
	beq _f
	lda ev_code
	cmp #$1f                    ; E0 1F: MEGA
	bne _merken
	lda #$08
	trb umsch
	lda ev_info
	lsr a                       ; Bit 0: losgelassen
	bcs _merken
	lda #$08
	tsb umsch
	bra _merken
_f
	ldy #m65_l_ftasten-m65_listen
	jsr m65_suche
	bcc _merken
	tay                         ; Y = Zwilling (F2, F4, ...)
	lda ev_info
	lsr a
	bcs _los
	lda umsch
	lsr a                       ; Umschalt?
	bcc _merken
	tya
	sta ev_code
	bra _merken
_los
	lda ev_code
	pha
	tya
	sta ev_code
	jsr taste_merken            ; den Zwilling loslassen
	pla
	sta ev_code
_merken
	jmp taste_merken

; in uebersetzen statt "lda tab_normal,x" / "lda tab_shift,x" (X = Scancode)
m65_normal
	.as
	.xl
	jsr m65_an
	beq _pc
	ldy #m65_l_normal-m65_listen
	bra m65_taste
_pc
	lda tab_normal,x
	rts
m65_shift
	.as
	.xl
	jsr m65_an
	beq _pc
	ldy #m65_l_shift-m65_listen
	bra m65_taste
_pc
	lda tab_shift,x
	rts
m65_taste                       ; MEGA: deren Liste, sonst Y, sonst die Tabelle
	.as
	.xl
	lda umsch
	and #$08
	beq _liste
	ldy #m65_l_mega-m65_listen
	jsr m65_suche
	bcs _ende
	lda #0
	rts
_liste
	jsr m65_suche
	bcs _ende
	lda umsch
	lsr a
	bcs _gross
	lda tab_normal,x
	rts
_gross
	lda tab_shift,x
_ende
	rts

; in uebersetzen (_alt) statt "lda PFO_LAYOUT": ALT = Umlaute
m65_alt
	.as
	.xl
	jsr m65_an
	bne _m65
	lda PFO_LAYOUT              ; nicht MEGA65: wie bisher
	rts
_m65
	ldy #m65_l_alt-m65_listen
	lda umsch
	lsr a
	bcc _suchen
	ldy #m65_l_altshift-m65_listen
_suchen
	jsr m65_suche
	bcs m65_fertig
	lda #0
m65_fertig                      ; A ist das Ergebnis von uebersetzen
	tay
	pla                         ; Ruecksprung in uebersetzen verwerfen
	pla
	tya
	rts

; in uebersetzen (_e0) statt "lda ev_code / cmp #$6c": Umschalt + / = ?,
; Umschalt + CRSR rechts/runter = links/hoch, MEGA + / = \
m65_e0
	.as
	.xl
	jsr m65_an
	beq _weiter
	ldy #m65_l_e0mega-m65_listen
	lda umsch
	and #$08
	bne _suchen
	ldy #m65_l_e0shift-m65_listen
	lda umsch
	lsr a
	bcc _weiter
_suchen
	jsr m65_suche
	bcs m65_fertig
_weiter
	lda ev_code
	cmp #$6c
	rts

	.include "tastatur_m65.inc"

;============================================================================
; Sprungtabelle (feste Adressen fuer Programme)

	* = $FF80
	jmp chrout                  ; $FF80 Zeichen ausgeben
	jmp getin                   ; $FF83 Taste holen (0 = keine)
	jmp print                   ; $FF86 Text ab X ausgeben
	jmp print_dez               ; $FF89 Zahl in $1A dezimal
	jmp hex8                    ; $FF8C A hexadezimal
	jmp loeschen                ; $FF8F Bildschirm loeschen
	jmp modus_setzen            ; $FF92 A = 40/80 Zeichen
	jmp klingel                 ; $FF95 kurzer Ton (wie Steuercode 7)
	jmp orgel_still             ; $FF98 ORGEL in den Grundzustand

	* = $FFA0                   ; Bruecken fuer BASIC (Aufruf im Emulationsmodus)
	jmp b_chrout                ; $FFA0 Zeichen ausgeben
	jmp b_zeile                 ; $FFA3 Zeile nach BASICs Eingabepuffer
	jmp b_getin                 ; $FFA6 Taste holen (0 = keine)
	jmp b_stopp                 ; $FFA9 A = 3, wenn Esc gedrueckt wurde
	jmp b_monitor               ; $FFAC in den Monitor
	jmp b_modus                 ; $FFAF MODUS: A = 40/80
	jmp b_grafik                ; $FFB2 GRAFIK: A = 0 aus, sonst an
	jmp b_punkt                 ; $FFB5 PUNKT (Werte ab $0380)
	jmp b_linie                 ; $FFB8 LINIE (Werte ab $0380)
	jmp b_befehl                ; $FFBB Befehl A, Werte ab $03A0 (Etappe 9c)
	jmp b_funktion              ; $FFBE Funktion A, Wert und Ergebnis in $00 (Etappe 11)

	* = $FFC1                   ; lange Einspruenge fuer das System-ROM (Etappe 13):
	jmp l_chrout                ; $FFC1 Zeichen ausgeben     JSL, zurueck mit RTL;
	jmp l_getin                 ; $FFC4 Taste holen          Akku 8, Index 16 Bit,
	jmp l_modus                 ; $FFC7 40/80 Zeichen        Seite und Datenbank 0
	jmp l_anzeige               ; $FFCA Anzeige zuruecksetzen
	jmp l_cursor_aus            ; $FFCD Cursor aus
	jmp l_stopp                 ; $FFD0 A = 3: Esc gedrueckt
	jmp l_katalog               ; $FFD3 Inhaltsverzeichnis
	jmp l_dostext               ; $FFD6 Text zum DOS-Fehler A
	jmp bef_basic               ; $FFD9 (JML) zurueck ins BASIC
	jmp haupt                   ; $FFDC (JML) Hauptschleife
	jmp emu_rti                 ; $FFDF (JML) in den Emulationsmodus und RTI
	.byte 1, 0                  ; $FFE2 Version des Systems: 1.0 (MERIDIAN 1.0)

;============================================================================
; Vektoren

	* = $FFE4
	.word nichts                ; COP
	.word brk_nativ             ; BRK: in den Monitor (Etappe 13)
	.word nichts                ; ABORT
	.word nmi_nativ             ; NMI: Einzelschritt oder Fernstart
	.word 0
	.word irq                   ; IRQ (nativ)

	* = $FFF4
	.word nichts                ; COP
	.word 0
	.word nichts                ; ABORT
	.word nmi_emu               ; NMI
	.word start                 ; RESET
	.word irq_emu               ; IRQ/BRK (Emulation: BASIC)
