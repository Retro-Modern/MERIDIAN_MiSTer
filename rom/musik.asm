;============================================================================
;  MUSIK - PLAY fuer BASIC (Etappe 11c), im ROM Bank $FF neben dem DOS
;
;  PLAY "noten"[,stimme] spielt auf einer der vier Synthesestimmen von
;  ORGEL, im Hintergrund: Der Kern ruft musik_takt in jedem Bild auf.
;
;  Noten (gross oder klein, Leerzeichen egal):
;   C D E F G A B   Note, danach # oder + (hoeher), - (tiefer), Laenge
;                   (1 ganze, 2, 4, 8, 16, 32, auch 3, 6, 12 ...) und . (punktiert)
;   R               Pause, Laenge wie bei Noten
;   O n  < >        Oktave 0-7 (Anfang 4), eine tiefer / hoeher
;   L n             Laenge ohne Angabe (Anfang 4 = Viertel)
;   T n             Tempo, Viertel je Minute 32-255 (Anfang 120)
;   W n             Welle 1 Dreieck, 2 Saegezahn, 3 Puls, 4 Rauschen
;   V n             Lautstaerke 0-15
;   !               von vorn (Endlosschleife)
;
;  Zeiten zaehlen in 1/16 Bildern: Tempo und Laengen bleiben auch bei
;  60 Bildern je Sekunde genau (der Rest wandert in die naechste Note).
;
;  Tabellen im ROM nur mit langer Adresse (ROM+...) lesen: die Datenbank
;  ist 0, damit die Chipregister erreichbar sind.
;
;  Arbeitsspeicher: direkte Seite $1700 ab $80 (das DOS nutzt nur bis $6A),
;  Notentexte im Zusatzspeicher ab $FE:1000 (256 Byte je Stimme).
;============================================================================

ORG_ST     = $C500              ; Stimme n ab $C500 + n * 16

; je Stimme 16 Byte ab $80 (X = Stimme * 16)
m_akt   = $80                   ; 0: still
m_pos   = $81                   ; naechstes Zeichen
m_tlen  = $82                   ; Laenge des Textes
m_okt   = $83
m_len   = $84                   ; Laenge ohne Angabe
m_welle = $85                   ; STEUER-Bits der Welle
m_rest  = $86                   ; 2 Byte: Restzeit in 1/16 Bildern (mit Vorzeichen)
m_ganz  = $88                   ; 2 Byte: ganze Note in 1/16 Bildern
m_klang = $8A                   ; 1: eine Note klingt (Gate an)
m_zeiger = $F0                  ; 3 Byte: Notentext der Stimme
m_d32   = $F4                   ; 4 Byte: Dividend / Quotient
m_teiler = $F8                  ; 2 Byte
m_r16   = $FA                   ; 2 Byte: Rest
m_dauer = $FC                   ; 2 Byte
m_stimme = $FE                  ; Stimme * 16 (fuer Unterprogramme)

; Einsprung $FF:4003: A = 0 PLAY starten (Werte von BASIC), 1 alles still
musik_befehl
	.as
	.xl
	phd
	phb
	pha
	#akku16
	lda #$1700
	tcd
	#akku8
	lda #0
	pha
	plb
	pla
	cmp #1
	beq _still
	jsr musik_start
	bra _ende
_still
	jsr musik_aus
	lda #0
_ende
	.as
	plb
	pld
	rtl

; Einsprung $FF:4006: aus dem Interrupt, einmal je Bild
musik_takt
	.as
	.xl
	phd
	phb
	#akku16
	lda #$1700
	tcd
	#akku8
	lda #0
	pha
	plb
	ldx #0
_stimme
	lda m_akt,x
	beq _naechste
	stx m_stimme
	#akku16
	lda m_rest,x
	sec
	sbc #16
	sta m_rest,x
	#akku8
	jsr zeiger_setzen
-	#akku16                     ; faellig: naechste Note (auch mehrere je Bild)
	lda m_rest,x
	beq +
	bpl _gate
+	#akku8
	jsr naechstes
	lda m_akt,x
	bne -
	bra _naechste
_gate
	.al
	cmp #17                     ; letztes Bild der Note: Gate aus (absetzen)
	#akku8
	bcs _naechste
	lda m_klang,x
	beq _naechste
	stz m_klang,x
	lda m_welle,x
	sta ORG_ST+4,x
_naechste
	#akku16
	txa
	clc
	adc #16
	tax
	#akku8
	cpx #64
	bne _stimme
	plb
	pld
	rtl

zeiger_setzen                   ; m_zeiger = $FE:1000 + Stimme * 256
	.as
	stz m_zeiger
	txa
	lsr a
	lsr a
	lsr a
	lsr a
	clc
	adc #$10
	sta m_zeiger+1
	lda #$FE
	sta m_zeiger+2
	rts

;----------------------------------------------------------------------------
; PLAY: Text aus BASIC (P_TPTR in Bank 1, P_TLEN) in den Puffer der Stimme

musik_start
	.as
	lda P_ANZ_M                 ; Stimme 1-4, sonst 1
	beq +
	lda P_WERT_M+1
	ora P_WERT_M+2
	bne _f
	lda P_WERT_M
	dec a
	cmp #4
	bcs _f
	bra ++
+	lda #0
+	asl a
	asl a
	asl a
	asl a
	#akku16
	and #$00ff
	tax
	#akku8
	php
	sei
	stz m_akt,x
	jsr zeiger_setzen
	lda P_TPTR_M                ; Quelle: Zeichenkette in Bank 1
	sta m_d32
	lda P_TPTR_M+1
	sta m_d32+1
	lda #1
	sta m_d32+2
	ldy #0
-	tya
	cmp P_TLEN_M
	beq +
	lda [m_d32],y
	sta [m_zeiger],y
	iny
	bra -
+	lda P_TLEN_M
	sta m_tlen,x
	stz m_pos,x
	lda #4
	sta m_okt,x
	sta m_len,x
	lda #$10                    ; Dreieck
	sta m_welle,x
	sta ORG_ST+4,x              ; Gate aus
	stz m_klang,x
	#akku16
	stz m_rest,x
	lda #1920                   ; Tempo 120: ganze Note = 2 s = 120 * 16
	sta m_ganz,x
	lda #$0800                  ; Puls 50 %
	sta ORG_ST+2,x
	#akku8
	lda #$08                    ; wie SOUND: Attack 2 ms, Decay 300 ms,
	sta ORG_ST+5,x
	lda #$c8                    ; Sustain 12, Release 300 ms
	sta ORG_ST+6,x
	lda #15
	sta ORG_ST+7,x
	lda #$ff
	sta ORG_ST+8,x
	lda P_TLEN_M
	sta m_akt,x                 ; leerer Text: Stimme bleibt still
	plp
	lda #0
	rts
_f
	lda #1
	rts

musik_aus                       ; alle Stimmen still (SILENCE, Programmende)
	.as
	ldx #0
-	stz m_akt,x
	stz m_klang,x
	#akku16
	txa
	clc
	adc #16
	tax
	#akku8
	cpx #64
	bne -
	rts

;----------------------------------------------------------------------------
; naechstes Ereignis der Stimme X lesen: Note oder Pause (setzt m_rest),
; Einstellungen dazwischen gleich ausfuehren; am Ende m_akt = 0

naechstes
	.as
_lesen
	jsr zeichen
	bcc +
	stz m_akt,x                 ; Ende des Textes
	stz m_klang,x
	lda m_welle,x
	sta ORG_ST+4,x
	rts
+	cmp #' '
	beq _lesen
	cmp #'a'
	bcc +
	cmp #'z'+1
	bcs +
	and #$df
+	cmp #'!'
	bne +
	stz m_pos,x                 ; von vorn
	bra _lesen
+	cmp #'<'
	bne +
	lda m_okt,x
	beq _lesen
	dec m_okt,x
	bra _lesen
+	cmp #'>'
	bne +
	lda m_okt,x
	cmp #7
	bcs _lesen
	inc m_okt,x
	bra _lesen
+	cmp #'O'
	bne +
	jsr zahl
	cmp #8
	bcs _lesen
	sta m_okt,x
	bra _lesen
+	cmp #'L'
	bne +
	jsr zahl
	beq _lesen
	sta m_len,x
	bra _lesen
+	cmp #'V'
	bne +
	jsr zahl
	cmp #16
	bcs _lesen
	sta ORG_ST+7,x
	bra _lesen
+	cmp #'W'
	bne +
	jsr zahl
	dec a
	cmp #4
	bcs _lesen
	phx
	#akku16
	and #$0003
	tax
	#akku8
	lda ROM+wellen,x
	plx
	sta m_welle,x
	bra _lesen
+	cmp #'T'
	bne +
	jsr zahl
	jsr tempo
	bra _lesen
+	cmp #'R'
	beq _pause
	cmp #'P'
	beq _pause
	cmp #'A'
	bcc _lesen
	cmp #'G'+1
	bcs _lesen
	jmp note
_pause
	jsr dauer
	stz m_klang,x
	lda m_welle,x
	sta ORG_ST+4,x              ; Gate aus
	rts

wellen
	.byte $10, $20, $40, $80

zeichen                         ; A = naechstes Zeichen; Carry: Ende
	.as
	lda m_pos,x
	cmp m_tlen,x
	bcs +
	inc m_pos,x
	#akku16
	and #$00ff
	tay
	#akku8
	lda [m_zeiger],y
	clc
+	rts

blick                           ; A = naechstes Zeichen, ohne es zu nehmen (0: Ende)
	.as
	lda m_pos,x
	cmp m_tlen,x
	bcs +
	#akku16
	and #$00ff
	tay
	#akku8
	lda [m_zeiger],y
	rts
+	lda #0
	rts

zahl                            ; Ziffern -> A (0-255, 0 ohne Ziffern); Z entsprechend
	.as
	stz m_r16
-	jsr blick
	cmp #'0'
	bcc +
	cmp #'9'+1
	bcs +
	inc m_pos,x
	sec
	sbc #'0'
	pha
	lda m_r16                   ; * 10 + Ziffer
	asl a
	sta m_r16+1
	asl a
	asl a
	clc
	adc m_r16+1
	sta m_r16
	pla
	clc
	adc m_r16
	sta m_r16
	bra -
+	lda m_r16
	rts

tempo                           ; A = Viertel je Minute -> m_ganz = 230400 / T
	.as
	cmp #32
	bcs +
	lda #32
+	sta m_teiler
	stz m_teiler+1
	#akku16
	lda #$8400                  ; 230400 = $38400
	sta m_d32
	lda #$0003
	sta m_d32+2
	jsr teilen
	lda m_d32
	sta m_ganz,x
	#akku8
	rts

dauer                           ; Laenge lesen -> m_rest += Dauer
	.as
	jsr zahl
	bne +
	lda m_len,x
+	sta m_teiler
	stz m_teiler+1
	#akku16
	lda m_ganz,x
	sta m_d32
	stz m_d32+2
	jsr teilen
	lda m_d32
	sta m_dauer
	#akku8
	jsr blick
	cmp #'.'
	bne +
	inc m_pos,x
	#akku16
	lda m_dauer
	lsr a
	clc
	adc m_dauer
	sta m_dauer
	#akku8
+	#akku16
	lda m_rest,x
	clc
	adc m_dauer
	sta m_rest,x
	#akku8
	rts

teilen                          ; m_d32 / m_teiler -> m_d32, Rest m_r16
	.al
	stz m_r16
	ldy #32
-	asl m_d32
	rol m_d32+2
	rol m_r16
	lda m_r16
	sec
	sbc m_teiler
	bcc +
	sta m_r16
	inc m_d32
+	dey
	bne -
	rts

; Note A-G: Halbton, Vorzeichen, Oktave -> Frequenz, anschlagen
note
	.as
	sec
	sbc #'A'
	phx
	#akku16
	and #$00ff
	tax
	#akku8
	lda ROM+halbton,x           ; A=9 B=11 C=0 D=2 E=4 F=5 G=7
	plx
	sta m_r16                   ; Halbton
	lda m_okt,x
	sta m_r16+1                 ; Oktave
	jsr blick
	cmp #'#'
	beq _hoch
	cmp #'+'
	beq _hoch
	cmp #'-'
	bne _zeit
	inc m_pos,x                 ; tiefer
	dec m_r16
	bpl _zeit
	lda #11
	sta m_r16
	dec m_r16+1
	bra _zeit
_hoch
	inc m_pos,x
	inc m_r16
	lda m_r16
	cmp #12
	bcc _zeit
	stz m_r16
	inc m_r16+1
_zeit
	lda m_r16+1                 ; Oktave sichern, Dauer braucht m_r16
	pha
	lda m_r16
	pha
	jsr dauer
	pla
	asl a
	phx
	#akku16
	and #$00ff
	tax
	lda ROM+noten6,x            ; Oktave 6
	plx
	sta m_d32
	#akku8
	pla                         ; Oktave
	bmi _still                  ; unter Oktave 0
	cmp #6
	beq _setzen
	bcs _hoeher
-	#akku16                     ; tiefer: halbieren
	lsr m_d32
	#akku8
	inc a
	cmp #6
	bne -
	bra _setzen
_hoeher
	cmp #8
	bcs _still
	#akku16                     ; Oktave 7: verdoppeln (bis $FFFF)
	asl m_d32
	bcc +
	lda #$ffff
	sta m_d32
+	#akku8
_setzen
	lda m_welle,x
	sta ORG_ST+4,x              ; Gate aus
	#akku16
	lda m_d32
	sta ORG_ST+0,x
	#akku8
	lda m_welle,x
	ora #$01
	sta ORG_ST+4,x              ; Gate an
	lda #1
	sta m_klang,x
	rts
_still
	stz m_klang,x
	rts

halbton
	.byte 9, 11, 0, 2, 4, 5, 7
noten6                          ; C6 bis B6: f * 2^24 / 1 MHz
	.word 17557, 18601, 19708, 20879, 22121, 23436
	.word 24830, 26306, 27871, 29528, 31284, 33144
