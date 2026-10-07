;============================================================================
;  GRAFIK - Vorfuehrprogramm zu Etappe 4
;
;  Szene 1: Ebene A zeigt ein Bild 320x240 mit 256 Farben aus 4096,
;           Ebene B Text mit durchsichtigem Hintergrund darueber.
;  Szene 2: zwei Kachelebenen als Parallax-Landschaft (Berge langsam,
;           Huegel viermal so schnell), Himmel per Rasterinterrupt Zeile
;           fuer Zeile umgefaerbt.
;  Je eine Taste schaltet weiter; danach zurueck in den Monitor.
;
;  Daten vorher laden: programme/daten/bild.mer, ebene_a.mer, ebene_b.mer
;  (fehlen sie, meldet GRAFIK das und kehrt zurueck)
;============================================================================

	.cpu "65816"

GETIN        = $FF83
PRINT        = $FF86
BENUTZER_IRQ = $0300
ZEICHEN      = $1800
TEXT         = $3000            ; Textschirm fuer Ebene B

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
PIN_B_OPT  = $C021
PIN_B_DATEN = $C022
PIN_B_MUSTER = $C025
PIN_B_SX   = $C030
PIN_B_SY   = $C032

BILDPALETTE = $022C00
PROBE_BILD = $017DB0            ; Stichproben der Daten (je 16 Byte)
PROBE_A    = $030220
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
	stz szene
	cli

	jsr szene1
	jsr taste
	jsr szene2
	jsr taste

	sei                         ; aufraeumen, der Kern stellt die Anzeige zurueck
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

taste
-	wai
	jsr GETIN
	beq -
	rts

; Liegen die Daten im Speicher? Je 16 Byte mit den Dateien vergleichen,
; aus denen sie stammen. C = 1: etwas fehlt
daten_pruefen
	ldx #15
-	lda PROBE_BILD,x
	cmp soll_bild,x
	bne _fehlt
	lda PROBE_A,x
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
; Szene 1: Bitmap mit 256 Farben, Text darueber

szene1
	lda #16                     ; 240 Bildfarben auf die Plaetze 16-255
	sta PIN_PIDX
	ldx #0
-	lda BILDPALETTE,x
	sta PIN_PLO
	lda BILDPALETTE+1,x
	sta PIN_PHI
	inx
	inx
	cpx #480
	bne -

	rep #$20                    ; Textschirm leeren: Zeichen 0, Farbe 0 = durchsichtig
	.al
	ldx #0
-	stz TEXT,x
	inx
	inx
	cpx #40*30*2
	bne -
	sep #$20
	.as
	ldx #texte1
	jsr alle_texte

	lda #$00                    ; Ebene A: Bitmap 256 ab $01:0000
	sta PIN_A_DATEN
	sta PIN_A_DATEN+1
	lda #$01
	sta PIN_A_DATEN+2
	lda #4
	sta PIN_A_TYP

	lda #<TEXT                  ; Ebene B: Text, 40 Zeichen
	sta PIN_B_DATEN
	lda #>TEXT
	sta PIN_B_DATEN+1
	stz PIN_B_DATEN+2
	lda #<ZEICHEN
	sta PIN_B_MUSTER
	lda #>ZEICHEN
	sta PIN_B_MUSTER+1
	stz PIN_B_MUSTER+2
	stz PIN_B_OPT
	lda #1
	sta PIN_B_TYP
	lda #1
	sta szene
	rts

; Liste von Texten ab X: Zeile, Spalte, Farbe, Text, 0 ... Ende mit $FF
alle_texte
-	lda $0000,x
	cmp #$ff
	beq +
	jsr schreibe
	inx
	bra -
+	rts

; Ein Text: X zeigt auf Zeile, Spalte, Farbe, Zeichen..., 0; X danach auf der 0
schreibe
	rep #$20
	.al
	lda $0000,x
	and #$00ff
	asl a
	asl a
	asl a
	sta tmp                     ; Zeile * 8
	asl a
	asl a
	clc
	adc tmp                     ; Zeile * 40
	sta tmp
	lda $0001,x
	and #$00ff
	clc
	adc tmp
	asl a
	tay
	sep #$20
	.as
	lda $0002,x
	sta farbe
	inx
	inx
	inx
-	lda $0000,x
	beq +
	sta TEXT,y
	lda farbe
	sta TEXT+1,y
	iny
	iny
	inx
	bra -
+	rts

;----------------------------------------------------------------------------
; Szene 2: Parallax aus zwei Kachelebenen

szene2
	sei
	lda #16                     ; Kachelpaletten: Bank 1 und 2
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

	stz PIN_A_DATEN             ; Ebene A: Karte $03:0000, Muster $03:1000
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

	stz PIN_B_DATEN             ; Ebene B: Karte $02:4000, Muster $02:5000
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

	stz zeit
	stz zeit+1
	lda #250                    ; Rasterinterrupt in der unsichtbaren Austastung,
	sta PIN_ZEILE               ; dort auf Zeile 0 warten
	stz PIN_ZEILEH
	lda #$03
	sta PIN_IRQEN
	lda #2
	sta szene
	cli
	rts

;----------------------------------------------------------------------------
; Interrupt-Haken: A = PINSEL-Status

haken
	pha
	and #$01
	beq +
	jsr bildende
+	pla
	and #$02
	beq +
	sta PIN_IRQST
	lda szene
	cmp #2
	bne +
	jsr himmel
+	rts

; Bildende: in Szene 2 beide Ebenen weiterschieben
bildende
	lda szene
	cmp #2
	bne +
	rep #$20
	.al
	inc zeit
	lda zeit
	lsr a                       ; hinten: ein Pixel alle zwei Bilder
	and #$01ff
	sep #$20
	.as
	sta PIN_A_SX
	xba
	sta PIN_A_SX+1
	rep #$20
	.al
	lda zeit
	asl a                       ; vorn: zwei Pixel pro Bild
	and #$01ff
	sep #$20
	.as
	sta PIN_B_SX
	xba
	sta PIN_B_SX+1
+	rts

; Himmel: Farbe 0 in jeder Zeile neu, immer in der Austastluecke. Der
; Interrupt kommt in Zeile 250; bis Zeile 0 warten (auch bei PAL mit 312 Zeilen)
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

texte1
	.byte 1, 2, 7
	.text "MERIDIAN 816 - GRAPHICS", 0
	.byte 3, 2, 1
	.text "Layer A: bitmap 320x240 pixels,", 0
	.byte 4, 2, 1
	.text "256 colors out of 4096.", 0
	.byte 6, 2, 14
	.text "Layer B: text, background", 0
	.byte 7, 2, 14
	.text "transparent.", 0
	.byte 27, 2, 7
	.text "Press a key for the landscape", 0
	.byte $ff

	.include "grafik_daten.inc"

; Stichproben aus den MER-Dateien (16 Byte Kopf)
soll_bild
	.binary "daten/bild.mer", 16 + (PROBE_BILD - $010000), 16
soll_a
	.binary "daten/ebene_a.mer", 16 + (PROBE_A - $030000), 16
soll_b
	.binary "daten/ebene_b.mer", 16 + (PROBE_B - $024000), 16
t_fehlt
	.text 13, "GRAFIK needs its data. Send first:", 13
	.text "  daten/bild.mer", 13
	.text "  daten/ebene_a.mer", 13
	.text "  daten/ebene_b.mer", 13, 0

alter_haken  .word 0
zeit         .word 0
tmp          .word 0
farbe        .byte 0
szene        .byte 0
