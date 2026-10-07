;============================================================================
;  KOBOLDE - Vorfuehrprogramm zu Etappe 5 (Sprites)
;
;  Auf der Parallax-Landschaft aus Etappe 4:
;   Sprite 0      UFO, doppelt gross, Joystick 1 oder Cursortasten
;   Sprite 1-24   Kugeln als Schlange auf einer Lissajous-Bahn, vier Farben
;                 aus einem Muster (Palettenbaenke), jede zweite fliegt
;                 hinter den Huegeln, jede achte doppelt gross
;   Sprite 25-28  Voegel mit Fluegelschlag
;   Sprite 29-31  Punktestand
;  Beruehrt das UFO eine Kugel (Kollisionsregister von KOBOLD), explodiert
;  sie und es gibt einen Punkt. Esc beendet.
;
;  Daten vorher laden: programme/daten/ebene_a.mer, ebene_b.mer
;  (fehlen sie, meldet KOBOLDE das und kehrt zurueck)
;============================================================================

	.cpu "65816"

GETIN        = $FF83
PRINT        = $FF86
BENUTZER_IRQ = $0300

PIN_A_TYP  = $C000
PIN_A_DATEN = $C002
PIN_A_MUSTER = $C005
PIN_PIDX   = $C008
PIN_PLO    = $C009
PIN_PHI    = $C00A
PIN_IRQEN  = $C00B
PIN_IRQST  = $C00C
PIN_ZEILE  = $C00D
PIN_ZEILEH = $C00E
PIN_A_SX   = $C010
PIN_A_SY   = $C012
PIN_B_TYP  = $C020
PIN_B_DATEN = $C022
PIN_B_MUSTER = $C025
PIN_B_SX   = $C030
PIN_B_SY   = $C032
PFO_JOY1   = $C108

KOB_TAB    = $C300              ; 8 Byte je Sprite
KOB_MADR   = $C400
KOB_MDATEN = $C402
KOB_STEUER = $C403
KOB_KOLL   = $C404

KUGELN     = 24
PROBE_A    = $030220            ; Stichproben der Daten (je 16 Byte)
PROBE_B    = $024880

	* = $2000

start
	.as
	.xl
	phb
	jsr daten_pruefen
	bcc +
	ldx #t_fehlt
	jsr PRINT
	plb
	rtl
+	sei
	rep #$20
	.al
	lda BENUTZER_IRQ
	sta alter_haken
	lda #haken
	sta BENUTZER_IRQ
	sep #$20
	.as

	stz KOB_MADR                ; Sprite-Muster in KOBOLDs eigenen Speicher
	stz KOB_MADR+1
	ldx #0
-	lda muster_daten,x
	sta KOB_MDATEN
	inx
	cpx #MUSTER_ANZAHL*128
	bne -

	lda #16                     ; Paletten: Baenke 1-2 Landschaft, 3-10 Sprites
	sta PIN_PIDX
	ldx #0
-	lda pal_ebene_a,x
	sta PIN_PLO
	lda pal_ebene_a+1,x
	sta PIN_PHI
	inx
	inx
	cpx #32
	bne -
	ldx #0
-	lda pal_ebene_b,x
	sta PIN_PLO
	lda pal_ebene_b+1,x
	sta PIN_PHI
	inx
	inx
	cpx #32
	bne -
	ldx #0
-	lda sprite_paletten,x
	sta PIN_PLO
	lda sprite_paletten+1,x
	sta PIN_PHI
	inx
	inx
	cpx #8*32
	bne -

	stz PIN_A_DATEN             ; Ebene A: Berge, Ebene B: Huegel
	stz PIN_A_DATEN+1
	lda #$03
	sta PIN_A_DATEN+2
	stz PIN_A_MUSTER
	lda #$10
	sta PIN_A_MUSTER+1
	lda #$03
	sta PIN_A_MUSTER+2
	stz PIN_A_SY
	lda #2
	sta PIN_A_TYP
	stz PIN_B_DATEN
	lda #$40
	sta PIN_B_DATEN+1
	lda #$02
	sta PIN_B_DATEN+2
	stz PIN_B_MUSTER
	lda #$50
	sta PIN_B_MUSTER+1
	lda #$02
	sta PIN_B_MUSTER+2
	stz PIN_B_SY
	lda #2
	sta PIN_B_TYP

	ldx #0                      ; alle Sprites aus, Zustaende auf null
-	stz KOB_TAB+6,x             ; (nicht ueber den 8-Bit-Akku zaehlen:
	inx                         ;  der laeuft bei 256 ueber)
	inx
	inx
	inx
	inx
	inx
	inx
	inx
	cpx #32*8
	bne -
	ldx #0
-	stz zustand,x
	inx
	cpx #32
	bne -
	rep #$20
	.al
	stz zeit
	stz punkte
	lda #160+32-16
	sta ufo_x
	lda #60+32
	sta ufo_y
	sep #$20
	.as
	sta KOB_KOLL
	lda #1
	sta KOB_STEUER

	lda #250                    ; Himmel per Rasterinterrupt (wie GRAFIK)
	sta PIN_ZEILE
	stz PIN_ZEILEH
	lda #$03
	sta PIN_IRQEN
	cli

haupt
	wai
	jsr GETIN
	beq haupt
	cmp #$03                    ; Esc
	beq ende
	sta taste                   ; Cursortasten schieben das UFO in Schritten
	ldx #0
	cmp #$1c
	bne +
	ldx #8
+	cmp #$1d
	bne +
	ldx #-8
+	stx tmp
	rep #$20
	.al
	lda ufo_x
	clc
	adc tmp
	sta ufo_x
	sep #$20
	.as
	ldx #0
	lda taste
	cmp #$1e
	bne +
	ldx #-8
+	cmp #$1f
	bne +
	ldx #8
+	stx tmp
	rep #$20
	.al
	lda ufo_y
	clc
	adc tmp
	sta ufo_y
	sep #$20
	.as
	jsr ufo_begrenzen
	bra haupt

ende
	sei
	stz KOB_STEUER
	lda #$01
	sta PIN_IRQEN
	lda #$02
	sta PIN_IRQST
	rep #$20
	.al
	lda alter_haken
	sta BENUTZER_IRQ
	sep #$20
	.as
	cli
	plb
	rtl

; Liegen die Daten im Speicher? Je 16 Byte mit den Dateien vergleichen,
; aus denen sie stammen. C = 1: etwas fehlt
daten_pruefen
	ldx #15
-	lda PROBE_A,x
	cmp soll_a,x
	bne _fehlt
	lda PROBE_B,x
	cmp soll_b,x
	bne _fehlt
	dex
	bpl -
	clc
	rts
_fehlt
	sec
	rts

;----------------------------------------------------------------------------
; Interrupt-Haken: A = PINSEL-Status

haken
	pha
	and #$01
	beq +
	jsr bild
+	pla
	and #$02
	beq +
	sta PIN_IRQST
	jsr himmel
+	rts

;----------------------------------------------------------------------------
; Einmal pro Bild: Landschaft schieben, Spiel weiterrechnen, Sprites setzen

bild
	rep #$20
	.al
	inc zeit
	lda zeit
	lsr a
	and #$01ff
	sep #$20
	.as
	sta PIN_A_SX
	xba
	sta PIN_A_SX+1
	rep #$20
	.al
	lda zeit
	asl a
	and #$01ff
	sep #$20
	.as
	sta PIN_B_SX
	xba
	sta PIN_B_SX+1

	jsr joystick
	jsr kollisionen
	jsr ufo_setzen
	jsr kugeln_setzen
	jsr voegel_setzen
	jsr punkte_setzen
	rts

; Joystick 1: Bit 0 rechts, 1 links, 2 runter, 3 hoch -> 2 Pixel pro Bild
joystick
	lda PFO_JOY1
	sta tmp
	rep #$20
	.al
	lda tmp
	and #$0001
	beq +
	inc ufo_x
	inc ufo_x
+	lda tmp
	and #$0002
	beq +
	dec ufo_x
	dec ufo_x
+	lda tmp
	and #$0004
	beq +
	inc ufo_y
	inc ufo_y
+	lda tmp
	and #$0008
	beq +
	dec ufo_y
	dec ufo_y
+	sep #$20
	.as
	jmp ufo_begrenzen

ufo_begrenzen
	rep #$20
	.al
	lda ufo_x
	bpl +
	lda #0
+	cmp #352-32+1
	bcc +
	lda #352-32
+	sta ufo_x
	lda ufo_y
	cmp #32
	bcs +
	lda #32
+	cmp #272-32+1
	bcc +
	lda #272-32
+	sta ufo_y
	sep #$20
	.as
	rts

; Kollisionen: Beruehrt das UFO (Bit 0) eine Kugel, die ebenfalls ein Bit
; hat und nahe genug ist, explodiert die Kugel.
kollisionen
	lda KOB_KOLL
	and #$01
	beq _fertig
	ldy #1
_kugel
	jsr koll_bit                ; C = Bit von Sprite Y
	bcc _weiter
	lda zustand,y
	bne _weiter                 ; explodiert schon
	rep #$20                    ; nahe genug? |UFO-Mitte - Kugel-Mitte| < 20
	.al
	tya
	asl a
	tax
	lda ufo_x
	clc
	adc #16-8
	sec
	sbc kugel_x,x
	bpl +
	eor #$ffff
	inc a
+	cmp #20
	bcs _weiter16
	lda ufo_y
	clc
	adc #16-8
	sec
	sbc kugel_y,x
	bpl +
	eor #$ffff
	inc a
+	cmp #20
	bcs _weiter16
	sep #$20
	.as
	lda #30                     ; 30 Bilder Explosion
	sta zustand,y
	sed
	lda punkte
	clc
	adc #1
	sta punkte
	lda punkte+1
	adc #0
	sta punkte+1
	cld
	bra _weiter
_weiter16
	sep #$20
	.as
_weiter
	iny
	cpy #KUGELN+1
	bne _kugel
_fertig
	sta KOB_KOLL                ; alle Kollisionsbits loeschen
	rts

; C = Kollisionsbit von Sprite Y (1-31). TAX/TAY uebertragen auch bei 8-Bit-Akku
; alle 16 Bit - deshalb die Indizes im 16-Bit-Modus bilden.
koll_bit
	rep #$20
	.al
	tya
	and #$0007
	tax
	sep #$20
	.as
	lda bitmaske,x
	sta tmp
	rep #$20
	.al
	tya
	lsr a
	lsr a
	lsr a
	tax
	sep #$20
	.as
	lda KOB_KOLL,x
	and tmp
	cmp #1                      ; C = 1, wenn das Bit gesetzt ist
	rts

bitmaske	.byte $01, $02, $04, $08, $10, $20, $40, $80

ufo_setzen
	rep #$20
	.al
	lda ufo_x
	sta KOB_TAB+0
	lda ufo_y
	sta KOB_TAB+2
	sep #$20
	.as
	lda #1
	sta KOB_TAB+4               ; Muster UFO
	lda #7 | $80                ; Bank 7, doppelt gross
	sta KOB_TAB+5
	lda #1
	sta KOB_TAB+6
	rts

; Kugeln: Schlange auf einer Lissajous-Bahn
kugeln_setzen
	ldy #1
_kugel
	rep #$20
	.al
	tya                         ; Phase = i * 10
	asl a
	sta tmp
	asl a
	asl a
	clc
	adc tmp
	sta phase
	lda zeit                    ; X-Winkel = Zeit * 2 + Phase
	asl a
	clc
	adc phase
	and #$00ff
	asl a
	tax
	lda bahn_x,x
	clc
	adc #32+160-8
	pha
	lda zeit                    ; Y-Winkel = Zeit * 3 + Phase
	asl a
	clc
	adc zeit
	adc phase
	and #$00ff
	asl a
	tax
	lda bahn_y,x
	clc
	adc #32+108-8
	pha
	tya
	asl a
	tax
	pla
	sta kugel_y,x
	pla
	sta kugel_x,x
	tya                         ; Tabellenplatz = i * 8
	asl a
	asl a
	asl a
	tax
	sep #$20
	.as
	jsr kugel_schreiben
	iny
	cpy #KUGELN+1
	bne _kugel
	rts

; X = Tabellenplatz, Y = Kugelnummer
kugel_schreiben
	phx
	rep #$20
	.al
	tya
	asl a
	tax
	lda kugel_x,x
	sta tmp
	lda kugel_y,x
	plx
	sta KOB_TAB+2,x
	lda tmp
	sta KOB_TAB+0,x
	sep #$20
	.as
	lda zustand,y
	beq _normal
	dec a                       ; Explosion laeuft
	sta zustand,y
	lsr a
	lsr a
	and #$01
	clc
	adc #4                      ; Muster 4 und 5 im Wechsel
	sta KOB_TAB+4,x
	lda #9                      ; Bank 9
	sta KOB_TAB+5,x
	lda zustand,y
	beq +
	lda #1
+	sta KOB_TAB+6,x
	rts
_normal
	stz KOB_TAB+4,x             ; Muster Kugel
	tya
	and #$03
	clc
	adc #3                      ; Baenke 3-6
	sta tmp
	tya
	and #$01
	beq +
	lda tmp
	ora #$40                    ; hinter Ebene B
	sta tmp
+	tya
	and #$07
	bne +
	lda tmp
	ora #$80                    ; doppelt gross
	sta tmp
+	lda tmp
	sta KOB_TAB+5,x
	lda #1
	sta KOB_TAB+6,x
	rts

; Voegel: von rechts nach links, Fluegelschlag alle 8 Bilder
voegel_setzen
	ldy #0
_vogel
	rep #$20
	.al
	tya                         ; X = 384 - ((Zeit + i*97) & 511), 9 Bit
	asl a
	asl a
	asl a
	asl a
	asl a
	sta tmp                     ; i*32
	tya
	asl a
	asl a
	asl a
	asl a
	asl a
	asl a                       ; i*64
	clc
	adc tmp
	sta tmp                     ; i*96
	tya
	clc
	adc tmp                     ; i*97
	adc zeit
	and #$01ff
	sta tmp
	lda #384
	sec
	sbc tmp
	and #$01ff
	sta tmp
	tya
	clc
	adc #25
	asl a
	asl a
	asl a
	tax
	lda tmp
	sta KOB_TAB+0,x
	tya
	asl a
	asl a
	asl a
	asl a
	clc
	adc #32+28
	sta KOB_TAB+2,x
	sep #$20
	.as
	lda zeit
	lsr a
	lsr a
	lsr a
	and #$01
	clc
	adc #2
	sta KOB_TAB+4,x
	lda #8
	sta KOB_TAB+5,x
	lda #1
	sta KOB_TAB+6,x
	iny
	cpy #4
	bne _vogel
	rts

; Punktestand (BCD) mit den Sprites 29-31
punkte_setzen
	lda punkte+1
	and #$0f
	ldy #0
	jsr ziffer
	lda punkte
	lsr a
	lsr a
	lsr a
	lsr a
	ldy #1
	jsr ziffer
	lda punkte
	and #$0f
	ldy #2

; A = Ziffer, Y = Stelle 0-2 (Sprite 29+Y)
ziffer
	pha
	rep #$20
	.al
	tya
	asl a
	tax
	lda ziffer_x,x
	pha
	tya
	clc
	adc #29
	asl a
	asl a
	asl a
	tax
	pla
	sta KOB_TAB+0,x
	lda #32+8
	sta KOB_TAB+2,x
	sep #$20
	.as
	pla
	clc
	adc #10                     ; Muster 10-19
	sta KOB_TAB+4,x
	lda #10                     ; Bank 10
	sta KOB_TAB+5,x
	lda #1
	sta KOB_TAB+6,x
	rts

ziffer_x	.word 32+262, 32+278, 32+294

;----------------------------------------------------------------------------
; Himmel: Farbe 0 Zeile fuer Zeile (wie in GRAFIK)

himmel
-	lda PIN_ZEILEH
	bne -
	lda PIN_ZEILE
	bne -
	stz PIN_PIDX
	lda himmel_tab
	sta PIN_PLO
	lda himmel_tab+1
	sta PIN_PHI
	ldy #1
_zeile
	lda PIN_ZEILE
-	cmp PIN_ZEILE
	beq -
	rep #$20
	.al
	tya
	asl a
	tax
	sep #$20
	.as
	stz PIN_PIDX
	lda himmel_tab,x
	sta PIN_PLO
	lda himmel_tab+1,x
	sta PIN_PHI
	iny
	cpy #HIMMEL_ZEILEN
	bne _zeile
	rts

;----------------------------------------------------------------------------

	.include "grafik_daten.inc"
	.include "kobolde_daten.inc"

; Stichproben aus den MER-Dateien (16 Byte Kopf)
soll_a
	.binary "daten/ebene_a.mer", 16 + (PROBE_A - $030000), 16
soll_b
	.binary "daten/ebene_b.mer", 16 + (PROBE_B - $024000), 16
t_fehlt
	.text 13, "KOBOLDE needs its data. Send first:", 13
	.text "  daten/ebene_a.mer", 13
	.text "  daten/ebene_b.mer", 13, 0

alter_haken  .word 0
zeit         .word 0
tmp          .word 0
phase        .word 0
ufo_x        .word 0
ufo_y        .word 0
punkte       .word 0
taste        .byte 0
kugel_x      .fill 2*32
kugel_y      .fill 2*32
zustand      .fill 32
