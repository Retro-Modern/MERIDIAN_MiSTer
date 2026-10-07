;============================================================================
;  Eingabe und Uhr fuer BASIC (Etappe 11) - wird in kern.asm eingebunden
;
;  Funktionen (Bruecke $FFBE, Nummer in A, Wert und Ergebnis 24 Bit mit
;  Vorzeichen in LZ = $00):
;   0 MOUSE(n)  0 X, 1 Y, 2 Tasten (1 links, 2 rechts, 4 Mitte), 3 Rad
;   1 JOY(n)    Joystick 1 oder 2: Bits wie PFORTE (1 rechts, 2 links,
;               4 runter, 8 hoch, 16 Feuer A, 32 B, 64 C, 128 D, ...)
;   2 KEY(c)    -1, wenn die Taste mit dem Zeichen c gedrueckt ist
;               (KEY(0): irgendeine Taste)
;   3 HIT(n)    -1, wenn Sprite n seit der letzten Frage einen anderen
;               beruehrt hat
;   4 CLOCK(n)  0 Bildzaehler (1/60 s), 1 Sekunde, 2 Minute, 3 Stunde,
;               4 Tag, 5 Monat, 6 Jahr, 7 Wochentag (0 = Sonntag)
;  Befehl 14 (ueber $FFBB): MOUSE 1[,sprite] Mauszeiger an, MOUSE 0 aus.
;
;  Nur ASCII in dieser Datei (sie wird nicht nach Latin-1 gewandelt).
;============================================================================

PFO_JOY1   = $C108
PFO_JOY2   = $C10A
PFO_MX     = $C120              ; Maus: festgehaltener Stand
PFO_MY     = $C122
PFO_MT     = $C124
PFO_MRAD   = $C125
PFO_MFEST  = $C12A              ; schreiben: Stand festhalten
PFO_UHR    = $C130              ; BCD: Sek, Min, Std, Tag, Mon, Jahr, Wtag
PFO_UHRST  = $C137              ; Bit 0 gestellt; schreiben: festhalten
KOB_KOLL   = $C404

MZ_SPRITE  = $03B8              ; Sprite des Mauszeigers ($FF: aus)
TASTEN_AN  = $033E00            ; je Taste ein Byte: 1 = gedrueckt
TREFFER    = $033F00            ; 4 Byte: Beruehrungen seit der letzten Frage
F_WERT     = $00                ; = LZ in BASIC
PFEIL_M    = 127                ; Muster des Mauszeigers

b_funktion
	#b_ein
	jsr bb_funktion
	#b_aus

bb_funktion
	.as
	#akku16
	and #$00ff
	asl a
	tax
	#akku8
	jmp (f_tabelle,x)

f_tabelle
	.word f_maus, f_joy, f_taste, f_hit, f_uhr
	.word f_netz, f_netzzeile, f_netztext   ; 5 NET(k), 6/7 NET$(k) (Etappe 12)

f_netz                          ; NET(k): Status / wartende Zeilen (ROM Bank $FF)
	.as
	lda #1
	jsl NETZ
	rts
f_netzzeile                     ; NET$(k), Teil 1: Zeile holen, Laenge -> LZ
	.as
	lda #2
	jsl NETZ
	rts
f_netztext                      ; NET$(k), Teil 2: Text nach LZ (Bank 1)
	.as
	lda #3
	jsl NETZ
	rts

f_wahr
	#akku8
	lda #$ff
	sta F_WERT
	sta F_WERT+1
	sta F_WERT+2
	rts
f_falsch
	#akku8
	stz F_WERT
	stz F_WERT+1
	stz F_WERT+2
	rts

;----------------------------------------------------------------------------
; MOUSE(n)

f_maus
	.as
	sta PFO_MFEST
	lda F_WERT
	beq _x
	cmp #1
	beq _y
	cmp #2
	beq _tasten
	cmp #3
	bne f_falsch
	lda PFO_MRAD                ; Rad mit Vorzeichen
	sta F_WERT
	bpl +
	lda #$ff
	bra ++
+	lda #0
+	sta F_WERT+1
	sta F_WERT+2
	rts
_tasten
	lda PFO_MT
	sta F_WERT
	stz F_WERT+1
	stz F_WERT+2
	rts
_x
	#akku16
	lda PFO_MX
	bra +
_y
	#akku16
	lda PFO_MY
+	sta F_WERT
	#akku8
	stz F_WERT+2
	rts

;----------------------------------------------------------------------------
; JOY(n)

f_joy
	.as
	lda F_WERT
	cmp #1
	beq _1
	cmp #2
	bne f_falsch
	#akku16
	lda PFO_JOY2
	bra +
_1
	#akku16
	lda PFO_JOY1
+	sta F_WERT
	#akku8
	stz F_WERT+2
	rts

;----------------------------------------------------------------------------
; KEY(c): sucht c in der Tastaturtabelle (ohne Umschalt) und bei den
; E0-Tasten; gedrueckt ist die Taste, wenn ihr Byte in TASTEN_AN 1 ist.
; Buchstaben gross oder klein, 28-31 Cursor, 13 Return, 32 Leertaste.

f_taste
	.as
	lda F_WERT
	bne _zeichen
	ldx #0                      ; KEY(0): irgendeine Taste
-	lda @l TASTEN_AN,x
	bne f_wahr
	inx
	cpx #256
	bne -
	bra f_falsch
_zeichen
	cmp #'A'
	bcc +
	cmp #'Z'+1
	bcs +
	ora #$20
+	sta hilf
	ldx #0
_normal
	lda tab_normal,x
	cmp hilf
	bne +
	lda @l TASTEN_AN,x          ; Index = Scancode
	bne f_wahr
+	inx
	cpx #128
	bne _normal
	ldy #0
_e0
	lda e0_tab,y
	beq f_falsch
	lda e0_tab+1,y
	cmp hilf
	bne +
	#akku16
	lda e0_tab,y
	and #$007f
	ora #$0080                  ; Index = 128 + Code
	tax
	#akku8
	lda @l TASTEN_AN,x
	bne f_wahr
+	iny
	iny
	bra _e0

; vom Tastaturtreiber fuer jedes Ereignis: Byte E0 * 128 + (Code & 127)
taste_merken
	.as
	lda ev_code
	and #$7f
	sta hilf
	lda ev_info
	and #$02
	beq +
	lda #$80
	tsb hilf
+	#akku16
	lda hilf
	and #$00ff
	tax
	#akku8
	lda ev_info
	and #$01
	eor #$01                    ; 1 = gedrueckt, 0 = losgelassen
	sta @l TASTEN_AN,x
	rts

;----------------------------------------------------------------------------
; HIT(n): KOBOLD meldet Beruehrungen, bis man sie loescht; der Kern sammelt
; sie in TREFFER, die Frage nach Sprite n loescht nur dessen Bit.

f_hit
	.as
	ldx #0
-	lda KOB_KOLL,x
	ora @l TREFFER,x
	sta @l TREFFER,x
	inx
	cpx #4
	bne -
	sta KOB_KOLL                ; KOBOLD: alle loeschen
	lda F_WERT+1
	ora F_WERT+2
	bne _nein
	lda F_WERT
	cmp #32
	bcs _nein
	pha
	lsr a
	lsr a
	lsr a
	#akku16
	and #$0003
	tax                         ; Byte
	#akku8
	pla
	#akku16
	and #$0007
	tay                         ; Bit
	#akku8
	lda bitmasken,y
	sta hilf
	lda @l TREFFER,x
	and hilf
	beq _nein
	lda hilf
	eor #$ff
	and @l TREFFER,x
	sta @l TREFFER,x
	jmp f_wahr
_nein
	jmp f_falsch

treffer_leeren
	.as
	lda #0
	sta @l TREFFER
	sta @l TREFFER+1
	sta @l TREFFER+2
	sta @l TREFFER+3
	sta KOB_KOLL
	rts

bitmasken
	.byte 1, 2, 4, 8, 16, 32, 64, 128

;----------------------------------------------------------------------------
; CLOCK(n)

f_uhr
	.as
	lda F_WERT+1
	ora F_WERT+2
	bne _nein
	lda F_WERT
	bne _uhr
	php                         ; Bildzaehler (der Interrupt zaehlt ihn)
	sei
	lda bilder
	sta F_WERT
	lda bilder+1
	sta F_WERT+1
	lda bilder+2
	sta F_WERT+2
	plp
	rts
_uhr
	cmp #8
	bcs _nein
	sta PFO_UHRST               ; Stand festhalten
	#akku16
	and #$00ff
	tax
	#akku8
	lda PFO_UHR-1,x
	cpx #7                      ; Wochentag ist binaer
	beq +
	jsr bcd_binaer
+	sta F_WERT
	stz F_WERT+1
	stz F_WERT+2
	cpx #6                      ; Jahr: zweistellig ab 2000
	bne +
	#akku16
	lda F_WERT
	clc
	adc #2000
	sta F_WERT
	#akku8
+	rts
_nein
	jmp f_falsch

bcd_binaer                      ; A (BCD) -> A binaer
	.as
	pha
	lsr a
	lsr a
	lsr a
	lsr a
	sta hilf
	asl a
	asl a
	clc
	adc hilf                    ; Zehner * 5
	asl a                       ; * 10
	sta hilf
	pla
	and #$0f
	clc
	adc hilf
	rts

;----------------------------------------------------------------------------
; Mauszeiger: MOUSE 1[,sprite] / MOUSE 0. Der Interrupt setzt den Sprite in
; jedem Bild auf die Mausposition (Spitze des Pfeils = Position).

maus_befehl
	.as
	lda P_ANZ
	beq _f
	lda P_WERT
	beq _aus
	lda P_ANZ
	cmp #2
	lda #0                      ; Vorgabe: Sprite 0 (liegt vorn)
	bcc +
	lda P_WERT+3
	cmp #32
	bcs _f
+	pha
	jsr _aus                    ; einen alten Zeiger zuerst weg
	pla
	sta MZ_SPRITE
	jsr sprites_an
	jsr pfeil_laden
	lda MZ_SPRITE
	#akku16
	and #$001f
	asl a
	asl a
	asl a
	tax
	#akku8
	lda #PFEIL_M
	sta KOB_TAB+4,x
	stz KOB_TAB+5,x
	lda #1
	sta KOB_TAB+6,x
	jsr maus_zeiger
	jmp b_gut
_aus
	lda MZ_SPRITE
	bmi +
	#akku16
	and #$001f
	asl a
	asl a
	asl a
	tax
	#akku8
	stz KOB_TAB+6,x
	lda #$ff
	sta MZ_SPRITE
+	jmp b_gut
_f
	jmp b_fehler

maus_zeiger                     ; aus dem Interrupt (und beim Einschalten)
	.as
	lda MZ_SPRITE
	bmi _ende
	sta PFO_MFEST
	#akku16
	and #$001f
	asl a
	asl a
	asl a
	tax
	lda PFO_MX
	clc
	adc #32
	sta KOB_TAB+0,x
	lda PFO_MY
	clc
	adc #32
	sta KOB_TAB+2,x
	#akku8
_ende
	rts

sprites_an                      ; beim ersten Sprite: Tabelle leeren, KOBOLD an
	.as
	lda SP_AN
	bne _ende
	phx
	ldx #0
-	stz KOB_TAB+4,x             ; Muster, Bank/Groesse und an: nichts von
	stz KOB_TAB+5,x             ; einem vorigen Programm erben (SPRITE ohne
	stz KOB_TAB+6,x             ; f behielt sonst z. B. dessen Bank)
	#akku16
	txa
	clc
	adc #8
	tax
	#akku8
	cpx #32*8
	bne -
	plx
	lda #1
	sta SP_AN
	sta KOB_STEUER
	jsr treffer_leeren
_ende
	rts

pfeil_laden                     ; Muster 127: Umriss dunkelgrau, Fuellung weiss
	.as
	#akku16
	lda #PFEIL_M*128
	sta KOB_MADR
	#akku8
	ldy #0
_byte
	lda pfeil,y                 ; 4 Pixel zu je 2 Bit
	sta hilf
	ldx #2                      ; ergibt 2 Musterbytes zu je 2 Pixeln
_paar
	jsr _farbe
	asl a
	asl a
	asl a
	asl a
	sta hilf+1
	jsr _farbe
	ora hilf+1
	sta KOB_MDATEN
	dex
	bne _paar
	iny
	cpy #64
	bne _byte
	rts
_farbe                          ; obere 2 Bit von hilf -> Farbwert
	lda #0
	asl hilf
	rol a
	asl hilf
	rol a
	beq +
	cmp #1
	beq _umriss
	lda #1                      ; Fuellung: weiss
	rts
_umriss
	lda #11                     ; Umriss: dunkelgrau
+	rts

pfeil                           ; 16 x 16, 2 Bit je Pixel (1 Umriss, 2 Fuellung)
	.byte $40, $00, $00, $00
	.byte $50, $00, $00, $00
	.byte $64, $00, $00, $00
	.byte $69, $00, $00, $00
	.byte $6a, $40, $00, $00
	.byte $6a, $90, $00, $00
	.byte $6a, $a4, $00, $00
	.byte $6a, $a9, $00, $00
	.byte $6a, $aa, $40, $00
	.byte $6a, $95, $40, $00
	.byte $69, $a4, $00, $00
	.byte $64, $69, $00, $00
	.byte $50, $69, $00, $00
	.byte $40, $1a, $40, $00
	.byte $00, $1a, $40, $00
	.byte $00, $05, $00, $00
