;============================================================================
;  ORDNER - Laufwerk 3: ein Ordner auf der SD-Karte (Etappe 14)
;
;  Der Netzdienst (tools/draht.py) stellt games/MERIDIAN/files als Laufwerk 3
;  bereit. Das DOS fragt ihn ueber das DRAHT-Fenster (Bank $FD, Anfrage-
;  Routine aus netz.asm); die Daten laufen stueckweise (bis 60 KB) durch
;  das Fenster ab $FD:1000. Lange Dateinamen zeigt der Dienst als 8.3-
;  Kuerzel (SPACED~1.MOD).
;
;  Anfragen (Art, Text ab $FD:0100):
;   4 EINTRAG    Index (2)                     -> naechster Index (2),
;                                                 Groesse (4), Namenslaenge,
;                                                 Name ("NAME.END")
;   5 LESEN      Name (11, 8.3), Versatz (4),  -> Datenlaenge (4), geliefert
;                hoechstens (2)                   (2), MER (1), Adresse (3)
;   6 SCHREIBEN  Name, Versatz, Laenge         -> (Versatz 0: Datei neu)
;   7 ENTFERNEN  Name
;   8 FREI                                     -> freie Bytes (4)
;  Status = Fehlernummer des DOS; antwortet der Dienst nicht: Fehler 4.
;  Eine MER-Datei liefert der Dienst ohne ihren Kopf (wie das DOS sonst).
;============================================================================

O_DATEN  = FEN+$1000            ; Daten im Fenster
O_STUECK = $F000                ; so viel je Anfrage

o_befehle
	.word o_laden, o_sichern, o_entfernen, o_eintrag, o_frei
	.word f_ungueltig, f_ungueltig, f_ungueltig

; Anfrage der Art A an den Dienst. A = Fehler (Z gesetzt: gut)
o_fragen
	.as
	sta @l F_ART
	lda #0
	sta @l F_KANAL
	lda #17
	sta @l F_LEN
	#akku16
	lda #10*60
	sta n_max
	#akku8
	jsr anfrage
	lda @l F_STATUS+1
	bmi _kein
	lda @l F_STATUS
	rts
_kein
	lda #4                      ; kein Dienst (oder Esc)
	rts

; D_TEXT -> 8.3 ins Fenster. A = Fehler
o_name
	.as
	jsr name83
	beq +
	rts
+	ldx #0
-	lda D_NAME,x
	sta @l F_TEXT,x
	inx
	cpx #11
	bne -
	lda #0
	rts

; Versatz tmp und Laenge A (16 Bit) in die Anfrage
o_versatz
	.al
	sta @l F_TEXT+15
	lda tmp
	sta @l F_TEXT+11
	lda tmp+2
	sta @l F_TEXT+13
	#akku8
	rts

;----------------------------------------------------------------------------
; 3 EINTRAG: Datei Nummer D_INDEX

o_eintrag
	.as
	#akku16
	lda D_INDEX
	sta @l F_TEXT
	#akku8
	lda #4
	jsr o_fragen
	beq +
	rts
+	#akku16
	lda @l F_ANTWORT            ; naechster Index
	sta D_INDEX
	lda @l F_ANTWORT+2          ; Groesse
	sta D_LAENGE
	lda @l F_ANTWORT+4
	sta D_LAENGE+2
	#akku8
	lda @l F_ANTWORT+6
	sta D_TLEN
	ldx #0
-	txa
	cmp D_TLEN
	beq +
	lda @l F_ANTWORT+7,x
	sta D_TEXT,x
	inx
	bra -
+	jmp gut

;----------------------------------------------------------------------------
; 0 LADEN: nach D_ADR (oder $FFFFFF: an die Adresse aus dem MER-Kopf),
; hoechstens D_LAENGE Byte. Zurueck: D_LAENGE gelesen, D_ADR Ziel

o_laden
	.as
	jsr o_name
	beq +
	rts
+	#akku16
	stz tmp                     ; Versatz in den Daten
	stz tmp+2
	stz tmp2                    ; gelesen
	stz tmp2+2
	#akku8
_stueck
	#akku16                     ; hoechstens O_STUECK und der Rest von D_LAENGE
	lda D_LAENGE
	sec
	sbc tmp2
	sta rest
	lda D_LAENGE+2
	sbc tmp2+2
	bne _voll
	lda rest
	cmp #O_STUECK
	bcc +
_voll
	lda #O_STUECK
+	sta cl                      ; angefordert
	jsr o_versatz
	.as
	lda #5
	jsr o_fragen
	beq +
	rts
+	#akku16
	lda tmp                     ; erstes Stueck: Ziel festlegen
	ora tmp+2
	bne _kopieren
	lda D_ADR
	cmp #$ffff
	bne _ziel
	#akku8
	lda D_ADR+2
	cmp #$ff
	bne _ziel8
	lda @l F_ANTWORT+6          ; keine Adresse: nur mit MER-Kopf
	bne +
	jmp f_ungueltig
+	lda @l F_ANTWORT+9
	sta D_ADR+2
	#akku16
	lda @l F_ANTWORT+7
	sta D_ADR
_ziel
	#akku8
_ziel8
	#akku16
	lda D_ADR
	sta ziel
	#akku8
	lda D_ADR+2
	sta ziel+2
_kopieren
	#akku16
	lda @l F_ANTWORT+4          ; geliefert
	sta n
	beq _fertig
	#akku8
	ldx #0
	ldy #0
-	lda @l O_DATEN,x
	sta [ziel],y
	inx
	iny
	cpy n
	bne -
	#akku16
	lda ziel                    ; ziel, Versatz und gelesen += n
	clc
	adc n
	sta ziel
	#akku8
	lda ziel+2
	adc #0
	sta ziel+2
	#akku16
	lda tmp
	clc
	adc n
	sta tmp
	lda tmp+2
	adc #0
	sta tmp+2
	lda tmp2
	clc
	adc n
	sta tmp2
	lda tmp2+2
	adc #0
	sta tmp2+2
	lda n                       ; weniger als angefordert: Dateiende
	cmp cl
	bcc _fertig
	lda tmp2+2                  ; D_LAENGE erreicht?
	cmp D_LAENGE+2
	bcc _weiter
	bne _fertig
	lda tmp2
	cmp D_LAENGE
	bcs _fertig
_weiter
	#akku8
	jmp _stueck
_fertig
	.al
	lda tmp2
	sta D_LAENGE
	lda tmp2+2
	sta D_LAENGE+2
	#akku8
	jmp gut

;----------------------------------------------------------------------------
; 1 SICHERN: D_LAENGE Byte ab D_ADR; D_MER = 1: mit MER-Kopf

o_sichern
	.as
	jsr o_name
	beq +
	rts
+	#akku16
	lda D_ADR
	sta ziel
	lda D_LAENGE
	sta rest
	lda D_LAENGE+2
	sta rest+2
	stz tmp                     ; Versatz in der Datei
	stz tmp+2
	#akku8
	lda D_ADR+2
	sta ziel+2
	lda D_MER
	sta kopf
_stueck
	ldx #0                      ; X = Bytes im Fenster
	lda kopf
	beq _daten
	stz kopf
	lda #'M'                    ; MER-Kopf (wie mer_kopf)
	sta @l O_DATEN
	lda #'E'
	sta @l O_DATEN+1
	lda #'R'
	sta @l O_DATEN+2
	lda #1
	sta @l O_DATEN+3
	lda #0
	sta @l O_DATEN+7
	sta @l O_DATEN+11
	sta @l O_DATEN+15
	#akku16
	lda D_ADR
	sta @l O_DATEN+4
	sta @l O_DATEN+8
	lda D_LAENGE
	sta @l O_DATEN+12
	#akku8
	lda D_ADR+2
	sta @l O_DATEN+6
	sta @l O_DATEN+10
	lda D_LAENGE+2
	sta @l O_DATEN+14
	ldx #16
_daten
	#akku16                     ; m = min(Rest, Platz im Fenster)
	stx n
	lda #O_STUECK
	sec
	sbc n
	sta cl
	lda rest+2
	bne +
	lda rest
	cmp cl
	bcs +
	sta cl
+	#akku8
	ldy #0
-	cpy cl
	beq +
	lda [ziel],y
	sta @l O_DATEN,x
	inx
	iny
	bra -
+	#akku16
	lda ziel                    ; Quelle und Rest weiter
	clc
	adc cl
	sta ziel
	#akku8
	lda ziel+2
	adc #0
	sta ziel+2
	#akku16
	lda rest
	sec
	sbc cl
	sta rest
	lda rest+2
	sbc #0
	sta rest+2
	stx n                       ; Bytes im Fenster
	txa
	jsr o_versatz
	.as
	lda #6
	jsr o_fragen
	beq +
	rts
+	#akku16
	lda tmp
	clc
	adc n
	sta tmp
	lda tmp+2
	adc #0
	sta tmp+2
	lda rest
	ora rest+2
	#akku8
	bne _stueck
	jmp gut

;----------------------------------------------------------------------------
; 2 ENTFERNEN, 4 FREI

o_entfernen
	.as
	jsr o_name
	beq +
	rts
+	lda #7
	jmp o_fragen

o_frei
	.as
	lda #8
	jsr o_fragen
	beq +
	rts
+	#akku16
	lda @l F_ANTWORT
	sta D_LAENGE
	lda @l F_ANTWORT+2
	sta D_LAENGE+2
	#akku8
	jmp gut
