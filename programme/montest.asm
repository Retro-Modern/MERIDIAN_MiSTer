;============================================================================
;  MONTEST - Selbsttest fuer Disassembler und Assembler des Monitors
;  (Etappe 13)
;
;  Fuer jeden der 256 Opcodes, einmal mit 8-Bit- und einmal mit 16-Bit-
;  Registern: Befehl mit den Bytes $12 $34 $56 hinlegen, disassemblieren
;  (MON_DIS), den Text ab Spalte 20 wieder uebersetzen (MON_ASM) und die
;  Bytes vergleichen. Zeigt jede Abweichung und am Ende die Zahl der Fehler.
;
;  Bauen: programme/bauen.sh montest  ->  programme/montest.mer
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

CHROUT   = $FF80
HEX8     = $FF8C
MON_DIS  = $FF4015
MON_ASM  = $FF4018

ARG1     = $2C                  ; Kern: langer Zeiger fuer den Monitor
EINGABE  = $0210
MO_FLAGS = $02B0
MO_LEN   = $02B4
MO_PUF   = $17C8
TEST     = $6000                ; Probeplatz in Bank 0

OP       = $80                  ; direkte Seite (BASIC laeuft nicht)
FLAGGEN  = $81
FEHLER   = $82                  ; 16 Bit

	* = $2000

	.as
	.xl
	#akku16
	stz FEHLER
	#akku8
	ldx #t_titel
	jsr text
	lda #$30                    ; erst 8 Bit, dann 16 Bit
	sta FLAGGEN
_runde
	stz OP
_befehl
	lda OP                      ; Befehl hinlegen
	sta TEST
	lda #$12
	sta TEST+1
	lda #$34
	sta TEST+2
	lda #$56
	sta TEST+3
	jsr zeiger
	jsl MON_DIS
	ldx #0                      ; Text ab Spalte 20 nach EINGABE
-	lda MO_PUF+20,x
	sta EINGABE,x
	beq +
	inx
	bra -
+	lda #$ea                    ; Platz mit NOPs ueberschreiben
	sta TEST
	sta TEST+1
	sta TEST+2
	sta TEST+3
	jsr zeiger
	jsl MON_ASM
	bcs _falsch
	ldx #0                      ; Bytes vergleichen
	lda TEST
	cmp OP
	bne _falsch
	lda MO_LEN
	cmp #1
	beq _gut
	lda TEST+1
	cmp #$12
	bne _falsch
	lda MO_LEN
	cmp #2
	beq _gut
	lda TEST+2
	cmp #$34
	bne _falsch
	lda MO_LEN
	cmp #3
	beq _gut
	lda TEST+3
	cmp #$56
	bne _falsch
	bra _gut
_falsch
	#akku16
	inc FEHLER
	#akku8
	lda OP                      ; "op: text"
	jsr HEX8
	lda #':'
	jsr CHROUT
	ldx #0
-	lda MO_PUF+20,x
	beq +
	jsr CHROUT
	inx
	bra -
+	lda #13
	jsr CHROUT
_gut
	inc OP
	bne _befehl
	lda FLAGGEN
	beq _fertig
	stz FLAGGEN
	jmp _runde
_fertig
	ldx #t_fehler
	jsr text
	lda FEHLER+1
	jsr HEX8
	lda FEHLER
	jsr HEX8
	lda #13
	jsr CHROUT
	rtl

zeiger                          ; ARG1 = TEST, Breiten setzen
	lda #<TEST
	sta ARG1
	lda #>TEST
	sta ARG1+1
	stz ARG1+2
	lda FLAGGEN
	sta MO_FLAGS
	rts

text
-	lda 0,x
	beq +
	jsr CHROUT
	inx
	bra -
+	rts

t_titel	.text 13, "MONTEST: 2 x 256 opcodes", 13, 0
t_fehler	.text "ERRORS: $", 0
