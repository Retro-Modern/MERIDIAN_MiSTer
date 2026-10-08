;============================================================================
;  WERKSTATT - die Werkzeuge am Geraet (MERIDIAN 1.0, Schritt 3)
;
;  Wie beim Pico-8: Aus der BASIC-Eingabe oeffnen F1-F6 die Werkzeuge
;  (SPRITES, TILES, MAP, SOUNDS, LOOK, FONT), F10 oder Esc fuehrt zurueck.
;  Das BASIC-Programm bleibt stehen; Schirm, Chips und geliehener Speicher
;  sind danach wie vorher. Oberflaeche englisch (wie BASIC).
;
;  ROM-Block Bank $FF ab $C000 (16 KB). Einsprung $FF:C000 per JSL aus dem
;  Kern (zeile_lesen), Akku 8 / Index 16 Bit, DBR 0, D 0, A = Reiter 0-5.
;
;  Geliehen, vorher gerettet und danach zurueck:
;    $02:0000-$03:2BFF  Ebene B, Bitmap 256 (die Flaeche von GRAPHIC)
;    $00:0400-$00:16BF  der Textschirm (80 Zeichen)
;    $00:A000-$00:AFFF  Arbeitsspeicher der Werkstatt (direkte Seite $A000)
;  Ablage im Zusatzspeicher: $F9:0000 Bitmap, $FA:4000 Text, $FA:5400
;  Bank 0, $FA:6400 Register. Die Cartridge (Muster, spaeter Kacheln, Karte,
;  Klaenge, Look, Font) liegt ab $F8:0000.
;============================================================================

	.cpu "65816"
	.include "kern_sym.inc"

akku8	.macro
	sep #$20
	.as
	.endm
akku16	.macro
	rep #$20
	.al
	.endm

; Kern-Aufruf (lange Einspruenge erwarten die direkte Seite 0)
kern	.macro ziel
	phd
	pea 0
	pld
	jsl \ziel
	pld
	.endm

; Text: Zeile, Spalte, Farbe (vorn + 16 * hinten), Text (0-terminiert)
text	.macro zeile, spalte, farbe, adr
	ldx #(\zeile) * 160 + (\spalte) * 2
	#akku16
	lda #<>(\adr)
	ldy #`(\adr)
	jsr w_text_xy
	.as
	lda #\farbe
	jsr w_text
	.endm

; Chips
PIN       = $C000
PIN_A_TYP = $C000
PIN_A_OPT = $C001
PIN_A_DAT = $C002
PIN_A_MUS = $C005
PIN_A_SX  = $C010
PIN_A_SY  = $C012
PIN_B_TYP = $C020
PIN_B_OPT = $C021
PIN_B_DAT = $C022
PIN_TUSCHE = $C034
PIN_GL_AN = $C04D
PIN_LEUCHT = $C052
KOB_TAB   = $C300
KOB_STEU  = $C403
KRAN_REG  = $C600
KRAN_BEF  = $C610
LOT_LISTE = $C700
LOT_STEU  = $C703
PFO_MX    = $C120
PFO_MY    = $C122
PFO_MT    = $C124
PFO_MFEST = $C12A
TASTEN_AN = $033E00
P_ANZ     = $039F               ; Werte fuer Kern-Befehle (wie aus BASIC)
P_WERT    = $03A0
MZ_SPRITE = $03B8
SP_AN     = $03BC

; Speicher
SCHIRM    = $0400               ; Textschirm 80 x 30 (Zeichen, Farbe)
ZEICHEN   = $1800               ; Zeichensatz des Rechners (BASIC LOOK)
W_FONT    = W_RAM+$800          ; die Werkstatt schreibt mit dem des ROM
BILD      = $020000             ; Ebene B: Bitmap 256
W_RAM     = $A000
AB_BILD   = $F90000             ; Ablage
AB_TEXT   = $FA4000
AB_RAM    = $FA5400
AB_REG    = $FA6400
KART      = $F80000             ; Cartridge
KART_MUSTER = KART              ; 128 Spritemuster (16 KB)
KART_STAND = KART+$4100         ; Stand der Werkzeuge ($A080-$A0FF) zwischen zwei Besuchen

; Farben der Oberflaeche (MERIDIAN-16; Text: vorn + 16 * hinten)
F_GRUND   = $6f                 ; hellgrau auf blau
F_TITEL   = $67                 ; gelb auf blau
F_REITER  = $bf                 ; hellgrau auf dunkelgrau
F_AKTIV   = $70                 ; schwarz auf gelb
F_STATUS  = $f0                 ; schwarz auf hellgrau
BLINK_FREI = $0029              ; Kern: Cursor blinkt (waehrend der Werkstatt aus)

; Direkte Seite der Werkstatt ($A000)
	.virtual W_RAM
w_reiter  .byte ?               ; 0 SPRITES, 1 TILES, 2 MAP, 3 SOUNDS, 4 LOOK, 5 FONT
w_ende    .byte ?
w_ftalt   .fill 8               ; F1-F6, F10: vorheriger Stand
w_mx      .word ?               ; Maus 0-319, 0-239, Tasten
w_my      .word ?
w_mt      .byte ?
w_mtalt   .byte ?
w_tz      .long ?               ; Zeiger auf Text
w_farbe   .byte ?
w_t0      .word ?
w_t1      .word ?
w_taste   .byte ?               ; Taste dieses Bildes (0 = keine)
	.endv
	.dpage W_RAM                ; die Werkstatt laeuft mit D = $A000

;============================================================================

	* = $FFC000
	jml ws_start                ; $FF:C000  A = Reiter
	jml ws_sichern              ; $FF:C004  SAVE: D_ADR/D_LAENGE setzen
	jml ws_laden                ; $FF:C008  LOAD: aus dem Puffer verteilen
	jml ws_basic                ; $FF:C00C  BASIC MAP/TILE/SFX/LOOK, Direktmodus, Kaltstart, SFX-Takt

ws_start
	.as
	.xl
	pha
	jsr w_retten                ; mit D = 0: noch nichts in $A000 benutzen
	pla
	pea W_RAM
	pld
	sta w_reiter
	stz w_ende
	ldx #$7f                    ; Stand der Werkzeuge vom letzten Besuch
-	lda @l KART_STAND,x
	sta W_RAM+$80,x
	dex
	bpl -
	jsr w_einrichten
	jsr w_ftasten_merken
	jsr w_reiter_zeichnen

_schleife
	wai
	jsr w_maus
	jsr w_ftasten
	#kern K_L_GETIN
	sta w_taste
	cmp #$03                    ; Esc: zurueck
	bne +
	inc w_ende
	bra ++
+	lda w_reiter                ; der Reiter bekommt Maus und Taste
	asl a
	#akku16
	and #$00ff
	tax
	#akku8
	lda w_taste
	jsr (reiter_takt,x)
+	lda w_ende
	beq _schleife

	jsr w_ebenen                ; MAP: LOTSE anhalten, bevor er zurueckstellt
	jsr sf_alle_aus             ; SOUNDS: nichts klingt weiter
	jsr lk_verlassen            ; LOOK: Startfarben
	ldx #$7f                    ; Stand merken
-	lda W_RAM+$80,x
	sta @l KART_STAND,x
	dex
	bpl -
	jsr w_zurueck               ; endet mit D = 0
	rtl

reiter_takt
	.word <>sp_takt, <>sp_takt, <>ka_takt, <>kl_takt, <>lk_takt, <>sp_takt
reiter_inhalt
	.word <>sp_zeichnen, <>ki_zeichnen, <>ka_zeichnen, <>kl_zeichnen, <>lk_zeichnen, <>zs_zeichnen
w_nichts
	rts

;----------------------------------------------------------------------------
; Retten und wiederherstellen

w_retten
	.as
	ldx #0                      ; Bank-0-Arbeitsspeicher, Textschirm, Bitmap
	jsr w_kran_liste
	ldx #0                      ; Register
-	#akku16
	lda @l reg_liste,x
	beq +
	tay
	#akku8
	lda $0000,y
	sta @l AB_REG,x
	inx
	inx
	bra -
+	#akku8
	ldx #0                      ; Sprite-Tabelle
-	lda KOB_TAB,x
	sta @l AB_REG+$100,x
	inx
	cpx #256
	bne -
	rts

w_zurueck
	.as
	lda #$ff                    ; Mauszeiger aus (nicht ueber den Kern: der
	sta MZ_SPRITE               ; loescht das An-Bit in der Tabelle)
	ldx #0                      ; Sprite-Tabelle
-	lda @l AB_REG+$100,x
	sta KOB_TAB,x
	inx
	cpx #256
	bne -
	jsr w_muster_zurueck        ; Muster 0-127 aus der Cartridge nach KOBOLD
	ldx #0                      ; Register (LOTSE zuletzt in der Liste)
-	#akku16
	lda @l reg_liste,x
	beq +
	tay
	#akku8
	lda @l AB_REG,x
	sta $0000,y
	inx
	inx
	bra -
+	#akku8
	pea 0                       ; ab hier keine Variablen in $A000 mehr
	pld
	ldx #kz_zurueck - kran_auftraege
	jmp w_kran_liste            ; Bitmap, Text, zuletzt Bank 0

; Register, die die Werkstatt aendert (alle lesbar), 0 = Ende
reg_liste
	.word PIN_A_TYP, PIN_A_OPT, PIN_A_DAT, PIN_A_DAT+1, PIN_A_DAT+2
	.word PIN_A_MUS, PIN_A_MUS+1, PIN_A_MUS+2, PIN_A_SX, PIN_A_SX+1, PIN_A_SY
	.word PIN_B_TYP, PIN_B_OPT, PIN_B_DAT, PIN_B_DAT+1, PIN_B_DAT+2
	.word PIN_B_MUS, PIN_B_MUS+1, PIN_B_MUS+2, PIN_B_SX, PIN_B_SX+1, PIN_B_SY
	.word PIN_TUSCHE, PIN_TUSCHE+1, PIN_TUSCHE+2, PIN_TUSCHE+3
	.word PIN_GL_AN, PIN_GL_AN+1, PIN_LEUCHT
	.word KOB_STEU, MZ_SPRITE, SP_AN, BLINK_FREI
	.word LOT_LISTE, LOT_LISTE+1, LOT_LISTE+2, LOT_STEU
	.word 0

; Muster 0-127 aus der Cartridge nach KOBOLD (der Zeiger nutzt Muster 127)
w_muster_zurueck
	.as
	stz KOB_TAB+$100            ; MADR = 0 ($C400/$C401)
	stz KOB_TAB+$101
	ldx #0
-	lda @l KART_MUSTER,x
	sta KOB_TAB+$102            ; MDATEN, MADR zaehlt weiter
	inx
	cpx #$4000
	bne -
	rts

;----------------------------------------------------------------------------
; KRAN: Auftraege zu 16 Byte ab kran_auftraege+X ausfuehren, bis eine Zeile
; mit Modus $FF kommt

kauftrag .macro quelle, ziel, breite, hoehe, qa, za, wert, modus
	.long \quelle, \ziel
	.word \breite, \hoehe, \qa, \za
	.byte \wert, \modus
	.endm

kran_auftraege
	; retten
	#kauftrag W_RAM, AB_RAM, $1000, 1, 0, 0, 0, 0
	#kauftrag SCHIRM, AB_TEXT, 4800, 1, 0, 0, 0, 0
	#kauftrag BILD, AB_BILD, $4000, 4, $4000, $4000, 0, 0
	#kauftrag BILD+$10000, AB_BILD+$10000, 76800-$10000, 1, 0, 0, 0, 0
	.fill 15
	.byte $ff
kz_zurueck
	#kauftrag AB_BILD, BILD, $4000, 4, $4000, $4000, 0, 0
	#kauftrag AB_BILD+$10000, BILD+$10000, 76800-$10000, 1, 0, 0, 0, 0
	#kauftrag AB_TEXT, SCHIRM, 4800, 1, 0, 0, 0, 0
	#kauftrag AB_RAM, W_RAM, $1000, 1, 0, 0, 0, 0
	.fill 15
	.byte $ff
kz_bild_leeren
	#kauftrag 0, BILD, 320, 240, 0, 320, 0, 1
	.fill 15
	.byte $ff
kz_loeschen                     ; Oberflaeche: Bitmap leer, Text Leerzeichen
	#kauftrag 0, BILD, 320, 240, 0, 320, 0, 1
	#kauftrag 0, SCHIRM, 1, 2400, 0, 2, $20, 1
	#kauftrag 0, SCHIRM+1, 1, 2400, 0, 2, F_GRUND, 1
	.fill 15
	.byte $ff

w_kran_liste
	.as
-	lda @l kran_auftraege+15,x
	cmp #$ff
	beq _fertig
	ldy #0
-	lda @l kran_auftraege,x
	sta KRAN_REG,y
	inx
	iny
	cpy #16
	bne -
	lda #$08                    ; alte Fertig-Meldung weg, starten, warten
	sta KRAN_BEF
	lda #$01
	sta KRAN_BEF
-	lda KRAN_BEF
	and #$01
	bne -
	bra ---
_fertig
	rts

;----------------------------------------------------------------------------
; Oberflaeche

w_einrichten
	.as
	stz BLINK_FREI              ; der Cursor des Kerns blinkt nicht hinein
	stz LOT_STEU                ; kein Copper, kein Look
	stz PIN_TUSCHE
	stz PIN_GL_AN
	stz PIN_GL_AN+1
	stz PIN_LEUCHT
	ldx #0                      ; alle Sprites aus (die Tabelle ist gerettet)
-	stz KOB_TAB+6,x
	inx
	inx
	inx
	inx
	inx
	inx
	inx
	inx
	cpx #256
	bne -
	ldx #kz_loeschen - kran_auftraege
	jsr w_kran_liste
	ldx #0                      ; Schrift der Oberflaeche: die des ROM (ein
-	lda @l K_ZEICHENSATZ,x      ; Zeichensatz aus FONT macht sie nie unlesbar)
	sta W_FONT,x
	inx
	cpx #2048
	bne -
	jsr w_ebenen
	lda #1                      ; Mauszeiger: MOUSE 1 (Sprite 0, Muster 127)
	sta P_ANZ
	sta P_WERT
	stz P_WERT+1
	stz P_WERT+2
	lda #14
	#kern K_L_BEFEHL
	rts

; Ebene A Text 80 Zeichen, Ebene B Bitmap 256, kein Copper (MAP schaltet
; mit LOTSE um)
w_ebenen
	.as
	stz LOT_STEU
	lda #1                      ; Ebene A: Text 80 Zeichen
	sta PIN_A_TYP
	sta PIN_A_OPT
	lda #<SCHIRM
	sta PIN_A_DAT
	lda #>SCHIRM
	sta PIN_A_DAT+1
	stz PIN_A_DAT+2
	lda #<W_FONT
	sta PIN_A_MUS
	lda #>W_FONT
	sta PIN_A_MUS+1
	stz PIN_A_MUS+2
	stz PIN_A_SX
	stz PIN_A_SX+1
	stz PIN_A_SY
	lda #4                      ; Ebene B: Bitmap 256 (Farbe 0 durchsichtig)
	sta PIN_B_TYP
	stz PIN_B_OPT
	stz PIN_B_DAT
	stz PIN_B_DAT+1
	lda #`BILD
	sta PIN_B_DAT+2
	rts

; Reiterleiste oben, Statuszeile unten, Inhalt des Reiters
w_reiter_zeichnen
	.as
	ldx #0                      ; Zeile 0 dunkelgrau
-	lda #' '
	sta SCHIRM,x
	lda #F_REITER
	sta SCHIRM+1,x
	inx
	inx
	cpx #160
	bne -
	stz w_t0                    ; die sechs Reiter
_reiter
	#akku16
	lda w_t0
	and #$00ff
	asl a
	tax
	lda @l reiter_text,x
	pha
	lda @l reiter_spalte,x
	tax
	pla
	ldy #`reiter_namen
	jsr w_text_xy
	.as
	lda w_t0
	cmp w_reiter
	bne +
	lda #F_AKTIV
	bra ++
+	lda #F_REITER
+	jsr w_text
	inc w_t0
	lda w_t0
	cmp #6
	bne _reiter
	#text 0, 58, F_REITER, t_zurueck
	jmp w_inhalt

reiter_spalte
	.word 1 * 2, 11 * 2, 19 * 2, 25 * 2, 34 * 2, 41 * 2
reiter_text
	.word <>t_r0, <>t_r1, <>t_r2, <>t_r3, <>t_r4, <>t_r5
reiter_namen
t_r0	.null " SPRITES "
t_r1	.null " TILES "
t_r2	.null " MAP "
t_r3	.null " SOUNDS "
t_r4	.null " LOOK "
t_r5	.null " FONT "
t_zurueck .null "F10/Esc: back to BASIC"

; Inhalt des Reiters: Zeilen 1-29 und die Bitmap leeren, dann zeichnen
w_inhalt
	.as
	jsr lk_verlassen            ; LOOK: Startfarben
	jsr w_ebenen
	ldx #160
-	lda #' '
	sta SCHIRM,x
	lda #F_GRUND
	sta SCHIRM+1,x
	inx
	inx
	cpx #4800
	bne -
	ldx #kz_bild_leeren - kran_auftraege
	jsr w_kran_liste
	ldx #8                      ; Sprites 1-31 aus (der Zeiger bleibt)
-	stz KOB_TAB+6,x
	#akku16
	txa
	clc
	adc #8
	tax
	#akku8
	cpx #256
	bne -
	stz PIN_TUSCHE
	lda w_reiter
	asl a
	#akku16
	and #$00ff
	tax
	#akku8
	jmp (reiter_inhalt,x)

w_bald                          ; noch nicht gebaut
	.as
	#text 3, 2, F_TITEL, t_bald
	#text 5, 2, F_GRUND, t_bald2
	#text 29, 0, F_STATUS, t_status
	rts
t_bald	.null "MERIDIAN WORKSHOP"
t_bald2	.null "F1 SPRITES  F2 TILES  F3 MAP  F4 SOUNDS  F5 LOOK  F6 FONT"
t_status .null " MERIDIAN 1.0 workshop - this tab is being built                                "

; A (16 Bit) = Text, Y = seine Bank: Zeiger setzen; zurueck mit Akku 8
w_text_xy
	.al
	sta w_tz
	#akku8
	tya
	sta w_tz+2
	rts

; Text ab w_tz nach SCHIRM+X in Farbe A
w_text
	.as
	sta w_farbe
	ldy #0
-	lda [w_tz],y
	beq +
	sta SCHIRM,x
	lda w_farbe
	sta SCHIRM+1,x
	inx
	inx
	iny
	bra -
+	rts

;----------------------------------------------------------------------------
; Eingaben

w_maus
	.as
	lda w_mt
	sta w_mtalt
	sta PFO_MFEST
	#akku16
	lda PFO_MX
	sta w_mx
	lda PFO_MY
	sta w_my
	#akku8
	lda PFO_MT
	sta w_mt
	rts

; F-Tasten: Stand merken (beim Oeffnen haelt die Taste noch)
w_ftasten_merken
	.as
	ldy #0
-	jsr w_ftaste
	sta w_ftalt,y
	iny
	cpy #7
	bne -
	rts

w_ftaste                        ; A = Stand der F-Taste Y (benutzt X)
	.as
	tyx
	lda @l ftasten,x
	#akku16
	and #$00ff
	tax
	#akku8
	lda @l TASTEN_AN,x
	rts

; Neu gedrueckt: F1-F6 waehlen den Reiter, F10 fuehrt zurueck
w_ftasten
	.as
	ldy #0
-	jsr w_ftaste
	cmp w_ftalt,y
	beq _weiter
	sta w_ftalt,y
	cmp #0
	beq _weiter
	cpy #6
	bne +
	inc w_ende                  ; F10
	bra _weiter
+	tya
	sta w_reiter
	phy
	jsr w_reiter_zeichnen
	ply
_weiter
	iny
	cpy #7
	bne -
	rts
ftasten
	.byte $05, $06, $04, $0c, $03, $0b, $09  ; F1-F6, F10

; Zahl A (0-255) dezimal nach SCHIRM+X: 3, 2 oder 1 Stelle(n)
w_zahl3
	.as
	ldy #100
	jsr w_stelle
w_zahl2
	.as
	ldy #10
	jsr w_stelle
w_zahl1
	.as
	clc
	adc #'0'
	sta SCHIRM,x
	inx
	inx
	rts
w_stelle                        ; A / Y: Ziffer schreiben, A = Rest
	sty w_t1
	ldy #'0'
-	cmp w_t1
	bcc +
	sbc w_t1
	iny
	bra -
+	pha
	tya
	sta SCHIRM,x
	inx
	inx
	pla
	rts

	.include "ws_maler.asm"
	.include "ws_datei.asm"
	.include "ws_karte.asm"
	.include "ws_klang.asm"
	.include "ws_look.asm"

	.cerror * > $FFFFFF, "Werkstatt-ROM voll"
