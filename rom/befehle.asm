;============================================================================
;  MERIDIAN-Befehle fuer BASIC (Etappe 9c) - wird in kern.asm eingebunden
;
;  BLIT, STAMP, SPRITE, PATTERN, SAMPLE, GRADIENT (bis Etappe 10 deutsch:
;  KOPIERE, STEMPEL, SPRITE, MUSTER, SAMPLE, VERLAUF). BASIC legt die Werte
;  ab P_WERT ab (je 3 Byte, 24 Bit mit Vorzeichen, Anzahl in P_ANZ) und ruft
;  die Bruecke $FFBB mit der Nummer des Befehls in A. Zurueck kommt A = 0
;  (gut) oder nicht 0 (BASIC meldet ?ILLEGAL QUANTITY).
;
;  Aufgerufen nativ (ueber b_ein): Akku 8 Bit, X/Y 16 Bit, Datenbank 0.
;  Nur ASCII in dieser Datei (sie wird nicht nach Latin-1 gewandelt).
;============================================================================

; Seite 3 (Bank 0; BASIC sieht sie ueber den Spiegel an derselben Stelle)
P_ANZ      = $039F              ; Anzahl der Werte
P_WERT     = $03A0              ; Wert i ab P_WERT + 3*i (bis 8 Werte)
SP_AN      = $03BC              ; Sprites eingeschaltet (Tabelle geloescht)
VL_FARBE   = $03BD              ; Palettenindex des Verlaufs
VL_AN      = $03BE              ; VERLAUF laeuft
K_LISTE    = $03C0              ; KRAN-Auftragsliste (2 x 16 Byte)
K_Q        = $03E0              ; KOPIERE: Quelle (3), Ziel (3), Laenge (3),
K_Z        = $03E3              ;   volle 16-KB-Zeilen (2), Rest (2),
K_L        = $03E6              ;   Versatz der Zeilen (3)
K_N        = $03E9
K_R        = $03EB
K_O        = $03ED
VL_V       = $03E0              ; VERLAUF: Farbanteile r, g, b (8.8)
VL_S       = $03E6              ;   und ihre Schritte je Zeile
AJOB       = $03F0              ; ein KRAN-Auftrag im Aufbau (16 Byte):
AQ         = AJOB+0             ;   Quelle
AZ         = AJOB+3             ;   Ziel
AW         = AJOB+6             ;   Breite
AH         = AJOB+8             ;   Hoehe
AQA        = AJOB+10            ;   Abstand Quelle
AZA        = AJOB+12            ;   Abstand Ziel
AWERT      = AJOB+14            ;   Wert (Fuellen, Durchsicht)
AM         = AJOB+15            ;   Modus

; Chip-RAM fuer VERLAUF und SAMPLE (Bank 3, hinter der BASIC-Grafik)
VL_TAB     = $032C00            ; Farbe je Zeile, 240 x 2 Byte
VL_LISTE   = $032E00            ; Copper-Liste, 240 x 16 Byte + ENDE

KOB_TAB    = $C300
KOB_MADR   = $C400
KOB_MDATEN = $C402
LOT_LISTE  = $C700
KRAN_LISTE = $C611
PIN_PHI_   = $C00A

	.xl                         ; Indexregister 16 Bit (Konvention des Kerns)

wert_lo	.macro i                ; A = untere 16 Bit von Wert i (Akku 16 Bit)
	lda P_WERT+3*\i
	.endm

bb_befehl
	.as
	#akku16
	and #$00ff
	asl a
	tax
	#akku8
	jmp (b_tabelle,x)

b_tabelle
	.word kopiere, stempel, sprite, muster, sample, verlauf
	.word d_lade, d_sichere, d_katalog, d_entferne, d_leere, d_laufwerk
	.word d_save, d_load
	.word maus_befehl, play_befehl, stille_befehl  ; 14 MOUSE, 15 PLAY, 16 SILENCE
	.word net_befehl, dos_fehlertext               ; 17 NET, 18 Text zu DOS-Fehler

play_befehl                     ; PLAY "noten"[,stimme] (Etappe 11, ROM Bank $FF)
	.as
	lda #0
	jsl MUSIK
	rts

dos_fehlertext                  ; Text zum DOS-Fehler P_WERT (2-9) fuer BASIC, 10-12 Schleifen
	.as
	lda P_WERT
	sec
	sbc #2
	cmp #11
	bcs +
	asl a
	#akku16
	and #$00ff
	tax
	lda df_tabelle,x
	tax
	#akku8
	jsr print
+	jmp b_gut

df_tabelle
	.word df_2, df_3, df_4, df_5, df_6, df_7, df_8, df_9
	.word df_10, df_11, df_12   ; Etappe 13: Schleifen
df_2	.text "FILE NOT FOUND", 0
df_3	.text "DISK FULL", 0
df_4	.text "NO DISK", 0
df_5	.text "BAD DISK", 0
df_6	.text "WRITE PROTECTED", 0
df_7	.text "DIRECTORY FULL", 0
df_8	.text "FILE TOO BIG", 0
df_9	.text "BAD FILE NAME", 0
df_10	.text "WEND WITHOUT WHILE", 0
df_11	.text "WHILE WITHOUT WEND", 0
df_12	.text "UNTIL WITHOUT REPEAT", 0

net_befehl                      ; NET "befehl"[,kanal] (Etappe 12, ROM Bank $FF)
	.as
	lda #0
	jsl NETZ
	rts

stille_befehl                   ; SILENCE: Stimmen und Samplekanaele aus, PLAY halt
	.as
	lda #1
	jsl MUSIK
	ldx #0
-	stz ORG+4,x
	stz ORG+$8b,x
	#akku16
	txa
	clc
	adc #16
	tax
	#akku8
	cpx #64
	bne -
	jmp b_gut

b_gut
	#akku8
	lda #0
	rts
b_fehler
	#akku8
	lda #1
	rts

;----------------------------------------------------------------------------
; KRAN-Hilfen

auftrag                         ; AJOB nach K_LISTE+Y, Y += 16
	#akku8
	ldx #0
-	lda AJOB,x
	sta K_LISTE,y
	iny
	inx
	cpx #16
	bne -
	rts

kran_los                      ; Liste bis K_LISTE+Y ausfuehren, warten
	#akku8
	lda K_LISTE-1,y             ; letzter Auftrag: Bit 7 im Modus
	ora #$80
	sta K_LISTE-1,y
	lda #<K_LISTE
	sta KRAN_LISTE
	lda #>K_LISTE
	sta KRAN_LISTE+1
	stz KRAN_LISTE+2
	lda #$02
	sta KRAN_BEF
-	lda KRAN_BEF
	and #$01
	bne -
	rts

kran_los_gut
	jsr kran_los
	jmp b_gut

;----------------------------------------------------------------------------
; BLIT von, nach, laenge - ueberall im Speicher, auch ueberlappend.
; KRAN-Abstaende haben 16 Bit mit Vorzeichen, deshalb in Zeilen zu 16 KB und
; einen Rest. Liegt das Ziel im Quellbereich hinter der Quelle, rueckwaerts.
kopiere
	.as
	lda P_ANZ
	cmp #3
	beq +
	jmp b_fehler
+	ldx #0                      ; Quelle, Ziel, Laenge nach K_Q, K_Z, K_L
-	lda P_WERT,x
	sta K_Q,x
	inx
	cpx #9
	bne -
	#akku16
	lda K_L+1                   ; Bits 8-23 >> 6 = Laenge >> 14
	lsr a
	lsr a
	lsr a
	lsr a
	lsr a
	lsr a
	sta K_N
	lda K_L
	and #$3fff
	sta K_R
	ora K_N
	bne +
	jmp b_gut                   ; Laenge 0: nichts zu tun
+	lda K_N                     ; K_O = K_N * 16 KB
	and #$0003
	xba
	asl a
	asl a
	asl a
	asl a
	asl a
	asl a
	sta K_O
	lda K_N
	lsr a
	lsr a
	#akku8
	sta K_O+2
	#akku16                     ; D = Ziel - Quelle
	sec
	lda K_Z
	sbc K_Q
	sta wert
	#akku8
	lda K_Z+2
	sbc K_Q+2
	sta wert+2
	bcc _vor                    ; Ziel vor der Quelle
	#akku16
	sec
	lda wert
	sbc K_L
	#akku8
	lda wert+2
	sbc K_L+2
	bcc _rueck                  ; Ziel im Quellbereich

_vor
	ldy #0
	#akku16
	lda K_N
	beq +
	jsr a_quelle_ziel           ; die vollen Zeilen
	lda #$4000
	sta AW
	sta AQA
	sta AZA
	lda K_N
	sta AH
	#akku8
	stz AM
	jsr auftrag
+	#akku16
	lda K_R
	beq +
	jsr a_quelle_ziel           ; der Rest dahinter
	jsr a_plus_versatz
	lda K_R
	sta AW
	lda #1
	sta AH
	stz AQA
	stz AZA
	#akku8
	stz AM
	jsr auftrag
+	jmp kran_los_gut

_rueck
	ldy #0
	#akku16
	lda K_R
	beq +
	jsr a_quelle_ziel           ; zuerst der Rest am Ende, von hinten
	jsr a_plus_laenge
	jsr a_minus_1
	lda K_R
	sta AW
	lda #1
	sta AH
	stz AQA
	stz AZA
	#akku8
	lda #$04                    ; Zeile rueckwaerts
	sta AM
	jsr auftrag
+	#akku16
	lda K_N
	beq +
	jsr a_quelle_ziel           ; dann die vollen Zeilen, von der letzten an
	jsr a_plus_versatz
	jsr a_minus_1
	lda #$4000
	sta AW
	lda #$c000                  ; -16 KB
	sta AQA
	sta AZA
	lda K_N
	sta AH
	#akku8
	lda #$04
	sta AM
	jsr auftrag
+	jmp kran_los_gut

a_quelle_ziel                   ; AQ = K_Q, AZ = K_Z (6 Byte am Stueck)
	#akku16
	lda K_Q
	sta AQ
	lda K_Q+2
	sta AQ+2
	lda K_Q+4
	sta AQ+4
	rts

a_plus_versatz                  ; AQ und AZ um K_O weiter
	ldx #K_O
	bra a_plus
a_plus_laenge                   ; AQ und AZ um K_L weiter
	ldx #K_L
a_plus                          ; X = Adresse eines 24-Bit-Werts in Seite 3
	#akku16
	clc
	lda AQ
	adc 0,x
	sta AQ
	#akku8
	lda AQ+2
	adc 2,x
	sta AQ+2
	#akku16
	clc
	lda AZ
	adc 0,x
	sta AZ
	#akku8
	lda AZ+2
	adc 2,x
	sta AZ+2
	#akku16
	rts

a_minus_1                       ; AQ und AZ um 1 zurueck
	#akku16
	lda AQ
	bne +
	#akku8
	dec AQ+2
	#akku16
+	dec AQ
	lda AZ
	bne +
	#akku8
	dec AZ+2
	#akku16
+	dec AZ
	rts

;----------------------------------------------------------------------------
; STAMP adr, x, y, b, h - Bild (b x h Bytes, Farbe 0 durchsichtig) von adr
; (auch Zusatzspeicher) in die BASIC-Grafik bei x, y
stempel
	.as
	lda P_ANZ
	cmp #5
	bne _f
	#akku16
	#wert_lo 3                  ; b: 1..320
	beq _f
	cmp #321
	bcs _f
	sta AW
	sta AQA
	#wert_lo 1                  ; x < 320 und x + b <= 320
	cmp #320
	bcs _f
	clc
	adc AW
	cmp #321
	bcs _f
	#wert_lo 4                  ; h: 1..240
	beq _f
	cmp #241
	bcs _f
	sta AH
	#wert_lo 2                  ; y < 240 und y + h <= 240
	cmp #240
	bcs _f
	clc
	adc AH
	cmp #241
	bcs _f
	#wert_lo 2                  ; Ziel = $020000 + y*320 + x
	xba                         ; y*256
	sta AZ
	#wert_lo 2
	asl a
	asl a
	asl a
	asl a
	asl a
	asl a                       ; y*64
	clc
	adc AZ
	sta AZ
	#akku8
	lda #2
	adc #0
	sta AZ+2
	#akku16
	clc
	lda AZ
	adc P_WERT+3                ; + x
	sta AZ
	#akku8
	lda AZ+2
	adc #0
	sta AZ+2
	#akku16
	lda P_WERT                  ; Quelle
	sta AQ
	lda #320
	sta AZA
	#akku8
	lda P_WERT+2
	sta AQ+2
	stz AWERT                   ; Farbe 0 bleibt durchsichtig
	lda #2                      ; kopieren ohne Bytes = WERT
	sta AM
	ldy #0
	jsr auftrag
	jmp kran_los_gut
_f	jmp b_fehler

;----------------------------------------------------------------------------
; SPRITE n[, x, y[, m[, f]]] - Sprite n (0-31) bei x, y zeigen, Muster m,
; Bits f (Palettenbank 0-15, +16 spiegeln X, +32 Y, +64 hinter der Grafik,
; +128 doppelt gross). Nur n: ausblenden.
sprite
	.as
	#akku16
	#wert_lo 0
	cmp #32
	bcs _f
	asl a
	asl a
	asl a
	tax                         ; X = n * 8
	#akku8
	lda P_ANZ
	cmp #1
	bne +
	stz KOB_TAB+6,x             ; ausblenden
	jmp b_gut
+	cmp #3
	bcc _f
	cmp #6
	bcs _f
	jsr sprites_an              ; der erste SPRITE: alle aus, dann KOBOLD an
	#akku16
	lda P_WERT+3                ; Bildschirm-X + 32
	clc
	adc #32
	sta KOB_TAB+0,x
	lda P_WERT+6                ; Bildschirm-Y + 32
	clc
	adc #32
	sta KOB_TAB+2,x
	#akku8
	lda P_ANZ
	cmp #4
	bcc +
	lda P_WERT+9
	and #$7f
	sta KOB_TAB+4,x
	lda P_ANZ
	cmp #5
	bcc +
	lda P_WERT+12
	sta KOB_TAB+5,x
+	lda #1
	sta KOB_TAB+6,x
	jmp b_gut
_f	jmp b_fehler

;----------------------------------------------------------------------------
; PATTERN m, z, "text" - Zeile z (0-15) von Muster m (0-127): 16 Zeichen, je
; ein Pixel als Hexziffer (0-F, "." oder Leerzeichen = 0 = durchsichtig)
muster
	.as
	lda P_ANZ
	cmp #2
	bne _f
	lda P_WERT+6                ; Laenge des Textes
	cmp #16
	bne _f
	#akku16
	#wert_lo 0
	cmp #128
	bcs _f
	xba
	lsr a                       ; m * 128
	sta zeiger
	#wert_lo 1
	cmp #16
	bcs _f
	asl a
	asl a
	asl a                       ; z * 8
	clc
	adc zeiger
	#akku8
	sta KOB_MADR
	xba
	sta KOB_MADR+1
	#akku16                     ; der Text liegt in BASICs Datenbank
	lda P_WERT+7
	sta zeiger
	#akku8
	lda #B_DATENBANK
	sta zeiger+2
	ldy #0
-	lda [zeiger],y              ; linkes Pixel ins obere Halbbyte
	jsr hexziffer
	bcs _f
	asl a
	asl a
	asl a
	asl a
	sta tmp
	iny
	lda [zeiger],y
	jsr hexziffer
	bcs _f
	ora tmp
	sta KOB_MDATEN
	iny
	cpy #16
	bne -
	jmp b_gut
_f	jmp b_fehler

hexziffer                         ; Zeichen -> 0-15; Carry gesetzt: unbekannt
	.as
	cmp #'.'
	beq _null
	cmp #' '
	beq _null
	cmp #'0'
	bcc _nein
	cmp #'9'+1
	bcc _ziffer
	and #$df                    ; klein -> gross
	cmp #'A'
	bcc _nein
	cmp #'F'+1
	bcs _nein
	sbc #'A'-11                 ; Carry geloescht: A - 'A' + 10
	clc
	rts
_ziffer
	sbc #'0'-1                  ; Carry geloescht: A - '0'
	clc
	rts
_null
	lda #0
	clc
	rts
_nein
	sec
	rts

;----------------------------------------------------------------------------
; SAMPLE k[, adr, laenge[, hz[, laut[, schleife]]]] - Samplekanal k (0-7)
; spielt laenge Bytes ab adr (8 Bit mit Vorzeichen) mit hz (Vorgabe 22050),
; laut 0-63 (Vorgabe 63), schleife <> 0: immer wieder. Seit Etappe 15
; spielt die ORGEL auch direkt aus dem Zusatzspeicher (bis 16 MB lang).
; Nur k: anhalten.
sample
	.as
	#akku16
	#wert_lo 0
	cmp #8                      ; Kanal 0-7 (4-7 seit Etappe 17, ab $CC80)
	bcs _f
	asl a
	asl a
	asl a
	asl a
	cmp #$40
	bcc +
	adc #$6c0-1                 ; (C = 1) Kanal 4-7: k * 16 + $6C0
+	tax                         ; X = Versatz ab ORG_KANAL
	#akku8
	stz ORG_KANAL+$b,x          ; anhalten
	lda P_ANZ
	cmp #1
	bne +
	jmp b_gut
+	cmp #3
	bcc _f
	cmp #7
	bcs _f
	lda P_WERT+6                ; Laenge 1 bis 16 MB
	ora P_WERT+7
	ora P_WERT+8
	beq _f
	lda P_WERT+3                ; START (Chip-RAM oder Zusatzspeicher)
	sta ORG_KANAL+0,x
	lda P_WERT+4
	sta ORG_KANAL+1,x
	lda P_WERT+5
	sta ORG_KANAL+2,x
	lda P_WERT+6                ; LAENGE
	sta ORG_KANAL+3,x
	lda P_WERT+7
	sta ORG_KANAL+4,x
	lda P_WERT+8                ; Bits 16-23 (nach +3)
	sta ORG_KANAL+$e,x
	stz ORG_KANAL+5,x           ; SCHLEIFE: zurueck zum Anfang (+F mit)
	stz ORG_KANAL+6,x
	lda P_ANZ                   ; SCHRITT = hz * 4295 / 65536
	cmp #4
	#akku16
	lda #22050
	bcc +
	#wert_lo 3
+	sta hilf
	phx
	jsr mal_4295
	plx
	sta ORG_KANAL+7,x
	#akku8
	lda P_ANZ                   ; LAUT
	cmp #5
	lda #63
	bcc +
	lda P_WERT+12
	cmp #64
	bcc +
	lda #63
+	sta ORG_KANAL+9,x
	lda #$ff                    ; Mitte
	sta ORG_KANAL+$a,x
	lda P_ANZ                   ; STEUER: spielen, auf Wunsch in Schleife
	cmp #6
	bcc _einmal
	lda P_WERT+15
	ora P_WERT+16
	beq _einmal
	lda #$03
	bra _los
_einmal
	lda #$01
_los
	sta ORG_KANAL+$b,x
	jmp b_gut
_f	jmp b_fehler

mal_4295                        ; A = hilf * 4295 / 65536 (16 Bit)
	#akku16
	lda #4295
	sta tmp
	stz wert                    ; Produkt: sprung (oben) : wert (unten)
	stz sprung
	ldx #16
-	asl wert
	rol sprung
	asl tmp
	bcc +
	clc
	lda wert
	adc hilf
	sta wert
	bcc +
	inc sprung
+	dex
	bne -
	lda sprung
	rts

;----------------------------------------------------------------------------
; GRADIENT z1, r1, g1, b1, z2, r2, g2, b2 - Farbverlauf der Hintergrundfarbe
; von Zeile z1 bis z2 (0-239), Farbanteile 0-15. LOTSE setzt die Farbe in
; jeder Zeile neu; mehrere Verlaeufe ergaenzen sich. VERLAUF allein: aus.
verlauf
	.as
	lda P_ANZ
	bne _an
	stz LOT_STEUER              ; aus
	lda VL_AN
	beq +
	stz VL_AN
	jsr vl_grundfarbe
	lda VL_FARBE                ; Hintergrundfarbe wie vorher
	sta PIN_PIDX
	#akku16
	txa
	#akku8
	sta PIN_PLO
	xba
	sta PIN_PHI_
+	jmp b_gut
_f	jmp b_fehler
_an
	cmp #8
	bne _f
	#akku16
	ldx #0                      ; Farbanteile 0..15?
-	ldy vl_anteile,x
	lda P_WERT,y
	cmp #16
	bcs _f
	inx
	inx
	cpx #12
	bne -
	#wert_lo 4                  ; z1 <= z2 < 240
	cmp #240
	bcs _f
	cmp P_WERT
	bcc _f
	#akku8
	lda VL_AN                   ; der erste Verlauf: Tabelle mit der
	bne _rechnen                ; Hintergrundfarbe fuellen
	lda farbe
	lsr a
	lsr a
	lsr a
	lsr a
	sta VL_FARBE
	jsr vl_grundfarbe
	#akku16
	txa
	ldx #0
-	sta VL_TAB,x
	inx
	inx
	cpx #480
	bne -
_rechnen
	#akku16
	ldx #0                      ; je Anteil: Start (8.8) und Schritt
_anteil
	ldy vl_anteile,x            ; Anfang
	lda P_WERT,y
	xba
	ora #$0080                  ; + 0,5 zum Runden
	sta VL_V,x
	lda P_WERT+12               ; Zeilen: z2 - z1
	sec
	sbc P_WERT
	sta hilf
	stz VL_S,x
	beq _naechst
	ldy vl_anteile+6,x          ; Ende - Anfang
	lda P_WERT,y
	ldy vl_anteile,x
	sec
	sbc P_WERT,y
	php
	bpl +
	eor #$ffff
	inc a
+	xba                         ; |Unterschied| * 256 / Zeilen
	phx
	jsr teilen
	plx
	plp
	bpl +
	eor #$ffff
	inc a
+	sta VL_S,x
_naechst
	inx
	inx
	cpx #6
	bne _anteil
	lda P_WERT                  ; Zeilen z1..z2 in die Tabelle
	asl a
	tax
	lda P_WERT+12
	sec
	sbc P_WERT
	inc a
	sta anzahl
_zeile
	lda VL_V+2                  ; gruen ins obere Halbbyte
	and #$0f00
	lsr a
	lsr a
	lsr a
	lsr a
	sta tmp
	lda VL_V+4                  ; blau ins untere
	xba
	and #$000f
	ora tmp
	sta tmp
	lda VL_V+0                  ; rot ins obere Byte
	and #$0f00
	ora tmp
	sta VL_TAB,x
	ldy #0
-	lda VL_V,y
	clc
	adc VL_S,y
	sta VL_V,y
	iny
	iny
	cpy #6
	bne -
	inx
	inx
	dec anzahl
	bne _zeile
	jsr vl_copper
	jmp b_gut

vl_anteile                      ; Versatz von r1, g1, b1, r2, g2, b2 in P_WERT
	.word 3, 6, 9, 15, 18, 21

vl_grundfarbe                   ; X = Farbe VL_FARBE aus der Startpalette
	#akku16
	lda VL_FARBE
	and #$00ff
	asl a
	tax
	lda palette,x
	tax
	#akku8
	rts

teilen                          ; A = A / hilf (16 Bit, ohne Vorzeichen)
	#akku16
	sta tmp
	lda #0
	ldx #16
-	asl tmp
	rol a
	cmp hilf
	bcc +
	sbc hilf
	inc tmp
+	dex
	bne -
	lda tmp
	rts

vl_copper                        ; Copper-Liste aus VL_TAB bauen und starten
	#akku16
	stz zeiger                  ; Zeile
	ldx #0
-	lda zeiger                  ; WARTE Zeile, Zeilenanfang ($1FF)
	xba
	ora #$0001
	sta VL_LISTE+0,x
	lda #$ff02
	sta VL_LISTE+2,x
	lda #$0802                  ; SETZE PAL_IDX = Farbe
	sta VL_LISTE+4,x
	lda VL_FARBE
	xba
	and #$ff00
	ora #$00c0
	sta VL_LISTE+6,x
	phx                         ; Tabellenwert holen
	lda zeiger
	asl a
	tax
	lda VL_TAB,x
	sta hilf
	plx
	lda #$0902                  ; SETZE PAL_LO = gggg bbbb
	sta VL_LISTE+8,x
	lda hilf
	xba
	and #$ff00
	ora #$00c0
	sta VL_LISTE+10,x
	lda #$0a02                  ; SETZE PAL_HI = rrrr
	sta VL_LISTE+12,x
	lda hilf
	and #$ff00
	ora #$00c0
	sta VL_LISTE+14,x
	txa
	clc
	adc #16
	tax
	inc zeiger
	lda zeiger
	cmp #240
	bne -
	lda #0                      ; ENDE
	sta VL_LISTE+0,x
	sta VL_LISTE+2,x
	#akku8
	lda #<VL_LISTE
	sta LOT_LISTE
	lda #>VL_LISTE
	sta LOT_LISTE+1
	lda #`VL_LISTE
	sta LOT_LISTE+2
	lda #1
	sta LOT_STEUER
	sta VL_AN
	rts

;============================================================================
; Datentraeger (Etappe 10): BASIC-Befehle fuer das DOS im DOS-ROM ($FF:4000)
;
; BASIC legt den Dateinamen als Laenge P_TLEN und Zeiger P_TPTR (in BASICs
; Datenbank) ab, die Zahlen wie immer ab P_WERT; SAVE/LOAD zusaetzlich
; Anfang und Laenge in P_START/P_LEN. Fehler des DOS (2-9) gibt der Kern
; an BASIC weiter, das sie als eigene Meldungen ausgibt.

P_START    = $0390              ; 3 Byte: Anfang (SAVE/LOAD)
P_LEN      = $0393              ; 3 Byte: Laenge / hoechstens
P_TLEN     = $039C              ; Laenge des Namens
P_TPTR     = $039D              ; 2 Byte: Name in Bank B_DATENBANK
STD_LW     = $16FF              ; Laufwerk, wenn keins angegeben ist
DZ_SCHON   = $16F0              ; Dezimalausgabe (chrout benutzt tmp!)
DZ_ZIFFER  = $16F1

DOS        = $FF4000
D_LW       = $16C0
D_MER      = $16C2
D_ENDUNG   = $16C3
D_TLEN     = $16C6
D_TEXT     = $16C7
D_ADR      = $16E4
D_LAENGE   = $16E8
D_INDEX    = $16EC

dos_name                        ; Name aus BASIC nach D_TEXT; A = Fehler
	.as
	lda P_TLEN
	beq _f
	cmp #17
	bcs _f
	sta D_TLEN
	#akku16
	lda P_TPTR
	sta zeiger
	#akku8
	lda #B_DATENBANK
	sta zeiger+2
	ldy #0
-	lda [zeiger],y
	sta D_TEXT,y
	iny
	tya
	cmp D_TLEN
	bne -
	lda #0
	rts
_f
	lda #9                      ; leer oder zu lang
	rts

endung                          ; D_ENDUNG = Text ab X (3 Zeichen)
	.as
	ldy #0
-	lda 0,x
	sta D_ENDUNG,y
	inx
	iny
	cpy #3
	bne -
	rts

dos_ruf                         ; DOS-Befehl A; A = Fehler (wie BASIC ihn braucht)
	.as
	jsl DOS
	rts

; BLOAD "name"[,adresse[,laufwerk]]
d_lade
	.as
	jsr dos_name
	bne _f
	ldx #e_mer
	jsr endung
	#akku16                     ; Ziel: Wert 0 oder aus dem MER-Kopf
	lda #$ffff
	sta D_ADR
	sta D_LAENGE
	#akku8
	sta D_ADR+2
	lda #$ff
	sta D_LAENGE+2
	stz D_LAENGE+3
	lda P_ANZ
	beq +
	#akku16
	lda P_WERT
	sta D_ADR
	#akku8
	lda P_WERT+2
	sta D_ADR+2
+	ldx #1
	jsr lw_wert
	lda #0
	jmp dos_ruf
_f
	jmp b_fehler

; BSAVE "name",adresse,laenge[,laufwerk] - mit MER-Kopf
d_sichere
	.as
	lda P_ANZ
	cmp #2
	bcc _f
	jsr dos_name
	bne _f
	ldx #e_mer
	jsr endung
	#akku16
	lda P_WERT
	sta D_ADR
	lda P_WERT+3
	sta D_LAENGE
	#akku8
	lda P_WERT+2
	sta D_ADR+2
	lda P_WERT+5
	sta D_LAENGE+2
	stz D_LAENGE+3
	lda #1
	sta D_MER
	ldx #2
	jsr lw_wert
	lda #1
	jmp dos_ruf
_f
	jmp b_fehler

; SCRATCH "name"[,laufwerk]
d_entferne
	.as
	jsr dos_name
	bne _f
	ldx #e_bas
	jsr endung
	ldx #0
	jsr lw_wert
	lda #2
	jmp dos_ruf
_f
	jmp b_fehler

; HEADER "name"[,laufwerk] - Diskette neu anlegen (alles weg)
d_leere
	.as
	jsr dos_name
	bne _f
	ldx #0
	jsr lw_wert
	lda #5
	jmp dos_ruf
_f
	jmp b_fehler

; DRIVE n
d_laufwerk
	.as
	lda P_ANZ
	cmp #1
	bne _f
	lda P_WERT
	cmp #4                      ; 0-2 Images, 3 der Ordner (Netzdienst)
	bcs _f
	lda P_WERT+1
	ora P_WERT+2
	bne _f
	lda P_WERT
	sta STD_LW
	jmp b_gut
_f
	jmp b_fehler

; SAVE "name"[,laufwerk]: P_START/P_LEN = BASIC-Programm, ohne Kopf
d_save
	.as
	jsr dos_name
	bne _f
	ldx #e_bas
	jsr endung
	#akku16
	lda P_START
	sta D_ADR
	lda P_LEN
	sta D_LAENGE
	#akku8
	lda P_START+2
	sta D_ADR+2
	lda P_LEN+2
	sta D_LAENGE+2
	stz D_LAENGE+3
	stz D_MER
	ldx #0
	jsr lw_wert
	lda #1
	jmp dos_ruf
_f
	jmp b_fehler

; LOAD "name"[,laufwerk]: nach P_START, hoechstens P_LEN; zurueck P_LEN
d_load
	.as
	jsr dos_name
	bne _f
	ldx #e_bas
	jsr endung
	#akku16
	lda P_START
	sta D_ADR
	lda P_LEN
	sta D_LAENGE
	#akku8
	lda P_START+2
	sta D_ADR+2
	lda P_LEN+2
	sta D_LAENGE+2
	stz D_LAENGE+3
	ldx #0
	jsr lw_wert
	lda #0
	jsl DOS
	pha
	#akku16
	lda D_LAENGE
	sta P_LEN
	#akku8
	lda D_LAENGE+2
	sta P_LEN+2
	pla
	rts
_f
	jmp b_fehler

lw_wert                         ; D_LW = Wert X, wenn es ihn gibt, sonst STD_LW
	.as
	txa
	cmp P_ANZ
	bcs _std
	#akku16                     ; Wert X liegt bei P_WERT + 3*X
	txa
	and #$00ff
	sta tmp
	asl a
	adc tmp
	tax
	#akku8
	lda P_WERT,x
	sta D_LW
	rts
_std
	lda STD_LW
	sta D_LW
	rts

; DIR [laufwerk]
d_katalog
	.as
	ldx #0
	jsr lw_wert
	ldx #t_lw                   ; "LAUFWERK n"
	jsr print
	lda D_LW
	clc
	adc #'0'
	jsr chrout
	lda #13
	jsr chrout
	#akku16
	stz D_INDEX
	#akku8
_naechste
	jsr stopp_pruefen           ; Esc bricht ab
	cmp #3
	beq _ende
	lda #3
	jsl DOS
	cmp #2
	beq _frei                   ; keine weitere Datei
	cmp #0
	bne _fehler
	lda #' '
	jsr chrout
	ldx #0
-	txa
	cmp D_TLEN
	beq +
	lda D_TEXT,x
	jsr chrout
	inx
	bra -
+	txa                         ; Groesse ab Spalte 14
_luecke
	cmp #13
	bcs _zahl
	lda #' '
	jsr chrout
	inx
	txa
	bra _luecke
_zahl
	jsr dez_laenge
	lda #13
	jsr chrout
	bra _naechste
_frei
	lda #4
	jsl DOS
	cmp #0
	bne _fehler
	jsr dez_laenge
	ldx #t_frei
	jsr print
_ende
	jmp b_gut
_fehler
	rts

dez_laenge                      ; D_LAENGE (32 Bit) dezimal, 8 Stellen rechtsbuendig
	.as
	ldx #0                      ; Stelle (Zehnerpotenz)
	stz DZ_SCHON                ; schon eine Ziffer ausgegeben?
_stelle
	lda #'0'
	sta DZ_ZIFFER
_abziehen                       ; solange D_LAENGE >= 10^n: abziehen, Ziffer + 1
	#akku16
	lda D_LAENGE+2
	cmp zehner32+2,x
	bcc _ziffer
	bne _ab
	lda D_LAENGE
	cmp zehner32,x
	bcc _ziffer
_ab
	sec
	lda D_LAENGE
	sbc zehner32,x
	sta D_LAENGE
	lda D_LAENGE+2
	sbc zehner32+2,x
	sta D_LAENGE+2
	#akku8
	inc DZ_ZIFFER
	bra _abziehen
_ziffer
	#akku8
	lda DZ_ZIFFER
	cmp #'0'
	bne _zeigen
	lda DZ_SCHON
	bne _zeigen
	cpx #7*4                    ; letzte Stelle immer zeigen
	beq _zeigen
	lda #' '
	bra +
_zeigen
	sta DZ_SCHON
	lda DZ_ZIFFER
+	jsr chrout
	inx
	inx
	inx
	inx
	cpx #8*4
	bne _stelle
	rts

zehner32	.dword 10000000, 1000000, 100000, 10000, 1000, 100, 10, 1

e_mer	.text "MER"
e_bas	.text "BAS"
t_lw	.text "DRIVE ", 0
t_frei	.text " BYTES FREE", 13, 0
