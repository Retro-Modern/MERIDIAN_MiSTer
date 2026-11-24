;============================================================================
;  WERKSTATT: MAP - Karten aus Kacheln setzen, dazu BASIC MAP und TILE
;  (eingebunden von werkstatt.asm)
;
;  Zwei Karten zu 64 x 32 Kacheln im Chip-RAM, so wie PINSEL sie liest:
;  Karte 1 fuer die hintere Ebene A, Karte 2 fuer die vordere Ebene B.
;  Eintrag 2 Byte: Bits 0-9 Kachel, 10 spiegeln X, 11 Y, 12-15 Palettenbank.
;
;  Oben zeigt PINSEL die Karten selbst (Zeilen 8-151, 40 x 18 Kacheln, Karte
;  2 vor Karte 1): LOTSE schaltet dort beide Ebenen auf Kacheln und danach
;  wieder auf Text und Bitmap. Unten die Kacheln zur Auswahl wie bei TILES.
;
;  Maus: links setzen, rechts Kachel aufnehmen; Klick in der Auswahl waehlt.
;  Tasten: 1/2 Karte, Pfeile rollen (auch der Zeiger am Rand der Ansicht,
;  rom/ws_rollen.asm), H/V spiegeln, ,/. Kachel, Entf oder
;  Rueckschritt das Feld unter der Maus leeren, X Karte leeren, U zurueck
;  (nur auf der Karte, die zuletzt geaendert wurde: ein Stand fuer beide).
;
;  Gemalt wird immer nur auf der gewaehlten Karte, zu sehen sind beide. Darum
;  steht die Karte farbig ueber der Auswahl (ka_kopf), und geleert (Entf,
;  oder links mit der leeren Kachel 0) wird nur die vorderste Kachel eines
;  Feldes: liegt sie auf der anderen Karte, bleibt alles stehen und ein
;  Hinweis nennt die Karte (ka_fremd). Sonst risse, wer auf Karte 1 eine Wand
;  von Karte 2 treffen will, Loecher in den Hintergrund darunter - und saehe
;  sie unter der Wand nicht einmal.
;============================================================================

KARTE1    = $036000             ; Karte 1 (Ebene A), 4 KB
KARTE2    = $037000             ; Karte 2 (Ebene B), 4 KB
KA_LOT_ADR  = BILD + 8 * 320      ; Befehlsliste: in Bitmap-Zeilen, die die Karte verdeckt
KA_UNDO   = KART+$5000          ; die Karte vor der letzten Aenderung
KA_TAUSCH = KART+$6000
KA_ZUSTAND = KART+$4300         ; BASIC MAP: Bit 0 Karte 1 auf A, Bit 1 Karte 2 auf B
KA_ALT    = KART+$4320          ; BASIC MAP: Register davor (wie PINSEL $00-$32)
PIN_B_MUS = $C025
PIN_B_SX  = $C030
PIN_B_SY  = $C032
ROLL_RUF  = $FF402A             ; System-ROM (rom/ws_rollen.asm): rollen mit Pfeiltaste A und Mausrand

	.virtual W_RAM+$a0          ; Variablen von MAP (bleiben bis zum naechsten Besuch)
ka_ebene  .byte ?               ; 0 Karte 1, 1 Karte 2
ka_sx     .byte ?               ; erste sichtbare Spalte 0-24
ka_sy     .byte ?               ;   Zeile 0-14
ka_flip   .byte ?               ; Bit 0 X, Bit 1 Y
ka_cx     .byte ?               ; Kachel unter der Maus (Schirm), $ff = keine
ka_cy     .byte ?
ka_z      .long ?               ; Zeiger auf den Eintrag
ka_hinweis .byte ?              ; Hinweis auf die andere Karte: KA_HINWEIS_AN, 0 = keiner
ka_undo_karte .byte ?           ; der Stand in KA_UNDO gehoert zu Karte 1/2, 0 = keiner da
ka_strich .byte ?               ; seit dem Klick ist schon gemerkt (0 = noch nicht)
ka_rand   .byte ?               ; Bilder, die der Zeiger schon am Rand steht (rom/ws_rollen.asm)
ka_bild   .byte ?               ;   und der Bildzaehler beim letzten Zaehlen
	.endv

KS_KARTE = 5
KS_ART = 7
KS_TILE = 24
KS_BANK = 34
KS_FLIP = 43
KS_X = 50
KS_Y = 56
KA_SPALTEN = 40
KA_ZEILEN  = 18
KK_SPALTE = 22                  ; Zeile 19: die gewaehlte Karte (der Anfang der
KK_BREITE = 16                  ; Statuszeile, farbig), daneben der Hinweis
KH_SPALTE = 40
F_KARTE2  = $30                 ; schwarz auf tuerkis (Karte 1: F_AKTIV, gelb)
F_HINWEIS = $21                 ; weiss auf rot
F_UNSICHTBAR = $66              ; blau auf blau
KA_HINWEIS_AN = F_HINWEIS ^ F_UNSICHTBAR    ; (ka_kopf macht daraus die Farbe)

setze	.macro reg, wert        ; LOTSE: Register = Wert
	.byte $02, <(\reg), >(\reg), \wert
	.endm

;----------------------------------------------------------------------------
; Reiter oeffnen

ka_zeichnen
	.as
	stz ka_hinweis              ; (bliebe sonst bis zum naechsten Besuch)
	jsr ki_wahl
	jsr sp_laden                ; Bank der Kachel
	#text 19, 1, F_TITEL, t_ki_bogen
	#text 26, 1, F_GRUND, t_ka_hilfe1
	#text 27, 1, F_GRUND, t_ka_hilfe2
	jsr ka_lotse
ka_neu                          ; nach der Wahl einer Kachel
	.as
	jsr sp_bogen
	jmp ka_status

t_ka_hilfe1 .null "Mouse: left place, right pick tile.  1/2 map  Arrows scroll  H/V flip  ,. tile"
t_ka_hilfe2 .null "Del erase  X clear map  U undo.  BASIC: MAP n,x,y shows map n"

; LOTSE: Karten in den Zeilen 8-151
ka_lotse
	.as
	ldx #0
-	lda @l ka_liste,x
	sta @l KA_LOT_ADR,x
	inx
	cpx #ka_liste_ende - ka_liste
	bne -
	lda #<KA_LOT_ADR
	sta LOT_LISTE
	lda #>KA_LOT_ADR
	sta LOT_LISTE+1
	lda #`KA_LOT_ADR
	sta LOT_LISTE+2
	lda #<KACHELN               ; Ebene B: Muster und Rollen braucht nur der
	sta PIN_B_MUS               ; Kachelmodus, die Bitmap stoert es nicht
	lda #>KACHELN
	sta PIN_B_MUS+1
	lda #`KACHELN
	sta PIN_B_MUS+2
	jsr ka_rollen
	lda #1
	sta LOT_STEU
	rts

ka_liste
	.byte $01, 7, $02, $ff      ; WARTE Zeile 7, Zeilenanfang: ab Zeile 8
	#setze PIN_A_TYP, 2
	#setze PIN_A_DAT, <KARTE1
	#setze PIN_A_DAT+1, >KARTE1
	#setze PIN_A_DAT+2, `KARTE1
	#setze PIN_A_MUS, <KACHELN
	#setze PIN_A_MUS+1, >KACHELN
	#setze PIN_A_MUS+2, `KACHELN
	#setze PIN_B_TYP, 2
	#setze PIN_B_DAT, <KARTE2
	#setze PIN_B_DAT+1, >KARTE2
	#setze PIN_B_DAT+2, `KARTE2
	.byte $01, 151, $02, $ff    ; WARTE Zeile 151: ab Zeile 152 wieder
	#setze PIN_A_TYP, 1         ; Text und Bitmap
	#setze PIN_A_DAT, <SCHIRM
	#setze PIN_A_DAT+1, >SCHIRM
	#setze PIN_A_DAT+2, 0
	#setze PIN_A_MUS, <ZEICHEN
	#setze PIN_A_MUS+1, >ZEICHEN
	#setze PIN_A_MUS+2, 0
	#setze PIN_B_TYP, 4
	#setze PIN_B_DAT, 0
	#setze PIN_B_DAT+1, 0
	#setze PIN_B_DAT+2, `BILD
	.byte 0, 0, 0, 0            ; ENDE
ka_liste_ende

; Rollen: Spalte ka_sx, Zeile ka_sy in Schirmzeile 8 (beide Ebenen). Das
; macht seit 24.11.2026 das System-ROM (rom/ws_rollen.asm): es setzt die
; Rollregister und rollt vorher mit einer Pfeiltaste in A und wenn der
; Mauszeiger am Rand der Ansicht steht. Hier war dafuer kein Platz mehr.
ka_rollen                       ; Reiter oeffnen: nur die Register, das Rollen am Rand ruht
	.as
	lda #$ff                    ; (WR_OEFFNEN)
ka_rollen_taste                 ; A = Taste dieses Bildes (bleibt)
	pha
	lda @l ROLL_RUF             ; steht dort der Sprung? In einem System-ROM vor
	cmp #$4c                    ; dem 24.11.2026 beginnt an der Stelle dos_befehl
	bne +                       ; (phd): der Aufruf wuerde je Bild das DOS laden lassen
	pla
	jsl ROLL_RUF
	rts
+	pla
	rts
	.cerror w_mx != W_RAM+$0a || w_my != W_RAM+$0c || w_mt != W_RAM+$0e, "ws_rollen.asm kennt w_mx, w_my, w_mt an $A00A, $A00C, $A00E"
	.cerror ka_sx != W_RAM+$a1 || ka_sy != W_RAM+$a2, "ws_rollen.asm kennt ka_sx, ka_sy an $A0A1, $A0A2"
	.cerror ka_rand != W_RAM+$ac || ka_bild != W_RAM+$ad, "ws_rollen.asm kennt ka_rand, ka_bild an $A0AC, $A0AD"
	.cerror KA_SPALTEN != 40 || KA_ZEILEN != 18, "ws_rollen.asm rechnet mit 40 x 18 Kacheln (WR_SPALTEN, WR_ZEILEN)"

; Statuszeile
ka_status
	.as
	#text 29, 0, F_STATUS, t_ka_status
	lda ka_ebene
	inc a
	ldx #29 * 160 + KS_KARTE * 2
	jsr w_zahl1
	lda ka_ebene
	bne +
	#text 29, KS_ART, F_STATUS, t_ka_hinten
	lda #F_AKTIV                ; Karte 1 gelb, Karte 2 tuerkis: der Wechsel
	bra ++                      ; soll auffallen
+	#text 29, KS_ART, F_STATUS, t_ka_vorn
	lda #F_KARTE2
+	jsr ka_kopf
	lda sp_m
	ldx #29 * 160 + KS_TILE * 2
	jsr w_zahl3
	lda sp_b
	ldx #29 * 160 + KS_BANK * 2
	jsr w_zahl2
	ldx #'-'                    ; spiegeln
	lda ka_flip
	lsr a
	bcc +
	ldx #'X'
+	txa
	sta SCHIRM+29*160+KS_FLIP*2
	ldx #'-'
	lda ka_flip
	and #$02
	beq +
	ldx #'Y'
+	txa
	sta SCHIRM+29*160+KS_FLIP*2+2
	lda ka_cy                   ; Feld unter der Maus (Karte)
	bmi +
	clc
	adc ka_sy
	pha
	lda ka_cx
	clc
	adc ka_sx
	ldx #29 * 160 + KS_X * 2
	jsr w_zahl2
	pla
	ldx #29 * 160 + KS_Y * 2
	jsr w_zahl2
+	rts
t_ka_status .null " MAP 1 (behind)    TILE 000  BANK 00  FLIP --   X 00  Y 00     map 64 x 32 tiles"
t_ka_hinten .null "(behind)"
t_ka_vorn   .null "(front) "

	.section w_luecke           ; (liegt vorn in werkstatt.asm, siehe dort)

; Zeile 19: die gewaehlte Karte in Farbe A - der Text ist der Anfang der
; Statuszeile, die schon steht -, daneben der Hinweis auf die andere Karte
; (ohne Hinweis blau auf blau: so muss ihn niemand wegwischen)
ka_kopf
	.as
	tay
	ldx #KK_BREITE * 2 - 2
-	lda SCHIRM + 29 * 160,x
	sta SCHIRM + 19 * 160 + KK_SPALTE * 2,x
	tya
	sta SCHIRM + 19 * 160 + KK_SPALTE * 2 + 1,x
	dex
	dex
	bpl -
	ldx #19 * 160 + KH_SPALTE * 2
	#akku16
	lda #<>t_ka_fremd
	ldy #`t_ka_fremd
	jsr w_text_xy
	.as
	lda ka_hinweis
	eor #F_UNSICHTBAR
	jsr w_text
	lda #'2'                    ; die andere Karte: 2 - ka_ebene
	sec
	sbc ka_ebene
	sta SCHIRM + 19 * 160 + (KH_SPALTE + KH_Z1) * 2
	sta SCHIRM + 19 * 160 + (KH_SPALTE + KH_Z2) * 2
	rts
t_ka_fremd .null "On MAP 2 - press 2"
KH_Z1 = 7                       ; die beiden Ziffern im Text
KH_Z2 = 17

; Vor der ersten Aenderung eines Strichs (vom Klick bis zum Loslassen): den
; Stand fuer U merken. Mit der leeren Kachel 0 ist das nicht immer der Klick
; selbst - der kann ein gesperrtes oder leeres Feld treffen und erst das
; Ziehen etwas leeren. Ein Strich, der nichts aendert, merkt auch nichts
ka_strich_merken
	.as
	inc ka_strich
	stz ka_hinweis
	jmp ka_merken

; Z = 1: der Stand in KA_UNDO gehoert zur gewaehlten Karte. Es gibt nur den
; einen fuer beide Karten - U auf der anderen tauschte sonst deren Inhalt
; gegen diesen Stand
ka_undo_hier
	.as
	lda ka_ebene
	inc a
	cmp ka_undo_karte
	rts

; Vor dem Leeren des Feldes ka_z (Entf, oder links mit der leeren Kachel 0):
; geleert wird nur die vorderste Kachel des Feldes - die von Karte 2, sonst
; die von Karte 1. Was man treffen will, ist fast immer sie; den Hintergrund
; unter einer Wand sieht man oft gar nicht, ein Loch darin auch nicht.
; Zurueck Z = 1: sie liegt auf der gewaehlten Karte, leeren. Sonst Z = 0 und
; A = der Hinweis (0, wenn das Feld auf beiden Karten leer ist). C bleibt.
ka_fremd
	.as
	#akku16
	lda ka_z                    ; dasselbe Feld in beiden Karten
	and #$0fff
	tax
	ldy #1                      ; vorn liegt die Kachel von Karte 2 ...
	lda @l KARTE2,x
	and #$03ff
	bne +
	dey                         ; ... sonst die von Karte 1 ...
	lda @l KARTE1,x
	and #$03ff
	beq _keine
+	#akku8
	tya
	eor ka_ebene
	beq +
	lda #KA_HINWEIS_AN          ; auf der anderen Karte
+	rts
_keine
	#akku8                      ; ... oder keine: A = 0, und Z = 0 macht
	dey                         ; das dey
	rts

	.send

;----------------------------------------------------------------------------
; Je Bild: Maus und Tasten (Taste in A, 0 = keine)

ka_takt
	.as
	jsr ka_rollen_taste         ; Pfeiltasten und der Zeiger am Rand rollen
	cmp #0
	beq +
	jsr ka_taste
+	jsr ka_maus_feld
	lda ka_cy
	bmi _unten
	lda w_mt
	and #$02                    ; rechts: Kachel aufnehmen
	beq _links
	jsr ka_zeiger
	lda [ka_z]
	cmp sp_m
	beq _ende
	jmp sp_waehlen
_links
	lda w_mt
	and #$01
	beq _ende
	jsr ka_zeiger               ; (ka_merken laesst ka_z stehen)
	lda w_mtalt
	lsr a                       ; C = 1: die Taste haelt schon
	bcs +
	stz ka_strich               ; ein neuer Strich
+	lda sp_m                    ; eine Kachel setzen geht ueberall, mit der
	bne _setzen                 ; leeren Kachel 0 aber nur die vorderste weg
	jsr ka_fremd
	bcs +                       ; der Hinweis nur beim Klick: nach dem Leeren
	sta ka_hinweis              ; zeigte er sonst gleich auf die Kachel darunter
+	bne _ende
_setzen
	lda ka_strich               ; die erste Aenderung des Strichs: vorher merken
	bne +
	jsr ka_strich_merken
+	jsr ka_eintrag
	#akku16
	sta [ka_z]
	#akku8
	bra _ende
_unten
	lda w_mt                    ; Klick in die Auswahl
	and #$01
	beq _ende
	lda w_mtalt
	and #$01
	bne _ende
	#akku16
	jmp sp_klick_bogen
_ende
	jmp ka_status

; ka_cx/ka_cy: Kachel unter der Maus in der Kartenansicht ($ff = keine)
ka_maus_feld
	.as
	lda #$ff
	sta ka_cx
	sta ka_cy
	#akku16
	lda w_my
	sec
	sbc #8
	cmp #KA_ZEILEN * 8
	bcs +
	lsr a
	lsr a
	lsr a
	#akku8
	sta ka_cy
	#akku16
	lda w_mx
	lsr a
	lsr a
	lsr a
	#akku8
	sta ka_cx
+	#akku8
	rts

; ka_z = Eintrag unter der Maus in der gewaehlten Karte
ka_zeiger
	.as
	lda ka_cy
	clc
	adc ka_sy
	and #31
	#akku16
	and #$00ff
	xba
	lsr a                       ; Zeile * 128
	sta ka_z
	#akku8
	lda ka_cx
	clc
	adc ka_sx
	and #63
	asl a
	#akku16
	and #$00ff
	ora ka_z
	clc
	adc #<>KARTE1
	sta ka_z
	#akku8
	lda ka_ebene
	asl a
	asl a
	asl a
	asl a
	clc
	adc ka_z+1                  ; Karte 2: + $1000
	sta ka_z+1
	lda #`KARTE1
	sta ka_z+2
	rts

; A (16 Bit) = Eintrag fuer die gewaehlte Kachel: Bank, spiegeln
ka_eintrag
	.as
	lda sp_b
	asl a
	asl a
	asl a
	asl a
	sta sp_t+1
	lda ka_flip
	asl a
	asl a
	ora sp_t+1
	xba
	lda sp_m
	rts

; die gewaehlte Karte nach KA_UNDO (vor einer Aenderung)
ka_merken
	.as
	lda ka_ebene                ; (fuer U: ka_undo_hier)
	inc a
	sta ka_undo_karte
	jsr ka_quelle
	#akku16
	lda #<>KA_UNDO
	sta dz_z
	#akku8
	lda #`KA_UNDO
	sta dz_z+2
	jmp ws_kopie

ka_quelle                       ; dz_q = Karte, dz_r = 4 KB
	.as
	#akku16
	lda #<>KARTE1
	sta dz_q
	lda #$1000
	sta dz_r
	#akku8
	lda ka_ebene
	beq +
	lda #>KARTE2
	sta dz_q+1
+	lda #`KARTE1
	sta dz_q+2
	stz dz_r+2
	rts

;----------------------------------------------------------------------------
; Tasten

; Entf oder Rueckschritt: das Feld unter der Maus leeren. Die gewaehlte Kachel
; bleibt dabei, anders als beim Aufnehmen der leeren Kachel 0 mit rechts
ka_feld_leeren
	.as
	jsr ka_maus_feld            ; (ka_takt fragt die Maus erst nach der Taste)
	lda ka_cy
	bmi +
	jsr ka_zeiger
	jsr ka_fremd
	sta ka_hinweis
	bne +                       ; nichts zu leeren: auch nichts merken - haelt
	jsr ka_merken               ; jemand die Taste, naehme ihre Wiederholung U
	#akku16                     ; sonst den Stand vor dem Leeren
	lda #0
	sta [ka_z]
	#akku8
+	rts

ka_taste
	.as
	stz ka_hinweis              ; jede Taste nimmt den Hinweis weg (Entf prueft neu)
	; (die Pfeiltasten: ka_rollen_taste, vor ka_taste gerufen)
	cmp #$7f                    ; Entf, Rueckschritt (GETIN des Kerns)
	beq ka_feld_leeren
	cmp #$08
	beq ka_feld_leeren
	cmp #'1'
	bne +
	stz ka_ebene
	rts
+	cmp #'2'
	bne +
	lda #1
	sta ka_ebene
	rts
+	cmp #','
	bne +
	lda sp_m
	dec a
	jmp sp_waehlen
+	cmp #'.'
	bne +
	lda sp_m
	inc a
	jmp sp_waehlen
+	and #$df                    ; Buchstaben gross
	cmp #'H'
	bne +
	lda ka_flip
	eor #$01
	sta ka_flip
	rts
+	cmp #'V'
	bne +
	lda ka_flip
	eor #$02
	sta ka_flip
	rts
+	cmp #'X'
	bne +
	jsr ka_merken               ; leeren (mit KRAN fuellen)
	jsr ka_quelle
	#akku16
	lda dz_q
	sta KRAN_REG+3
	lda #$1000
	sta KRAN_REG+6
	lda #1
	sta KRAN_REG+8
	stz KRAN_REG+10
	stz KRAN_REG+12
	#akku8
	lda dz_q+2
	sta KRAN_REG+5
	stz KRAN_REG+14
	lda #1
	sta KRAN_REG+15
	jmp ws_starten
+	cmp #'U'
	bne +
	jsr ka_undo_hier            ; nur auf der Karte, deren Stand gemerkt ist
	bne +
	jsr ka_quelle               ; zurueck: Karte <-> KA_UNDO ueber KA_TAUSCH
	#akku16
	lda #<>KA_TAUSCH
	sta dz_z
	#akku8
	lda #`KA_TAUSCH
	sta dz_z+2
	jsr ws_kopie                ; Karte -> Tausch
	#akku16
	lda #<>KA_UNDO
	sta dz_q
	lda #$1000
	sta dz_r
	#akku8
	lda #`KA_UNDO
	sta dz_q+2
	stz dz_r+2
	jsr ka_quelle_ziel
	jsr ws_kopie                ; Undo -> Karte
	#akku16
	lda #<>KA_TAUSCH
	sta dz_q
	lda #<>KA_UNDO
	sta dz_z
	lda #$1000
	sta dz_r
	#akku8
	lda #`KA_TAUSCH
	sta dz_q+2
	lda #`KA_UNDO
	sta dz_z+2
	stz dz_r+2
	jmp ws_kopie                ; Tausch -> Undo
+	rts

ka_quelle_ziel                  ; dz_z = die gewaehlte Karte
	.as
	#akku16
	lda #<>KARTE1
	sta dz_z
	#akku8
	lda ka_ebene
	beq +
	lda #>KARTE2
	sta dz_z+1
+	lda #`KARTE1
	sta dz_z+2
	rts

;============================================================================
; BASIC (ueber den Kern: Akku 8, Index 16, D = 0, DBR 0). A = 0 MAP,
; 1 TILE, 2 TILE(), 3 BASIC wartet auf einen Befehl, 4 Kaltstart, 5 SFX,
; 6 Takt des SFX-Abspielers (aus dem Interrupt), 7 LOOK. Befehle
; geben A = 0 (gut) oder 1 (ILLEGAL QUANTITY) zurueck.

	.dpage 0
WB_E     = DZ                   ; Ebene/Karte 0 oder 1
WB_GRENZE = DZ+1
WB_BIT   = DZ+2
F_WERT   = $00                  ; Ergebnis einer Funktion (LZ in BASIC)
KA_PIN   = $C000

ws_basic
	.as
	.xl
	#akku16
	and #$00ff
	asl a
	tax
	lda K_BAENKE                ; ohne Zusatzspeicher (kein SDRAM-Modul)
	cmp #$fd
	#akku8
	bcc wb_ohne
	jmp (wb_tabelle,x)
wb_ohne                         ; Befehle melden es, der Rest tut nichts
	cpx #2 * 2
	bne +
	stz F_WERT                  ; TILE(): 0
	stz F_WERT+1
	stz F_WERT+2
	rtl
+	cpx #3 * 2                  ; Direktmodus, Kaltstart, SFX-Takt
	beq +
	cpx #4 * 2
	beq +
	cpx #6 * 2
	beq +
	lda #14                     ; NO EXPANSION RAM
	rtl
+	lda #0
	rtl
wb_tabelle
	.word <>wb_map, <>wb_tile, <>wb_tile_wert, <>wb_direkt, <>wb_kalt
	.word <>wb_sfx, <>ws_sfx_takt, <>wb_look

; MAP l[,x,y]: Ebene l (1 hinten = A, 2 vorn = B) zeigt Karte l, gerollt um
; x (0-511), y (0-255) Punkte. MAP 0: aus (Text und Grafik wie vorher).
wb_map
	.as
	lda P_ANZ
	beq wb_falsch
	lda #3
	sta WB_GRENZE
	ldy #0
	jsr wb_wert
	bcs wb_falsch
	cmp #0
	bne +
	jsr wb_karten_aus
	lda #0
	rtl
+	dec a
	sta WB_E
	inc a
	sta WB_BIT                  ; 1 oder 2
	lda @l KA_ZUSTAND           ; zum ersten Mal: Register merken
	and WB_BIT
	bne +
	lda @l KA_ZUSTAND
	ora WB_BIT
	sta @l KA_ZUSTAND
	jsr wb_basis
	jsr wb_retten
+	jsr wb_basis                ; X = Ebene * $20
	lda #2
	sta KA_PIN+0,x              ; TYP Kacheln
	lda #0
	sta KA_PIN+1,x
	sta KA_PIN+2,x              ; DATEN = Karte
	lda WB_E
	asl a
	asl a
	asl a
	asl a
	ora #>KARTE1
	sta KA_PIN+3,x
	lda #`KARTE1
	sta KA_PIN+4,x
	lda #<KACHELN
	sta KA_PIN+5,x
	lda #>KACHELN
	sta KA_PIN+6,x
	lda #`KACHELN
	sta KA_PIN+7,x
	lda P_ANZ                   ; rollen
	cmp #2
	bcc ++
	lda P_WERT+3
	sta KA_PIN+$10,x
	lda P_WERT+4
	and #1
	sta KA_PIN+$11,x
	lda P_ANZ
	cmp #3
	bcc +
	lda P_WERT+6
	sta KA_PIN+$12,x
+
+	lda #0
	rtl

wb_falsch
	lda #1
	rtl

wb_basis                        ; X = WB_E * $20
	.as
	lda WB_E
	asl a
	asl a
	asl a
	asl a
	asl a
	#akku16
	and #$00ff
	tax
	#akku8
	rts

; Register $00-$07 und $10-$12 der Ebene X nach KA_ALT bzw. zurueck
wb_retten
	.as
	ldy #11
-	lda KA_PIN,x
	sta @l KA_ALT,x
	jsr wb_naechstes
	bne -
	rts
wb_zurueck
	.as
	ldy #11
-	lda @l KA_ALT,x
	sta KA_PIN,x
	jsr wb_naechstes
	bne -
	rts
wb_naechstes                    ; X weiter ($07 -> $10), Y zaehlt herab
	inx
	#akku16
	txa
	and #$000f
	cmp #8
	bne +
	txa
	clc
	adc #8
	tax
+	#akku8
	dey
	rts

; Karten aus: Ebenen wie vor dem ersten MAP
wb_karten_aus
	.as
	lda @l KA_ZUSTAND
	lsr a
	bcc +
	ldx #0
	jsr wb_zurueck
+	lda @l KA_ZUSTAND
	and #2
	beq +
	ldx #$20
	jsr wb_zurueck
+	lda #0
	sta @l KA_ZUSTAND
	rts

; BASIC wartet auf einen Befehl: das Programm ist zu Ende, Karten aus
wb_direkt
	.as
	lda @l KA_ZUSTAND
	beq +
	jsr wb_karten_aus
+	rtl

; Kaltstart: Cartridge (mit Klaengen), Kacheln und Karten leeren
wb_kalt
	.as
	ldx #0
-	lda @l wb_leeren,x
	sta KRAN_REG,x
	inx
	cpx #16
	bne -
	jsr ws_starten
	ldx #0
-	lda @l wb_leeren+16,x
	sta KRAN_REG,x
	inx
	cpx #16
	bne -
	jsr ws_starten
	jsr ws_vorgaben             ; Startfarben, Zeichensatz des ROM
	rtl
wb_leeren
	#kauftrag 0, KART, $4000, 3, 0, $4000, 0, 1           ; $F8:0000-$BFFF
	#kauftrag 0, KACHELN, $4000, 1, 0, 0, 0, 1            ; $03:4000-$7FFF
	; (der Zeichensatz $F8:C000 bekommt den des ROM: ws_vorgaben)

; TILE l,x,y,t[,f]: Feld x (0-63), y (0-31) der Karte l (1/2) bekommt
; Kachel t (0-255); f = Palettenbank + 16 spiegeln X + 32 Y, ohne f die
; Bank, in der die Kachel gemalt wurde
wb_tile
	.as
	lda P_ANZ
	cmp #4
	bcc wb_falsch
	jsr wb_feld
	bcs wb_falsch
	lda #0                      ; Kachel
	sta WB_GRENZE
	ldy #9
	jsr wb_wert                 ; (Grenze 0 = 256)
	bcs wb_falsch
	pha
	lda P_ANZ
	cmp #5
	bcc _bank
	lda #64
	sta WB_GRENZE
	ldy #12
	jsr wb_wert
	bcs _falsch2
	pha                         ; f: Bits 0-3 Bank, 4 X, 5 Y
	asl a
	asl a
	asl a
	asl a
	sta WB_BIT                  ; Bank oben
	pla
	lsr a
	lsr a
	and #$0c                    ; X -> Bit 2, Y -> Bit 3 (des oberen Bytes)
	ora WB_BIT
	bra _schreiben
_bank
	lda 1,s                     ; Bank der Kachel
	#akku16
	and #$00ff
	tax
	#akku8
	lda @l KART_KBANK,x
	asl a
	asl a
	asl a
	asl a
_schreiben
	xba
	pla
	#akku16
	sta [K_ZEIGER]
	#akku8
	lda #0
	rtl
_falsch2
	pla
	jmp wb_falsch

; TILE(l,x,y): Kachel im Feld x,y der Karte l (0, wenn es das Feld nicht gibt)
wb_tile_wert
	.as
	stz F_WERT+2
	lda P_ANZ
	cmp #3
	bcc _null
	jsr wb_feld
	bcs _null
	#akku16
	lda [K_ZEIGER]
	and #$03ff
	sta F_WERT
	#akku8
	rtl
_null
	stz F_WERT
	stz F_WERT+1
	rtl

; Werte 0-2 (l, x, y) pruefen, K_ZEIGER = Eintrag; C = 1: falsch
wb_feld
	.as
	lda #3
	sta WB_GRENZE
	ldy #0
	jsr wb_wert
	bcs _f
	dec a
	bmi _f                      ; l = 0
	sta WB_E
	lda #64
	sta WB_GRENZE
	ldy #3
	jsr wb_wert
	bcs _f
	asl a
	sta K_ZEIGER                ; x * 2
	stz K_ZEIGER+1
	lda #32
	sta WB_GRENZE
	ldy #6
	jsr wb_wert
	bcs _f
	#akku16
	and #$00ff
	xba
	lsr a                       ; y * 128
	ora K_ZEIGER
	and #$0fff
	clc
	adc #<>KARTE1
	sta K_ZEIGER
	#akku8
	lda WB_E
	asl a
	asl a
	asl a
	asl a
	clc
	adc K_ZEIGER+1
	sta K_ZEIGER+1
	lda #`KARTE1
	sta K_ZEIGER+2
	clc
	rts
_f
	sec
	rts

; Wert Y/3 als Byte: A = Wert, C = 1, wenn > 255 oder >= WB_GRENZE (0 = 256)
wb_wert
	.as
	lda P_WERT+1,y
	ora P_WERT+2,y
	bne +
	lda WB_GRENZE
	beq _ok
	lda P_WERT,y
	cmp WB_GRENZE
	rts
_ok
	lda P_WERT,y
	clc
	rts
+	sec
	rts

; KRAN starten und warten (Auftrag steht in KRAN_REG)
ws_starten
	.as
	lda #$08
	sta KRAN_BEF
	lda #$01
	sta KRAN_BEF
-	lda KRAN_BEF
	and #$01
	bne -
	rts

	.dpage W_RAM
