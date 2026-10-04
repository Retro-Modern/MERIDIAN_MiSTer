;============================================================================
;  ZUSATZDIAG - Fehlersuche im Zusatzspeicher (Etappe 8)
;
;  Beschreibt die Baenke $04-$13 (1 MB) mit einem Muster, prueft zweimal
;  (Lesefehler wechseln, Schreibfehler bleiben) und zeigt die ersten
;  Fehler mit Adresse, Soll und Ist.
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

CHROUT = $FF80
PRINT  = $FF86
HEX8   = $FF8C

ERSTE  = $04
LETZTE = $13

zeiger = $80
bank   = $84
muster = $86
fehler = $88                    ; 24 Bit
gezeigt = $8C
soll   = $8E
ist    = $90

	* = $2000

start
	.as
	.xl
	phb
	lda #ERSTE
	sta bank
-	jsr muster_setzen
	#akku16
	ldy #0
-	tya
	eor muster
	sta [zeiger],y
	iny
	iny
	bne -
	#akku8
	lda bank
	inc a
	sta bank
	cmp #LETZTE+1
	bne --
	ldx #t_lauf1
	jsr PRINT
	jsr pruefen
	ldx #t_lauf2
	jsr PRINT
	jsr pruefen
	plb
	rtl

pruefen
	stz fehler
	stz fehler+1
	stz fehler+2
	stz gezeigt
	lda #ERSTE
	sta bank
_bank
	jsr muster_setzen
	#akku16
	ldy #0
_wort
	tya
	eor muster
	sta soll
	lda [zeiger],y
	cmp soll
	beq _gut
	sta ist
	#akku8
	inc fehler
	bne +
	inc fehler+1
	bne +
	inc fehler+2
+	lda gezeigt
	cmp #6
	bcs +
	inc gezeigt
	jsr fehler_zeigen
+	#akku16
_gut
	iny
	iny
	bne _wort
	#akku8
	lda bank
	inc a
	sta bank
	cmp #LETZTE+1
	bne _bank
	ldx #t_fehler
	jsr PRINT
	lda fehler+2
	jsr HEX8
	lda fehler+1
	jsr HEX8
	lda fehler
	jsr HEX8
	lda #13
	jsr CHROUT
	rts

fehler_zeigen                   ; " bbyyyy soll ist"
	phy
	lda #' '
	jsr CHROUT
	lda bank
	jsr HEX8
	#akku16
	tya
	#akku8
	xba
	jsr HEX8
	xba
	jsr HEX8
	lda #' '
	jsr CHROUT
	lda soll+1
	jsr HEX8
	lda soll
	jsr HEX8
	lda #' '
	jsr CHROUT
	lda ist+1
	jsr HEX8
	lda ist
	jsr HEX8
	lda #13
	jsr CHROUT
	ply
	rts

muster_setzen
	lda bank
	sta zeiger+2
	stz zeiger
	stz zeiger+1
	#akku16
	lda bank
	and #$00ff
	sta muster
	xba
	ora muster
	eor #$5a3c
	sta muster
	#akku8
	rts

t_lauf1
	.text 13, "ZUSATZDIAG 1 MB, test 1:", 13, 0
t_lauf2
	.text "Test 2:", 13, 0
t_fehler
	.text "Errors: $", 0
