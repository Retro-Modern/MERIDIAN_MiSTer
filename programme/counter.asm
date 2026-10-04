;============================================================================
;  COUNTER - Testmodul (Etappe 10, bis zum Sprachwechsel ZÄHLER)
;
;  Ein Modul ist ein ROM-Abbild ab $40:0000 (Menü "Insert cartridge"). Der
;  Kern ruft es beim Start per JSL auf. COUNTER kopiert seinen Programmteil
;  nach $00:4800 - dort erreicht er die Kernroutinen per JSR -, zählt im
;  Speicherstand (Laufwerk 0, Block 0) mit, wie oft er schon gestartet
;  wurde, prüft den Schreibschutz des Modul-ROMs und kehrt ins BASIC
;  zurück.
;
;  Bauen: programme/modul.sh counter  ->  programme/counter.mod
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

CHROUT  = $FF80
PRINT   = $FF86
PRDEZ   = $FF89
HEX8    = $FF8C
ZAHL    = $1A                   ; Zahl für PRDEZ (16 Bit)
DOS     = $FF4000
D_LW    = $16C0
D_ADR   = $16E4
D_BLOCK = $16F4
PUFFER  = $5000                 ; Block des Speicherstands (512 Byte)

;---------------------------------------------------------------- Modulkopf
	* = $400000
	.text "MODUL816"            ; Kennung
	.byte 1                     ; Version
	.byte 0                     ; Flags
	.long einsprung             ; Startadresse
	.byte 0, 0, 0
	.text "COUNTER"             ; Name, 16 Zeichen
	.fill 16 - 7, 0

;---------------------------------------------------------------- im ROM
einsprung                       ; läuft in Bank $40
	.as
	.xl
	phb
	#akku16
	lda #ram_ende - ram_anfang - 1
	ldx #<>ram_quelle
	ldy #ram_anfang
	mvn #`ram_quelle, #0        ; Datenbank danach 0
	#akku8
	jsl haupt
	plb
	rtl

;---------------------------------------------------------------- im RAM
ram_quelle
	.logical $4800
ram_anfang

haupt
	.as
	.xl
	ldx #t_titel
	jsr PRINT

	stz D_LW                    ; Laufwerk 0: Speicherstand des Moduls
	#akku16
	stz D_BLOCK
	stz D_BLOCK+2
	lda #PUFFER
	sta D_ADR
	#akku8
	stz D_ADR+2
	lda #6                      ; Block lesen
	jsl DOS
	cmp #0
	beq +
	jmp kein_stand
+	#akku16
	lda PUFFER                  ; schon einmal geschrieben?
	cmp kennung
	bne _neu
	lda PUFFER+2
	cmp kennung+2
	beq _zaehlen
_neu
	lda kennung                 ; nein: neu anfangen
	sta PUFFER
	lda kennung+2
	sta PUFFER+2
	stz PUFFER+4
_zaehlen
	inc PUFFER+4
	#akku8
	lda #7                      ; Block schreiben
	jsl DOS
	cmp #0
	bne kein_stand
	ldx #t_start
	jsr PRINT
	#akku16
	lda PUFFER+4
	sta ZAHL
	#akku8
	jsr PRDEZ
	lda #13
	jsr CHROUT

schutz
	lda @l $400000              ; Modul-ROM beschreiben ...
	eor #$ff
	sta @l $400000
	lda @l $400000              ; ... und nachsehen
	ldx #t_rom
	cmp #'M'
	beq +
	ldx #t_ram
+	jsr PRINT
	rtl

kein_stand
	pha
	ldx #t_kein
	jsr PRINT
	pla
	jsr HEX8
	lda #13
	jsr CHROUT
	bra schutz

kennung	.text "CNTR"
t_titel	.text "COUNTER - a cartridge for the MERIDIAN", 13, 0
t_start	.text "Start no. ", 0
t_kein	.text "No save file, error ", 0
t_rom	.text "Cartridge ROM is write-protected", 13, 0
t_ram	.text "Cartridge ROM can be written!", 13, 0

ram_ende
	.endlogical
