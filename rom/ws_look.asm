;============================================================================
;  WERKSTATT: LOOK - Palette, Leuchten und Tusche fuer das Spiel, dazu BASIC
;  LOOK (eingebunden von werkstatt.asm)
;
;  Die Cartridge haelt einen eigenen Look: alle 256 Farben, welche Farben
;  leuchten und wie stark, die Tusche (Farbe, Versatz, Schatten von Ebene B).
;  Im Reiter wirkt er sofort (das Gitter zeigt die Palette selbst, auch mit
;  Lichthof); beim Verlassen gelten wieder die Startfarben. BASIC LOOK holt
;  ihn ins Programm, dazu den Zeichensatz aus FONT; LOOK 0 stellt alles
;  zurueck.
;
;  Maus: Farbe im Gitter waehlen, R/G/B an den Balken setzen.
;  Tasten: G leuchten, +/- Staerke, I Tusche = diese Farbe, O Tusche aus,
;  Pfeile Versatz, B Schatten von Ebene B, D Farbe wie beim Start, X alles
;  wie beim Start, ,/. Farbe.
;============================================================================

KART_LOOK = KART+$4800          ; +0 geaendert (Bit 0 Look, Bit 1 Zeichensatz)
LK_STAERKE = KART_LOOK+1        ; Leuchten 0-15
LK_TINTE  = KART_LOOK+2         ; Tusche: Farbe (0 = aus), Versatz x, y,
LK_DX     = KART_LOOK+3         ;   Schatten von Ebene B
LK_DY     = KART_LOOK+4
LK_EBENE  = KART_LOOK+5
LK_MASKE  = KART_LOOK+16        ; 32 Byte: Bit = Farbe leuchtet
LK_PAL    = KART_LOOK+64        ; 256 Farben: gggg bbbb, ---- rrrr
LK_LAENGE = 64 + 512
PIN_PIDX  = $C008
PIN_PLO   = $C009
PIN_PHI   = $C00A
PIN_LM_IDX = $C050              ; (LM_DATEN $C051 zaehlt den Index weiter)

LX0 = 8                         ; Gitter 16 x 16 Felder zu 9 Punkten
LY0 = 24
LB_X = 184                      ; Balken R, G, B: 16 Stufen zu 8 Punkten
LB_Z = 5                        ; Textzeile von R (G, B darunter)

	.virtual W_RAM+$d0          ; Variablen von LOOK
lk_c      .byte ?               ; gewaehlte Farbe
lk_aktiv  .byte ?               ; der Reiter zeigt den Look der Cartridge
lk_t      .word ?
	.endv

;----------------------------------------------------------------------------
; Vorgaben der Cartridge (Kaltstart, LOAD): Startfarben, Zeichensatz des ROM

ws_vorgaben
	.as
	ldx #0
-	lda @l K_PALETTE,x
	sta @l LK_PAL,x
	inx
	cpx #512
	bne -
	ldx #0
-	lda @l K_ZEICHENSATZ,x
	sta @l KART_FONT,x
	inx
	cpx #2048
	bne -
	lda #2
	sta @l LK_DX
	sta @l LK_DY
	rts

; Look der Cartridge zeigen: Palette, Leuchten, Tusche (lange Adressen, geht
; mit jeder direkten Seite)
lk_zeigen
	.as
	stz PIN_PIDX
	ldx #0
-	lda @l LK_PAL,x
	sta PIN_PLO
	lda @l LK_PAL+1,x
	sta PIN_PHI
	inx
	inx
	cpx #512
	bne -
	stz PIN_LM_IDX
	ldx #0
-	lda @l LK_MASKE,x
	sta PIN_LM_IDX+1
	inx
	cpx #32
	bne -
	lda @l LK_STAERKE
	sta PIN_LEUCHT
lk_tusche                       ; nur die Tusche
	.as
	lda @l LK_TINTE
	beq _aus
	sta PIN_TUSCHE+1
	lda @l LK_DX
	sta PIN_TUSCHE+2
	lda @l LK_DY
	sta PIN_TUSCHE+3
	lda @l LK_EBENE
	beq +
	lda #4
+	ora #3
	sta PIN_TUSCHE
	rts
_aus
	stz PIN_TUSCHE
	rts

; Startfarben, kein Leuchten, keine Tusche
lk_standard
	.as
	stz PIN_PIDX
	ldx #0
-	lda @l K_PALETTE,x
	sta PIN_PLO
	lda @l K_PALETTE+1,x
	sta PIN_PHI
	inx
	inx
	cpx #512
	bne -
	stz PIN_LEUCHT
	stz PIN_LM_IDX
	ldx #32
-	stz PIN_LM_IDX+1
	dex
	bne -
	stz PIN_TUSCHE
	rts

lk_verlassen                    ; der Reiter geht: Startfarben
	.as
	lda lk_aktiv
	beq +
	stz lk_aktiv
	jsr lk_standard
+	rts

;----------------------------------------------------------------------------
; Reiter oeffnen

lk_zeichnen
	.as
	lda #1
	sta lk_aktiv
	jsr lk_zeigen
	#text 2, 1, F_TITEL, t_lk_palette
	#text 2, 42, F_TITEL, t_lk_farbe
	#text LB_Z, 42, F_GRUND, t_lk_r
	#text LB_Z+1, 42, F_GRUND, t_lk_g
	#text LB_Z+2, 42, F_GRUND, t_lk_b
	#text 15, 58, F_TITEL, t_lk_vor
	#text 26, 1, F_GRUND, t_lk_hilfe1
	#text 27, 1, F_GRUND, t_lk_hilfe2
	lda #$0f                    ; Farbe 0 ist in der Bitmap durchsichtig: dort
	sta SCHIRM+3*160+2*2+1      ; zeigt der Text sie als Hintergrund
	sta SCHIRM+3*160+3*2+1
	lda #0
-	pha                         ; das Gitter
	sta lk_t
	lda #0
	jsr lk_feld
	pla
	inc a
	bne -
	jsr lk_vorschau
	lda lk_c
	jsr lk_waehlen_a
	rts

t_lk_palette .null "PALETTE (the colours of your game)"
t_lk_farbe   .null "COLOUR"
t_lk_r       .null "R"
t_lk_g       .null "G"
t_lk_b       .null "B"
t_lk_vor     .null "PREVIEW"
t_lk_hilfe1  .null "Mouse: pick a colour, set R/G/B on the bars.  G glow  +- strength  I ink colour"
t_lk_hilfe2  .null "O ink off  Arrows ink offset  B shadow of layer B  D default  X all default  ,."

; Feld lk_t im Gitter: Rechteck in seiner Farbe (8 x 8), mit Rahmen in
; Farbe A, wenn A nicht 0 (sonst ohne)
lk_feld
	.as
	sta sp_c
	jsr lk_platz
	lda sp_c
	beq +
	#akku16
	dec sp_x
	dec sp_y
	lda #10
	sta sp_w
	sta sp_h
	#akku8
	jsr sp_rechteck
	#akku16
	inc sp_x
	inc sp_y
	#akku8
+	#akku16
	lda #8
	sta sp_w
	sta sp_h
	#akku8
	lda lk_t
	sta sp_c
	jmp sp_rechteck

lk_platz                        ; sp_x, sp_y des Feldes lk_t
	.as
	#akku16
	lda lk_t
	and #$000f
	sta sp_x
	asl a
	asl a
	asl a
	clc
	adc sp_x                    ; * 9
	adc #LX0
	sta sp_x
	lda lk_t
	and #$00f0
	lsr a
	lsr a
	lsr a
	lsr a
	sta sp_y
	asl a
	asl a
	asl a
	clc
	adc sp_y
	adc #LY0
	sta sp_y
	#akku8
	rts

; Farbe A waehlen: alten Rahmen weg, neuen zeichnen, Regler und Werte
lk_waehlen
	.as
	pha
	lda lk_c                    ; alter Rahmen: durchsichtig
	sta lk_t
	jsr lk_rahmen_weg
	pla
lk_waehlen_a
	.as
	sta lk_c
	sta lk_t
	lda #1                      ; weiss umrandet
	jsr lk_feld
lk_neu
	.as
	jsr lk_regler
	jmp lk_status

lk_rahmen_weg                   ; Rahmen um Feld lk_t loeschen (Farbe 0)
	.as
	jsr lk_platz
	#akku16
	dec sp_x
	dec sp_y
	lda #10
	sta sp_w
	sta sp_h
	#akku8
	stz sp_c
	jsr sp_rechteck
	lda #0
	jmp lk_feld

; die drei Balken der gewaehlten Farbe
lk_regler
	.as
	jsr lk_rgb                  ; lk_t = r, lk_t+1 = g, sp_fx = b
	lda lk_t
	ldy #LB_Z * 8 + 1
	ldx #2                      ; rot
	jsr lk_balken
	lda lk_t+1
	ldy #(LB_Z+1) * 8 + 1
	ldx #5                      ; gruen
	jsr lk_balken
	lda sp_fx
	ldy #(LB_Z+2) * 8 + 1
	ldx #14                     ; hellblau
lk_balken                       ; Wert A (0-15) als Balken in Zeile Y, Farbe X
	.as
	sta sp_fy
	stx sp_t
	#akku16
	sty sp_y
	lda #LB_X
	sta sp_x
	lda #16 * 8
	sta sp_w
	lda #6
	sta sp_h
	#akku8
	lda #B_RAHMEN
	sta sp_c
	jsr sp_rechteck
	#akku16
	lda sp_fy
	and #$000f
	inc a
	asl a
	asl a
	asl a
	sta sp_w
	#akku8
	lda sp_t
	sta sp_c
	jsr sp_rechteck
	lda sp_y                    ; Wert daneben: Zeile = y / 8
	lsr a
	lsr a
	lsr a
	#akku16
	and #$00ff
	asl a
	asl a
	sta sp_h
	asl a
	asl a
	clc
	adc sp_h                    ; * 20
	asl a
	asl a
	asl a                       ; * 160
	clc
	adc #78 * 2
	tax
	#akku8
	lda sp_fy
	jmp w_zahl2

; lk_t = rot, lk_t+1 = gruen, sp_fx = blau der gewaehlten Farbe; X = Platz
lk_rgb
	.as
	jsr lk_index
	lda @l LK_PAL+1,x
	and #$0f
	sta lk_t
	lda @l LK_PAL,x
	lsr a
	lsr a
	lsr a
	lsr a
	sta lk_t+1
	lda @l LK_PAL,x
	and #$0f
	sta sp_fx
	rts
lk_index                        ; X = lk_c * 2
	.as
	lda lk_c
	#akku16
	and #$00ff
	asl a
	tax
	#akku8
	rts

; gewaehlte Farbe in die Cartridge und gleich in die Palette
lk_setzen                       ; aus lk_t (r), lk_t+1 (g), sp_fx (b)
	.as
	jsr lk_index
	lda lk_t
	sta @l LK_PAL+1,x
	lda lk_t+1
	asl a
	asl a
	asl a
	asl a
	ora sp_fx
	sta @l LK_PAL,x
lk_eine                         ; Farbe lk_c aus der Cartridge in PINSEL
	.as
	jsr lk_index
	lda lk_c
	sta PIN_PIDX
	lda @l LK_PAL,x
	sta PIN_PLO
	lda @l LK_PAL+1,x
	sta PIN_PHI
lk_geaendert
	.as
	lda @l KART_LOOK
	ora #1
	sta @l KART_LOOK
	rts

; Vorschau: das zuletzt gemalte Muster doppelt mit Tusche vor einer Flaeche
lk_vorschau
	.as
	#akku16
	lda #232
	sta sp_x
	lda #128
	sta sp_y
	lda #80
	sta sp_w
	lda #56
	sta sp_h
	#akku8
	lda #15
	sta sp_c
	jsr sp_rechteck
	#akku16
	lda #248+32
	sta KOB_TAB+8
	lda #136+32
	sta KOB_TAB+10
	#akku8
	lda sp_art                  ; Muster: das zuletzt in SPRITES gemalte
	bne +
	lda sp_m
	bra ++
+	lda sp_merk
+	sta KOB_TAB+12
	#akku16
	and #$007f
	tax
	#akku8
	lda @l KART_BANK,x
	and #$0f
	ora #$80                    ; doppelt
	sta KOB_TAB+13
	lda #7                      ; an, Kontur, Schatten
	sta KOB_TAB+14
	rts

; Statuszeile
lk_status
	.as
	#text 29, 0, F_STATUS, t_lk_status
	lda lk_c
	ldx #29 * 160 + 8 * 2
	jsr w_zahl3
	lda lk_c                    ; leuchtet sie?
	jsr lk_bit
	and @l LK_MASKE,x
	beq +
	#text 29, 18, F_STATUS, t_lk_an
+	lda @l LK_STAERKE
	ldx #29 * 160 + 32 * 2
	jsr w_zahl2
	lda @l LK_TINTE
	beq +
	ldx #29 * 160 + 40 * 2
	jsr w_zahl3
+	lda @l LK_DX
	ldx #29 * 160 + 52 * 2
	jsr w_zahl1
	lda @l LK_DY
	ldx #29 * 160 + 54 * 2
	jsr w_zahl1
	lda @l LK_EBENE
	beq +
	#text 29, 65, F_STATUS, t_lk_an
+	rts
t_lk_status .null " COLOUR 000  GLOW off  strength 00  INK off  offset 0,0  layer B off            "
t_lk_an     .null "on "

lk_bit                          ; Farbe A: X = Byte in LK_MASKE, A = Bit
	.as
	pha
	lsr a
	lsr a
	lsr a
	#akku16
	and #$001f
	tax
	#akku8
	pla
	and #7
	sta lk_t+1
	lda #1
-	dec lk_t+1
	bmi +
	asl a
	bra -
+	rts

;----------------------------------------------------------------------------
; Je Bild: Maus und Tasten (Taste in A, 0 = keine)

lk_takt
	.as
	cmp #0
	beq +
	jsr lk_taste
+	lda w_mt
	and #$01
	bne +
	rts
+	#akku16
	lda w_mx                    ; Gitter?
	sec
	sbc #LX0
	cmp #16 * 9
	bcs _balken
	ldx #0
-	cmp #9
	bcc +
	sbc #9
	inx
	bra -
+	stx lk_t
	lda w_my
	sec
	sbc #LY0
	cmp #16 * 9
	bcs _nichts
	ldx #0
-	cmp #9
	bcc +
	sbc #9
	inx
	bra -
+	txa
	asl a
	asl a
	asl a
	asl a
	ora lk_t
	#akku8
	cmp lk_c
	beq +
	jmp lk_waehlen
+	rts
_balken
	.al
	lda w_mx
	sec
	sbc #LB_X
	cmp #16 * 8
	bcs _nichts
	lsr a
	lsr a
	lsr a
	sta lk_t+1                  ; (Wert, 16 Bit unschaedlich)
	lda w_my
	sec
	sbc #LB_Z * 8
	cmp #3 * 8
	bcs _nichts
	lsr a
	lsr a
	lsr a
	#akku8
	pha                         ; 0 R, 1 G, 2 B
	lda lk_t+1
	pha
	jsr lk_rgb
	pla
	sta sp_fy
	pla
	beq _r
	cmp #1
	beq _g
	lda sp_fy
	sta sp_fx
	bra _setzen
_r
	lda sp_fy
	sta lk_t
	bra _setzen
_g
	lda sp_fy
	sta lk_t+1
_setzen
	jsr lk_setzen
	jmp lk_neu
_nichts
	#akku8
	rts

;----------------------------------------------------------------------------
; Tasten

lk_taste
	.as
	cmp #'+'
	bne +
	lda @l LK_STAERKE
	inc a
	cmp #16
	bcc _staerke
	lda #15
	bra _staerke
+	cmp #'-'
	bne +
	lda @l LK_STAERKE
	beq _staerke
	dec a
_staerke
	sta @l LK_STAERKE
	sta PIN_LEUCHT
	bra _fertig
+	cmp #','
	bne +
	lda lk_c
	dec a
	jmp lk_waehlen
+	cmp #'.'
	bne +
	lda lk_c
	inc a
	jmp lk_waehlen
+	cmp #$1c                    ; Pfeile: Versatz der Tusche
	bcc _buchstabe
	cmp #$20
	bcs _buchstabe
	ldx #0                      ; X: 0 dx, 1 dy; Y: +1 / -1
	ldy #1
	cmp #$1c
	beq _versatz
	ldy #$ffff
	cmp #$1d
	beq _versatz
	ldx #1
	cmp #$1e                    ; hoch: dy kleiner
	beq _versatz
	ldy #1
_versatz
	tya
	clc
	adc @l LK_DX,x
	cmp #8                      ; dx 0-7, dy 1-7
	bcs _fertig
	cpx #0
	beq +
	cmp #0
	beq _fertig
+	sta @l LK_DX,x
	jsr lk_tusche
	bra _fertig
_buchstabe
	and #$df
	cmp #'G'
	bne +
	lda lk_c                    ; leuchten an/aus
	jsr lk_bit
	eor @l LK_MASKE,x
	sta @l LK_MASKE,x
	pha
	txa
	sta PIN_LM_IDX
	pla
	sta PIN_LM_IDX+1
	bra _fertig
+	cmp #'I'
	bne +
	lda lk_c
	sta @l LK_TINTE
	jsr lk_tusche
	bra _fertig
+	cmp #'O'
	bne +
	lda #0
	sta @l LK_TINTE
	jsr lk_tusche
	bra _fertig
+	cmp #'B'
	bne +
	lda @l LK_EBENE
	eor #1
	sta @l LK_EBENE
	jsr lk_tusche
	bra _fertig
+	cmp #'D'
	bne +
	jsr lk_index                ; Farbe wie beim Start
	lda @l K_PALETTE,x
	sta @l LK_PAL,x
	lda @l K_PALETTE+1,x
	sta @l LK_PAL+1,x
	jsr lk_eine
	jmp lk_neu
+	cmp #'X'
	bne _nichts
	jsr ws_vorgaben_look        ; alles wie beim Start
	jsr lk_zeigen
	jmp lk_neu
_fertig
	jsr lk_geaendert
	jmp lk_status
_nichts
	rts

ws_vorgaben_look                ; Look wie beim Start (der Zeichensatz bleibt)
	.as
	ldx #0
-	lda @l K_PALETTE,x
	sta @l LK_PAL,x
	inx
	cpx #512
	bne -
	ldx #63
	lda #0
-	sta @l KART_LOOK,x
	dex
	bne -
	lda @l KART_LOOK            ; nur noch der Zeichensatz zaehlt als geaendert
	and #2
	sta @l KART_LOOK
	lda #2
	sta @l LK_DX
	sta @l LK_DY
	rts

;----------------------------------------------------------------------------
; BASIC: LOOK [n] (ueber ws_basic, A = 7; D = 0). Ohne n oder n nicht 0: der
; Look der Cartridge und ihr Zeichensatz gelten; LOOK 0: Startfarben, kein
; Leuchten, keine Tusche, Zeichensatz des ROM.

	.dpage 0
wb_look
	.as
	lda P_ANZ
	beq _an
	lda P_WERT
	ora P_WERT+1
	ora P_WERT+2
	bne _an
	jsr lk_standard
	ldx #0
-	lda @l K_ZEICHENSATZ,x
	sta ZEICHEN,x
	inx
	cpx #2048
	bne -
	lda #0
	rtl
_an
	jsr lk_zeigen
	ldx #0
-	lda @l KART_FONT,x
	sta ZEICHEN,x
	inx
	cpx #2048
	bne -
	lda #0
	rtl

	.dpage W_RAM
