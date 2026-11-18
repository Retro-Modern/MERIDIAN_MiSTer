;============================================================================
;  SONG - TAKTSTOCK-Songs aus BASIC (MERIDIAN 1.0, Schritt 1)
;
;  ROM-Block Bank $FF ab $8000 (16 KB). Er enthaelt den Abspieler von
;  TAKTSTOCK (taktstock/spieler.asm, mit der Rechnung des Synth-Pults aus
;  taktstock/pult_rechnen.asm). Die .TAK-Datei wird einmal geladen und an
;  Ort und Stelle gespielt - der Abspieler findet Samples, Lautstaerke-
;  Spalte, Huellkurven und Pult auch im Aufbau der Datei.
;  Bilder und Texte der Bildspur bleiben liegen (BASIC hat keine Buehne).
;
;  Einspruenge (JSL, Akku 8, Index 16, DBR 0):
;    $FF:8000  A = 0: Song laden und spielen - den Namen hat der Kern schon
;              ins DOS gelegt (D_TEXT, D_TLEN, D_ENDUNG, D_LW).
;              A = 0 gut, 2-9 Fehler des DOS, 13 keine TAKTSTOCK-Datei.
;              A = 1: SONG STOP
;    $FF:8004  Takt: aus dem Interrupt des Kerns, wenn Timer A gemeldet hat
;              (nur, solange SONG_AN gesetzt ist und der Standard-Haken gilt)
;    $FF:8008  A = n -> A: 0 Position in der Folge, 1 Zeile, 2 spielt (1/0)
;    $FF:800C  Systemkarte der Logo-Taste F7 (der Kern ruft sie am READY)
;
;  Speicher: der Abspieler $00:B49A-$B7FF, davor eigene Werte ab $B480 (das
;  Ende des Bereichs fuer Maschinenprogramme); der Merker SONG_AN $00:02E0
;  liegt beim Kern, der ihn beim Kaltstart und Fernstart loescht. Die Datei
;  liegt ab $80:0000 (hoechstens 4 MB), das Echo in Bank $EC.
;============================================================================

	.cpu "65816"

akku8	.macro
	sep #$20
	.as
	.endm
akku16	.macro
	rep #$20
	.al
	.endm

DOS       = $FF4000
D_ADR     = $16E4
D_LAENGE  = $16E8
PFO_IRQST = $C104
PFO_IRQEN = $C105

SONG_AN   = $02E0               ; 1: SONG laeuft (beim Kern, siehe oben)
SG        = $B480               ; eigene Werte (26 Byte vor dem Abspieler)
sg_ende   = SG+0                ; 4: so lang muss die Datei mindestens sein
sg_marke  = SG+22               ; 4: "SONG", solange der Abspieler hier wohnt
SP_RAM    = $B49A               ; Abspieler: $366 Byte bis $B7FF
	.cerror sg_marke+4 > SP_RAM, "SONG: eigene Werte reichen in den Abspieler"
	.cerror SP_RAM + $366 > $B800, "SONG: Abspieler reicht in die BASIC-Erweiterung"

SONG      = $800000             ; die Datei (bis $BF:FFFF)
SK_ANZPAT = 26                  ; Kopf der Datei (siehe taktstock/tak.py)
SK_PANFANG = 40                 ; 4: Anfang der Samples
SK_PLAENGE = 44                 ; 4: ihre Laenge
SK_BILDTEIL = 60                ; 3: Laenge des Bildteils dahinter
SK_MARKE  = 63                  ; $E7 hiesse "Arbeitskopie von TAKTSTOCK"

	* = $FF8000
	jml song_befehl             ; $FF8000
	jml song_takt               ; $FF8004
	jml song_funktion           ; $FF8008
	jml logo_karte              ; $FF800C

;----------------------------------------------------------------------------
; Logo-Taste F7: Systemkarte am READY. Schreibt mit dem Kern in die Textzeilen
; und laesst den Cursor in einer leeren Zeile darunter.

LK_CHROUT = $00FFC1
LK_FARBE  = $12                 ; Hintergrund * 16 + Vordergrund
LK_BAENKE = $20                 ; 16 Bit: Baenke zu 64 KB

logo_karte
	.as
	.xl
	lda LK_FARBE
	pha
	and #$f0
	ora #$07                    ; gelb auf dem Hintergrund des Benutzers
	sta LK_FARBE
	ldx #<>lk_titel
	jsr lk_text
	lda 1,s
	sta LK_FARBE
	ldx #<>lk_cpu
	jsr lk_text
	#akku16
	lda LK_BAENKE
	cmp #16
	bcc _kb
	clc                         ; ab 1 MB aufgerundet wie beim Start
	adc #15
	lsr a
	lsr a
	lsr a
	lsr a
	jsr lk_zahl
	ldx #<>lk_mb
	bra _ram
_kb
	asl a
	asl a
	asl a
	asl a
	asl a
	asl a
	jsr lk_zahl
	ldx #<>lk_kb
_ram
	#akku8
	jsr lk_text
	lda @l $00FFE2              ; Version des Systems
	ora #'0'
	jsl LK_CHROUT
	lda #'.'
	jsl LK_CHROUT
	lda @l $00FFE3
	ora #'0'
	jsl LK_CHROUT
	lda #13
	jsl LK_CHROUT
	#akku16
	lda LK_BAENKE
	cmp #$fd
	#akku8
	bcc _ende                   ; ohne Zusatzspeicher keine Werkstatt
	ldx #<>lk_tasten
	jsr lk_text
_ende
	pla
	sta LK_FARBE
	rtl

lk_text                         ; X = Text in dieser Bank, mit 0 am Ende
	.as
	.xl
-	lda @l $FF0000,x
	beq +
	phx
	jsl LK_CHROUT
	plx
	inx
	bra -
+	rts

lk_zahl                         ; A (16 Bit) dezimal ausgeben
	.al
	.xl
	ldy #0
_teilen
	ldx #0
-	cmp #10
	bcc +
	sbc #10
	inx
	bra -
+	pha
	iny
	txa
	bne _teilen
_ziffer
	pla
	#akku8
	ora #'0'
	phy
	jsl LK_CHROUT
	ply
	#akku16
	dey
	bne _ziffer
	rts

lk_titel
	.text 13, "**** MERIDIAN 816 ****", 13, 0
lk_cpu
	.text "65C816 / 8 MHz / ", 0
lk_kb
	.text " KB RAM / OS ", 0
lk_mb
	.text " MB RAM / OS ", 0
lk_tasten
	.text 13, "F1 SPRITES   F2 TILES   F3 MAP", 13
	.text "F4 SOUNDS    F5 LOOK    F6 FONT", 13
	.text "F10 BACK     ESC STOP", 13, 0

;----------------------------------------------------------------------------
; Befehl: A = 0 laden und spielen, 1 anhalten

song_befehl
	.as
	.xl
	cmp #1
	bne +
	jsr song_halt
	lda #0
	rtl
+	jsr song_halt
	jsr song_laden
	rtl

song_halt
	.as
	lda SONG_AN
	beq +
	stz SONG_AN
	jsr sp_halt                 ; Noten los, alles still
	jsr sp_stopp                ; Timer A aus
	lda PFO_IRQEN
	and #$fd
	sta PFO_IRQEN
+	rts

; A = 0 gut, sonst Fehler
song_laden
	.as
	#akku16                     ; ganze Datei (hoechstens 4 MB)
	lda #<>SONG
	sta D_ADR
	lda #0
	sta D_LAENGE
	lda #$0040
	sta D_LAENGE+2
	#akku8
	lda #`SONG
	sta D_ADR+2
	lda #0
	jsl DOS
	cmp #0
	beq +
	rts
+	lda @l SONG                 ; "TAK", Version 1-5
	cmp #'T'
	bne _kein
	lda @l SONG+1
	cmp #'A'
	bne _kein
	lda @l SONG+2
	cmp #'K'
	bne _kein
	lda @l SONG+3
	beq _kein
	cmp #6
	bcs _kein
	lda @l SONG+SK_ANZPAT       ; 1-128 Patterns
	beq _kein
	cmp #129
	bcs _kein
	jsr song_ende               ; ganz gelesen?
	#akku16
	lda D_LAENGE+2
	cmp sg_ende+2
	bne +
	lda D_LAENGE
	cmp sg_ende
+	#akku8
	bcc _kein
	lda #0                      ; Aufbau der Datei, nicht der Arbeitskopie
	sta @l SONG+SK_MARKE
	jmp song_starten
_kein
	lda #13
	rts

; sg_ende = Samples + ihre Laenge + Bildteil, ab Version 2 die
; Lautstaerke-Spalte (Patterns * 512), ab 3 die Huellkurven (4096), ab 4
; das Pult (512)
song_ende
	.as
	#akku16
	lda @l SONG+SK_PANFANG
	clc
	adc @l SONG+SK_PLAENGE
	sta sg_ende
	lda @l SONG+SK_PANFANG+2
	adc @l SONG+SK_PLAENGE+2
	sta sg_ende+2
	lda @l SONG+SK_BILDTEIL
	jsr _dazu
	lda @l SONG+SK_BILDTEIL+2
	and #$00ff
	clc
	adc sg_ende+2
	sta sg_ende+2
	#akku8
	lda @l SONG+3
	cmp #2
	bcc _r
	#akku16
	lda @l SONG+SK_ANZPAT
	and #$00ff
	xba                         ; * 256
	asl a                       ; * 512 (128 Patterns: 64 KB = 0 und Uebertrag)
	php
	jsr _dazu
	plp
	bcc +
	inc sg_ende+2
+	#akku8
	lda @l SONG+3
	cmp #3
	bcc _r
	#akku16
	lda #64*64
	jsr _dazu
	#akku8
	lda @l SONG+3
	cmp #4
	bcc _r
	#akku16
	lda #64*8
	jsr _dazu
	#akku8
_r	rts
_dazu
	.al
	clc
	adc sg_ende
	sta sg_ende
	bcc +
	inc sg_ende+2
+	rts

; Abspieler einrichten und den Song von vorn spielen
song_starten
	.as
	ldx #0                      ; Felder des Abspielers leeren
-	stz SP_RAM,x
	inx
	cpx #$366
	bne -
	#akku16
	lda #<>SONG
	sta sp_song
	lda @l SONG+SK_PANFANG      ; Samples: in der Datei
	clc
	adc #<>SONG
	sta sp_chip
	lda #<>pu_rechnen
	sta sp_pvek
	#akku8
	lda @l SONG+SK_PANFANG+2
	adc #`SONG
	sta sp_chip+2
	lda #`SONG
	sta sp_song+2
	lda #`pu_rechnen
	sta sp_pvek+2
	jsr sp_init
	lda #1
	jsr sp_spielen
	#akku16
	lda #$4f53                  ; "SO"
	sta sg_marke
	lda #$474e                  ; "NG"
	sta sg_marke+2
	#akku8
	lda #1
	sta SONG_AN
	lda PFO_IRQEN               ; Timer A meldet sich beim Kern
	ora #$02
	sta PFO_IRQEN
	lda #0
	rts

;----------------------------------------------------------------------------
; Takt (aus dem Interrupt) und Funktion

song_takt
	.as
	.xl
	lda #$02                    ; Timer A quittieren
	sta PFO_IRQST
	#akku16                     ; Hat ein Programm den Abspieler ueberschrieben
	lda sg_marke                ; (Bank 0 bis $B7FF)? Dann still aufhoeren,
	cmp #$4f53                  ; ohne seine Felder anzufassen
	bne _weg
	lda sg_marke+2
	cmp #$474e
	bne _weg
	#akku8
	jsr sp_takt
	rtl
_weg
	#akku8
	stz SONG_AN
	lda PFO_IRQEN
	and #$fd
	sta PFO_IRQEN
	stz SP_TAST                 ; Timer A aus
	jsr sp_still
	stz ECHO+4
	rtl

song_funktion
	.as
	.xl
	cmp #3
	bcs _null
	cmp #2
	bcc +
	lda SONG_AN                 ; SONG(2): spielt er (F00 haelt ihn an)?
	beq _r
	lda sp_an
	rtl
_null
	lda #0
	rtl
+	cmp #1
	beq +
	lda SONG_AN                 ; SONG(0): Position (laeuft nichts: 0)
	beq _r
	lda sp_pos
	rtl
+	lda SONG_AN                 ; SONG(1): Zeile
	beq _r
	lda sp_zeile
_r	rtl

;----------------------------------------------------------------------------
; der Abspieler von TAKTSTOCK und die Rechnung des Pults

	.include "../taktstock/spieler.asm"
PR_PERIODEN = sp_perioden
	.include "../taktstock/pult_rechnen.asm"

	.cerror * > $FFC000, "SONG: ROM-Block voll"
