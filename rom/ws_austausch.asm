;============================================================================
;  WERKSTATT: Sprites austauschen (SPRITES, Tasten S und L; 22.10.2026)
;  (eingebunden von werkstatt.asm)
;
;  Sprites in mehreren Programmen benutzen: eine eigene Datei, die die
;  Werkstatt wieder einliest, die Palette kommt mit.
;
;  S sichert die 128 Spritemuster mit ihren Baenken und den Look (Palette,
;  Leuchten, Tusche) als NAME.SPR. Aufbau wie eine mit SAVE gesicherte Datei
;  (ws_datei.asm): ein leeres BASIC-Programm (0, 0), die Abschnitte 1 und 5,
;  die Laenge des Programms (2) und "MWS1". LOAD "NAME.SPR" gibt also ein
;  leeres Programm mit diesen Sprites; tools/cartridge.py liest sie auch.
;
;  L holt Muster, Baenke und Look aus so einer Datei oder aus jedem mit SAVE
;  gesicherten Programm (mit Endung, z. B. GLOWMINE.BAS). Das Programm im
;  Speicher und die anderen Werkstatt-Daten bleiben, der Zeichensatz auch.
;  Hat die Quelle keinen eigenen Look, gilt der Startlook.
;
;  Name in der Statuszeile (jedes Mal leer): Sichern A-Z 0-9 _ - bis 8
;  Zeichen, die Datei heisst immer NAME.SPR (so trifft S nie ein Spiel);
;  Holen auch mit Punkt und Endung (8.3, ohne Endung .SPR). Tab wechselt
;  das Laufwerk (Vorgabe: DRIVE), Return los, Esc zurueck. Die Meldung
;  danach bleibt 3 s stehen (sd_halten, sp_status).
;============================================================================

DOS_RUF   = $FF4000
DATA_RUF  = $FF401B              ; Sprites als DATA-Zeilen
DO_LW     = $16C0               ; Parameterblock des DOS (Bank 0)
DO_MER    = $16C2
DO_ENDUNG = $16C3
DO_TLEN   = $16C6
DO_TEXT   = $16C7
DO_STD_LW = $16FF               ; DRIVE

SD_NAME_MAX = 12

	.virtual W_RAM+$40          ; nur waehrend eines Besuchs (ws_start setzt sie)
sd_modus  .byte ?               ; 0 sichern, 1 holen, 2 DATA-Zeilen
sd_lw     .byte ?               ; Laufwerk 0-3
sd_len    .byte ?               ; Laenge des Namens
sd_name   .fill SD_NAME_MAX+1   ; Name, mit 0
sd_fehler .byte ?               ; 0 gut, 1-9 DOS, $FA-$FC DATA-Zeilen (siehe
                                ; rom/spritedata.asm), $FD ohne Zusatz-
                                ; speicher, $FE keine Sprites in der Datei,
                                ; $FF keine gemalt
sd_zahl   .byte ?               ; geholte (DATA: geschriebene) Muster
sd_alt    .byte ?               ; Look: Bit 1 (Zeichensatz geaendert) vorher
sd_spr    .long ?               ; Abschnitte in der Datei (Bank 0 = keiner)
sd_look   .long ?
sd_halten .byte ?               ; Bilder, die die Meldung noch stehen bleibt (sp_status)
	.endv

;----------------------------------------------------------------------------
; S oder L in SPRITES (A = Taste, gross; D = W_RAM)

sd_taste
	.as
	ldy #0
	cmp #'S'
	beq +
	iny
	cmp #'L'
	beq +
	iny
+	tya
	sta sd_modus
	#akku16                     ; ohne Zusatzspeicher keine Werkstatt-Daten
	lda K_BAENKE
	cmp #$fd
	#akku8
	bcs +
	lda #$fd
	sta sd_fehler
	jmp sd_melden
+	cpy #2
	bne +
	ldy #sd_name                ; B: als DATA-Zeilen ins Programm (rom/spritedata.asm),
	jsl DATA_RUF                ; die erste Zeilennummer kommt nach sd_name
	sta sd_fehler
	txa
	sta sd_zahl
	bra sd_melden
+	jsr sd_eingabe
	bcc +
	jmp sp_status               ; Esc: Statuszeile wie vorher
+	ldx #0                      ; Name, Endung, Laufwerk fuer das DOS
-	lda sd_name,x
	sta DO_TEXT,x
	inx
	cpx #SD_NAME_MAX
	bne -
	lda sd_len
	sta DO_TLEN
	lda sd_lw
	sta DO_LW
	lda #'S'
	sta DO_ENDUNG
	lda #'P'
	sta DO_ENDUNG+1
	lda #'R'
	sta DO_ENDUNG+2
	stz DO_MER
	lda sd_modus
	phd                         ; Puffer und DOS mit D = 0 (wie SAVE/LOAD)
	pea 0
	pld
	.dpage 0
	cmp #0
	bne +
	jsr sd_sichern
	bra ++
+	jsr sd_holen
+	sta sd_fehler
	pld
	.dpage W_RAM
	lda sd_fehler
	bne sd_melden
	lda sd_modus
	beq sd_melden
	lda sp_m                    ; geholt: Muster neu laden, alles zeichnen
	jsr sp_waehlen
	; weiter: Meldung

; Ergebnis in der Statuszeile (bleibt, bis sie sich wieder aendert)
sd_melden
	.as
	lda #150                    ; 3 s stehen lassen (SPRITES schreibt die Zeile sonst
	sta sd_halten               ; jedes Bild neu)
	jsr sd_zeile_leeren
	lda sd_fehler
	beq _gut
	cmp #$fa
	bcc +
	sbc #$fa-9                  ; $FA-$FF -> 9-14
	bra ++
+	dec a                       ; DOS 1-9 -> 0-8
+	#akku16
	and #$00ff
	asl a
	tax
	lda @l sd_fehlertexte,x
	ldx #29 * 160 + 1 * 2
	ldy #`sd_fehlertexte
	jsr w_text_xy
	.as
	lda #F_STATUS
	jmp w_text
_gut
	lda sd_modus
	bne _geholt
	#text 29, 1, F_STATUS, t_sd_gesichert
	jsr sd_name_zeigen
	jmp sd_endung_zeigen
_geholt
	cmp #2
	bne +
	#text 29, 1, F_STATUS, t_sd_data1
	jsr _zahl
	#akku16
	lda #<>t_sd_data2
	ldy #`t_sd_data2
	jsr w_text_xy
	.as
	lda #F_STATUS
	jsr w_text
	jmp sd_name_zeigen
+	#text 29, 1, F_STATUS, t_sd_geholt1
	jsr _zahl
	#akku16
	lda #<>t_sd_geholt2
	ldy #`t_sd_geholt2
	jsr w_text_xy
	.as
	lda #F_STATUS
	jsr w_text
	jmp sd_name_zeigen
_zahl
	lda sd_zahl                 ; ohne fuehrende Nullen
	cmp #100
	bcs _drei
	cmp #10
	bcs _zwei
	jmp w_zahl1
_zwei
	jmp w_zahl2
_drei
	jmp w_zahl3

sd_zeile_leeren                 ; Zeile 29: Leerzeichen in F_STATUS
	.as
	ldx #29 * 160
-	lda #' '
	sta SCHIRM,x
	lda #F_STATUS
	sta SCHIRM+1,x
	inx
	inx
	cpx #30 * 160
	bne -
	rts

sd_endung_zeigen                ; ".SPR" ab SCHIRM+X
	.as
	#akku16
	lda #<>t_sd_endung
	ldy #`t_sd_endung
	jsr w_text_xy
	.as
	lda #F_STATUS
	jmp w_text

sd_name_zeigen                  ; Name ab SCHIRM+X, X dahinter
	.as
	#akku16
	lda #<>sd_name
	ldy #0
	jsr w_text_xy
	.as
	lda #F_STATUS
	jmp w_text

;----------------------------------------------------------------------------
; Name eingeben (Statuszeile). C = 0: Return mit Name, C = 1: Esc

sd_eingabe
	.as
	stz sd_len                  ; jedes Mal leer: ein alter Name (GLOWMINE.BAS)
	stz sd_name                 ; wuerde beim Sichern sonst das Spiel treffen
_zeigen
	jsr sd_zeile_leeren
	lda sd_modus
	bne +
	#text 29, 1, F_STATUS, t_sd_frage_s
	bra ++
+	#text 29, 1, F_STATUS, t_sd_frage_l
+	ldx #29 * 160 + 28 * 2
	jsr sd_name_zeigen
	lda #'_'                    ; Schreibmarke
	sta SCHIRM,x
	lda sd_modus                ; Sichern: immer NAME.SPR
	bne +
	inx
	inx
	jsr sd_endung_zeigen
+
	#text 29, 43, F_STATUS, t_sd_lw
	lda sd_lw
	ldx #29 * 160 + 49 * 2
	jsr w_zahl1
	#text 29, 51, F_STATUS, t_sd_knoepfe
_warten
	wai
	#kern K_L_GETIN
	cmp #0
	beq _warten
	cmp #$03                    ; Esc
	bne +
	sec
	rts
+	cmp #$0d                    ; Return (nur mit Name)
	bne +
	lda sd_len
	beq _warten
	clc
	rts
+	cmp #$08                    ; Rueckschritt
	bne +
	lda sd_len
	beq _warten
	dec sd_len
	bra _schluss
+	cmp #$09                    ; Tab: naechstes Laufwerk
	bne +
	lda sd_lw
	inc a
	and #3
	sta sd_lw
	jmp _zeigen
+	cmp #'_'                    ; erlaubt: A-Z 0-9 _ - .
	beq _nehmen
	cmp #'-'
	beq _nehmen
	cmp #'.'                    ; Punkt nur beim Holen (Endung angeben)
	bne ++
	pha
	lda sd_modus
	bne +
	pla
	bra _warten
+	pla
	bra _nehmen
+	cmp #'0'
	bcc _warten
	cmp #'9'+1
	bcc _nehmen
	cmp #'A'
	bcc _warten
	cmp #'Z'+1
	bcc _nehmen
	cmp #'a'
	bcc _warten
	cmp #'z'+1
	bcs _warten
	and #$df                    ; gross
_nehmen
	pha
	lda sd_modus                ; hoechstens 8 Zeichen (Sichern) bzw. 8.3
	beq +
	lda #SD_NAME_MAX
	bra ++
+	lda #8
+	cmp sd_len
	beq +
	bcs ++
+	pla                         ; voll
	jmp _warten
+	lda sd_len
	#akku16
	and #$00ff
	tax
	#akku8
	pla
	sta sd_name,x
	inc sd_len
_schluss                        ; 0 hinter den Namen
	lda sd_len
	#akku16
	and #$00ff
	tax
	#akku8
	stz sd_name,x
	jmp _zeigen

;----------------------------------------------------------------------------
; Mit D = 0 (wie ws_sichern/ws_laden): Puffer WS_PUFFER, Hilfswerte dz_*

	.dpage 0

; Sichern: leeres Programm, Sprites, Look, Schluss; dann die Datei. A = Fehler
sd_sichern
	.as
	ldx #<>KART                 ; ueberhaupt Muster da?
	lda #`KART
	ldy #SPR_LAENGE
	jsr ws_belegt
	bcs +
	lda #$ff
	rts
+	#akku16
	lda #0                      ; leeres BASIC-Programm: 0, 0
	sta @l WS_PUFFER
	lda #<>(WS_PUFFER+2)
	sta dz_z
	#akku8
	lda #`WS_PUFFER
	sta dz_z+2
	lda #ART_SPRITES
	ldx #SPR_LAENGE
	jsr ws_kopf
	ldx #<>KART
	lda #`KART
	ldy #SPR_LAENGE
	jsr ws_teil
	lda #ART_LOOK
	ldx #LK_LAENGE
	jsr ws_kopf
	ldx #<>KART_LOOK
	lda #`KART_LOOK
	ldy #LK_LAENGE
	jsr ws_teil
	jsr ws_zeiger_z             ; Schluss: Laenge des Programms (2), "MWS1"
	lda #2
	sta [K_ZEIGER]
	lda #0
	ldy #1
	sta [K_ZEIGER],y
	iny
	sta [K_ZEIGER],y
	ldx #0
	ldy #3
-	lda @l t_kennung,x
	sta [K_ZEIGER],y
	inx
	iny
	cpy #7
	bne -
	#akku16                     ; Laenge = Ende - Puffer
	lda dz_z
	clc
	adc #7
	sta D_LAENGE
	#akku8
	lda dz_z+2
	adc #0
	sec
	sbc #`WS_PUFFER
	sta D_LAENGE+2
	stz D_LAENGE+3
	#akku16
	lda #<>WS_PUFFER
	sta D_ADR
	#akku8
	lda #`WS_PUFFER
	sta D_ADR+2
	lda #1
	jsl DOS_RUF
	rts

; Holen: Datei nach WS_PUFFER, Abschnitte Sprites und Look suchen, verteilen.
; A = Fehler
sd_holen
	.as
	#akku16
	lda #<>WS_PUFFER
	sta D_ADR
	stz D_LAENGE
	#akku8
	lda #`WS_PUFFER
	sta D_ADR+2
	lda #2                      ; hoechstens 128 KB
	sta D_LAENGE+2
	stz D_LAENGE+3
	lda #0
	jsl DOS_RUF
	cmp #0
	beq +
	rts
+	lda D_LAENGE+2              ; mindestens 7 Byte?
	bne +
	#akku16
	lda D_LAENGE
	cmp #7
	#akku8
	bcs +
	jmp _ohne
+	#akku16                     ; K_ZEIGER = Ende - 7
	lda D_LAENGE
	sec
	sbc #7
	sta K_ZEIGER
	#akku8
	lda D_LAENGE+2
	sbc #0
	clc
	adc #`WS_PUFFER
	sta K_ZEIGER+2
	ldy #3                      ; "MWS1"?
	ldx #0
-	lda [K_ZEIGER],y
	cmp @l t_kennung,x
	beq +
	jmp _ohne
+	iny
	inx
	cpx #4
	bne -
	#akku16                     ; Abschnitte: Puffer + Programm bis Ende - 7
	lda [K_ZEIGER]
	sta dz_q
	lda K_ZEIGER
	sta dz_e
	#akku8
	ldy #2
	lda [K_ZEIGER],y
	clc
	adc #`WS_PUFFER
	sta dz_q+2
	lda K_ZEIGER+2
	sta dz_e+2
	#akku16
	stz sd_spr
	stz sd_look
	#akku8
	stz sd_spr+2
	stz sd_look+2
_abschnitt
	lda dz_q+2                  ; dz_q < dz_e?
	cmp dz_e+2
	bcc +
	bne _ende
	#akku16
	lda dz_q
	cmp dz_e
	#akku8
	bcs _ende
+	#akku16                     ; Kopf: Art, Laenge (3)
	lda dz_q
	sta K_ZEIGER
	#akku8
	lda dz_q+2
	sta K_ZEIGER+2
	ldy #1
	#akku16
	lda [K_ZEIGER],y
	sta dz_r
	#akku8
	ldy #3
	lda [K_ZEIGER],y
	sta dz_r+2
	#akku16                     ; Daten ab Kopf + 4
	lda dz_q
	clc
	adc #4
	sta dz_q
	#akku8
	lda dz_q+2
	adc #0
	sta dz_q+2
	lda dz_r+2
	bne _weiter
	lda [K_ZEIGER]
	cmp #ART_SPRITES
	bne +
	ldx #SPR_LAENGE
	jsr ws_laenge
	bne _weiter
	#akku16
	lda dz_q
	sta sd_spr
	#akku8
	lda dz_q+2
	sta sd_spr+2
	bra _weiter
+	cmp #ART_LOOK
	bne _weiter
	ldx #LK_LAENGE
	jsr ws_laenge
	bne _weiter
	#akku16
	lda dz_q
	sta sd_look
	#akku8
	lda dz_q+2
	sta sd_look+2
_weiter                         ; zum naechsten Abschnitt
	#akku16
	lda dz_q
	clc
	adc dz_r
	sta dz_q
	#akku8
	lda dz_q+2
	adc dz_r+2
	sta dz_q+2
	jmp _abschnitt
_ende
	lda sd_spr+2
	bne +
_ohne
	lda #$fe                    ; keine Sprites in dieser Datei
	rts
+	#akku16                     ; Muster und Baenke
	lda sd_spr
	sta dz_q
	lda #SPR_LAENGE
	sta dz_r
	#akku8
	lda sd_spr+2
	sta dz_q+2
	stz dz_r+2
	ldx #<>KART
	lda #`KART
	jsr ws_hin
	lda @l KART_LOOK            ; Look: der Zeichensatz bleibt, wie er ist
	and #2
	sta sd_alt
	lda sd_look+2
	beq _startlook
	#akku16
	lda sd_look
	sta dz_q
	lda #LK_LAENGE
	sta dz_r
	#akku8
	lda sd_look+2
	sta dz_q+2
	stz dz_r+2
	ldx #<>KART_LOOK
	lda #`KART_LOOK
	jsr ws_hin
	lda @l KART_LOOK
	and #1
	ora sd_alt
	sta @l KART_LOOK
	bra _zaehlen
_startlook
	jsr ws_vorgaben_look        ; behaelt Bit 1 selbst
_zaehlen                        ; belegte Muster zaehlen (fuer die Meldung)
	stz sd_zahl
	ldx #0
_muster
	ldy #128
-	lda @l KART_MUSTER,x
	bne _belegt
	inx
	dey
	bne -
	bra _naechstes
_belegt
	inc sd_zahl
	#akku16
	txa
	ora #$007f
	inc a
	tax
	#akku8
_naechstes
	cpx #$4000
	bcc _muster
	lda #0
	rts

	.dpage W_RAM

;----------------------------------------------------------------------------
; Texte

t_sd_hilfe     .null "S save as NAME.SPR  L load from .SPR or program  B as DATA lines in program"
t_sd_frage_s   .null "Save sprites + look as"
t_sd_frage_l   .null "Load sprites + look from"
t_sd_lw        .null "drive"
t_sd_knoepfe   .null "(Tab)  Return go  Esc back"
t_sd_gesichert .null "Saved sprites + look: "
t_sd_geholt1   .null "Loaded "
t_sd_geholt2   .null " patterns + look from "
t_sd_data1     .null "Wrote "
t_sd_data2     .null " patterns as DATA lines into the program: GOSUB "
t_sd_endung    .null ".SPR"

sd_fehlertexte
	.word <>t_sd_f1, <>t_sd_f2, <>t_sd_f3, <>t_sd_f4, <>t_sd_f5, <>t_sd_f6
	.word <>t_sd_f7, <>t_sd_f8, <>t_sd_f9, <>t_sd_ffa, <>t_sd_ffb, <>t_sd_ffc
	.word <>t_sd_ffd, <>t_sd_ffe, <>t_sd_fff
t_sd_f1  .null "Not possible on this drive"
t_sd_f2  .null "File not found (a program needs its ending, e.g. GAME.BAS)"
t_sd_f3  .null "Disk full"
t_sd_f4  .null "No disk in this drive"
t_sd_f5  .null "Not a FAT16 disk"
t_sd_f6  .null "Disk is write-protected"
t_sd_f7  .null "Directory full"
t_sd_f8  .null "File too big"
t_sd_f9  .null "Invalid name (8.3: A-Z 0-9 _ -)"
t_sd_ffa .null "Program lines follow the old DATA lines"
t_sd_ffb .null "No line numbers left for the DATA lines"
t_sd_ffc .null "Not enough BASIC memory for the DATA lines"
t_sd_ffd .null "Needs the memory expansion (SDRAM)"
t_sd_ffe .null "No sprites in this file"
t_sd_fff .null "No sprites drawn yet"
