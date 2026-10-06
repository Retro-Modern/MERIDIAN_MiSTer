;============================================================================
;  BALLETT - Vorfuehrprogramm fuer Copper LOTSE und Blitter KRAN (Etappe 7)
;
;  Oben 176 Zeilen Bitmap mit 256 Farben: KRAN loescht sie in jedem Bild und
;  zeichnet viele Baelle hinein ("Bobs"), alles aus einer Auftragsliste, die
;  er allein abarbeitet. Doppelpuffer in den Baenken 2 und 3.
;  LOTSE setzt in jeder Zeile die Hintergrundfarbe (Himmel, unten
;  Rasterbalken), laesst das MERIDIAN-Logo auf der Kachelebene wellen (im
;  Takt der Kick) und schaltet ab Zeile 176 auf Text um. Den Pufferwechsel
;  macht er gleich mit: Jeder Puffer hat seine eigene Copper-Liste.
;  Die Zahl der Baelle steigt, bis KRAN gut 13 ms je Bild braucht.
;  Dazu laeuft die Musik aus Etappe 6 (Timer A, 50 Hz).
;
;  Speicher: Programm $2000, Musik $00:4000, Samples $01:0000, Grafik
;  $01:C000 (Baelle, Logo-Kacheln, Karte). Bank 2/3: Bild $0000-$DBFF,
;  Copper-Liste ab $DC00, KRAN-Auftragsliste ab $EF00.
;
;  Daten vorher laden: programme/daten/orgel_klaenge.mer, ballett_musik.mer,
;  ballett_grafik.mer
;  Assemblieren: programme/bauen.sh ballett
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
CUR_X        = $10
CUR_Y        = $11
BILDER       = $50

PIN_A_TYP  = $C000
PIN_A_DATEN = $C002
PIN_A_MUSTER = $C005
PIN_PIDX   = $C008
PIN_PLO    = $C009
PIN_PHI    = $C00A
PIN_B_TYP  = $C020
PIN_B_OPT  = $C021
PIN_B_DATEN = $C022
PIN_B_MUSTER = $C025
PIN_B_SX   = $C030
PIN_B_SY   = $C032
PFO_IRQST  = $C104
PFO_IRQEN  = $C105
PFO_UHR    = $C110
PFO_TA     = $C114
PFO_TASTEU = $C116
ORG        = $C500
KRAN       = $C600
KRAN_BEF   = $C610
KRAN_LISTE = $C611
LOT_LISTE  = $C700
LOT_STEUER = $C703
LOT_BEFEHLE = $C705

MUSIK      = $004000
KOPPER     = $DC00              ; Copper-Liste in Bank 2/3
KRANL      = $EF00              ; KRAN-Auftragsliste in Bank 2/3
ZEILE      = 80                 ; Bytes je Textzeile
LOGO_OBEN  = 8                  ; Logo: Zeilen 8-39
GRENZE     = 13000              ; us KRAN-Zeit, bis zu der Baelle dazukommen

; Direkte Seite (der Kern belegt $10-$54)
strom    = $80                  ; 3 Byte: Musikstrom
schleife = $84                  ; 3 Byte
teil     = $87
t50      = $88
sek      = $89
minu     = $8A
letztes  = $8B
p        = $8C                  ; Puffer, in den gezeichnet wird (0/1)
pbank    = $8D                  ; dessen Bank (2/3)
kz       = $8E                  ; 3 Byte: Zeiger auf Copper-Liste
kl       = $92                  ; 3 Byte: Zeiger auf KRAN-Liste
anzahl   = $96                  ; 16 Bit: Baelle
bx       = $98                  ; 16 Bit
by       = $9A                  ; 16 Bit
tmp      = $9C                  ; 16 Bit
zz       = $9E                  ; 16 Bit
pha_x    = $A0
pha_y    = $A1
pha_w    = $A2                  ; Welle
pha_b    = $A3                  ; Rasterbalken
wackel   = $A4                  ; Bilder seit der letzten Kick
kzeit    = $A6                  ; 16 Bit: KRAN-Zeit in us
t0       = $A8                  ; 16 Bit
runden   = $AA                  ; Bilder seit dem letzten Anpassen
bps      = $AB                  ; Bilder je Sekunde (gezaehlt)
bps_z    = $AC
sek_alt  = $AD
ziffern  = $AE                  ; 10 Byte (Ziffern an geraden Stellen)

	* = $2000

start
	.as
	.xl
	phb
	sei
	stz kz+2                    ; 16-Bit-Zugriffe auf DP-Zaehler: Hochbytes 0
	stz anzahl+1
	jsr bild_einrichten
	lda #39                     ; Cursor in eine Ecke mit Farbe 0
	sta CUR_X
	lda #29
	sta CUR_Y

	lda #2                      ; beide Listen bauen
	jsr listen_bauen
	lda #3
	jsr listen_bauen

	lda #16
	sta anzahl
	stz pha_x
	stz pha_y
	stz pha_w
	stz pha_b
	lda #20
	sta wackel
	stz runden
	stz bps
	stz bps_z
	#akku16
	stz kzeit
	#akku8

	#akku16                     ; Puffer 0 loeschen, LOTSE zeigt ihn
	lda #KRANL
	sta kl
	#akku8
	lda #2
	sta kl+2
	jsr loeschen_direkt
	lda #<KOPPER
	sta LOT_LISTE
	lda #>KOPPER
	sta LOT_LISTE+1
	lda #2
	sta LOT_LISTE+2
	lda #$01
	sta LOT_STEUER
	lda #1                      ; gezeichnet wird zuerst in Puffer 1
	sta p
	lda #3
	sta pbank

	#akku16                     ; Musik: Kopf = Schleifenadresse
	lda MUSIK
	sta schleife
	lda #(MUSIK + 3) & $ffff
	sta strom
	lda BENUTZER_IRQ            ; Interrupt-Haken
	sta alter_haken
	lda #haken
	sta BENUTZER_IRQ
	#akku8
	lda MUSIK+2
	sta schleife+2
	lda #`MUSIK
	sta strom+2
	stz teil
	stz t50
	stz sek
	stz minu
	stz sek_alt
	lda #<19999                 ; Timer A: 50 Hz
	sta PFO_TA
	lda #>19999
	sta PFO_TA+1
	lda #$01
	sta PFO_TASTEU
	lda #$02
	sta PFO_IRQEN
	lda BILDER
	sta letztes
	cli

haupt
	jsr bild_abwarten
	jsr baelle_setzen           ; Auftragsliste fuer den Zeichenpuffer
	stz PFO_UHR                 ; KRAN los, Zeit messen
	#akku16
	lda PFO_UHR
	sta t0
	#akku8
	lda #<KRANL
	sta KRAN_LISTE
	lda #>KRANL
	sta KRAN_LISTE+1
	lda pbank
	sta KRAN_LISTE+2
	lda #$02
	sta KRAN_BEF
	jsr copper_bewegen          ; waehrenddessen: Welle und Balken
	jsr anzeigen
-	lda KRAN_BEF                ; warten, bis KRAN fertig ist
	and #$01
	bne -
	stz PFO_UHR
	#akku16
	lda PFO_UHR
	sec
	sbc t0
	sta kzeit
	#akku8
	jsr letzter_zurueck
	lda #<KOPPER                ; diesen Puffer ab dem naechsten Bild zeigen
	sta LOT_LISTE
	lda #>KOPPER
	sta LOT_LISTE+1
	lda pbank
	sta LOT_LISTE+2
	lda BILDER                  ; erst nach dem naechsten Bildwechsel weiter
	sta letztes
	lda p                       ; Puffer tauschen
	eor #$01
	sta p
	ora #$02
	sta pbank
	inc bps_z
	jsr mehr_baelle
	jsr GETIN
	bne ende
	jmp haupt

ende
	sei
	stz PFO_TASTEU
	stz PFO_IRQEN
	lda #$06
	sta PFO_IRQST
	stz LOT_STEUER
	lda #$0c
	sta KRAN_BEF
	stz PIN_B_TYP
	#akku16
	lda alter_haken
	sta BENUTZER_IRQ
	#akku8
	jsr ORGEL_STILL
	jsr LOESCHEN
	cli
	plb
	rtl

; bis zum naechsten Bildwechsel warten
bild_abwarten
-	lda BILDER
	cmp letztes
	beq -
	sta letztes
	rts

;----------------------------------------------------------------------------
; Interrupt: Timer A -> ein Takt Musik

haken
	.as
	lda PFO_IRQST
	and #$02
	beq +
	sta PFO_IRQST
	jsr spieler
	jsr uhr
+	lda #$02                    ; Raster quittieren (nicht benutzt)
	sta $c00c
	rts

spieler
	lda [strom]
	jsr weiter
	cmp #$fd
	bcs _marke
	#akku16
	and #$00ff
	tax
	#akku8
	lda [strom]
	jsr weiter
	sta ORG,x
	bra spieler
_marke
	beq _teil
	cmp #$fe
	beq _schleife
	rts
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

weiter
	#akku16
	inc strom
	#akku8
	bne +
	inc strom+2
+	rts

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
; Einrichten: Palette, Ebenen, Statustexte

bild_einrichten
	stz PIN_PIDX
	ldx #0
-	lda palette,x
	sta PIN_PLO
	lda palette+1,x
	sta PIN_PHI
	inx
	inx
	cpx #96*2
	bne -
	lda #2                      ; Ebene B: Kacheln mit dem Logo
	sta PIN_B_TYP
	stz PIN_B_OPT
	stz PIN_B_DATEN
	lda #$e0
	sta PIN_B_DATEN+1
	lda #$01
	sta PIN_B_DATEN+2
	stz PIN_B_MUSTER
	lda #$c4
	sta PIN_B_MUSTER+1
	lda #$01
	sta PIN_B_MUSTER+2
	lda #64
	sta PIN_B_SX
	stz PIN_B_SX+1
	stz PIN_B_SY
	ldx #0                      ; Textzeilen 22-29 leeren, Grund Farbe 0
-	lda #' '
	sta BILDSCHIRM+22*ZEILE,x
	lda #$02
	sta BILDSCHIRM+22*ZEILE+1,x
	inx
	inx
	cpx #8*ZEILE
	bne -
	ldx #texte                  ; feste Texte: Adresse, Farbe, Text, 0
_text
	#akku16
	lda $0000,x
	beq _fertig
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
_fertig
	#akku8
	ldx #1*2                    ; Lastbalken: Farbverlauf gruen -> rot
-	txa
	lsr a
	lsr a
	lsr a
	lsr a
	clc
	adc #10
	sta BILDSCHIRM+26*ZEILE+1,x
	inx
	inx
	cpx #33*2
	bne -
	stz BILDSCHIRM+29*ZEILE+39*2+1
	rts

;----------------------------------------------------------------------------
; Copper- und KRAN-Liste fuer den Puffer in Bank A bauen

listen_bauen
	sta pbank
	sta kz+2
	sta kl+2
	#akku16
	lda #KOPPER
	sta kz
	lda #KRANL
	sta kl
	#akku8
	ldy #0
	; Kopf (beim Bildwechsel): Ebene A = Bitmap 256 in diesem Puffer
	lda #$00
	ldx #4
	jsr setze
	lda #$02
	ldx #0
	jsr setze
	lda #$03
	ldx #0
	jsr setze
	lda #$04
	ldx pbank
	jsr setze
	#akku16
	stz zz
	#akku8
_zeile
	lda #$01                    ; WARTE zz (Zeilenanfang)
	sta [kz],y
	iny
	lda zz
	sta [kz],y
	iny
	lda zz+1
	ora #$02
	sta [kz],y
	iny
	lda #$ff
	sta [kz],y
	iny
	lda #$08                    ; Farbe 0 waehlen
	ldx #0
	jsr setze
	#akku16                     ; Himmel bzw. Grund
	lda zz
	cmp #HOEHE
	bcs +
	asl a
	tax
	lda himmel,x
	bra ++
+	lda raster_grund
+	sta tmp
	#akku8
	lda #$09
	ldx tmp
	jsr setze
	lda #$0a
	ldx tmp+1
	jsr setze
	#akku16                     ; Logo-Zeilen: Scrolling der Ebene B
	lda zz
	cmp #LOGO_OBEN-1
	bcc +
	cmp #LOGO_OBEN+31
	bcs +
	#akku8
	lda #$30
	ldx #64
	jsr setze
	bra ++
+	#akku8
	lda #$01                    ; sonst ein leerer Befehl: dasselbe WARTE
	sta [kz],y                  ; (Zeilenanfang) noch einmal - bis 06.10.2026
	iny                         ; stand hier $06, seitdem ist das FARBE
	lda zz
	sta [kz],y
	iny
	lda zz+1
	ora #$02
	sta [kz],y
	iny
	lda #$ff
	sta [kz],y
	iny
+	#akku16
	lda zz
	cmp #HOEHE-1
	bne +
	#akku8                      ; vor Zeile 176: Ebene A = Text
	lda #$00
	ldx #1
	jsr setze
	lda #$02
	ldx #$00
	jsr setze
	lda #$03
	ldx #$04
	jsr setze
	lda #$04
	ldx #0
	jsr setze
+	#akku16
	inc zz
	lda zz
	cmp #240
	#akku8
	beq +
	jmp _zeile
+	lda #$00                    ; ENDE
	sta [kz],y
	iny
	sta [kz],y
	iny
	sta [kz],y
	iny
	sta [kz],y

	; KRAN-Liste: Auftrag 0 loescht, 1-255 sind Baelle
	ldy #0
	ldx #0
-	lda auftrag_loeschen,x
	sta [kl],y
	iny
	inx
	cpx #16
	bne -
	lda pbank
	ldy #5
	sta [kl],y
	ldy #16
	stz zz                      ; Ballnummer
_ball
	lda #0                      ; QUELLE: $01:C000 + (n & 3) * 256
	sta [kl],y
	iny
	lda zz
	and #$03
	ora #$c0
	sta [kl],y
	iny
	lda #$01
	sta [kl],y
	iny
	ldx #0
-	lda auftrag_ball,x          ; Rest: ZIEL (Bank), Groesse, Abstaende, Modus
	sta [kl],y
	iny
	inx
	cpx #13
	bne -
	dey                         ; Bank des Ziels eintragen
	dey
	dey
	dey
	dey
	dey
	dey
	dey
	dey
	dey
	dey
	lda pbank
	sta [kl],y
	#akku16
	tya
	clc
	adc #11
	tay
	#akku8
	inc zz
	lda zz
	cmp #255
	bne _ball
	rts

; SETZE: Register $C0(A) auf X (unteres Byte), an [kz],y anhaengen
setze
	pha
	lda #$02
	sta [kz],y
	iny
	pla
	sta [kz],y
	iny
	lda #$c0
	sta [kz],y
	iny
	txa
	sta [kz],y
	iny
	rts

; Puffer in Bank kl+2 direkt loeschen (Auftrag aus den Registern)
loeschen_direkt
	ldx #0
-	lda auftrag_loeschen,x
	sta KRAN,x
	inx
	cpx #16
	bne -
	lda kl+2
	sta KRAN+5
	lda #$01
	sta KRAN_BEF
-	lda KRAN_BEF
	and #$01
	bne -
	rts

;----------------------------------------------------------------------------
; Jedes Bild

; Ziele der Baelle in die Auftragsliste des Zeichenpuffers schreiben
baelle_setzen
	lda pbank
	sta kl+2
	#akku16
	lda #KRANL
	sta kl
	#akku8
	inc pha_x
	inc pha_y
	inc pha_y
	#akku16
	lda pha_x
	and #$00ff
	sta bx
	lda pha_y
	and #$00ff
	sta by
	ldy #16+3                   ; Auftrag 1, ZIEL
	ldx anzahl
_b	phx
	lda bx
	asl a
	tax
	lda bahn_x,x
	sta tmp
	lda by
	asl a
	tax
	lda bahn_y,x
	clc
	adc tmp
	sta [kl],y                  ; ZIEL unten und Mitte
	tya
	clc
	adc #16
	tay
	lda bx
	clc
	adc #7
	and #$00ff
	sta bx
	lda by
	clc
	adc #11
	and #$00ff
	sta by
	plx
	dex
	bne _b
	jsr letzter_adresse         ; Auftrag "anzahl" ist der letzte
	#akku8
	lda #$82
	sta [kl],y
	rts

letzter_zurueck
	jsr letzter_adresse
	#akku8
	lda #$02
	sta [kl],y
	rts

letzter_adresse                 ; Y = anzahl * 16 + 15
	#akku16
	lda anzahl
	asl a
	asl a
	asl a
	asl a
	clc
	adc #15
	tay
	rts
	.as

; Alle 32 Bilder: noch acht Baelle, solange KRAN unter der Grenze bleibt
mehr_baelle
	inc runden
	lda runden
	cmp #32
	bcc +
	stz runden
	#akku16
	lda kzeit
	cmp #GRENZE
	bcs ++
	lda anzahl
	clc
	adc #8
	cmp #256
	bcs ++
	sta anzahl
+	#akku8
	rts
+	#akku8
	rts

; Welle des Logos und Rasterbalken in die Copper-Liste des Zeichenpuffers
copper_bewegen
	lda pbank
	sta kz+2
	#akku16
	lda #KOPPER
	sta kz
	#akku8
	lda ORG+$8b                 ; Kick gerade angeschlagen?
	and #$01
	beq +
	lda ORG+$8d
	cmp #2
	bcs +
	stz wackel
+	lda wackel
	cmp #20
	bcs +
	inc wackel
+	inc pha_w
	inc pha_w
	inc pha_w
	; Welle: Wert fuer Logozeile L steht im Eintrag der Zeile L-1
	ldy #16+(LOGO_OBEN-1)*20+19
	ldx #0
_w	txa
	asl a
	asl a
	asl a
	clc
	adc pha_w
	#akku16
	and #$00ff
	phx
	tax
	#akku8
	lda sin_welle,x
	plx
	jsr daempfen
	clc
	adc #64
	sta [kz],y
	#akku16
	tya
	clc
	adc #20
	tay
	#akku8
	inx
	cpx #32
	bne _w

	; Rasterbalken: 64 Zeilen Grund, drei Balken darueber
	ldx #0
-	lda raster_grund
	sta farben,x
	lda raster_grund+1
	sta farben+1,x
	inx
	inx
	cpx #128
	bne -
	inc pha_b
	lda pha_b
	asl a
	jsr balken_pos
	ldy #balken0
	jsr balken_malen
	lda pha_b
	asl a
	clc
	adc pha_b
	adc #85
	jsr balken_pos
	ldy #balken1
	jsr balken_malen
	lda pha_b
	asl a
	asl a
	adc #170
	jsr balken_pos
	ldy #balken2
	jsr balken_malen
	ldy #16+176*20+16+11        ; Zeile 176: PLO-Wert
	ldx #0
-	lda farben,x
	sta [kz],y
	iny
	iny
	iny
	iny
	lda farben+1,x
	sta [kz],y
	#akku16
	tya
	clc
	adc #16
	tay
	#akku8
	inx
	inx
	cpx #128
	bne -
	rts

; Wellenausschlag: frisch nach der Kick gross, dann kleiner
daempfen
	pha
	lda wackel
	cmp #3
	bcc _halb
	cmp #10
	bcc _viertel
	pla                         ; sonst ein Achtel
	cmp #$80
	ror a
	cmp #$80
	ror a
	cmp #$80
	ror a
	rts
_viertel
	pla
	cmp #$80
	ror a
	cmp #$80
	ror a
	rts
_halb
	pla
	cmp #$80
	ror a
	rts

balken_pos                      ; A = Phase -> X = Zeile * 2 (0..106)
	#akku16
	and #$00ff
	tax
	#akku8
	lda sin_balken,x
	#akku16
	and #$00ff
	asl a
	tax
	#akku8
	rts

balken_malen                    ; X = Startzeile * 2, Y = Farbtabelle (11 Eintraege)
	lda #11
	sta zz
-	lda $0000,y
	sta farben,x
	lda $0001,y
	sta farben+1,x
	inx
	inx
	iny
	iny
	dec zz
	bne -
	rts

;----------------------------------------------------------------------------
; Statuszeilen

anzeigen
	ldx #BILDSCHIRM+25*ZEILE+8*2        ; Baelle
	#akku16
	lda anzahl
	jsr zahl3
	#akku16                             ; KRAN-Zeit in ms mit einer Stelle
	lda kzeit
	ldx #0
-	cmp #100
	bcc +
	sbc #100
	inx
	bra -
+	txa
	#akku8
	ldx #BILDSCHIRM+25*ZEILE+19*2
	jsr zehntel
	#akku16                             ; Lastbalken: kzeit / 64
	lda kzeit
	lsr a
	lsr a
	lsr a
	lsr a
	lsr a
	lsr a
	cmp #256
	bcc +
	lda #255
+	#akku8
	jsr lastbalken
	#akku16                             ; LOTSE: Befehle je Bild
	lda LOT_BEFEHLE
	ldx #BILDSCHIRM+27*ZEILE+8*2
	jsr zahl4
	lda sek                             ; Bilder je Sekunde
	cmp sek_alt
	beq +
	sta sek_alt
	lda bps_z
	sta bps
	stz bps_z
+	#akku16
	lda bps
	and #$00ff
	ldx #BILDSCHIRM+27*ZEILE+36*2
	jsr zahl3
	lda teil                            ; Musik: Teil
	#akku16
	and #$00ff
	asl a
	asl a
	sta tmp
	asl a
	clc
	adc tmp
	clc
	adc #teil_namen
	tax
	#akku8
	ldy #BILDSCHIRM+28*ZEILE+8*2
	lda #12
	sta zz
-	lda $0000,x
	sta $0000,y
	inx
	iny
	iny
	dec zz
	bne -
	rts

; A16 = Zahl -> drei Stellen ab X (rechtsbuendig, fuehrende Leerzeichen)
zahl3
	.al
	jsr zerlegen
	#akku8
	ldy #2
	bra zahl_schreiben
zahl4
	.al
	jsr zerlegen
	#akku8
	ldy #1
zahl_schreiben
	.as
	lda #' '
	sta tmp                     ; Fuellzeichen bis zur ersten Ziffer
-	lda ziffern,y
	cpy #4
	beq +
	cmp #0
	bne +
	lda tmp
	bra ++
+	ora #'0'
	pha
	lda #'0'
	sta tmp
	pla
+	sta $0000,x
	inx
	inx
	iny
	cpy #5
	bne -
	rts

; A16 -> ziffern[0..4] (Zehntausender bis Einer); X bleibt erhalten
zerlegen
	.al
	phx
	ldx #0
_stelle
	sep #$20
	.as
	stz ziffern,x
	rep #$20
	.al
-	cmp zehner,x
	bcc +
	sbc zehner,x
	sep #$20
	.as
	inc ziffern,x
	rep #$20
	.al
	bra -
+	inx
	inx
	cpx #10
	bne _stelle
	; ziffern stehen jetzt an geraden Stellen 0,2,4,6,8 -> zusammenschieben
	sep #$20
	.as
	lda ziffern+2
	sta ziffern+1
	lda ziffern+4
	sta ziffern+2
	lda ziffern+6
	sta ziffern+3
	lda ziffern+8
	sta ziffern+4
	rep #$20
	.al
	plx
	rts
	.as

; A8 = Zehntel (0-255) -> "12,3" ab X
zehntel
	#akku16
	and #$00ff
	jsr zerlegen
	#akku8
	lda ziffern+2
	beq +
	ora #'0'
	bra ++
+	lda #' '
+	sta $0000,x
	lda ziffern+3
	ora #'0'
	sta $0002,x
	lda #'.'
	sta $0004,x
	lda ziffern+4
	ora #'0'
	sta $0006,x
	rts

; A = Pegel (8 je Zeichen) -> Lastbalken Zeile 26, Spalten 1-32
lastbalken
	pha
	ldx #BILDSCHIRM+26*ZEILE+1*2
	lsr a
	lsr a
	lsr a
	sta zz
	ldy #32
	lda zz
	beq +
-	lda #$b8
	sta $0000,x
	inx
	inx
	dey
	dec zz
	bne -
+	pla
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
zehner
	.word 10000, 1000, 100, 10, 1
farben                          ; Rasterbalken: 64 Zeilen lo, hi
	.fill 128

;                QUELLE   ZIEL     BREITE      HOEHE      QABST  ZABST       WERT MODUS
auftrag_loeschen
	.byte 0,0,0,  0,0,0,  <320,>320,  176,0,     0,0,   <320,>320,  0,   1
auftrag_ball                    ; ab ZIEL (13 Byte)
	.byte         0,0,0,  16,0,       16,0,      16,0,  <320,>320,  0,   2

teil_namen
	.text "Intro       "
	.text "Verse       "
	.text "Chorus      "
	.text "Filter sweep"
	.text "Finale      "

texte
	.word BILDSCHIRM+23*ZEILE+1*2
	.byte $03
	.text "BALLETT", 0
	.word BILDSCHIRM+23*ZEILE+10*2
	.byte $02
	.text "Copper LOTSE + Blitter KRAN", 0
	.word BILDSCHIRM+25*ZEILE+1*2
	.byte $04
	.text "Balls", 0
	.word BILDSCHIRM+25*ZEILE+13*2
	.byte $05
	.text "KRAN", 0
	.word BILDSCHIRM+25*ZEILE+24*2
	.byte $02
	.text "ms/frame", 0
	.word BILDSCHIRM+27*ZEILE+1*2
	.byte $07
	.text "LOTSE", 0
	.word BILDSCHIRM+27*ZEILE+13*2
	.byte $02
	.text "commands/frame", 0
	.word BILDSCHIRM+27*ZEILE+30*2
	.byte $06
	.text "fps", 0
	.word BILDSCHIRM+28*ZEILE+1*2
	.byte $09
	.text "Music", 0
	.word BILDSCHIRM+29*ZEILE+1*2
	.byte $08
	.text "Any key quits", 0
	.word 0

	.include "ballett_daten.inc"
