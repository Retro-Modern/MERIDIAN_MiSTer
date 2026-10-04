;============================================================================
;  DOSTEST - das DOS direkt aufrufen (Etappe 10)
;
;  Laufwerk 1: Verzeichnis, freier Platz, REGEN.BAS laden, als TEST.BIN mit
;  MER-Kopf schreiben, KRANTEST.MER entfernen, Verzeichnis noch einmal.
;  Laufwerk 2: neu anlegen (LEEREN) und Verzeichnis zeigen.
;
;  Assemblieren: programme/bauen.sh dostest
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
DOS    = $FF4000

D_LW       = $16C0
D_FEHLER   = $16C1
D_MER      = $16C2
D_ENDUNG   = $16C3
D_TLEN     = $16C6
D_TEXT     = $16C7
D_ADR      = $16E4
D_LAENGE   = $16E8
D_INDEX    = $16EC

	* = $2000

start
	.as
	.xl
	phb
	ldx #t_titel
	jsr PRINT
	lda #1
	sta D_LW
	jsr verzeichnis
	jsr freier_platz

	ldx #t_laden                ; REGEN.BAS nach $05:0000
	jsr PRINT
	ldx #n_regen
	jsr name_setzen
	#akku16
	lda #$0000
	sta D_ADR
	lda #$ffff
	sta D_LAENGE
	lda #$00ff
	sta D_LAENGE+2
	#akku8
	lda #$05
	sta D_ADR+2
	lda #0
	jsl DOS
	jsr fehler_zeigen
	lda D_LAENGE+1
	jsr HEX8
	lda D_LAENGE
	jsr HEX8
	lda #' '
	jsr CHROUT
	ldx #0
-	lda $050000,x
	jsr CHROUT
	inx
	cpx #12
	bne -
	lda #13
	jsr CHROUT

	ldx #t_sichern              ; als TEST.BIN mit MER-Kopf
	jsr PRINT
	ldx #n_test
	jsr name_setzen
	#akku16
	lda #$0000
	sta D_ADR
	#akku8
	lda #$05
	sta D_ADR+2
	stz D_LAENGE+2
	lda #1
	sta D_MER
	lda #1
	jsl DOS
	jsr fehler_zeigen
	lda #13
	jsr CHROUT

	ldx #t_entfernen            ; KRANTEST.MER weg
	jsr PRINT
	ldx #n_kran
	jsr name_setzen
	lda #2
	jsl DOS
	jsr fehler_zeigen
	lda #13
	jsr CHROUT
	jsr verzeichnis
	jsr freier_platz

	ldx #t_leeren               ; Laufwerk 2 neu anlegen
	jsr PRINT
	lda #2
	sta D_LW
	ldx #n_leer
	jsr name_setzen
	lda #5
	jsl DOS
	jsr fehler_zeigen
	lda #13
	jsr CHROUT
	jsr verzeichnis
	jsr freier_platz
	plb
	rtl

verzeichnis
	#akku16
	stz D_INDEX
	#akku8
_naechste
	lda #3
	jsl DOS
	cmp #0
	beq _zeigen
	cmp #2                      ; 2: keine weitere Datei
	beq _ende
	jsr fehler_zeigen
_ende
	rts
_zeigen
	lda #' '
	jsr CHROUT
	ldx #0
_zeichen
	txa
	cmp D_TLEN
	beq _groesse
	lda D_TEXT,x
	jsr CHROUT
	inx
	bra _zeichen
_groesse
	lda #' '
	jsr CHROUT
	lda D_LAENGE+2
	jsr HEX8
	lda D_LAENGE+1
	jsr HEX8
	lda D_LAENGE
	jsr HEX8
	lda #13
	jsr CHROUT
	bra _naechste

freier_platz
	ldx #t_frei
	jsr PRINT
	lda #4
	jsl DOS
	lda D_LAENGE+3
	jsr HEX8
	lda D_LAENGE+2
	jsr HEX8
	lda D_LAENGE+1
	jsr HEX8
	lda D_LAENGE
	jsr HEX8
	lda #13
	jsr CHROUT
	rts

fehler_zeigen                   ; " Fehler n"
	pha
	ldx #t_fehler
	jsr PRINT
	pla
	jsr HEX8
	lda #' '
	jsr CHROUT
	rts

name_setzen                     ; X = Text mit 0 am Ende -> D_TEXT/D_TLEN
	ldy #0
_zeichen
	lda 0,x
	beq _ende
	sta D_TEXT,y
	inx
	iny
	bra _zeichen
_ende
	tya
	sta D_TLEN
	lda #'B'
	sta D_ENDUNG
	lda #'A'
	sta D_ENDUNG+1
	lda #'S'
	sta D_ENDUNG+2
	rts

t_titel	.text 13, "DOSTEST - drive 1:", 13, 0
t_frei	.text " free: $", 0
t_laden	.text "Load REGEN.BAS:", 0
t_sichern .text "Save TEST.BIN:", 0
t_entfernen .text "Scratch KRANTEST.MER:", 0
t_leeren .text "Format drive 2:", 0
t_fehler .text " error ", 0
n_regen	.text "regen.bas", 0
n_test	.text "test.bin", 0
n_kran	.text "KRANTEST.MER", 0
n_leer	.text "EMPTY", 0
