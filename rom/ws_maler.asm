;============================================================================
;  WERKSTATT: der Maler fuer SPRITES (16x16, 128 Muster), TILES (8x8,
;  256 Kacheln) und FONT (8x8, 256 Zeichen, 1 Bit) - eingebunden von
;  werkstatt.asm
;
;  Das Bild liegt beim Malen entpackt in SP_PUF (ein Byte je Pixel, 0-15,
;  Zeile y ab y*16). Jede Aenderung geht zeilenweise zurueck an ihren Platz:
;  Muster in die Cartridge (und sofort nach KOBOLD), Kacheln ins Chip-RAM
;  $03:4000 (dort liest PINSEL sie fuer MAP), Zeichen in die Cartridge
;  (BASIC LOOK holt sie in den Zeichensatz).
;
;  Maus: links malen (Stift) bzw. fuellen, rechts Farbe aufnehmen; Klick auf
;  ein Farbfeld waehlt die Farbe, auf den Bogen das Muster bzw. die Kachel.
;  Tasten: D zeichnen, F fuellen, H/V spiegeln, R drehen, Pfeile schieben,
;  C kopieren, P einfuegen, X leeren, U zurueck, 0-9 Farbe, +/- Bank,
;  ,/. voriges/naechstes.
;============================================================================

SP_PUF    = W_RAM+$200          ; 256 Byte: das Bild entpackt
SP_UNDO   = W_RAM+$300          ; 256 Byte: vor der letzten Aenderung
SP_KLAU   = W_RAM+$400          ; 256 Byte: Zwischenablage
SP_HILF   = W_RAM+$500          ; 256 Byte: Drehen, Fuellen (Stapel)
KART_BANK = KART+$4000          ; je Muster die Bank, in der es gemalt wurde
KART_KBANK = KART+$4200         ; je Kachel die Bank (256)
KACHELN   = $034000             ; 256 Kacheln zu 32 Byte (PINSEL: 8 Zeilen zu 4 Byte)
KART_FONT = KART+$C000          ; 256 Zeichen zu 8 Byte (Bit 7 links)
KART_FBANK = KART+$4600         ; je Zeichen eine Bank (nur fuer die Anzeige)

; Lage auf dem Schirm (Bitmap-Punkte)
GX0 = 8                         ; Malflaeche: 16 x 7 = 8 x 14 Punkte
GY0 = 16
VX0 = 192                       ; Vorschau 64 x 48
VY0 = 24
FX0 = 266                       ; Farbfelder 4 x 4 zu 12 Punkten
FY0 = 34
BX0 = 8                         ; Bogen (die Bitmap nur bis Zeile 204 benutzen:
BY0 = 164                       ; 16-Bit-Versatz)

; Farben in der Bitmap (Palettenindex)
B_FELD1 = 145                   ; Schachbrett fuer durchsichtig (indigo 1/2)
B_FELD2 = 146
B_RAHMEN = 147
B_GRUND  = 144

	.virtual W_RAM+$80          ; Variablen des Malers (bleiben bis zum naechsten Besuch)
sp_m      .byte ?               ; Muster bzw. Kachel
sp_f      .byte ?               ; Farbe 0-15
sp_b      .byte ?               ; Bank 0-15
sp_wz     .byte ?               ; Werkzeug: 0 zeichnen, 1 fuellen
sp_px     .byte ?               ; Feld unter der Maus ($ff = keins)
sp_py     .byte ?
sp_t      .word ?
sp_u      .word ?
sp_x      .word ?               ; Rechteck: x, y, Breite, Hoehe, Farbe
sp_y      .word ?
sp_w      .word ?
sp_h      .word ?
sp_c      .byte ?
sp_fx     .byte ?               ; Feld fuer sp_feld
sp_fy     .byte ?
sp_lx     .byte ?               ; zuletzt gemaltes Feld (Strich)
sp_ly     .byte ?
sp_zx     .byte ?               ; Ziel des Strichs
sp_zy     .byte ?
sp_geaendert .byte ?
sp_art    .word ?               ; 0 Sprites, 1 Kacheln, 2 Zeichen (Wort: ldx sp_art geht)
sp_n      .byte ?               ; Pixel je Seite (16 / 8)
sp_merk   .fill 3               ; zuletzt bearbeitet je Art (das aktuelle steht in sp_m)
	.endv

;----------------------------------------------------------------------------
; Reiter oeffnen

sp_zeichnen                     ; SPRITES
	.as
	lda #0
	jsr sp_wahl
	bra sp_oeffnen

ki_zeichnen                     ; TILES
	.as
	jsr ki_wahl
	lda sp_m                    ; Kachel 0 bleibt leer: mit 1 anfangen
	bne sp_oeffnen
	inc sp_m
	bra sp_oeffnen

zs_zeichnen                     ; FONT
	.as
	lda #2
	jsr sp_wahl
	lda #1                      ; Zeichen kennen nur 0 und 1: mit 1 malen
	sta sp_f
	bra sp_oeffnen

ki_wahl                         ; auf Kacheln umstellen (TILES, MAP)
	.as
	lda #1

sp_wahl                         ; auf Art A umstellen
	.as
	pha
	ldx sp_art                  ; das bisherige merken
	lda sp_m
	sta sp_merk,x
	pla
	sta sp_art
	stz sp_art+1
	ldx sp_art
	lda sp_merk,x
	sta sp_m
	lda #8
	cpx #0
	bne +
	lda #16
+	sta sp_n
	rts

sp_oeffnen
	.as
	#text 2, 33, F_TITEL, t_sp_wz
	#text 2, 47, F_TITEL, t_sp_vor
	#text 2, 66, F_TITEL, t_sp_farben
	lda sp_art
	bne +
	#text 19, 1, F_TITEL, t_sp_bogen
	bra _hilfe
+	cmp #2
	beq +
	#text 19, 1, F_TITEL, t_ki_bogen
	bra _hilfe
+	#text 19, 1, F_TITEL, t_zs_bogen
_hilfe
	#text 26, 1, F_GRUND, t_sp_hilfe1
	#text 27, 1, F_GRUND, t_sp_hilfe2
	jsr sp_laden
	jmp sp_alles

t_sp_wz      .null "TOOLS"
t_sp_vor     .null "PREVIEW"
t_sp_farben  .null "COLOURS"
t_sp_bogen   .null "PATTERNS"
t_ki_bogen   .null "TILES   "
t_zs_bogen   .null "FONT    "
t_sp_hilfe1  .null "Mouse: left paint, right pick colour.  D draw  F fill  H/V flip  R rotate"
t_sp_hilfe2  .null "Arrows shift  C copy  P paste  X clear  U undo  0-9 colour  +- bank  ,. pick"

; alles neu: Werkzeuge, Malflaeche, Farben, Bogen, Vorschau, Status
sp_alles
	.as
	jsr sp_werkzeuge
	jsr sp_gitter
	jsr sp_farbfelder
	jsr sp_bogen
	jsr sp_vorschau
	jmp sp_status

; Werkzeugliste (Zeilen 3-4), das aktive hervorgehoben
sp_werkzeuge
	.as
	lda sp_wz
	bne +
	#text 3, 33, F_AKTIV, t_sp_w0
	#text 4, 33, F_GRUND, t_sp_w1
	rts
+	#text 3, 33, F_GRUND, t_sp_w0
	#text 4, 33, F_AKTIV, t_sp_w1
	rts
t_sp_w0 .null " D draw "
t_sp_w1 .null " F fill "

;----------------------------------------------------------------------------
; Bild <-> Puffer

; Versatz von Bild sp_m in seiner Ablage -> sp_t (Muster * 128, Kachel * 32)
sp_versatz                      ; (Zeichen * 8, Kachel * 32, Muster * 128)
	.as
	#akku16
	lda sp_m
	and #$00ff
	asl a
	asl a
	asl a                       ; * 8
	ldx sp_art
	cpx #2
	beq +
	asl a
	asl a                       ; * 32
	cpx #0
	bne +
	asl a
	asl a                       ; * 128
+	sta sp_t
	#akku8
	rts

sp_lies                         ; A = Byte X der Ablage
	.as
	lda sp_art
	beq _muster
	cmp #2
	beq _zeichen
	lda @l KACHELN,x
	rts
_muster
	lda @l KART_MUSTER,x
	rts
_zeichen
	lda @l KART_FONT,x
	rts

sp_schreib                      ; Byte X der Ablage = A (Muster auch nach KOBOLD)
	.as
	pha
	lda sp_art
	beq _muster
	cmp #2
	beq _zeichen
	pla
	sta @l KACHELN,x
	rts
_muster
	pla
	sta @l KART_MUSTER,x
	sta KOB_TAB+$102            ; MDATEN (MADR steht)
	rts
_zeichen
	pla
	sta @l KART_FONT,x
	rts

sp_bank_index                   ; X = Platz der Bank von Bild sp_m in der Cartridge
	.as
	#akku16
	lda sp_m
	and #$00ff
	tax
	#akku8
	lda sp_art
	beq +
	cmp #2
	#akku16
	txa
	bcs _zeichen
	adc #KART_KBANK - KART_BANK  ; (Carry geloescht)
	bra _x
_zeichen
	clc
	adc #KART_FBANK - KART_BANK
_x
	tax
	#akku8
+	rts

sp_laden                        ; Bild sp_m entpacken, Bank holen
	.as
	jsr sp_versatz
	ldx sp_t
	ldy #0
	lda sp_art
	cmp #2
	bne _zeile
_bits                           ; Zeichen: 8 Zeilen zu 1 Byte, Bit 7 links
	jsr sp_lies
	sta sp_u
	lda #8
	sta sp_u+1
-	asl sp_u
	lda #0
	rol a
	sta SP_PUF,y
	iny
	dec sp_u+1
	bne -
	#akku16
	tya
	clc
	adc #8
	tay
	#akku8
	inx
	cpy #8 * 16
	bne _bits
	bra _bank
_zeile
	lda sp_n
	lsr a
	sta sp_u                    ; Bytes je Zeile
-	jsr sp_lies
	pha
	lsr a
	lsr a
	lsr a
	lsr a
	sta SP_PUF,y
	pla
	and #$0f
	sta SP_PUF+1,y
	inx
	iny
	iny
	dec sp_u
	bne -
	#akku16                     ; zur naechsten Pufferzeile (Abstand 16)
	tya
	clc
	adc #15
	and #$fff0
	tay
	lsr a
	lsr a
	lsr a
	lsr a
	#akku8
	cmp sp_n
	bne _zeile
_bank
	jsr sp_bank_index
	lda @l KART_BANK,x
	and #$0f
	sta sp_b
	rts

; Zeile A des Puffers packen und an ihren Platz
sp_zeile_schreiben
	.as
	pha
	jsr sp_versatz
	lda sp_art
	cmp #2
	beq _zeichen
	pla
	pha
	#akku16
	and #$000f
	asl a
	asl a                       ; Zeile * 4 (Kachel)
	ldx sp_art
	bne +
	asl a                       ; Zeile * 8 (Muster)
+	clc
	adc sp_t
	tax                         ; Versatz = auch die KOBOLD-Adresse
	#akku8
	sta KOB_TAB+$100            ; MADR (nur fuer Muster von Belang)
	xba
	sta KOB_TAB+$101
	pla
	#akku16
	and #$000f
	asl a
	asl a
	asl a
	asl a                       ; Zeile * 16 im Puffer
	tay
	#akku8
	lda sp_n
	lsr a
	sta sp_u
-	lda SP_PUF,y
	asl a
	asl a
	asl a
	asl a
	ora SP_PUF+1,y
	jsr sp_schreib
	inx
	iny
	iny
	dec sp_u
	bne -
	rts
_zeichen                        ; 8 Punkte -> 1 Byte (gesetzt: nicht 0)
	pla
	#akku16
	and #$000f
	pha
	clc
	adc sp_t
	tax
	pla
	asl a
	asl a
	asl a
	asl a
	tay
	#akku8
	stz sp_u
	lda #8
	sta sp_u+1
-	lda SP_PUF,y
	cmp #1                      ; Carry: Punkt gesetzt
	rol sp_u
	iny
	dec sp_u+1
	bne -
	lda sp_u
	jsr sp_schreib
	lda @l KART_LOOK            ; der Zeichensatz ist geaendert
	ora #2
	sta @l KART_LOOK
	rts

sp_alles_schreiben              ; alle Zeilen
	.as
	lda #0
-	pha
	jsr sp_zeile_schreiben
	pla
	inc a
	cmp sp_n
	bne -
	rts

sp_merken                       ; vor einer Aenderung: Puffer -> SP_UNDO
	.as
	ldx #0
-	lda SP_PUF,x
	sta SP_UNDO,x
	inx
	cpx #256
	bne -
	rts

;----------------------------------------------------------------------------
; Zeichnen in die Bitmap

; Rechteck sp_x, sp_y, sp_w, sp_h in Farbe sp_c (KRAN fuellt)
sp_rechteck
	.as
	#akku16
	lda sp_y                    ; Ziel = BILD + y * 320 + x (y < 204)
	asl a
	asl a
	clc
	adc sp_y                    ; y * 5
	asl a
	asl a
	asl a
	asl a
	asl a
	asl a                       ; * 64 = y * 320
	clc
	adc sp_x
	sta KRAN_REG+3
	lda sp_w
	sta KRAN_REG+6
	lda sp_h
	sta KRAN_REG+8
	lda #320
	sta KRAN_REG+12
	stz KRAN_REG+10
	#akku8
	lda #`BILD
	sta KRAN_REG+5
	lda sp_c
	sta KRAN_REG+14
	lda #1                      ; fuellen
	sta KRAN_REG+15
	lda #$08
	sta KRAN_BEF
	lda #$01
	sta KRAN_BEF
-	lda KRAN_BEF
	and #$01
	bne -
	rts

; Farbe fuer Pixelwert A in der Bank sp_b (0 = durchsichtig: Y gerade/ungerade
; waehlt das Schachbrett)
sp_pixelfarbe
	.as
	cmp #0
	beq +
	sta sp_c
	lda sp_b
	asl a
	asl a
	asl a
	asl a
	ora sp_c
	sta sp_c
	rts
+	lda #B_FELD1
	sta sp_c
	tya
	and #1
	beq +
	inc sp_c
+	rts

; Feldgroesse auf dem Schirm: 7 (Muster) bzw. 14 (Kachel)
sp_feldmal                      ; A (16 Bit) = Feld * Feldgroesse
	.al
	sta sp_t
	asl a
	asl a
	asl a
	sec
	sbc sp_t                    ; * 7
	ldx sp_art
	beq +
	asl a                       ; * 14
+	rts

; Feld sp_fx, sp_fy der Malflaeche zeichnen
sp_feld
	.as
	lda sp_fy
	asl a
	asl a
	asl a
	asl a
	ora sp_fx
	#akku16
	and #$00ff
	tax                         ; Pixel im Puffer
	#akku8
	lda sp_fx                   ; Schachbrett: (x + y) gerade?
	clc
	adc sp_fy
	#akku16
	and #$0001
	tay
	#akku8
	lda SP_PUF,x
	jsr sp_pixelfarbe
	#akku16
	lda sp_fx
	and #$00ff
	jsr sp_feldmal
	clc
	adc #GX0
	sta sp_x
	lda sp_fy
	and #$00ff
	jsr sp_feldmal
	clc
	adc #GY0
	sta sp_y
	lda #1
	jsr sp_feldmal              ; Feldgroesse - 1 Punkt Fuge
	dec a
	sta sp_w
	sta sp_h
	#akku8
	jmp sp_rechteck

sp_gitter                       ; die ganze Malflaeche
	.as
	#akku16
	lda #GX0-2
	sta sp_x
	lda #GY0-2
	sta sp_y
	lda #16*7+3
	sta sp_w
	sta sp_h
	#akku8
	lda #B_RAHMEN
	sta sp_c
	jsr sp_rechteck
	stz sp_fy
-	stz sp_fx
-	jsr sp_feld
	inc sp_fx
	lda sp_fx
	cmp sp_n
	bne -
	inc sp_fy
	lda sp_fy
	cmp sp_n
	bne --
	rts

; Farbfelder der Bank (16), das gewaehlte mit Rahmen
sp_farbfelder
	.as
	#akku16
	lda #FX0-2
	sta sp_x
	lda #FY0-2
	sta sp_y
	lda #4*12+2
	sta sp_w
	sta sp_h
	#akku8
	lda #B_GRUND
	sta sp_c
	jsr sp_rechteck
	ldy #0
_feld
	phy
	#akku16
	tya
	and #$0003
	sta sp_t
	asl a
	clc
	adc sp_t
	asl a
	asl a                       ; (i mod 4) * 12
	clc
	adc #FX0
	sta sp_x
	tya
	and #$000c
	sta sp_t
	asl a
	clc
	adc sp_t                    ; (i div 4) * 12
	clc
	adc #FY0
	sta sp_y
	lda #10
	sta sp_w
	sta sp_h
	#akku8
	pla
	pha
	cmp sp_f                    ; gewaehlt: weisser Rahmen
	bne +
	#akku16
	dec sp_x
	dec sp_y
	lda #12
	sta sp_w
	sta sp_h
	#akku8
	lda #1
	sta sp_c
	jsr sp_rechteck
	#akku16
	inc sp_x
	inc sp_y
	lda #10
	sta sp_w
	sta sp_h
	#akku8
+	pla
	pha
	ldy #0
	jsr sp_pixelfarbe
	jsr sp_rechteck
	ply
	iny
	cpy #16
	bne _feld
	#text 11, 66, F_GRUND, t_sp_bank
	lda sp_b
	ldx #11 * 160 + 71 * 2
	jsr w_zahl2
	rts
t_sp_bank .null "bank   "

; Bogen: die Seite mit dem aktuellen Bild. Muster: 2 x 16 zu 19 Punkten,
; Kacheln: 2 x 32 zu 9 Punkten - je Seite 32 bzw. 64, vier Seiten.
sp_seite_maske                  ; A = Maske fuer den Seitenanfang
	.as
	lda sp_art
	bne +
	lda #$60
	rts
+	lda #$c0
	rts

sp_bogen
	.as
	jsr sp_seite_maske
	and sp_m
	sta sp_u                    ; erstes Bild der Seite
	#text 19, 10, F_GRUND, t_sp_seite
	lda sp_u                    ; Seite: Muster Bits 5-6, Kacheln Bits 6-7
	lsr a
	lsr a
	lsr a
	lsr a
	lsr a
	ldx sp_art
	beq +
	lsr a
+	inc a
	ldx #19 * 160 + 15 * 2
	jsr w_zahl1
	#akku16                     ; Grund
	lda #BX0-2
	sta sp_x
	lda #BY0-2
	sta sp_y
	lda #16*19+2
	sta sp_w
	lda #2*19+2
	sta sp_h
	#akku8
	lda #B_GRUND
	sta sp_c
	jsr sp_rechteck
	stz sp_u+1                  ; Nummer auf der Seite
_bild
	jsr sp_bogen_platz
	jsr sp_bild_klein
	inc sp_u+1
	lda sp_u+1
	ldx sp_art
	bne _kacheln
	cmp #32
	bne _bild
	bra sp_bogen_eins
_kacheln
	cmp #64
	bne _bild

sp_bogen_eins                   ; das aktuelle Bild auf Gelb neu
	.as
	jsr sp_seite_maske
	and sp_m
	sta sp_u
	eor sp_m
	sta sp_u+1
	jsr sp_bogen_platz
	#akku16
	lda sp_n
	and #$00ff
	inc a
	inc a
	sta sp_w
	sta sp_h
	#akku8
	lda #7
	sta sp_c
	jsr sp_rechteck
	jmp sp_bild_klein

t_sp_seite .null "page  /4"

; Rahmen des Bildes Nummer sp_u+1 auf der Seite -> sp_x, sp_y
sp_bogen_platz
	.as
	#akku16
	lda sp_u+1
	and #$001f
	ldx sp_art
	bne _kachel
	and #$000f                  ; Muster: Spalte * 19
	sta sp_t
	asl a
	asl a
	asl a
	asl a
	clc
	adc sp_t
	clc
	adc sp_t
	clc
	adc sp_t
	clc
	adc #BX0-1
	sta sp_x
	lda #BY0-1
	sta sp_y
	lda sp_u+1
	and #$0010
	beq +
	lda #BY0-1+19
	sta sp_y
+	#akku8
	rts
_kachel
	.al
	sta sp_t                    ; Kachel: Spalte * 9
	asl a
	asl a
	asl a
	clc
	adc sp_t
	clc
	adc #BX0-1
	sta sp_x
	lda #BY0-1
	sta sp_y
	lda sp_u+1
	and #$0020
	beq +
	lda #BY0-1+11
	sta sp_y
+	#akku8
	rts

; Bild (sp_u + sp_u+1) klein bei sp_x+1, sp_y+1 (Pixel fuer Pixel)
sp_bild_klein
	.as
	lda sp_m                    ; Bank und Versatz dieses Bildes
	pha
	lda sp_b
	pha
	lda sp_u
	clc
	adc sp_u+1
	sta sp_m
	jsr sp_bank_index
	lda @l KART_BANK,x
	and #$0f
	sta sp_b
	jsr sp_versatz
	#akku16
	lda sp_y                    ; Ziel: BILD + (y+1) * 320 + x + 1
	inc a
	asl a
	asl a
	clc
	adc sp_y
	inc a
	asl a
	asl a
	asl a
	asl a
	asl a
	asl a
	clc
	adc sp_x
	inc a
	tay
	#akku8
	ldx sp_t
	lda sp_n
	sta sp_w                    ; Zeilen
_zeile
	lda sp_art
	cmp #2
	bne +
	jsr sp_lies                 ; Zeichen: 8 Bits (sp_zx/zy sind hier frei)
	sta sp_zx
	lda #8
	sta sp_zy
-	asl sp_zx
	lda #0
	rol a
	jsr _punkt
	dec sp_zy
	bne -
	inx
	bra _weiter
+	lda sp_n
	lsr a
	sta sp_w+1                  ; Bytes
_byte
	jsr sp_lies
	pha
	lsr a
	lsr a
	lsr a
	lsr a
	jsr _punkt
	pla
	and #$0f
	jsr _punkt
	inx
	dec sp_w+1
	bne _byte
_weiter
	#akku16
	lda sp_n
	and #$00ff
	eor #$ffff
	sec
	adc #320                    ; 320 - n
	sta sp_h
	tya
	clc
	adc sp_h
	tay
	#akku8
	dec sp_w
	bne _zeile
	pla
	sta sp_b
	pla
	sta sp_m
	jmp sp_versatz
_punkt                          ; Pixelwert A nach BILD+Y, Y weiter
	beq +
	sta sp_c
	lda sp_b
	asl a
	asl a
	asl a
	asl a
	ora sp_c
	phx
	tyx
	sta @l BILD,x
	plx
+	iny
	rts

; Vorschau. Muster: Sprite 1 einfach, Sprite 2 doppelt mit Kontur (Tusche).
; Kachel: 8 x 6-mal nebeneinander (zeigt, ob sie nahtlos passt).
sp_vorschau
	.as
	#akku16
	lda #VX0
	sta sp_x
	lda #VY0
	sta sp_y
	lda #64
	sta sp_w
	lda #48
	sta sp_h
	#akku8
	lda #B_GRUND
	sta sp_c
	jsr sp_rechteck
	lda sp_art
	beq ++
	cmp #2
	bne +
	jmp sp_vorschau_zeichen
+	jmp sp_vorschau_kachel
+	#akku16
	lda #VX0+8+32               ; Sprite 1: 1x
	sta KOB_TAB+8
	lda #VY0+16+32
	sta KOB_TAB+10
	lda #VX0+28+32              ; Sprite 2: 2x
	sta KOB_TAB+16
	lda #VY0+8+32
	sta KOB_TAB+18
	#akku8
	lda sp_m
	sta KOB_TAB+12
	sta KOB_TAB+20
	lda sp_b
	sta KOB_TAB+13
	ora #$80
	sta KOB_TAB+21
	lda #1
	sta KOB_TAB+14
	lda #3                      ; an + Kontur
	sta KOB_TAB+22
	lda #1                      ; Tusche: Kontur an, Tinte indigo 0
	sta PIN_TUSCHE
	lda #144
	sta PIN_TUSCHE+1
	#text 10, 48, F_GRUND, t_sp_vor2
	rts
t_sp_vor2 .null "1x   2x + ink"
t_ki_vor2 .null "tiled 8 x 6  "

; Zeichen: ein Probetext aus dem Zeichensatz der Cartridge, 8 x 6 Zeichen
sp_vorschau_zeichen
	.as
	stz KOB_TAB+14              ; keine Vorschau-Sprites
	stz KOB_TAB+22
	stz sp_fy                   ; Zeichen 0-47
_zeichen
	lda sp_fy                   ; Ziel: Zeile * 8 * 320 + Spalte * 8
	lsr a
	lsr a
	lsr a
	#akku16
	and #$00ff
	xba                         ; * 256
	sta sp_h
	lsr a
	lsr a                       ; * 64
	clc
	adc sp_h                    ; * 320 (eine Zeichenzeile hoch: * 8)
	asl a
	asl a
	asl a
	sta sp_h
	lda sp_fy
	and #$0007
	asl a
	asl a
	asl a
	clc
	adc sp_h
	adc #VY0 * 320 + VX0
	tay
	lda sp_fy                   ; Zeichen -> Versatz im Zeichensatz
	and #$00ff
	tax
	lda @l t_zs_probe,x
	and #$00ff
	asl a
	asl a
	asl a
	tax
	#akku8
	lda #8
	sta sp_zy
_zeile
	lda @l KART_FONT,x
	sta sp_zx
	lda #8
	sta sp_c
-	asl sp_zx
	bcc +
	lda #1                      ; weiss
	phx
	tyx
	sta @l BILD,x
	plx
+	iny
	dec sp_c
	bne -
	#akku16
	tya
	clc
	adc #320 - 8
	tay
	#akku8
	inx
	dec sp_zy
	bne _zeile
	inc sp_fy
	lda sp_fy
	cmp #48
	bne _zeichen
	#text 10, 48, F_GRUND, t_zs_vor2
	rts
t_zs_probe .text "MERIDIAN", "816 font", "AaBbCcDd", "0123456!", "for x=1:", "?(y+z)*2"
t_zs_vor2  .null "with this font"

sp_vorschau_kachel
	.as
	stz KOB_TAB+14              ; keine Vorschau-Sprites
	stz KOB_TAB+22
	#akku16                     ; Zeile fuer Zeile: Pixel (x mod 8, y mod 8)
	lda #VY0*320+VX0
	sta sp_h                    ; Ziel der Zeile
	#akku8
	stz sp_fy
_zeile
	ldy sp_h
	stz sp_fx
_punkt
	lda sp_fy
	and #7
	asl a
	asl a
	asl a
	asl a
	sta sp_t
	lda sp_fx
	and #7
	ora sp_t
	#akku16
	and #$00ff
	tax
	#akku8
	lda SP_PUF,x
	beq +
	sta sp_c
	lda sp_b
	asl a
	asl a
	asl a
	asl a
	ora sp_c
	tyx
	sta @l BILD,x
+	iny
	inc sp_fx
	lda sp_fx
	cmp #64
	bne _punkt
	#akku16
	lda sp_h
	clc
	adc #320
	sta sp_h
	#akku8
	inc sp_fy
	lda sp_fy
	cmp #48
	bne _zeile
	#text 10, 48, F_GRUND, t_ki_vor2
	rts

; C = 1: Kachel 0 - sie bleibt leer (leere Karten bestehen aus ihr; A bleibt)
sp_gesperrt
	.as
	pha
	lda sp_art
	cmp #1
	bne +
	lda sp_m
	bne +
	pla
	sec
	rts
+	pla
	clc
	rts

sp_farbe_setzen                 ; sp_f = A (Zeichen: nur 0 und 1), Farbfelder neu
	.as
	ldx sp_art
	cpx #2
	bne +
	cmp #0
	beq +
	lda #1
+	sta sp_f
	jmp sp_farbfelder

; Statuszeile
sp_status
	.as
	lda sp_art
	bne +
	#text 29, 0, F_STATUS, t_sp_status
	bra _werte
+	cmp #2
	bne +
	#text 29, 0, F_STATUS, t_zs_status
	bra _werte
+	jsr sp_gesperrt
	bcs +
	#text 29, 0, F_STATUS, t_ki_status
	bra _werte
+	#text 29, 0, F_STATUS, t_ki_null
_werte
	lda sp_m
	ldx #29 * 160 + 9 * 2
	jsr w_zahl3
	lda sp_b
	ldx #29 * 160 + 19 * 2
	jsr w_zahl2
	lda sp_f
	ldx #29 * 160 + 31 * 2
	jsr w_zahl2
	lda sp_px
	bmi +
	ldx #29 * 160 + 37 * 2
	jsr w_zahl2
	lda sp_py
	ldx #29 * 160 + 42 * 2
	jsr w_zahl2
+	rts
t_sp_status .null " PATTERN      BANK      COLOUR     X    Y        pattern 127 = mouse pointer    "
t_zs_status .null " CHAR         BANK      COLOUR     X    Y        BASIC: LOOK uses this font     "
t_ki_null   .null " TILE         BANK      COLOUR     X    Y        tile 0 stays empty (map)       "
t_ki_status .null " TILE         BANK      COLOUR     X    Y        tiles for MAP (F3) and BASIC   "

;----------------------------------------------------------------------------
; Je Bild: Maus und Tasten (Taste in A, 0 = keine)

sp_takt
	.as
	cmp #0
	beq +
	jsr sp_taste
+	jsr sp_maus_feld            ; Feld unter der Maus
	lda w_mt
	and #$02                    ; rechts: Farbe aufnehmen
	beq _links
	lda sp_px
	bmi _ende
	jsr sp_pixel_index
	lda SP_PUF,x
	cmp sp_f
	beq _ende
	sta sp_f
	jsr sp_farbfelder
	jmp sp_status
_links
	lda w_mt
	and #$01
	beq _ende
	lda w_mtalt                 ; gerade gedrueckt?
	and #$01
	bne _halten
	jsr sp_klick                ; Farbfelder, Bogen
	jsr sp_gesperrt
	bcs _ende
	lda sp_px
	bmi _ende
	jsr sp_merken               ; ein neuer Strich: vorher merken
	lda sp_px
	sta sp_lx
	lda sp_py
	sta sp_ly
	lda sp_wz
	beq _halten
	jsr sp_pixel_index          ; fuellen
	jsr sp_fuellen
	jmp sp_neu
_halten
	jsr sp_gesperrt
	bcs _ende
	lda sp_wz
	bne _ende
	lda sp_px
	bmi _ende
	lda sp_px                   ; zeichnen: vom letzten Feld Schritt fuer
	sta sp_zx                   ; Schritt bis hierher (die Maus springt)
	lda sp_py
	sta sp_zy
	stz sp_geaendert
_schritt
	lda sp_lx
	sta sp_px
	lda sp_ly
	sta sp_py
	jsr sp_setzen
	lda sp_lx                   ; ein Feld naeher
	cmp sp_zx
	beq _y
	bcs _xab
	inc sp_lx
	bra _y
_xab
	dec sp_lx
_y
	lda sp_ly
	cmp sp_zy
	beq _pruefen
	bcs _yab
	inc sp_ly
	bra _pruefen
_yab
	dec sp_ly
_pruefen
	lda sp_lx
	cmp sp_zx
	bne _schritt
	lda sp_ly
	cmp sp_zy
	bne _schritt
	sta sp_py
	lda sp_lx
	sta sp_px
	jsr sp_setzen               ; das Zielfeld selbst
	lda sp_geaendert
	beq _ende
	jsr sp_bogen_eins           ; das kleine Bild im Bogen
	lda sp_art
	beq _ende
	jsr sp_vorschau             ; Kachel: die Flaeche neu
_ende
	jmp sp_status

; Feld sp_px, sp_py auf sp_f setzen (wenn anders; dann sp_geaendert = 1)
sp_setzen
	.as
	jsr sp_pixel_index
	lda SP_PUF,x
	cmp sp_f
	beq +
	lda sp_f
	sta SP_PUF,x
	lda #1
	sta sp_geaendert
	lda sp_py
	jsr sp_zeile_schreiben
	lda sp_px
	sta sp_fx
	lda sp_py
	sta sp_fy
	jsr sp_feld
+	rts

; sp_px/sp_py: Feld unter der Maus ($ff = keins)
sp_maus_feld
	.as
	lda #$ff
	sta sp_px
	sta sp_py
	#akku16
	lda w_mx
	sec
	sbc #GX0
	cmp #16*7
	bcs _raus
	jsr sp_durch7
	sta sp_t
	lda w_my
	sec
	sbc #GY0
	cmp #16*7
	bcs _raus
	jsr sp_durch7
	#akku8
	sta sp_py
	lda sp_t
	sta sp_px
	lda sp_art                  ; Kachel: Felder doppelt so gross
	beq +
	lsr sp_px
	lsr sp_py
+	rts
_raus
	#akku8
	rts
sp_durch7                       ; A (16 Bit, < 112) / 7
	.al
	ldx #0
-	cmp #7
	bcc +
	sbc #7
	inx
	bra -
+	txa
	rts

sp_pixel_index                  ; X = sp_py * 16 + sp_px
	.as
	lda sp_py
	asl a
	asl a
	asl a
	asl a
	ora sp_px
	#akku16
	and #$00ff
	tax
	#akku8
	rts

; Klick ausserhalb der Malflaeche: Farbfeld oder Bogen?
sp_klick
	.as
	#akku16
	lda w_mx                    ; Farbfelder
	sec
	sbc #FX0
	cmp #4*12
	bcs sp_klick_bogen
	lsr a
	lsr a                       ; / 12 = (/4) / 3
	ldx #0
-	cmp #3
	bcc +
	sbc #3
	inx
	bra -
+	stx sp_t
	lda w_my
	sec
	sbc #FY0
	cmp #4*12
	bcs sp_klick_bogen
	lsr a
	lsr a
	ldx #0
-	cmp #3
	bcc +
	sbc #3
	inx
	bra -
+	txa
	asl a
	asl a
	ora sp_t
	#akku8
	jsr sp_farbe_setzen
	jmp sp_status
sp_klick_bogen                  ; Klick in den Bogen (Akku 16 Bit)
	.al
	lda sp_art
	and #$00ff
	bne _kacheln
	lda w_my                    ; Musterbogen: 2 Reihen zu 19 Punkten
	sec
	sbc #BY0-1
	cmp #2*19
	bcs _nichts
	ldx #0
	cmp #19
	bcc +
	ldx #16
+	stx sp_t
	lda w_mx
	sec
	sbc #BX0-1
	cmp #16*19
	bcs _nichts
	ldx #0
-	cmp #19
	bcc +
	sbc #19
	inx
	bra -
+	txa
	bra _waehlen
_kacheln                        ; Kachelbogen: 2 Reihen zu 11, Spalten zu 9
	lda w_my
	sec
	sbc #BY0-1
	cmp #2*11
	bcs _nichts
	ldx #0
	cmp #11
	bcc +
	ldx #32
+	stx sp_t
	lda w_mx
	sec
	sbc #BX0-1
	cmp #32*9
	bcs _nichts
	ldx #0
-	cmp #9
	bcc +
	sbc #9
	inx
	bra -
+	txa
_waehlen
	clc
	adc sp_t
	sta sp_t
	#akku8
	jsr sp_seite_maske
	and sp_m
	ora sp_t
	jmp sp_waehlen
_nichts
	#akku8
	rts

; Bild A waehlen (Muster 0-127, Kachel 0-255)
sp_waehlen
	.as
	ldx sp_art
	bne +
	and #$7f
+	sta sp_m
	jsr sp_laden
	lda w_reiter
	cmp #2
	bne +
	jmp ka_neu                  ; MAP: nur Auswahl und Status
+	jmp sp_alles

;----------------------------------------------------------------------------
; Tasten

sp_taste
	.as
	cmp #$1c                    ; Pfeile: schieben
	bcc +
	cmp #$20
	bcs +
	jsr sp_gesperrt
	bcc _schieben
	rts
_schieben
	pha
	jsr sp_merken
	pla
	jmp sp_schieben
+	cmp #'0'
	bcc +
	cmp #'9'+1
	bcs +
	sec
	sbc #'0'
	jsr sp_farbe_setzen
	jmp sp_status
+	cmp #'+'
	bne +
	lda sp_b
	inc a
	bra _bank
+	cmp #'-'
	bne +
	lda sp_b
	dec a
_bank
	and #$0f
	sta sp_b
	jsr sp_bank_index
	lda sp_b
	sta @l KART_BANK,x
	jmp sp_alles
+	cmp #','
	bne +
	lda sp_m
	dec a
	jmp sp_waehlen
+	cmp #'.'
	bne +
	lda sp_m
	inc a
	jmp sp_waehlen
+	and #$df                    ; Buchstaben gross
	cmp #'D'
	bne +
	stz sp_wz
	jmp sp_werkzeuge
+	cmp #'F'
	bne +
	lda #1
	sta sp_wz
	jmp sp_werkzeuge
+	cmp #'U'
	bne +
	jsr sp_gesperrt
	bcc _undo
	rts
_undo
	ldx #0                      ; zurueck: Puffer <-> SP_UNDO
-	lda SP_PUF,x
	pha
	lda SP_UNDO,x
	sta SP_PUF,x
	pla
	sta SP_UNDO,x
	inx
	cpx #256
	bne -
	bra sp_neu
+	cmp #'C'
	bne +
	ldx #0
-	lda SP_PUF,x
	sta SP_KLAU,x
	inx
	cpx #256
	bne -
	rts
+	cmp #'P'
	beq +
	cmp #'X'
	beq +
	cmp #'H'
	beq +
	cmp #'V'
	beq +
	cmp #'R'
	beq +
	rts
+	jsr sp_gesperrt
	bcc _aendern
	rts
_aendern
	pha
	jsr sp_merken               ; diese aendern das Bild
	pla
	cmp #'P'
	bne +
	ldx #0
-	lda SP_KLAU,x
	sta SP_PUF,x
	inx
	cpx #256
	bne -
	bra sp_neu
+	cmp #'X'
	bne +
	ldx #0
-	stz SP_PUF,x
	inx
	cpx #256
	bne -
	bra sp_neu
+	cmp #'H'
	bne +
	jsr sp_spiegeln_h
	bra sp_neu
+	cmp #'V'
	bne +
	jsr sp_spiegeln_v
	bra sp_neu
+	jsr sp_drehen
sp_neu                          ; Puffer geaendert: schreiben, neu zeichnen
	jsr sp_alles_schreiben
	jsr sp_gitter
	jsr sp_bogen_eins
	lda sp_art
	beq +
	jsr sp_vorschau
+	rts

;----------------------------------------------------------------------------
; Werkzeuge auf dem Puffer (Seite sp_n, Zeilenabstand 16)

sp_spiegeln_h                   ; links <-> rechts: x <-> n-1-x
	.as
	stz sp_fy
_zeile
	stz sp_fx
_x
	lda sp_fy
	asl a
	asl a
	asl a
	asl a
	sta sp_t                    ; Zeilenanfang
	ora sp_fx
	sta sp_u                    ; links
	lda sp_n
	dec a
	sec
	sbc sp_fx
	ora sp_t
	sta sp_u+1                  ; rechts
	#akku16
	lda sp_u
	and #$00ff
	tax
	lda sp_u+1
	and #$00ff
	tay
	#akku8
	lda SP_PUF,x
	pha
	lda SP_PUF,y
	sta SP_PUF,x
	pla
	sta SP_PUF,y
	inc sp_fx
	lda sp_n
	lsr a
	cmp sp_fx
	bne _x
	inc sp_fy
	lda sp_fy
	cmp sp_n
	bne _zeile
	rts

sp_spiegeln_v                   ; oben <-> unten: y <-> n-1-y
	.as
	stz sp_fy
_zeile
	lda sp_fy
	asl a
	asl a
	asl a
	asl a
	sta sp_u                    ; obere Zeile
	lda sp_n
	dec a
	sec
	sbc sp_fy
	asl a
	asl a
	asl a
	asl a
	sta sp_u+1                  ; untere Zeile
	stz sp_fx
_x
	lda sp_u
	ora sp_fx
	#akku16
	and #$00ff
	tax
	#akku8
	lda sp_u+1
	ora sp_fx
	#akku16
	and #$00ff
	tay
	#akku8
	lda SP_PUF,x
	pha
	lda SP_PUF,y
	sta SP_PUF,x
	pla
	sta SP_PUF,y
	inc sp_fx
	lda sp_fx
	cmp sp_n
	bne _x
	inc sp_fy
	lda sp_n
	lsr a
	cmp sp_fy
	bne _zeile
	rts

sp_drehen                       ; 90 Grad im Uhrzeigersinn: neu[y][x] = alt[n-1-x][y]
	.as
	ldx #0
-	lda SP_PUF,x
	sta SP_HILF,x
	inx
	cpx #256
	bne -
	stz sp_fy
_zeile
	stz sp_fx
_x
	lda sp_n                    ; Quelle: (n-1-x) * 16 + y
	dec a
	sec
	sbc sp_fx
	asl a
	asl a
	asl a
	asl a
	ora sp_fy
	#akku16
	and #$00ff
	tax
	#akku8
	lda SP_HILF,x
	pha
	lda sp_fy                   ; Ziel: y * 16 + x
	asl a
	asl a
	asl a
	asl a
	ora sp_fx
	#akku16
	and #$00ff
	tax
	#akku8
	pla
	sta SP_PUF,x
	inc sp_fx
	lda sp_fx
	cmp sp_n
	bne _x
	inc sp_fy
	lda sp_fy
	cmp sp_n
	bne _zeile
	rts

sp_schieben                     ; um ein Pixel (w_taste = Pfeil); was hinausfaellt, kommt rein
	.as
	ldx #0
-	lda SP_PUF,x
	sta SP_HILF,x
	inx
	cpx #256
	bne -
	stz sp_fy
_zeile
	stz sp_fx
_x
	lda sp_fx                   ; Quelle
	sta sp_lx
	lda sp_fy
	sta sp_ly
	lda w_taste
	cmp #$1c                    ; rechts: Quelle x-1
	bne +
	dec sp_lx
+	cmp #$1d                    ; links: x+1
	bne +
	inc sp_lx
+	cmp #$1e                    ; hoch: y+1
	bne +
	inc sp_ly
+	cmp #$1f                    ; runter: y-1
	bne +
	dec sp_ly
+	lda sp_n                    ; mod n
	dec a
	sta sp_t
	lda sp_lx
	and sp_t
	sta sp_lx
	lda sp_ly
	and sp_t
	asl a
	asl a
	asl a
	asl a
	ora sp_lx
	#akku16
	and #$00ff
	tax
	#akku8
	lda SP_HILF,x
	pha
	lda sp_fy
	asl a
	asl a
	asl a
	asl a
	ora sp_fx
	#akku16
	and #$00ff
	tax
	#akku8
	pla
	sta SP_PUF,x
	inc sp_fx
	lda sp_fx
	cmp sp_n
	bne _x
	inc sp_fy
	lda sp_fy
	cmp sp_n
	bne _zeile
	jmp sp_neu

; Fuellen ab Pixel X mit sp_f (4 Nachbarn innerhalb n x n, Stapel in SP_HILF)
sp_fuellen
	.as
	lda SP_PUF,x
	cmp sp_f
	bne +
	rts
+	sta sp_c                    ; alte Farbe
	txa
	sta SP_HILF
	ldy #1                      ; Stapel: Y Eintraege
_naechster
	cpy #0
	beq _fertig
	dey
	lda SP_HILF,y
	#akku16
	and #$00ff
	tax
	#akku8
	lda SP_PUF,x
	cmp sp_c
	bne _naechster
	lda sp_f
	sta SP_PUF,x
	lda sp_n
	dec a
	sta sp_t                    ; n-1
	txa                         ; links
	and #$0f
	beq +
	txa
	dec a
	jsr _push
+	txa                         ; rechts
	and #$0f
	cmp sp_t
	beq +
	txa
	inc a
	jsr _push
+	txa                         ; oben
	cmp #16
	bcc +
	sec
	sbc #16
	jsr _push
+	txa                         ; unten: Zeile < n-1
	lsr a
	lsr a
	lsr a
	lsr a
	cmp sp_t
	bcs _naechster
	txa
	clc
	adc #16
	jsr _push
	bra _naechster
_fertig
	rts
_push
	cpy #255
	bcs +
	sta SP_HILF,y
	iny
+	rts
