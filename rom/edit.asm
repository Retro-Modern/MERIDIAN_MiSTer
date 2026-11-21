;============================================================================
;  EDIT - a text and BASIC editor in the workshop (tab 7, F8)
;
;  Included at the end of song.asm: the code lives in the free part of the
;  SONG ROM (the other ROM blocks of bank $FF are full, and the FPGA has no
;  block RAM left for another one). The workshop calls it through the jump
;  table at $FF:BFF0 (JSR, same bank), with Akku 8 / Index 16 bit, DBR 0,
;  D = W_RAM:
;    $BFF0  draw the tab (from w_inhalt: rows 1-29 are already cleared)
;    $BFF3  one frame; A = the key GETIN gave this frame (0 = none)
;    $BFF6  the workshop is about to close: C = 1 keeps it open (the
;           program has an error, the editor shows it)
;
;  Three kinds of document:
;    PROGRAM     the BASIC program in memory, listed as text whenever the
;                tab opens; when the workshop closes, a changed text
;                replaces the program (like typing all lines, then CLR)
;    TEXT FILE   any file; lines end with LF (CR LF and CR are read too,
;                Tab becomes spaces)
;    BASIC FILE  a program file (tokenized), listed as text and saved
;                tokenized again
;  Text to program works like tools/bas.py and Microsoft's CRUNCH:
;  keywords are found anywhere outside quotes, REM and DATA, "?" is PRINT,
;  an ELSE gets a ":" in front if it has none.
;
;  Keys: cursor keys, Home/End, PgUp/PgDn, Shift+Home (top), Ctrl+End
;  (bottom), Return, Backspace, Del, Tab (spaces); a mouse click places the
;  cursor. Ctrl+O open, Ctrl+S save, Ctrl+N new text, Ctrl+B the BASIC
;  program, Ctrl+P use this text as the program, Ctrl+F find, Ctrl+G find
;  again, Ctrl+L go to line, Ctrl+X cut line (cuts in a row collect),
;  Ctrl+C copy line, Ctrl+V paste lines. Ctrl+letter does not reach GETIN,
;  so those come raw from the key table, like the workshop's F keys.
;
;  Expansion RAM: $E4:0000 state (kept between visits), $E4:0100 keyword
;  index, $E4:1000 clipboard, $E5:0000 the text (up to $FF00 bytes),
;  $E6:0000 work buffer (files, the tokenized program). Variables at $A100,
;  inside the workshop's borrowed $A000-$AFFF (it saves and restores it).
;============================================================================

	.include "kern_sym.inc"     ; K_L_GETIN
	.include "ws_sym.inc"       ; W_W_MX ... W_SD_FEHLERTEXTE (rom/bauen.sh)
	.include "basic_sym.inc"    ; B_TXTTAB ..., B_RESLST, B_REMTK ...

ED_SPRUNG     = $FFBFF0            ; jump table (see werkstatt.asm, ED_ZEICHNEN)
ED_DP      = $A100
ED_ST      = $E40000            ; state, ED_STAND bytes
ED_KW      = $E40100            ; 128 words: where each keyword starts (bank $FF)
ED_ERST    = $E40200            ; 256 bytes: first keyword with this first character
ED_NAECHST = $E40300            ; 128 bytes: next keyword with the same first character
ED_CLIP    = $E41000            ; clipboard
ED_BUF     = $E50000            ; the text
ED_TMP     = $E60000            ; work buffer
ED_MAX     = $FF00              ; longest text
ED_CLIPMAX = $EF00
ED_LF      = $0a
ED_OBEN    = 2                  ; first text row
ED_ZEILEN  = 26                 ; text rows (2-27); 28 help, 29 status
ED_SCHIRM  = $0400              ; text screen, 80 x 30 cells of 2 bytes
ED_TASTEN  = $033E00            ; kernel: one byte per key, 1 = held
ED_UMSCH   = $000022            ; kernel: bit 1 = Ctrl held
ED_DOS     = $FF4000
ED_DO_LW   = $16C0              ; DOS parameter block (bank 0)
ED_DO_MER  = $16C2
ED_DO_ENDUNG = $16C3
ED_DO_TLEN = $16C6
ED_DO_TEXT = $16C7
ED_D_ADR   = $16E4
ED_D_LAENGE = $16E8
ED_STD_LW  = $16FF              ; DRIVE
ED_F_TEXT  = $6f                ; light grey on blue (the workshop's F_GRUND)
ED_F_KOPF  = $67                ; yellow on blue
ED_F_HILFE = $bf                ; light grey on dark grey
ED_F_STATUS = $f0               ; black on light grey
ED_F_CURSOR = $70               ; black on yellow
ED_NAMEMAX = 12
ED_BESUCH_MARKE  = $ed17              ; marks the variables of this visit

; documents
DOK_PROGRAMM = 0
DOK_TEXT   = 1
DOK_BASIC  = 2

	.virtual ED_DP
e_marke   .fill 4               ; "ED01": the state below is valid
e_modus   .byte ?               ; DOK_*
e_lw      .byte ?               ; drive of the file
e_nlen    .byte ?               ; its name
e_name    .fill ED_NAMEMAX+1
e_len     .word ?               ; text length
e_cur     .word ?               ; cursor (offset in the text)
e_top     .word ?               ; first line shown (its offset)
e_topnr   .word ?               ;   and its number (0 = first)
e_curnr   .word ?               ; line of the cursor
e_links   .word ?               ; first column shown
e_will    .word ?               ; column the cursor keeps on up/down
e_zeilen  .word ?               ; number of lines (at least 1)
e_clen    .word ?               ; clipboard length
e_geaendert .byte ?             ; 1 = changed (PROGRAM: not yet applied)
e_mitdaten   .byte ?               ; BASIC FILE with workshop data after the program
e_slen    .byte ?               ; search text
e_such    .fill 21
ED_STAND = * - ED_DP
	; only during a visit (ed_besuch clears them)
e_t0      .word ?
e_t1      .word ?
e_t2      .word ?
e_t3      .word ?
e_p       .long ?
e_q       .long ?
e_farbe   .byte ?
e_taste   .byte ?
e_strg    .byte ?               ; 1 = Ctrl held
e_neu     .byte ?               ; not 0 = draw everything
e_schnitt .byte ?               ; 1 = the last action was a cut
e_meld    .byte ?               ; frames the message stays
e_mtext   .word ?               ; the message (bank $FF)
e_i       .word ?
e_alt     .fill 16              ; raw keys: state last frame
e_wdh     .byte ?               ; repeat: frames to go
e_wtaste  .byte ?               ;   for this entry ($FF = none)
e_wortz   .byte ?               ; number of keywords
e_zif     .fill 5               ; decimal digits
e_zn      .word ?
e_ein     .fill 41              ; input line
e_elen    .byte ?
e_emax    .byte ?
e_eart    .byte ?               ; 1 = file name (Tab changes the drive)
	; tokenizing
e_basis   .word ?               ; address of the first line (TXTTAB)
e_aus     .word ?               ; output offset in ED_TMP
e_kanf    .word ?               ; output offset where the line's text starts
e_zanf    .word ?               ; start of the text line
e_zend    .word ?               ;   its end (LF or e_len)
e_rend    .word ?               ;   its end without trailing spaces
e_nr      .word ?               ; BASIC line number
e_letzte  .word ?               ; the one before
e_hat     .word ?               ; 1 = there was a line before
e_rem     .word ?
e_data    .word ?
e_rest    .word ?               ; characters left in the line (keyword match)
e_ueber   .byte ?               ; not 0 = output buffer full
e_besuch  .word ?               ; ED_BESUCH_MARKE during a visit
	.cerror * > ED_DP+$100, "EDIT: variables do not fit into $A100-$A1FF"
	.endv

	.dpage ED_DP

;----------------------------------------------------------------------------
; Entry points (the workshop runs with D = W_RAM)

ed_zeichnen_e
	.as
	.xl
	phd
	pea ED_DP
	pld
	jsr ed_zeichnen
	pld
	rts

ed_takt_e
	.as
	.xl
	phd
	pea ED_DP
	pld
	jsr ed_takt
	pld
	rts

ed_verlassen_e
	.as
	.xl
	phd
	pea ED_DP
	pld
	jsr ed_verlassen
	pld                         ; keeps C
	rts

; The variables at $A100 hold whatever was there in BASIC's memory when the
; workshop opened (it puts that back when it closes): the first call of a
; visit clears them.
ed_besuch
	.as
	#akku16
	lda e_besuch
	cmp #ED_BESUCH_MARKE
	beq +
	#akku8
	ldx #e_besuch - e_t0 - 1
-	stz e_t0,x
	dex
	bpl -
	#akku16
	lda #ED_BESUCH_MARKE
	sta e_besuch
+	#akku8
	rts

;----------------------------------------------------------------------------
; The tab opens (or is drawn again)

ed_zeichnen
	.as
	jsr ed_besuch
	jsr ed_stand_laden
	jsr ed_stand_gilt
	bcs +
	jsr ed_init
+	jsr ed_wortliste
	jsr ed_tasten_merken
	stz e_schnitt
	lda e_modus                 ; the program: list it again (it may have
	bne +                       ; changed in BASIC), unless it has changes
	lda e_geaendert             ; that are not applied yet
	bne +
	jsr ed_programm_holen
+	jsr ed_sichtbar
	jsr ed_alles
	stz e_neu
	jmp ed_stand_sichern

ed_stand_laden                  ; $E4:0000 -> variables
	.as
	ldx #ED_STAND-1
-	lda @l ED_ST,x
	sta e_marke,x
	dex
	bpl -
	rts

ed_stand_sichern
	.as
	ldx #ED_STAND-1
-	lda e_marke,x
	sta @l ED_ST,x
	dex
	bpl -
	rts

ed_stand_gilt                   ; C = 1: the state is valid
	.as
	#akku16
	lda e_marke
	cmp #'E' | ('D' << 8)
	bne _nein
	lda e_marke+2
	cmp #'0' | ('1' << 8)
	bne _nein
	lda e_len
	cmp #ED_MAX+1
	bcs _nein
	#akku8
	lda e_modus
	cmp #3
	bcs _nein8
	sec
	rts
_nein
	#akku8
_nein8
	clc
	rts

ed_init
	.as
	ldx #ED_STAND-1
-	stz e_marke,x
	dex
	bpl -
	#akku16
	lda #'E' | ('D' << 8)
	sta e_marke
	lda #'0' | ('1' << 8)
	sta e_marke+2
	lda #1
	sta e_zeilen
	#akku8
	lda ED_STD_LW
	and #3
	sta e_lw
	rts                         ; DOK_PROGRAMM, empty

; The program in memory as text; the cursor stays on its line number
ed_programm_holen
	.as
	#akku16
	lda e_curnr
	pha
	lda @l $000000+B_TXTTAB     ; the program is in bank 1
	sta e_q
	#akku8
	lda #1
	sta e_q+2
	jsr ed_liste
	bcc +
	#akku16
	lda #<>t_ed_zulang
	jsr ed_melden
	.as
+	stz e_geaendert
	stz e_mitdaten
	#akku16
	stz e_links
	stz e_top
	stz e_topnr
	pla
	jsr ed_gehe_zeile
	.al
	#akku8
	rts

;----------------------------------------------------------------------------
; One frame

ed_takt
	.as
	sta e_taste
	jsr ed_besuch
	lda @l ED_UMSCH
	lsr a
	and #1
	sta e_strg
	jsr ed_roh
	jsr ed_maus
	lda e_strg                  ; with Ctrl nothing is typed (Ctrl + digit
	bne +                       ; would be a colour code)
	lda e_taste
	beq +
	jsr ed_taste
+	lda e_meld                  ; message: count down, then clear
	beq +
	dec e_meld
	bne +
	inc e_neu
+	lda e_neu
	beq +
	stz e_neu
	jsr ed_sichtbar
	jsr ed_alles
+	jmp ed_stand_sichern

; a key from GETIN
ed_taste
	.as
	ldx #0
-	lda @l ed_tastentab,x
	beq _zeichen
	cmp e_taste
	beq _treffer
	inx
	inx
	inx
	bra -
_treffer
	stz e_schnitt
	inc e_neu
	#akku16
	lda @l ed_tastentab+1,x
	sta e_t0
	#akku8
	jmp (e_t0)
_zeichen
	lda e_taste
	cmp #$20
	bcc _nichts
	stz e_schnitt
	inc e_neu
	jmp ed_zeichen_ein
_nichts
	rts

ed_tastentab
	.byte $0d
	.word <>ed_return
	.byte $08
	.word <>ed_rueck
	.byte $7f
	.word <>ed_entf
	.byte $1c
	.word <>ed_rechts
	.byte $1d
	.word <>ed_links
	.byte $1e
	.word <>ed_hoch
	.byte $1f
	.word <>ed_runter
	.byte $01
	.word <>ed_pos1
	.byte $0c
	.word <>ed_anfang
	.byte $09
	.word <>ed_tab
	.byte $0e                   ; Insert: nothing
	.word <>ed_nichts
	.byte 0

ed_nichts
	rts

; Keys from the key table: scancode index (E0 keys at 128 + code), 1 = only
; with Ctrl / 0 = only without, action
ed_rohtab
	.byte $e9, 0, 0             ; End
	.byte $e9, 1, 1             ; Ctrl+End
	.byte $fd, 0, 2             ; PgUp
	.byte $fa, 0, 3             ; PgDn
	.byte $44, 1, 4             ; Ctrl+O
	.byte $1b, 1, 5             ; Ctrl+S
	.byte $31, 1, 6             ; Ctrl+N
	.byte $32, 1, 7             ; Ctrl+B
	.byte $4d, 1, 8             ; Ctrl+P
	.byte $2b, 1, 9             ; Ctrl+F
	.byte $34, 1, 10            ; Ctrl+G
	.byte $4b, 1, 11            ; Ctrl+L
	.byte $22, 1, 12            ; Ctrl+X
	.byte $21, 1, 13            ; Ctrl+C
	.byte $2a, 1, 14            ; Ctrl+V
	.byte 0
ed_aktionen
	.word <>ed_ende, <>ed_schluss, <>ed_bildauf, <>ed_bildab, <>ed_oeffnen
	.word <>ed_sichern, <>ed_neu_text, <>ed_basic, <>ed_als_programm, <>ed_suchen
	.word <>ed_weiter, <>ed_zeile, <>ed_ausschneiden, <>ed_kopieren, <>ed_einfuegen

ed_tasten_merken                ; the state now (held keys do nothing)
	.as
	ldx #0
	ldy #0
-	lda @l ed_rohtab,x
	beq +
	phx
	#akku16
	and #$00ff
	tax
	#akku8
	lda @l ED_TASTEN,x
	plx
	sta e_alt,y
	inx
	inx
	inx
	iny
	bra -
+	lda #$ff
	sta e_wtaste
	rts

ed_roh
	.as
	#akku16
	stz e_i
	#akku8
	ldx #0
_eintrag
	lda @l ed_rohtab,x
	bne +
	rts
+	sta e_t0
	lda @l ed_rohtab+1,x
	sta e_t1
	lda @l ed_rohtab+2,x
	sta e_t2
	phx
	#akku16
	lda e_t0
	and #$00ff
	tax
	#akku8
	lda @l ED_TASTEN,x
	sta e_t3
	ldy e_i
	lda e_alt,y
	cmp e_t3
	beq _gleich
	lda e_t3
	sta e_alt,y
	beq _weiter                 ; let go
	lda e_t1                    ; pressed: right Ctrl state?
	cmp e_strg
	bne _weiter
	lda e_t1                    ; without Ctrl it repeats
	bne +
	lda e_i
	sta e_wtaste
	lda #25
	sta e_wdh
+	jsr _los
	bra _weiter
_gleich
	lda e_t3                    ; held: repeat (after 25 frames, every 3rd)
	beq _weiter
	lda e_t1
	bne _weiter
	lda e_strg
	bne _weiter
	lda e_i
	cmp e_wtaste
	bne _weiter
	dec e_wdh
	bne _weiter
	lda #3
	sta e_wdh
	jsr _los
_weiter
	plx
	inx
	inx
	inx
	#akku16
	inc e_i
	#akku8
	bra _eintrag
_los
	lda e_t2                    ; action (cuts in a row keep collecting)
	cmp #12
	beq +
	stz e_schnitt
+	inc e_neu
	asl a
	#akku16
	and #$00ff
	tax
	lda @l ed_aktionen,x
	sta e_t0
	#akku8
	jmp (e_t0)

;----------------------------------------------------------------------------
; Mouse: a click into the text puts the cursor there

ed_maus
	.as
	lda W_W_MT
	and #1
	beq _nein
	lda W_W_MTALT
	and #1
	bne _nein
	#akku16
	lda W_W_MY
	lsr a
	lsr a
	lsr a                       ; row
	sec
	sbc #ED_OBEN
	bcc _nein16
	cmp #ED_ZEILEN
	bcs _nein16
	sta e_t2                    ; rows below the top
	lda W_W_MX
	lsr a
	lsr a                       ; column
	clc
	adc e_links
	sta e_t3
	lda e_topnr
	sta e_curnr
	#akku8
	ldx e_top
_runter
	#akku16
	lda e_t2
	beq _da16
	dec e_t2
	#akku8
	jsr ed_zende
	cpx e_len
	bcs _da                     ; that was the last line
	inx
	#akku16
	inc e_curnr
	bra _runter
_da16
	#akku8
_da
	jsr ed_zstart
	jsr ed_spalte_setzen        ; X = line start, e_t3 = column
	stz e_schnitt
	inc e_neu
	rts
_nein16
	#akku8
_nein
	rts

; cursor = line start X + column e_t3, at most the line end
ed_spalte_setzen
	.as
	stx e_t0
	jsr ed_zende
	stx e_t1
	#akku16
	lda e_t0
	clc
	adc e_t3
	bcs +
	cmp e_t1
	bcc ++
+	lda e_t1
+	sta e_cur
	#akku8
	jmp ed_will_setzen

;----------------------------------------------------------------------------
; Moving

; X = offset -> X = start of its line
ed_zstart
	.as
-	cpx #0
	beq +
	lda @l ED_BUF-1,x
	cmp #ED_LF
	beq +
	dex
	bra -
+	rts

; X = offset -> X = end of its line (the LF, or e_len)
ed_zende
	.as
-	cpx e_len
	bcs +
	lda @l ED_BUF,x
	cmp #ED_LF
	beq +
	inx
	bra -
+	rts

; A (16 bit) = column of the cursor; returns with Akku 16. Call with Akku 8.
ed_spalte
	.as
	ldx e_cur
	jsr ed_zstart
	stx e_t0
	#akku16
	lda e_cur
	sec
	sbc e_t0
	rts

ed_will_setzen
	.as
	jsr ed_spalte
	.al
	sta e_will
	#akku8
	rts

ed_links
	.as
	ldx e_cur
	beq +
	dex
	stx e_cur
	lda @l ED_BUF,x
	cmp #ED_LF
	bne ed_will_setzen
	#akku16
	dec e_curnr
	#akku8
	bra ed_will_setzen
+	rts

ed_rechts
	.as
	ldx e_cur
	cpx e_len
	bcs +
	lda @l ED_BUF,x
	inx
	stx e_cur
	cmp #ED_LF
	bne ed_will_setzen
	#akku16
	inc e_curnr
	#akku8
	bra ed_will_setzen
+	rts

ed_hoch                         ; C = 1: already on the first line
	.as
	ldx e_cur
	jsr ed_zstart
	cpx #0
	bne +
	sec
	rts
+	dex                         ; the LF of the line above
	stx e_t1
	jsr ed_zstart
	#akku16
	dec e_curnr
	bra ed_auf_spalte

ed_runter                       ; C = 1: already on the last line
	.as
	ldx e_cur
	jsr ed_zende
	cpx e_len
	bcc +
	sec
	rts
+	inx
	stx e_t2
	jsr ed_zende
	stx e_t1
	ldx e_t2
	#akku16
	inc e_curnr
ed_auf_spalte                   ; X = line start, e_t1 = its end: column e_will
	.al
	txa
	clc
	adc e_will
	bcs +
	cmp e_t1
	bcc ++
+	lda e_t1
+	sta e_cur
	#akku8
	clc
	rts

ed_pos1
	.as
	ldx e_cur
	jsr ed_zstart
	stx e_cur
	jmp ed_will_setzen

ed_ende
	.as
	ldx e_cur
	jsr ed_zende
	stx e_cur
	jmp ed_will_setzen

ed_anfang
	.as
	#akku16
	stz e_cur
	stz e_curnr
	stz e_will
	#akku8
	rts

ed_schluss
	.as
	#akku16
	lda e_len
	sta e_cur
	lda e_zeilen
	dec a
	sta e_curnr
	#akku8
	jmp ed_will_setzen

ed_bildauf
	.as
	lda #ED_ZEILEN-1
	sta e_t3
-	jsr ed_hoch
	bcs +
	dec e_t3
	bne -
+	rts

ed_bildab
	.as
	lda #ED_ZEILEN-1
	sta e_t3
-	jsr ed_runter
	bcs +
	dec e_t3
	bne -
+	rts

; Keep the cursor on the screen: rows and columns
ed_sichtbar
	.as
	#akku16
	lda e_curnr
	cmp e_topnr
	bcs _drunter
	sta e_topnr                 ; above: its line becomes the top line
	#akku8
	ldx e_cur
	jsr ed_zstart
	stx e_top
	bra _spalte
_drunter
	.al
	sec
	sbc e_topnr
	cmp #ED_ZEILEN
	bcc _spalte16
	sbc #ED_ZEILEN-1            ; below: move the top down that many lines
	tay
	#akku8
	ldx e_top
-	jsr ed_zende
	inx
	#akku16
	inc e_topnr
	#akku8
	dey
	bne -
	stx e_top
	bra _spalte
_spalte16
	#akku8
_spalte
	jsr ed_spalte               ; Akku 16
	.al
	cmp e_links
	bcs +
	sta e_links
	bra _gut
+	sec
	sbc e_links
	cmp #80
	bcc _gut
	#akku8
	jsr ed_spalte
	.al
	sec
	sbc #79
	sta e_links
_gut
	#akku8
	rts

; After a jump: the cursor's line about a third down the screen
ed_mitte
	.as
	ldx e_cur
	jsr ed_zstart
	#akku16
	lda e_curnr
	sta e_topnr
	#akku8
	lda #8
	sta e_t3
-	cpx #0
	beq +
	dex
	jsr ed_zstart
	#akku16
	dec e_topnr
	#akku8
	dec e_t3
	bne -
+	stx e_top
	rts

; e_curnr = lines before the cursor
ed_zaehlen
	.as
	#akku16
	stz e_curnr
	#akku8
	ldx #0
-	cpx e_cur
	bcs +
	lda @l ED_BUF,x
	inx
	cmp #ED_LF
	bne -
	#akku16
	inc e_curnr
	#akku8
	bra -
+	rts

; e_zeilen = LFs + 1
ed_alle_zeilen
	.as
	ldx e_cur
	phx
	ldx e_len
	stx e_cur
	jsr ed_zaehlen
	#akku16
	lda e_curnr
	inc a
	sta e_zeilen
	#akku8
	plx
	stx e_cur
	jmp ed_zaehlen

; A (16 bit) = line number (0 = first): the cursor goes to its start (or to
; the last line); returns with Akku 16
ed_gehe_zeile
	.al
	sta e_t2
	stz e_curnr
	#akku8
	ldx #0
_zeile
	#akku16
	lda e_curnr
	cmp e_t2
	bcs _da16
	#akku8
	jsr ed_zende
	cpx e_len
	bcs _da
	inx
	#akku16
	inc e_curnr
	bra _zeile
_da16
	#akku8
_da
	jsr ed_zstart
	stx e_cur
	stz e_will
	stz e_will+1
	jsr ed_mitte
	#akku16
	rts

;----------------------------------------------------------------------------
; Changing the text

ed_geaendert
	.as
	lda #1
	sta e_geaendert
	inc e_neu
	rts

; Room for Y bytes at X: [X, e_len) moves up, e_len grows
ed_platz
	.as
	stx e_t0
	sty e_t1
	#akku16
	lda e_len
	sec
	sbc e_t0
	beq +
	dec a                       ; MVP: count - 1, from the last byte down
	pha
	lda e_len
	dec a
	tax
	clc
	adc e_t1
	tay
	pla
	phb
	mvp `ED_BUF, `ED_BUF
	plb
+	lda e_len
	clc
	adc e_t1
	sta e_len
	#akku8
	rts

; Y bytes at X go away: [X + Y, e_len) moves down, e_len shrinks
ed_weg
	.as
	stx e_t0
	sty e_t1
	#akku16
	lda e_len
	sec
	sbc e_t0
	sec
	sbc e_t1
	beq +
	dec a
	pha
	lda e_t0
	clc
	adc e_t1
	tax
	ldy e_t0
	pla
	phb
	mvn `ED_BUF, `ED_BUF
	plb
+	lda e_len
	sec
	sbc e_t1
	sta e_len
	#akku8
	rts

; Room for A (16 bit) more bytes? C = 1 (and a message) if not. Returns Akku 8.
ed_passt_rein
	.al
	clc
	adc e_len
	bcs +
	cmp #ED_MAX+1
	bcs +
	#akku8
	clc
	rts
+	.al
	lda #<>t_ed_voll
	jsr ed_melden
	.as
	sec
	rts

ed_zeichen_ein                  ; A = character at the cursor
	.as
	sta e_t3
	#akku16
	lda #1
	jsr ed_passt_rein
	.as
	bcs _aus
	ldx e_cur
	ldy #1
	jsr ed_platz
	ldx e_cur
	lda e_t3
	sta @l ED_BUF,x
	inx
	stx e_cur
	cmp #ED_LF
	bne +
	#akku16
	inc e_curnr
	inc e_zeilen
	#akku8
+	jsr ed_will_setzen
	jmp ed_geaendert
_aus
	rts

ed_return
	.as
	lda #ED_LF
	jmp ed_zeichen_ein

ed_tab                          ; spaces up to the next column of 4
	.as
	jsr ed_spalte
	.al
	and #3
	eor #3
	inc a
	#akku8
	sta e_t2
-	lda #' '
	jsr ed_zeichen_ein
	dec e_t2
	bne -
	rts

ed_entf
	.as
	ldx e_cur
	cpx e_len
	bcs _aus
	lda @l ED_BUF,x
	pha
	ldy #1
	jsr ed_weg
	pla
	cmp #ED_LF
	bne +
	#akku16
	dec e_zeilen
	#akku8
+	jmp ed_geaendert
_aus
	rts

ed_rueck
	.as
	ldx e_cur
	beq +
	jsr ed_links
	jmp ed_entf
+	rts

;----------------------------------------------------------------------------
; Lines: cut, copy, paste

; e_t2 = start of the cursor's line, e_t3 = its end (LF or e_len)
ed_bereich
	.as
	ldx e_cur
	jsr ed_zstart
	stx e_t2
	jsr ed_zende
	stx e_t3
	rts

; the line [e_t2, e_t3) and a LF to the clipboard at e_clen; C = 1 full
ed_zur_ablage
	.as
	#akku16
	lda e_t3
	sec
	sbc e_t2
	sec                         ; + LF
	adc e_clen
	cmp #ED_CLIPMAX
	bcc +
	lda #<>t_ed_ablage_voll
	jsr ed_melden
	.as
	sec
	rts
+	#akku8
	ldx e_t2
	ldy e_clen
-	cpx e_t3
	bcs +
	lda @l ED_BUF,x
	phx
	tyx
	sta @l ED_CLIP,x
	plx
	inx
	iny
	bra -
+	lda #ED_LF
	tyx
	sta @l ED_CLIP,x
	iny
	sty e_clen
	clc
	rts

ed_ausschneiden
	.as
	lda e_schnitt               ; a new cut starts an empty clipboard
	bne +
	#akku16
	stz e_clen
	#akku8
+	jsr ed_bereich
	jsr ed_zur_ablage
	bcs _aus
	ldx e_t3                    ; with its LF; the last line takes the LF
	cpx e_len                   ; before it instead
	bcs _letzte
	inx
	#akku16
	txa
	sec
	sbc e_t2
	tay
	#akku8
	ldx e_t2
	jsr ed_weg
	#akku16
	dec e_zeilen
	#akku8
	ldx e_t2
	stx e_cur
	bra _fertig
_letzte
	ldx e_t2
	beq _einzige
	dex
	#akku16
	lda e_t3
	sec
	sbc e_t2
	inc a
	tay
	#akku8
	stx e_t2
	jsr ed_weg
	#akku16
	dec e_zeilen
	dec e_curnr
	#akku8
	ldx e_t2
	jsr ed_zstart
	stx e_cur
	bra _fertig
_einzige
	ldy e_t3
	ldx #0
	jsr ed_weg
	ldx #0
	stx e_cur
_fertig
	lda #1
	sta e_schnitt
	jsr ed_will_setzen
	jmp ed_geaendert
_aus
	rts

ed_kopieren
	.as
	#akku16
	stz e_clen
	#akku8
	jsr ed_bereich
	jsr ed_zur_ablage
	bcs +
	#akku16
	lda #<>t_ed_kopiert
	jmp ed_melden
+	rts

ed_einfuegen                    ; the clipboard in front of the cursor's line
	.as
	#akku16
	lda e_clen
	bne +
	lda #<>t_ed_ablage_leer
	jmp ed_melden
+	jsr ed_passt_rein
	.as
	bcs _aus
	ldx e_cur
	jsr ed_zstart
	stx e_t2
	ldy e_clen
	jsr ed_platz
	#akku16
	lda e_clen
	dec a
	ldx #<>ED_CLIP
	ldy e_t2
	phb
	mvn `ED_CLIP, `ED_BUF
	plb
	lda e_cur                   ; the cursor stays on its text
	clc
	adc e_clen
	sta e_cur
	#akku8
	ldx #0                      ; LFs in the clipboard = new lines
-	cpx e_clen
	bcs +
	lda @l ED_CLIP,x
	inx
	cmp #ED_LF
	bne -
	#akku16
	inc e_curnr
	inc e_zeilen
	#akku8
	bra -
+	jmp ed_geaendert
_aus
	rts

;----------------------------------------------------------------------------
; Drawing

ed_alles
	.as
	jsr ed_kopf
	jsr ed_text_zeichnen
	jsr ed_hilfe
	jmp ed_status

; A = row -> X = its offset on the screen; the row filled with spaces in e_farbe
ed_zeile_leeren
	.as
	jsr ed_zeile_x
	phx
	ldy #80
-	lda #' '
	sta ED_SCHIRM,x
	lda e_farbe
	sta ED_SCHIRM+1,x
	inx
	inx
	dey
	bne -
	plx
	rts

ed_zeile_x                      ; A = row -> X = row * 160
	.as
	#akku16
	and #$00ff
	asl a
	asl a
	asl a
	asl a
	asl a                       ; * 32
	sta e_t0
	asl a
	asl a                       ; * 128
	clc
	adc e_t0
	tax
	#akku8
	rts

; text A (16 bit, bank $FF) at screen offset X in e_farbe; X behind it.
; Returns Akku 8.
ed_text
	.al
	sta e_p
	#akku8
	lda #$ff
	sta e_p+2
	ldy #0
-	lda [e_p],y
	beq +
	sta ED_SCHIRM,x
	lda e_farbe
	sta ED_SCHIRM+1,x
	inx
	inx
	iny
	bra -
+	rts

; the file's name (e_name, e_nlen long) at X
ed_name_zeigen
	.as
	ldy #0
-	tya
	cmp e_nlen
	bcs +
	lda e_name,y
	sta ED_SCHIRM,x
	lda e_farbe
	sta ED_SCHIRM+1,x
	inx
	inx
	iny
	bra -
+	rts

; A (16 bit) decimal at X; X behind it. Returns Akku 8.
ed_zahl
	.al
	jsr ed_ziffern
	.as
	ldy #0
-	lda e_zif,y
	sta ED_SCHIRM,x
	lda e_farbe
	sta ED_SCHIRM+1,x
	inx
	inx
	iny
	cpy e_zn
	bne -
	rts

; A (16 bit) -> e_zif (e_zn digits, no leading zeros); returns Akku 8, keeps X
ed_ziffern
	.al
	phx
	sta e_t1
	ldy #0
	ldx #0
_stelle
	stz e_t2
-	lda e_t1
	cmp @l ed_zehner,x
	bcc +
	sbc @l ed_zehner,x
	sta e_t1
	inc e_t2
	bra -
+	lda e_t2
	bne _schreiben
	cpy #0
	bne _schreiben
	cpx #8                      ; the last digit always
	bne _naechste
_schreiben
	lda e_t2
	clc
	adc #'0'
	#akku8
	sta e_zif,y
	#akku16
	iny
_naechste
	inx
	inx
	cpx #10
	bne _stelle
	sty e_zn
	#akku8
	plx
	rts
ed_zehner
	.word 10000, 1000, 100, 10, 1

; Row 1: what is being edited, line and column
ed_kopf
	.as
	lda #ED_F_KOPF
	sta e_farbe
	lda #1
	jsr ed_zeile_leeren
	inx
	inx
	lda e_modus
	bne _datei
	#akku16
	lda #<>t_ed_programm
	jsr ed_text
	.as
	lda e_geaendert
	beq _zeile
	#akku16
	lda #<>t_ed_ersetzt
	jsr ed_text
	.as
	bra _zeile
_datei
	cmp #DOK_BASIC
	beq +
	#akku16
	lda #<>t_ed_text
	bra ++
+	#akku16
	lda #<>t_ed_basicdatei
+	jsr ed_text
	.as
	lda e_nlen
	bne +
	#akku16
	lda #<>t_ed_neu
	jsr ed_text
	.as
	bra ++
+	jsr ed_name_zeigen
	#akku16
	lda #<>t_ed_lw
	jsr ed_text
	.as
	lda e_lw
	clc
	adc #'0'
	sta ED_SCHIRM,x
	inx
	inx
+	lda e_geaendert
	beq _zeile
	#akku16
	lda #<>t_ed_stern
	jsr ed_text
	.as
_zeile
	ldx #1 * 160 + 56 * 2
	#akku16
	lda #<>t_ed_zeile
	jsr ed_text
	.as
	#akku16
	lda e_curnr
	inc a
	jsr ed_zahl
	.as
	lda #'/'
	sta ED_SCHIRM,x
	inx
	inx
	#akku16
	lda e_zeilen
	jsr ed_zahl
	.as
	#akku16
	lda #<>t_ed_spalte
	jsr ed_text
	.as
	phx
	jsr ed_spalte               ; Akku 16
	.al
	plx
	inc a
	jmp ed_zahl

ed_hilfe
	.as
	lda #ED_F_HILFE
	sta e_farbe
	lda #28
	jsr ed_zeile_leeren
	inx
	inx
	#akku16
	lda #<>t_ed_hilfe
	jmp ed_text

ed_status                       ; the message, or the other keys
	.as
	lda #ED_F_STATUS
	sta e_farbe
	lda #29
	jsr ed_zeile_leeren
	inx
	inx
	lda e_meld
	beq +
	#akku16
	lda e_mtext
	jmp ed_text
+	#akku16
	lda #<>t_ed_hilfe2
	jmp ed_text

; A (16 bit) = message (bank $FF), stays 4 s; returns Akku 8
ed_melden
	.al
	sta e_mtext
	#akku8
	lda #200
	sta e_meld
	inc e_neu
	rts

; A = DOS error 1-9 as a message (the workshop's texts)
ed_dosfehler
	.as
	dec a
	asl a
	#akku16
	and #$00ff
	clc
	adc #<>W_SD_FEHLERTEXTE
	sta e_p
	#akku8
	lda #`W_SD_FEHLERTEXTE
	sta e_p+2
	#akku16
	lda [e_p]
	jmp ed_melden

; The text rows
ed_text_zeichnen
	.as
	ldx e_top
	stx e_t0                    ; line start ($FFFF: after the last line)
	ldy #ED_OBEN * 160
	lda #ED_ZEILEN
	sta e_t2
_zeile
	ldx e_t0
	cpx #$ffff
	beq _leer
	jsr ed_zende
	stx e_t1
	#akku16
	lda e_t0
	clc
	adc e_links
	bcs +
	cmp e_t1
	bcc ++
+	lda e_t1
+	tax
	#akku8
	lda #80
	sta e_t3
-	cpx e_t1
	bcs _sp
	lda @l ED_BUF,x
	inx
	bra +
_sp	lda #' '
+	sta ED_SCHIRM,y
	lda #ED_F_TEXT
	sta ED_SCHIRM+1,y
	iny
	iny
	dec e_t3
	bne -
	ldx e_t1                    ; next line
	cpx e_len
	bcc +
	ldx #$ffff
	bra ++
+	inx
+	stx e_t0
	bra _naechste
_leer
	lda #80
	sta e_t3
-	lda #' '
	sta ED_SCHIRM,y
	lda #ED_F_TEXT
	sta ED_SCHIRM+1,y
	iny
	iny
	dec e_t3
	bne -
_naechste
	dec e_t2
	bne _zeile
	#akku16                     ; the cursor: its cell in black on yellow
	lda e_curnr
	sec
	sbc e_topnr
	clc
	adc #ED_OBEN
	#akku8
	jsr ed_zeile_x
	stx e_t1
	jsr ed_spalte               ; Akku 16
	.al
	sec
	sbc e_links
	asl a
	clc
	adc e_t1
	tax
	#akku8
	lda #ED_F_CURSOR
	sta ED_SCHIRM+1,x
	rts

;----------------------------------------------------------------------------
; Input in the status row. A (16 bit) = prompt; e_ein/e_elen hold the start
; text, e_emax the length, e_eart = 1 file name (A-Z 0-9 _ - ., Tab changes
; the drive). C = 0 Return, C = 1 Esc. Returns Akku 8.

ed_eingabe
	.al
	sta e_t2
	#akku8
_zeigen
	lda #ED_F_STATUS
	sta e_farbe
	lda #29
	jsr ed_zeile_leeren
	inx
	inx
	#akku16
	lda e_t2
	jsr ed_text
	.as
	ldy #0
-	tya
	cmp e_elen
	bcs +
	lda e_ein,y
	sta ED_SCHIRM,x
	inx
	inx
	iny
	bra -
+	lda #'_'
	sta ED_SCHIRM,x
	lda e_eart
	beq _warten
	ldx #29 * 160 + 50 * 2
	#akku16
	lda #<>t_ed_lw_tab
	jsr ed_text
	.as
	lda e_lw
	clc
	adc #'0'
	sta ED_SCHIRM+29*160+56*2
_warten
	wai
	jsr ed_getin
	beq _warten
	cmp #$03                    ; Esc
	bne +
	sec
	rts
+	cmp #$0d
	bne +
	clc
	rts
+	cmp #$08
	bne +
	lda e_elen
	beq _warten
	dec e_elen
	bra _zeigen
+	cmp #$09
	bne +
	lda e_eart
	beq _warten
	lda e_lw
	inc a
	and #3
	sta e_lw
	bra _zeigen
+	sta e_t3
	lda e_eart
	beq _frei
	lda e_t3                    ; file name: A-Z 0-9 _ - .
	jsr ed_gross
	cmp #'_'
	beq _nehmen
	cmp #'-'
	beq _nehmen
	cmp #'.'
	beq _nehmen
	cmp #'0'
	bcc _warten
	cmp #'9'+1
	bcc _nehmen
	cmp #'A'
	bcc _warten
	cmp #'Z'+1
	bcs _warten
	bra _nehmen
_frei
	lda e_t3
	cmp #$20
	bcc _warten
_nehmen
	sta e_t3
	lda e_elen
	cmp e_emax
	bcs _warten
	#akku16
	and #$00ff
	tax
	#akku8
	lda e_t3
	sta e_ein,x
	inc e_elen
	jmp _zeigen

ed_getin                        ; A = key (0 = none), Z from A
	.as
	phd
	pea 0
	pld
	jsl K_L_GETIN
	pld
	cmp #0
	rts

ed_gross                        ; a-z and the Latin-1 small letters
	.as
	cmp #'a'
	bcc +
	cmp #'z'+1
	bcc _klein
	cmp #$e0
	bcc +
	cmp #$f7
	beq +
	cmp #$ff
	beq +
_klein
	sec
	sbc #$20
+	rts

; A (16 bit) = question; C = 0: Y, C = 1: N or Esc. Returns Akku 8.
ed_frage
	.al
	sta e_t2
	#akku8
	lda #ED_F_STATUS
	sta e_farbe
	lda #29
	jsr ed_zeile_leeren
	inx
	inx
	#akku16
	lda e_t2
	jsr ed_text
	.as
-	wai
	jsr ed_getin
	beq -
	jsr ed_gross
	cmp #'Y'
	beq _ja
	cmp #'N'
	beq _nein
	cmp #$03
	bne -
_nein
	inc e_neu
	sec
	rts
_ja
	inc e_neu
	clc
	rts

; C = 0: the text may be thrown away (unchanged, or the user says so)
ed_verwerfen_ok
	.as
	lda e_geaendert
	bne +
	clc
	rts
+	#akku16
	lda #<>t_ed_verwerfen
	jsr ed_frage
	.as
	php
	jsr ed_tasten_merken
	plp
	rts

;----------------------------------------------------------------------------
; Files

ed_name_vorgeben                ; the file's name as the start text
	.as
	stz e_elen
	lda e_modus
	beq +
	ldx #0
-	txa
	cmp e_nlen
	bcs +
	lda e_name,x
	sta e_ein,x
	inx
	inc e_elen
	bra -
+	lda #ED_NAMEMAX
	sta e_emax
	lda #1
	sta e_eart
	rts

ed_name_nach_dos                ; e_ein -> DOS block; A, X, Y = default ending
	.as
	sta ED_DO_ENDUNG
	txa
	sta ED_DO_ENDUNG+1
	tya
	sta ED_DO_ENDUNG+2
	ldx #0
-	lda e_ein,x
	sta ED_DO_TEXT,x
	inx
	cpx #ED_NAMEMAX
	bne -
	lda e_elen
	sta ED_DO_TLEN
	lda e_lw
	sta ED_DO_LW
	stz ED_DO_MER
	rts

ed_dos_ruf                      ; A = DOS command; A = error, Z = 1 good
	.as
	phd
	pea 0
	pld
	jsl ED_DOS
	pld
	cmp #0
	rts

ed_name_merken                  ; e_ein -> e_name
	.as
	ldx #0
-	lda e_ein,x
	sta e_name,x
	inx
	cpx #ED_NAMEMAX
	bne -
	lda e_elen
	sta e_nlen
	rts

ed_oeffnen
	.as
	jsr ed_verwerfen_ok
	bcc +
	rts
+	jsr ed_name_vorgeben
	#akku16
	lda #<>t_ed_frage_oeffnen
	jsr ed_eingabe
	.as
	php
	jsr ed_tasten_merken
	inc e_neu
	plp
	bcc +
	rts
+	lda e_elen
	bne +
	rts
+	lda #'T'
	ldx #'X'
	ldy #'T'
	jsr ed_name_nach_dos
	#akku16
	lda #<>ED_TMP
	sta ED_D_ADR
	lda #ED_MAX
	sta ED_D_LAENGE
	stz ED_D_LAENGE+2
	#akku8
	lda #`ED_TMP
	sta ED_D_ADR+2
	lda #0
	jsr ed_dos_ruf
	beq +
	jmp ed_dosfehler
+	#akku16
	lda ED_D_LAENGE+2           ; longer than the editor takes?
	bne _zugross16
	lda ED_D_LAENGE
	cmp #ED_MAX
	bcs _zugross16
	sta e_t3                    ; file length
	#akku8
	jsr ed_ist_basic
	bcc _text
	lda #DOK_BASIC
	sta e_modus
	#akku16
	lda #<>ED_TMP
	sta e_q
	#akku8
	lda #`ED_TMP
	sta e_q+2
	jsr ed_liste
	bcs _zugross
	bra _geladen
_text
	lda #DOK_TEXT
	sta e_modus
	stz e_mitdaten
	jsr ed_text_rein
	bcs _zugross
_geladen
	jsr ed_name_merken
	stz e_geaendert
	jsr ed_dok_anfang
	lda e_mitdaten
	bne +
	#akku16
	lda #<>t_ed_geoeffnet
	jmp ed_melden
+	#akku16
	lda #<>t_ed_mit_daten
	jmp ed_melden
_zugross16
	#akku8
_zugross
	jsr ed_leer
	#akku16
	lda #<>t_ed_zugross
	jmp ed_melden

ed_dok_anfang
	.as
	#akku16
	stz e_cur
	stz e_curnr
	stz e_top
	stz e_topnr
	stz e_links
	stz e_will
	#akku8
	rts

ed_leer                         ; an empty, unnamed text
	.as
	#akku16
	stz e_len
	lda #1
	sta e_zeilen
	#akku8
	lda #DOK_TEXT
	sta e_modus
	stz e_nlen
	stz e_geaendert
	stz e_mitdaten
	jmp ed_dok_anfang

ed_neu_text
	.as
	jsr ed_verwerfen_ok
	bcs +
	jsr ed_leer
	#akku16
	lda #<>t_ed_neutext
	jmp ed_melden
+	rts

; File in ED_TMP (e_t3 bytes) a tokenized BASIC program? C = 1 yes; then
; e_mitdaten = 1 if more data follows the program (a workshop file)
ed_ist_basic
	.as
	#akku16
	stz e_t0                    ; offset of the line
	stz e_letzte
	stz e_hat
_zeile
	.al
	lda e_t0
	clc
	adc #2
	cmp e_t3
	beq +
	bcs _nein                   ; no room for the link
+	ldx e_t0
	lda @l ED_TMP,x
	bne _link
	lda e_t0                    ; link 0: the end of the program
	clc
	adc #2
	cmp e_t3                    ; C = 1: nothing follows
	#akku8
	lda #0
	bcs +
	lda #1
+	sta e_mitdaten
	sec
	rts
_link
	.al
	sec
	sbc #$4801
	bcc _nein
	sta e_t1                    ; offset of the next line
	cmp e_t3
	beq +
	bcs _nein
+	lda e_t0                    ; link, number, the closing 0 at least
	clc
	adc #5
	cmp e_t1
	beq +
	bcs _nein
+	lda @l ED_TMP+2,x           ; line numbers go up
	cmp #64000
	bcs _nein
	ldy e_hat
	beq +
	cmp e_letzte
	beq _nein
	bcc _nein
+	sta e_letzte
	lda #1
	sta e_hat
	txa                         ; the text: no 0 before its end, 0 at it
	clc
	adc #4
	tax
	lda e_t1
	dec a
	sta e_t2
	#akku8
-	cpx e_t2
	bcs +
	lda @l ED_TMP,x
	beq _nein8
	inx
	bra -
+	lda @l ED_TMP,x
	bne _nein8
	#akku16
	lda e_t1
	sta e_t0
	bra _zeile
_nein
	#akku8
_nein8
	clc
	rts

; ED_TMP (e_t3 bytes of text) -> the editor: CR LF and CR become LF, Tab
; spaces up to the next column of 8. C = 1 too long.
ed_text_rein
	.as
	#akku16
	lda #<>ED_TMP
	sta e_q
	stz e_t2                    ; column
	#akku8
	lda #`ED_TMP
	sta e_q+2
	ldy #0
	ldx #0
_zeichen
	cpy e_t3
	bcs _fertig
	lda [e_q],y
	iny
	cmp #$0d
	bne _kein_cr
	cpy e_t3                    ; CR LF: only the LF
	bcs _lf
	lda [e_q],y
	cmp #ED_LF
	beq _zeichen
_lf
	lda #ED_LF
_kein_cr
	cmp #ED_LF
	bne +
	jsr ed_put
	bcs _voll
	#akku16
	stz e_t2
	#akku8
	bra _zeichen
+	cmp #$09
	bne _normal
-	lda #' '
	jsr ed_put
	bcs _voll
	#akku16
	inc e_t2
	lda e_t2
	and #7
	#akku8
	bne -
	bra _zeichen
_normal
	jsr ed_put
	bcs _voll
	#akku16
	inc e_t2
	#akku8
	bra _zeichen
_fertig
	stx e_len
	jsr ed_dok_anfang
	jsr ed_alle_zeilen
	clc
	rts
_voll
	sec
	rts

ed_put                          ; A to the text at X; C = 1 full
	.as
	sta @l ED_BUF,x
	inx
	cpx #ED_MAX
	rts

ed_sichern
	.as
	lda e_modus
	cmp #DOK_BASIC
	bne +
	lda e_mitdaten
	beq +
	#akku16
	lda #<>t_ed_nicht_sichern
	jmp ed_melden
+	jsr ed_name_vorgeben
	#akku16
	lda #<>t_ed_frage_sichern
	jsr ed_eingabe
	.as
	php
	jsr ed_tasten_merken
	inc e_neu
	plp
	bcc +
	rts
+	lda e_elen
	bne +
	rts
+	lda e_modus
	cmp #DOK_TEXT
	bne _basic
	lda #'T'                    ; text as it is
	ldx #'X'
	ldy #'T'
	jsr ed_name_nach_dos
	#akku16
	lda #<>ED_BUF
	sta ED_D_ADR
	lda e_len
	sta ED_D_LAENGE
	stz ED_D_LAENGE+2
	#akku8
	lda #`ED_BUF
	sta ED_D_ADR+2
	bra _los
_basic
	#akku16                     ; tokenized, as LOAD expects it
	lda #$4801
	sta e_basis
	#akku8
	jsr ed_crunch
	bcc +
	rts
+	lda #'B'
	ldx #'A'
	ldy #'S'
	jsr ed_name_nach_dos
	#akku16
	lda #<>ED_TMP
	sta ED_D_ADR
	lda e_aus
	sta ED_D_LAENGE
	stz ED_D_LAENGE+2
	#akku8
	lda #`ED_TMP
	sta ED_D_ADR+2
_los
	lda #1
	jsr ed_dos_ruf
	beq +
	jmp ed_dosfehler
+	lda e_modus                 ; the program stays the program
	beq +
	jsr ed_name_merken
	stz e_geaendert
+	#akku16
	lda #<>t_ed_gesichert
	jmp ed_melden

ed_basic                        ; Ctrl+B: the program in memory
	.as
	lda e_modus
	bne +
	lda e_geaendert
	bne +
	rts                         ; already shown
+	jsr ed_verwerfen_ok
	bcs +
	lda #DOK_PROGRAMM
	sta e_modus
	#akku16
	stz e_curnr
	#akku8
	jsr ed_programm_holen
	#akku16
	lda #<>t_ed_ist_programm
	jmp ed_melden
+	rts

ed_als_programm                 ; Ctrl+P: this text replaces the program
	.as
	lda e_modus
	bne +
	#akku16
	lda #<>t_ed_schon_programm
	jmp ed_melden
+	#akku16                     ; check it first
	lda @l $000000+B_TXTTAB
	sta e_basis
	#akku8
	jsr ed_crunch
	bcs +
	lda #DOK_PROGRAMM
	sta e_modus
	jsr ed_geaendert
	#akku16
	lda #<>t_ed_wird_programm
	jmp ed_melden
+	rts

;----------------------------------------------------------------------------
; Find, go to line

ed_suchen
	.as
	ldx #0                      ; the last search text as the start
-	lda e_such,x
	sta e_ein,x
	inx
	cpx #20
	bne -
	lda e_slen
	sta e_elen
	lda #20
	sta e_emax
	stz e_eart
	#akku16
	lda #<>t_ed_frage_suchen
	jsr ed_eingabe
	.as
	php
	jsr ed_tasten_merken
	inc e_neu
	plp
	bcs _aus
	lda e_elen
	beq _aus
	sta e_slen
	ldx #0
-	lda e_ein,x
	sta e_such,x
	inx
	cpx #20
	bne -
	jmp ed_finden
_aus
	rts

ed_weiter                       ; Ctrl+G
	.as
	lda e_slen
	bne ed_finden
	jmp ed_suchen

; from the cursor + 1 to the end, then from the start (case does not matter)
ed_finden
	.as
	ldx e_cur
	cpx e_len
	bcs +
	inx
+	stx e_t3                    ; where the search started
-	cpx e_len
	bcs _vorn
	jsr ed_hier
	bcs _gefunden
	inx
	bra -
_vorn
	ldx #0
-	cpx e_t3
	bcs _nicht
	jsr ed_hier
	bcs _gefunden
	inx
	bra -
_nicht
	#akku16
	lda #<>t_ed_nicht_gefunden
	jmp ed_melden
_gefunden
	stx e_cur
	jsr ed_zaehlen
	jsr ed_will_setzen
	jsr ed_mitte
	inc e_neu
	rts

ed_hier                         ; does the search text start at X? C = 1 yes
	.as
	phx
	ldy #0
-	tya
	cmp e_slen
	bcs _ja
	cpx e_len
	bcs _nein
	lda @l ED_BUF,x
	jsr ed_gross
	sta e_t2
	lda e_such,y
	jsr ed_gross
	cmp e_t2
	bne _nein
	inx
	iny
	bra -
_ja
	plx
	sec
	rts
_nein
	plx
	clc
	rts

ed_zeile                        ; Ctrl+L: go to a line (BASIC: its number)
	.as
	stz e_elen
	lda #5
	sta e_emax
	stz e_eart
	#akku16
	lda #<>t_ed_frage_zeile
	jsr ed_eingabe
	.as
	php
	jsr ed_tasten_merken
	inc e_neu
	plp
	bcc +
	rts
+	ldy #0                      ; the number
	#akku16
	stz e_t3
	#akku8
_ziffer
	tya
	cmp e_elen
	bcs _zahl_da
	lda e_ein,y
	iny
	sec
	sbc #'0'
	cmp #10
	bcc +
	rts
+	pha
	#akku16
	lda e_t3                    ; * 10 + digit
	asl a
	sta e_t2
	asl a
	asl a
	clc
	adc e_t2
	sta e_t3
	#akku8
	pla
	#akku16
	and #$00ff
	clc
	adc e_t3
	sta e_t3
	#akku8
	bra _ziffer
_zahl_da
	lda e_modus
	cmp #DOK_TEXT
	bne _basic
	#akku16                     ; text: line n
	lda e_t3
	beq +
	dec a
+	jsr ed_gehe_zeile
	.al
	#akku8
	jmp ed_will_setzen
_basic
	#akku16                     ; BASIC: the first line numbered n or more
	stz e_curnr
	#akku8
	ldx #0
_zeilen
	stx e_t0
	jsr ed_zeilennummer
	.al
	cmp e_t3
	#akku8
	bcs _da
	ldx e_t0
	jsr ed_zende
	cpx e_len
	bcs _da
	inx
	#akku16
	inc e_curnr
	#akku8
	bra _zeilen
_da
	ldx e_t0
	stx e_cur
	jsr ed_will_setzen
	jmp ed_mitte

ed_zeilennummer                 ; X = line start -> A (16 bit) = its number (0: none)
	.as
	#akku16
	stz e_t2
	#akku8
-	cpx e_len
	bcs _ziffern
	lda @l ED_BUF,x
	cmp #' '
	bne _ziffern
	inx
	bra -
_ziffern
	cpx e_len
	bcs _fertig
	lda @l ED_BUF,x
	sec
	sbc #'0'
	cmp #10
	bcs _fertig
	pha
	#akku16
	lda e_t2
	asl a
	sta e_t1
	asl a
	asl a
	clc
	adc e_t1
	sta e_t2
	#akku8
	pla
	#akku16
	and #$00ff
	clc
	adc e_t2
	sta e_t2
	#akku8
	inx
	bra _ziffern
_fertig
	#akku16
	lda e_t2
	rts

;----------------------------------------------------------------------------
; Leaving the workshop: a changed program goes into BASIC

ed_verlassen
	.as
	jsr ed_besuch
	jsr ed_stand_laden
	jsr ed_stand_gilt
	bcc _nichts
	lda e_modus
	bne _nichts
	lda e_geaendert
	beq _nichts
	jsr ed_wortliste
	#akku16
	lda @l $000000+B_TXTTAB
	sta e_basis
	#akku8
	jsr ed_crunch
	bcs _offen
	#akku16                     ; fits below the strings? (1 KB for variables)
	lda e_basis
	clc
	adc e_aus
	bcs _zugross
	adc #1024
	bcs _zugross
	cmp @l $000000+B_MEMSIZ
	bcs _zugross
	lda e_aus                   ; the program to bank 1
	dec a
	ldx #<>ED_TMP
	ldy e_basis
	phb
	mvn `ED_TMP, $01
	plb
	lda e_basis                 ; BASIC as after CLR (like rom/spritedata.asm)
	clc
	adc e_aus
	sta @l $000000+B_VARTAB
	sta @l $000000+B_ARYTAB
	sta @l $000000+B_STREND
	lda @l $000000+B_MEMSIZ
	sta @l $000000+B_FRETOP
	lda e_basis
	dec a
	sta @l $000000+B_DATPTR
	#akku8
	lda #0
	sta @l $000000+B_OLDTXT+1
	stz e_geaendert
	jsr ed_stand_sichern
_nichts
	clc
	rts
_zugross
	.al
	lda #<>t_ed_basic_voll
	jsr ed_melden
	.as
_offen
	jsr ed_stand_sichern
	sec
	rts

;----------------------------------------------------------------------------
; Program <-> text

; Keyword index from the BASIC ROM (both word lists, in token order)
ed_wortliste
	.as
	ldx #255                    ; no keyword starts with any character yet
	lda #$ff
-	sta @l ED_ERST,x
	dex
	bpl -
	ldx #0
	#akku16
	lda #<>(B_RESLST - B_ROMLOC)
	jsr _liste
	lda #<>(B_M_RESLST - B_ROMLOC)
	jsr _liste
	txa
	lsr a
	#akku8
	sta e_wortz
	dec a                       ; chains per first character, from the back
	sta e_t2                    ; so that each keeps the token order
_kette
	lda e_t2
	jsr ed_wortzeiger
	lda [e_p]
	sta e_t3
	#akku16
	lda e_t3
	and #$007f
	tax
	#akku8
	lda @l ED_ERST,x
	pha
	lda e_t2
	sta @l ED_ERST,x
	#akku16
	lda e_t2
	and #$00ff
	tax
	#akku8
	pla
	sta @l ED_NAECHST,x
	dec e_t2
	bpl _kette
	rts
_liste                          ; A (16 bit) = list in bank $FF, X = index * 2
	.al
	sta e_p
	#akku8
	lda #$ff
	sta e_p+2
_wort
	lda [e_p]
	beq _fertig
	#akku16
	lda e_p
	sta @l ED_KW,x
	inx
	inx
_zeichen
	#akku8
	lda [e_p]
	#akku16
	inc e_p
	and #$0080
	beq _zeichen
	#akku8
	bra _wort
_fertig
	#akku16
	rts

ed_wortzeiger                   ; A = keyword number -> e_p (bank $FF); keeps X
	.as
	phx
	#akku16
	and #$00ff
	asl a
	tax
	lda @l ED_KW,x
	sta e_p
	#akku8
	lda #$ff
	sta e_p+2
	plx
	rts

; Program at e_q (link, number, text, 0 ... until link 0) -> text. C = 1
; too long (the text is then empty).
ed_liste
	.as
	ldx #0                      ; text offset
	ldy #0                      ; program offset
	#akku16
	stz e_zeilen
	#akku8
_zeile
	#akku16
	lda [e_q],y
	beq _ende
	iny
	iny
	lda [e_q],y                 ; line number and a space
	iny
	iny
	phy
	jsr ed_ziffern
	.as
	ldy #0
-	lda e_zif,y
	jsr ed_put
	bcs _voll_y
	iny
	cpy e_zn
	bne -
	ply
	lda #' '
	jsr ed_put
	bcs _voll
	stz e_t3                    ; in quotes
_byte
	lda [e_q],y
	iny
	cmp #0
	beq _zende
	cmp #'"'
	bne +
	pha
	lda e_t3
	eor #1
	sta e_t3
	pla
	bra _roh
+	cmp #$80
	bcc _roh
	pha
	lda e_t3
	bne _roh_pla
	pla
	sec
	sbc #$80
	cmp e_wortz
	bcs _kein
	jsr ed_wort_raus
	bcs _voll
	bra _byte
_kein
	clc
	adc #$80
	bra _roh
_roh_pla
	pla
_roh
	jsr ed_put
	bcs _voll
	bra _byte
_zende
	lda #ED_LF
	jsr ed_put
	bcs _voll
	#akku16
	inc e_zeilen
	#akku8
	bra _zeile
_ende
	.al
	#akku8
	stx e_len                   ; the last LF goes
	cpx #0
	beq +
	dex
	stx e_len
	clc
	rts
+	#akku16
	lda #1
	sta e_zeilen
	#akku8
	clc
	rts
_voll_y
	ply
_voll
	#akku16
	stz e_len
	lda #1
	sta e_zeilen
	#akku8
	sec
	rts

ed_wort_raus                    ; keyword A to the text at X; C = 1 full
	.as
	jsr ed_wortzeiger
	phy
	ldy #0
-	lda [e_p],y
	sta e_t2
	and #$7f
	jsr ed_put
	bcs +
	iny
	lda e_t2
	bpl -
	ply
	clc
	rts
+	ply
	sec
	rts

; The text -> a program in ED_TMP (e_aus bytes; links from e_basis). On an
; error: message, cursor on that line, C = 1.
ed_crunch
	.as
	#akku16
	stz e_aus
	stz e_hat
	#akku8
	stz e_ueber
	lda #`ED_BUF
	sta e_q+2
	ldx #0
_zeile
	cpx e_len
	bcc +
	jmp _ende
+	stx e_zanf
	jsr ed_zende
	stx e_zend
-	cpx e_zanf                  ; without trailing spaces
	beq +
	lda @l ED_BUF-1,x
	cmp #' '
	bne +
	dex
	bra -
+	stx e_rend
	ldx e_zanf                  ; leading spaces
-	cpx e_rend
	bcs _leer
	lda @l ED_BUF,x
	cmp #' '
	bne +
	inx
	bra -
+	sec                         ; a number
	sbc #'0'
	cmp #10
	bcc +
	#akku16
	lda #<>t_ed_keine_nr
	jmp _fehler
+	#akku16
	stz e_nr
	#akku8
_ziffer
	cpx e_rend
	bcs _nr_da
	lda @l ED_BUF,x
	sec
	sbc #'0'
	cmp #10
	bcs _nr_da
	pha
	#akku16
	lda e_nr
	cmp #6400
	bcs _zu_hoch
	asl a
	sta e_t1
	asl a
	asl a
	clc
	adc e_t1
	sta e_nr
	#akku8
	pla
	#akku16
	and #$00ff
	clc
	adc e_nr
	sta e_nr
	#akku8
	inx
	bra _ziffer
_zu_hoch
	#akku8
	pla
	#akku16
	lda #<>t_ed_nr_hoch
	jmp _fehler
_leer
	jmp _weiter
_nr_da
	#akku16
	lda e_nr
	cmp #64000
	bcc +
	lda #<>t_ed_nr_hoch
	jmp _fehler
+	ldy e_hat                   ; going up
	beq _ok
	cmp e_letzte
	beq _reihe
	bcs _ok
_reihe
	lda #<>t_ed_reihe
	jmp _fehler
_ok
	sta e_letzte
	lda #1
	sta e_hat
	#akku8
	cpx e_rend                  ; one space after the number belongs to it
	bcs +
	lda @l ED_BUF,x
	cmp #' '
	bne +
	inx
+	phx                         ; link (later) and number
	ldx e_aus
	#akku16
	lda e_nr
	sta @l ED_TMP+2,x
	txa
	clc
	adc #4
	sta e_aus
	sta e_kanf
	#akku8
	plx
	jsr ed_crunch_zeile
	lda e_ueber
	beq +
	#akku16
	lda #<>t_ed_basic_voll
	jmp _fehler
+	#akku16
	lda e_aus                   ; at most 250 bytes of text
	sec
	sbc e_kanf
	cmp #251
	bcc +
	lda #<>t_ed_zu_lang
	jmp _fehler
+	#akku8
	lda #0
	jsr ed_aus_byte
	#akku16
	lda e_kanf                  ; the link: address of the next line
	sec
	sbc #4
	tax
	lda e_aus
	clc
	adc e_basis
	sta @l ED_TMP,x
	#akku8
_weiter
	ldx e_zend                  ; next line of the text
	cpx e_len
	bcs _ende
	inx
	jmp _zeile
_ende
	lda #0                      ; 0, 0
	jsr ed_aus_byte
	jsr ed_aus_byte
	lda e_ueber
	bne +
	clc
	rts
+	#akku16
	lda #<>t_ed_basic_voll
_fehler                         ; Akku 16 = message
	.al
	jsr ed_melden
	.as
	ldx e_zanf
	stx e_cur
	jsr ed_zaehlen
	jsr ed_will_setzen
	jsr ed_mitte
	inc e_neu
	sec
	rts

ed_aus_byte                     ; A to ED_TMP at e_aus (keeps A and X)
	.as
	phx
	ldx e_aus
	sta @l ED_TMP,x
	inx
	cpx #ED_MAX
	bcc +
	inc e_ueber                 ; full: stays at the end
	dex
+	stx e_aus
	plx
	rts

; One line's text [X, e_rend) -> tokens (like Microsoft's CRUNCH)
ed_crunch_zeile
	.as
	#akku16
	stz e_rem
	stz e_data
	#akku8
_zeichen
	cpx e_rend
	bcc +
	rts
+	lda @l ED_BUF,x
	ldy e_rem
	beq +
	jsr ed_gross                ; after REM: the rest in capitals
	jsr ed_aus_byte
	inx
	bra _zeichen
+	cmp #'"'                    ; text up to the next quote
	bne _kein_text
-	jsr ed_aus_byte
	inx
	cpx e_rend
	bcs _zeichen
	lda @l ED_BUF,x
	cmp #'"'
	bne -
	jsr ed_aus_byte
	inx
	bra _zeichen
_kein_text
	ldy e_data
	beq +
	cmp #':'                    ; DATA: up to a colon
	bne _gross_raus
	stz e_data
	bra _gross_raus
+	cmp #'?'
	bne +
	lda #B_PRINTK
	jsr ed_aus_byte
	inx
	bra _zeichen
+	jsr ed_gross                ; a keyword starting here?
	#akku16
	and #$00ff
	phx
	tax
	#akku8
	lda @l ED_ERST,x
	plx
	sta e_t3
_wort
	lda e_t3
	cmp #$ff
	beq _kein_wort
	jsr ed_passt
	bcs _treffer
	phx
	#akku16
	lda e_t3
	and #$00ff
	tax
	#akku8
	lda @l ED_NAECHST,x
	plx
	sta e_t3
	bra _wort
_treffer
	sty e_t2                    ; length
	lda e_t3
	clc
	adc #B_ENDTK
	cmp #B_ELSETK               ; ELSE starts a statement: ":" in front
	bne +
	jsr ed_else
	lda #B_ELSETK
+	jsr ed_aus_byte
	cmp #B_REMTK
	bne +
	lda #1
	sta e_rem
	bra ++
+	cmp #B_DATATK
	bne +
	lda #1
	sta e_data
+	#akku16
	txa
	clc
	adc e_t2
	tax
	#akku8
	jmp _zeichen
_kein_wort
	lda @l ED_BUF,x
_gross_raus
	jsr ed_gross
	jsr ed_aus_byte
	inx
	jmp _zeichen

; keyword e_t3 at text X? C = 1 yes, Y = its length
ed_passt
	.as
	#akku16
	stx e_q
	lda e_rend
	sec
	sbc e_q
	sta e_rest
	#akku8
	lda e_t3
	jsr ed_wortzeiger
	ldy #0
-	cpy e_rest
	bcs _nein
	lda [e_q],y
	jsr ed_gross
	sta e_t2
	lda [e_p],y
	and #$7f
	cmp e_t2
	bne _nein
	lda [e_p],y
	iny
	asl a                       ; the last character has bit 7
	bcc -
	rts
_nein
	clc
	rts

ed_else                         ; ":" before ELSE unless there is one
	.as
	phx
	ldx e_aus
-	cpx e_kanf
	beq _nichts                 ; nothing before it
	lda @l ED_TMP-1,x
	dex
	cmp #' '
	beq -
	cmp #':'
	beq _nichts
	lda #':'
	jsr ed_aus_byte
_nichts
	plx
	rts

;----------------------------------------------------------------------------
; Texts

t_ed_hilfe  .null "^O open  ^S save  ^N new text  ^F find  ^G find next  ^L go to line"
t_ed_hilfe2 .null "^X cut line  ^C copy line  ^V paste  ^B BASIC program  ^P use as program"
t_ed_programm .null "BASIC PROGRAM in memory"
t_ed_ersetzt .null " - changed, applied on leaving"
t_ed_text   .null "TEXT "
t_ed_basicdatei .null "BASIC FILE "
t_ed_neu    .null "(new)"
t_ed_lw     .null "  drive "
t_ed_stern  .null "  *"
t_ed_zeile  .null "Ln "
t_ed_spalte .null " Col "
t_ed_lw_tab .null "drive    (Tab)  Return  Esc"
t_ed_frage_oeffnen .null "Open: "
t_ed_frage_sichern .null "Save as: "
t_ed_frage_suchen .null "Find: "
t_ed_frage_zeile .null "Go to line: "
t_ed_verwerfen .null "Throw away your changes? (Y/N)"
t_ed_geoeffnet .null "Opened."
t_ed_mit_daten .null "Opened. It has workshop data: to change it, LOAD it in BASIC"
t_ed_nicht_sichern .null "This file has workshop data: LOAD it in BASIC, F8, then SAVE"
t_ed_zugross .null "File too big for the editor (65279 bytes)"
t_ed_zulang .null "The program is too big for the editor"
t_ed_gesichert .null "Saved."
t_ed_neutext .null "New text"
t_ed_ist_programm .null "The BASIC program in memory"
t_ed_schon_programm .null "This is the program already"
t_ed_wird_programm .null "This text replaces the BASIC program when you leave"
t_ed_nicht_gefunden .null "Not found"
t_ed_voll   .null "The text is full (65279 bytes)"
t_ed_ablage_voll .null "Clipboard full"
t_ed_ablage_leer .null "Clipboard empty: ^X cuts a line, ^C copies it"
t_ed_kopiert .null "Line copied: ^V pastes it"
t_ed_keine_nr .null "This line needs a line number"
t_ed_nr_hoch .null "Line numbers go up to 63999"
t_ed_reihe  .null "Line numbers must go up"
t_ed_zu_lang .null "Line too long for BASIC (250 bytes)"
t_ed_basic_voll .null "The program is too big for BASIC memory"

;----------------------------------------------------------------------------
; Jump table (fixed: the workshop calls it)

	.cerror * > ED_SPRUNG, "EDIT: the SONG ROM is full"
	* = ED_SPRUNG
	jmp ed_zeichnen_e           ; $BFF0
	jmp ed_takt_e               ; $BFF3
	jmp ed_verlassen_e          ; $BFF6

	.dpage 0
