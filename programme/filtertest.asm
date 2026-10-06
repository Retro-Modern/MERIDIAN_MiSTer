;============================================================================
;  FILTERTEST - Filterausgang verzerren und ins Echo schicken (Etappe 18)
;
;  Stimme 0: Saege 110 Hz durch den Tiefpass (Resonanz C).
;    0,0 - 1,0 s  trocken (FILTER-ZERR 0, FILTER-ECHO 0)
;    1,0 - 2,0 s  FILTER-ZERR 8
;    ab 1,5 s     FILTER-ECHO 15 (Echo 300 ms, Rueckkopplung 8, Anteil 12)
;    2,0 s        Gate aus - danach muss eine Echo-Fahne bleiben
;  (Zeiten in Bildern zu 1/60 s.)
;
;  Assemblieren: programme/bauen.sh filtertest
;============================================================================

	.cpu "65816"

BILDER  = $50
ORG     = $C500
FILTER  = $C540
ECHO    = $C550

	* = $2000

start
	.as
	.xl
	lda #<1846                  ; 110 Hz (FREQ * 0,0596 Hz)
	sta ORG+0
	lda #>1846
	sta ORG+1
	stz ORG+5                   ; AD 00
	lda #$F0                    ; SR: Sustain 15
	sta ORG+6
	lda #15
	sta ORG+7
	lda #$FF
	sta ORG+8
	lda #<250                   ; Eckfrequenz
	sta FILTER+0
	lda #>250
	sta FILTER+1
	lda #$C1                    ; Resonanz C, Stimme 0 durchs Filter
	sta FILTER+2
	lda #$1F                    ; Tiefpass, Gesamtlautstaerke 15
	sta FILTER+3
	stz FILTER+5                ; FILTER-ECHO
	stz FILTER+6                ; FILTER-ZERR
	lda #<9375                  ; Echo 300 ms (9375 * 32 us)
	sta ECHO+0
	lda #>9375
	sta ECHO+1
	lda #8
	sta ECHO+2
	lda #12
	sta ECHO+3
	lda #$10                    ; Puffer im Zusatzspeicher ab $10:0000
	sta ECHO+4
	lda #$21                    ; Saege + Gate
	sta ORG+4
	lda #60
	jsr warten
	lda #8
	sta FILTER+6
	lda #30
	jsr warten
	lda #15
	sta FILTER+5
	lda #30
	jsr warten
	lda #$20                    ; Gate aus
	sta ORG+4
-	bra -

; A Bilder warten
warten
	.as
	clc
	adc BILDER
-	cmp BILDER
	bne -
	rts
