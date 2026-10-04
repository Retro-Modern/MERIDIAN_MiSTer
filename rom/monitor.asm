;============================================================================
;  MONITOR - Maschinensprache-Monitor im Stil von SMON (Etappe 13)
;
;  Liegt im System-ROM (Bank $FF ab $4000, neben DOS, MUSIK und NETZ). Der
;  Kern liest die Zeile unter dem Cursor (Bildschirmeditor wie beim C64)
;  nach EINGABE und ruft MON_BEFEHL ($FF:400C); Ausgaben gehen ueber die
;  langen Einspruenge des Kerns ab $FFC1 (JSL, zurueck mit RTL).
;
;  Neu gegenueber dem Monitor im Kern (bis Etappe 12):
;   A a         Assembler fuer den 65C816 (Operandengroesse nach der Zahl
;               der Ziffern: $12 Direktseite, $1234 absolut, $123456 lang;
;               #$12 ist 8 Bit, #$1234 16 Bit)
;   D [a [e]]   Disassembler (verfolgt REP/SEP fuer die Akku-/Indexbreite)
;   ,a ...      eine Zeile des Disassemblers aendern: neu uebersetzen
;   R / ;...    Register zeigen / aendern (nach BRK oder Einzelschritt)
;   G           ohne Adresse: mit den Registern weiter, wo es stand
;   W [n]       Einzelschritt (mit Hilfe der Hardware, siehe SYSTEM Bit 1)
;   H a e ..    Bytes oder "Text" suchen      C a e z  Bereiche vergleichen
;   L/S/DIR     Laden, Speichern, Inhaltsverzeichnis
;   $ # %       Zahlen umrechnen (hex, dezimal, binaer)
;
;  Konvention: Akku 8 Bit, Indexregister 16 Bit, direkte Seite 0 (die des
;  Kerns), Datenbank 0. Eigene Tabellen und Texte stehen hier in Bank $FF
;  und werden nur lang gelesen (ROM+marke); JSR (a,X) liest aus Bank $FF.
;============================================================================

; Lange Einspruenge des Kerns (JSL, zurueck mit RTL)
K_CHROUT   = $00FFC1
K_GETIN    = $00FFC4
K_MODUS    = $00FFC7
K_ANZEIGE  = $00FFCA
K_CURAUS   = $00FFCD
K_STOPP    = $00FFD0            ; A = 3: Esc gedrueckt
K_KATALOG  = $00FFD3
K_DOSTEXT  = $00FFD6            ; Text zum DOS-Fehler A
K_BASIC    = $00FFD9            ; (JML) zurueck ins BASIC
K_HAUPT    = $00FFDC            ; (JML) Hauptschleife: auf Eingaben warten
K_EMU_RTI  = $00FFDF            ; (JML) SEC, XCE, RTI - aus Bank 0 (siehe dort)

; Direkte Seite des Kerns (Seite 0)
k_cur_x    = $10
k_farbe    = $12
k_spalten  = $15
k_blink    = $29                ; blink_frei: der Cursor blinkt
k_ein_pos  = $2A                ; 16 Bit
k_arg1     = $2C                ; 3 Byte
k_arg2     = $30
k_arg3     = $34
k_anzahl   = $3A                ; 16 Bit
k_sprung   = $3E                ; 3 Byte
k_wert     = $42                ; 3 Byte
k_bpz      = $48                ; Bytes je Speicherzeile (8/16)

EINGABE    = $0210              ; Zeile des Bildschirmeditors (mit 0)
KOPIER     = $0270              ; Stummel fuer MVN/MVP
BILDSCHIRM = $0400
ZEILEN     = 30
SYSTEM     = $00C800            ; Bit 0 SPIEGEL, Bit 1 SCHRITT (Etappe 13)
P_ANZ      = $039F
STD_LW     = $16FF

; Eigene Variablen in Bank 0: Seite 2 hinter VERBUND ($02B0-$02DF), der
; Puffer zwischen NETZ ($17C0) und MUSIK ($17F0; MUSIK belegt auch $1780-$17BF,
; je Stimme 16 Byte), drei Bytes im freien Teil der DOS-Seite ($176A)
mo_flags   = $02B0              ; Disassembler: Bit 5 M, Bit 4 X (1 = 8 Bit)
mo_op      = $02B1
mo_mn      = $02B2
mo_art     = $02B3
mo_len     = $02B4              ; Laenge des Befehls
mo_bytes   = $02B5              ; 4 Byte
mo_pp      = $02B9              ; 16 Bit: Schreibstelle im Puffer
mo_ziff    = $02BB              ; Ziffern der letzten Zahl
mo_vor     = $02BC              ; Assembler: Vorsatz ('#', '(', '[', 'A', 0)
mo_ns      = $02BD              ; Assembler: Nachsatz (Nummer)
mo_zz      = $02BE
mo_w2      = $02BF              ; Blockbefehl: zweite Bank
; Abzug der Register ($02C0-$02CF)
r_pc       = $02C0              ; 3 Byte (mit Bank)
r_a        = $02C3
r_x        = $02C5
r_y        = $02C7
r_s        = $02C9
r_d        = $02CB
r_b        = $02CD
r_p        = $02CE
r_e        = $02CF
mo_w1      = $02D0              ; 3 Byte: Operand
mo_grund   = $02D3              ; 0 BRK, 1 Schritt (+$80: Emulationsmodus)
mo_sys     = $02D4              ; SPIEGEL beim Halt
mo_schritte = $02D5             ; 16 Bit: noch zu gehende Schritte
mo_vorpc   = $02D7              ; 3 Byte: PC vor dem Schritt
mo_vorp    = $02DA              ; P vor dem Schritt
mo_dweiter = $02DB              ; 3 Byte: D ohne Adresse macht hier weiter
mo_tmp     = $02DE              ; 16 Bit
mo_puf     = $17C8              ; 40 Byte: eine Ausgabezeile (bis $17EF)
mo_amodus  = $176A              ; 1: zuletzt "A aaaaaa " angeboten
mo_avor    = $176B              ; ... vor diesem Befehl
mo_spalte  = $176C              ; mo_zeilenrest: Spalte am Anfang
MO_PUFLEN  = 40

; Adressierungsarten und Tabellen (tools/opcodes.py)
	.include "opcodes.inc"

aus	.macro                      ; Zeichen in A ausgeben
	jsl K_CHROUT
	.endm

;----------------------------------------------------------------------------
; Einsprung vom Kern: Zeile in EINGABE ausfuehren

mon_befehl
	.as
	.xl
	phb
	phd
	pea 0
	pld
	lda #0
	pha
	plb
	lda mo_amodus               ; wurde eben "A aaaaaa " angeboten?
	sta mo_avor
	stz mo_amodus
	ldy #0
	jsr mo_leer
	sty k_ein_pos
	ldx #mo_befehle
_eintrag
	lda ROM,x
	cmp #$ff
	beq _unbekannt
	stx mo_tmp
	ldy k_ein_pos
_vgl
	lda ROM,x
	beq _wortende
	cmp EINGABE,y
	bne _weiter
	inx
	iny
	bra _vgl
_wortende
	#akku16
	txa
	sec
	sbc mo_tmp
	cmp #2
	#akku8
	bcc _treffer                ; ein Zeichen: Zahlen duerfen folgen
	lda EINGABE,y
	beq _treffer
	cmp #' '
	beq _treffer
_weiter
	ldx mo_tmp
-	lda ROM,x
	beq +
	inx
	bra -
+	inx
	inx
	inx
	bra _eintrag
_treffer
	sty k_ein_pos
	jsr (1,x)                   ; Adresse hinter der 0 (aus Bank $FF)
	bra _ende
_unbekannt
	jsr mo_fehler
_ende
	sep #$20
	rep #$10
	.as
	.xl
	pld
	plb
	rtl

mo_befehle
	.text "BASIC", 0
	.word mo_basic
	.text "MODE", 0
	.word mo_modus
	.text "COLOR", 0
	.word mo_farbe
	.text "CHARS", 0
	.word mo_zeichen
	.text "HELP", 0
	.word mo_hilfe
	.text "DIR", 0
	.word mo_dir
	.text "M", 0
	.word mo_m
	.text ":", 0
	.word mo_doppelpunkt
	.text "D", 0
	.word mo_d
	.text ",", 0
	.word mo_komma
	.text "A", 0
	.word mo_a
	.text "R", 0
	.word mo_r
	.text ";", 0
	.word mo_strichpunkt
	.text "G", 0
	.word mo_g
	.text "W", 0
	.word mo_w
	.text "F", 0
	.word mo_f
	.text "T", 0
	.word mo_t
	.text "C", 0
	.word mo_c
	.text "H", 0
	.word mo_h
	.text "L", 0
	.word mo_l
	.text "S", 0
	.word mo_s
	.text "X", 0
	.word mo_basic
	.text "$", 0
	.word mo_hexzahl
	.text "#", 0
	.word mo_dezzahl
	.text "%", 0
	.word mo_binzahl
	.text "?", 0
	.word mo_hilfe
	.byte $ff

;----------------------------------------------------------------------------
; Hilfen: Ausgabe

mo_fehler                       ; "?ERROR" mit Klingel
	ldx #t_mo_fehler
mo_text                         ; Text ab X (Bank $FF, mit 0 abgeschlossen)
-	lda ROM,x
	beq +
	#aus
	inx
	bra -
+	rts

mo_cr                           ; neue Zeile, wenn der Cursor nicht schon vorn steht
	lda k_cur_x
	beq +
	lda #13
	#aus
+	rts

mo_hex8                         ; A als zwei Hexziffern
	pha
	lsr a
	lsr a
	lsr a
	lsr a
	jsr _ziffer
	pla
	and #$0f
_ziffer
	cmp #10
	bcc +
	adc #'A'-'0'-11
+	adc #'0'
	#aus
	rts

mo_adr                          ; X = Stelle in Seite 0: 24-Bit-Adresse, 6 Ziffern
	lda 2,x
	jsr mo_hex8
	lda 1,x
	jsr mo_hex8
	lda 0,x
	jmp mo_hex8

mo_leerzeichen
	lda #' '
	#aus
	rts

; Rest der Zeile mit Leerzeichen loeschen (nicht bis in die letzte Spalte,
; sonst bricht der Kern um); zurueck an die Stelle, wenn C = 1
mo_zeilenrest
	php
	lda k_cur_x
	sta mo_spalte
-	lda k_cur_x
	inc a
	cmp k_spalten
	bcs +
	jsr mo_leerzeichen
	bra -
+	plp
	bcc _ende
-	lda k_cur_x
	cmp mo_spalte
	beq _ende
	lda #$1d                    ; Cursor links
	#aus
	bra -
_ende
	rts

;----------------------------------------------------------------------------
; Hilfen: Puffer (eine Zeile, mo_puf)

mo_puf_neu
	#akku16
	stz mo_pp
	#akku8
	rts

mo_put                          ; A an den Puffer haengen
	phx
	ldx mo_pp
	sta mo_puf,x
	inx
	stx mo_pp
	plx
	rts

mo_put_hex                      ; A als zwei Hexziffern in den Puffer
	pha
	lsr a
	lsr a
	lsr a
	lsr a
	jsr _ziffer
	pla
	and #$0f
_ziffer
	cmp #10
	bcc +
	adc #'A'-'0'-11
+	adc #'0'
	jmp mo_put

mo_puf_zeigen                   ; Puffer ausgeben (bis zur 0), dann neue Zeile
	ldx #0
-	lda mo_puf,x
	beq +
	#aus
	inx
	bra -
+	clc
	jsr mo_zeilenrest
	lda #13
	#aus
	rts

;----------------------------------------------------------------------------
; Hilfen: Eingabe

mo_leer                         ; Y = Stelle in EINGABE: Leerzeichen ueberspringen
-	lda EINGABE,y
	cmp #' '
	bne +
	iny
	bra -
+	rts

mo_hexwert                      ; A = Zeichen -> Wert 0-15, C = 0; sonst C = 1
	cmp #'0'
	bcc _nein
	cmp #'9'+1
	bcc _ziffer
	cmp #'A'
	bcc _nein
	cmp #'F'+1
	bcs _nein
	sbc #'A'-11
	clc
	rts
_ziffer
	sbc #'0'-1
	clc
	rts
_nein
	sec
	rts

; Hexzahl ab k_ein_pos (davor Leerzeichen und ein "$" erlaubt) nach k_wert,
; bis 6 Ziffern; mo_ziff = Zahl der Ziffern. C = 1: keine Zahl
mo_hex
	ldy k_ein_pos
	jsr mo_leer
	lda EINGABE,y
	cmp #'$'
	bne +
	iny
+	stz k_wert
	stz k_wert+1
	stz k_wert+2
	stz mo_ziff
_ziffer
	lda EINGABE,y
	jsr mo_hexwert
	bcs _ende
	ldx #4
-	asl k_wert
	rol k_wert+1
	rol k_wert+2
	dex
	bne -
	ora k_wert
	sta k_wert
	iny
	inc mo_ziff
	lda mo_ziff
	cmp #6
	bne _ziffer
_ende
	sty k_ein_pos
	lda mo_ziff
	beq +
	clc
	rts
+	sec
	rts

mo_wert_nach                    ; k_wert -> Seite 0 ab X
	lda k_wert
	sta 0,x
	lda k_wert+1
	sta 1,x
	lda k_wert+2
	sta 2,x
	rts

mo_arg1                         ; Zahl nach k_arg1 (C = 1: keine)
	jsr mo_hex
	bcs +
	ldx #k_arg1
	jsr mo_wert_nach
	clc
+	rts

mo_arg2
	jsr mo_hex
	bcs +
	ldx #k_arg2
	jsr mo_wert_nach
	clc
+	rts

mo_arg3
	jsr mo_hex
	bcs +
	ldx #k_arg3
	jsr mo_wert_nach
	clc
+	rts

mo_arg1_ist_ende                ; C = 1, wenn k_arg1 > k_arg2 (24 Bit)
	lda k_arg2+2
	cmp k_arg1+2
	bne +
	#akku16
	lda k_arg2
	cmp k_arg1
	#akku8
+	beq _gleich
	bcc _drueber
	clc
	rts
_gleich
	clc
	rts
_drueber
	sec
	rts

mo_arg1_plus                    ; k_arg1 um 1 weiter (24 Bit)
	inc k_arg1
	bne +
	inc k_arg1+1
	bne +
	inc k_arg1+2
+	rts

mo_esc                          ; C = 1, wenn Esc gedrueckt wurde
	jsl K_STOPP
	cmp #3
	beq +
	clc
	rts
+	sec
	rts

;============================================================================
; Disassembler

; Eine Zeile ab k_arg1 nach mo_puf; k_arg1 danach auf den naechsten Befehl.
; Breiten aus mo_flags (REP und SEP aendern sie).
mo_dis
	jsr mo_puf_neu
	lda #','
	jsr mo_put
	lda k_arg1+2
	jsr mo_put_hex
	lda k_arg1+1
	jsr mo_put_hex
	lda k_arg1
	jsr mo_put_hex
	lda #' '
	jsr mo_put
	lda [k_arg1]
	sta mo_op
	jsr mo_op_info
	ldy #0
-	lda [k_arg1],y
	jsr mo_put_hex
	lda #' '
	jsr mo_put
	iny
	tya
	cmp mo_len
	bne -
-	lda mo_pp                   ; Mnemonic ab Spalte 20
	cmp #20
	bcs +
	lda #' '
	jsr mo_put
	bra -
+	jsr mo_put_mn
	jsr mo_put_operand
	lda #0
	jsr mo_put
	jsr mo_breiten              ; REP/SEP
	#akku16                     ; weiter
	lda mo_len
	and #$00ff
	clc
	adc k_arg1
	sta k_arg1
	#akku8
	bcc +
	inc k_arg1+2
+	rts

; REP/SEP am Ort k_arg1 aendern die angenommenen Breiten
mo_breiten
	lda mo_op
	cmp #$c2                    ; REP
	bne +
	ldy #1
	lda [k_arg1],y
	eor #$ff
	and mo_flags
	sta mo_flags
	rts
+	cmp #$e2                    ; SEP
	bne +
	ldy #1
	lda [k_arg1],y
	ora mo_flags
	sta mo_flags
+	rts

; mo_op -> mo_mn, mo_art, mo_len
mo_op_info
	#akku16
	lda mo_op
	and #$00ff
	tax
	#akku8
	lda ROM+mo_op_mn,x
	sta mo_mn
	lda ROM+mo_op_art,x
	sta mo_art
	jsr mo_art_x
	lda ROM+mo_arten+1,x        ; Art des Operanden
	jsr mo_laenge
	sta mo_len
	rts

; A = Art des Operanden (0-9) -> A = Laenge des Befehls (nach mo_flags)
mo_laenge
	cmp #4
	beq _m
	cmp #5
	beq _x
	#akku16
	and #$00ff
	tax
	#akku8
	lda ROM+_tabelle,x
	rts
_m
	lda mo_flags
	and #$20
	bra +
_x
	lda mo_flags
	and #$10
+	beq +
	lda #2                      ; 8 Bit
	rts
+	lda #3
	rts
_tabelle
	.byte 1, 2, 3, 4, 0, 0, 2, 3, 3, 1

mo_art_x                        ; X = mo_art * 3 (Eintrag in mo_arten)
	#akku16
	lda mo_art
	and #$00ff
	sta mo_tmp
	asl a
	adc mo_tmp
	tax
	#akku8
	rts

mo_put_mn                       ; Mnemonic mo_mn (drei Buchstaben)
	#akku16
	lda mo_mn
	and #$00ff
	sta mo_tmp
	asl a
	adc mo_tmp
	tax
	#akku8
	ldy #3
-	lda ROM+mo_mnemonics,x
	jsr mo_put
	inx
	dey
	bne -
	rts

; Operand nach der Art mo_art; die Bytes stehen ab [k_arg1]+1
mo_put_operand
	jsr mo_art_x
	lda ROM+mo_arten+1,x
	bne +
	rts                         ; ohne Operand
+	pha
	lda #' '
	jsr mo_put
	lda ROM+mo_arten,x          ; Vorsatz
	beq +
	jsr mo_put
+	pla
	cmp #4
	bne +
	lda mo_flags                ; nach M: 1 oder 2 Byte
	and #$20
	beq _zwei
	bra _eins
+	cmp #5
	bne +
	lda mo_flags
	and #$10
	beq _zwei
	bra _eins
+	cmp #1
	beq _eins
	cmp #2
	beq _zwei
	cmp #3
	beq _drei
	cmp #6
	beq _rel8
	cmp #7
	beq _rel16
	cmp #8
	beq _block
	lda #'A'                    ; 9: Akku
	jsr mo_put
	bra _nachsatz
_drei
	jsr _dollar
	ldy #3
	bra _bytes
_zwei
	jsr _dollar
	ldy #2
	bra _bytes
_eins
	jsr _dollar
	ldy #1
_bytes
	lda [k_arg1],y
	jsr mo_put_hex
	dey
	bne _bytes
	bra _nachsatz
_rel8                           ; Ziel = Adresse + 2 + Abstand (mit Vorzeichen)
	ldy #1
	lda [k_arg1],y
	#akku16
	and #$00ff
	cmp #$0080
	bcc +
	ora #$ff00
+	clc
	adc #2
	bra _ziel
_rel16
	ldy #1
	#akku16
	lda [k_arg1],y
	clc
	adc #3
_ziel
	.al
	clc
	adc k_arg1
	sta mo_tmp
	#akku8
	jsr _dollar
	lda mo_tmp+1
	jsr mo_put_hex
	lda mo_tmp
	jsr mo_put_hex
	bra _nachsatz
_block                          ; MVN quelle,ziel (Bytes: Befehl, Ziel, Quelle)
	jsr _dollar
	ldy #2
	lda [k_arg1],y
	jsr mo_put_hex
	lda #','
	jsr mo_put
	jsr _dollar
	ldy #1
	lda [k_arg1],y
	jsr mo_put_hex
_nachsatz
	jsr mo_art_x
	lda ROM+mo_arten+2,x
	#akku16
	and #$00ff
	asl a
	tax
	lda ROM+mo_ns_tab,x
	tax
	#akku8
-	lda ROM,x
	beq +
	jsr mo_put
	inx
	bra -
+	rts
_dollar
	lda #'$'
	jmp mo_put

;----------------------------------------------------------------------------
; D [anfang [ende]]: disassemblieren (ohne Ende 16 Zeilen, ohne Anfang weiter).
; Die Breiten (mo_flags) kommen vom letzten Halt (BRK/Schritt), aus ";" oder
; vom Assembler (REP/SEP, #$12/#$1234) - und D verfolgt REP/SEP selbst.

mo_d
	jsr mo_arg1
	bcc +
	lda mo_dweiter              ; ohne Adresse: weiter
	sta k_arg1
	lda mo_dweiter+1
	sta k_arg1+1
	lda mo_dweiter+2
	sta k_arg1+2
	bra _zeilen
+	jsr mo_arg2
	bcs _zeilen
_bereich
	jsr mo_dis
	jsr mo_puf_zeigen
	jsr mo_esc
	bcs _ende
	jsr mo_arg1_ist_ende
	bcc _bereich
	bra _ende
_zeilen
	lda #16
	sta mo_zz
-	jsr mo_dis
	jsr mo_puf_zeigen
	dec mo_zz
	bne -
_ende
	lda k_arg1
	sta mo_dweiter
	lda k_arg1+1
	sta mo_dweiter+1
	lda k_arg1+2
	sta mo_dweiter+2
	rts

;============================================================================
; Assembler

; A anfang [befehl]: Befehl uebersetzen; ohne Befehl nur die Eingabe
; "A anfang " anbieten. Nach jedem Befehl steht die Zeile disassembliert da
; und darunter die naechste Eingabe - eine leere beendet das Assemblieren.
mo_a
	jsr mo_arg1
	bcc +
	jmp mo_fehler
+	ldy k_ein_pos
	jsr mo_leer
	lda EINGABE,y
	bne +
	lda mo_avor                 ; leere Eingabe auf "A aaaaaa ": fertig
	beq mo_anbieten
	rts
+	jsr mo_asm
	bcc +
	jsr mo_fehler
	bra mo_anbieten
+	jsr mo_ueberschreiben
	; weiter in mo_anbieten

mo_anbieten                     ; "A aaaaaa " ohne Zeilenende, Rest der Zeile leer
	lda #1
	sta mo_amodus
	lda #'A'
	#aus
	jsr mo_leerzeichen
	ldx #k_arg1
	jsr mo_adr
	jsr mo_leerzeichen
	sec
	jmp mo_zeilenrest

; Die eben eingegebene Zeile durch die disassemblierte ersetzen
mo_ueberschreiben
	lda #$1e                    ; Cursor hoch
	#aus
	jsr mo_dis
	jmp mo_puf_zeigen

; ,anfang [bytes] befehl: eine Zeile des Disassemblers neu uebersetzen. Der
; Befehl steht ab Spalte 20 (wie ihn D schreibt) oder, bei kurzen Zeilen,
; gleich hinter der Adresse.
mo_komma
	jsr mo_arg1
	bcc +
	jmp mo_fehler
+	ldy #20
	ldx #0                      ; steht hinter Spalte 20 noch etwas?
-	lda EINGABE,x
	beq +
	inx
	bra -
+	cpx #21
	bcs +
	ldy k_ein_pos
+	jsr mo_asm
	bcc +
	jmp mo_fehler
+	jmp mo_ueberschreiben

; Befehl ab EINGABE,Y fuer die Adresse k_arg1 uebersetzen und dorthin
; schreiben. C = 1 bei Fehlern; sonst mo_len = Laenge (k_arg1 bleibt).
mo_asm
	jsr mo_leer
	ldx #0                      ; drei Buchstaben nach mo_bytes
-	lda EINGABE,y
	cmp #'A'
	bcc _fehler
	cmp #'Z'+1
	bcs _fehler
	sta mo_bytes,x
	iny
	inx
	cpx #3
	bne -
	lda EINGABE,y               ; dahinter Ende oder Leerzeichen
	beq +
	cmp #' '
	bne _fehler
+	sty k_ein_pos
	jsr mo_mn_suchen
	bcs _fehler
	jsr mo_operand_lesen
	bcs _fehler
	jsr mo_art_waehlen
	bcs _fehler
	jsr mo_bytes_bilden
	bcs _fehler
	ldy #0                      ; schreiben
-	lda mo_bytes,y
	sta [k_arg1],y
	iny
	tya
	cmp mo_len
	bne -
	jsr mo_breiten              ; REP/SEP und Breite des Werts merken
	lda mo_art
	cmp #A_IMM_M
	bne +
	lda #$20
	bra ++
+	cmp #A_IMM_X
	bne _gut
	lda #$10
+	sta mo_zz                   ; 2 Byte: 8 Bit (Bit setzen), 3: 16 Bit
	lda mo_len
	cmp #2
	beq +
	lda mo_zz
	eor #$ff
	and mo_flags
	bra ++
+	lda mo_zz
	ora mo_flags
+	sta mo_flags
_gut
	clc
	rts
_fehler
	sec
	rts

mo_mn_suchen                    ; mo_bytes[0..2] -> mo_mn; C = 1: unbekannt
	ldx #0
	stz mo_mn
-	lda ROM+mo_mnemonics,x
	cmp mo_bytes
	bne _weiter
	lda ROM+mo_mnemonics+1,x
	cmp mo_bytes+1
	bne _weiter
	lda ROM+mo_mnemonics+2,x
	cmp mo_bytes+2
	bne _weiter
	clc
	rts
_weiter
	inx
	inx
	inx
	inc mo_mn
	lda mo_mn
	cmp #MN_ANZAHL
	bne -
	sec
	rts

; Operand lesen: mo_vor ('#', '(', '[', 'A' Akku, 0 Zahl, 'N' keiner),
; mo_w1 (Wert), mo_ziff (Ziffern), mo_ns (Nachsatz-Nummer), mo_w2 (zweite
; Bank bei MVN/MVP, mo_vor = 'B'). C = 1 bei Fehlern.
mo_operand_lesen
	stz mo_ns
	stz mo_w1
	stz mo_w1+1
	stz mo_w1+2
	stz mo_ziff
	ldy k_ein_pos
	jsr mo_leer
	lda EINGABE,y
	bne +
	lda #'N'
	sta mo_vor
	clc
	rts
+	cmp #'A'                    ; "A" allein: Akku
	bne +
	lda EINGABE+1,y
	beq _akku
	cmp #' '
	bne +
_akku
	lda #'A'
	sta mo_vor
	clc
	rts
+	stz mo_vor
	lda EINGABE,y
	cmp #'#'
	beq _vor
	cmp #'('
	beq _vor
	cmp #'['
	bne +
_vor
	sta mo_vor
	iny
+	sty k_ein_pos
	jsr mo_hex
	bcs _fehler
	lda k_wert
	sta mo_w1
	lda k_wert+1
	sta mo_w1+1
	lda k_wert+2
	sta mo_w1+2
	; Rest ohne Leerzeichen nach mo_puf
	ldy k_ein_pos
	ldx #0
-	lda EINGABE,y
	beq +
	iny
	cmp #' '
	beq -
	sta mo_puf,x
	inx
	cpx #MO_PUFLEN-1
	bne -
+	stz mo_puf,x
	; zweite Bank (MVN $12,$34)? Hinter dem Komma eine Ziffer, "$" oder "#"
	lda mo_puf
	cmp #','
	bne _nachsatz
	lda mo_puf+1
	cmp #'$'
	beq _block
	cmp #'#'
	beq _block
	jsr mo_hexwert
	bcs _nachsatz
_block
	ldx #1
	lda mo_puf,x
	cmp #'#'
	bne +
	inx
+	lda mo_puf,x
	cmp #'$'
	bne +
	inx
+	stz mo_w2
	ldy #0
-	lda mo_puf,x
	beq +
	jsr mo_hexwert
	bcs _fehler
	asl mo_w2
	asl mo_w2
	asl mo_w2
	asl mo_w2
	ora mo_w2
	sta mo_w2
	inx
	iny
	cpy #3
	bne -
	bra _fehler                 ; mehr als zwei Ziffern
+	cpy #0
	beq _fehler
	lda mo_vor                  ; "#$12,#$34" wie bei 64tass ist auch recht
	beq +
	cmp #'#'
	bne _fehler
+	lda #'B'
	sta mo_vor
	clc
	rts
_nachsatz                       ; den Rest mit den Nachsaetzen vergleichen
	stz mo_ns
_ns
	lda mo_ns
	#akku16
	and #$00ff
	asl a
	tax
	lda ROM+mo_ns_tab,x
	tax
	#akku8
	ldy #0
-	lda ROM,x
	cmp mo_puf,y
	bne _anders
	cmp #0
	beq _gefunden
	inx
	iny
	bra -
_anders
	inc mo_ns
	lda mo_ns
	cmp #10
	bne _ns
_fehler
	sec
	rts
_gefunden
	clc
	rts

; Adressierungsart zu Mnemonic und Operand waehlen -> mo_art, mo_op
mo_art_waehlen
	lda mo_vor
	cmp #'N'                    ; ohne Operand: implizit, sonst Akku,
	bne _akku                   ; BRK/COP/WDM mit Signatur 0
	lda #A_IMP
	jsr mo_op_suchen
	bcc _gut
	lda #A_AKKU
	jsr mo_op_suchen
	bcc _gut
	lda #1
	sta mo_ziff
	lda #A_IMM8
	jsr mo_op_suchen
	bcc _gut
	bra _fehler
_akku
	cmp #'A'
	bne _block
	lda #A_AKKU
	jsr mo_op_suchen
	bcc _gut
	bra _fehler
_block
	cmp #'B'
	bne _sofort
	lda #A_BLOCK
	jsr mo_op_suchen
	bcc _gut
	bra _fehler
_sofort
	cmp #'#'
	bne _sprung
	lda mo_ns                   ; hinter dem Wert nichts mehr
	bne _fehler
	lda #A_IMM_M
	jsr mo_op_suchen
	bcc _gut
	lda #A_IMM_X
	jsr mo_op_suchen
	bcc _gut
	lda #A_IMM8
	jsr mo_op_suchen
	bcc _gut
	bra _fehler
_sprung                         ; Verzweigungen: der Wert ist das Ziel
	lda mo_vor
	ora mo_ns
	bne _groesse
	lda #A_REL
	jsr mo_op_suchen
	bcc _gut
	lda #A_RELL
	jsr mo_op_suchen
	bcc _gut
_groesse                        ; Groesse nach Ziffern: 1-2, 3-4, 5-6
	lda mo_ziff
	inc a
	lsr a                       ; 1, 2 oder 3
	sta mo_zz
	lda mo_mn                   ; JMP lang oder [abs]: JML, JSR lang: JSL
	cmp #MN_JMP
	bne +
	lda mo_zz
	cmp #3
	beq _jml
	lda mo_vor
	cmp #'['
	bne _versuch
_jml
	lda #MN_JML
	sta mo_mn
	bra _versuch
+	cmp #MN_JSR
	bne _versuch
	lda mo_zz
	cmp #3
	bne _versuch
	lda #MN_JSL
	sta mo_mn
_versuch
	jsr _art_suchen             ; Art mit Vorsatz, Groesse und Nachsatz
	bcs _groesser
	jsr mo_op_suchen
	bcc _gut
_groesser                       ; $12 geht auch als $0012 (STA $12,Y -> abs,Y)
	lda mo_zz
	cmp #3
	bcs _fehler
	inc mo_zz
	bra _versuch
_gut
	sta mo_op
	clc
	rts
_fehler
	sec
	rts

; Art mit Vorsatz mo_vor, Operandengroesse mo_zz und Nachsatz mo_ns -> A
_art_suchen
	ldx #0
	stz mo_art
-	lda ROM+mo_arten,x
	cmp mo_vor
	bne +
	lda ROM+mo_arten+1,x
	cmp mo_zz
	bne +
	lda ROM+mo_arten+2,x
	cmp mo_ns
	bne +
	lda mo_art
	clc
	rts
+	inx
	inx
	inx
	inc mo_art
	lda mo_art
	cmp #A_BLOCK+1
	bne -
	sec
	rts

; Opcode zu mo_mn und Art A suchen -> A = Opcode, mo_art = Art; C = 1: keiner
mo_op_suchen
	sta mo_art
	ldx #0
-	lda ROM+mo_op_mn,x
	cmp mo_mn
	bne +
	lda ROM+mo_op_art,x
	cmp mo_art
	bne +
	txa
	clc
	rts
+	inx
	cpx #256
	bne -
	sec
	rts

; Bytes in mo_bytes und Laenge mo_len aus mo_op, mo_art und mo_w1/mo_w2
mo_bytes_bilden
	lda mo_op
	sta mo_bytes
	lda mo_w1
	sta mo_bytes+1
	lda mo_w1+1
	sta mo_bytes+2
	lda mo_w1+2
	sta mo_bytes+3
	jsr mo_art_x
	lda ROM+mo_arten+1,x
	cmp #4
	beq _sofort
	cmp #5
	beq _sofort
	cmp #6
	beq _rel8
	cmp #7
	beq _rel16
	cmp #8
	beq _block
	cmp #1                      ; ein Byte: der Wert muss passen
	bne +
	ldx mo_w1+1
	bne _fehler
+	jsr mo_laenge
	sta mo_len
	clc
	rts
_sofort                         ; #$12: 8 Bit, #$1234: 16 Bit
	lda mo_ziff
	cmp #3
	lda #2
	bcc +
	lda #3
+	sta mo_len
	cmp #2
	bne +
	lda mo_w1+1
	bne _fehler
+	lda mo_w1+2
	bne _fehler
	clc
	rts
_block                          ; MVN quelle,ziel -> Befehl, Ziel, Quelle
	lda mo_w1+1
	bne _fehler
	lda mo_w2
	sta mo_bytes+1
	lda mo_w1
	sta mo_bytes+2
	lda #3
	sta mo_len
	clc
	rts
_rel8                           ; Abstand = Ziel - (Adresse + 2), -128..127
	jsr _bank
	bcs _fehler
	#akku16
	lda k_arg1
	clc
	adc #2
	sta mo_tmp
	lda mo_w1
	sec
	sbc mo_tmp
	sta mo_tmp
	clc
	adc #$0080
	cmp #$0100
	#akku8
	bcs _fehler
	lda mo_tmp
	sta mo_bytes+1
	lda #2
	sta mo_len
	clc
	rts
_rel16                          ; Abstand = Ziel - (Adresse + 3)
	jsr _bank
	bcs _fehler
	#akku16
	lda k_arg1
	clc
	adc #3
	sta mo_tmp
	lda mo_w1
	sec
	sbc mo_tmp
	sta mo_bytes+1
	#akku8
	lda #3
	sta mo_len
	clc
	rts
_bank                           ; Ziel mit Bank: dieselbe wie die Adresse
	lda mo_ziff
	cmp #5
	bcc +
	lda mo_w1+2
	cmp k_arg1+2
	bne _fehler
+	clc
	rts
_fehler
	sec
	rts

;============================================================================
; Register

; R: Register zeigen (die Zeile mit ";" laesst sich aendern)
mo_r
	ldx #t_mo_kopf
	jsr mo_text
	lda #';'
	#aus
	ldx #r_pc
	jsr mo_adr
	ldx #r_a
	jsr _wort
	ldx #r_x
	jsr _wort
	ldx #r_y
	jsr _wort
	ldx #r_s
	jsr _wort
	ldx #r_d
	jsr _wort
	jsr mo_leerzeichen
	lda r_b
	jsr mo_hex8
	jsr mo_leerzeichen
	lda r_p
	jsr mo_hex8
	lda #13
	#aus
	jsr mo_leerzeichen          ; Flaggen: gross = gesetzt
	ldx #_namen                 ; Emulationsmodus: Bit 5 frei, Bit 4 B
	lda r_e
	beq +
	ldx #_namen_e
+	lda r_p
	sta mo_zz
	lda #8
	sta mo_op
-	lda ROM,x
	asl mo_zz
	bcs +
	ora #$20                    ; klein
+	#aus
	inx
	dec mo_op
	bne -
	ldx #t_mo_nativ
	lda r_e
	beq +
	ldx #t_mo_emu
+	jsr mo_text
	lda #13
	#aus
	rts
_wort
	jsr mo_leerzeichen
	lda 1,x
	jsr mo_hex8
	lda 0,x
	jmp mo_hex8
_namen	.text "NVMXDIZC"
_namen_e .text "NV1BDIZC"

; ;pc a x y s d b p: Register aendern
mo_strichpunkt
	jsr mo_hex
	bcs _fehler
	lda k_wert
	sta r_pc
	lda k_wert+1
	sta r_pc+1
	lda k_wert+2
	sta r_pc+2
	ldx #r_a
-	phx
	jsr mo_hex
	plx
	bcs _fehler
	lda k_wert
	sta 0,x
	lda k_wert+1
	sta 1,x
	inx
	inx
	cpx #r_d+2
	bne -
	jsr mo_hex
	bcs _fehler
	lda k_wert
	sta r_b
	jsr mo_hex
	bcs _fehler
	lda k_wert
	sta r_p
	and #$30                    ; D nimmt die Breiten von hier
	sta mo_flags
	rts
_fehler
	jmp mo_fehler

;----------------------------------------------------------------------------
; G [adresse]: mit Adresse wie bisher per JSL starten (zurueck mit RTL),
; ohne mit den Registern aus dem Abzug fortsetzen (nach BRK/Einzelschritt)

mo_g
	jsr mo_hex
	bcc +
	stz mo_schritte
	stz mo_schritte+1
	jmp mo_fortsetzen
+	ldx #k_sprung
	jsr mo_wert_nach
	stz k_blink
	jsl K_CURAUS
	ldx #$01ff                  ; frischer Stapel: ein angehaltenes Programm
	txs                         ; (BRK) ist damit aufgegeben, sonst wuchse er
	phk
	pea _zurueck-1
	jml [k_sprung]
_zurueck
	rep #$10
	.xl
	#akku8
	pea 0
	pld
	lda #0
	pha
	plb
	jsl K_ANZEIGE
	jml K_HAUPT

; W [n]: n Befehle (ohne Angabe einen) im Einzelschritt
mo_w
	jsr mo_hex
	bcc +
	lda #1
	sta k_wert
	stz k_wert+1
+	lda k_wert
	sta mo_schritte
	lda k_wert+1
	sta mo_schritte+1
	ora mo_schritte
	bne mo_schritt
	rts

; Einen Schritt: PC und P merken (fuer die Anzeige danach), SCHRITT scharf
mo_schritt
	lda r_pc
	sta mo_vorpc
	lda r_pc+1
	sta mo_vorpc+1
	lda r_pc+2
	sta mo_vorpc+2
	lda r_p
	sta mo_vorp
	; weiter in mo_fortsetzen (mo_schritte > 0: Schritt)

; Register aus dem Abzug laden und mit RTI dorthin, wo das Programm stand.
; SCHRITT (SYSTEM Bit 1): die Hardware loest nach dem ersten Befehl hinter
; dem RTI einen NMI aus (und haelt bis dahin IRQs zurueck).
mo_fortsetzen
	sei
	#akku16
	ldx r_s
	txs
	#akku8
	lda r_e
	bne _emu
	lda r_pc+2                  ; nativ: PBR, PC, P
	pha
	#akku16
	lda r_pc
	pha
	#akku8
	lda r_p
	pha
	jsr _register
	rep #$30
	.al
	pld
	ply
	plx
	pla
	rti
_emu                            ; Emulationsmodus: PC, P (Bank 0)
	.as
	#akku16
	lda r_pc
	pha
	#akku8
	lda r_p
	pha
	jsr _register
	rep #$30
	.al
	pld
	ply
	plx
	pla
	jml K_EMU_RTI               ; RTI emuliert laesst PBR stehen: aus Bank 0
_register                       ; A, X, Y, D auf den Stapel, Datenbank und SYSTEM
	.as
	#akku16                     ; (unter die Ruecksprungadresse schieben)
	pla
	sta mo_tmp
	lda r_a
	pha
	lda r_x
	pha
	lda r_y
	pha
	lda r_d
	pha
	lda mo_tmp
	pha
	#akku8
	lda mo_schritte
	ora mo_schritte+1
	beq +
	lda r_e                     ; SCHRITT scharf (Bit 2: der RTI ist emuliert)
	asl a
	asl a
	ora #$02
+	ora mo_sys
	sta SYSTEM
	lda r_b
	pha
	plb
	rts

; Einsprung vom Kern nach BRK oder Einzelschritt (MON_HALT, $FF:400F):
; auf dem Stapel liegen Grund (16 Bit), D, Datenbank, Y, X, A (je 16 Bit),
; dann was die CPU gestapelt hat: P, PC und (nativ) PBR. Direkte Seite und
; Datenbank sind 0, Akku und Indexregister 16 Bit.
mon_halt
	.al
	.xl
	pla
	sta mo_grund
	pla
	sta r_d
	#akku8
	pla
	sta r_b
	#akku16
	pla
	sta r_y
	pla
	sta r_x
	pla
	sta r_a
	#akku8
	pla
	sta r_p
	#akku16
	pla
	sta r_pc
	#akku8
	stz r_pc+2
	lda #1
	sta r_e
	lda mo_grund
	bmi +
	pla                         ; nativ: PBR
	sta r_pc+2
	stz r_e
+	tsx
	stx r_s
	lda SYSTEM                  ; SPIEGEL merken, fuer den Monitor aus
	and #$01
	sta mo_sys
	lda #0
	sta SYSTEM
	cli
	lda mo_grund
	and #$7f
	bne _schritt
	ldx #t_mo_brk               ; BRK: Register zeigen
	jsr mo_text
	jsr mo_r
	bra _monitor
_schritt                        ; ausgefuehrten Befehl und Register zeigen
	lda mo_vorpc
	sta k_arg1
	lda mo_vorpc+1
	sta k_arg1+1
	lda mo_vorpc+2
	sta k_arg1+2
	lda mo_vorp
	and #$30
	sta mo_flags
	jsr mo_dis
	jsr mo_puf_zeigen
	jsr mo_r
	#akku16
	dec mo_schritte
	#akku8
	lda mo_schritte
	ora mo_schritte+1
	beq _monitor
	jsr mo_esc
	bcs _monitor
	jmp mo_schritt
_monitor
	stz mo_schritte
	stz mo_schritte+1
	lda r_pc                    ; D ohne Adresse zeigt, wo es steht
	sta mo_dweiter
	lda r_pc+1
	sta mo_dweiter+1
	lda r_pc+2
	sta mo_dweiter+2
	lda r_p
	and #$30
	sta mo_flags
	jml K_HAUPT

; Fuer Programme (und den Selbsttest): eine Zeile ab [k_arg1] nach mo_puf
; disassemblieren / den Text in EINGABE fuer k_arg1 uebersetzen (C = 1:
; Fehler). Aufruf per JSL mit Akku 8, Index 16 Bit, Seite und Datenbank 0.
mon_dis
	jsr mo_dis
	rtl
mon_asm
	ldy #0
	jsr mo_asm
	rtl

; Abzug beim Einschalten: Breiten wie im Kern (Akku 8, Index 16 Bit)
mon_anfang
	.as
	.xl
	ldx #0
-	stz r_pc,x
	inx
	cpx #16
	bne -
	lda #$24                    ; M gesetzt, I gesetzt
	sta r_p
	lda #$20                    ; D: Akku 8, Index 16 Bit
	sta mo_flags
	lda #$ff
	sta r_s
	lda #$01
	sta r_s+1
	stz mo_schritte
	stz mo_schritte+1
	rtl

;============================================================================
; Speicher

; M anfang [ende]: Speicher zeigen
mo_m
	jsr mo_arg1
	bcc +
	jmp mo_fehler
+	jsr mo_arg2
	bcc _bereich
	lda #16
	sta mo_zz
-	jsr mo_speicherzeile
	dec mo_zz
	bne -
	rts
_bereich
	jsr mo_speicherzeile
	jsr mo_esc
	bcs +
	jsr mo_arg1_ist_ende
	bcc _bereich
+	rts

; Eine Zeile ":aaaaaa xx xx ... zeichen" ab k_arg1, danach k_arg1 weiter
mo_speicherzeile
	lda #':'
	#aus
	ldx #k_arg1
	jsr mo_adr
	ldy #0
-	jsr mo_leerzeichen
	lda [k_arg1],y
	jsr mo_hex8
	iny
	cpy k_bpz
	bne -
	jsr mo_leerzeichen
	ldy #0
-	lda [k_arg1],y
	cmp #$20
	bcc _punkt
	cmp #$7f
	bne +
_punkt
	lda #'.'
+	#aus
	iny
	cpy k_bpz
	bne -
	jsr mo_cr
	#akku16
	lda k_arg1
	clc
	adc k_bpz
	sta k_arg1
	#akku8
	bcc +
	inc k_arg1+2
+	rts

; :aaaaaa xx xx ...: Bytes schreiben (hoechstens eine Speicherzeile)
mo_doppelpunkt
	jsr mo_arg1
	bcc +
	jmp mo_fehler
+	ldy #0
-	phy
	jsr mo_hex
	ply
	bcs +
	lda k_wert
	sta [k_arg1],y
	iny
	cpy k_bpz
	bne -
+	rts

; F anfang ende byte: Bereich fuellen
mo_f
	jsr mo_arg1
	bcs _fehler
	jsr mo_arg2
	bcs _fehler
	jsr mo_hex
	bcs _fehler
-	lda k_wert
	sta [k_arg1]
	jsr mo_arg1_plus
	jsr mo_arg1_ist_ende
	bcc -
	rts
_fehler
	jmp mo_fehler

; T anfang ende ziel: Bereich kopieren (MVN oder MVP je nach Richtung, der
; Stummel in Seite 2 endet mit RTL)
mo_t
	jsr mo_arg1
	bcs _fehler
	jsr mo_arg2
	bcs _fehler
	jsr mo_arg3
	bcs _fehler
	#akku16
	lda k_arg2
	sec
	sbc k_arg1
	sta k_anzahl                ; Bytes - 1
	#akku8
	lda k_arg3+2
	sta KOPIER+1
	lda k_arg1+2
	sta KOPIER+2
	lda #$6b                    ; RTL
	sta KOPIER+3
	lda k_arg3+2                ; Ziel hinter der Quelle in derselben Bank: MVP
	cmp k_arg1+2
	bne _mvn
	#akku16
	lda k_arg3
	cmp k_arg1
	#akku8
	bcc _mvn
	beq _mvn
	lda #$44                    ; MVP: von hinten nach vorn
	sta KOPIER
	#akku16
	lda k_arg1
	clc
	adc k_anzahl
	tax
	lda k_arg3
	clc
	adc k_anzahl
	tay
	bra _los
_mvn
	lda #$54
	sta KOPIER
	#akku16
	ldx k_arg1
	ldy k_arg3
_los
	lda k_anzahl
	jsl KOPIER
	#akku8
	lda #0
	pha
	plb
	rts
_fehler
	jmp mo_fehler

; C anfang ende ziel: vergleichen, Abweichungen zeigen
mo_c
	jsr mo_arg1
	bcs _fehler
	jsr mo_arg2
	bcs _fehler
	jsr mo_arg3
	bcs _fehler
	stz mo_zz
-	lda [k_arg1]
	cmp [k_arg3]
	beq +
	jsr mo_fund
+	inc k_arg3
	bne +
	inc k_arg3+1
	bne +
	inc k_arg3+2
+	jsr mo_arg1_plus
	jsr mo_esc
	bcs +
	jsr mo_arg1_ist_ende
	bcc -
+	jmp mo_cr
_fehler
	jmp mo_fehler

; Fundstelle k_arg1 zeigen (fuenf je Zeile)
mo_fund
	lda #'$'
	#aus
	ldx #k_arg1
	jsr mo_adr
	jsr mo_leerzeichen
	inc mo_zz
	lda mo_zz
	cmp #5
	bne +
	stz mo_zz
	lda #13
	#aus
+	rts

; H anfang ende bytes / "text": suchen
mo_h
	jsr mo_arg1
	bcs _fehler
	jsr mo_arg2
	bcs _fehler
	ldy k_ein_pos               ; Muster nach mo_puf, Laenge in mo_len
	jsr mo_leer
	ldx #0
	lda EINGABE,y
	cmp #'"'
	bne _bytes
	iny
-	lda EINGABE,y
	beq _da
	cmp #'"'
	beq _da
	sta mo_puf,x
	iny
	inx
	cpx #MO_PUFLEN
	bne -
	bra _da
_bytes
	sty k_ein_pos
-	phx
	jsr mo_hex
	plx
	bcs _da
	lda k_wert
	sta mo_puf,x
	inx
	cpx #MO_PUFLEN
	bne -
_da
	txa
	beq _fehler
	sta mo_len
	stz mo_zz
_suche
	ldy #0
-	lda [k_arg1],y
	cmp mo_puf,y
	bne +
	iny
	tya
	cmp mo_len
	bne -
	jsr mo_fund
+	jsr mo_arg1_plus
	jsr mo_esc
	bcs +
	jsr mo_arg1_ist_ende
	bcc _suche
+	jmp mo_cr
_fehler
	jmp mo_fehler

;============================================================================
; Zahlen umrechnen: $ hex, # dezimal, % binaer -> alle drei Schreibweisen

mo_hexzahl
	jsr mo_hex
	bcs mo_zahlfehler
	bra mo_zahl_zeigen

mo_dezzahl
	ldy k_ein_pos
	jsr mo_leer
	stz k_wert
	stz k_wert+1
	stz k_wert+2
	stz mo_ziff
-	lda EINGABE,y
	sec
	sbc #'0'
	cmp #10
	bcs +
	pha                         ; wert = wert * 10 + ziffer
	jsr _mal10
	pla
	clc
	adc k_wert
	sta k_wert
	bcc ++
	inc k_wert+1
	bne ++
	inc k_wert+2
+	bra _ende
+	iny
	inc mo_ziff
	lda mo_ziff
	cmp #9
	bne -
	bra mo_zahlfehler
_ende
	lda mo_ziff
	beq mo_zahlfehler
	bra mo_zahl_zeigen
_mal10                          ; k_wert * 10 = (wert * 4 + wert) * 2
	lda k_wert
	sta mo_w1
	lda k_wert+1
	sta mo_w1+1
	lda k_wert+2
	sta mo_w1+2
	asl k_wert
	rol k_wert+1
	rol k_wert+2
	asl k_wert
	rol k_wert+1
	rol k_wert+2
	clc
	lda k_wert
	adc mo_w1
	sta k_wert
	lda k_wert+1
	adc mo_w1+1
	sta k_wert+1
	lda k_wert+2
	adc mo_w1+2
	sta k_wert+2
	asl k_wert
	rol k_wert+1
	rol k_wert+2
	rts

mo_binzahl
	ldy k_ein_pos
	jsr mo_leer
	stz k_wert
	stz k_wert+1
	stz k_wert+2
	stz mo_ziff
-	lda EINGABE,y
	sec
	sbc #'0'
	cmp #2
	bcs +
	lsr a
	rol k_wert
	rol k_wert+1
	rol k_wert+2
	iny
	inc mo_ziff
	lda mo_ziff
	cmp #25
	bne -
	bra mo_zahlfehler
+	lda mo_ziff
	beq mo_zahlfehler
	bra mo_zahl_zeigen

mo_zahlfehler
	jmp mo_fehler

; k_wert als $hex, #dezimal und (bis 16 Bit) %binaer
mo_zahl_zeigen
	lda #'$'
	#aus
	ldx #k_wert
	jsr mo_adr
	jsr mo_leerzeichen
	jsr mo_leerzeichen
	lda #'#'
	#aus
	jsr mo_dez24
	lda k_wert+2
	bne _ende
	jsr mo_leerzeichen
	jsr mo_leerzeichen
	lda #'%'
	#aus
	ldx #16
-	asl k_wert
	rol k_wert+1
	lda #'0'
	adc #0
	#aus
	dex
	bne -
_ende
	lda #13
	#aus
	rts

; k_wert (24 Bit) dezimal ohne fuehrende Nullen (k_wert bleibt)
mo_dez24
	lda k_wert
	sta mo_w1
	lda k_wert+1
	sta mo_w1+1
	lda k_wert+2
	sta mo_w1+2
	stz mo_zz                   ; schon eine Ziffer gezeigt?
	ldx #0
_stelle
	lda #'0'
	sta mo_op
_ab                             ; solange w1 >= 10^n: abziehen
	lda mo_w1+2
	cmp ROM+_zehner+2,x
	bne +
	#akku16
	lda mo_w1
	cmp ROM+_zehner,x
	#akku8
+	bcc _ziffer
	#akku16
	lda mo_w1
	sec
	sbc ROM+_zehner,x
	sta mo_w1
	#akku8
	lda mo_w1+2
	sbc ROM+_zehner+2,x
	sta mo_w1+2
	inc mo_op
	bra _ab
_ziffer
	lda mo_op
	cmp #'0'
	bne +
	lda mo_zz
	bne +
	cpx #7*3                    ; die letzte Stelle immer
	bne _naechste
+	sta mo_zz
	lda mo_op
	#aus
_naechste
	inx
	inx
	inx
	cpx #8*3
	bne _stelle
	rts
_zehner	.long 10000000, 1000000, 100000, 10000, 1000, 100, 10, 1

;============================================================================
; Laufwerk: L "name" [adresse], S "name" anfang ende, DIR

DOS_LADEN   = 0
DOS_SICHERN = 1
MO_DOS      = ROM+dos_befehl    ; (D_... aus dos.asm)

mo_name                         ; "name" ab k_ein_pos nach D_TEXT; C = 1: Fehler
	ldy k_ein_pos
	jsr mo_leer
	lda EINGABE,y
	cmp #'"'
	bne _fehler
	iny
	ldx #0
-	lda EINGABE,y
	beq _fehler
	iny
	cmp #'"'
	beq +
	sta D_TEXT,x
	inx
	cpx #17
	bne -
	bra _fehler
+	txa
	beq _fehler
	sta D_TLEN
	sty k_ein_pos
	lda #'M'                    ; ohne Endung: .MER
	sta D_ENDUNG
	lda #'E'
	sta D_ENDUNG+1
	lda #'R'
	sta D_ENDUNG+2
	lda STD_LW
	sta D_LW
	clc
	rts
_fehler
	sec
	rts

mo_l
	jsr mo_name
	bcs _fehler
	lda #$ff                    ; ohne Adresse: die aus dem MER-Kopf
	sta D_ADR
	sta D_ADR+1
	sta D_ADR+2
	sta D_LAENGE
	sta D_LAENGE+1
	sta D_LAENGE+2
	stz D_LAENGE+3
	jsr mo_hex
	bcs +
	lda k_wert
	sta D_ADR
	lda k_wert+1
	sta D_ADR+1
	lda k_wert+2
	sta D_ADR+2
+	lda #DOS_LADEN
	jsl MO_DOS
	cmp #0
	bne mo_dosfehler
	ldx #t_mo_geladen           ; "LOADED $aaaaaa-$eeeeee"
	jsr mo_text
	ldx #D_ADR
	jsr mo_adr
	lda #'-'
	#aus
	lda #'$'
	#aus
	#akku16                     ; Ende = Anfang + Laenge - 1
	lda D_ADR
	clc
	adc D_LAENGE
	sta k_wert
	#akku8
	lda D_ADR+2
	adc D_LAENGE+2
	sta k_wert+2
	#akku16
	lda k_wert
	bne +
	#akku8
	dec k_wert+2
	#akku16
+	dec k_wert
	#akku8
	ldx #k_wert
	jsr mo_adr
	lda #13
	#aus
	rts
_fehler
	jmp mo_fehler

mo_dosfehler                    ; A = Fehler des DOS: Text vom Kern
	pha
	lda #'?'
	#aus
	pla
	jsl K_DOSTEXT
	lda #13
	#aus
	rts

mo_s
	jsr mo_name
	bcs _fehler
	jsr mo_arg1
	bcs _fehler
	jsr mo_arg2
	bcs _fehler
	jsr mo_arg1_ist_ende
	bcs _fehler
	lda k_arg1
	sta D_ADR
	lda k_arg1+1
	sta D_ADR+1
	lda k_arg1+2
	sta D_ADR+2
	#akku16                     ; Laenge = Ende - Anfang + 1
	lda k_arg2
	sec
	sbc k_arg1
	sta D_LAENGE
	#akku8
	lda k_arg2+2
	sbc k_arg1+2
	sta D_LAENGE+2
	stz D_LAENGE+3
	#akku16
	inc D_LAENGE
	#akku8
	bne +
	inc D_LAENGE+2
+	lda #1                      ; mit MER-Kopf (Ladeadresse = Anfang)
	sta D_MER
	lda #DOS_SICHERN
	jsl MO_DOS
	cmp #0
	bne mo_dosfehler
	ldx #t_mo_gesichert
	jmp mo_text
_fehler
	jmp mo_fehler

mo_dir
	stz P_ANZ
	jsl K_KATALOG
	rts

;============================================================================
; Bildschirm und Sonstiges (bis Etappe 12 im Kern)

mo_basic
	jml K_BASIC

; MODE 40 / MODE 80
mo_modus
	jsr mo_hex
	bcs _fehler
	lda k_wert
	cmp #$80
	beq +
	cmp #$40
	bne _fehler
	lda #40
	bra ++
+	lda #80
+	jsl K_MODUS
	ldx #t_mo_bereit
	jmp mo_text
_fehler
	jmp mo_fehler

; COLOR v h: Vorder- und Hintergrundfarbe (0-F), faerbt den Bildschirm um
mo_farbe
	jsr mo_hex
	bcs _fehler
	lda k_wert
	and #$0f
	sta mo_zz
	jsr mo_hex
	bcs _fehler
	lda k_wert
	asl a
	asl a
	asl a
	asl a
	ora mo_zz
	sta k_farbe
	php
	sei
	jsl K_CURAUS
	lda k_farbe
	ldx #1
-	sta BILDSCHIRM,x
	inx
	inx
	cpx #80*ZEILEN*2+1
	bcc -
	plp
	rts
_fehler
	jmp mo_fehler

; CHARS: Zeichentabelle
mo_zeichen
	lda #$20
	sta mo_zz
_zeile
	lda #'$'
	#aus
	lda mo_zz
	jsr mo_hex8
	jsr mo_leerzeichen
	ldy #16
-	lda mo_zz
	cmp #$7f
	bne +
	lda #' '
+	#aus
	jsr mo_leerzeichen
	inc mo_zz
	dey
	bne -
	jsr mo_cr
	lda mo_zz
	bne _zeile
	rts

mo_hilfe
	ldx #t_mo_hilfe
	jmp mo_text

;----------------------------------------------------------------------------
; Texte

t_mo_fehler	.text 7, "?ERROR", 13, 0
t_mo_bereit	.text "READY.", 13, 0
t_mo_kopf	.text "   PC     AC   XR   YR   SP   DP  DB P", 13, 0
t_mo_nativ	.text "  native", 0
t_mo_emu	.text "  emulation", 0
t_mo_brk	.text "BRK", 13, 0
t_mo_geladen	.text "LOADED $", 0
t_mo_gesichert	.text "SAVED", 13, 0
t_mo_hilfe
	.text "A a         assemble from a", 13
	.text "D [a [e]]   disassemble", 13
	.text "M a [e]     show memory", 13
	.text ":a bb ..    change bytes", 13
	.text ",a ...      change a D line", 13
	.text "R / ;...    show / change registers", 13
	.text "G [a]       run (without a: continue)", 13
	.text "W [n]       single step", 13
	.text "F a e bb    fill", 13
	.text "T a e z     transfer (copy)", 13
	.text "C a e z     compare", 13
	.text 'H a e bb.. / "text"  hunt', 13
	.text 'L "name" [a]  S "name" a e  DIR', 13
	.text "$1F #31 %11111  convert numbers", 13
	.text "MODE 40/80  COLOR f b  CHARS", 13
	.text "X / BASIC   back to BASIC", 13
	.text "Numbers in hex: $12 = direct page,", 13
	.text "$1234 absolute, $123456 long", 13, 0
