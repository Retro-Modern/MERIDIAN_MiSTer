;============================================================================
;  PALETTE - die Merkpalette (23.10.2026)
;
;  Die Palette von PINSEL laesst sich nur schreiben. SHINE und GRADIENT
;  schreiben ihre Farbe Zeile fuer Zeile hinein; schalten sie ab, muss die
;  Farbe wieder werden, was sie vorher war - nicht die Startfarbe, wenn ein
;  Programm sie mit PALETTE oder LOOK geaendert hat. Darum merkt sich das
;  System, was Programme setzen:
;
;   PAL_MERK     $FE:1600-$FE:17FF  256 Farben, je gggg bbbb / ---- rrrr
;   PAL_GUELTIG  $FE:15FF           0: es gelten die Startfarben (nach dem
;                                   Reset, LOOK 0); 1: PAL_MERK gilt
;
;  Schreiben: PALETTE (hier), LOOK (ws_look.asm kopiert die Palette der
;  Cartridge mit), LOOK 0 und der Reset (anzeige_zuruecksetzen) setzen
;  PAL_GUELTIG auf 0. Ohne Zusatzspeicher gelten immer die Startfarben.
;  Was ein Programm per POKE in die Palette schreibt, sieht hier niemand.
;
;  Einspruenge (JSL, Akku 8 Bit, Indexregister 16 Bit, jede Datenbank):
;   $FF:401E  pal_befehl     BASIC PALETTE n,r,g,b (Kern-Befehl 28): Werte
;                            in P_WERT_M, A = 0 gut, 1 Wert zu gross
;   $FF:4021  pal_gemerkt    A = Farbe -> X = ihr gemerkter Wert
;   $FF:4024  pal_zurueck    A = Farbe: gemerkten Wert nach PINSEL
;   $FF:4027  pal_glanz_aus  Glanzkanaele aus, jede Farbe in GL_TAB zurueck
;============================================================================

	.include "merkpalette.inc"  ; PAL_MERK, PAL_GUELTIG, GL_TAB

PL_PIDX    = $00C008            ; PINSEL: Index, gggg bbbb, ---- rrrr
PL_PLO     = $00C009
PL_PHI     = $00C00A
PL_GL_AN   = $00C04D            ; Glanzkanaele 0-7, 8-15 an
PL_BAENKE  = $000020            ; Kern: Baenke mit Speicher
PL_ANZ     = $000000 + P_ANZ_M
PL_WERT    = $000000 + P_WERT_M

pal_befehl
	.as
	.xl
	lda @l PL_ANZ
	cmp #4
	bne _f
	ldx #0                      ; alle Werte 0-255
-	lda @l PL_WERT+1,x
	ora @l PL_WERT+2,x
	bne _f
	inx
	inx
	inx
	cpx #12
	bne -
	lda @l PL_WERT+6            ; gruen nach oben ...
	asl a
	asl a
	asl a
	asl a
	sta @l PL_WERT+7            ; (Hilfsbyte, war 0)
	lda @l PL_WERT+3            ; rot
	and #$0f
	xba
	lda @l PL_WERT+9            ; ... blau nach unten
	and #$0f
	ora @l PL_WERT+7
	tax                         ; X = ---- rrrr / gggg bbbb (16 Bit)
	lda @l PL_WERT              ; n
	jsr pl_pinsel
	jsr pl_bereit               ; merken, wenn es geht
	bcc +
	lda @l PL_WERT              ; n (pl_pinsel hat A verbraucht)
	jsr pl_index                ; X = n * 2, A = Wert
	rep #$20
	.al
	sta @l PAL_MERK,x
	sep #$20
	.as
+	lda #0
	rtl
_f	lda #1
	rtl

pal_gemerkt                     ; A = Farbe -> X = Wert
	.as
	jsr pl_farbwert
	rtl

pal_zurueck                     ; A = Farbe: gemerkten Wert nach PINSEL
	.as
	pha
	jsr pl_farbwert
	pla
	jsr pl_pinsel
	rtl

pal_glanz_aus                   ; SHINE aus: Kanaele aus, Farben zurueck
	.as
	lda #0
	sta @l PL_GL_AN
	sta @l PL_GL_AN+1
	lda @l GL_TAB               ; Punkte (je 5 Byte, Farbe vorn)
	beq _ende
	ldx #1
_punkt
	pha
	phx
	lda @l GL_TAB,x
	pha
	jsr pl_farbwert
	pla
	jsr pl_pinsel
	rep #$20
	.al
	pla
	clc
	adc #5
	tax
	sep #$20
	.as
	pla
	dec a
	bne _punkt
_ende
	rtl

; A = Farbe, X = Wert: in die Palette von PINSEL
pl_pinsel
	.as
	sta @l PL_PIDX
	rep #$20
	.al
	txa
	sep #$20
	.as
	sta @l PL_PLO
	xba
	sta @l PL_PHI
	rts

; A = Farbe -> X = gemerkter Wert (Merkpalette oder Startfarbe)
pl_farbwert
	.as
	pha
	jsr pl_nutzbar
	pla
	php
	jsr pl_index                ; X = Farbe * 2, A 8 Bit
	plp
	rep #$20
	.al
	bcc +
	lda @l PAL_MERK,x
	bra ++
+	lda @l K_PALETTE,x
+	tax
	sep #$20
	.as
	rts

; A = Farbe -> X = Farbe * 2; A (16 Bit in B:A) = der X von vorher
pl_index
	.as
	rep #$20
	.al
	and #$00ff
	asl a
	phx
	tax
	pla                         ; der X von vorher (fuer pal_befehl: der Wert)
	sep #$20
	.as
	rts

; C = 1: der Zusatzspeicher ist da und PAL_MERK gilt
pl_nutzbar
	.as
	jsr pl_speicher
	bcc +
	lda @l PAL_GUELTIG
	cmp #1
	beq +                       ; C = 1
	clc
+	rts

; C = 1: Zusatzspeicher bis Bank $FE
pl_speicher
	.as
	rep #$20
	.al
	lda @l PL_BAENKE
	cmp #$ff
	sep #$20
	.as
	rts

; C = 1: PAL_MERK ist benutzbar - gilt sie noch nicht, kommen erst die
; Startfarben hinein. A bleibt.
pl_bereit
	.as
	pha
	jsr pl_speicher
	bcc _nein
	lda @l PAL_GUELTIG
	cmp #1
	beq _ja
	phx
	ldx #0
-	lda @l K_PALETTE,x
	sta @l PAL_MERK,x
	inx
	cpx #512
	bne -
	plx
	lda #1
	sta @l PAL_GUELTIG
_ja
	pla
	sec
	rts
_nein
	pla
	clc
	rts
