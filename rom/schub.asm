;============================================================================
;  SCHUB aus BASIC: SCHUB adr / SCHUB 0 und SCHUB(n[,a[,b[,c]]])
;
;  SCHUB adr  haelt SCHUB an, setzt die Startadresse (durch 4 teilbar),
;             leert das Postfach und startet SCHUB (schaltet es auch ein,
;             wenn es im Menue aus war). Den Code legt das Programm vorher
;             hin, meist mit BLOAD "NAME",262144.
;  SCHUB 0    haelt SCHUB an und schaltet es aus (wie im Menue).
;  SCHUB(-1)  Status ($CD09).
;  SCHUB(n,…) ruft Funktion n (0 bis 8 388 607) des laufenden RISC-V-
;             Programms ueber das Postfach und wartet auf das Ergebnis.
;
;  Postfach im Zusatzspeicher (RISC-V: ungecacht ab $80FE1800), je 32 Bit:
;   $FE:1800  Zustand: 0 frei, 1 Auftrag (BASIC), 2 fertig (SCHUB)
;   $FE:1804  n         $FE:1808  a      $FE:180C  b      $FE:1810  c
;   $FE:1814  Ergebnis  (Werte mit Vorzeichen, fehlende Werte 0)
;  Das RISC-V-Programm wartet, bis der Zustand 1 ist, liest n und die Werte,
;  schreibt das Ergebnis und dann den Zustand 2. BASIC setzt ihn auf 0.
;
;  Einspruenge (JSL, Akku 8 Bit, Indexregister 16 Bit, Datenbank 0):
;   $FF:4030  schub_befehl   Kern-Befehl 29: Wert in P_WERT_M;
;                            A = 0 gut, 1 falscher Wert / kein SCHUB
;   $FF:4033  schub_funktion Kern-Funktion 10: Werte in P_WERT_M, Ergebnis
;                            (32 Bit) in P_WERT_M+0..3; A = 0 gut,
;                            1 SCHUB laeuft nicht / Adressfehler, 3 Esc
;============================================================================

SB_STATUS  = $00CD09            ; Bit 7 da, 3 Adressfehler, 2 Bus, 1 laeuft
SB_STEUER  = $00CD08            ; Bit 0 an, Bit 1 laufen
SB_START   = $00CD0C            ; Startadresse (nur angehalten schreibbar)
SB_POST    = $FE1800            ; Postfach (siehe oben)
SB_ANZ     = $000000 + P_ANZ_M
SB_WERT    = $000000 + P_WERT_M
SB_STOPP   = $00FFD0            ; Kern: A = 3, wenn Esc gedrueckt wurde

schub_befehl
	.as
	.xl
	jsr sb_da
	bne sb_falsch               ; kein SCHUB in diesem Kern
	lda @l SB_ANZ
	cmp #1
	bne sb_falsch
	jsr sb_halt
	lda @l SB_WERT
	ora @l SB_WERT+1
	ora @l SB_WERT+2
	beq sb_gut                  ; SCHUB 0: aus
	lda @l SB_WERT              ; Adresse bis $FFFFFC (24 Bit ohne Vorzeichen)
	and #3
	bne sb_falsch
	jsr pl_speicher             ; das Postfach braucht den Zusatzspeicher
	bcc sb_falsch
	#akku16
	lda #0
	sta @l SB_POST
	sta @l SB_POST+2
	lda @l SB_WERT
	sta @l SB_START
	#akku8
	lda @l SB_WERT+2
	sta @l SB_START+2
	lda #0
	sta @l SB_START+3
	lda #3                      ; an und laufen
	sta @l SB_STEUER
sb_gut
	lda #0
	rtl
sb_falsch
	lda #1
	rtl

sb_da                           ; Z = 1: SCHUB ist da. Sein Status ist immer
	lda @l SB_STATUS            ; %1000xxxx; ohne SCHUB ist $CD09 frei und
	and #$f0                    ; liest sich als $FF - Bit 7 allein hielt das
	cmp #$80                    ; fuer SCHUB, und SCHUB 0 wartete dann ewig
	rts                         ; auf Bit 1 und 2 (Kern 20261127, MiSTer)

sb_halt                         ; aus, warten bis Bus und CPU still sind
	lda #0
	sta @l SB_STEUER
-	lda @l SB_STATUS
	and #6
	bne -
	rts

; Wert i (24 Bit aus BASIC) mit Vorzeichen als 32 Bit ins Postfach, 0 wenn
; er fehlt
sb_arg	.macro i
	lda @l SB_ANZ
	cmp #\i+1
	bcc +
	#akku16
	lda @l SB_WERT+3*\i
	sta @l SB_POST+4+4*\i
	#akku8
	lda @l SB_WERT+3*\i+2
	sta @l SB_POST+6+4*\i
	asl a                       ; Carry: negativ
	lda #0
	adc #$ff
	eor #$ff                    ; $ff wenn negativ, sonst 0
	sta @l SB_POST+7+4*\i
	bra ++
+	#akku16
	lda #0
	sta @l SB_POST+4+4*\i
	sta @l SB_POST+6+4*\i
	#akku8
+
	.endm

schub_funktion
	.as
	.xl
	jsr sb_da
	bne sb_falsch
	lda @l SB_WERT              ; n = -1: Status
	and @l SB_WERT+1
	and @l SB_WERT+2
	cmp #$ff
	bne _ruf
	lda @l SB_STATUS
	sta @l SB_WERT
	lda #0
	sta @l SB_WERT+1
	sta @l SB_WERT+2
	sta @l SB_WERT+3
	rtl
_ruf
	lda @l SB_WERT+2
	bmi sb_falsch               ; andere negative n gibt es nicht
	jsr pl_speicher
	bcc sb_falsch
	lda @l SB_STATUS
	and #$0a
	cmp #2                      ; laeuft, ohne Adressfehler
	bne sb_falsch
	#sb_arg 0
	#sb_arg 1
	#sb_arg 2
	#sb_arg 3
	lda #1                      ; Auftrag
	sta @l SB_POST
_warte
	lda @l SB_POST
	cmp #2
	beq _fertig
	lda @l SB_STATUS
	and #$0a
	cmp #2
	bne _ab                     ; angehalten oder Adressfehler
	jsl SB_STOPP
	cmp #3
	bne _warte
	lda #0                      ; Esc: Auftrag zurueckziehen
	sta @l SB_POST
	lda #3
	rtl
_ab
	lda #0
	sta @l SB_POST
	bra sb_falsch
_fertig
	#akku16
	lda @l SB_POST+20           ; Ergebnis nach P_WERT_M+0..3
	sta @l SB_WERT
	lda @l SB_POST+22
	sta @l SB_WERT+2
	#akku8
	lda #0
	sta @l SB_POST
	rtl
