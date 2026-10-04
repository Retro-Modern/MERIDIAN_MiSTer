;============================================================================
;  RASTERBALKEN - erstes Programm fuer MERIDIAN, per Netz geladen
;
;  Haengt sich in den Interrupt-Haken des Kerns:
;   - Rasterinterrupt ab Zeile 48: fuer 168 Zeilen in jeder Austastluecke
;     die Hintergrundfarbe (Palette 6) neu setzen -> wandernde Farbbalken
;   - Timer A alle 10 ms: Stoppuhr im Dezimalmodus des 65816
;  Eine Taste beendet das Programm und raeumt alles wieder auf.
;
;  Assemblieren: programme/bauen.sh rasterbalken
;============================================================================

	.cpu "65816"

CHROUT       = $FF80
GETIN        = $FF83
PRINT        = $FF86
BENUTZER_IRQ = $0300
BILDSCHIRM   = $0400

PIN_PIDX   = $C008
PIN_PLO    = $C009
PIN_PHI    = $C00A
PIN_IRQEN  = $C00B
PIN_IRQST  = $C00C
PIN_ZEILE  = $C00D
PIN_ZEILEH = $C00E

PFO_IRQST  = $C104
PFO_IRQEN  = $C105
PFO_TA     = $C114
PFO_TASTEU = $C116

ERSTE      = 48                 ; erste Balkenzeile
ANZAHL     = 168                ; so viele Zeilen

	* = $2000

start
	.as
	.xl
	phb
	ldx #titel
	jsr PRINT

	sei
	rep #$20
	.al
	lda BENUTZER_IRQ            ; alten Haken merken, eigenen einsetzen
	sta alter_haken
	lda #haken
	sta BENUTZER_IRQ
	sep #$20
	.as
	stz phase
	stz hundertstel
	stz sekunden
	stz minuten

	lda #ERSTE                  ; Rasterinterrupt
	sta PIN_ZEILE
	stz PIN_ZEILEH
	lda #$03
	sta PIN_IRQEN

	lda #<9999                  ; Timer A: 10 000 us, immer wieder
	sta PFO_TA
	lda #>9999
	sta PFO_TA+1
	lda #$01
	sta PFO_TASTEU
	lda #$02
	sta PFO_IRQEN
	cli

warten
	wai
	jsr GETIN
	beq warten

	sei                         ; aufraeumen
	lda #$01
	sta PIN_IRQEN
	lda #$02
	sta PIN_IRQST
	stz PFO_TASTEU
	stz PFO_IRQEN
	lda #$06
	sta PFO_IRQST
	rep #$20
	.al
	lda alter_haken
	sta BENUTZER_IRQ
	sep #$20
	.as
	jsr hintergrund_normal
	cli
	ldx #ende
	jsr PRINT
	plb
	rtl

;----------------------------------------------------------------------------
; Interrupt-Haken: A = PINSEL-Status

haken
	pha
	lda PFO_IRQST               ; Timer A?
	and #$02
	beq _kein_timer
	sta PFO_IRQST
	sed                         ; Stoppuhr im Dezimalmodus
	lda hundertstel
	clc
	adc #$01
	sta hundertstel
	bcc _uhr_fertig             ; 99 + 1 = 00 mit Uebertrag
	lda sekunden
	adc #$00
	cmp #$60
	bcc _sek_ok
	lda #$00
	sta sekunden
	lda minuten
	clc
	adc #$01
	sta minuten
	bra _uhr_fertig
_sek_ok
	sta sekunden
_uhr_fertig
	cld
_kein_timer
	pla
	and #$02                    ; Rasterzeile?
	bne balken
	rts

balken
	sta PIN_IRQST
	ldy #0
_zeile
	lda PIN_ZEILE
-	cmp PIN_ZEILE               ; warten, bis die Austastluecke beginnt
	beq -
	tya
	clc
	adc phase
	rep #$20
	.al
	and #$003f
	asl a
	tax
	sep #$20
	.as
	lda #6
	sta PIN_PIDX
	lda farben,x
	sta PIN_PLO
	lda farben+1,x
	sta PIN_PHI
	iny
	cpy #ANZAHL
	bne _zeile
	jsr hintergrund_normal
	inc phase
	jmp uhr_zeigen

hintergrund_normal
	lda #6
	sta PIN_PIDX
	lda #$38
	sta PIN_PLO
	lda #$02
	sta PIN_PHI
	rts

; Stoppuhr oben rechts direkt in den Bildschirmspeicher schreiben
uhr_zeigen
	ldx #(0*40+31)*2
	lda minuten
	jsr bcd
	lda #':'
	jsr zeichen
	lda sekunden
	jsr bcd
	lda #'.'
	jsr zeichen
	lda hundertstel
	jsr bcd
	rts

bcd
	pha
	lsr a
	lsr a
	lsr a
	lsr a
	ora #'0'
	jsr zeichen
	pla
	and #$0f
	ora #'0'
zeichen
	sta BILDSCHIRM,x
	lda #$61                    ; weiss auf blau
	sta BILDSCHIRM+1,x
	inx
	inx
	rts

;----------------------------------------------------------------------------

titel
	.text 13, "RASTERBALKEN - loaded over the network.", 13
	.text "From line 48 on, every line gets a new", 13
	.text "background color during horizontal", 13
	.text "blanking. Top right: a stopwatch on", 13
	.text "timer A (10 ms) in decimal mode.", 13, 13
	.text "Any key ends the program.", 13, 0
ende
	.text "Program ended.", 13, 0

	.include "farben.inc"

alter_haken  .word 0
phase        .byte 0
hundertstel  .byte 0
sekunden     .byte 0
minuten      .byte 0
