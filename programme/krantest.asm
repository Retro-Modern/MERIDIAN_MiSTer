;============================================================================
;  KRANTEST - KRAN und der Zusatzspeicher (Etappe 9a)
;
;  Je 32 KB mit KRAN bewegen und die Zeit mit der Mikrosekundenuhr messen:
;  Chip -> Chip (Vergleich), Fuellen im Zusatzspeicher, Chip -> Zusatz,
;  Zusatz -> Chip, Zusatz -> Zusatz. Jedes Ergebnis prueft die CPU Byte fuer
;  Byte. Zum Schluss schreibt und liest die CPU im Zusatzspeicher, waehrend
;  KRAN dort kopiert - beide muessen richtig ankommen.
;
;  Assemblieren: programme/bauen.sh krantest
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
PRDEZ  = $FF89
zahl   = $1A                    ; 16 Bit fuer PRDEZ
UHR    = $C110
KRAN   = $C600
K_BEF  = $C610

GROESSE = 32768
CHIP_A  = $010000               ; Muster
CHIP_B  = $018000               ; Ziel im Chip-RAM
ZUS_A   = $050000
ZUS_B   = $060000
ZUS_C   = $070000
ZUS_D   = $080000               ; CPU, waehrend KRAN arbeitet
CPU_N   = 1024

zeiger  = $80                   ; 3 Byte
t0      = $84                   ; 16 Bit
fehler  = $86                   ; 16 Bit
hi      = $88
umkehr  = $89                   ; 0 oder $FF: Muster umgedreht
lief    = $8A                   ; KRAN arbeitete noch, als die CPU fertig war

; Auftrag in job eintragen: Quelle, Ziel, Modus
auftrag	.macro quelle, ziel, modus
	#akku16
	lda #<>\quelle
	sta job
	lda #<>\ziel
	sta job+3
	#akku8
	lda #`\quelle
	sta job+2
	lda #`\ziel
	sta job+5
	lda #\modus
	sta job+15
	.endm

	* = $2000

start
	.as
	.xl
	phb
	ldx #t_titel
	jsr PRINT

	; Muster ins Chip-RAM
	stz umkehr
	lda #`CHIP_A
	ldx #<>CHIP_A
	jsr zeiger_setzen
	ldy #0
-	jsr muster
	sta [zeiger],y
	iny
	cpy #GROESSE
	bne -

	; Breite 32 KB, eine Zeile
	#akku16
	lda #GROESSE
	sta job+6
	lda #1
	sta job+8
	stz job+10
	stz job+12
	#akku8
	lda #$A5
	sta job+14

	#auftrag CHIP_A, CHIP_B, 0
	jsr kran_los
	ldx #t_cc
	jsr zeit_zeigen
	lda #`CHIP_B
	ldx #<>CHIP_B
	jsr pruefen

	#auftrag 0, ZUS_A, 1        ; fuellen
	jsr kran_los
	ldx #t_fz
	jsr zeit_zeigen
	jsr fuellung_pruefen

	#auftrag CHIP_A, ZUS_A, 0
	jsr kran_los
	ldx #t_cz
	jsr zeit_zeigen
	lda #`ZUS_A
	ldx #<>ZUS_A
	jsr pruefen

	#auftrag ZUS_A, CHIP_B, 0
	jsr kran_los
	ldx #t_zc
	jsr zeit_zeigen
	lda #`CHIP_B
	ldx #<>CHIP_B
	jsr pruefen

	#auftrag ZUS_A, ZUS_B, 0
	jsr kran_los
	ldx #t_zz
	jsr zeit_zeigen
	lda #`ZUS_B
	ldx #<>ZUS_B
	jsr pruefen

	; KRAN kopiert Zusatz -> Zusatz, die CPU schreibt und liest gleichzeitig
	; dort (umgedrehtes Muster, jedes Byte sofort zurueckgelesen)
	#auftrag ZUS_A, ZUS_C, 0
	jsr kran_starten
	lda #$FF
	sta umkehr
	lda #`ZUS_D
	ldx #<>ZUS_D
	jsr zeiger_setzen
	#akku16
	stz fehler
	#akku8
	ldy #0
-	jsr muster
	sta [zeiger],y
	cmp [zeiger],y
	beq +
	#akku16
	inc fehler
	#akku8
+	iny
	cpy #CPU_N
	bne -
	lda K_BEF                   ; arbeitet KRAN noch? (sonst war der Test zu kurz)
	and #$01
	sta lief
	#akku16
	lda fehler
	pha
	#akku8
	jsr kran_warten
	ldx #t_par
	jsr PRINT
	lda lief
	clc
	adc #'0'
	jsr CHROUT
	ldx #t_cpu
	jsr PRINT
	#akku16
	pla
	sta zahl
	#akku8
	jsr PRDEZ
	lda #13
	jsr CHROUT
	ldx #t_cpu2                 ; CPU-Bereich danach noch einmal ganz pruefen
	jsr PRINT
	lda #`ZUS_D
	ldx #<>ZUS_D
	jsr zeiger_setzen
	ldy #CPU_N
	jsr pruefen_n
	stz umkehr
	ldx #t_kran
	jsr PRINT
	lda #`ZUS_C
	ldx #<>ZUS_C
	jsr zeiger_setzen
	ldy #GROESSE
	jsr pruefen_n
	lda #13
	jsr CHROUT
	plb
	rtl

kran_los                        ; Auftrag starten, warten, Zeit in zahl
	jsr kran_starten
kran_warten
-	lda K_BEF
	and #$01
	bne -
	stz UHR
	#akku16
	lda UHR
	sec
	sbc t0
	sta zahl
	#akku8
	rts

kran_starten
	ldx #0
-	lda job,x
	sta KRAN,x
	inx
	cpx #16
	bne -
	stz UHR
	#akku16
	lda UHR
	sta t0
	#akku8
	lda #$01
	sta K_BEF
	rts

zeit_zeigen                     ; Text ab X, dann zahl dezimal
	jsr PRINT
	jsr PRDEZ
	rts

zeiger_setzen                   ; zeiger = A:X
	stx zeiger
	sta zeiger+2
	rts

muster                          ; A = lo(Y) ^ hi(Y) ^ $5A ^ umkehr
	#akku16
	tya
	#akku8
	xba
	sta hi
	xba
	eor hi
	eor #$5A
	eor umkehr
	rts

pruefen                         ; 32 KB ab A:X gegen das Muster, Fehler zeigen
	jsr zeiger_setzen
	ldy #GROESSE
	ldx #t_fehler
	jsr PRINT
pruefen_n                       ; Y Bytes ab zeiger pruefen
	sty fehler                  ; Grenze merken
	#akku16
	lda fehler
	sta t0
	stz fehler
	#akku8
	ldy #0
-	jsr muster
	cmp [zeiger],y
	beq +
	#akku16
	inc fehler
	#akku8
+	iny
	cpy t0
	bne -
	#akku16
	lda fehler
	sta zahl
	#akku8
	jsr PRDEZ
	lda #13
	jsr CHROUT
	rts

fuellung_pruefen                ; 32 KB ab ZUS_A muessen $A5 sein
	ldx #t_fehler
	jsr PRINT
	lda #`ZUS_A
	ldx #<>ZUS_A
	jsr zeiger_setzen
	#akku16
	stz fehler
	#akku8
	ldy #0
-	lda [zeiger],y
	cmp #$A5
	beq +
	#akku16
	inc fehler
	#akku8
+	iny
	cpy #GROESSE
	bne -
	#akku16
	lda fehler
	sta zahl
	#akku8
	jsr PRDEZ
	lda #13
	jsr CHROUT
	rts

t_titel	.text 13, "KRANTEST - KRAN and expansion memory", 13
	.text "32 KB per job, time in us:", 13, 0
t_cc	.text " Chip   -> Chip   ", 0
t_fz	.text " Fill     Exp.    ", 0
t_cz	.text " Chip   -> Exp.   ", 0
t_zc	.text " Exp.   -> Chip   ", 0
t_zz	.text " Exp.   -> Exp.   ", 0
t_fehler .text "  errors ", 0
t_par	.text " In parallel (KRAN running: ", 0
t_cpu	.text ")", 13, "  CPU errors during ", 0
t_cpu2	.text "  CPU errors after  ", 0
t_kran	.text "  KRAN errors       ", 0

job	.fill 16
