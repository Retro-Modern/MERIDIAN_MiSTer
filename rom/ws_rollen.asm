;============================================================================
;  WERKSTATT, Reiter MAP: die Karte rollen (24.11.2026)
;  (eingebunden von dos.asm; Einsprung $FF:402A, gerufen aus ws_karte.asm)
;
;  Die Kartenansicht zeigt 40 x 18 Kacheln der 64 x 32 grossen Karten. Sie
;  rollt mit den Pfeiltasten und - neu - wenn der Mauszeiger am Rand der
;  Ansicht steht.
;
;  Die Routine liegt im System-ROM, weil das Werkstatt-ROM voll war (1 Byte
;  frei). Die Pfeiltasten und das Setzen der Rollregister sind mit umgezogen:
;  so steht alles zum Rollen an einer Stelle, und in der Werkstatt wurde
;  Platz frei (81 Byte weniger die Pruefung des Einsprungs).
;
;  Am Rand rollt die Karte nicht sofort: oben grenzt die Ansicht an die
;  Reiterzeile, unten an die Kachelauswahl, und wer dorthin faehrt, kommt
;  durch den Rand. Erst wenn der Zeiger WR_WARTEN Bilder lang im Randstreifen
;  bleibt, rollt sie um eine Kachel und dann alle WR_TEMPO Bilder weiter. In
;  einer Ecke rollt sie schraeg. Links und rechts ist der Rand der Ansicht
;  der Rand des Bildes, dort haelt der Zeiger von selbst an: der Streifen ist
;  darum nur zwei Punkte breit. Oben und unten haelt ihn nichts an - mit
;  vier Punkten in der Karte allein fuhr man darueber hinaus und nichts
;  rollte - so war es in der ersten Fassung. Darum zaehlt oben die ganze Reiterzeile mit (dort ist auch der
;  Bildrand) und unten die Zeile unter der Karte, je mit den vier Punkten in
;  der Karte: zwoelf Bildzeilen. Wer auf einen Reiter zeigt und wartet, rollt
;  die Karte dabei nach oben - das ist der Preis.
;
;  Eine Pfeiltaste haelt das Rollen am Rand an, bis der Zeiger den Streifen
;  einmal verlassen hat (WR_AUS). Sonst liefe die Karte, wenn die Maus zur
;  Seite geschoben am Bildrand liegt, gegen die Tasten an. Dasselbe gilt
;  nach dem Oeffnen des Reiters: die gemerkte Ansicht bleibt stehen, auch
;  wenn der Zeiger gerade am Rand liegt. Mit gedrueckter Maustaste rollt die
;  Karte nicht (malen in der Randkachel).
;
;  Gezaehlt werden Bilder (der Bildzaehler des Kerns), nicht Durchlaeufe: die
;  Schleife der Werkstatt weckt jeder Interrupt, mit einem laufenden SONG
;  also auch dessen Taktgeber - die Karte liefe dann schneller.
;
;  Gerufen aus ws_karte.asm mit D = $A000 (die Variablen der Werkstatt liegen
;  in der direkten Seite) und A 8 Bit:
;    je Bild mit der Taste in A (0 = keine)
;    A = WR_OEFFNEN ($FF) beim Oeffnen des Reiters: nur die Rollregister, das
;      Rollen am Rand ist angehalten (die Maus ist dann noch nicht gelesen;
;      eine Taste $FF liefert die Tastatur nicht)
;  A (8 Bit, das obere Byte wird 0), X, Y, D, das Datenbankregister und die
;  Schalter bleiben.
;
;  Ein System-ROM ohne diesen Einsprung: ws_karte.asm prueft, ob bei $FF:402A
;  ein Sprung steht, und ruft sonst nicht (dort begaenne dos_befehl). Die
;  Karte rollt dann gar nicht und steht um eine Zeile versetzt - beide ROMs
;  gehoeren zusammen in einen Kern, die Pruefung verhindert nur Schlimmeres.
;============================================================================

; Variablen der Werkstatt (direkte Seite $A000). ws_karte.asm prueft mit
; .cerror, dass sie dort liegen - wer hier etwas aendert, aendert es dort mit.
WR_MX     = $0a                 ; w_mx: Maus 0-319 (16 Bit)
WR_MY     = $0c                 ; w_my: 0-239
WR_MT     = $0e                 ; w_mt: Maustasten (Bit 0 links, Bit 1 rechts)
WR_SX     = $a1                 ; ka_sx: erste sichtbare Spalte
WR_SY     = $a2                 ; ka_sy:   Zeile
WR_ZAEHLER = $ac                ; ka_rand: so viele Bilder steht der Zeiger schon am Rand (WR_AUS: angehalten)
WR_BILD   = $ad                 ; ka_bild: der Bildzaehler beim letzten Zaehlen

WR_BILDER = $000050             ; Kern: Bildzaehler (bilder in kern.asm), unteres Byte

WR_SPALTEN = 40                 ; die Ansicht (KA_SPALTEN, KA_ZEILEN)
WR_ZEILEN  = 18
WR_OBEN    = 8                  ; ihre erste Bildzeile
WR_UNTEN   = WR_OBEN + WR_ZEILEN * 8   ; die erste Bildzeile unter ihr
WR_DARUNTER = 8                 ; so viele Bildzeilen unter der Karte rollen noch nach unten (die Kopfzeile
                                ;   der Kachelauswahl; dort ist nichts anzuklicken)
WR_SX_MAX  = 64 - WR_SPALTEN
WR_SY_MAX  = 32 - WR_ZEILEN
WR_STREIFEN_X = 2               ; so breit ist der Randstreifen links und rechts (Punkte)
WR_STREIFEN_Y = 4               ;   und so hoch oben und unten
WR_WARTEN  = 20                 ; Bilder am Rand, bevor es rollt (eine Drittelsekunde)
WR_TEMPO   = 4                  ; danach alle so viele Bilder eine Kachel
WR_AUS     = $ff                ; WR_ZAEHLER: nach einer Pfeiltaste, bis der Zeiger den Streifen verlaesst
WR_OEFFNEN = $ff                ; A: der Reiter wird geoeffnet
WR_RECHTS = 1                   ; Richtungen (Bits)
WR_LINKS  = 2
WR_HOCH   = 4
WR_RUNTER = 8

WR_A_SX   = $00C010             ; PINSEL: Rollen der Ebenen A und B
WR_A_SY   = $00C012
WR_B_SX   = $00C030
WR_B_SY   = $00C032

ws_rollen
	php
	rep #$10
	sep #$20
	.as
	.xl
	pha
	phy
	cmp #WR_OEFFNEN
	bne +
	sta WR_ZAEHLER              ; (= WR_AUS) liegt der Zeiger schon am Rand, rollt
	jmp _register               ; es erst, wenn er ihn einmal verlassen hat
+	ldy #WR_RECHTS              ; Pfeiltaste -> Richtung in Y
	cmp #$1c
	beq +
	ldy #WR_LINKS
	cmp #$1d
	beq +
	ldy #WR_HOCH
	cmp #$1e
	beq +
	ldy #WR_RUNTER
	cmp #$1f
	bne _maus
+	jsr wr_anwenden
	lda #WR_AUS                 ; mit den Tasten gerollt: am Rand erst wieder,
	sta WR_ZAEHLER              ; wenn der Zeiger ihn einmal verlassen hat
_maus
	ldy #0                      ; Y = Richtungen, an deren Rand der Zeiger steht
	rep #$20
	.al
	lda WR_MY
	cmp #WR_UNTEN + WR_DARUNTER
	bcs _zone                   ; der Zeiger ist unterhalb: nichts
	cmp #WR_OBEN + WR_STREIFEN_Y
	bcs +
	ldy #WR_HOCH                ; oben: die Reiterzeile und der Streifen der Karte
+	cmp #WR_UNTEN - WR_STREIFEN_Y
	bcc +
	ldy #WR_RUNTER              ; unten: der Streifen und die Zeile unter der Karte
+	cmp #WR_OBEN
	bcc _zone                   ; links und rechts nur in der Karte selbst
	cmp #WR_UNTEN
	bcs _zone
	lda WR_MX
	cmp #WR_STREIFEN_X
	bcs +
	iny
	iny                         ; + WR_LINKS
+	cmp #WR_SPALTEN * 8 - WR_STREIFEN_X
	bcc _zone
	iny                         ; + WR_RECHTS
_zone
	sep #$20
	.as
	tya
	bne +
	stz WR_ZAEHLER              ; nicht am Rand: das Warten beginnt von vorn
	bra _register
+	lda WR_MT                   ; mit gedrueckter Maustaste rollt nichts: wer am
	and #$03                    ; Rand malt, zoege sonst einen Streifen durch die
	bne _register               ; Karte. Das Warten laeuft danach weiter
	lda @l WR_BILDER            ; gezaehlt wird einmal je Bild
	cmp WR_BILD
	beq _register
	sta WR_BILD
	lda WR_ZAEHLER
	cmp #WR_AUS
	beq _register               ; angehalten (Pfeiltaste)
	inc a
	cmp #WR_WARTEN
	bcc +
	jsr wr_anwenden
	lda #WR_WARTEN - WR_TEMPO
+	sta WR_ZAEHLER
_register                       ; Spalte WR_SX, Zeile WR_SY in Bildzeile WR_OBEN (beide Ebenen)
	rep #$20
	.al
	lda WR_SX
	and #$00ff
	asl a
	asl a
	asl a
	sta @l WR_A_SX
	sta @l WR_B_SX
	sep #$20
	.as
	lda WR_SY
	asl a
	asl a
	asl a
	sec
	sbc #WR_OBEN
	sta @l WR_A_SY
	sta @l WR_B_SY
	ply
	pla
	plp
	rtl

; Um eine Kachel in jede Richtung aus Y rollen, soweit die Karte reicht
; (A 8 Bit: tya holt nur das untere Byte)
wr_anwenden
	.as
	.xl
	tya
	and #WR_RECHTS
	beq +
	lda WR_SX
	cmp #WR_SX_MAX
	bcs +
	inc WR_SX
+	tya
	and #WR_LINKS
	beq +
	lda WR_SX
	beq +
	dec WR_SX
+	tya
	and #WR_HOCH
	beq +
	lda WR_SY
	beq +
	dec WR_SY
+	tya
	and #WR_RUNTER
	beq +
	lda WR_SY
	cmp #WR_SY_MAX
	bcs +
	inc WR_SY
+	rts
