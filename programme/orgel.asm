;============================================================================
;  ORGEL - Vorfuehrprogramm fuer den Klangchip (Etappe 6)
;
;  Spielt ein Musikstueck auf allen acht Kanaelen: vier Synthesestimmen
;  (Bass durchs Filter, Akkorde, Melodie, Echo) und vier Samplekanaele
;  (Kick, Snare, Hi-Hat, Stimme und Becken). Die Musik liegt als
;  Registerstrom ab $02:0000, die Samples ab $01:0000 (beides aus
;  tools/orgel.py). Der Spieler laeuft im Timer-A-Interrupt mit 50 Hz,
;  unabhaengig von der Bildfrequenz.
;
;  Die Anzeige liest Huellkurven und Samplepositionen direkt aus ORGEL;
;  was nur schreibbar ist (Frequenz, Welle, Filter), merkt sich der
;  Spieler in einem Schattenspeicher. Eine Taste beendet das Programm.
;
;  Daten vorher laden: programme/daten/orgel_klaenge.mer, orgel_musik.mer
;  Assemblieren: programme/bauen.sh orgel
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

GETIN        = $FF83
LOESCHEN     = $FF8F
ORGEL_STILL  = $FF98
BENUTZER_IRQ = $0300
BILDSCHIRM   = $0400
CUR_X        = $10              ; Cursor des Kerns
CUR_Y        = $11
BILDER       = $50              ; Bildzaehler des Kerns

PIN_PIDX   = $C008
PIN_PLO    = $C009
PIN_PHI    = $C00A
PFO_IRQST  = $C104
PFO_IRQEN  = $C105
PFO_TA     = $C114
PFO_TASTEU = $C116
ORG        = $C500
MUSIK      = $020000

; Direkte Seite (der Kern belegt $10-$54)
strom    = $80                  ; 3 Byte: naechstes Byte im Musikstrom
schleife = $84                  ; 3 Byte: Schleifenmarke
teil     = $87
t50      = $88                  ; Uhr: Fuenfzigstel, Sekunden, Minuten (BCD)
sek      = $89
minu     = $8A
letztes  = $8B                  ; zuletzt gesehener Bildzaehler
adr      = $8C                  ; 16 Bit: Anfang der Bildschirmzeile
zz       = $8E                  ; 16 Bit: Zaehler
hz       = $90                  ; 16 Bit: Textzeiger
kanal    = $92                  ; 16 Bit: Kanal 0-7 (0-3 Stimmen, 4-7 Samples)
reg      = $94                  ; 16 Bit: Kanal * $10
si       = $96                  ; 16 Bit: Sample-Nummer * 2
wert     = $98                  ; 16 Bit
pegel    = $9A                  ; 4 Byte: Pegel der Samplekanaele
bsp      = $9E                  ; Balken: erste Spalte
bbr      = $A0                  ; 16 Bit: Balken: Breite in Zeichen

ZEILE    = 80                   ; Bytes je Bildschirmzeile (40 Zeichen)
BALKEN   = 32                   ; Balkenbreite in Zeichen

	* = $2000

start
	.as
	.xl
	phb
	sei
	jsr bild_aufbauen
	lda #39                     ; Cursor in eine unsichtbare Ecke
	sta CUR_X
	lda #29
	sta CUR_Y

	#akku16                     ; Musik: Kopf = Schleifenadresse
	lda MUSIK
	sta schleife
	lda #(MUSIK+3) & $ffff
	sta strom
	stz kanal
	#akku8
	lda MUSIK+2
	sta schleife+2
	lda #`MUSIK
	sta strom+2
	stz teil
	stz t50
	stz sek
	stz minu
	ldx #0
-	stz schatten,x
	inx
	cpx #256
	bne -
	stz pegel
	stz pegel+1
	stz pegel+2
	stz pegel+3

	#akku16                     ; Interrupt-Haken einsetzen
	lda BENUTZER_IRQ
	sta alter_haken
	lda #haken
	sta BENUTZER_IRQ
	#akku8
	lda #<19999                 ; Timer A: 20 000 us = 50 Hz
	sta PFO_TA
	lda #>19999
	sta PFO_TA+1
	lda #$01
	sta PFO_TASTEU
	lda #$02
	sta PFO_IRQEN
	cli

haupt
	wai
	lda BILDER
	cmp letztes
	beq +
	sta letztes
	jsr anzeigen
+	jsr GETIN
	beq haupt

	sei                         ; aufraeumen
	stz PFO_TASTEU
	stz PFO_IRQEN
	lda #$06
	sta PFO_IRQST
	#akku16
	lda alter_haken
	sta BENUTZER_IRQ
	#akku8
	jsr ORGEL_STILL
	jsr LOESCHEN
	cli
	plb
	rtl

;----------------------------------------------------------------------------
; Interrupt-Haken: A = PINSEL-Status. Timer A -> ein Takt Musik.

haken
	.as
	lda PFO_IRQST
	and #$02
	beq +
	sta PFO_IRQST
	jsr spieler
	jsr uhr
+	rts

; Spieler: Register/Wert-Paare bis $FF; $FD n = Teil n; $FE = Schleife
spieler
	lda [strom]
	jsr weiter
	cmp #$fd
	bcs _marke
	#akku16                     ; Register als 16-Bit-Index
	and #$00ff
	tax
	#akku8
	lda [strom]
	jsr weiter
	sta ORG,x
	sta schatten,x
	bra spieler
_marke
	beq _teil
	cmp #$fe
	beq _schleife
	rts                         ; $FF: Takt fertig
_teil
	lda [strom]
	jsr weiter
	sta teil
	bra spieler
_schleife
	#akku16
	lda schleife
	sta strom
	#akku8
	lda schleife+2
	sta strom+2
	bra spieler

weiter                          ; Stromzeiger + 1, auch ueber Bankgrenzen
	#akku16
	inc strom
	#akku8
	bne +
	inc strom+2
+	rts

; Spielzeit im Dezimalmodus
uhr
	inc t50
	lda t50
	cmp #50
	bcc _fertig
	stz t50
	sed
	lda sek
	clc
	adc #$01
	sta sek
	cmp #$60
	bcc +
	stz sek
	lda minu
	clc
	adc #$01
	sta minu
+	cld
_fertig
	rts

;----------------------------------------------------------------------------
; Bildschirm einrichten: Palette, Farben, feste Texte

bild_aufbauen
	stz PIN_PIDX
	ldx #0
-	lda palette,x
	sta PIN_PLO
	lda palette+1,x
	sta PIN_PHI
	inx
	inx
	cpx #32
	bne -

	ldx #0                      ; alles leer, grau auf Grund
-	lda #' '
	sta BILDSCHIRM,x
	lda #$02
	sta BILDSCHIRM+1,x
	inx
	inx
	cpx #30*ZEILE
	bne -
	stz BILDSCHIRM+29*ZEILE+39*2+1   ; Cursorzelle: Farbe 0 auf 0

	ldx #BILDSCHIRM+2*ZEILE+2   ; Trennlinien
	jsr linie
	ldx #BILDSCHIRM+24*ZEILE+2
	jsr linie

	ldx #0                      ; Balkenspuren mit Farbverlauf
-	lda balken_zeilen,x
	#akku16
	and #$00ff
	jsr zeilenadresse
	clc
	adc #3*2
	tay
	#akku8
	lda balken_farbe,x
	sta zz
	lda balken_schritt,x
	sta wert
	lda #BALKEN
	sta zz+1
-	lda zz                      ; alle 8 Zeichen eine Farbe weiter
	sta $0001,y
	iny
	iny
	dec zz+1
	lda zz+1
	and #$07
	bne -
	lda zz
	clc
	adc wert
	sta zz
	lda zz+1
	bne -
	inx
	cpx #9
	bne --

	ldx #texte                  ; feste Texte: Adresse, Farbe, Text, 0
_text
	#akku16
	lda $0000,x
	beq _texte_fertig
	tay
	#akku8
	lda $0002,x
	sta zz
	inx
	inx
	inx
-	lda $0000,x
	beq +
	sta $0000,y
	lda zz
	sta $0001,y
	iny
	iny
	inx
	bra -
+	inx
	bra _text
_texte_fertig
	#akku8
	ldx #0                      ; L und R neben jeder Panoramaanzeige
-	lda label_zeilen,x
	#akku16
	and #$00ff
	jsr zeilenadresse
	tay
	#akku8
	lda #'L'
	sta 31*2,y
	lda #'R'
	sta 39*2,y
	lda #$07
	sta 31*2+1,y
	sta 39*2+1,y
	inx
	cpx #8
	bne -
	rts

linie                           ; 38 Striche ab X
	ldy #38
-	lda #$80
	sta $0000,x
	lda #$07
	sta $0001,x
	inx
	inx
	dey
	bne -
	rts

zeilenadresse                   ; A16 = Zeile -> A16 = Bildschirmadresse (zz weg)
	.al
	asl a                       ; * 80 = * 64 + * 16
	asl a
	asl a
	asl a
	sta zz
	asl a
	asl a
	clc
	adc zz
	clc
	adc #BILDSCHIRM
	rts
	.as

;----------------------------------------------------------------------------
; Anzeige, einmal je Bild

anzeigen
	lda #3                      ; Kanalbalken: ab Spalte 3, 32 Zeichen
	sta bsp
	#akku16
	lda #BALKEN
	sta bbr
	#akku8
	stz kanal
_stimme                         ; vier Synthesestimmen
	jsr kanal_einrichten
	ldx reg                     ; Wellenform aus STEUER Bits 4-7
	lda schatten+4,x
	and #$f0
	lsr a
	#akku16
	and #$00ff
	clc
	adc #wellen_namen
	sta hz
	#akku8
	lda #12
	ldy #8
	jsr schreib
	ldx reg                     ; Note, solange das Gate offen ist
	lda schatten+4,x
	and #$01
	beq _ohne_note
	#akku16
	lda schatten,x
	jsr notenname
	#akku8
	bra +
_ohne_note
	jsr leer_zeigen
+	lda #21
	ldy #3
	jsr schreib
	ldx kanal                   ; laeuft die Stimme durchs Filter?
	lda bits,x
	and schatten+$42
	#akku16
	beq +
	lda #t_filter
	bra ++
+	lda #t_leer
+	sta hz
	#akku8
	lda #25
	ldy #6
	jsr schreib
	ldx reg
	lda schatten+8,x
	jsr pan_zeigen
	ldx reg                     ; Pegel = Huellkurve aus ORGEL
	lda ORG+9,x
	jsr balken_zeigen
	inc kanal
	lda kanal
	cmp #4
	bne _stimme

	lda #4
	sta kanal
_kanal                          ; vier Samplekanaele
	jsr kanal_einrichten
	ldx reg                     ; welches Sample? Startadresse vergleichen
	#akku16
	lda schatten+$80,x
	ldy #0
-	cmp smp_start,y
	beq _gefunden
	iny
	iny
	cpy #SAMPLES*2
	bne -
	#akku8
	jsr leer_zeigen             ; noch nichts gespielt
	lda #12
	ldy #8
	jsr schreib
	lda #21
	ldy #6
	jsr schreib
	lda #0
	bra _pegel
_gefunden
	.al                         ; hier noch 16 Bit vom Vergleich
	sty si
	tya                         ; Name: 8 Zeichen je Sample
	asl a
	asl a
	clc
	adc #smp_namen
	sta hz
	#akku8
	lda #12
	ldy #8
	jsr schreib
	#akku16                     ; Rate: 6 Zeichen je Sample
	lda si
	asl a
	clc
	adc si
	clc
	adc #smp_raten
	sta hz
	#akku8
	lda #21
	ldy #6
	jsr schreib
	ldx reg                     ; spielt er? Dann Pegel aus der Huellkurve
	lda ORG+$8b,x
	and #$01
	beq _pegel
	lda ORG+$8d,x               ; Position / 256 = Block
	ldy si
	cmp smp_bloecke,y
	lda #0
	bcs _pegel
	lda ORG+$8d,x
	#akku16
	and #$00ff
	sta wert
	lda smp_huelle,y
	clc
	adc wert
	tay
	#akku8
	lda $0000,y
_pegel                          ; A = neuer Pegel; der alte faellt langsam ab
	sta wert
	ldx kanal
	lda pegel-4,x
	sec
	sbc #12
	bcs +
	lda #0
+	cmp wert
	bcs +
	lda wert
+	sta pegel-4,x
	pha
	ldx reg
	lda schatten+$8a,x
	jsr pan_zeigen
	pla
	jsr balken_zeigen
	inc kanal
	lda kanal
	cmp #8
	beq +
	jmp _kanal
+
	; Filter: Art, Resonanz, Eckfrequenz
	#akku16
	lda #25
	jsr zeilenadresse
	sta adr
	#akku8
	lda schatten+$43            ; Art: Bits 4-6, 10 Zeichen je Name
	lsr a
	lsr a
	lsr a
	lsr a
	and #$07
	#akku16
	and #$00ff
	sta wert
	asl a
	asl a
	clc
	adc wert
	asl a
	clc
	adc #filter_namen
	sta hz
	#akku8
	lda #9
	ldy #10
	jsr schreib
	lda schatten+$42            ; Resonanz 0-15 zweistellig
	lsr a
	lsr a
	lsr a
	lsr a
	ldx #' '
	cmp #10
	bcc +
	sbc #10
	ldx #'1'
+	ora #'0'
	sta wert+1
	txa
	sta wert
	lda #30
	jsr spalte
	lda wert
	sta $0000,x
	lda wert+1
	sta $0002,x
	lda #7                      ; Eckfrequenz: ab Spalte 7, 28 Zeichen
	sta bsp
	#akku16
	lda #BALKEN-4
	sta bbr
	lda #26
	jsr zeilenadresse
	sta adr
	lda schatten+$40            ; Ecke (11 Bit) / 4 = Balken, oben gekappt
	and #$07ff
	lsr a
	lsr a
	cmp #(BALKEN-4)*8
	bcc +
	lda #(BALKEN-4)*8-1
+	#akku8
	jsr balken_hier

	#akku16                     ; Teil und Spielzeit
	lda #28
	jsr zeilenadresse
	sta adr
	lda teil
	and #$00ff
	asl a
	asl a
	sta wert
	asl a
	clc
	adc wert                    ; * 12
	clc
	adc #teil_namen
	sta hz
	#akku8
	lda #7
	ldy #12
	jsr schreib
	lda #34
	jsr spalte
	lda minu
	and #$0f
	ora #'0'
	sta $0000,x
	lda #':'
	sta $0002,x
	lda sek
	lsr a
	lsr a
	lsr a
	lsr a
	ora #'0'
	sta $0004,x
	lda sek
	and #$0f
	ora #'0'
	sta $0006,x
	rts

; adr (Namenszeile) und reg (Registerversatz) fuer den Kanal setzen
kanal_einrichten
	#akku16
	lda kanal
	and #$00ff
	tax
	and #$0003
	asl a
	asl a
	asl a
	asl a
	sta reg
	#akku8
	lda label_zeilen,x
	#akku16
	and #$00ff
	jsr zeilenadresse
	sta adr
	#akku8
	rts

leer_zeigen
	#akku16
	lda #t_leer
	sta hz
	#akku8
	rts

; A = Spalte -> X = adr + 2 * Spalte
spalte
	#akku16
	and #$00ff
	asl a
	clc
	adc adr
	tax
	#akku8
	rts

; Text ab hz schreiben: A = Spalte, Y = Laenge (nur Zeichen, keine Farbe)
schreib
	sty zz
	jsr spalte
	ldy #0
-	lda (hz),y
	sta $0000,x
	inx
	inx
	iny
	cpy zz
	bne -
	rts

; A16 = Frequenzregister -> hz = Notenname (4 Byte je Eintrag)
notenname
	.al
	ldx #0
-	cmp noten_mitte,x
	bcc +
	inx
	inx
	cpx #NOTEN_MITTEN*2
	bne -
+	txa
	asl a
	clc
	adc #noten_namen
	sta hz
	rts
	.as

; A = Panorama -> Raute in den Spalten 32-38
pan_zeigen
	#akku16
	and #$00ff
	tax
	#akku8
	lda pan_pos,x
	sta zz
	lda #32
	jsr spalte
	ldy #0
-	tya
	cmp zz
	beq +
	lda #$80
	bra ++
+	lda #$98
+	sta $0000,x
	inx
	inx
	iny
	cpy #7
	bne -
	rts

; A = Pegel (8 je Zeichen) -> Balken eine Zeile unter adr, ab Spalte bsp,
; bbr Zeichen breit
balken_zeigen
	pha
	#akku16
	lda adr
	clc
	adc #ZEILE
	sta adr
	#akku8
	pla
balken_hier
	pha
	lda bsp
	jsr spalte
	pla
	pha
	lsr a                       ; volle Zeichen: Pegel / 8
	lsr a
	lsr a
	sta zz
	ldy bbr
	lda zz
	beq +
-	lda #$b8
	sta $0000,x
	inx
	inx
	dey
	dec zz
	bne -
+	pla                         ; Rest als Achtelzeichen
	and #$07
	beq +
	ora #$b0
	sta $0000,x
	inx
	inx
	dey
+	cpy #0
	beq +
-	lda #' '
	sta $0000,x
	inx
	inx
	dey
	bne -
+	rts

;----------------------------------------------------------------------------
; Daten

alter_haken
	.word 0

bits
	.byte 1, 2, 4, 8

label_zeilen                    ; Namenszeilen der acht Kanaele
	.byte 5, 7, 9, 11, 15, 17, 19, 21

balken_zeilen                   ; Balkenzeilen und ihre erste Farbe
	.byte 6, 8, 10, 12, 16, 18, 20, 22, 26
balken_farbe
	.byte $37, $37, $37, $37, $3b, $3b, $3b, $3b, $3f
balken_schritt
	.byte 1, 1, 1, 1, 1, 1, 1, 1, 0

; MERIDIAN-Palette fuer die Anzeige: gggg bbbb, ---- rrrr
palette
	.byte $13,$1, $ff,$f, $bd,$a, $36,$3   ; Grund, weiss, grau, Spur
	.byte $c3,$f, $df,$5, $93,$f, $7f,$3   ; gold, tuerkis, orange, blau
	.byte $bf,$4, $ee,$6, $fc,$a           ; Verlauf Synthese
	.byte $d4,$f, $a3,$f, $63,$f, $36,$f   ; Verlauf Samples
	.byte $5f,$b                           ; Filter: violett

t_leer
	.text "        "
t_filter
	.text "Filter"

texte
	.word BILDSCHIRM+1*ZEILE+2
	.byte $04
	.text "ORGEL", 0
	.word BILDSCHIRM+1*ZEILE+8*2
	.byte $02
	.text "MERIDIAN 816 sound chip", 0
	.word BILDSCHIRM+4*ZEILE+2
	.byte $05
	.text "SID SOUL", 0
	.word BILDSCHIRM+4*ZEILE+12*2
	.byte $02
	.text "four synth voices", 0
	.word BILDSCHIRM+5*ZEILE+2
	.byte $01
	.text "1 Bass", 0
	.word BILDSCHIRM+7*ZEILE+2
	.byte $01
	.text "2 Chords", 0
	.word BILDSCHIRM+9*ZEILE+2
	.byte $01
	.text "3 Melody", 0
	.word BILDSCHIRM+11*ZEILE+2
	.byte $01
	.text "4 Echo", 0
	.word BILDSCHIRM+14*ZEILE+2
	.byte $06
	.text "PAULA SOUL", 0
	.word BILDSCHIRM+14*ZEILE+14*2
	.byte $02
	.text "four sample channels", 0
	.word BILDSCHIRM+15*ZEILE+2
	.byte $01
	.text "5 Chan 1", 0
	.word BILDSCHIRM+17*ZEILE+2
	.byte $01
	.text "6 Chan 2", 0
	.word BILDSCHIRM+19*ZEILE+2
	.byte $01
	.text "7 Chan 3", 0
	.word BILDSCHIRM+21*ZEILE+2
	.byte $01
	.text "8 Chan 4", 0
	.word BILDSCHIRM+25*ZEILE+2
	.byte $0f
	.text "Filter", 0
	.word BILDSCHIRM+25*ZEILE+20*2
	.byte $02
	.text "Resonance", 0
	.word BILDSCHIRM+26*ZEILE+2
	.byte $0f
	.text "Cutoff", 0           ; die Leerzeichen loeschen die Balkenspur
	.word BILDSCHIRM+28*ZEILE+2
	.byte $02
	.text "Part", 0
	.word BILDSCHIRM+28*ZEILE+29*2
	.byte $02
	.text "Time", 0
	.word BILDSCHIRM+29*ZEILE+2
	.byte $07
	.text "Any key quits", 0
	.word 0

	.include "orgel_daten.inc"

schatten                        ; zuletzt geschriebene ORGEL-Register
	.fill 256
