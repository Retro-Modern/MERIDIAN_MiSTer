;============================================================================
;  EDIT: die Zeilen des Programms ordnen (24.11.2026)
;  (eingebunden von dos.asm; EDIT ruft ed_sortieren in Bank $FF ueber rom/dos_sym.inc)
;
;  EDIT macht aus dem Text ein Programm wie beim Eintippen aller Zeilen.
;  Beim Eintippen ordnet BASIC die Zeilen nach ihrer Nummer, und eine
;  Zeile ersetzt die fruehere mit derselben Nummer. Das tut ed_sortieren
;  mit dem Programm, das ed_crunch (rom/edit.asm) in Textreihenfolge nach
;  $E6:0000 geschrieben hat: Saetze aus Verweis (2), Nummer (2), Tokens und
;  einer 0, am Ende 0, 0. Danach stehen die Verweise neu.
;
;  Die Routine liegt im System-ROM, weil das SONG-ROM (mit EDIT) voll ist.
;
;  Rufen mit JSR (Bank $FF), A (16 Bit) = Adresse der ersten Zeile im
;  BASIC-Speicher (fuer die Verweise). Zurueck: A (16 Bit) = Laenge des
;  Programms mit den beiden Nullen am Ende. P, D und B bleiben erhalten.
;
;  Einfuegen nach Nummer: Satz R steht hinter den schon geordneten Saetzen;
;  der erste davor mit Nummer >= der von R heisst Q. Gleiche Nummer: Q
;  faellt weg. Groessere: R wandert vor Q (R nach $E6:FF00, Q.. nach oben,
;  R an Qs Stelle). Ein Satz ist hoechstens 4 + 250 + 1 Byte lang.
;============================================================================

ES_PUFFER = $E60000             ; das Programm (ED_TMP in edit.asm)
ES_ABLAGE = $E6FF00             ; ein Satz (hinter ED_MAX = $FF00)

; Rahmen auf dem Stapel (D zeigt darauf)
ES_P     = 1                    ; Satz R (Abstand in ES_PUFFER)
ES_Q     = 3                    ; Satz Q
ES_LR    = 5                    ; Laenge von R
ES_NR    = 7                    ; Nummer von R
ES_ENDE  = 9                    ; wo die beiden Nullen stehen
ES_BASIS = 11                   ; Adresse der ersten Zeile
ES_T     = 13
ES_GROESSTE = 15                ; groesste Nummer der geordneten Saetze
ES_RAHMEN = 16

ed_sortieren
	php
	phb
	rep #$30
	.al
	.xl
	phd
	tax                         ; die Basis
	tsc
	sec
	sbc #ES_RAHMEN
	tcs
	tcd
	stx ES_BASIS
	stz ES_P                    ; wo die Nullen stehen
	jsr _bis_ende
	sta ES_ENDE
	stz ES_P
_naechster                      ; Satz R bei ES_P
	ldx ES_P
	cpx ES_ENDE
	bcs _verweise
	lda @l ES_PUFFER+2,x
	sta ES_NR
	jsr _laenge
	sta ES_LR
	ldx ES_P                    ; der erste, oder groesser als alle davor
	beq _bleibt                 ; (so geht ein geordnetes Programm schnell)
	lda ES_NR
	cmp ES_GROESSTE
	beq +
	bcs _bleibt
+	stz ES_Q
_suchen
	lda ES_Q
	cmp ES_P
	bcs _bleibt                 ; keiner davor ist groesser: R bleibt
	tax
	lda @l ES_PUFFER+2,x
	cmp ES_NR
	bcs _gefunden
	jsr _laenge
	clc
	adc ES_Q
	sta ES_Q
	bra _suchen
_bleibt
	lda ES_NR
	sta ES_GROESSTE
_weiter
	lda ES_P
	clc
	adc ES_LR
	sta ES_P
	bra _naechster
_gefunden
	bne _einfuegen
	jsr _laenge                 ; gleiche Nummer: Q faellt weg
	sta ES_T
	txy                         ; nach Q
	clc
	adc ES_Q
	tax                         ; von Q + Laenge
	stx ES_Q
	lda ES_ENDE                 ; bis hinter die Nullen: ES_ENDE + 2 - X Byte
	inc a
	sec
	sbc ES_Q
	mvn `ES_PUFFER, `ES_PUFFER
	lda ES_ENDE
	sec
	sbc ES_T
	sta ES_ENDE
	lda ES_P
	sec
	sbc ES_T
	sta ES_P
	bra _naechster              ; R noch einmal (steht jetzt weiter vorn)
_einfuegen
	lda ES_LR                   ; R zur Seite
	dec a
	ldx ES_P
	ldy #<>ES_ABLAGE
	mvn `ES_PUFFER, `ES_ABLAGE
	lda ES_P                    ; Q bis vor R um ES_LR nach oben
	dec a
	tax                         ; letztes Byte davon
	clc
	adc ES_LR
	tay
	lda ES_P
	sec
	sbc ES_Q
	dec a
	mvp `ES_PUFFER, `ES_PUFFER
	lda ES_LR                   ; R an Qs Stelle
	dec a
	ldx #<>ES_ABLAGE
	ldy ES_Q
	mvn `ES_ABLAGE, `ES_PUFFER
	bra _weiter                 ; (die groesste bleibt)
_verweise                       ; die Verweise neu
	stz ES_P
	jsr _bis_ende
	clc
	adc #2
	tax                         ; die Laenge
	tdc
	clc
	adc #ES_RAHMEN
	tcs
	pld
	txa
	plb
	plp
	rts

; Saetze ab ES_P bis zu den Nullen; jeder Verweis = Basis + Abstand des
; naechsten. A = Abstand der Nullen.
_bis_ende
	ldx ES_P
	lda @l ES_PUFFER,x
	beq +
	jsr _laenge
	clc
	adc ES_P
	sta ES_P
	clc
	adc ES_BASIS
	sta @l ES_PUFFER,x
	bra _bis_ende
+	txa
	rts

; A = Laenge des Satzes bei X (X bleibt)
_laenge
	phx
	inx
	inx
	inx
	inx
	sep #$20
	.as
-	lda @l ES_PUFFER,x
	beq +
	inx
	bra -
+	rep #$20
	.al
	inx
	txa
	sec
	sbc 1,s
	plx
	rts
