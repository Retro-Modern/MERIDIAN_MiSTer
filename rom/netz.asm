;============================================================================
;  NETZ - Postfach zum Netzdienst (Etappe 12), im ROM Bank $FF neben dem DOS
;
;  Bank $FD ist ein Fenster ins DDR3 (DRAHT), das auch der Linux-Teil des
;  MiSTer sieht. Dort laeuft tools/draht.py und erledigt die eigentliche
;  Arbeit (TCP, HTTP, Diskettenbilder). Jede Anfrage ist ein Wechselspiel:
;  der MERIDIAN schreibt Art, Kanal und Text und zuletzt die Anfrage-Nummer;
;  der Dienst schreibt Status und Antworttext und zuletzt die Antwort-Nummer.
;
;  Fenster ($FD:0000):
;   $00 Anfrage-Nr   $01 Antwort-Nr   $02 Art (1 Befehl, 2 Zeile, 3 Zustand)
;   $03 Kanal (0-4)  $04 Laenge der Anfrage   $06/$07 Status (mit Vorzeichen)
;   $08 Laenge der Antwort   $10 Herzschlag des Dienstes
;   $100 Anfragetext   $200 Antworttext (je bis 255 Zeichen)
;
;  Einsprung $FF:4009, A = 0 NET "befehl"[,kanal] (Werte von BASIC)
;                          1 NET(k):  Status (k = 0) / wartende Zeilen
;                          2 NET$(k): Zeile holen, Laenge nach LZ
;                          3 NET$(k): Text nach LZ (Bank 1) kopieren
;  LZ = $00:0000 (3 Byte): Wert und Ergebnis wie bei den Funktionen
;============================================================================

FEN        = $FD0000
F_ANR      = FEN+0
F_ANTW     = FEN+1
F_ART      = FEN+2
F_KANAL    = FEN+3
F_LEN      = FEN+4
F_STATUS   = FEN+6
F_ALEN     = FEN+8
F_TEXT     = FEN+$100
F_ANTWORT  = FEN+$200

N_LZ       = $0000              ; LZ in Bank 0 (absolut ansprechen: D = $1700)
N_BILDER   = $0050              ; Bildzaehler des Kerns
N_ESC      = $033E76            ; KEY-Tabelle: Esc (Scancode $76) gedrueckt?

n_q     = $C0                   ; 3 Byte: Quelle (Text in Bank 1)
n_nr    = $C3                   ; Nummer der laufenden Anfrage
n_t0    = $C4                   ; 2 Byte: Bildzaehler beim Abschicken
n_max   = $C6                   ; 2 Byte: Wartezeit in Bildern

netz_befehl
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
	asl a
	#akku16
	and #$00ff
	tax
	#akku8
	jsr (n_tabelle,x)
	.as
	plb
	pld
	rtl

n_tabelle
	.word n_befehl, n_zustand, n_zeile, n_text

;----------------------------------------------------------------------------
; NET "befehl"[,kanal]: Text aus BASIC (Bank 1) ins Fenster, abschicken

n_befehl
	.as
	lda P_ANZ_M                 ; Kanal: ohne Angabe 0
	beq _null
	lda P_WERT_M+1
	ora P_WERT_M+2
	bne _f
	lda P_WERT_M
	cmp #5
	bcs _f
	bra +
_null
	lda #0
+	sta @l F_KANAL
	lda #1
	sta @l F_ART
	lda P_TLEN_M
	sta @l F_LEN
	lda P_TPTR_M
	sta n_q
	lda P_TPTR_M+1
	sta n_q+1
	lda #1
	sta n_q+2
	ldy #0
-	tya
	cmp P_TLEN_M
	beq +
	lda [n_q],y
	tyx
	sta @l F_TEXT,x
	iny
	bra -
+	#akku16                     ; Befehle duerfen dauern (Verbindung, Abruf)
	lda #20*60
	sta n_max
	#akku8
	jsr anfrage
	lda #0
	rts
_f
	lda #1
	rts

;----------------------------------------------------------------------------
; NET(k): Status des letzten Befehls (k = 0) oder wartende Zeilen

n_zustand
	.as
	lda #3
	jsr kurz_fragen
	#akku16                     ; Status (16 Bit mit Vorzeichen) -> LZ
	lda @l F_STATUS
	sta @w N_LZ
	#akku8
	lda @w N_LZ+1
	bmi +
	lda #0
	bra ++
+	lda #$ff
+	sta @w N_LZ+2
	rts

; NET$(k): naechste Zeile holen; Laenge nach LZ
n_zeile
	.as
	lda #2
	jsr kurz_fragen
	lda @l F_ALEN
	sta @w N_LZ
	lda #0
	sta @w N_LZ+1
	sta @w N_LZ+2
	rts

; NET$(k): die geholte Zeile nach LZ (Bank 1) kopieren
n_text
	.as
	lda @w N_LZ
	sta n_q
	lda @w N_LZ+1
	sta n_q+1
	lda #1
	sta n_q+2
	ldy #0
-	tya
	cmp @l F_ALEN
	beq +
	tyx
	lda @l F_ANTWORT,x
	sta [n_q],y
	iny
	bra -
+	rts

kurz_fragen                     ; A = Art, Kanal = LZ; kurze Wartezeit
	.as
	sta @l F_ART
	lda @w N_LZ
	sta @l F_KANAL
	lda #0
	sta @l F_LEN
	#akku16
	lda #3*60
	sta n_max
	#akku8
	; weiter in anfrage

;----------------------------------------------------------------------------
; Anfrage abschicken und auf die Antwort warten (Esc bricht ab). Antwortet
; der Dienst nicht, steht eine eigene Meldung im Fenster.

anfrage
	.as
	lda @l F_ANR
	inc a
	sta n_nr
	#akku16
	lda @w N_BILDER
	sta n_t0
	#akku8
	lda n_nr
	sta @l F_ANR                ; zuletzt: abschicken
_warten
	lda @l F_ANTW
	cmp n_nr
	beq _da
	lda @l N_ESC
	bne _abbruch
	#akku16
	lda @w N_BILDER
	sec
	sbc n_t0
	cmp n_max
	#akku8
	bcc _warten
	ldx #t_kein_dienst - t_meldungen
	lda #$9d                    ; -99
	bra _selbst
_abbruch
	ldx #t_abbruch - t_meldungen
	lda #$9e                    ; -98
_selbst                         ; eigene Antwort ins Fenster
	sta @l F_STATUS
	lda #$ff
	sta @l F_STATUS+1
	ldy #0
-	lda ROM+t_meldungen,x
	beq +
	phx
	tyx
	sta @l F_ANTWORT,x
	plx
	inx
	iny
	bra -
+	tya
	sta @l F_ALEN
	lda n_nr
	sta @l F_ANTW
_da
	rts

t_meldungen
t_kein_dienst .text "NO NETWORK SERVICE", 0
t_abbruch     .text "ABORTED", 0
