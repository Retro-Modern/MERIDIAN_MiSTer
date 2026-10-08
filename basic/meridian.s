;============================================================================
;  MERIDIAN BASIC - Microsoft BASIC 1.1 fuer den MERIDIAN 816 (Etappe 8)
;
;  Grundlage ist Microsofts Originalquelle von 1978 (BASIC M6502 8K VER 1.1,
;  Copyright Microsoft, seit 2025 unter MIT-Lizenz), maschinell uebersetzt
;  mit werkzeuge/m10.py und angepasst mit werkzeuge/anpassen.py.
;
;  BASIC laeuft im Emulationsmodus des 65816 - die CPU verhaelt sich dort
;  wie ein 6502, der Originalcode laeuft unveraendert. Zeropage ab $55
;  (darunter liegt der Kern), Code ab ROMLOC.
;
;  Speicher: Der Code laeuft in Bank 0; Programm, Variablen und
;  Zeichenketten liegen in Bank 1 (Datenbank, ab RAMLOC). Dort steht auch
;  eine Kopie des Codes, aus der er seine Tabellen liest. Der Spiegel
;  (SYSTEM $C800) blendet $0000-$1FFF aus Bank 0 in Bank 1 ein: Zeropage,
;  Stapel und Eingabepuffer sind fuer BASIC dieselben wie fuer den Kern.
;  Chipregister nur mit langer Adresse (@l) ansprechen!
;  Ein- und Ausgabe ueber die Bruecken des Kerns ab $FFA0.
;============================================================================

	.cpu "65816"
	.as
	.xs

; Bruecken des Kerns (Aufruf im Emulationsmodus)
K_CHROUT  = $FFA0               ; Zeichen ausgeben
K_ZEILE   = $FFA3               ; Zeile nach BUF lesen (mit 0 abgeschlossen)
K_GETIN   = $FFA6               ; Taste holen, A = 0: keine
K_STOPP   = $FFA9               ; A = 3, wenn Esc gedrueckt wurde
K_MONITOR = $FFAC               ; in den Maschinensprache-Monitor
K_MODUS   = $FFAF               ; A = 40 oder 80 Zeichen
K_GRAFIK  = $FFB2               ; A = 0 Grafik aus, sonst an
K_PUNKT   = $FFB5               ; Punkt (Werte ab P_X)
K_LINIE   = $FFB8               ; Linie (Werte ab P_X)
K_BEFEHL  = $FFBB               ; Befehl A (Werte ab P_WERT), A = 0: gut
K_FUNKTION = $FFBE              ; Funktion A, Wert und Ergebnis in LZ (Etappe 11)

; Werte fuer die Grafik-Bruecken (Seite 3, hinter dem Eingabepuffer)
P_X       = $0380               ; 2 Byte
P_Y       = $0382
P_X2      = $0383               ; 2 Byte
P_Y2      = $0385
P_F       = $0386               ; Zeichenfarbe
P_ANZ     = $039F               ; Befehle ab Etappe 9c: Anzahl der Werte
P_WERT    = $03A0               ;   Wert i ab P_WERT + 3*i (24 Bit, bis 8)
P_START   = $0390               ; Laufwerke (Etappe 10): Anfang und Laenge
P_LEN     = $0393               ;   fuer SAVE/LOAD
P_TLEN    = $039C               ;   Dateiname: Laenge
P_TPTR    = $039D               ;   und Adresse (in Bank 1)

M_REG     = $05                 ; Zeropage unter dem Kern
M_WELLE   = $06
M_ROH     = $07                 ; LIST: in Anfuehrungszeichen (Bit 0) oder nach REM (Bit 7)
FARBE_K   = $12                 ; Textfarbe des Kerns (Hintergrund * 16 + Vorder)
BILDER_K  = $50                 ; Bildzaehler des Kerns
ORG       = $C500               ; Klangchip ORGEL
PAL_IDX   = $C008               ; PINSEL: Palettenindex, Farbe gggg bbbb / ---- rrrr
PAL_LO    = $C009
PAL_HI    = $C00A

ABLAGE_BANK = $10                ; Bank im Zusatzspeicher fuer SAVE/LOAD
DATENBANK = 1                   ; BASICs Datenbank (Programm, Variablen)
LZ        = $00                 ; 3 Byte: langer Zeiger (Zeropage unter dem Kern)
ZAEHL     = $03                 ; 2 Byte

	.include "basic.s"

;============================================================================
;  MERIDIAN-Ergaenzungen

; Kaltstart: Speicher reicht bis ans Ende von Bank 1, keine Fragen
M_SPEICHER
	lda #$ff
	ldy #$ff
	sta MEMSIZ
	sty MEMSIZ+1
	sta FRETOP
	sty FRETOP+1
	jmp ASKAGN

; SAVE "name"[,lw]: aufs Laufwerk. SAVE ohne Namen: in den Zusatzspeicher
; (Bank ABLAGE), Kopf "MB" + Laenge. POKER = Laenge des Programms.
M_SAVE
	jsr CHRGOT
	beq _ablage
	lda #1
	sta M_REG
	jsr M_NAME
	lda TXTTAB
	sta P_START
	lda TXTTAB+1
	sta P_START+1
	lda #DATENBANK
	sta P_START+2
	lda POKER
	sta P_LEN
	lda POKER+1
	sta P_LEN+1
	lda #0
	sta P_LEN+2
	lda #12
	sta ZAEHL
	jmp M_RUFEN
_ablage
	jsr M_ABLAGE
	ldy #0
	lda #'M'
	sta [LZ],y
	iny
	lda #'B'
	sta [LZ],y
	iny
	lda POKER
	sta [LZ],y
	iny
	lda POKER+1
	sta [LZ],y
	lda #4
	sta LZ
	jsr M_TEXTZ
	ldy #0
-	lda ZAEHL
	ora ZAEHL+1
	beq +
	lda (INDEX),y
	sta [LZ],y
	jsr M_WEITER
	jmp -
+	lda #<M_TSAVED
	ldy #>M_TSAVED
	jmp STROUT

; LOAD "name"[,lw]: vom Laufwerk. LOAD ohne Namen: aus dem Zusatzspeicher.
; Laenge nach POKER, Programm nach TXTTAB
M_LOAD
	jsr CHRGOT
	beq _ablage
	lda #1
	sta M_REG
	jsr M_NAME
	lda TXTTAB
	sta P_START
	lda TXTTAB+1
	sta P_START+1
	lda #DATENBANK
	sta P_START+2
	sec                         ; hoechstens bis 1 KB vor das Ende
	lda MEMSIZ
	sbc TXTTAB
	sta P_LEN
	lda MEMSIZ+1
	sbc TXTTAB+1
	sbc #4
	sta P_LEN+1
	lda #0
	sta P_LEN+2
	lda #13
	sta ZAEHL
	jsr M_RUFEN
	lda P_LEN
	sta POKER
	lda P_LEN+1
	sta POKER+1
	rts
_ablage
	jsr M_ABLAGE
	ldy #0
	lda [LZ],y
	cmp #'M'
	bne _fehlt
	iny
	lda [LZ],y
	cmp #'B'
	bne _fehlt
	iny
	lda [LZ],y
	sta POKER
	iny
	lda [LZ],y
	sta POKER+1
	lda #4
	sta LZ
	jsr M_TEXTZ
	ldy #0
-	lda ZAEHL
	ora ZAEHL+1
	beq +
	lda [LZ],y
	sta (INDEX),y
	jsr M_WEITER
	jmp -
+	rts
_fehlt
	jmp FCERR

M_ABLAGE                        ; LZ = ABLAGE:0000
	lda #0
	sta LZ
	sta LZ+1
	lda #ABLAGE_BANK
	sta LZ+2
	rts

M_TEXTZ                         ; INDEX = TXTTAB, ZAEHL = POKER
	lda TXTTAB
	sta INDEX
	lda TXTTAB+1
	sta INDEX+1
	lda POKER
	sta ZAEHL
	lda POKER+1
	sta ZAEHL+1
	rts

M_WEITER                        ; beide Zeiger +1, Zaehler -1
	inc INDEX
	bne +
	inc INDEX+1
+	inc LZ
	bne +
	inc LZ+1
+	lda ZAEHL
	bne +
	dec ZAEHL+1
+	dec ZAEHL
	rts

M_TSAVED
	.text "SAVED", 0                ; READY. setzt den Zeilenumbruch

;============================================================================
;  Eigene Schluesselwortliste
;
;  Microsoft durchsucht seine Liste mit einem 8-Bit-Index, sie darf also
;  hoechstens 256 Bytes lang sein. Die MERIDIAN-Befehle stehen deshalb in
;  einer zweiten Liste; ihre Token folgen auf das letzte Microsoft-Token GO.
;  Die Microsoft-Liste wird zuerst durchsucht: kein MERIDIAN-Befehl darf mit
;  einem Microsoft-Wort beginnen (FORMAT waere als FOR + MAT gelesen
;  worden, daher HEADER; WAIT gibt es schon, daher PAUSE).

	.cerror ERRTAB-RESLST > 256, "Microsofts Schluesselwortliste ist laenger als 256 Bytes"

M_RESLST
	.shift "MONITOR"
	.shift "CLS"
	.shift "COLOR"
	.shift "MODE"
	.shift "GRAPHIC"
	.shift "PLOT"
	.shift "LINE"
	.shift "SOUND"
	.shift "SILENCE"
	.shift "PAUSE"
	.shift "PALETTE"
	.shift "BLIT"
	.shift "STAMP"
	.shift "SPRITE"
	.shift "PATTERN"
	.shift "SAMPLE"
	.shift "GRADIENT"
	.shift "DIR"
	.shift "SCRATCH"
	.shift "BLOAD"
	.shift "BSAVE"
	.shift "HEADER"
	.shift "DRIVE"
	.shift "PLAY"                ; Etappe 11: PLAY und MOUSE sind Befehle,
	.shift "MOUSE"               ; MOUSE bis CLOCK Funktionen (zusammenhaengend,
	.shift "JOY"                 ; ab M_ERSTE)
	.shift "KEY"
	.shift "HIT"
	.shift "CLOCK"
	.shift "NET$"                ; Etappe 12: NET$ vor NET (sonst verdeckt NET es)
	.shift "NET"
	.shift "ELSE"                ; Etappe 13: Programmsteuerung
	.shift "WHILE"
	.shift "WEND"
	.shift "REPEAT"
	.shift "UNTIL"
	.shift "RENUMBER"            ; Etappe 13b: Zeilen neu nummerieren
	.shift "SONG"                ; MERIDIAN 1.0: TAKTSTOCK-Songs (Befehl und Funktion)
	.shift "SHINE"               ; MERIDIAN 1.0, PINSEL-Look: Glanz, Leuchten, Tusche
	.shift "GLOW"
	.shift "INK"
	.byte 0
M_RESENDE

	.cerror M_RESENDE-M_RESLST > 256, "MERIDIAN-Schluesselwortliste ist laenger als 256 Bytes"

M_STMDSP
	.word M_MONITOR-1, M_CLS-1, M_FARBE-1, M_MODUS-1, M_GRAFIK-1
	.word M_PUNKT-1, M_LINIE-1, M_KLANG-1, M_STILLE-1, M_WARTE-1
	.word M_PALETTE-1, M_KOPIERE-1, M_STEMPEL-1, M_SPRITE-1, M_MUSTER-1
	.word M_SAMPLE-1, M_VERLAUF-1, M_KATALOG-1, M_ENTFERNE-1, M_LADE-1
	.word M_SICHERE-1, M_LEERE-1, M_LAUFWERK-1, M_PLAY-1, M_MAUS-1
	.word SNERR-1, SNERR-1, SNERR-1, SNERR-1, SNERR-1   ; JOY KEY HIT CLOCK NET$
	.word M_NET-1
	.word REM-1, M_WHILE-1, M_WEND-1, M_REPEAT-1, M_UNTIL-1  ; ELSE: Rest der Zeile weg
	.word M_RENUMBER-1, M_SONG-1
	.word M_SHINE-1, M_GLOW-1, M_INK-1
M_ANZAHL = (* - M_STMDSP) / 2
M_ERSTE  = 24                   ; Token-Index von MOUSE, der ersten Funktion
M_FANZ   = 7                    ; MOUSE JOY KEY HIT CLOCK NET$ NET

; Etappe 13: Token der Programmsteuerung (Index in der Liste: ELSE ist 31)
ELSETK   = GOTK+1+31
WHILETK  = ELSETK+1
WENDTK   = ELSETK+2
REPEATTK = ELSETK+3
UNTILTK  = ELSETK+4
IFTK     = GOTOTK+2             ; Microsofts Liste: GOTO RUN IF
RUNTK    = GOTOTK+1
STOPTK   = REMTK+1              ; Microsofts Liste: REM STOP
SONGTK   = GOTK+1+37            ; MERIDIAN 1.0
	.cerror M_ANZAHL != 41, "Liste geaendert: ELSE muss Eintrag 31 bleiben, SONG 37"

	.cerror GOTK+M_ANZAHL > $ff, "zu viele Token"

; Umwandeln (CRUNCH): die Microsoft-Liste ist zu Ende, X zeigt auf das Wort,
; COUNT zaehlt weiter - das ergibt die Token nach GO
M_SUCHE
	ldy #0
_vergl
	lda BUFOFS,x
	sec
	sbc M_RESLST,y
	beq _gleich
	cmp #$80                    ; letzter Buchstabe gleich: gefunden
	bne _anders
	ora COUNT
	cmp #ELSETK                 ; ELSE beginnt einen eigenen Befehl
	bne +
	jmp M_KRUNCH_ELSE
+	jmp GETBPT
_gleich
	iny
	inx
	bra _vergl
_anders
	ldx TXTPTR                  ; naechstes Wort
	inc COUNT
-	iny
	lda M_RESLST-1,y
	bpl -
	lda M_RESLST,y
	bne _vergl
	lda BUFOFS,x                ; kein Schluesselwort: Zeichen uebernehmen
	jmp GETBPT

; Ausfuehren: A = Token - ENDTK, Carry gesetzt
M_GONE
	sbc #GOTK-ENDTK+1
	cmp #M_ANZAHL
	bcc +
	jmp SNERR
+	asl a
	tay
	lda M_STMDSP+1,y
	pha
	lda M_STMDSP,y
	pha
	jmp CHRGET

; LIST: Zeichen in A. Microsoft listet jedes Byte ab $80 als Token - auch
; Umlaute in Texten. Hier nur ausserhalb von Anfuehrungszeichen und vor REM.
M_QPLOP
	cmp #'"'
	bne +
	pha
	lda M_ROH
	eor #$01
	sta M_ROH
	pla
	jmp PLOOP
+	cmp #$80
	bcc _roh
	ldx M_ROH
	bne _roh
	cmp #REMTK
	bne +
	ldx #$80                    ; Rest der Zeile wie geschrieben
	stx M_ROH
	jmp QPLOP2
+	cmp #GOTK+1
	bcs +
	jmp QPLOP2                  ; Microsoft-Token
+	cmp #GOTK+1+M_ANZAHL
	bcs _roh                    ; kein Token
	sbc #GOTK-1                 ; Carry geloescht: 1 = erster MERIDIAN-Befehl
	tax
	sty LSTPNT
	ldy #$ff
_suche
	dex
	beq _wort
-	iny
	lda M_RESLST,y
	bpl -
	bra _suche
_wort
	iny
	lda M_RESLST,y
	bmi _ende
	jsr OUTDO
	bra _wort
_ende
	jmp PRIT4
_roh
	jmp PLOOP

;============================================================================
;  MERIDIAN-Befehle

M_MONITOR                       ; MONITOR
	jmp K_MONITOR

M_CLS                           ; CLS
	lda #0
	sta TRMPOS
	lda #12
	jmp K_CHROUT

M_FARBE                         ; COLOR v[,h]
	jsr GETBYT
	txa
	and #$0f
	sta M_REG
	lda FARBE_K
	and #$f0
	ora M_REG
	sta FARBE_K
	jsr CHRGOT
	cmp #','
	bne +
	jsr COMBYT
	txa
	asl a
	asl a
	asl a
	asl a
	sta M_REG
	lda FARBE_K
	and #$0f
	ora M_REG
	sta FARBE_K
+	rts

M_MODUS                         ; MODE 40 | 80
	jsr GETBYT
	txa
	cmp #40
	beq +
	cmp #80
	beq +
	jmp FCERR
+	sta LINWID
	jsr K_MODUS
	lda #0
	sta TRMPOS
	rts

M_GRAFIK                        ; GRAPHIC 1 | 0
	jsr GETBYT
	txa
	jsr K_GRAFIK
	lda #1
	sta P_F
	rts

M_PUNKT                         ; PLOT x,y[,f]
	jsr M_XY
	jsr M_FARBWAHL
	jmp K_PUNKT

M_LINIE                         ; LINE x1,y1,x2,y2[,f]
	jsr M_XY
	jsr CHKCOM
	jsr FRMNUM
	jsr GETADR
	lda POKER
	sta P_X2
	lda POKER+1
	sta P_X2+1
	jsr COMBYT
	stx P_Y2
	jsr M_FARBWAHL
	jmp K_LINIE

M_XY                            ; x (16 Bit) , y (Byte)
	jsr FRMNUM
	jsr GETADR
	lda POKER
	sta P_X
	lda POKER+1
	sta P_X+1
	jsr COMBYT
	stx P_Y
	rts

M_FARBWAHL                      ; [,f]
	jsr CHRGOT
	cmp #','
	bne +
	jsr COMBYT
	stx P_F
+	rts

M_KLANG                         ; SOUND stimme,hz[,welle]
	jsr GETBYT
	dex
	cpx #4
	bcc +
	jmp FCERR
+	txa
	asl a
	asl a
	asl a
	asl a
	sta M_REG
	jsr CHKCOM
	jsr FRMNUM
	lda #<M_HZ                  ; Hz * 16,777216 = ORGEL-Frequenzwert
	ldy #>M_HZ
	jsr FMULT
	jsr GETADR
	lda #$10                    ; Dreieck
	sta M_WELLE
	jsr CHRGOT
	cmp #','
	bne +
	jsr COMBYT
	dex
	cpx #4
	bcc ++
	jmp FCERR
+	jmp _setzen
+	lda M_WELLEN,x
	sta M_WELLE
_setzen
	ldx M_REG
	lda M_WELLE
	sta @l ORG+4,x                 ; Gate aus: neu anschlagen
	lda POKER
	ora POKER+1
	beq +                       ; 0 Hz: nur ausklingen lassen
	lda POKER
	sta @l ORG+0,x
	lda POKER+1
	sta @l ORG+1,x
	lda #0
	sta @l ORG+2,x
	lda #8
	sta @l ORG+3,x                 ; Puls 50 %
	lda #$08
	sta @l ORG+5,x                 ; Attack 2 ms, Decay 300 ms
	lda #$c8
	sta @l ORG+6,x                 ; Sustain 12, Release 300 ms
	lda #15
	sta @l ORG+7,x
	lda #$ff
	sta @l ORG+8,x
	lda M_WELLE
	ora #$01
	sta @l ORG+4,x                 ; Gate an
+	rts

M_WELLEN                        ; 1 Dreieck, 2 Saege, 3 Puls, 4 Rauschen
	.byte $10, $20, $40, $80
M_HZ                            ; 16,777216 als Gleitkommazahl
	.byte $85, $06, $37, $bd, $06

M_STILLE                        ; SILENCE (der Kern haelt auch PLAY an)
	lda #16
	jmp K_BEFEHL

M_WARTE                         ; PAUSE n (Bilder)
	jsr GETBYT
	txa
	beq +
-	lda BILDER_K
-	cmp BILDER_K
	beq -
	dex
	bne --
+	rts

M_PALETTE                       ; PALETTE n,r,g,b (Anteile 0-15)
	jsr GETBYT
	stx M_REG
	jsr COMBYT
	txa
	and #$0f
	sta M_WELLE                 ; rot
	jsr COMBYT
	txa
	asl a
	asl a
	asl a
	asl a
	sta ZAEHL                   ; gruen
	jsr COMBYT
	txa
	and #$0f
	ora ZAEHL                   ; blau
	pha
	lda M_REG
	sta @l PAL_IDX
	pla
	sta @l PAL_LO
	lda M_WELLE
	sta @l PAL_HI
	rts

; PEEK, POKE, WAIT: Adresse bis 16 MB nach LZ (langer Zeiger)
M_GETNUM
	jsr FRMNUM
	jsr M_ADR24
	jmp COMBYT

M_ADR24                         ; ohne Vorzeichen
	lda FACSGN
	bmi M_FEHLER
M_INT24                         ; mit Vorzeichen (Zweierkomplement)
	lda FACEXP
	cmp #$99                    ; ab 2^24: zu gross
	bcs M_FEHLER
	jsr QINT
	lda FACLO
	sta LZ
	lda FACMO
	sta LZ+1
	lda FACMOH
	sta LZ+2
	rts
M_FEHLER
	jmp FCERR

; FRE: freie Bytes ohne Vorzeichen (A = hoch, Y = niedrig)
M_FREI
	ldx #0
	stx VALTYP
	sta FACHO
	sty FACHO+1
	ldx #$90
	sec                         ; positiv
	jmp FLOATC

; Befehle ab Etappe 9c: BASIC liest nur die Zahlen, die Arbeit macht der
; Kern (Bruecke K_BEFEHL, Nummer in A)
M_KOPIERE                       ; BLIT von,nach,laenge
	ldx #3
	ldy #0
	bra M_ALLG
M_STEMPEL                       ; STAMP adr,x,y,b,h
	ldx #5
	ldy #1
	bra M_ALLG
M_SPRITE                        ; SPRITE n[,x,y[,muster[,bits]]]
	ldx #5
	ldy #2
	bra M_ALLG
M_SAMPLE                        ; SAMPLE k[,adr,laenge[,hz[,laut[,schleife]]]]
	ldx #6
	ldy #4
	bra M_ALLG
M_VERLAUF                       ; GRADIENT [z1,r1,g1,b1,z2,r2,g2,b2]
	ldx #8
	ldy #5
M_ALLG
	stx M_REG
	sty ZAEHL
	jsr M_ARGS
M_RUFEN
	lda ZAEHL
	jsr K_BEFEHL
	cmp #0
	beq +
	cmp #2
	bcs M_DOSFEHLER
	jmp FCERR
+	rts

; Fehler des DOS (2-9) als eigene Meldung, weiter wie Microsofts ERROR
M_DOSFEHLER                     ; A = Fehler 2-9; den Text gibt der Kern aus
	sta P_WERT                  ; (seit Etappe 12, das spart Platz im ROM)
	lsr CNTWFL
	jsr CRDO
	jsr OUTQST
	lda #18
	jsr K_BEFEHL
	jmp TYPERR

; Etappe 11: MOUSE 1[,sprite] / MOUSE 0 - Mauszeiger; PLAY - Musik
M_MAUS
	ldx #2
	ldy #14
	jmp M_ALLG
M_PLAY                          ; PLAY "noten"[,stimme]
	ldx #1
	ldy #15
	jmp M_DATEI

; Funktionen MOUSE(n), JOY(n), KEY(c), HIT(n), CLOCK(n): Token nach GO in
; einem Ausdruck (EVAL4 springt hierher). Der Kern rechnet; Wert und
; Ergebnis stehen als 24-Bit-Zahl mit Vorzeichen in LZ.
M_FUNKTION
	sec
	sbc #GOTK+1+M_ERSTE
	cmp #SONGTK-GOTK-1-M_ERSTE  ; SONG(n): Kernfunktion 8
	bne +
	lda #8
	bra _wert
+	cmp #M_FANZ
	bcc +
	jmp SNERR                   ; GO oder ein Befehl
+	cmp #5                      ; NET$: Text
	beq M_NETTEXT
	bcc _wert
	lda #5                      ; NET(k): Kernfunktion 5
_wert
	pha
	jsr CHRGET
	jsr PARCHK                  ; ( Ausdruck )
	jsr CHKNUM
	jsr M_INT24
	pla
	jsr K_FUNKTION
	lda LZ+2                    ; Ergebnis -> FAC
	sta FACHO
	lda LZ+1
	sta FACMOH
	lda LZ
	sta FACMO
	lda #0
	sta FACLO
	sta VALTYP
	ldx #$98                    ; 2^24
	lda FACHO
	eor #$ff
	rol a                       ; Carry: positiv
	lda #0
	jmp FLOATB

; MERIDIAN 1.0: SONG "name"[,laufwerk] spielt einen TAKTSTOCK-Song im
; Hintergrund, SONG STOP haelt ihn an (Kern 19 und 20, Abspieler im ROM)
M_SONG
	cmp #STOPTK
	bne +
	jsr CHRGET
	lda #20
	jmp K_BEFEHL
+	ldx #1
	ldy #19
	jmp M_DATEI

; Etappe 12: NET "befehl"[,kanal] - der Netzdienst draht.py erledigt es
M_NET
	ldx #1
	ldy #17
	jmp M_DATEI

; NET$(k): naechste Zeile von Kanal k (k = 0: Meldung zum letzten Befehl)
M_NETTEXT
	jsr CHRGET
	jsr PARCHK
	jsr CHKNUM
	jsr M_INT24
	lda #6                      ; Kern: Zeile holen, Laenge -> LZ
	jsr K_FUNKTION
	lda LZ
	jsr STRSPA                  ; Platz in Bank 1
	lda DSCTMP+1
	sta LZ
	lda DSCTMP+2
	sta LZ+1
	lda #7                      ; Kern: Text dorthin
	jsr K_FUNKTION
	jmp PUTNEW

; Laufwerke (Etappe 10)
M_KATALOG                       ; DIR [laufwerk]
	ldx #1
	ldy #8
	bra M_ALLG2
M_LAUFWERK                      ; DRIVE n
	ldx #1
	ldy #11
M_ALLG2
	jmp M_ALLG
M_LADE                          ; BLOAD "name"[,adresse[,laufwerk]]
	ldx #2
	ldy #6
	bra M_DATEI
M_SICHERE                       ; BSAVE "name",adresse,laenge[,laufwerk]
	ldx #3
	ldy #7
	bra M_DATEI
M_ENTFERNE                      ; SCRATCH "name"[,laufwerk]
	ldx #1
	ldy #9
	bra M_DATEI
M_LEERE                         ; HEADER "name"[,laufwerk]
	ldx #1
	ldy #10
M_DATEI
	stx M_REG
	sty ZAEHL
	jsr M_NAME
	jmp M_RUFEN

M_NAME                          ; "name" nach P_TLEN/P_TPTR, dann [,Zahlen]
	jsr FRMEVL
	jsr FRESTR                  ; A = Laenge, X/Y = Adresse
	sta P_TLEN
	stx P_TPTR
	sty P_TPTR+1
	jsr CHRGOT
	cmp #','
	bne +
	jsr CHRGET
	jmp M_ARGS
+	lda #0
	sta P_ANZ
	rts

M_MUSTER                        ; PATTERN m,zeile,"16 Hexziffern"
	ldx #2
	stx M_REG
	ldy #3
	sty ZAEHL
	jsr M_ARGS
	jsr CHKCOM
	jsr FRMEVL
	jsr FRESTR                  ; A = Laenge, X/Y = Adresse (in Bank 1)
	sta P_WERT+6
	stx P_WERT+7
	sty P_WERT+8
	jmp M_RUFEN

; Bis zu M_REG Zahlen (durch Komma getrennt) nach P_WERT, Anzahl nach P_ANZ
M_ARGS
	lda #0
	sta M_WELLE
	jsr CHRGOT
	beq _ende                   ; keine Werte
_wert
	jsr FRMNUM
	jsr M_INT24
	lda M_WELLE
	asl a
	adc M_WELLE
	tax
	lda LZ
	sta P_WERT,x
	lda LZ+1
	sta P_WERT+1,x
	lda LZ+2
	sta P_WERT+2,x
	inc M_WELLE
	lda M_WELLE
	cmp M_REG
	beq _ende
	jsr CHRGOT
	cmp #','
	bne _ende
	jsr CHRGET
	jmp _wert
_ende
	lda M_WELLE
	sta P_ANZ
	rts

BASIC_ENDE

	.cerror BASIC_ENDE > RAMLOC, "BASIC-Code reicht in den Programmspeicher"

;============================================================================
;  ERWEITERUNG (Etappe 13): ELSE, WHILE/WEND, REPEAT/UNTIL
;
;  Das BASIC-ROM bis $47FF ist voll. Weiterer Code steht deshalb in Bank 0
;  ab ERWEITERUNG ($B800-$BFFF); der Kern kopiert ihn dorthin, aber nicht in
;  Bank 1 - dort liegen an derselben Stelle Programm und Variablen. Hier
;  darf also nur Code stehen, der nichts aus seinem eigenen Bereich liest
;  (keine Tabellen, keine Texte; bankpruefung.py wacht darueber).
;
;  Schleifen legen wie FOR und GOSUB einen Rahmen auf den Stapel:
;    Token (WHILE/REPEAT), Zeilennummer (2), Textzeiger (2)
;  WHILE merkt sich den Anfang der Bedingung, REPEAT die Stelle dahinter.
;============================================================================

ERWEITERUNG = $B800

	* = ERWEITERUNG

; ELSE beim Umwandeln: ELSE muss einen eigenen Befehl beginnen, damit PRINT
; und die anderen Befehle davor ordentlich enden. Steht davor kein ":", setzt
; BASIC eines ein (wie beim C128: IF A THEN PRINT 1:ELSE PRINT 2).
M_KRUNCH_ELSE
	ldy BUFPTR
-	cpy #4                      ; Anfang der Zeile: nichts davor
	beq _gut
	lda BUF-5,y
	cmp #' '
	bne +
	dey
	bne -
+	cmp #':'
	beq _gut
	ldy BUFPTR
	iny
	lda #':'
	sta BUF-5,y
	sty BUFPTR
_gut
	lda #ELSETK
	jmp GETBPT

; IF ist falsch: im Rest der Zeile nach dem passenden ELSE suchen. Jedes IF
; dazwischen bringt sein eigenes ELSE mit (X zaehlt sie). Ohne ELSE geht es
; in der naechsten Zeile weiter - wie bisher.
M_WENN_NEIN
	ldx #0
	ldy #0
_naechstes
	lda (TXTPTR),y
	beq _ende
	iny
	cmp #'"'
	beq _text
	cmp #REMTK
	beq _rest
	cmp #DATATK
	beq _daten
	cmp #IFTK
	bne +
	inx
	bra _naechstes
+	cmp #ELSETK
	bne _naechstes
	dex
	bpl _naechstes
	dey                         ; gefunden: TXTPTR auf ELSE
	jsr ADDON
	jsr CHRGET                  ; dahinter: Zeilennummer oder Befehl
	jmp DOCOND
_text
-	lda (TXTPTR),y
	beq _ende
	iny
	cmp #'"'
	bne -
	bra _naechstes
_daten                          ; DATA endet beim ":" ausserhalb von Text
-	lda (TXTPTR),y
	beq _ende
	cmp #':'
	beq _naechstes
	iny
	cmp #'"'
	bne -
-	lda (TXTPTR),y
	beq _ende
	iny
	cmp #'"'
	bne -
	bra --
_rest
-	lda (TXTPTR),y
	beq _ende
	iny
	bra -
_ende
	jmp ADDON                   ; TXTPTR auf das Zeilenende

; WHILE bedingung: ist sie wahr, Rahmen auf den Stapel und weiter; sonst
; hinter das passende WEND springen.
M_WHILE
	lda #3
	jsr GETSTK
	lda TXTPTR+1                ; Anfang der Bedingung
	pha
	lda TXTPTR
	pha
	jsr FRMEVL
	lda FACEXP
	beq _falsch
	pla
	tay
	pla
	tax
	pla                         ; Ruecksprung nach NEWSTT weg (wie FOR)
	pla
	txa
	pha
	tya
	pha
	lda CURLIN+1
	pha
	lda CURLIN
	pha
	lda #WHILETK
	pha
	jmp NEWSTT
_falsch
	pla
	pla
	jmp M_ZUM_WEND

; WEND: Bedingung des WHILE noch einmal pruefen. Wahr: hinter der Bedingung
; weiter (der Rahmen bleibt), falsch: Rahmen weg, hinter WEND weiter.
M_WEND
	tsx
	lda $103,x
	cmp #WHILETK
	beq +
	lda #10                     ; WEND WITHOUT WHILE
	jmp M_DOSFEHLER
+	lda TXTPTR+1                ; Stelle hinter WEND merken
	pha
	lda TXTPTR
	pha
	lda CURLIN+1
	pha
	lda CURLIN
	pha
	tsx
	lda $108,x                  ; Rahmen: Zeile und Bedingung
	sta CURLIN
	lda $109,x
	sta CURLIN+1
	lda $10A,x
	sta TXTPTR
	lda $10B,x
	sta TXTPTR+1
	jsr FRMEVL
	lda FACEXP
	beq _fertig
	pla
	pla
	pla
	pla
	rts
_fertig
	pla
	sta CURLIN
	pla
	sta CURLIN+1
	pla
	sta TXTPTR
	pla
	sta TXTPTR+1
	jmp M_RAHMEN_WEG

; Ruecksprung und Rahmen (5 Byte) vom Stapel, weiter mit dem naechsten Befehl
M_RAHMEN_WEG
	tsx
	txa
	clc
	adc #7
	tax
	txs
	jmp NEWSTT

; REPEAT: Rahmen auf den Stapel, weiter
M_REPEAT
	lda #3
	jsr GETSTK
	pla
	pla
	lda TXTPTR+1
	pha
	lda TXTPTR
	pha
	lda CURLIN+1
	pha
	lda CURLIN
	pha
	lda #REPEATTK
	pha
	jmp NEWSTT

; UNTIL bedingung: falsch - zurueck hinter REPEAT; wahr - Rahmen weg, weiter
M_UNTIL
	tsx
	lda $103,x
	cmp #REPEATTK
	beq +
	lda #12                     ; UNTIL WITHOUT REPEAT
	jmp M_DOSFEHLER
+	jsr FRMEVL
	lda FACEXP
	bne M_RAHMEN_WEG
	tsx
	lda $104,x
	sta CURLIN
	lda $105,x
	sta CURLIN+1
	lda $106,x
	sta TXTPTR
	lda $107,x
	sta TXTPTR+1
	rts

; WHILE war gleich zu Beginn falsch: das passende WEND suchen, auch ueber
; Zeilen hinweg (Texte, REM und DATA ueberspringen, innere WHILE zaehlen).
M_ZUM_WEND
	lda CURLIN+1                ; fuer die Fehlermeldung
	pha
	lda CURLIN
	pha
	ldx #0
_lies
	ldy #0
	lda (TXTPTR),y
	bne _zeichen
	jsr _zeile
	bra _weiter
_zeichen
	cmp #'"'
	beq _text
	cmp #REMTK
	beq _rest
	cmp #DATATK
	beq _daten
	cmp #WHILETK
	bne +
	inx
	bra _weiter
+	cmp #WENDTK
	bne _weiter
	dex
	bpl _weiter
	pla                         ; gefunden
	pla
	jmp CHRGET                  ; hinter WEND; RTS fuehrt nach NEWSTT
_weiter
	jsr _plus1
	bra _lies
_text                           ; bis zum naechsten "
-	jsr _plus1
	lda (TXTPTR),y
	beq _lies
	cmp #'"'
	bne -
	bra _weiter
_rest                           ; bis zum Zeilenende
-	jsr _plus1
	lda (TXTPTR),y
	bne -
	bra _lies
_daten                          ; bis ":" ausserhalb von Text
-	jsr _plus1
	lda (TXTPTR),y
	beq _lies
	cmp #':'
	beq _lies
	cmp #'"'
	bne -
-	jsr _plus1
	lda (TXTPTR),y
	beq _lies
	cmp #'"'
	bne -
	bra --

_plus1
	inc TXTPTR
	bne +
	inc TXTPTR+1
+	rts

_zeile                          ; Zeilenende: naechste Zeile oder Programmende
	ldy #2
	lda (TXTPTR),y
	beq _fehlt
	iny
	lda (TXTPTR),y
	sta CURLIN
	iny
	lda (TXTPTR),y
	sta CURLIN+1
	tya
	clc
	adc TXTPTR
	sta TXTPTR
	bcc +
	inc TXTPTR+1
+	ldy #0
	rts
_fehlt
	pla                         ; Ruecksprung aus _zeile
	pla
	pla                         ; Zeile des WHILE fuer die Meldung
	sta CURLIN
	pla
	sta CURLIN+1
	lda #11                     ; WHILE WITHOUT WEND
	jmp M_DOSFEHLER

; FNDFOR (FOR, NEXT, RETURN) geht ueber WHILE- und REPEAT-Rahmen hinweg:
; RETURN aus einer Schleife heraus raeumt sie mit ab.
M_FFANDERE
	cmp #WHILETK
	beq +
	cmp #REPEATTK
	bne _ende
+	txa
	clc
	adc #5
	tax
	jmp FFLOOP
_ende
	rts


;============================================================================
; RENUMBER [neu[,schritt[,ab]]] (Etappe 13): Zeilen ab "ab" (Vorgabe: die
; erste) bekommen die Nummern neu, neu+schritt, ... (Vorgabe 10, 10); alle
; Verweise darauf (GOTO, GOSUB, THEN, ELSE, RUN, ON ... GOTO/GOSUB, GO TO)
; ziehen mit. Wie beim C128: Ein Verweis auf eine Zeile, die es nicht gibt,
; bricht ab, bevor sich etwas aendert (?UNDEF'D STATEMENT ERROR IN zeile).
;
; Die Zahlen stehen als Text im Programm und koennen laenger werden, das
; Programm waechst also. Ablauf:
;  1. CLR - der Platz der Variablen wird gebraucht.
;  2. Oben im Speicher eine Tabelle der alten Zeilennummern (mit $FFFF am
;     Ende): neue Nummer = Platz in der Tabelle.
;  3. Probelauf: prueft alle Verweise, misst, wie weit das neue Programm
;     dem alten vorauslaeuft (schreibt nichts).
;  4. Das Programm rutscht nach oben, direkt unter die Tabelle.
;  5. Schreiblauf: von oben nach unten zurueckkopieren und dabei Nummern und
;     Verweise ersetzen - der Schreibzeiger holt den Lesezeiger nie ein.
;  6. Zeilen neu verketten, READY.

RN_NEU   = $0368                ; Arbeitsplatz in Seite 3 (hinter BASICs
RN_SCHR  = $036A                ; Eingabepuffer; ueber den Spiegel auch mit
RN_AB    = $036C                ; Datenbank 1 erreichbar)
RN_TAB   = $036E                ; Tabelle der alten Nummern
RN_ZAHL  = $0370
RN_NEUZ  = $0372
RN_NUM   = $0374                ; naechste neue Zeilennummer
RN_PLUS  = $0376                ; groesster Vorsprung Schreib- vor Lesezeiger
RN_ZEILE = $0378                ; alte Nummer der Zeile in Arbeit
RN_MODUS = $037A                ; 0 Probelauf, 1 schreiben
RN_ZST   = $037B                ; Bit 0 Text, 1 REM, 2 DATA, 3 nach GO, 7 Ziffer da
RN_ART   = $037C                ; 1 eine Zeilennummer, 2 eine Liste
RN_T     = $037D                ; 2 Byte
RN_R     = $00                  ; Lesezeiger (Zeropage unter BASIC)
RN_W     = $03                  ; Schreibzeiger
RN_Z     = $05                  ; Tabelle

M_RENUMBER
	lda #10
	sta RN_NEU
	sta RN_SCHR
	lda #0
	sta RN_NEU+1
	sta RN_SCHR+1
	sta RN_AB
	sta RN_AB+1
	jsr CHRGOT
	beq _los
	jsr LINGET
	lda LINNUM
	sta RN_NEU
	lda LINNUM+1
	sta RN_NEU+1
	jsr CHRGOT
	beq _los
	jsr CHKCOM
	jsr LINGET
	lda LINNUM
	sta RN_SCHR
	lda LINNUM+1
	sta RN_SCHR+1
	jsr CHRGOT
	beq _los
	jsr CHKCOM
	jsr LINGET
	lda LINNUM
	sta RN_AB
	lda LINNUM+1
	sta RN_AB+1
	jsr CHRGOT
	beq _los
	jmp SNERR
_los
	lda RN_SCHR
	ora RN_SCHR+1
	bne +
	jmp FCERR                   ; Schritt 0
+	jsr CLEARC                  ; Variablen weg (auch der Stapel ist frisch)
	; 2. Tabelle: Zeilen zaehlen, Platz oben im Speicher
	lda MEMSIZ                  ; RN_TAB = MEMSIZ + 1 - 2 (Endmarke)
	sec
	sbc #1
	sta RN_TAB
	lda MEMSIZ+1
	sbc #0
	sta RN_TAB+1
	jsr rn_r_anfang
_zaehlen
	ldy #1                      ; je Zeile 2 Byte
	lda (RN_R),y
	beq _gezaehlt
	lda RN_TAB
	sec
	sbc #2
	sta RN_TAB
	bcs +
	dec RN_TAB+1
+	jsr rn_weiter
	bra _zaehlen
_gezaehlt
	lda RN_TAB                  ; passt sie ueber das Programm?
	sec
	sbc VARTAB
	lda RN_TAB+1
	sbc VARTAB+1
	bcs +
	jmp OMERR
+	jsr rn_z_tab                ; Tabelle fuellen
	jsr rn_r_anfang
_fuellen
	ldy #1
	lda (RN_R),y
	beq _gefuellt
	iny
	lda (RN_R),y
	ldy #0
	sta (RN_Z),y
	ldy #3
	lda (RN_R),y
	ldy #1
	sta (RN_Z),y
	jsr rn_z2
	jsr rn_weiter
	bra _fuellen
_gefuellt
	lda #$ff                    ; Endmarke
	ldy #0
	sta (RN_Z),y
	iny
	sta (RN_Z),y
	; Reihenfolge: die letzte Zeile vor "ab" muss unter "neu" liegen
	jsr rn_z_tab
_vorher
	jsr rn_eintrag_ab           ; C = 1: Eintrag >= ab (oder Endmarke)
	bcs _probe
	ldy #0                      ; Eintrag < neu?
	lda (RN_Z),y
	cmp RN_NEU
	iny
	lda (RN_Z),y
	sbc RN_NEU+1
	bcc +
	jmp FCERR
+	jsr rn_z2
	bra _vorher
_probe
	; 3. Probelauf
	lda #0
	sta RN_MODUS
	sta RN_PLUS
	sta RN_PLUS+1
	jsr rn_r_anfang
	lda RN_R
	sta RN_W
	lda RN_R+1
	sta RN_W+1
	jsr rn_lauf
	; 4. Programm nach oben: RN_T = RN_TAB - (VARTAB - TXTTAB)
	lda VARTAB
	sec
	sbc TXTTAB
	sta RN_ZAHL                 ; Laenge
	lda VARTAB+1
	sbc TXTTAB+1
	sta RN_ZAHL+1
	lda RN_TAB
	sec
	sbc RN_ZAHL
	sta RN_T
	lda RN_TAB+1
	sbc RN_ZAHL+1
	sta RN_T+1
	lda RN_T                    ; Luecke = RN_T - TXTTAB muss den Vorsprung
	sec                         ; plus 3 fassen
	sbc TXTTAB
	tax
	lda RN_T+1
	sbc TXTTAB+1
	tay
	txa
	sec
	sbc RN_PLUS
	tax
	tya
	sbc RN_PLUS+1
	bcc _voll                   ; Luecke < Vorsprung
	bne _platz                  ; >= 256 mehr: reicht
	cpx #3
	bcs _platz
_voll
	jmp OMERR
_platz
	lda VARTAB                  ; rueckwaerts kopieren: VARTAB-1 -> RN_TAB-1
	sta RN_R
	lda VARTAB+1
	sta RN_R+1
	lda RN_TAB
	sta RN_W
	lda RN_TAB+1
	sta RN_W+1
_schieben
	lda RN_ZAHL
	ora RN_ZAHL+1
	beq _geschoben
	jsr rn_r_minus
	jsr rn_w_minus
	ldy #0
	lda (RN_R),y
	sta (RN_W),y
	lda RN_ZAHL                 ; Zaehler - 1
	bne +
	dec RN_ZAHL+1
+	dec RN_ZAHL
	bra _schieben
_geschoben
	; 5. Schreiblauf
	lda #1
	sta RN_MODUS
	lda RN_T
	sta RN_R
	lda RN_T+1
	sta RN_R+1
	lda TXTTAB
	sta RN_W
	lda TXTTAB+1
	sta RN_W+1
	jsr rn_lauf
	; 6. Ende des Programms, verketten, READY
	lda RN_W
	sta VARTAB
	lda RN_W+1
	sta VARTAB+1
	jsr RUNC
	jsr LNKPRG
	jmp READY

rn_r_anfang                     ; RN_R = TXTTAB
	lda TXTTAB
	sta RN_R
	lda TXTTAB+1
	sta RN_R+1
	rts

rn_z_tab                        ; RN_Z = RN_TAB
	lda RN_TAB
	sta RN_Z
	lda RN_TAB+1
	sta RN_Z+1
	rts

; Ein Lauf durch das Programm ab RN_R; schreibt nach RN_W (RN_MODUS = 1)
rn_lauf
	lda RN_NEU
	sta RN_NUM
	lda RN_NEU+1
	sta RN_NUM+1
_zeile
	ldy #1
	lda (RN_R),y
	bne +
	lda #0                      ; Programmende: Verkettung 0
	jsr rn_aus
	lda #0
	jmp rn_aus
+	jsr rn_lies                 ; Verkettung (LNKPRG rechnet sie neu)
	jsr rn_aus
	jsr rn_lies
	jsr rn_aus
	jsr rn_lies                 ; Zeilennummer
	sta RN_ZEILE
	jsr rn_lies
	sta RN_ZEILE+1
	lda RN_ZEILE                ; ab "ab": die naechste neue Nummer
	cmp RN_AB
	lda RN_ZEILE+1
	sbc RN_AB+1
	bcc _alt
	lda RN_NUM+1                ; hoechstens 63999 ($F9FF)
	cmp #$fa
	bcc +
	jmp FCERR
+	lda RN_NUM
	jsr rn_aus
	lda RN_NUM+1
	jsr rn_aus
	lda RN_NUM
	clc
	adc RN_SCHR
	sta RN_NUM
	lda RN_NUM+1
	adc RN_SCHR+1
	sta RN_NUM+1
	bcc +
	lda #$ff                    ; uebergelaufen: die naechste meldet es
	sta RN_NUM+1
+	bra _text
_alt
	lda RN_ZEILE
	jsr rn_aus
	lda RN_ZEILE+1
	jsr rn_aus
_text
	lda #0
	sta RN_ZST
_zeichen
	jsr rn_lies
	jsr rn_aus
	cmp #0
	beq _zeile
	tax
	lda RN_ZST
	lsr a
	bcc _nicht_text
	cpx #'"'                    ; in Anfuehrungszeichen
	bne _zeichen
	lda RN_ZST
	and #$fe
	sta RN_ZST
	bra _zeichen
_nicht_text
	cpx #'"'
	bne +
	lda RN_ZST
	ora #$01
	sta RN_ZST
	bra _zeichen
+	lsr a                       ; nach REM: nichts mehr
	bcs _zeichen
	lsr a
	bcc _nicht_data
	cpx #':'                    ; DATA endet beim ":"
	bne _zeichen
	lda RN_ZST
	and #$fb
	sta RN_ZST
	bra _zeichen
_nicht_data
	cpx #' '                    ; Leerzeichen aendern nichts (GO TO)
	beq _zeichen
	lsr a                       ; Bit 3: das Token davor war GO
	php
	lda RN_ZST
	and #$f7
	sta RN_ZST
	plp
	bcc +
	cpx #TOTK                   ; GO TO
	beq _liste
+	cpx #REMTK
	bne +
	lda #$02
	bra _setzen
+	cpx #DATATK
	bne +
	lda #$04
	bra _setzen
+	cpx #GOTK
	bne +
	lda #$08
_setzen
	ora RN_ZST
	sta RN_ZST
	bra _zeichen
+	cpx #GOTOTK
	beq _liste
	cpx #GOSUTK
	beq _liste
	cpx #THENTK
	beq _eine
	cpx #ELSETK
	beq _eine
	cpx #RUNTK
	bne _zeichen
_eine
	lda #1
	bra +
_liste
	lda #2
+	sta RN_ART
	jsr rn_verweis
	jmp _zeichen

; Hinter GOTO usw.: Zeilennummer(n) ersetzen
rn_verweis
_nochmal
	jsr rn_leer
	cmp #'0'
	bcc _fertig
	cmp #'9'+1
	bcs _fertig
	lda #0
	sta RN_ZAHL
	sta RN_ZAHL+1
-	ldy #0                      ; Ziffern lesen
	lda (RN_R),y
	sec
	sbc #'0'
	cmp #10
	bcs +
	pha
	jsr rn_r_plus
	jsr rn_mal10
	pla
	clc
	adc RN_ZAHL
	sta RN_ZAHL
	bcc -
	inc RN_ZAHL+1
	bra -
+	jsr rn_suche
	bcc +
	lda RN_ZEILE                ; gibt es nicht: abbrechen (Probelauf)
	sta CURLIN
	lda RN_ZEILE+1
	sta CURLIN+1
	ldx #ERRUS
	jmp ERROR
+	jsr rn_ziffern
	lda RN_W                    ; Vorsprung = W - R (mit Vorzeichen)
	sec
	sbc RN_R
	tax
	lda RN_W+1
	sbc RN_R+1
	bmi _liste                  ; zurueckgefallen
	cmp RN_PLUS+1
	bcc _liste
	bne _mehr
	cpx RN_PLUS
	bcc _liste
_mehr
	stx RN_PLUS
	sta RN_PLUS+1
_liste
	lda RN_ART                  ; ON ... GOTO a,b,c
	cmp #2
	bne _fertig
	jsr rn_leer
	cmp #','
	bne _fertig
	jsr rn_lies
	jsr rn_aus
	bra _nochmal
_fertig
	rts

rn_leer                         ; Leerzeichen kopieren; A = naechstes Zeichen
-	ldy #0
	lda (RN_R),y
	cmp #' '
	bne +
	jsr rn_lies
	jsr rn_aus
	bra -
+	rts

rn_mal10                        ; RN_ZAHL * 10
	lda RN_ZAHL
	ldx RN_ZAHL+1
	asl RN_ZAHL
	rol RN_ZAHL+1
	asl RN_ZAHL
	rol RN_ZAHL+1
	clc
	adc RN_ZAHL
	sta RN_ZAHL
	txa
	adc RN_ZAHL+1
	sta RN_ZAHL+1
	asl RN_ZAHL
	rol RN_ZAHL+1
	rts

; Neue Nummer der alten Zeile RN_ZAHL -> RN_NEUZ; C = 1: gibt es nicht
rn_suche
	jsr rn_z_tab
	lda RN_NEU
	sta RN_NEUZ
	lda RN_NEU+1
	sta RN_NEUZ+1
_eintrag
	ldy #1
	lda (RN_Z),y
	cmp #$ff                    ; Ende der Tabelle
	beq _nein
	cmp RN_ZAHL+1
	bcc _kleiner
	bne _nein                   ; schon groesser: gibt es nicht
	dey
	lda (RN_Z),y
	cmp RN_ZAHL
	bcc _kleiner
	bne _nein
	lda RN_ZAHL                 ; gefunden; unter "ab" bleibt die Nummer
	cmp RN_AB
	lda RN_ZAHL+1
	sbc RN_AB+1
	bcs +
	lda RN_ZAHL
	sta RN_NEUZ
	lda RN_ZAHL+1
	sta RN_NEUZ+1
+	clc
	rts
_kleiner
	jsr rn_eintrag_ab
	bcc +
	lda RN_NEUZ
	clc
	adc RN_SCHR
	sta RN_NEUZ
	lda RN_NEUZ+1
	adc RN_SCHR+1
	sta RN_NEUZ+1
+	jsr rn_z2
	bra _eintrag
_nein
	sec
	rts

rn_eintrag_ab                   ; C = 1, wenn der Eintrag bei RN_Z >= ab ist
	ldy #0
	lda (RN_Z),y
	cmp RN_AB
	iny
	lda (RN_Z),y
	sbc RN_AB+1
	rts

; RN_NEUZ dezimal ausgeben (ohne fuehrende Nullen)
rn_ziffern
	lda RN_ZST
	and #$7f
	sta RN_ZST
	lda #<10000
	ldx #>10000
	jsr rn_stelle
	lda #<1000
	ldx #>1000
	jsr rn_stelle
	lda #100
	ldx #0
	jsr rn_stelle
	lda #10
	ldx #0
	jsr rn_stelle
	lda RN_NEUZ
	ora #'0'
	jmp rn_aus

rn_stelle                       ; Teiler in A/X: Ziffer zaehlen und ausgeben
	sta RN_ZAHL
	stx RN_ZAHL+1
	ldy #'0'
-	lda RN_NEUZ
	sec
	sbc RN_ZAHL
	tax
	lda RN_NEUZ+1
	sbc RN_ZAHL+1
	bcc +
	sta RN_NEUZ+1
	stx RN_NEUZ
	iny
	bra -
+	tya
	cmp #'0'
	bne +
	bit RN_ZST                  ; fuehrende Null weglassen
	bpl ++
+	jsr rn_aus
	lda RN_ZST
	ora #$80
	sta RN_ZST
+	rts

rn_lies                         ; A = Byte bei RN_R, RN_R + 1
	ldy #0
	lda (RN_R),y
rn_r_plus
	inc RN_R
	bne +
	inc RN_R+1
+	rts

rn_aus                          ; A schreiben (nur im Schreiblauf), RN_W + 1
	ldy RN_MODUS
	beq +
	ldy #0
	sta (RN_W),y
+	inc RN_W
	bne +
	inc RN_W+1
+	rts

rn_weiter                       ; RN_R auf die naechste Zeile (Verkettung)
	ldy #0
	lda (RN_R),y
	tax
	iny
	lda (RN_R),y
	sta RN_R+1
	stx RN_R
	rts

rn_z2
	lda RN_Z
	clc
	adc #2
	sta RN_Z
	bcc +
	inc RN_Z+1
+	rts

rn_r_minus
	lda RN_R
	bne +
	dec RN_R+1
+	dec RN_R
	rts

rn_w_minus
	lda RN_W
	bne +
	dec RN_W+1
+	dec RN_W
	rts

; MERIDIAN 1.0, PINSEL-Look: SHINE c,y,r,g,b (Glanz), GLOW s[,c ...]
; (Leuchten), INK c[,dx,dy[,b]] (Tusche) - die Arbeit macht der Kern
; (Befehle 21-23); ohne Werte schaltet jeder seinen Teil aus
M_SHINE
	ldx #5
	ldy #21
	jmp M_ALLG
M_GLOW
	ldx #8
	ldy #22
	jmp M_ALLG
M_INK
	ldx #4
	ldy #23
	jmp M_ALLG

ERW_ENDE

	.cerror ERW_ENDE > $C000, "BASIC-Erweiterung reicht in die Chips"
