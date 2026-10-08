;============================================================================
;  WERKSTATT: Programm und Daten in einer Datei (SAVE/LOAD, MERIDIAN 1.0)
;
;  Datei = das BASIC-Programm, dahinter Abschnitte (Art 1 Byte, Laenge 3,
;  Daten), am Ende die Laenge des Programms (3 Byte) und "MWS1". Hat die
;  Werkstatt keine Daten, bleibt die Datei, wie sie immer war; alte Dateien
;  (ohne "MWS1" am Ende) laden wie bisher.
;
;  Abschnitte:  1  Sprites: 128 Muster (16 KB) und je Muster die Bank (128)
;               2  Kacheln: 256 Kacheln (8 KB) und je Kachel die Bank (256)
;               3  Karten: 1 und 2 (je 4 KB)
;               4  Klaenge: 64 zu 132 Byte
;               5  Look: Palette, Leuchten, Tusche ($240)
;               6  Zeichensatz: 256 Zeichen zu 8 Byte
;  Gespeichert wird nur, was nicht leer ist.
;
;  Aufgerufen vom Kern (d_save, d_load) per JSL: Akku 8, Index 16, DBR 0,
;  D 0. Hilfswerte auf Seite 2 ($02E1, wie SHINE), Zeiger des Kerns ($16).
;============================================================================

WS_PUFFER = $FB0000             ; bis $FC:FFFF
D_ADR     = $16E4
D_LAENGE  = $16E8
P_START   = $0390
P_LEN     = $0393
K_ZEIGER  = $16                 ; 3 Byte, direkte Seite 0

DZ        = $02E1
dz_q      = DZ+0                ; 3: Quelle
dz_z      = DZ+3                ; 3: Ziel
dz_r      = DZ+6                ; 3: Laenge
dz_n      = DZ+9                ; 2: volle 16-KB-Zeilen
dz_s      = DZ+11               ; 2: Rest
dz_p      = DZ+13               ; 3: Lesestelle
dz_e      = DZ+16               ; 3: Ende der Abschnitte (bis $02F3)

ART_SPRITES = 1
SPR_LAENGE  = $4080             ; Muster und Banken
ART_KACHELN = 2
KI_LAENGE   = $2100             ; Kacheln und Banken
ART_KARTEN  = 3
KA_LAENGE   = $2000             ; beide Karten
ART_KLAENGE = 4
KL_LAENGE   = 64 * 132
ART_LOOK    = 5
ART_FONT    = 6

;----------------------------------------------------------------------------
; SAVE: D_ADR/D_LAENGE setzen - nur das Programm oder der Puffer mit Daten

ws_sichern
	.as
	.xl
	.dpage 0
	#akku16                     ; ohne Zusatzspeicher (kein SDRAM-Modul)
	lda K_BAENKE                ; gibt es keine Werkstatt-Daten
	cmp #$fd
	#akku8
	lda #0
	bcc +
	jsr ws_hat_daten
+	cmp #0            ; A = belegte Abschnitte (Bits 0-2)
	bne _mit
	#akku16                     ; nur das Programm
	lda P_START
	sta D_ADR
	lda P_LEN
	sta D_LAENGE
	#akku8
	lda P_START+2
	sta D_ADR+2
	lda P_LEN+2
	sta D_LAENGE+2
	rtl
_mit
	pha
	#akku16                     ; das Programm in den Puffer
	lda P_START
	sta dz_q
	lda P_LEN
	sta dz_r
	lda #<>WS_PUFFER
	sta dz_z
	#akku8
	lda P_START+2
	sta dz_q+2
	lda P_LEN+2
	sta dz_r+2
	lda #`WS_PUFFER
	sta dz_z+2
	jsr ws_kopie                ; dz_z steht dahinter
	lda 1,s
	and #1
	beq +
	lda #ART_SPRITES            ; Abschnitt Sprites
	ldx #SPR_LAENGE
	jsr ws_kopf
	ldx #<>KART
	lda #`KART
	ldy #SPR_LAENGE
	jsr ws_teil
+	lda 1,s
	and #2
	beq +
	lda #ART_KACHELN            ; Abschnitt Kacheln
	ldx #KI_LAENGE
	jsr ws_kopf
	ldx #<>KACHELN
	lda #`KACHELN
	ldy #$2000
	jsr ws_teil
	ldx #<>KART_KBANK
	lda #`KART_KBANK
	ldy #$100
	jsr ws_teil
+	lda 1,s
	and #4
	beq +
	lda #ART_KARTEN             ; Abschnitt Karten
	ldx #KA_LAENGE
	jsr ws_kopf
	ldx #<>KARTE1
	lda #`KARTE1
	ldy #KA_LAENGE
	jsr ws_teil
+	lda 1,s
	and #8
	beq +
	lda #ART_KLAENGE            ; Abschnitt Klaenge
	ldx #KL_LAENGE
	jsr ws_kopf
	ldx #<>KL_DATEN
	lda #`KL_DATEN
	ldy #KL_LAENGE
	jsr ws_teil
+	lda 1,s
	and #16
	beq +
	lda #ART_LOOK               ; Abschnitt Look
	ldx #LK_LAENGE
	jsr ws_kopf
	ldx #<>KART_LOOK
	lda #`KART_LOOK
	ldy #LK_LAENGE
	jsr ws_teil
+	pla
	and #32
	beq +
	lda #ART_FONT               ; Abschnitt Zeichensatz
	ldx #$800
	jsr ws_kopf
	ldx #<>KART_FONT
	lda #`KART_FONT
	ldy #$800
	jsr ws_teil
+	jsr ws_zeiger_z             ; Schluss: Laenge des Programms, "MWS1"
	ldy #0
-	lda P_LEN,y
	sta [K_ZEIGER],y
	iny
	cpy #3
	bne -
	ldx #0
-	lda @l t_kennung,x
	sta [K_ZEIGER],y
	inx
	iny
	cpy #7
	bne -
	#akku16                     ; Laenge = Ende - Puffer
	lda dz_z
	clc
	adc #7
	sta D_LAENGE
	#akku8
	lda dz_z+2
	adc #0
	sec
	sbc #`WS_PUFFER
	sta D_LAENGE+2
	#akku16
	lda #<>WS_PUFFER
	sta D_ADR
	#akku8
	lda #`WS_PUFFER
	sta D_ADR+2
	rtl

t_kennung .text "MWS1"

; Abschnittskopf an dz_z: Art A, Laenge X (16 Bit); dz_z dahinter
ws_kopf
	.as
	pha
	jsr ws_zeiger_z
	pla
	sta [K_ZEIGER]
	#akku16
	txa
	ldy #1
	sta [K_ZEIGER],y
	#akku8
	lda #0
	ldy #3
	sta [K_ZEIGER],y
	#akku16
	lda dz_z
	clc
	adc #4
	sta dz_z
	#akku8
	lda dz_z+2
	adc #0
	sta dz_z+2
	rts

ws_zeiger_z                     ; K_ZEIGER = dz_z
	.as
	#akku16
	lda dz_z
	sta K_ZEIGER
	#akku8
	lda dz_z+2
	sta K_ZEIGER+2
	rts

; Teil eines Abschnitts in den Puffer: Y Byte ab A:X (dz_z steht dahinter)
ws_teil
	.as
	stx dz_q
	sta dz_q+2
	sty dz_r
	stz dz_r+2
	jmp ws_kopie

; A = Abschnitte, in denen etwas steht: Bit 0 Sprites, 1 Kacheln, 2 Karten,
; 3 Klaenge, 4 Look, 5 Zeichensatz
ws_hat_daten
	.as
	lda #0
	pha
	ldx #<>KART
	lda #`KART
	ldy #SPR_LAENGE
	jsr ws_belegt
	bcc +
	lda #1
	sta 1,s
+	ldx #<>KACHELN
	lda #`KACHELN
	ldy #$2000
	jsr ws_belegt
	bcs +
	ldx #<>KART_KBANK
	lda #`KART_KBANK
	ldy #$100
	jsr ws_belegt
	bcc ++
+	lda 1,s
	ora #2
	sta 1,s
+	ldx #<>KARTE1
	lda #`KARTE1
	ldy #KA_LAENGE
	jsr ws_belegt
	bcc +
	lda 1,s
	ora #4
	sta 1,s
+	ldx #<>KL_DATEN
	lda #`KL_DATEN
	ldy #KL_LAENGE
	jsr ws_belegt
	bcc +
	lda 1,s
	ora #8
	sta 1,s
+	lda @l KART_LOOK            ; Look und Zeichensatz: nur wenn geaendert
	and #3
	asl a
	asl a
	asl a
	asl a
	ora 1,s
	sta 1,s
	pla
	rts

; C = 1: in Y Byte ab A:X steht etwas, das nicht 0 ist
ws_belegt
	.as
	stx K_ZEIGER
	sta K_ZEIGER+2
	sty dz_r
	ldy #0
-	lda [K_ZEIGER],y
	bne _ja
	iny
	cpy dz_r
	bne -
	clc
	rts
_ja
	sec
	rts

;----------------------------------------------------------------------------
; LOAD: die Datei liegt in WS_PUFFER (Laenge D_LAENGE). Programm nach P_START
; (hoechstens P_LEN, sonst A = 8), P_LEN = seine Laenge, Daten verteilen.

ws_laden
	.as
	.xl
	.dpage 0
	#akku16                     ; dz_e = Ende der Datei
	lda D_LAENGE
	clc
	adc #<>WS_PUFFER
	sta dz_e
	#akku8
	lda D_LAENGE+2
	adc #`WS_PUFFER
	sta dz_e+2
	#akku16                     ; mindestens 7 Byte? dann Kennung pruefen
	lda D_LAENGE+1
	bne +
	lda D_LAENGE
	cmp #7
	bcc _ohne
+	lda dz_e                    ; K_ZEIGER = Ende - 7
	sec
	sbc #7
	sta K_ZEIGER
	#akku8
	lda dz_e+2
	sbc #0
	sta K_ZEIGER+2
	ldy #3
	ldx #0
-	lda [K_ZEIGER],y
	cmp @l t_kennung,x
	bne _ohne
	iny
	inx
	cpx #4
	bne -
	ldy #0                      ; mit Daten: Laenge des Programms
-	lda [K_ZEIGER],y
	sta dz_r,y
	iny
	cpy #3
	bne -
	#akku16                     ; Abschnitte enden vor dem Schluss
	lda K_ZEIGER
	sta dz_e
	#akku8
	lda K_ZEIGER+2
	sta dz_e+2
	bra _programm
_ohne
	#akku16                     ; ohne Daten: alles ist Programm
	lda D_LAENGE
	sta dz_r
	#akku8
	lda D_LAENGE+2
	sta dz_r+2
_programm
	lda dz_r+2                  ; passt es? (P_LEN = hoechstens)
	cmp P_LEN+2
	bcc +
	bne _gross
	#akku16
	lda dz_r
	cmp P_LEN
	#akku8
	beq +
	bcs _gross
+	#akku16
	lda dz_r
	sta P_LEN
	lda #<>WS_PUFFER
	sta dz_q
	lda P_START
	sta dz_z
	#akku8
	lda dz_r+2
	sta P_LEN+2
	lda #`WS_PUFFER
	sta dz_q+2
	lda P_START+2
	sta dz_z+2
	jsr ws_kopie                ; dz_q steht hinter dem Programm
	ldx #0                      ; Cartridge, Kacheln und Karten leeren
-	lda @l wb_leeren,x
	sta KRAN_REG,x
	inx
	cpx #16
	bne -
	jsr ws_starten
	ldx #0
-	lda @l wb_leeren+16,x
	sta KRAN_REG,x
	inx
	cpx #16
	bne -
	jsr ws_starten
	jsr ws_vorgaben             ; Startfarben, Zeichensatz des ROM
_abschnitt
	#akku16                     ; dz_q < dz_e?
	lda dz_q+1
	cmp dz_e+1
	#akku8
	bcc +
	bne _fertig
	lda dz_q
	cmp dz_e
	bcs _fertig
+	#akku16                     ; Kopf lesen
	lda dz_q
	sta K_ZEIGER
	#akku8
	lda dz_q+2
	sta K_ZEIGER+2
	ldy #1
	#akku16
	lda [K_ZEIGER],y
	sta dz_r
	#akku8
	ldy #3
	lda [K_ZEIGER],y
	sta dz_r+2
	#akku16
	lda dz_q                    ; Daten ab Kopf + 4
	clc
	adc #4
	sta dz_q
	#akku8
	lda dz_q+2
	adc #0
	sta dz_q+2
	lda dz_r+2                  ; bekannte Abschnitte haben ihre Laenge
	bne _ueberspringen
	lda [K_ZEIGER]
	cmp #ART_SPRITES
	bne +
	ldx #SPR_LAENGE
	jsr ws_laenge
	bne _ueberspringen
	ldx #<>KART
	lda #`KART
	jsr ws_hin
	bra _abschnitt
+	cmp #ART_KACHELN
	bne +
	ldx #KI_LAENGE
	jsr ws_laenge
	bne _ueberspringen
	ldx #<>KACHELN
	lda #`KACHELN
	ldy #$2000
	jsr ws_hin_y
	ldx #<>KART_KBANK
	lda #`KART_KBANK
	ldy #$100
	jsr ws_hin_y
	bra _abschnitt
+	cmp #ART_KARTEN
	bne +
	ldx #KA_LAENGE
	jsr ws_laenge
	bne _ueberspringen
	ldx #<>KARTE1
	lda #`KARTE1
	jsr ws_hin
	bra _abschnitt
+	cmp #ART_KLAENGE
	bne +
	ldx #KL_LAENGE
	jsr ws_laenge
	bne _ueberspringen
	ldx #<>KL_DATEN
	lda #`KL_DATEN
	jsr ws_hin
	bra _abschnitt
+	cmp #ART_LOOK
	bne +
	ldx #LK_LAENGE
	jsr ws_laenge
	bne _ueberspringen
	ldx #<>KART_LOOK
	lda #`KART_LOOK
	jsr ws_hin
	bra _abschnitt
+	cmp #ART_FONT
	bne _ueberspringen
	ldx #$800
	jsr ws_laenge
	bne _ueberspringen
	ldx #<>KART_FONT
	lda #`KART_FONT
	jsr ws_hin
	bra _abschnitt
_ueberspringen                  ; unbekannt: Laenge weiter
	#akku16
	lda dz_q
	clc
	adc dz_r
	sta dz_q
	#akku8
	lda dz_q+2
	adc dz_r+2
	sta dz_q+2
	bra _abschnitt
_fertig
	stz KOB_TAB+$100            ; Muster nach KOBOLD
	stz KOB_TAB+$101
	ldx #0
-	lda @l KART_MUSTER,x
	sta KOB_TAB+$102
	inx
	cpx #$4000
	bne -
	lda #0
	rtl
_gross
	lda #8                      ; FILE TOO BIG
	rtl

ws_laenge                       ; Z = 1: dz_r (16 Bit) = X
	.as
	#akku16
	txa
	cmp dz_r
	#akku8
	rts
ws_hin                          ; den ganzen Abschnitt (dz_r) nach A:X
	.as
	stx dz_z
	sta dz_z+2
	jmp ws_kopie
ws_hin_y                        ; Y Byte des Abschnitts nach A:X
	.as
	stx dz_z
	sta dz_z+2
	sty dz_r
	stz dz_r+2
	jmp ws_kopie

;----------------------------------------------------------------------------
; KRAN: dz_r Byte von dz_q nach dz_z (Zeilen zu 16 KB und ein Rest); danach
; stehen dz_q und dz_z hinter dem Block

ws_kopie
	.as
	#akku16
	lda dz_r+1                  ; Zeilen = Laenge >> 14
	lsr a
	lsr a
	lsr a
	lsr a
	lsr a
	lsr a
	sta dz_n
	lda dz_r
	and #$3fff
	sta dz_s
	#akku8
	lda dz_n
	ora dz_n+1
	beq _rest
	jsr _adressen
	#akku16
	lda #$4000
	sta KRAN_REG+6
	sta KRAN_REG+10
	sta KRAN_REG+12
	lda dz_n
	sta KRAN_REG+8
	asl a                       ; Versatz in Seiten zu 256: Zeilen * 64
	asl a
	asl a
	asl a
	asl a
	asl a
	sta dz_n
	#akku8
	jsr _starten
	clc
	lda dz_q+1
	adc dz_n
	sta dz_q+1
	lda dz_q+2
	adc dz_n+1
	sta dz_q+2
	clc
	lda dz_z+1
	adc dz_n
	sta dz_z+1
	lda dz_z+2
	adc dz_n+1
	sta dz_z+2
_rest
	lda dz_s
	ora dz_s+1
	beq _ende
	jsr _adressen
	#akku16
	lda dz_s
	sta KRAN_REG+6
	lda #1
	sta KRAN_REG+8
	stz KRAN_REG+10
	stz KRAN_REG+12
	#akku8
	jsr _starten
	#akku16
	lda dz_q
	clc
	adc dz_s
	sta dz_q
	#akku8
	lda dz_q+2
	adc #0
	sta dz_q+2
	#akku16
	lda dz_z
	clc
	adc dz_s
	sta dz_z
	#akku8
	lda dz_z+2
	adc #0
	sta dz_z+2
_ende
	rts
_adressen
	ldx #0
-	lda dz_q,x
	sta KRAN_REG,x
	inx
	cpx #6
	bne -
	stz KRAN_REG+14
	stz KRAN_REG+15             ; kopieren
	rts
_starten
	lda #$08
	sta KRAN_BEF
	lda #$01
	sta KRAN_BEF
-	lda KRAN_BEF
	and #$01
	bne -
	rts

	.dpage W_RAM
