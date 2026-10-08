;============================================================================
;  PRUEFSTAND - alle Chips des MERIDIAN in zwei Sekunden (MERIDIAN 1.0)
;
;  Spricht jeden Chip einmal kurz an und zeigt je Zeile OK oder ERROR mit
;  dem Grund:
;    CHIP RAM   16 KB ab $03:8000 mit zwei Mustern
;    EXPANSION  64 KB in Bank $20 (ohne SDRAM-Modul nur ein Hinweis)
;    KRAN       fuellen und kopieren im Chip-RAM, ueber den Zusatzspeicher
;    PINSEL     Register lesen, Rasterzeile laeuft, Bildzaehler laeuft
;    KOBOLD     zwei Sprites ueberlappen: Kollision gemeldet (Muster 127,
;               sonst der Mauszeiger, wird ein volles Quadrat - MOUSE 1
;               laedt den Pfeil wieder)
;    ORGEL      Stimme 3: Huellkurve steigt, Oszillator laeuft; Samplekanal
;               7 spielt und hoert auf - alles mit Lautstaerke 0, stumm
;    LOTSE      eine Befehlsliste mit SIGNAL wird ausgefuehrt
;    PFORTE     Mikrosekundenuhr zaehlt, Timer B meldet sich
;    TRUHE      Bootsektor von Laufwerk 1 (endet mit $55 $AA; ohne Diskette
;               nur ein Hinweis)
;  Gewartet wird mit Zaehlschleifen der CPU, nie mit einem Chip, der gerade
;  geprueft wird - ein toter Chip haelt den Pruefstand nicht an.
;
;  Assemblieren: programme/bauen.sh pruefstand
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

CHROUT = $FF80
PRINT  = $FF86
PRDEZ  = $FF89
zahl   = $1A                    ; 16 Bit fuer PRDEZ
BAENKE = $20                    ; Kern: Baenke mit Speicher (16 Bit)

PIN_IDX   = $C008
PIN_ZEILE = $C00D
PIN_BILD  = $C00F
PIN_B_SX  = $C030
PFO_IRQST = $C104
PFO_UHR   = $C110
PFO_TB    = $C118
PFO_TB_ST = $C11A
KOB_TAB   = $C300
KOB_STEU  = $C403
KOB_KOLL  = $C404
ORG_S3    = $C530               ; Synthesestimme 3
ORG_K7    = $CCB0               ; Samplekanal 7
KRAN_REG  = $C600
K_BEF     = $C610
LOT_LISTE = $C700
LOT_STEU  = $C703
LOT_STAT  = $C704
LOT_ANZ   = $C705
TR_BEF    = $C900
TR_LW     = $C901
TR_BLOCK  = $C902
TR_EIN    = $C906
TR_SEITE  = $C90C
TR_ANZAHL = $C90D
TR_PUF    = $CA00

TEST      = $038000             ; 16 KB Chip-RAM fuer die Tests
TEST_KOPIE = $039000
SAMPLE    = $03A000
LISTE     = $03B000
ZUS       = $200000

zeiger  = $80                   ; 3 Byte
fehler  = $84                   ; Zahl der Fehler
muster  = $85
t0      = $86                   ; 2 Byte
t1      = $88
hinweis = $8A                   ; 2 Byte: statt OK ein Hinweis (kein Fehler)
gerettet = $90                  ; 16 Byte: Sprites 30 und 31

	* = $2000

start
	.as
	.xl
	phb
	phd
	pea 0
	pld
	lda #0
	pha
	plb
	stz fehler
	ldx #t_titel
	jsr PRINT
	ldx #0                      ; die Tests der Reihe nach
-	phx
	lda tests_text,x            ; Name der Zeile
	sta t0
	lda tests_text+1,x
	sta t0+1
	ldx t0
	jsr PRINT
	plx
	phx
	stz hinweis
	stz hinweis+1
	jsr (tests,x)
	bcs _fehler
	ldx hinweis                 ; nicht pruefbar (kein Modul, keine Diskette)?
	bne +
	ldx #t_ok
+	jsr PRINT
	bra _weiter
_fehler
	phx
	ldx #t_error
	jsr PRINT
	plx
	jsr PRINT                   ; der Grund
	inc fehler
_weiter
	lda #13
	jsr CHROUT
	plx
	inx
	inx
	cpx #tests_ende - tests
	bne -
	lda fehler                  ; Ergebnis
	bne +
	ldx #t_alle
	jsr PRINT
	bra ++
+	sta zahl
	stz zahl+1
	jsr PRDEZ
	ldx #t_fehler
	jsr PRINT
+	pld
	plb
	rtl

tests
	.word chip_ram, zusatz, kran, pinsel, kobold, orgel, lotse, pforte, truhe
tests_ende
tests_text
	.word t_chip, t_zus, t_kran, t_pin, t_kob, t_org, t_lot, t_pfo, t_tru

t_titel .text 13, "MERIDIAN 816 TEST BENCH", 13, 0
t_chip  .text " CHIP RAM  16 KB      ", 0
t_zus   .text " EXPANSION 64 KB      ", 0
t_kran  .text " KRAN      FILL COPY  ", 0
t_pin   .text " PINSEL    REG RASTER ", 0
t_kob   .text " KOBOLD    COLLISION  ", 0
t_org   .text " ORGEL     VOICE SMPL ", 0
t_lot   .text " LOTSE     LIST       ", 0
t_pfo   .text " PFORTE    CLK TIMER  ", 0
t_tru   .text " TRUHE     DRIVE 1    ", 0
t_ok    .text "OK", 0
t_error .text "ERROR ", 0
t_alle  .text 13, "ALL CHIPS OK", 13, 0
t_fehler .text " ERROR(S)", 13, 0

;----------------------------------------------------------------------------
; Hilfen

warte                           ; X Durchlaeufe (je 5 Takte, 65535 = 41 ms)
-	dex
	bne -
	rts
warte_bild                      ; gut 2 Bilder
	ldx #$ffff
	jsr warte
	ldx #$ffff
	jmp warte

; 16 KB ab TEST mit Muster (Adresse xor muster), C = 1 bei Abweichung
muster_schreiben
	ldx #0
-	jsr muster_x
	sta @l TEST,x
	inx
	cpx #$4000
	bne -
	rts
muster_pruefen                  ; ab Bank:Adresse in zeiger, Y Byte
	ldx #0
-	jsr muster_x
	cmp @l TEST,x
	bne _falsch
	inx
	cpx #$4000
	bne -
	clc
	rts
_falsch
	sec
	rts
muster_x                        ; A = X-Low xor X-High xor muster
	txa
	xba
	sta t1
	xba
	eor t1
	eor muster
	rts

kran_los                        ; Auftrag aus job starten, warten (begrenzt)
	ldx #0
-	lda job,x
	sta KRAN_REG,x
	inx
	cpx #16
	bne -
	lda #$08
	sta K_BEF
	lda #$01
	sta K_BEF
	ldy #0
-	lda K_BEF
	and #$01
	beq +
	dey
	bne -
	sec                         ; nach 65536 Runden noch beschaeftigt
	rts
+	clc
	rts

;----------------------------------------------------------------------------
; Die Tests: C = 0 gut, sonst X = Grund

chip_ram
	lda #$00
	sta muster
	jsr muster_schreiben
	jsr muster_pruefen
	bcs _f
	lda #$ff
	sta muster
	jsr muster_schreiben
	jsr muster_pruefen
	bcs _f
	rts
_f
	ldx #g_muster
	sec
	rts

zusatz
	#akku16
	lda BAENKE
	cmp #$21
	bcs +
	lda #g_kein                 ; kein SDRAM-Modul: nur ein Hinweis
	sta hinweis
	#akku8
	clc
	rts
+	#akku8
	ldx #0                      ; 64 KB in Bank $20
-	jsr muster_x
	sta @l ZUS,x
	inx
	bne -
-	jsr muster_x
	cmp @l ZUS,x
	bne _f
	inx
	bne -
	clc
	rts
_f
	ldx #g_muster
	sec
	rts

kran
	lda #$5a                    ; fuellen: 4 KB mit $5A
	ldx #<>TEST
	ldy #<>TEST
	jsr job_setzen
	lda #$5a
	sta job+14
	lda #1
	sta job+15
	jsr kran_los
	bcs _haengt
	ldx #0
-	lda @l TEST,x
	cmp #$5a
	bne _fuell
	inx
	cpx #$1000
	bne -
	lda #$33                    ; kopieren: Muster nach TEST_KOPIE
	sta muster
	jsr muster_schreiben
	jsr job_kopie_chip
	jsr kran_los
	bcs _haengt
	ldx #0
-	jsr muster_x
	cmp @l TEST_KOPIE,x
	bne _kopie
	inx
	cpx #$1000
	bne -
	#akku16                     ; ueber den Zusatzspeicher (wenn es ihn gibt)
	lda BAENKE
	cmp #$21
	#akku8
	bcc _gut
	jsr job_kopie_chip          ; TEST -> ZUS
	lda #`ZUS
	sta job+5
	stz job+3
	stz job+4
	jsr kran_los
	bcs _haengt
	lda #`ZUS                   ; ZUS -> TEST_KOPIE (vorher geloescht)
	sta job+2
	stz job+0
	stz job+1
	lda #<TEST_KOPIE
	sta job+3
	lda #>TEST_KOPIE
	sta job+4
	lda #`TEST_KOPIE
	sta job+5
	ldx #0
	lda #0
-	sta @l TEST_KOPIE,x
	inx
	cpx #$1000
	bne -
	jsr kran_los
	bcs _haengt
	ldx #0
-	jsr muster_x
	cmp @l TEST_KOPIE,x
	bne _kopie
	inx
	cpx #$1000
	bne -
_gut
	clc
	rts
_haengt
	ldx #g_haengt
	sec
	rts
_fuell
	ldx #g_fuellen
	sec
	rts
_kopie
	ldx #g_kopie
	sec
	rts

job_setzen                      ; Quelle/Ziel im Chip-RAM bei TEST, 4 KB, eine Zeile
	#akku16
	lda #<>TEST
	sta job
	sta job+3
	lda #$1000
	sta job+6
	lda #1
	sta job+8
	stz job+10
	stz job+12
	#akku8
	lda #`TEST
	sta job+2
	sta job+5
	stz job+14
	stz job+15
	rts
job_kopie_chip                  ; TEST -> TEST_KOPIE, kopieren
	jsr job_setzen
	lda #<TEST_KOPIE
	sta job+3
	lda #>TEST_KOPIE
	sta job+4
	rts

pinsel
	lda PIN_IDX                 ; Palettenindex schreiben und lesen
	pha
	lda #$77
	sta PIN_IDX
	lda PIN_IDX
	sta t0
	pla
	sta PIN_IDX
	lda t0
	cmp #$77
	bne _reg
	lda PIN_B_SX                ; Rollen von Ebene B (wirkt nur auf Kacheln)
	pha
	lda #$a5
	sta PIN_B_SX
	lda PIN_B_SX
	sta t0
	pla
	sta PIN_B_SX
	lda t0
	cmp #$a5
	bne _reg
	lda PIN_ZEILE               ; Rasterzeile: nach 1 ms eine andere
	sta t0
	ldx #1600
	jsr warte
	lda PIN_ZEILE
	cmp t0
	beq _raster
	lda PIN_BILD                ; Bildzaehler: nach gut 2 Bildern weiter
	sta t0
	jsr warte_bild
	lda PIN_BILD
	cmp t0
	beq _bild
	clc
	rts
_reg
	ldx #g_reg
	sec
	rts
_raster
	ldx #g_raster
	sec
	rts
_bild
	ldx #g_bild
	sec
	rts

kobold
	ldx #15                     ; Sprites 30 und 31 retten
-	lda KOB_TAB+30*8,x
	sta gerettet,x
	dex
	bpl -
	lda KOB_STEU
	pha
	lda #<127*128               ; Muster 127 (der Mauszeiger, MOUSE 1 laedt
	sta KOB_TAB+$100            ; ihn neu): ein volles Quadrat in Farbe 1
	lda #>127*128
	sta KOB_TAB+$101
	ldx #128
	lda #$11
-	sta KOB_TAB+$102
	dex
	bne -
	ldx #0                      ; beide bei 100,100 mit Muster 127, an
-	#akku16
	lda #100+32
	sta KOB_TAB+30*8,x
	sta KOB_TAB+30*8+2,x
	#akku8
	lda #127
	sta KOB_TAB+30*8+4,x
	stz KOB_TAB+30*8+5,x
	lda #1
	sta KOB_TAB+30*8+6,x
	txa
	clc
	adc #8
	tax
	cpx #16
	bne -
	lda #1
	sta KOB_STEU
	sta KOB_KOLL                ; Kollisionen loeschen
	jsr warte_bild
	lda KOB_KOLL+3              ; Bits 30 und 31
	and #$c0
	sta t0
	ldx #15                     ; zurueck
-	lda gerettet,x
	sta KOB_TAB+30*8,x
	dex
	bpl -
	pla
	sta KOB_STEU
	sta KOB_KOLL
	lda t0
	cmp #$c0
	bne _f
	clc
	rts
_f
	ldx #g_koll
	sec
	rts

orgel
	lda #0                      ; Stimme 3 stumm: Saege, Gate, Anschlag 0
	sta ORG_S3+7                ; LAUT 0
	sta ORG_S3+5
	sta ORG_S3+0
	lda #$40                    ; FREQ $4000, knapp 1 kHz
	sta ORG_S3+1
	lda #$f0
	sta ORG_S3+6
	lda #$21
	sta ORG_S3+4
	ldx #$ffff                  ; 40 ms
	jsr warte
	lda ORG_S3+9                ; Huellkurve oben?
	sta t0
	lda ORG_S3+10               ; Oszillator: nach 0,1 ms ein anderer Wert
	sta t0+1
	ldx #160
	jsr warte
	lda ORG_S3+10
	sta t1
	stz ORG_S3+4                ; Gate aus
	stz ORG_S3+1
	lda t0
	cmp #$80
	bcc _huelle
	lda t1
	cmp t0+1
	beq _osz
	ldx #0                      ; Samplekanal 7: 1 KB Stille, 22 kHz, stumm
	lda #0
-	sta @l SAMPLE,x
	inx
	cpx #$400
	bne -
	stz ORG_K7+11               ; anhalten
	lda #<SAMPLE
	sta ORG_K7+0
	lda #>SAMPLE
	sta ORG_K7+1
	lda #`SAMPLE
	sta ORG_K7+2
	stz ORG_K7+3                ; Laenge $400
	lda #$04
	sta ORG_K7+4
	stz ORG_K7+14
	stz ORG_K7+5
	stz ORG_K7+6
	stz ORG_K7+15
	lda #<1445
	sta ORG_K7+7
	lda #>1445
	sta ORG_K7+8
	stz ORG_K7+9                ; LAUT 0
	lda #1                      ; starten, ohne Schleife
	sta ORG_K7+11
	ldx #16000                  ; 10 ms: spielt, Position weiter
	jsr warte
	lda ORG_K7+11
	and #1
	beq _sample
	lda ORG_K7+12
	ora ORG_K7+13
	beq _sample
	ldx #$ffff                  ; noch 80 ms: zu Ende (1 KB = 46 ms)
	jsr warte
	ldx #$ffff
	jsr warte
	lda ORG_K7+11
	and #1
	bne _ende
	clc
	rts
_huelle
	ldx #g_huelle
	sec
	rts
_osz
	ldx #g_osz
	sec
	rts
_sample
	stz ORG_K7+11
	ldx #g_sample
	sec
	rts
_ende
	stz ORG_K7+11
	ldx #g_ende
	sec
	rts

lotse
	lda LOT_STEU
	pha
	ldx #0                      ; Liste: SIGNAL, ENDE
-	lda lot_befehle,x
	sta @l LISTE,x
	inx
	cpx #8
	bne -
	stz LOT_STEU
	lda #1
	sta LOT_STAT                ; altes Signal weg
	lda #<LISTE
	sta LOT_LISTE
	lda #>LISTE
	sta LOT_LISTE+1
	lda #`LISTE
	sta LOT_LISTE+2
	php                         ; SIGNAL meldet sich nur mit erlaubtem
	sei                         ; Interrupt - die CPU nimmt ihn hier nicht an
	lda #3
	sta LOT_STEU
	jsr warte_bild
	lda LOT_STAT
	sta t0
	lda LOT_ANZ
	sta t1
	pla                         ; (P)
	sta t1+1
	pla
	sta LOT_STEU
	lda #1
	sta LOT_STAT                ; Meldung weg, bevor der Interrupt wieder darf
	lda t1+1
	pha
	plp
	lda t0
	and #1
	beq _f
	lda t1
	cmp #2
	bcc _f
	clc
	rts
_f
	ldx #g_signal
	sec
	rts
lot_befehle .byte $04, 0, 0, 0, $00, 0, 0, 0     ; SIGNAL, ENDE

pforte
	sta PFO_UHR                 ; Uhr festhalten und lesen
	#akku16
	lda PFO_UHR
	sta t0
	#akku8
	ldx #1600                   ; 1 ms
	jsr warte
	sta PFO_UHR
	#akku16
	lda PFO_UHR
	sec
	sbc t0                      ; vergangen (Mikrosekunden, untere 16 Bit)
	sta t1
	#akku8
	lda t1+1                    ; zwischen 256 und 16383 us
	beq _uhr
	cmp #$40
	bcs _uhr
	php                         ; Timer B einmal 500 us (ohne Interrupt)
	sei
	lda #$04
	sta PFO_IRQST
	lda #<499
	sta PFO_TB
	lda #>499
	sta PFO_TB+1
	lda #3                      ; laeuft, nur einmal
	sta PFO_TB_ST
	ldx #4000                   ; 2,5 ms
	jsr warte
	lda PFO_IRQST
	sta t0
	stz PFO_TB_ST
	lda #$04
	sta PFO_IRQST
	plp
	lda t0
	and #$04
	beq _timer
	clc
	rts
_uhr
	ldx #g_uhr
	sec
	rts
_timer
	ldx #g_timer
	sec
	rts

truhe
	lda TR_EIN
	and #$02
	bne +
	#akku16                     ; keine Diskette: nur ein Hinweis
	lda #g_keine
	sta hinweis
	#akku8
	clc
	rts
+	lda #1
	sta TR_LW
	stz TR_BLOCK
	stz TR_BLOCK+1
	stz TR_BLOCK+2
	stz TR_BLOCK+3
	lda #15
	sta TR_SEITE
	lda #1
	sta TR_ANZAHL
	stz TR_PUF+$1fe
	stz TR_PUF+$1ff
	lda #1                      ; Block lesen
	sta TR_BEF
	ldy #20                     ; hoechstens 20 x 41 ms
-	ldx #$ffff
	jsr warte
	lda TR_BEF
	and #1
	beq +
	dey
	bne -
	ldx #g_haengt
	sec
	rts
+	lda TR_BEF
	and #2
	bne _lesen
	lda TR_PUF+$1fe
	cmp #$55
	bne _sektor
	lda TR_PUF+$1ff
	cmp #$aa
	bne _sektor
	clc
	rts
_lesen
	ldx #g_lesen
	sec
	rts
_sektor
	ldx #g_sektor
	sec
	rts

g_muster .text "PATTERN", 0
g_kein   .text "-- NO SDRAM", 0
g_haengt .text "BUSY", 0
g_fuellen .text "FILL", 0
g_kopie  .text "COPY", 0
g_reg    .text "REGISTER", 0
g_raster .text "RASTER LINE", 0
g_bild   .text "FRAME COUNT", 0
g_koll   .text "COLLISION", 0
g_huelle .text "ENVELOPE", 0
g_osz    .text "OSCILLATOR", 0
g_sample .text "SAMPLE START", 0
g_ende   .text "SAMPLE END", 0
g_signal .text "SIGNAL", 0
g_uhr    .text "CLOCK", 0
g_timer  .text "TIMER B", 0
g_keine  .text "-- NO DISK", 0
g_lesen  .text "READ", 0
g_sektor .text "NO $55AA", 0

job	.fill 16
