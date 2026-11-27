;============================================================================
;  BRUN "name"[,laufwerk] - ein Programm (MER-Datei) laden und starten
;
;  Laedt die Datei an die Ladeadresse aus ihrem MER-Kopf und ruft sie dort
;  per JSL auf (zurueck mit RTL), wie der Fernstart. Anders als der
;  Fernstart geht es danach im BASIC weiter, auch mitten in einem Programm:
;  Ein Maschinenprogramm darf die ganze Bank 0 ab $2000 benutzen (65C816-
;  Programme laden meist nach $2000, mitten in den BASIC-Code), darum
;  rettet BRUN vorher
;    $00:2000-$BFFF  BASIC-Code, frei, BASIC-Erweiterung
;    $00:0000-$000F  Bruecken     $00:0055-$00FF  direkte Seite von BASIC
;    $00:0300-$03FF  Seite 3 (Interrupt-Haken, Eingabezeile, Grafikwerte)
;  in die Bank BR_BANK des Zusatzspeichers und holt sie danach zurueck.
;  Danach wie beim Fernstart: nur der Bildende-Interrupt, PFORTE still,
;  Anzeige zurueckgesetzt (Text, ohne zu loeschen; ORGEL still).
;
;  Einsprung $FF:402D (JSL) direkt aus BASIC, im Emulationsmodus mit
;  Datenbank 1: Name ueber P_TLEN_M / P_TPTR_M (Text in Bank 1), Laufwerk
;  als Wert 0 (P_ANZ_M, P_WERT_M; ohne: STD_LW).
;  Zurueck (RTL, wieder im Emulationsmodus, Register wie vorher):
;  A = 0 gut, 2-9 Fehler des DOS, 1 kein Zusatzspeicher, 9 Name falsch.
;============================================================================

BR_BANK    = $E7                ; Sicherung (frei im Zusatzspeicher; $E0 hat SPIELMACHER)
BR_SIEGEL  = $E71000            ; Spiegel-Schalter (1 Byte), Ergebnis (1 Byte)
BR_ERGEB   = $E71001
BR_STD_LW  = $16FF              ; Laufwerk, wenn keins angegeben ist
BR_SYS     = $C800              ; SYSTEM: Bit 0 SPIEGEL
BR_PIN_EN  = $C00B
BR_PIN_ST  = $C00C
BR_PFO_ST  = $C104
BR_PFO_EN  = $C105
BR_PFO_TA  = $C116
BR_PFO_TB  = $C11A
BR_ANZEIGE = $00FFCA            ; Kern: Anzeige zuruecksetzen (JSL)
BR_DOS     = $FF4000

brun_befehl
	php
	phb
	phd
	clc
	xce                         ; nativ
	rep #$10
	.xl
	sep #$20
	.as
	pea $0000
	pld                         ; direkte Seite 0
	lda #0
	pha
	plb                         ; Datenbank 0
	jsr pl_speicher             ; ohne Zusatzspeicher keine Sicherung
	bcs +
	lda #1
	jmp _raus
	; Name und Laufwerk in den Parameterblock des DOS
+	lda P_TLEN_M
	beq _name_f
	cmp #17
	bcs _name_f
	sta D_TLEN
	ldx P_TPTR_M
	ldy #0
-	lda @l $010000,x
	sta D_TEXT,y
	inx
	iny
	tya
	cmp D_TLEN
	bne -
	lda #'M'                    ; ohne Endung: .MER
	sta D_ENDUNG
	lda #'E'
	sta D_ENDUNG+1
	lda #'R'
	sta D_ENDUNG+2
	lda BR_STD_LW
	ldx P_ANZ_M
	beq +
	lda P_WERT_M
+	sta D_LW
	lda #$ff                    ; an die Adresse aus dem MER-Kopf
	sta D_ADR
	sta D_ADR+1
	sta D_ADR+2
	sta D_LAENGE
	sta D_LAENGE+1
	sta D_LAENGE+2
	stz D_LAENGE+3
	; Bank 0 retten
	#akku16
	ldx #$2000
	ldy #$2000
	lda #$9fff
	mvn #$00,#BR_BANK
	ldx #$0000
	ldy #$0000
	lda #$00ff
	mvn #$00,#BR_BANK
	ldx #$0300
	ldy #$0300
	lda #$00ff
	mvn #$00,#BR_BANK
	#akku8
	lda #0
	pha
	plb
	lda BR_SYS
	sta @l BR_SIEGEL
	stz BR_SYS                  ; Spiegel aus, solange das Programm laeuft
	; laden und starten
	lda #0
	jsl BR_DOS
	cmp #0
	bne _zurueck
	phk
	pea _nach-1
	jml [D_ADR]
_nach
	rep #$10
	.xl
	sep #$20
	.as
	pea $0000
	pld
	lda #0
	pha
	plb
	jsl BR_ANZEIGE
	lda #0
_zurueck
	; A = Ergebnis; erst die Interrupts ruhig, dann Bank 0 zurueck (der
	; Haken in Seite 3 zeigt sonst vielleicht noch ins Programm)
	sei
	sta @l BR_ERGEB
	lda #$01
	sta BR_PIN_ST
	sta BR_PIN_EN
	lda #$03
	sta BR_PIN_ST
	stz BR_PFO_EN
	stz BR_PFO_TA
	stz BR_PFO_TB
	lda #$07
	sta BR_PFO_ST
	#akku16
	ldx #$0300
	ldy #$0300
	lda #$00ff
	mvn #BR_BANK,#$00
	ldx #$2000
	ldy #$2000
	lda #$9fff
	mvn #BR_BANK,#$00
	ldx #$0000
	ldy #$0000
	lda #$000f
	mvn #BR_BANK,#$00
	ldx #$0055
	ldy #$0055
	lda #$00ff-$55
	mvn #BR_BANK,#$00
	#akku8
	lda @l BR_SIEGEL
	sta BR_SYS
	lda @l BR_ERGEB
	bra _raus
_name_f
	lda #9
_raus
	sec
	xce                         ; zurueck in den Emulationsmodus
	pld
	plb
	plp
	rtl
