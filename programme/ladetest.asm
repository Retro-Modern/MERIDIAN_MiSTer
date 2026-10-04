;============================================================================
;  LADETEST - BOTE und der Zusatzspeicher (Etappe 9b)
;
;  Prueft, was BOTE vorher geladen hat (programme/ladetest.py erzeugt es):
;    256 KB ab $20:0000 - mitten im Zusatzspeicher
;      8 KB ab $03:F000 - ueber die Grenze vom Chip-RAM in den Zusatzspeicher
;  Muster: Byte i = (i ^ (i >> 8) ^ (i >> 16) ^ $3C) + Startwert
;
;  Assemblieren: programme/bauen.sh ladetest
;  Senden:  senden.py daten/ladetest_gross.mer daten/ladetest_grenze.mer ladetest.mer
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

zeiger = $80                    ; 3 Byte
nr     = $83                    ; Bank im Block (i >> 16)
startw = $84                    ; Startwert des Musters
tmp    = $85
fehler = $86                    ; 24 Bit

	* = $2000

start
	.as
	.xl
	phb
	ldx #t_titel
	jsr PRINT

	; 256 KB ab $20:0000, vier Baenke
	stz fehler
	stz fehler+1
	stz fehler+2
	stz startw
	stz zeiger
	stz zeiger+1
	stz nr
-	lda nr
	clc
	adc #$20
	sta zeiger+2
	ldy #0
-	jsr soll
	cmp [zeiger],y
	beq +
	jsr fehler_plus
+	iny
	bne -                       ; Y laeuft nach $FFFF auf 0: Bank fertig
	inc nr
	lda nr
	cmp #4
	bne --
	ldx #t_gross
	jsr fehler_zeigen

	; 8 KB ab $03:F000 (der lange Zeiger laeuft von Bank 3 nach Bank 4)
	stz fehler
	stz fehler+1
	stz fehler+2
	lda #$55
	sta startw
	stz nr
	stz zeiger
	lda #$F0
	sta zeiger+1
	lda #$03
	sta zeiger+2
	ldy #0
-	jsr soll
	cmp [zeiger],y
	beq +
	jsr fehler_plus
+	iny
	cpy #$2000
	bne -
	ldx #t_grenze
	jsr fehler_zeigen
	plb
	rtl

soll                            ; A = (lo(Y) ^ hi(Y) ^ nr ^ $3C) + startw
	#akku16
	tya
	#akku8
	xba
	sta tmp
	xba
	eor tmp
	eor nr
	eor #$3C
	clc
	adc startw
	rts

fehler_plus
	inc fehler
	bne +
	inc fehler+1
	bne +
	inc fehler+2
+	rts

fehler_zeigen                   ; Text ab X, dann "Fehler $xxxxxx"
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

t_titel	.text 13, "LADETEST - BOTE and expansion memory", 13, 0
t_gross	.text " 256 KB at $20:0000: errors $", 0
t_grenze .text "   8 KB at $03:F000: errors $", 0
