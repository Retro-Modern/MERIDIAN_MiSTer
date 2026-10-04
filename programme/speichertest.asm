;============================================================================
;  SPEICHERTEST - prueft den Zusatzspeicher (SDRAM) des MERIDIAN (Etappe 8)
;
;  1. Tempo: 16 KB schreiben und lesen, einmal im Chip-RAM (Bank 1), einmal
;     im Zusatzspeicher (Bank 4) - gemessen mit der Mikrosekundenuhr.
;  2. Pruefung: alle Baenke von ERSTE bis LETZTE mit einem Muster
;     beschreiben, das von Adresse und Bank abhaengt, dann alles
;     zuruecklesen und Fehler zaehlen.
;
;  Assemblieren: programme/bauen.sh speichertest
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
UHR    = $C110

ERSTE  = $04
	.weak
LETZTE = $FE                    ; Bank $FF ist das BASIC-ROM; zum Simulieren: 64tass -D LETZTE=5
	.endweak

zeiger = $80                    ; 3 Byte
bank   = $84
muster = $86                    ; 16 Bit
fehler = $88                    ; 24 Bit
t0     = $8C                    ; 16 Bit

	* = $2000

start
	.as
	.xl
	phb
	ldx #t_titel
	jsr PRINT
	lda #$01                    ; Tempo im Chip-RAM
	ldx #t_chip
	jsr tempo
	lda #$04                    ; Tempo im Zusatzspeicher
	ldx #t_zus
	jsr tempo

	ldx #t_schreiben
	jsr PRINT
	lda #ERSTE
	sta bank
-	jsr bank_zeigen
	jsr bank_schreiben
	lda bank
	cmp #LETZTE
	beq +
	inc bank
	bra -
+	ldx #t_lesen
	jsr PRINT
	#akku16
	stz fehler
	#akku8
	stz fehler+2
	lda #ERSTE
	sta bank
-	jsr bank_zeigen
	jsr bank_pruefen
	lda bank
	cmp #LETZTE
	beq +
	inc bank
	bra -
+	ldx #t_fehler
	jsr PRINT
	lda fehler+2
	jsr HEX8
	lda fehler+1
	jsr HEX8
	lda fehler
	jsr HEX8
	lda #13
	jsr CHROUT
	plb
	rtl

; A = Bank, X = Text: 16 KB schreiben und lesen, Zeiten in us (hex)
tempo
	sta zeiger+2
	stz zeiger
	stz zeiger+1
	jsr PRINT
	jsr uhr_start
	#akku16
	ldy #0
-	tya
	sta [zeiger],y
	iny
	iny
	cpy #$4000
	bne -
	#akku8
	jsr uhr_zeigen
	jsr uhr_start
	#akku16
	ldy #0
-	lda [zeiger],y
	iny
	iny
	cpy #$4000
	bne -
	#akku8
	jsr uhr_zeigen
	lda #13
	jsr CHROUT
	rts

uhr_start
	stz UHR
	#akku16
	lda UHR
	sta t0
	#akku8
	rts

uhr_zeigen                      ; vergangene us (16 Bit) hex ausgeben
	stz UHR
	#akku16
	lda UHR
	sec
	sbc t0
	sta t0
	#akku8
	lda #' '
	jsr CHROUT
	lda t0+1
	jsr HEX8
	lda t0
	jsr HEX8
	rts

bank_zeigen                     ; Banknummer an den Zeilenanfang
	lda #13
	jsr CHROUT
	lda #$1e                    ; Cursor hoch
	jsr CHROUT
	lda #' '
	jsr CHROUT
	lda #'$'
	jsr CHROUT
	lda bank
	jsr HEX8
	rts

; Muster: Wort = Adresse in der Bank XOR (Bank * $0101 + $5A3C)
muster_setzen
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

bank_schreiben
	lda bank
	jsr muster_setzen
	#akku16
	ldy #0
-	tya
	eor muster
	sta [zeiger],y
	iny
	iny
	bne -
	#akku8
	rts

bank_pruefen
	lda bank
	jsr muster_setzen
	#akku16
	ldy #0
-	tya
	eor muster
	cmp [zeiger],y
	beq +
	inc fehler                  ; 16 Bit, Uebertrag ins dritte Byte
	bne +
	#akku8
	inc fehler+2
	#akku16
+	iny
	iny
	bne -
	#akku8
	rts

t_titel
	.text 13, "SPEICHERTEST - expansion memory (SDRAM)", 13
	.text "16 KB write/read in us (hex):", 13, 0
t_chip
	.text " Chip RAM    ", 0
t_zus
	.text " Expansion   ", 0
t_schreiben
	.text "Writing pattern, bank", 13, 13, 0
t_lesen
	.text 13, "Checking, bank", 13, 13, 0
t_fehler
	.text 13, "Errors (words): $", 0
