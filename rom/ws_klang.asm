;============================================================================
;  WERKSTATT: SOUNDS - kurze Klaenge wie beim Pico-8, dazu BASIC SFX und der
;  Abspieler (eingebunden von werkstatt.asm)
;
;  64 Klaenge zu 132 Byte im Zusatzspeicher: Kopf (Tempo in Bildern je
;  Schritt, 0 = 8; Schleife; 2 frei), dann 32 Schritte zu 4 Byte: Note
;  (0-83, C-0 bis B-6), Welle (0-7), Lautstaerke (0-15, 0 = Pause), Effekt
;  (0-7). Der Abspieler laeuft im Interrupt des Kerns, jedes Bild, solange
;  SFX_AN nicht 0 ist, und nimmt die Synthesestimmen der ORGEL.
;
;  Maus: oben die Tonhoehe malen (links setzen, rechts Pause), darunter die
;  Lautstaerke; in den Zeilen WAVE und EFFECT setzt ein Klick die gewaehlte
;  Welle bzw. den Effekt. Links die Liste.
;  Tasten: Leertaste hoeren, 1-8 Welle, E Effekt, +/- Tempo, L Schleife,
;  V Stimme, Pfeile hoch/runter transponieren, ,/. Klang, C P X U.
;============================================================================

KL_DATEN  = KART+$8000          ; 64 Klaenge zu 132 Byte (bis $A0FF)
KL_GROESSE = 132
KL_STAND  = KART+$4400          ; Abspieler: je Stimme 16 Byte
KL_UNDO   = W_RAM+$600          ; der Klang vor der letzten Aenderung
KL_KLAU   = W_RAM+$700          ; Zwischenablage

; Seite 2, nur fuer den Abspieler (der Interrupt benutzt sie auch: wer sie
; ausserhalb anfasst, sperrt ihn so lange)
SFX_AN    = $02F4               ; Bit v: auf Stimme v laeuft ein Klang
SF_V      = $02F5               ; 2: Stimme * 16 (Stand und ORGEL)
SF_K      = $02F7               ; 2: Anfang des Klangs in KL_DATEN
SF_T      = $02F9               ; 2: Hilfswert
SF_U      = $02FB               ; 2: Hilfswert
SF_D      = $02FD               ; 2: Teiler (oberes Byte 0)
SF_N      = $02FF               ; Stimme 0-3
ORG_ST    = $C500               ; Synthesestimme v ab $C500 + v * 16

ST_KLANG  = 0                   ; Stand einer Stimme
ST_SCHRITT = 1
ST_BILD   = 2                   ; Bild im Schritt
ST_FREQ   = 3                   ; 2
ST_DF     = 5                   ; 2: FREQ je Bild (mit Vorzeichen)
ST_LAUT   = 7                   ; 2: Lautstaerke 8.8
ST_DL     = 9                   ; 2: je Bild
ST_FX     = 11
ST_NOTE   = 12
ST_GRUND  = 13                  ; 2: FREQ der Note (Vibrato)
ST_ENDE   = 15                  ; Schritte bis nach dem letzten hoerbaren

; Lage (Bitmap und Text)
KX0 = 64                        ; Schritt s ab x = KX0 + 8 s
KY_TON = 107                    ; Note n bei y = KY_TON - n (24-107)
KY_LAUT = 143                   ; Lautstaerke l: Balken 2 l hoch bis 143
KZ_WELLE = 19                   ; Textzeilen
KZ_EFFEKT = 20

	.virtual W_RAM+$c0          ; Variablen von SOUNDS
kl_n      .byte ?               ; Klang 0-63
kl_welle  .byte ?               ; gewaehlte Welle
kl_fx     .byte ?               ; gewaehlter Effekt
kl_stimme .byte ?               ; Stimme zum Hoeren 0-3
kl_s      .byte ?               ; Schritt unter der Maus ($ff = keiner)
kl_i      .word ?               ; Anfang des Klangs in KL_DATEN
kl_t      .word ?               ; Schritt, Hilfsbyte
kl_z      .word ?
kl_h      .word ?               ; Liste: Stelle auf dem Schirm
	.endv

;----------------------------------------------------------------------------
; Reiter oeffnen

kl_zeichnen
	.as
	lda kl_n
	and #63
	sta kl_n
	lda #$ff
	sta kl_s
	#text KZ_WELLE, 1, F_TITEL, t_kl_welle
	#text KZ_EFFEKT, 1, F_TITEL, t_kl_effekt
	#text 24, 1, F_GRUND, t_kl_basic
	#text 26, 1, F_GRUND, t_kl_hilfe1
	#text 27, 1, F_GRUND, t_kl_hilfe2
kl_alles                        ; nach der Wahl eines Klangs
	.as
	jsr kl_index
	jsr kl_liste
	jsr kl_kopf
	jsr kl_graph
	jsr kl_wahl
	jmp kl_status

t_kl_welle  .null "WAVE"
t_kl_effekt .null "EFFECT"
t_kl_basic  .null "BASIC: SFX n plays sound n on a free voice, SFX n,v on voice v, SFX -1 stops"
t_kl_hilfe1 .null "Mouse: paint pitch and volume (right: rest), click WAVE/EFFECT to set.  Space"
t_kl_hilfe2 .null "listen  1-8 wave  E effect  +- speed  L loop  V voice  Up/Down transpose  CPXU"

kl_index                        ; kl_i = kl_n * 132
	.as
	php
	sei
	lda kl_n
	jsr sf_klang
	#akku16
	lda SF_K
	sta kl_i
	#akku8
	plp
	rts

kl_belegt                       ; A = Klang A ist belegt (Schritte bis zum letzten hoerbaren)
	.as
	php
	sei
	jsr sf_klang
	jsr sf_laenge
	plp
	cmp #0
	rts

; Liste links: 16 Klaenge der Seite, belegte mit Stern
kl_liste
	.as
	#text 2, 1, F_TITEL, t_kl_titel
	lda kl_n
	lsr a
	lsr a
	lsr a
	lsr a
	inc a
	ldx #2 * 160 + 13 * 2
	jsr w_zahl1
	stz kl_t                    ; Zeile 0-15
	#akku16
	lda #3 * 160 + 1 * 2        ; ab Zeile 3, Spalte 1
	sta kl_h
	#akku8
_zeile
	lda kl_n
	and #$30
	ora kl_t
	sta kl_z                    ; Klang
	jsr kl_belegt
	sta kl_z+1
	ldx kl_h
	lda kl_z
	jsr w_zahl2
	lda #' '
	sta SCHIRM,x
	sta SCHIRM+4,x
	lda kl_z+1
	beq _leer
	lda #'*'
_leer
	cmp #0
	bne +
	lda #' '
+	sta SCHIRM+2,x
	dex                         ; Farbe der fuenf Zellen
	dex
	dex
	dex
	lda kl_z
	cmp kl_n
	beq +
	lda #F_GRUND
	bra ++
+	lda #F_AKTIV
+	ldy #5
-	sta SCHIRM+1,x
	inx
	inx
	dey
	bne -
	#akku16
	lda kl_h
	clc
	adc #160
	sta kl_h
	#akku8
	inc kl_t
	lda kl_t
	cmp #16
	bne _zeile
	rts
t_kl_titel .null "SOUNDS page  /4"

; Kopf: Nummer, Tempo, Schleife, Stimme
kl_kopf
	.as
	#text 2, 18, F_TITEL, t_kl_kopf
	lda kl_n
	ldx #2 * 160 + 24 * 2
	jsr w_zahl2
	jsr kl_tempo
	ldx #2 * 160 + 35 * 2
	jsr w_zahl2
	ldx kl_i
	lda @l KL_DATEN+1,x
	beq +
	#text 2, 45, F_TITEL, t_kl_an
+	lda kl_stimme
	inc a
	ldx #2 * 160 + 57 * 2
	jmp w_zahl1
t_kl_kopf .null "SOUND 00   SPEED 00   LOOP off   VOICE 0   "
t_kl_an   .null "on "

kl_tempo                        ; A = Bilder je Schritt (0 heisst 8)
	.as
	ldx kl_i
	lda @l KL_DATEN,x
	bne +
	lda #8
+	rts

; Graph: Tonhoehe und Lautstaerke aller Schritte
kl_graph
	.as
	#akku16
	lda #KX0-2
	sta sp_x
	lda #KY_TON-83-2
	sta sp_y
	lda #32*8+2
	sta sp_w
	lda #84+4
	sta sp_h
	#akku8
	lda #B_RAHMEN
	sta sp_c
	jsr sp_rechteck
	#akku16
	lda #KY_LAUT-31-2
	sta sp_y
	lda #32+4
	sta sp_h
	#akku8
	jsr sp_rechteck
	lda #0
-	pha
	jsr kl_spalte
	pla
	inc a
	cmp #32
	bne -
	rts

; Schritt A neu zeichnen: Balken, Welle, Effekt
kl_spalte
	.as
	sta kl_t
	#akku16
	and #$00ff
	asl a
	asl a
	asl a
	clc
	adc #KX0
	sta sp_x
	lda #KY_TON-83
	sta sp_y
	lda #8
	sta sp_w
	lda #84
	sta sp_h
	#akku8
	lda #B_GRUND
	sta sp_c
	jsr sp_rechteck             ; leeren
	#akku16
	lda #KY_LAUT-31
	sta sp_y
	lda #32
	sta sp_h
	#akku8
	jsr sp_rechteck
	jsr kl_schritt_x            ; X = Schritt in KL_DATEN
	lda @l KL_DATEN+2,x
	bne +
	jmp _texte                  ; Pause
+	#akku16                     ; Lautstaerke: 2 l hoch
	and #$000f
	asl a
	sta sp_h
	lda #KY_LAUT+1
	sec
	sbc sp_h
	sta sp_y
	inc sp_x
	lda #6
	sta sp_w
	#akku8
	lda #5
	sta sp_c
	jsr sp_rechteck
	jsr kl_schritt_x            ; Tonhoehe in der Farbe der Welle
	lda @l KL_DATEN+1,x
	and #7
	#akku16
	and #$00ff
	tax
	#akku8
	lda @l kl_farben,x
	sta sp_c
	jsr kl_schritt_x
	lda @l KL_DATEN,x
	#akku16
	and #$00ff
	cmp #84
	bcc +
	lda #83
+	inc a
	sta sp_h
	lda #KY_TON+1
	sec
	sbc sp_h
	sta sp_y
	#akku8
	jsr sp_rechteck
_texte
	jsr kl_schritt_x            ; Welle und Effekt als Text
	lda @l KL_DATEN+2,x
	beq _leer
	lda @l KL_DATEN+3,x
	and #7
	asl a
	ora #16                     ; (kl_ek folgt auf kl_wk)
	pha
	lda @l KL_DATEN+1,x
	and #7
	asl a
	pha
	jsr kl_text_x
	#akku16
	txa
	clc
	adc #KZ_WELLE * 160
	tax
	#akku8
	pla
	jsr kl_zwei
	jsr kl_text_x
	#akku16
	txa
	clc
	adc #KZ_EFFEKT * 160
	tax
	#akku8
	pla
	jmp kl_zwei
_leer
	jsr kl_text_x
	lda #' '
	sta SCHIRM+KZ_WELLE*160,x
	sta SCHIRM+KZ_WELLE*160+2,x
	sta SCHIRM+KZ_EFFEKT*160,x
	sta SCHIRM+KZ_EFFEKT*160+2,x
	rts

kl_zwei                         ; Kuerzel ab kl_wk+A nach SCHIRM+X und +2,
	.as                         ; jeder zweite Schritt (kl_t) hellblau
	phx
	#akku16
	and #$00ff
	tax
	lda @l kl_wk,x
	sta kl_z
	#akku8
	plx
	lda kl_z
	sta SCHIRM,x
	lda kl_z+1
	sta SCHIRM+2,x
	lda #F_GRUND
	pha
	lda kl_t
	lsr a
	pla
	bcc +
	lda #F_GRUND-1              ; hellblau auf blau
+	sta SCHIRM+1,x
	sta SCHIRM+3,x
	rts

kl_schritt_x                    ; X = kl_i + 4 + 4 * kl_t
	.as
	lda kl_t
	asl a
	asl a
	#akku16
	and #$00ff
	clc
	adc kl_i
	adc #4
	tax
	#akku8
	rts
kl_text_x                       ; X = Spalte des Schritts kl_t (16 + 2 s) * 2
	.as
	lda kl_t
	asl a
	clc
	adc #KX0/4
	asl a
	#akku16
	and #$00ff
	tax
	#akku8
	rts

kl_farben                       ; Farbe der Welle im Graph
	.byte 7, 3, 2, 10, 8, 15, 13, 4
kl_wk	.text "TRSWSQP2P1NOTSSP"   ; Kuerzel der Wellen
kl_ek	.text "--SLVBDRFIFOAFAS"   ; und gleich dahinter der Effekte

; gewaehlte Welle und Effekt (Zeile 22)
kl_wahl
	.as
	#text 22, 1, F_GRUND, t_kl_wahl
	lda kl_welle
	and #7
	sta kl_welle
	asl a
	asl a
	asl a
	asl a
	#akku16
	and #$00ff
	clc
	adc #<>t_kl_wellen
	ldy #`t_kl_wellen
	ldx #22 * 160 + 16 * 2
	jsr w_text_xy
	.as
	lda #F_AKTIV
	jsr w_text
	lda kl_fx
	and #7
	sta kl_fx
	asl a
	asl a
	asl a
	asl a
	#akku16
	and #$00ff
	clc
	adc #<>t_kl_effekte
	ldy #`t_kl_effekte
	ldx #22 * 160 + 45 * 2
	jsr w_text_xy
	.as
	lda #F_AKTIV
	jmp w_text
t_kl_wahl .null "paint with wave                (1-8)  effect                (E)  "
t_kl_wellen                     ; je 16 Byte
	.null " triangle      "
	.null " saw           "
	.null " square        "
	.null " pulse 25 %    "
	.null " pulse 12 %    "
	.null " noise         "
	.null " tri + saw     "
	.null " saw + pulse   "
t_kl_effekte
	.null " none          "
	.null " slide         "
	.null " vibrato       "
	.null " drop          "
	.null " fade in       "
	.null " fade out      "
	.null " arpeggio fast "
	.null " arpeggio slow "

; Statuszeile: Schritt unter der Maus
kl_status
	.as
	#text 29, 0, F_STATUS, t_kl_status
	lda kl_n
	ldx #29 * 160 + 7 * 2
	jsr w_zahl2
	lda kl_s
	bmi _ende
	sta kl_t
	ldx #29 * 160 + 16 * 2
	jsr w_zahl2
	jsr kl_schritt_x
	lda @l KL_DATEN+2,x
	beq _pause
	sta kl_z+1
	lda @l KL_DATEN,x           ; Note: Name und Oktave
	ldy #0
-	cmp #12
	bcc +
	sbc #12
	iny
	bra -
+	asl a
	sta kl_z
	tya
	clc
	adc #'0'
	sta SCHIRM+29*160+27*2
	lda kl_z
	#akku16
	and #$00ff
	tax
	#akku8
	lda @l kl_noten,x
	sta SCHIRM+29*160+25*2
	lda @l kl_noten+1,x
	sta SCHIRM+29*160+26*2
	lda kl_z+1                  ; Lautstaerke
	ldx #29 * 160 + 46 * 2
	jsr w_zahl2
	jsr kl_text_x               ; Welle und Effekt wie in den Zeilen
	lda SCHIRM+KZ_WELLE*160,x
	sta SCHIRM+29*160+35*2
	lda SCHIRM+KZ_WELLE*160+2,x
	sta SCHIRM+29*160+36*2
	lda SCHIRM+KZ_EFFEKT*160,x
	sta SCHIRM+29*160+53*2
	lda SCHIRM+KZ_EFFEKT*160+2,x
	sta SCHIRM+29*160+54*2
	rts
_pause
	#text 29, 25, F_STATUS, t_kl_pause
_ende
	rts
t_kl_status .null " SOUND 00  STEP --  NOTE ---  WAVE --  VOLUME --  FX --         space: listen   "
t_kl_pause  .null "rest"
kl_noten .text "C-C#D-D#E-F-F#G-G#A-A#B-"

;----------------------------------------------------------------------------
; Je Bild: Maus und Tasten (Taste in A, 0 = keine)

kl_takt
	.as
	cmp #0
	beq +
	jsr kl_taste
+	lda kl_s                    ; Schritt unter der Maus
	pha
	lda #$ff
	sta kl_s
	#akku16
	lda w_mx
	sec
	sbc #KX0
	bcc +
	lsr a
	lsr a
	lsr a
	#akku8
	sta kl_s
+	#akku8
	pla
	cmp kl_s
	beq +
	jsr kl_status
+	lda w_mt
	and #$03
	bne +
	rts
+	lda kl_s
	bpl _graph
	jmp kl_klick_liste
_graph
	sta kl_t
	lda w_mtalt                 ; gerade gedrueckt: vorher merken
	and #$03
	bne +
	jsr kl_merken
+	#akku16
	lda w_my
	cmp #KY_TON-83
	bcc _nichts
	cmp #KY_TON+1
	bcc _ton
	cmp #KY_LAUT-31-2
	bcc _nichts
	cmp #KY_LAUT+1
	bcc _laut
	cmp #KZ_WELLE*8
	bcc _nichts
	cmp #KZ_WELLE*8+8
	bcc _welle
	cmp #KZ_EFFEKT*8+8
	bcc _effekt
_nichts
	#akku8
	rts
_ton
	.al
	eor #$ffff                  ; Note = KY_TON - y
	sec
	adc #KY_TON
	#akku8
	sta kl_t+1
	jsr kl_schritt_x
	lda w_mt
	and #$02                    ; rechts: Pause
	bne _pause
	lda kl_t+1
	sta @l KL_DATEN,x
	lda kl_welle
	sta @l KL_DATEN+1,x
	lda @l KL_DATEN+2,x
	bne _neu
	lda #10                     ; neue Note: Lautstaerke 10
	sta @l KL_DATEN+2,x
	bra _neu
_pause
	lda #0
	sta @l KL_DATEN+2,x
	bra _neu
_laut
	.al
	eor #$ffff                  ; Lautstaerke = (KY_LAUT - y) / 2 + 1
	sec
	adc #KY_LAUT
	lsr a
	inc a
	cmp #16
	bcc +
	lda #15
+	#akku8
	sta kl_t+1
	jsr kl_schritt_x
	lda w_mt
	and #$02                    ; rechts: 0
	beq +
	stz kl_t+1
+	lda kl_t+1
	sta @l KL_DATEN+2,x
	bra _neu
_welle
	#akku8
	jsr kl_schritt_x
	lda w_mt
	and #$02
	bne _nichts2
	lda kl_welle
	sta @l KL_DATEN+1,x
	bra _neu
_effekt
	#akku8
	jsr kl_schritt_x
	lda w_mt
	and #$02                    ; rechts: kein Effekt
	beq +
	lda #0
	bra ++
+	lda kl_fx
+	sta @l KL_DATEN+3,x
_neu
	lda kl_t
	jsr kl_spalte
	jsr kl_liste                ; (belegt?)
	jmp kl_status
_nichts2
	rts

kl_klick_liste                  ; Klick links: Klang waehlen
	.as
	lda w_mtalt
	and #$03
	bne _ende
	#akku16
	lda w_my
	sec
	sbc #3*8
	cmp #16*8
	bcs _aus
	lsr a
	lsr a
	lsr a
	#akku8
	sta kl_t
	lda kl_n
	and #$30
	ora kl_t
	jmp kl_waehlen
_aus
	#akku8
_ende
	rts

kl_waehlen                      ; Klang A (0-63)
	.as
	and #63
	sta kl_n
	jmp kl_alles

kl_merken                       ; Klang -> KL_UNDO
	.as
	ldx kl_i
	ldy #0
-	lda @l KL_DATEN,x
	sta KL_UNDO,y
	inx
	iny
	cpy #KL_GROESSE
	bne -
	rts

;----------------------------------------------------------------------------
; Tasten

kl_taste
	.as
	cmp #' '                    ; hoeren / anhalten
	bne _nicht_hoeren
	php
	sei
	lda kl_stimme
	sta SF_N
	jsr sf_bit
	and SFX_AN
	beq +
	jsr sf_stopp_n
	plp
	rts
+	ldx kl_stimme
	lda kl_n
	jsr sf_start
	plp
	rts
_nicht_hoeren
	cmp #'1'                    ; Welle
	bcc +
	cmp #'8'+1
	bcs +
	sec
	sbc #'1'
	sta kl_welle
	jmp kl_wahl
+	cmp #'+'
	bne +
	jsr kl_tempo
	inc a
	cmp #33
	bcc _tempo
	lda #32
	bra _tempo
+	cmp #'-'
	bne +
	jsr kl_tempo
	dec a
	bne _tempo
	lda #1
_tempo
	ldx kl_i
	sta @l KL_DATEN,x
	jmp kl_kopf
+	cmp #','
	bne +
	lda kl_n
	dec a
	jmp kl_waehlen
+	cmp #'.'
	bne +
	lda kl_n
	inc a
	jmp kl_waehlen
+	cmp #$1e                    ; hoch / runter: transponieren
	bne +
	lda #1
	bra _transponieren
+	cmp #$1f
	bne +
	lda #$ff
	bra _transponieren
+	and #$df                    ; Buchstaben gross
	cmp #'E'
	bne +
	lda kl_fx
	inc a
	sta kl_fx
	jmp kl_wahl
+	cmp #'L'
	bne +
	ldx kl_i
	lda @l KL_DATEN+1,x
	eor #1
	sta @l KL_DATEN+1,x
	jmp kl_kopf
+	cmp #'V'
	bne +
	lda kl_stimme
	inc a
	and #3
	sta kl_stimme
	jmp kl_kopf
+	cmp #'C'
	bne +
	ldx kl_i
	ldy #0
-	lda @l KL_DATEN,x
	sta KL_KLAU,y
	inx
	iny
	cpy #KL_GROESSE
	bne -
	rts
+	cmp #'P'
	bne +
	jsr kl_merken
	ldx kl_i
	ldy #0
-	lda KL_KLAU,y
	sta @l KL_DATEN,x
	inx
	iny
	cpy #KL_GROESSE
	bne -
	jmp kl_alles
+	cmp #'X'
	bne +
	jsr kl_merken
	ldx kl_i
	ldy #0
	lda #0
-	sta @l KL_DATEN,x
	inx
	iny
	cpy #KL_GROESSE
	bne -
	jmp kl_alles
+	cmp #'U'
	bne +
	ldx kl_i                    ; Klang <-> KL_UNDO
	ldy #0
-	lda @l KL_DATEN,x
	pha
	lda KL_UNDO,y
	sta @l KL_DATEN,x
	pla
	sta KL_UNDO,y
	inx
	iny
	cpy #KL_GROESSE
	bne -
	jmp kl_alles
+	rts
_transponieren
	sta kl_z
	jsr kl_merken
	stz kl_t
-	jsr kl_schritt_x
	lda @l KL_DATEN+2,x
	beq _weiter
	lda @l KL_DATEN,x
	clc
	adc kl_z
	cmp #84                     ; (auch $ff: unter 0)
	bcs _weiter
	sta @l KL_DATEN,x
_weiter
	inc kl_t
	lda kl_t
	cmp #32
	bne -
	jmp kl_alles

;============================================================================
; Abspieler. Nutzt nur SF_* auf Seite 2 und lange Adressen (geht mit jeder
; direkten Seite); Akku 8, Index 16, DBR 0.

; SF_K = Anfang von Klang A in KL_DATEN (A * 132)
sf_klang
	.as
	#akku16
	and #$003f
	sta SF_K
	asl a
	asl a
	sta SF_U                    ; * 4
	lda SF_K
	xba
	lsr a                       ; * 128
	clc
	adc SF_U
	sta SF_K
	#akku8
	rts

; A = Schritte bis nach dem letzten hoerbaren (0: der Klang SF_K ist leer)
sf_laenge
	.as
	#akku16
	lda SF_K
	clc
	adc #4 + 31 * 4 + 2
	tax
	#akku8
	ldy #32
-	lda @l KL_DATEN,x
	bne +
	dex
	dex
	dex
	dex
	dey
	bne -
+	tya
	rts

; SF_T = FREQ fuer Note A (0-83)
sf_freq
	.as
	cmp #84
	bcc +
	lda #83
+	ldy #0                      ; Oktave
-	cmp #12
	bcc +
	sbc #12
	iny
	bra -
+	asl a
	#akku16
	and #$00ff
	tax
	lda @l sf_tabelle,x         ; Oktave 6, darunter halbieren
-	cpy #6
	beq +
	lsr a
	iny
	bra -
+	sta SF_T
	#akku8
	rts
sf_tabelle                      ; C-6 bis B-6: f * 2^24 / 1 MHz
	.word 17557, 18601, 19708, 20879, 22121, 23436
	.word 24830, 26306, 27871, 29528, 31284, 33144

; SF_U = SF_U / A (A 1-255), ohne Vorzeichen
sf_teilen
	.as
	sta SF_D
	stz SF_D+1
	#akku16
	stz SF_T
	ldy #16
-	asl SF_U
	rol SF_T
	lda SF_T
	cmp SF_D
	bcc +
	sbc SF_D
	sta SF_T
	inc SF_U
+	dey
	bne -
	#akku8
	rts

sf_vx                            ; SF_V = X = SF_N * 16
	.as
	lda SF_N
	asl a
	asl a
	asl a
	asl a
	#akku16
	and #$00ff
	sta SF_V
	tax
	#akku8
	rts
sf_bit                          ; A = 1 << SF_N (benutzt X)
	.as
	lda SF_N
	and #3
	#akku16
	and #$00ff
	tax
	#akku8
	lda @l sf_bits,x
	rts
sf_bits .byte 1, 2, 4, 8

; Stimme SF_N still, ihr Bit aus (Interrupt gesperrt oder im Interrupt)
sf_stopp_n
	.as
	jsr sf_bit
	eor #$ff
	and SFX_AN
	sta SFX_AN
	jsr sf_vx
	lda #0
	sta ORG_ST+4,x              ; Gate aus, keine Welle
	sta ORG_ST+7,x
	rts

; Klang A auf Stimme X (0-3) starten - leere Klaenge nicht
sf_start
	.as
	php
	sei
	pha
	txa
	and #3
	sta SF_N
	jsr sf_stopp_n
	pla
	pha
	jsr sf_klang
	jsr sf_laenge
	beq _leer
	sta SF_T
	jsr sf_vx
	pla
	sta @l KL_STAND+ST_KLANG,x
	lda SF_T
	sta @l KL_STAND+ST_ENDE,x
	lda #0
	sta @l KL_STAND+ST_SCHRITT,x
	sta @l KL_STAND+ST_BILD,x
	sta @l KL_STAND+ST_FREQ,x
	sta @l KL_STAND+ST_FREQ+1,x
	sta @l KL_STAND+ST_FX,x
	sta ORG_ST+7,x              ; leise, schneller Anschlag, halten 15
	sta ORG_ST+5,x
	lda #$f0
	sta ORG_ST+6,x
	lda #$ff                    ; Mitte
	sta ORG_ST+8,x
	jsr sf_bit
	ora SFX_AN
	sta SFX_AN
	plp
	rts
_leer
	pla
	plp
	rts

; alle Stimmen still (beim Verlassen der Werkstatt)
sf_alle_aus
	.as
	php
	sei
	stz SF_N
-	jsr sf_stopp_n
	inc SF_N
	lda SF_N
	cmp #4
	bne -
	plp
	rts

; Jedes Bild aus dem Interrupt (ueber ws_basic, A = 6)
ws_sfx_takt
	.as
	stz SF_N
_stimme
	jsr sf_bit
	and SFX_AN
	beq +
	jsr sf_vx
	jsr sf_stimme
+	inc SF_N
	lda SF_N
	cmp #4
	bne _stimme
	rtl

sf_stimme                       ; Stimme SF_N (SF_V, X) ein Bild weiter
	.as
	lda @l KL_STAND+ST_KLANG,x
	jsr sf_klang
	ldx SF_V
	lda @l KL_STAND+ST_BILD,x
	bne +
	jsr sf_schritt              ; ein neuer Schritt; C = 1: zu Ende
	bcc +
	rts
+	jsr sf_wirkung
	jsr sf_tempo
	sta SF_T
	ldx SF_V
	lda @l KL_STAND+ST_BILD,x
	inc a
	cmp SF_T
	bcc +
	lda @l KL_STAND+ST_SCHRITT,x
	inc a
	sta @l KL_STAND+ST_SCHRITT,x
	lda #0
+	sta @l KL_STAND+ST_BILD,x
	rts

sf_tempo                        ; A = Bilder je Schritt des Klangs SF_K (benutzt X)
	.as
	ldx SF_K
	lda @l KL_DATEN,x
	bne +
	lda #8
+	rts

; Schritt beginnt (X = SF_V): lesen, Welle setzen, Effekt vorbereiten
sf_schritt
	.as
	lda @l KL_STAND+ST_SCHRITT,x
	cmp @l KL_STAND+ST_ENDE,x
	bcc _spielen
	ldx SF_K                    ; zu Ende: Schleife?
	lda @l KL_DATEN+1,x
	bne +
	jsr sf_stopp_n
	sec
	rts
+	ldx SF_V
	lda #0
	sta @l KL_STAND+ST_SCHRITT,x
_spielen
	asl a                       ; SF_U = Schritt in KL_DATEN
	asl a
	#akku16
	and #$00ff
	clc
	adc SF_K
	adc #4
	sta SF_U
	#akku8
	ldx SF_U
	lda @l KL_DATEN+2,x
	bne _ton
	ldx SF_V                    ; Pause
	lda #0
	sta @l KL_STAND+ST_LAUT,x
	sta @l KL_STAND+ST_LAUT+1,x
	sta @l KL_STAND+ST_DL,x
	sta @l KL_STAND+ST_DL+1,x
	sta @l KL_STAND+ST_FX,x
	clc
	rts
_ton
	lda @l KL_DATEN+1,x         ; Welle: STEUER und Pulsbreite
	and #7
	asl a
	#akku16
	and #$00ff
	tax
	lda @l sf_wellen,x
	sta SF_T
	#akku8
	ldx SF_V
	lda #0
	sta ORG_ST+2,x
	lda SF_T+1
	sta ORG_ST+3,x
	lda SF_T
	ora #$01                    ; Gate (bleibt an, laut macht LAUT)
	sta ORG_ST+4,x
	ldx SF_U                    ; Effekt
	lda @l KL_DATEN+3,x
	and #7
	ldx SF_V
	sta @l KL_STAND+ST_FX,x
	ldx SF_U                    ; Note
	lda @l KL_DATEN,x
	ldx SF_V
	sta @l KL_STAND+ST_NOTE,x
	jsr sf_freq                 ; SF_T = Ziel
	ldx SF_U                    ; Lautstaerke 8.8
	lda @l KL_DATEN+2,x
	ldx SF_V
	sta @l KL_STAND+ST_LAUT+1,x
	lda #0
	sta @l KL_STAND+ST_LAUT,x
	sta @l KL_STAND+ST_DF,x
	sta @l KL_STAND+ST_DF+1,x
	sta @l KL_STAND+ST_DL,x
	sta @l KL_STAND+ST_DL+1,x
	#akku16
	lda SF_T
	sta @l KL_STAND+ST_GRUND,x
	lda @l KL_STAND+ST_FREQ,x   ; alte Frequenz (fuer Gleiten)
	sta SF_U
	lda SF_T
	sta @l KL_STAND+ST_FREQ,x
	#akku8
	lda @l KL_STAND+ST_FX,x
	cmp #1
	beq _gleiten
	cmp #3
	beq _fallen
	cmp #4
	beq _einblenden
	cmp #5
	beq _ausblenden
	clc
	rts
_gleiten                        ; von der alten Frequenz zur neuen
	#akku16
	lda SF_U
	beq _fertig16               ; nichts davor: gleich die neue
	sta @l KL_STAND+ST_FREQ,x
	lda SF_T
	sec
	sbc SF_U                    ; Ziel - alt
	php
	bcs +
	eor #$ffff
	inc a
+	sta SF_U
	#akku8
	jsr sf_tempo
	jsr sf_teilen
	plp                         ; (Akku wieder 16 Bit, Carry: aufwaerts)
	.al
	lda SF_U
	bcs _df
	eor #$ffff
	inc a
	bra _df
_fallen                         ; bis 0
	#akku16
	lda SF_T
	sta SF_U
	#akku8
	jsr sf_tempo
	jsr sf_teilen
	#akku16
	lda SF_U
	eor #$ffff
	inc a
_df
	ldx SF_V
	sta @l KL_STAND+ST_DF,x
_fertig16
	#akku8
	clc
	rts
_einblenden
	lda @l KL_STAND+ST_LAUT+1,x
	pha
	lda #0
	sta @l KL_STAND+ST_LAUT+1,x
	pla
	jsr _dl
	bra _dl_setzen
_ausblenden
	lda @l KL_STAND+ST_LAUT+1,x
	jsr _dl
	#akku16
	lda SF_U
	eor #$ffff
	inc a
	sta SF_U
	#akku8
_dl_setzen
	ldx SF_V
	#akku16
	lda SF_U
	sta @l KL_STAND+ST_DL,x
	#akku8
	clc
	rts
_dl                             ; SF_U = A * 256 / Tempo
	.as
	stz SF_U
	sta SF_U+1
	jsr sf_tempo
	jmp sf_teilen

sf_wellen                       ; STEUER, Pulsbreite (oberes Byte) je Welle
	.byte $10, 0, $20, 0, $40, $08, $40, $04, $40, $02, $80, 0, $30, 0, $60, $08

; Effekt dieses Bildes, dann FREQ und LAUT in die ORGEL
sf_wirkung
	.as
	ldx SF_V
	lda @l KL_STAND+ST_FX,x
	asl a
	#akku16
	and #$000e
	tax
	#akku8
	jsr (sf_wirk_tab,x)
	ldx SF_V
	lda @l KL_STAND+ST_FREQ,x
	sta ORG_ST+0,x
	lda @l KL_STAND+ST_FREQ+1,x
	sta ORG_ST+1,x
	lda @l KL_STAND+ST_LAUT+1,x
	sta ORG_ST+7,x
	rts
sf_wirk_tab
	.word <>sf_nichts, <>sf_frei, <>sf_vibrato, <>sf_frei
	.word <>sf_blenden, <>sf_blenden, <>sf_arp, <>sf_arp

sf_nichts
	rts
sf_frei                         ; Gleiten, Fallen: FREQ + DF
	.as
	ldx SF_V
	#akku16
	lda @l KL_STAND+ST_FREQ,x
	clc
	adc @l KL_STAND+ST_DF,x
	sta @l KL_STAND+ST_FREQ,x
	#akku8
	rts
sf_blenden                      ; Ein-, Ausblenden: LAUT + DL, 0-15
	.as
	ldx SF_V
	#akku16
	lda @l KL_STAND+ST_LAUT,x
	clc
	adc @l KL_STAND+ST_DL,x
	bpl +
	lda #0
+	cmp #$1000
	bcc +
	lda #$0f00
+	sta @l KL_STAND+ST_LAUT,x
	#akku8
	rts
sf_vibrato                      ; GRUND + d * (0 1 2 1 0 -1 -2 -1), d = GRUND / 64
	.as
	ldx SF_V
	lda @l KL_STAND+ST_BILD,x
	sta SF_D
	#akku16
	lda @l KL_STAND+ST_GRUND,x
	lsr a
	lsr a
	lsr a
	lsr a
	lsr a
	lsr a
	sta SF_U
	lda SF_D
	and #$0003
	beq _null
	cmp #2
	bne +
	asl SF_U                    ; 2 d
+	lda SF_D
	and #$0004
	beq _plus
	lda @l KL_STAND+ST_GRUND,x
	sec
	sbc SF_U
	bra _setzen
_plus
	lda @l KL_STAND+ST_GRUND,x
	clc
	adc SF_U
	bra _setzen
_null
	lda @l KL_STAND+ST_GRUND,x
_setzen
	sta @l KL_STAND+ST_FREQ,x
	#akku8
	rts
sf_arp                          ; Note, +4, +7 (schnell je Bild, langsam je 2)
	.as
	ldx SF_V
	lda @l KL_STAND+ST_FX,x
	cmp #7
	lda @l KL_STAND+ST_BILD,x
	bcc +
	lsr a
+
-	cmp #3                      ; mod 3
	bcc +
	sbc #3
	bra -
+	sta SF_D
	lda @l KL_STAND+ST_NOTE,x
	pha
	lda SF_D
	beq _grund
	cmp #1
	beq _terz
	pla
	clc
	adc #7
	bra _note
_terz
	pla
	clc
	adc #4
	bra _note
_grund
	pla
_note
	jsr sf_freq
	ldx SF_V
	#akku16
	lda SF_T
	sta @l KL_STAND+ST_FREQ,x
	#akku8
	rts

;----------------------------------------------------------------------------
; BASIC: SFX n[,v] (ueber ws_basic, A = 5; D = 0). Klang n (0-63) auf Stimme
; v (1-4), ohne v auf einer freien (von 4 abwaerts, sonst 4); n = -1 haelt
; Stimme v an, ohne v alle.

	.dpage 0
wb_sfx
	.as
	lda P_ANZ
	bne +
	jmp wb_falsch
+	ldx #3                      ; Stimme
	lda P_ANZ
	cmp #2
	bcc _frei
	lda #5
	sta WB_GRENZE
	ldy #3
	jsr wb_wert
	bcs _f
	dec a
	bmi _f
	#akku16
	and #$0003
	tax
	#akku8
	bra _klang
_frei
	lda SFX_AN                  ; die erste freie von 4 abwaerts
	sta WB_BIT
-	lda WB_BIT
	and @l sf_bits,x
	beq _klang
	dex
	bpl -
	ldx #3
_klang
	lda P_WERT+2                ; -1: anhalten
	bmi _stopp
	lda #64
	sta WB_GRENZE
	ldy #0
	phx
	jsr wb_wert
	plx
	bcs _f
	jsr sf_start
	lda #0
	rtl
_stopp
	lda P_ANZ
	cmp #2
	bcc _alle
	php
	sei
	txa
	sta SF_N
	jsr sf_stopp_n
	plp
	lda #0
	rtl
_alle
	jsr sf_alle_aus
	lda #0
	rtl
_f
	jmp wb_falsch

	.dpage W_RAM
