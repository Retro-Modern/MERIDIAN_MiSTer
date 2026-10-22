;============================================================================
;  SPRITEDATA - die Spritemuster der Werkstatt als DATA-Zeilen ins
;  BASIC-Programm (22.10.2026; Taste B in SPRITES, rom/ws_austausch.asm)
;
;  Aufruf: JSL $FF401B mit Akku 8 Bit, Indexregistern 16 Bit, nur aus dem
;  Direktmodus von BASIC (die Werkstatt) und nur mit Zusatzspeicher.
;  Y = Puffer in Bank 0 (6 Byte) fuer die erste Zeilennummer als Text.
;  Zurueck: A = 0 gut, $FA alter Block nicht am Ende des Programms, $FB
;  keine Zeilennummern mehr frei, $FC zu wenig BASIC-Speicher, $FF kein
;  Muster belegt; X = Zahl der Muster. Y geht verloren.
;
;  Haengt an das Programm in Bank 1 an (Schritt 10), was auch
;  tools/cartridge.py data am Mac schreibt:
;
;   9000 REM SPRITE PATTERNS FROM THE WORKSHOP - GOSUB 9000
;   9010 DIM PB(127):RESTORE
;   9020 READ A$:IF A$<>"SPRITEDATA" THEN 9020
;   9030 READ M:IF M<0 THEN RETURN
;   9040 READ PB(M):FOR Z=0 TO 15:READ A$:PATTERN M,Z,A$:NEXT:GOTO 9030
;   9050 DATA SPRITEDATA
;   je belegtem Muster: DATA Nummer,Bank und vier Zeilen DATA mit je vier
;   Pixelzeilen (16 Hexziffern, "." = durchsichtig), zuletzt DATA -1
;  RESTORE und die Kennung SPRITEDATA: Das Programm darf davor eigene DATA
;  haben, READ ueberliest sie (als Text geht jedes DATA-Element).
;
;  Erste Zeile 9000; reicht das Programm schon so weit, der naechste volle
;  Tausender dahinter. Endet das Programm mit so einem Block (die Zeile mit
;  diesem REM, als letzte Zeile DATA -1), ersetzt es ihn an seiner Stelle.
;  Die Kopfzeilen liegen fertig umgewandelt in sprite_kopf.inc (rom/bauen.sh
;  erzeugt sie mit tools/bas.py aus dem gebauten BASIC); ein Byte n unter
;  $20 darin steht fuer die Zeilennummer Anfang + (n - 1) x 10. Wie alle
;  Tabellen des System-ROM nur lang lesen (ROM + Marke).
;  Danach gilt wie nach jeder geaenderten Zeile CLR: Variablen weg, DATA
;  von vorn, kein CONT. Der Platz wird vorher ausgerechnet, mit 1 KB Rest
;  fuer die Variablen des Unterprogramms (PB() allein braucht 650 Byte).
;  Bei einem Fehler bleibt alles, wie es war.
;============================================================================

	.include "basic_sym.inc"    ; B_TXTTAB ... (basic/bauen.sh)

SX_MUSTER  = $F80000            ; Werkstatt: 128 Muster zu 128 Byte
SX_BANK    = $F84000            ;   und ihre Baenke
SX_TXTTAB  = $000000 + B_TXTTAB ; BASIC (Bank 0, lang - D zeigt auf den Rahmen)
SX_VARTAB  = $000000 + B_VARTAB
SX_ARYTAB  = $000000 + B_ARYTAB
SX_STREND  = $000000 + B_STREND
SX_FRETOP  = $000000 + B_FRETOP
SX_MEMSIZ  = $000000 + B_MEMSIZ
SX_DATPTR  = $000000 + B_DATPTR
SX_OLDTXT  = $000000 + B_OLDTXT
SX_RESERVE = 1024
SX_JE_MUSTER = 304              ; Bytes je Muster ohne die Ziffern von Nummer
                                ; und Bank: 8 + 4 x 74

; Rahmen auf dem Stapel (D zeigt darauf)
sx_p      = $00                 ; Schreibzeiger in Bank 1
sx_zeile  = $02                 ; Anfang der Zeile, die gerade entsteht
sx_nr     = $04                 ; naechste Zeilennummer
sx_m      = $06                 ; Muster
sx_zahl   = $08                 ; belegte Muster
sx_groesse = $0a                ; Bytes, die dazukommen
sx_alt    = $0c                 ; alter Block (0 = keiner)
sx_letzte = $0e                 ; letzte Zeile des Programms
sx_tmp    = $10
sx_ziffer = $12                 ; Dezimalausgabe: schon eine Ziffer geschrieben
sx_teiler = $14
sx_hoechste = $16               ; hoechste Zeilennummer vor dem alten Block
sx_anfang = $18                 ; erste Zeilennummer des Blocks
sx_puffer = $1a                 ; Puffer des Aufrufers (Bank 0)
SX_RAHMEN = $1c

sprite_data
	.as
	.xl
	php
	phb
	phd
	rep #$30
	.al
	tsc
	sec
	sbc #SX_RAHMEN
	tcs
	inc a
	tcd
	sty sx_puffer
	sep #$20
	.as
	lda #1                      ; Datenbank 1: das Programm
	pha
	plb
	rep #$20
	.al

	; 1. Das Programm ablaufen: Ende, hoechste Nummer, alter Block
	stz sx_alt
	stz sx_hoechste
	lda @l SX_TXTTAB
	sta sx_p
	sta sx_letzte
_suchen
	lda (sx_p)
	beq _ende
	ldx sx_alt                  ; im alten Block: nur bis zum Ende laufen
	bne _nachfolger
	ldy #2
	lda (sx_p),y
	sta sx_nr
	jsr sx_unser_rem
	bcs +
	lda sx_nr
	sta sx_hoechste
	bra _nachfolger
+	lda sx_p
	sta sx_alt
	lda sx_nr
	sta sx_anfang
_nachfolger
	lda sx_p
	sta sx_letzte
	lda (sx_p)
	sta sx_p
	bra _suchen
_ende
	lda sx_alt                  ; alter Block: endet das Programm damit?
	beq _neu
	ldy #4
	lda (sx_letzte),y
	cmp #SX_DATATK | (' ' << 8)
	bne _nicht_am_ende
	ldy #6
	lda (sx_letzte),y
	cmp #'-' | ('1' << 8)
	bne _nicht_am_ende
	ldy #8
	lda (sx_letzte),y
	and #$00ff
	bne _nicht_am_ende
	lda sx_alt                  ; ja: an seiner Stelle neu schreiben
	sta sx_p
	bra _zaehlen
_nicht_am_ende
	lda #$fa
	jmp sx_raus
_neu
	lda #9000                   ; 9000 oder der Tausender hinter dem Programm
	sta sx_anfang
-	lda sx_hoechste
	cmp sx_anfang
	bcc _zaehlen
	lda sx_anfang
	adc #1000 - 1               ; C = 1
	sta sx_anfang
	bra -

	; 2. Belegte Muster zaehlen und den Platz ausrechnen
_zaehlen
	lda #2 + 9 + 3 * 4          ; Endmarke, DATA -1, drei Zeilennummern im Kopf
	sta sx_groesse
	ldx #0
-	lda @l ROM + sx_kopf,x            ; Kopfzeilen: Laenge + Verkettung, Nummer, Ende
	and #$00ff
	beq +
	sta sx_tmp
	clc
	adc #5
	adc sx_groesse
	sta sx_groesse
	txa
	sec                         ; Laengenbyte mitzaehlen
	adc sx_tmp
	tax
	bra -
+	stz sx_zahl
	stz sx_m
_jedes_z
	jsr sx_belegt
	bcc _weiter_z
	inc sx_zahl
	lda sx_m
	jsr sx_stellen
	adc sx_groesse              ; C = 0 von sx_stellen
	adc #SX_JE_MUSTER
	sta sx_groesse
	ldx sx_m
	lda @l SX_BANK,x
	and #$00ff
	jsr sx_stellen
	adc sx_groesse
	sta sx_groesse
_weiter_z
	inc sx_m
	lda sx_m
	cmp #128
	bcc _jedes_z
	lda sx_zahl
	bne +
	lda #$ff                    ; nichts gemalt
	jmp sx_raus

	; 3. Reichen die Zeilennummern (letzte = Anfang + 50 x Muster + 60)?
+	asl a                       ; x 2
	sta sx_tmp
	asl a
	asl a
	asl a                       ; x 16
	adc sx_tmp
	sta sx_tmp
	asl a                       ; x 32
	adc sx_tmp                  ; = x 50
	adc #60
	adc sx_anfang
	bcs _keine_nummern
	cmp #64000
	bcc _platz
_keine_nummern
	lda #$fb
	jmp sx_raus

	; 4. Passt es? Programm + neue Zeilen + Rest unter MEMSIZ
_platz
	lda sx_p
	clc
	adc sx_groesse
	bcs _voll
	adc #SX_RESERVE
	bcs _voll
	cmp @l SX_MEMSIZ
	bcc _schreiben
_voll
	lda #$fc
	jmp sx_raus

	; 5. Schreiben
_schreiben
	lda sx_anfang
	sta sx_nr
	ldx #0                      ; die Kopfzeilen aus der Tabelle
_kopf
	lda @l ROM + sx_kopf,x
	and #$00ff
	beq _muster
	sta sx_tmp
	inx
	jsr sx_zeile_auf
	sep #$20
	.as
_kopfbyte
	lda @l ROM + sx_kopf,x
	cmp #$20
	bcs _normal
	rep #$20                    ; n: Zeilennummer Anfang + (n - 1) x 10
	.al
	phx
	and #$001f
	dec a
	asl a                       ; x 2
	sta sx_teiler
	asl a
	asl a                       ; x 8
	adc sx_teiler
	adc sx_anfang
	jsr sx_dezimal
	plx
	sep #$20
	.as
	bra +
_normal
	sta (sx_p)
	jsr sx_weiter
+	inx
	dec sx_tmp
	bne _kopfbyte
	jsr sx_zeile_zu
	rep #$20
	.al
	bra _kopf

_muster
	stz sx_m
_jedes
	jsr sx_belegt
	bcs +
	jmp _naechstes
+	jsr sx_data                 ; DATA Nummer,Bank
	lda sx_m
	jsr sx_dezimal
	lda #','
	jsr sx_byte
	ldx sx_m
	lda @l SX_BANK,x
	and #$00ff
	jsr sx_dezimal
	jsr sx_zeile_zu
	lda sx_m                    ; X = Anfang des Musters
	xba
	lsr a
	tax
	lda #4                      ; vier Zeilen zu vier Pixelzeilen
	sta sx_tmp
_zeile
	jsr sx_data
	ldy #4
_reihe
	sep #$20
	.as
	lda #8                      ; 8 Byte = 16 Pixel
	xba
-	lda @l SX_MUSTER,x
	lsr a
	lsr a
	lsr a
	lsr a
	jsr sx_hex
	lda @l SX_MUSTER,x
	and #$0f
	jsr sx_hex
	inx
	xba
	dec a
	beq +
	xba
	bra -
+	rep #$20
	.al
	dey
	beq +
	lda #','
	jsr sx_byte
	bra _reihe
+	jsr sx_zeile_zu
	dec sx_tmp
	bne _zeile
_naechstes
	inc sx_m
	lda sx_m
	cmp #128
	bcs +
	jmp _jedes
+	jsr sx_data                 ; DATA -1
	lda #'-' | ('1' << 8)
	sta (sx_p)
	jsr sx_weiter2
	jsr sx_zeile_zu
	lda #0                      ; Endmarke
	sta (sx_p)

	; 6. BASIC wie nach CLR
	lda sx_p
	clc
	adc #2
	sta @l SX_VARTAB
	sta @l SX_ARYTAB
	sta @l SX_STREND
	lda @l SX_MEMSIZ
	sta @l SX_FRETOP
	lda @l SX_TXTTAB
	dec a
	sta @l SX_DATPTR
	sep #$20
	.as
	lda #0
	sta @l SX_OLDTXT+1

	; 7. Erste Zeilennummer als Text in den Puffer des Aufrufers (Bank 0)
	pha                         ; Datenbank 0
	plb
	rep #$20
	.al
	lda sx_puffer
	sta sx_p
	lda sx_anfang
	jsr sx_dezimal
	lda #0
	jsr sx_byte
	lda #0

sx_raus                         ; A = Fehler (16 Bit)
	.al
	ldx sx_zahl
	tay
	tsc
	clc
	adc #SX_RAHMEN
	tcs
	tya
	pld
	plb
	plp
	rtl

; C = 1: Muster sx_m hat mindestens einen Punkt
sx_belegt
	.al
	lda sx_m
	xba
	lsr a
	tax
	ldy #64
-	lda @l SX_MUSTER,x
	bne +
	inx
	inx
	dey
	bne -
	clc
	rts
+	sec
	rts

; A = Zahl der Dezimalstellen von A (0-999), C = 0
sx_stellen
	.al
	cmp #10
	bcc _eins
	cmp #100
	bcc _zwei
	lda #3
	clc
	rts
_zwei
	lda #2
	rts                         ; C = 0
_eins
	lda #1
	rts

; neue Zeile: Verkettung freilassen, Nummer schreiben (A16)
sx_zeile_auf
	.al
	lda sx_p
	sta sx_zeile
	ldy #2
	lda sx_nr
	sta (sx_p),y
	clc
	adc #10
	sta sx_nr
	lda sx_p
	clc
	adc #4
	sta sx_p
	rts

; DATA und Leerzeichen an den Anfang einer neuen Zeile (A16)
sx_data
	.al
	jsr sx_zeile_auf
	lda #SX_DATATK | (' ' << 8)
	sta (sx_p)

; zwei Bytes weiter
sx_weiter2
	jsr sx_weiter
; ein Byte weiter (A8 oder A16)
sx_weiter
	php
	rep #$20
	inc sx_p
	plp
	rts

; Zeile abschliessen: 0, dann die Verkettung der Zeile (A8 oder A16)
sx_zeile_zu
	php
	sep #$20
	.as
	lda #0
	sta (sx_p)
	rep #$20
	.al
	inc sx_p
	lda sx_p
	sta (sx_zeile)
	plp
	rts

; ein Zeichen (A, unteres Byte) anhaengen (A8 oder A16)
sx_byte
	php
	sep #$20
	sta (sx_p)
	rep #$20
	inc sx_p
	plp
	rts

; Halbbyte A (A8) als Hexziffer, 0 als "."
sx_hex
	.as
	cmp #0
	bne +
	lda #'.'
	bra sx_byte
+	cmp #10
	bcc +
	adc #'A' - 10 - 1           ; C = 1
	bra sx_byte
+	ora #'0'
	bra sx_byte

; A (A16) dezimal ohne fuehrende Nullen anhaengen; X, Y gehen verloren
sx_dezimal
	.al
	stz sx_ziffer
	ldy #10000
	jsr _stelle
	ldy #1000
	jsr _stelle
	ldy #100
	jsr _stelle
	ldy #10
	jsr _stelle
	ldy #1
	inc sx_ziffer               ; die Einer immer
_stelle                         ; A = Rest, Y = Stellenwert
	sty sx_teiler
	ldx #0
-	cmp sx_teiler
	bcc +
	sbc sx_teiler
	inx
	bra -
+	pha
	txa
	ora sx_ziffer
	beq +                       ; fuehrende Null
	txa
	ora #'0'
	jsr sx_byte
	inc sx_ziffer
+	pla
	rts

; C = 1: die Zeile bei sx_p beginnt mit unserem REM (bis zur Zeilennummer)
sx_unser_rem
	.al
	sep #$20
	.as
	ldx #1
	ldy #4
-	lda @l ROM + sx_kopf,x
	cmp #$20
	bcc _ja
	cmp (sx_p),y
	bne _nein
	inx
	iny
	bra -
_ja
	rep #$20
	.al
	sec
	rts
_nein
	rep #$20
	.al
	clc
	rts

	.include "sprite_kopf.inc"  ; sx_kopf (die Kopfzeilen), SX_DATATK
