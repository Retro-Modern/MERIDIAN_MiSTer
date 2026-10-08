;============================================================================
;  TAKTSTOCK - Rechnung des Synth-Pults im Abspieler (aus pult.asm)
;
;  Eingebunden vom Modul (pult.asm, PULT_RECHNEN) und vom System-ROM des
;  MERIDIAN (rom/song.asm, BASIC SONG). Wer einbindet, setzt PR_PERIODEN auf
;  eine Kopie der Periodentabelle des Abspielers (lang gelesen).
;============================================================================

;============================================================================
;  Abspieler-Teil (PULT_RECHNEN): direkte Seite = SP_RAM, X = Kanal * 2.
;  A = 0 Anschlag (in sp_stimme), 1 Tick (vor der Ausgabe), 2 GLIDE pruefen
;  (C = 1: gleitet statt anzuschlagen). Rueckkehr mit RTL.
;============================================================================

	.dpage SP_RAM

pu_rechnen
	.as
	.xl
	cmp #1
	beq _tick
	bcs _gleiten
	jsr pr_anschlag
	rtl
_tick
	jsr pr_tick
	rtl
_gleiten
	jsr pr_gleiten
	rtl

; sp_pz = Pult des Instruments k_ins,x
pr_pz
	.as
	#akku16
	lda k_ins,x
	and #$003f
	asl a
	asl a
	asl a
	clc
	adc sp_pbasis
	sta sp_pz
	#akku8
	lda sp_pbasis+2
	adc #0
	sta sp_pz+2
	rts

; Anschlag einer Synthstimme: Filter-Huellkurve (nur durchs Filter), DRIVE
; und ECHO des Filterausgangs. sp_ecke steht schon auf der Vorgabe des
; Instruments (oder Jxx) - das ist die Grundlage.
pr_anschlag
	.as
	jsr pr_pz
	lda k_filter,x
	bpl _effekte
	ldy #PU_ENV
	lda [sp_pz],y
	bne +
	stz sp_fan                  ; ohne ENV MOD: eine laufende Huellkurve endet
	bra _effekte
+	#akku16
	and #$00ff
	asl a
	asl a
	asl a                       ; Hub = ENV MOD * 8 (bis 2040)
	sta sp_fenv
	lda sp_ecke
	sta sp_fbasis
	#akku8
	lda k_vol,x                 ; Akzent: laute Note
	cmp #48
	bcc +
	ldy #PU_AKZENT
	lda [sp_pz],y
	#akku16
	and #$00ff
	asl a
	asl a                       ; + ACCENT * 4 (bis 1020)
	clc
	adc sp_fenv
	sta sp_fenv
	#akku8
+	ldy #PU_DECAY               ; je Tick um (255 - DECAY)^2 / 65536, mindestens
	lda [sp_pz],y               ; 1/256 - quadratisch, damit der Regler auch
	eor #$ff                    ; lange Fahnen fein einstellt
	#akku16
	and #$00ff
	sta sp_t0
	sta sp_t1
	stz sp_t2
	ldy #8
-	lsr sp_t1
	bcc +
	lda sp_t2
	clc
	adc sp_t0
	sta sp_t2
+	asl sp_t0
	dey
	bne -
	lda sp_t2
	xba                         ; / 256
	#akku8
	cmp #0
	bne +
	inc a
+	sta sp_frate
	lda #1
	sta sp_fan
	jsr pr_ecke
_effekte
	ldy #PU_SCHALTER
	lda [sp_pz],y
	lsr a
	bcc _r
	ldy #PU_DRIVE
	lda [sp_pz],y
	sta FILTER+6                ; wie Txx
	ldy #PU_ECHO
	lda [sp_pz],y
	sta FILTER+5                ; wie Sxx
	beq _r
	lda sp_ezeit                ; das Echo hat noch keine Zeit: drei Zeilen,
	ora sp_ezeit+1              ; etwas Rueckkopplung (wie O48 und P03)
	bne _r
	lda #4
	sta ECHO+2
	lda #8
	sta ECHO+3
	jsr pr_echo_zeit
_r	rts

; Echo-Zeit fuer drei Zeilen: 3 * Tempo * 78125 / BPM (32-us-Schritte),
; gerechnet als 3 * Tempo * 2 * (39062 / BPM), hoechstens 32767
pr_echo_zeit
	.as
	#akku16
	lda #39062
	sta sp_t0
	lda sp_bpm
	and #$00ff
	bne +
	inc a
+	sta sp_t1
	jsr pr_teilen               ; sp_t0 = 39062 / BPM
	asl sp_t0
	lda sp_tempo
	and #$00ff
	sta sp_t1
	asl a
	clc
	adc sp_t1                   ; 3 * Tempo
	tay
	lda #0
-	cpy #0
	beq +
	clc
	adc sp_t0
	bcs _voll
	bmi _voll
	dey
	bra -
_voll
	lda #32767
+	sta sp_ezeit
	sta ECHO
	#akku8
	rts

; sp_t0 = sp_t0 / sp_t1 (16 Bit), Akku 16 Bit
pr_teilen
	.al
	lda #0
	ldy #16
-	asl sp_t0
	rol a
	cmp sp_t1
	bcc +
	sbc sp_t1
	inc sp_t0
+	dey
	bne -
	rts

; sp_ecke = Grundlage + Huellkurve (hoechstens 2047)
pr_ecke
	.as
	#akku16
	lda sp_fbasis
	clc
	adc sp_fenv
	cmp #2048
	bcc +
	lda #2047
+	sta sp_ecke
	#akku8
	rts

; je Tick: Filter-Huellkurve abklingen lassen, gleitende Stimmen nachfuehren
pr_tick
	.as
	lda sp_fan
	beq _gleiten
	#akku16                     ; Hub -= (Hub/16) * Rate / 16, mindestens 1
	lda sp_fenv
	lsr a
	lsr a
	lsr a
	lsr a
	sta sp_t0                   ; hoechstens 191
	lda sp_frate
	and #$00ff
	sta sp_t1
	stz sp_t2
	ldy #8
-	lsr sp_t1
	bcc +
	lda sp_t2
	clc
	adc sp_t0
	sta sp_t2
+	asl sp_t0
	dey
	bne -
	lda sp_t2
	lsr a
	lsr a
	lsr a
	lsr a
	bne +
	inc a
+	sta sp_t0
	lda sp_fenv
	sec
	sbc sp_t0
	bcs +
	lda #0
+	sta sp_fenv
	bne +
	#akku8
	stz sp_fan                  ; abgeklungen
	#akku16
+	#akku8
	jsr pr_ecke
_gleiten
	lda sp_gl
	beq _r
	ldx #0
-	lda @l pr_bit,x
	and sp_gl
	beq +
	jsr pr_gleit_schritt
+	inx
	inx
	cpx #8
	bne -
_r	rts

pr_bit	.byte 1, 0, 2, 0, 4, 0, 8, 0

; Spur X einen Schritt zur Zielnote; angekommen: Gleiten aus
pr_gleit_schritt
	.as
	#akku16
	lda k_per,x
	cmp k_ziel,x
	beq _da
	bcc _tiefer                 ; Ziel hat die groessere Periode
	sec
	sbc g_tempo,x
	bcc _ziel
	cmp k_ziel,x
	bcs _setzen
_ziel
	lda k_ziel,x
	bra _setzen
_tiefer
	clc
	adc g_tempo,x
	bcs _ziel
	cmp k_ziel,x
	bcs _ziel
_setzen
	sta k_per,x
	cmp k_ziel,x
	bne _weiter
_da
	#akku8
	lda @l pr_bit,x
	trb sp_gl
	rts
_weiter
	#akku8
	rts

; GLIDE: Klingt auf Synthspur X noch eine Note und hat das Instrument GLIDE,
; gleitet die Tonhoehe in 1 + GLIDE/32 Ticks zur neuen Note sp_n - ohne
; neuen Anschlag, wie das Slide der 303. C = 1: gleitet
pr_gleiten
	.as
	cpx #8
	bcs _nein
	lda k_gate,x
	beq _nein
	jsr pr_pz
	ldy #PU_GLIDE
	lda [sp_pz],y
	beq _nein
	lsr a
	lsr a
	lsr a
	lsr a
	lsr a
	inc a
	sta sp_t5                   ; Ticks
	lda sp_n
	sta k_note,x
	#akku16
	and #$00ff
	asl a
	phx
	tax
	lda @l PR_PERIODEN,x
	plx
	sta k_ziel,x
	sec
	sbc k_per,x
	bcs +
	eor #$ffff
	inc a
+	sta sp_t0                   ; Abstand / Ticks = Schritt je Tick
	lda sp_t5
	and #$00ff
	sta sp_t1
	jsr pr_teilen
	lda sp_t0
	bne +
	inc a
+	sta g_tempo,x
	#akku8
	lda @l pr_bit,x
	tsb sp_gl
	sec
	rts
_nein
	clc
	rts

	.dpage 0
