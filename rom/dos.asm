;============================================================================
;  MERIDIAN-DOS - Dateisystem fuer die Laufwerke von TRUHE (Etappe 10)
;
;  FAT16 ohne Partitionstabelle (wie eine grosse Diskette) oder in der
;  ersten Partition, nur das Hauptverzeichnis, Namen 8.3. Images, die der
;  Mac anlegt (tools/disk.py) oder einhaengt, liest MERIDIAN und umgekehrt.
;
;  Liegt im DOS-ROM: Bank $FF ab $4000. Aufruf nativ per JSL $FF4000 mit
;  Akku 8 Bit, Indexregistern 16 Bit; A = Befehl. Die Werte stehen im
;  Parameterblock D_... (Bank 0). Zurueck: A = Fehler (0 = gut).
;
;  Befehle:
;   0 LADEN      Datei D_TEXT nach D_ADR (oder, bei D_ADR = $FFFFFF, an
;                die Ladeadresse aus dem MER-Kopf); hoechstens D_LAENGE Byte.
;                Zurueck: D_LAENGE = gelesene Bytes, D_ADR = Ziel
;   1 SICHERN    D_LAENGE Bytes ab D_ADR als Datei D_TEXT; D_MER = 1:
;                mit MER-Kopf (Ladeadresse D_ADR)
;   2 ENTFERNEN  Datei D_TEXT
;  (Laufwerk 3 ist ein Ordner auf der SD-Karte ueber den Netzdienst,
;  rom/ordner.asm - dort gibt es kein LEEREN und keine Bloecke)
;   3 EINTRAG    naechste Datei ab D_INDEX: Name in D_TEXT, Groesse in
;                D_LAENGE; Fehler 2 = keine weitere
;   4 FREI       freie Bytes nach D_LAENGE (4 Byte)
;   5 LEEREN     Image neu anlegen (FAT16), Name D_TEXT
;   6 BLOCK      Block D_BLOCK von Laufwerk D_LW nach D_ADR lesen (512 Byte,
;                roh, ohne Dateisystem - auch Laufwerk 0, der Speicher-
;                stand eines Moduls)
;   7 BLOCK      512 Byte ab D_ADR als Block D_BLOCK schreiben (roh)
;  Fehler: 1 ungueltig, 2 nicht gefunden, 3 voll, 4 kein Image,
;          5 keine FAT16-Diskette, 6 schreibgeschuetzt, 7 Verzeichnis voll,
;          8 zu gross, 9 ungueltiger Name (8.3: A-Z 0-9 _ -)
;
;  Arbeitsspeicher: Parameterblock $16C0-$16FF, eigene direkte Seite $1700
;  (zwischen Bildschirm und Zeichensatz), FAT-Puffer im Zusatzspeicher
;  $FE:0000 (Systembank).
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

; TRUHE
TR_BEFEHL  = $C900
TR_LW      = $C901
TR_BLOCK   = $C902
TR_EIN     = $C906
TR_WECHSEL = $C907
TR_BLOECKE = $C908
TR_SEITE   = $C90C
TR_ANZAHL  = $C90D
PUF        = $CA00
ROM        = $FF0000            ; eigene Tabellen nur lang lesen (Datenbank ist 0!)              ; sichtbare Seite des Puffers (512 Byte)

; Der Puffer von TRUHE hat 16 Seiten. Einzelne Sektoren (Bootsektor, FAT,
; Verzeichnis) laufen immer ueber Seite 15; die Seiten 0-14 sammeln Daten,
; damit TRUHE bis zu 15 Sektoren mit einem Auftrag liest oder schreibt (der
; MiSTer schreibt jeden Auftrag sofort fest auf die SD-Karte).
EINZEL     = 15
STAPEL     = 15                 ; Sektoren je Sammelauftrag

FATPUF     = $FE0000            ; FAT-Sektor im Zusatzspeicher

; Parameterblock (Bank 0)
D_LW       = $16C0              ; Laufwerk 0-2
D_FEHLER   = $16C1
D_MER      = $16C2              ; SICHERN: mit MER-Kopf
D_ENDUNG   = $16C3              ; 3 Byte: Endung, wenn der Name keine hat
D_TLEN     = $16C6              ; Laenge des Namens
D_TEXT     = $16C7              ; bis 16 Zeichen (Name / Ausgabe)
D_NAME     = $16D8              ; 11 Byte 8.3 (intern)
D_ADR      = $16E4              ; 3 Byte
D_LAENGE   = $16E8              ; 4 Byte
D_INDEX    = $16EC              ; 2 Byte
D_BLOCK    = $16F4              ; 4 Byte: Blocknummer (BLOCK lesen/schreiben)

; direkte Seite des DOS ($1700)
lw      = $00                   ; Laufwerk des Zustands ($FF: keiner)
spc     = $01                   ; Sektoren je Cluster
spc_sh  = $02                   ; Zweierpotenz davon
nfat    = $03
fat     = $04                   ; 4 Byte: erster FAT-Sektor
spf     = $08                   ; Sektoren je FAT
root    = $0A                   ; 4 Byte: erster Sektor des Verzeichnisses
rootsek = $0E                   ; Sektoren des Verzeichnisses
daten   = $10                   ; 4 Byte: erster Datensektor (Cluster 2)
clust   = $14                   ; Anzahl Cluster
csek    = $16                   ; 4 Byte: FAT-Sektor im Puffer
cdirty  = $1A                   ; FAT-Puffer geaendert
lba     = $1C                   ; 4 Byte
ziel    = $20                   ; 3 Byte: langer Zeiger in den Speicher
rest    = $24                   ; 4 Byte
start   = $28                   ; Startcluster
groesse = $2A                   ; 4 Byte
e_lba   = $2E                   ; 4 Byte: Sektor des Eintrags
e_ofs   = $32                   ; Versatz des Eintrags im Sektor
f_lba   = $34                   ; 4 Byte: freier Eintrag ($FFFF....: keiner)
f_ofs   = $38
cl      = $3A
vorher  = $3C
s_cl    = $3E                   ; Sektor im Cluster
skip    = $40                   ; Bytes, die im Sektor zu ueberspringen sind
n       = $42
tmp     = $44                   ; 4 Byte
tmp2    = $48                   ; 4 Byte
maske   = $4C
frei_ab = $4E
idx     = $50
part    = $52                   ; 4 Byte: Beginn der Partition
cneu    = $56                   ; 4 Byte (LEEREN)
kopf    = $5A                   ; MER-Kopf noch zu schreiben
b_lba   = $5C                   ; 4 Byte: erster Sektor im Schreibstapel
b_n     = $60                   ; Sektoren im Schreibstapel (16 Bit)
v_lba   = $62                   ; 4 Byte: erster Sektor im Lesevorrat
v_n     = $66                   ; Sektoren im Lesevorrat (16 Bit, 0: keiner)
n_st    = $68                   ; Nullsektoren in dieser Runde (LEEREN)

ldx8	.macro adr                 ; X = Byte (16 Bit, obere Haelfte 0); Akku danach 8 Bit
	rep #$20
	.al
	lda \adr
	and #$00ff
	tax
	sep #$20
	.as
	.endm

	* = $4000

	jmp dos_befehl              ; $FF:4000
	jmp musik_befehl            ; $FF:4003 PLAY (Etappe 11, rom/musik.asm)
	jmp musik_takt              ; $FF:4006 einmal je Bild
	jmp netz_befehl             ; $FF:4009 NET (Etappe 12, rom/netz.asm)
	jmp mon_befehl              ; $FF:400C Monitor: Zeile ausfuehren (Etappe 13,
	jmp mon_halt                ; $FF:400F   rom/monitor.asm); BRK/Einzelschritt
	jmp mon_anfang              ; $FF:4012   Abzug der Register beim Einschalten
	jmp mon_dis                 ; $FF:4015   eine Zeile disassemblieren
	jmp mon_asm                 ; $FF:4018   eine Zeile uebersetzen

dos_befehl
	.as
	.xl
	phd
	phb
	pha
	#akku16
	lda #$1700
	tcd
	#akku8
	lda #0
	pha
	plb
	#akku16
	stz b_n                     ; Stapel und Vorrat leer, Seite 15
	stz v_n
	jsr seite15
	pla                         ; Befehl
	#akku16
	and #$00ff
	cmp #8
	bcc +
	#akku8                      ; unbekannter Befehl
	lda #1
	bra _ende
+	asl a
	tax
	#akku8
	lda D_LW                    ; Laufwerk 3: der Ordner (ordner.asm)
	cmp #3
	beq +
	jsr (befehle,x)
	bra _ende
+	jsr (o_befehle,x)
_ende
	.as
	sta D_FEHLER
	plb
	pld
	lda @l D_FEHLER
	rtl

befehle
	.word laden, sichern, entfernen, eintrag, frei, leeren
	.word block_lesen, block_schreiben

gut
	#akku8
	lda #0
	rts
f_ungueltig
	#akku8
	lda #1
	rts
f_fehlt
	#akku8
	lda #2
	rts
f_voll
	#akku8
	lda #3
	rts
f_kein
	#akku8
	lda #4
	rts
f_fat
	#akku8
	lda #5
	rts
f_schutz
	#akku8
	lda #6
	rts
f_vzvoll
	#akku8
	lda #7
	rts
f_gross
	#akku8
	lda #8
	rts

;----------------------------------------------------------------------------
; Sektoren (Laufwerk lw, Sektor lba, ueber den Puffer von TRUHE)

sektor_lesen                    ; Carry gesetzt: Fehler
	#akku8
	lda #1
	bra sektor_auftrag
sektor_schreiben
	#akku8
	lda #2
sektor_auftrag
	pha
	lda #EINZEL                 ; einzelne Sektoren: Seite 15
	sta TR_SEITE
	lda #1
	sta TR_ANZAHL
	lda lw
	sta TR_LW
	#akku16
	lda lba
	sta TR_BLOCK
	lda lba+2
	sta TR_BLOCK+2
	#akku8
	pla
	sta TR_BEFEHL
-	lda TR_BEFEHL
	lsr a
	bcs -
	lsr a                       ; Carry = Fehler
	rts

seite15                         ; Fenster auf Seite 15, ein Sektor je Auftrag
	#akku8
	lda #EINZEL
	sta TR_SEITE
	lda #1
	sta TR_ANZAHL
	rts

; Auftrag ueber TRUHE_n Sektoren ab Seite 0: A = 1 lesen / 2 schreiben,
; Sektor ab TR_BLOCK, Anzahl in TR_ANZAHL. Carry gesetzt: Fehler
sammel_auftrag
	#akku8
	pha
	lda lw
	sta TR_LW
	stz TR_SEITE
	pla
	sta TR_BEFEHL
-	lda TR_BEFEHL
	lsr a
	bcs -
	lsr a
	rts

; Datensektor lba lesen, mit Vorrat: holt 15 Sektoren mit einem Auftrag in
; die Seiten 0-14 und bedient die folgenden daraus. Danach zeigt das Fenster
; auf den Sektor (wieder auf Seite 15 schaltet seite15). Carry: Fehler
daten_lesen
	#akku16
	lda v_n
	beq _holen
	sec                         ; lba - v_lba < v_n?
	lda lba
	sbc v_lba
	tax
	lda lba+2
	sbc v_lba+2
	bne _holen
	txa
	cmp v_n
	bcs _holen
	#akku8
	sta TR_SEITE
	clc
	rts
_holen
	#akku16
	lda lba
	sta v_lba
	sta TR_BLOCK
	lda lba+2
	sta v_lba+2
	sta TR_BLOCK+2
	stz v_n
	#akku8
	lda #STAPEL
	sta TR_ANZAHL
	lda #1
	jsr sammel_auftrag
	bcs +
	lda #STAPEL
	sta v_n
+	lda #1                      ; (Seite 0 bleibt im Fenster)
	sta TR_ANZAHL
	rts

; Schreibstapel: Datensektoren sammeln, bis 15 beisammen sind oder einer
; nicht mehr anschliesst; dann alle mit einem Auftrag schreiben.

stapel_platz                    ; Platz fuer Sektor lba schaffen, Fenster dorthin
	#akku16                     ; Carry: Fehler
	lda b_n
	beq _seite
	cmp #STAPEL
	beq _schreiben
	clc                         ; schliesst lba an (b_lba + b_n)?
	adc b_lba
	tax
	lda b_lba+2
	adc #0
	cmp lba+2
	bne _schreiben
	txa
	cmp lba
	beq _seite
_schreiben
	jsr stapel_schreiben
	bcs _ende
_seite
	#akku8
	lda b_n
	sta TR_SEITE
	clc
_ende
	rts

stapel_dazu                     ; der Sektor im Fenster gehoert zum Stapel
	#akku16
	lda b_n
	bne +
	lda lba
	sta b_lba
	lda lba+2
	sta b_lba+2
+	inc b_n
	jmp seite15

stapel_schreiben                ; Stapel schreiben; Carry: Fehler
	#akku16
	lda b_n
	beq _leer
	lda b_lba
	sta TR_BLOCK
	lda b_lba+2
	sta TR_BLOCK+2
	#akku8
	lda b_n
	sta TR_ANZAHL
	lda #2
	jsr sammel_auftrag
	php
	#akku16
	stz b_n
	jsr seite15
	plp
	rts
_leer
	clc
	rts

; idx Nullsektoren ab lba schreiben, bis zu 15 je Auftrag; danach steht lba
; hinter dem letzten. Carry: Fehler
nullen_schreiben
	#akku8
	lda #0
-	sta TR_SEITE
	pha
	jsr puffer_leeren
	pla
	inc a
	cmp #STAPEL
	bne -
_runde
	#akku16
	lda idx
	beq _fertig
	cmp #STAPEL
	bcc +
	lda #STAPEL
+	sta n_st
	lda lba
	sta TR_BLOCK
	lda lba+2
	sta TR_BLOCK+2
	#akku8
	lda n_st
	sta TR_ANZAHL
	lda #2
	jsr sammel_auftrag
	bcs _fehler
	#akku16
	clc
	lda lba
	adc n_st
	sta lba
	bcc +
	inc lba+2
+	sec
	lda idx
	sbc n_st
	sta idx
	bra _runde
_fertig
	jsr seite15
	clc
	rts
_fehler
	jsr seite15
	sec
	rts

puffer_leeren                   ; Puffer von TRUHE mit Nullen
	#akku16
	ldx #0
-	stz PUF,x
	inx
	inx
	cpx #512
	bne -
	#akku8
	rts

lba_cluster                     ; lba = daten + (cl - 2) << spc_sh + s_cl
	#akku16
	lda cl
	sec
	sbc #2
	sta tmp
	stz tmp+2
	#ldx8 spc_sh
	beq +
	#akku16
-	asl tmp
	rol tmp+2
	dex
	bne -
+	#akku16
	clc
	lda daten
	adc tmp
	sta lba
	lda daten+2
	adc tmp+2
	sta lba+2
	lda s_cl
	and #$00ff
	clc
	adc lba
	sta lba
	bcc +
	inc lba+2
+	#akku8
	rts

;----------------------------------------------------------------------------
; Laufwerk aufschliessen: Bootsektor lesen, Aufbau der FAT merken

aufschliessen                   ; A = Fehler (Z gesetzt: gut)
	#akku8
	lda D_LW
	cmp #3
	bcc +
	jmp f_ungueltig
+	#ldx8 D_LW
	lda #1
	cpx #0
	beq +
-	asl a
	dex
	bne -
+	sta maske
	and TR_EIN
	bne +
	jmp f_kein
+	lda TR_WECHSEL
	and maske
	bne _neu
	lda lw
	cmp D_LW
	bne _neu
	jmp gut
_neu
	lda #$ff
	sta lw
	sta csek+3                  ; FAT-Puffer ungueltig
	stz cdirty
	lda maske
	sta TR_WECHSEL              ; Wechsel gesehen
	#akku16
	stz part
	stz part+2
	stz lba
	stz lba+2
	#akku8
	lda D_LW
	sta lw
	jsr sektor_lesen
	bcc +
	jmp _kein
+	jsr bootsektor_pruefen
	bcc _bpb
	lda PUF+$1c2                ; erste Partition: FAT16?
	cmp #$04
	beq _part
	cmp #$06
	beq _part
	cmp #$0e
	bne _fat
_part
	#akku16
	lda PUF+$1c6
	sta part
	sta lba
	lda PUF+$1c8
	sta part+2
	sta lba+2
	#akku8
	jsr sektor_lesen
	bcs _kein
	jsr bootsektor_pruefen
	bcs _fat
_bpb
	#akku8
	lda PUF+$0d                 ; Sektoren je Cluster
	beq _fat
	sta spc
	stz spc_sh
-	lsr a
	bcs +
	inc spc_sh
	bra -
+	bne _fat                    ; keine Zweierpotenz
	lda PUF+$10
	beq _fat
	sta nfat
	#akku16
	lda PUF+$16                 ; Sektoren je FAT (0: FAT32)
	beq _fat
	sta spf
	lda PUF+$11                 ; Eintraege im Verzeichnis
	lsr a
	lsr a
	lsr a
	lsr a
	sta rootsek
	clc                         ; fat = part + reservierte Sektoren
	lda part
	adc PUF+$0e
	sta fat
	lda part+2
	adc #0
	sta fat+2
	lda fat                     ; root = fat + nfat * spf
	sta root
	lda fat+2
	sta root+2
	#ldx8 nfat
	#akku16
-	clc
	lda root
	adc spf
	sta root
	bcc +
	inc root+2
+	dex
	bne -
	clc                         ; daten = root + rootsek
	lda root
	adc rootsek
	sta daten
	lda root+2
	adc #0
	sta daten+2
	lda PUF+$13                 ; Sektoren gesamt
	sta tmp
	stz tmp+2
	bne +
	lda PUF+$20
	sta tmp
	lda PUF+$22
	sta tmp+2
+	sec                         ; Cluster = (gesamt - (daten - part)) >> spc_sh
	lda daten
	sbc part
	sta tmp2
	lda daten+2
	sbc part+2
	sta tmp2+2
	sec
	lda tmp
	sbc tmp2
	sta tmp
	lda tmp+2
	sbc tmp2+2
	sta tmp+2
	bcc _fat
	#ldx8 spc_sh
	beq +
	#akku16
-	lsr tmp+2
	ror tmp
	dex
	bne -
+	#akku16
	lda tmp+2
	bne _fat                    ; zu viele Cluster
	lda tmp
	cmp #4085
	bcc _fat                    ; zu wenige (FAT12)
	cmp #65525
	bcs _fat
	sta clust
	lda #2
	sta frei_ab
	#akku8
	jmp gut
_kein
	lda #$ff
	sta lw
	jmp f_kein
_fat
	#akku8
	lda #$ff
	sta lw
	jmp f_fat

bootsektor_pruefen              ; Carry gesetzt: kein FAT-Bootsektor
	#akku8
	lda PUF+$1fe
	cmp #$55
	bne _nein
	lda PUF+$1ff
	cmp #$aa
	bne _nein
	lda PUF+$0b                 ; 512 Byte je Sektor
	bne _nein
	lda PUF+$0c
	cmp #$02
	bne _nein
	lda PUF
	cmp #$eb
	beq _ja
	cmp #$e9
	bne _nein
_ja
	clc
	rts
_nein
	sec
	rts

;----------------------------------------------------------------------------
; Name D_TEXT (D_TLEN Zeichen) -> D_NAME (8.3, Leerzeichen)

name83                          ; A = Fehler
	#akku8
	ldx #10
	lda #' '
-	sta D_NAME,x
	dex
	bpl -
	ldx #0                      ; Text
	ldy #0                      ; Name
	stz tmp                     ; 0: Name, 1: Endung
	stz tmp+1                   ; Endung angegeben
_zeichen
	txa
	cmp D_TLEN
	beq _fertig
	lda D_TEXT,x
	inx
	cmp #'.'
	bne +
	lda tmp
	bne _f
	inc tmp
	inc tmp+1
	ldy #8
	bra _zeichen
+	cmp #'a'
	bcc +
	cmp #'z'+1
	bcs +
	and #$df
+	cmp #'A'
	bcc _ziffer
	cmp #'Z'+1
	bcc _gut
_ziffer
	cmp #'0'
	bcc _sonder
	cmp #'9'+1
	bcc _gut
_sonder
	cmp #'_'
	beq _gut
	cmp #'-'
	beq _gut
	cmp #'~'                    ; Kuerzel langer Namen (Laufwerk 3)
	beq _gut
	bra _f
_gut
	pha
	lda tmp
	bne +
	cpy #8
	bra ++
+	cpy #11
+	pla
	bcs _f
	sta D_NAME,y
	iny
	bra _zeichen
_fertig
	lda D_NAME
	cmp #' '
	beq _f
	lda tmp+1
	bne +
	lda D_ENDUNG
	sta D_NAME+8
	lda D_ENDUNG+1
	sta D_NAME+9
	lda D_ENDUNG+2
	sta D_NAME+10
+	jmp gut
_f
	lda #9                      ; kein 8.3-Name
	rts

;----------------------------------------------------------------------------
; D_NAME im Verzeichnis suchen. Carry geloescht: gefunden (e_lba, e_ofs,
; start, groesse). f_lba/f_ofs: erster freier Eintrag ($FF in f_lba+3: keiner)

suchen
	#akku8
	lda #$ff
	sta f_lba+3
	#akku16
	stz idx
_sektor
	lda idx
	cmp rootsek
	bne +
	sec                         ; Ende des Verzeichnisses
	rts
+	clc
	adc root
	sta lba
	lda root+2
	adc #0
	sta lba+2
	jsr sektor_lesen
	bcc +
	rts
+	#akku16
	ldx #0
_eintrag
	#akku8
	lda PUF,x
	beq _frei_ende
	cmp #$e5
	beq _frei
	lda PUF+11,x
	cmp #$0f
	beq _weiter
	and #$18
	bne _weiter
	phx
	ldy #0
-	lda PUF,x
	cmp D_NAME,y
	bne _anders
	inx
	iny
	cpy #11
	bne -
	plx
	#akku16                     ; gefunden
	stx e_ofs
	lda lba
	sta e_lba
	lda lba+2
	sta e_lba+2
	lda PUF+$1a,x
	sta start
	lda PUF+$1c,x
	sta groesse
	lda PUF+$1e,x
	sta groesse+2
	#akku8
	clc
	rts
_anders
	plx
	bra _weiter
_frei_ende
	jsr frei_merken
	sec
	rts
_frei
	jsr frei_merken
_weiter
	#akku16
	txa
	clc
	adc #32
	tax
	cpx #512
	bne _eintrag
	inc idx
	bra _sektor

frei_merken
	#akku8
	lda f_lba+3
	cmp #$ff
	bne +
	#akku16
	lda lba
	sta f_lba
	lda lba+2
	sta f_lba+2
	stx f_ofs
	#akku8
+	rts

;----------------------------------------------------------------------------
; FAT mit einem Sektor Puffer im Zusatzspeicher

fat_holen                       ; X = Cluster -> X = Versatz im FAT-Puffer
	#akku16
	phx
	txa
	xba
	and #$00ff                  ; Cluster >> 8 = Sektor in der FAT
	clc
	adc fat
	sta tmp2
	lda fat+2
	adc #0
	sta tmp2+2
	cmp csek+2
	bne _laden
	lda tmp2
	cmp csek
	beq _da
_laden
	jsr fat_leeren
	#akku16
	lda tmp2
	sta lba
	sta csek
	lda tmp2+2
	sta lba+2
	sta csek+2
	jsr sektor_lesen
	#akku16
	ldx #0
-	lda PUF,x
	sta FATPUF,x
	inx
	inx
	cpx #512
	bne -
_da
	pla
	and #$00ff
	asl a
	tax
	rts

fat_lesen                       ; X = Cluster -> A (16 Bit) = Eintrag
	jsr fat_holen
	#akku16
	lda FATPUF,x
	rts

fat_schreiben                   ; X = Cluster, A (16 Bit) = Eintrag
	#akku16
	pha
	jsr fat_holen
	#akku16
	pla
	sta FATPUF,x
	#akku8
	lda #1
	sta cdirty
	rts

fat_leeren                      ; geaenderten FAT-Puffer in alle FATs schreiben
	#akku8
	lda cdirty
	beq _ende
	jsr seite15
	#akku16
	ldx #0
-	lda FATPUF,x
	sta PUF,x
	inx
	inx
	cpx #512
	bne -
	lda csek
	sta lba
	lda csek+2
	sta lba+2
	#akku8
	lda nfat
	sta tmp
-	jsr sektor_schreiben
	#akku16
	clc
	lda lba
	adc spf
	sta lba
	bcc +
	inc lba+2
+	#akku8
	dec tmp
	bne -
	stz cdirty
_ende
	rts

frei_zaehlen                    ; tmp = freie Cluster (16 Bit)
	#akku16
	stz cneu
	lda #2
	sta cl
-	ldx cl
	jsr fat_lesen
	#akku16
	cmp #0
	bne +
	inc cneu
+	inc cl
	lda clust
	inc a
	inc a
	cmp cl
	bne -
	lda cneu
	sta tmp
	#akku8
	rts

freien_finden                   ; A (16 Bit) = freier Cluster ab frei_ab
	#akku16
-	ldx frei_ab
	jsr fat_lesen
	#akku16
	ldx frei_ab
	inc frei_ab
	cmp #0
	bne -
	txa
	rts

;----------------------------------------------------------------------------
; Zeitstempel fuer Verzeichniseintraege: tmp = Uhrzeit, tmp+2 = Datum (FAT).
; Die Uhr von PFORTE stellt der MiSTer beim Start; ist sie nicht gestellt,
; gilt der 1. Januar 2026, 0:00 Uhr.

PF_UHR     = $C130              ; BCD: Sek, Min, Std, Tag, Mon, Jahr
PF_UHRST   = $C137

zeitstempel
	#akku8
	lda PF_UHRST
	lsr a
	bcs +
	#akku16
	stz tmp
	lda #$5c21
	sta tmp+2
	#akku8
	rts
+	sta PF_UHRST                ; Stand festhalten
	lda PF_UHR+2                ; Stunde << 11
	jsr bcd_bin
	#akku16
	and #$001f
	xba
	asl a
	asl a
	asl a
	sta tmp
	#akku8
	lda PF_UHR+1                ; Minute << 5
	jsr bcd_bin
	#akku16
	and #$003f
	asl a
	asl a
	asl a
	asl a
	asl a
	ora tmp
	sta tmp
	#akku8
	lda PF_UHR                  ; Sekunde / 2
	jsr bcd_bin
	lsr a
	#akku16
	and #$001f
	ora tmp
	sta tmp
	#akku8
	lda PF_UHR+5                ; Jahr seit 1980 << 9 (zweistellig ab 2000)
	jsr bcd_bin
	clc
	adc #20
	#akku16
	and #$007f
	xba
	asl a
	sta tmp+2
	#akku8
	lda PF_UHR+4                ; Monat << 5
	jsr bcd_bin
	#akku16
	and #$000f
	asl a
	asl a
	asl a
	asl a
	asl a
	ora tmp+2
	sta tmp+2
	#akku8
	lda PF_UHR+3                ; Tag
	jsr bcd_bin
	#akku16
	and #$001f
	ora tmp+2
	sta tmp+2
	#akku8
	rts

bcd_bin                         ; A (8 Bit, BCD) -> binaer
	.as
	pha
	lsr a
	lsr a
	lsr a
	lsr a
	sta maske
	asl a
	asl a
	clc
	adc maske
	asl a
	sta maske
	pla
	and #$0f
	clc
	adc maske
	rts

;----------------------------------------------------------------------------
; 6/7 BLOCK lesen und schreiben: 512 Byte roh zwischen Laufwerk D_LW und dem
; Speicher ab D_ADR (z. B. der Speicherstand eines Moduls auf Laufwerk 0)

block_lesen
	#akku8
	lda #1
	bra block_auftrag
block_schreiben
	#akku8
	lda #2
block_auftrag
	sta tmp
	lda D_LW
	cmp #3
	bcc +
	jmp f_ungueltig
+	sta TR_LW
	#akku16
	lda D_BLOCK
	sta TR_BLOCK
	lda D_BLOCK+2
	sta TR_BLOCK+2
	stz skip
	lda #512
	sta n
	lda D_ADR
	sta ziel
	#akku8
	lda D_ADR+2
	sta ziel+2
	lda tmp
	cmp #2
	bne +
	jsr in_puffer               ; schreiben: erst in den Puffer
	#akku8
	lda D_LW                    ; Dateisystem dieses Laufwerks neu lesen
	cmp lw
	bne +
	lda #$ff
	sta lw
+	#akku8
	lda tmp
	sta TR_BEFEHL
-	lda TR_BEFEHL
	lsr a
	bcs -
	lsr a
	bcs _fehler
	lda tmp
	cmp #1
	bne +
	jsr aus_puffer              ; lesen: aus dem Puffer
+	jmp gut
_fehler                         ; kein Image oder schreibgeschuetzt
	#ldx8 D_LW
	lda TR_EIN
-	cpx #0
	beq +
	lsr a
	dex
	bra -
+	lsr a
	bcs +
	jmp f_kein
+	jmp f_schutz

;----------------------------------------------------------------------------
; Kopieren zwischen dem Puffer von TRUHE und dem Speicher ([ziel])

aus_puffer                      ; n Bytes ab PUF+skip nach [ziel], ziel += n
	#akku8
	ldx skip
	ldy #0
-	cpy n
	beq +
	lda PUF,x
	sta [ziel],y
	inx
	iny
	bra -
+	jmp ziel_weiter

in_puffer                       ; n Bytes ab [ziel] nach PUF+skip, ziel += n
	#akku8
	ldx skip
	ldy #0
-	cpy n
	beq +
	lda [ziel],y
	sta PUF,x
	inx
	iny
	bra -
+
ziel_weiter
	#akku16
	clc
	lda ziel
	adc n
	sta ziel
	#akku8
	lda ziel+2
	adc #0
	sta ziel+2
	rts

n_berechnen                     ; n = min(512 - skip, rest)
	#akku16
	lda #512
	sec
	sbc skip
	sta n
	lda rest+2
	bne +
	lda rest
	cmp n
	bcs +
	sta n
+	sec                         ; rest -= n
	lda rest
	sbc n
	sta rest
	lda rest+2
	sbc #0
	sta rest+2
	#akku8
	rts

rest_null                       ; Z gesetzt: rest = 0
	#akku16
	lda rest
	ora rest+2
	php
	#akku8
	plp
	rts

;----------------------------------------------------------------------------
; 0 LADEN

laden
	jsr aufschliessen
	beq +
	rts
+	jsr name83
	beq +
	rts
+	jsr suchen
	bcc +
	jmp f_fehlt
+	#akku8
	lda groesse+3
	beq +
	jmp f_gross
+	#akku16                     ; erster Sektor: MER-Kopf?
	stz skip
	lda start
	sta cl
	#akku8
	stz s_cl
	lda groesse+2
	ora groesse+1
	beq _ohne                   ; kleiner als 256 Byte: Kopf nur, wenn >= 16
	bra _kopf
_ohne
	lda groesse
	cmp #16
	bcc _kein_kopf
_kopf
	jsr lba_cluster
	jsr sektor_lesen
	bcc +
	jmp f_kein
+	lda PUF
	cmp #'M'
	bne _kein_kopf
	lda PUF+1
	cmp #'E'
	bne _kein_kopf
	lda PUF+2
	cmp #'R'
	bne _kein_kopf
	#akku16                     ; MER: Kopf ueberspringen
	lda #16
	sta skip
	sec
	lda groesse
	sbc #16
	sta groesse
	lda groesse+2
	sbc #0
	sta groesse+2
	lda D_ADR                   ; ohne Ziel: Ladeadresse aus dem Kopf
	cmp #$ffff
	bne _adresse
	#akku8
	lda D_ADR+2
	cmp #$ff
	bne _adresse
	#akku16
	lda PUF+4
	sta D_ADR
	#akku8
	lda PUF+6
	sta D_ADR+2
	bra _adresse
_kein_kopf
	#akku16                     ; ohne Kopf braucht es ein Ziel
	lda D_ADR
	cmp #$ffff
	bne _adresse
	#akku8
	lda D_ADR+2
	cmp #$ff
	bne _adresse
	jmp f_ungueltig
_adresse
	#akku16
	lda groesse+2               ; passt es?
	cmp D_LAENGE+2
	bcc +
	bne _gross
	lda groesse
	cmp D_LAENGE
	beq +
	bcs _gross
+	lda groesse
	sta D_LAENGE
	sta rest
	lda groesse+2
	sta D_LAENGE+2
	sta rest+2
	lda D_ADR
	sta ziel
	#akku8
	lda D_ADR+2
	sta ziel+2
	#akku16
	lda start
	sta cl
_cluster
	jsr rest_null
	beq _fertig
	stz s_cl
_sektor
	jsr lba_cluster
	jsr daten_lesen
	bcc +
	jmp f_kein
+	jsr n_berechnen
	jsr aus_puffer
	jsr seite15
	#akku16
	stz skip
	jsr rest_null
	beq _fertig
	inc s_cl
	lda s_cl
	cmp spc
	bne _sektor
	ldx cl                      ; naechster Cluster
	jsr fat_lesen
	#akku16
	cmp #2
	bcc _kaputt
	cmp #$fff8
	bcs _kaputt
	sta cl
	bra _cluster
_fertig
	jmp gut
_kaputt
	jmp f_fat
_gross
	jmp f_gross

;----------------------------------------------------------------------------
; 1 SICHERN

sichern
	jsr aufschliessen
	beq +
	rts
+	lda maske                   ; schreibgeschuetzt?
	asl a
	asl a
	asl a
	asl a
	and TR_EIN
	beq +
	jmp f_schutz
+	jsr name83
	beq +
	rts
+	jsr suchen                  ; alte Datei weg
	bcs +
	jsr eintrag_loeschen
	bcc +
	jmp f_kein
+	jsr suchen                  ; freier Eintrag?
	#akku8
	lda f_lba+3
	cmp #$ff
	bne +
	jmp f_vzvoll
+	#akku16                     ; Gesamtlaenge mit Kopf
	lda D_LAENGE
	sta groesse
	lda D_LAENGE+2
	and #$00ff
	sta groesse+2
	#akku8
	lda D_MER
	sta kopf
	beq +
	#akku16
	clc
	lda groesse
	adc #16
	sta groesse
	bcc +
	inc groesse+2
+	jsr frei_zaehlen            ; tmp = freie (benutzt tmp2 intern!)
	jsr cluster_noetig          ; tmp2 = Cluster, die gebraucht werden
	#akku16
	lda tmp
	cmp tmp2
	bcs +
	jmp f_voll
+	lda D_ADR
	sta ziel
	#akku8
	lda D_ADR+2
	sta ziel+2
	#akku16
	lda D_LAENGE
	sta rest
	lda D_LAENGE+2
	and #$00ff
	sta rest+2
	stz vorher
	stz start
	lda tmp2
	sta idx                     ; Cluster zu schreiben
	beq _eintrag
_cluster
	jsr freien_finden
	#akku16
	sta cl
	tax
	lda #$ffff
	jsr fat_schreiben
	#akku16
	ldx vorher
	beq _erster
	lda cl
	jsr fat_schreiben
	bra +
_erster
	lda cl
	sta start
+	#akku16
	lda cl
	sta vorher
	#akku8
	stz s_cl
_sektor
	jsr lba_cluster
	jsr stapel_platz            ; Fenster auf die naechste Seite des Stapels
	bcc +
	jmp f_kein
+	jsr puffer_leeren
	#akku16
	stz skip
	#akku8
	lda kopf                    ; im ersten Sektor zuerst der MER-Kopf
	beq +
	stz kopf
	jsr mer_kopf
	#akku16
	lda #16
	sta skip
+	jsr n_berechnen
	jsr in_puffer
	jsr stapel_dazu
	jsr rest_null
	beq _naechster
	inc s_cl
	lda s_cl
	cmp spc
	bne _sektor
_naechster
	#akku16
	dec idx
	bne _cluster
_eintrag
	jsr stapel_schreiben        ; was noch im Stapel liegt
	bcc +
	jmp f_kein
+	jsr fat_leeren
	#akku16                     ; Verzeichniseintrag schreiben
	lda f_lba
	sta lba
	lda f_lba+2
	sta lba+2
	jsr sektor_lesen
	bcc +
	jmp f_kein
+	#akku16
	ldx f_ofs
	ldy #0
	#akku8
-	lda D_NAME,y
	sta PUF,x
	inx
	iny
	cpy #11
	bne -
	lda #$20                    ; Archiv
	sta PUF,x
	inx
	lda #0
	ldy #10
-	sta PUF,x
	inx
	dey
	bne -
	jsr zeitstempel             ; Uhrzeit und Datum (Etappe 11: aus PFORTE)
	#akku16
	lda tmp
	sta PUF,x
	lda tmp+2
	sta PUF+2,x
	lda start
	sta PUF+4,x
	lda groesse
	sta PUF+6,x
	lda groesse+2
	sta PUF+8,x
	jsr sektor_schreiben
	bcc +
	jmp f_kein
+	jmp gut

mer_kopf                        ; MER-Kopf (Ladeadresse D_ADR) an den Pufferanfang
	#akku8
	lda #'M'
	sta PUF
	lda #'E'
	sta PUF+1
	lda #'R'
	sta PUF+2
	lda #1
	sta PUF+3
	#akku16
	lda D_ADR
	sta PUF+4
	sta PUF+8
	lda D_LAENGE
	sta PUF+12
	#akku8
	lda D_ADR+2
	sta PUF+6
	sta PUF+10
	lda D_LAENGE+2
	sta PUF+14
	rts

cluster_noetig                  ; tmp2 = (groesse + Clustergroesse - 1) >> (9 + spc_sh)
	#akku16
	lda groesse
	sta tmp2
	lda groesse+2
	sta tmp2+2
	lda tmp2
	ora tmp2+2
	beq _ende
	lda tmp2                    ; - 1
	bne +
	dec tmp2+2
+	dec tmp2
	lda spc_sh
	and #$00ff
	clc
	adc #9
	tax
-	lsr tmp2+2
	ror tmp2
	dex
	bne -
	inc tmp2                    ; + 1
_ende
	#akku8
	rts

eintrag_loeschen                ; gefundene Datei (e_lba, e_ofs, start) entfernen
	#akku16
	lda e_lba
	sta lba
	lda e_lba+2
	sta lba+2
	jsr sektor_lesen
	bcs _ende
	#akku16
	ldx e_ofs
	#akku8
	lda #$e5
	sta PUF,x
	jsr sektor_schreiben
	bcs _ende
	#akku16                     ; Kette freigeben
	lda start
	sta cl
-	lda cl
	cmp #2
	bcc +
	cmp #$fff8
	bcs +
	tax
	jsr fat_lesen
	#akku16
	pha
	ldx cl
	lda #0
	jsr fat_schreiben
	#akku16
	pla
	sta cl
	bra -
+	jsr fat_leeren
	#akku16
	lda #2
	sta frei_ab
	#akku8
	clc
_ende
	rts

;----------------------------------------------------------------------------
; 2 ENTFERNEN

entfernen
	jsr aufschliessen
	beq +
	rts
+	lda maske
	asl a
	asl a
	asl a
	asl a
	and TR_EIN
	beq +
	jmp f_schutz
+	jsr name83
	beq +
	rts
+	jsr suchen
	bcc +
	jmp f_fehlt
+	jsr eintrag_loeschen
	bcc +
	jmp f_kein
+	jmp gut

;----------------------------------------------------------------------------
; 3 EINTRAG: naechste Datei ab D_INDEX

eintrag
	jsr aufschliessen
	beq _suche
	rts
_suche
	#akku16
	lda D_INDEX
	lsr a                       ; Sektor = Index / 16
	lsr a
	lsr a
	lsr a
	cmp rootsek
	bcc +
	jmp f_fehlt
+	clc
	adc root
	sta lba
	lda root+2
	adc #0
	sta lba+2
	jsr sektor_lesen
	bcc +
	jmp f_kein
+	#akku16
	lda D_INDEX
	inc D_INDEX
	and #$000f
	asl a
	asl a
	asl a
	asl a
	asl a
	tax
	#akku8
	lda PUF,x
	bne +
	jmp f_fehlt                 ; Ende des Verzeichnisses
+	cmp #$e5
	beq _suche
	lda PUF+11,x
	cmp #$0f
	beq _suche
	and #$18
	bne _suche
	ldy #0                      ; Name als Text: NAME.END
-	lda PUF,x
	cmp #' '
	beq +
	sta D_TEXT,y
	iny
+	inx
	txa
	and #$1f
	cmp #8
	bcc -
	lda PUF,x
	cmp #' '
	beq _ohne
	lda #'.'
	sta D_TEXT,y
	iny
-	lda PUF,x
	cmp #' '
	beq +
	sta D_TEXT,y
	iny
+	inx
	txa
	and #$1f
	cmp #11
	bcc -
_ohne
	tya
	sta D_TLEN
	#akku16
	txa
	and #$ffe0
	tax
	lda PUF+$1c,x
	sta D_LAENGE
	lda PUF+$1e,x
	sta D_LAENGE+2
	jmp gut

;----------------------------------------------------------------------------
; 4 FREI: freie Bytes

frei
	jsr aufschliessen
	beq +
	rts
+	jsr frei_zaehlen            ; tmp = freie Cluster
	#akku16
	stz tmp+2
	lda spc_sh
	and #$00ff
	clc
	adc #9
	tax
-	asl tmp
	rol tmp+2
	dex
	bne -
	lda tmp
	sta D_LAENGE
	lda tmp+2
	sta D_LAENGE+2
	jmp gut

;----------------------------------------------------------------------------
; 5 LEEREN: FAT16 neu anlegen (wie tools/disk.py), Name D_TEXT

leeren
	#akku8
	lda D_LW
	cmp #3
	bcc +
	jmp f_ungueltig
+	sta TR_LW
	#ldx8 D_LW
	lda #1
	cpx #0
	beq +
-	asl a
	dex
	bne -
+	sta maske
	and TR_EIN
	bne +
	jmp f_kein
+	lda maske
	asl a
	asl a
	asl a
	asl a
	and TR_EIN
	beq +
	jmp f_schutz
+	#akku16                     ; Sektoren des Images
	lda TR_BLOECKE
	sta part                    ; (hier: Sektoren gesamt)
	lda TR_BLOECKE+2
	sta part+2
	cmp #$0040                  ; hoechstens 2 GB
	bcc +
	jmp f_gross
+	#akku8
	stz spc_sh
_spc
	#akku16
	lda #1
	sta spf
_spf                            ; cneu = (gesamt - 33 - 2 * spf) >> spc_sh
	lda spf
	asl a
	clc
	adc #33
	sta tmp
	sec
	lda part
	sbc tmp
	sta cneu
	lda part+2
	sbc #0
	sta cneu+2
	bcs +
	jmp f_gross                 ; zu klein
+	#ldx8 spc_sh
	beq +
	#akku16
-	lsr cneu+2
	ror cneu
	dex
	bne -
+	#akku16                     ; noetig = (cneu + 2 + 255) >> 8
	lda cneu+2
	bne _mehr                   ; ueber 65535 Cluster
	clc
	lda cneu
	adc #257
	sta tmp
	lda #0
	adc #0
	sta tmp+2
	lda tmp+1                   ; >> 8 (tmp+3 ist 0)
	cmp spf
	beq _stabil
	bcc _stabil
	sta spf
	bra _spf
_stabil
	lda cneu
	cmp #65525
	bcc +
_mehr
	#akku8
	inc spc_sh
	lda spc_sh
	cmp #7
	bcc _spc
	jmp f_gross
+	.al                         ; (von bcc oben: Akku 16 Bit)
	cmp #4085
	bcs +
	jmp f_gross                 ; zu klein fuer FAT16
+	#akku8                      ; Zustand fuer das Schreiben
	lda D_LW
	sta lw
	#ldx8 spc_sh
	lda #1
	cpx #0
	beq +
-	asl a
	dex
	bne -
+	sta spc
	; Bootsektor
	jsr puffer_leeren
	lda #$eb
	sta PUF
	lda #$3c
	sta PUF+1
	lda #$90
	sta PUF+2
	ldx #0
-	lda ROM+t_oem,x            ; lang: die Datenbank ist 0
	sta PUF+3,x
	inx
	cpx #8
	bne -
	#akku16
	lda #512
	sta PUF+$0b
	#akku8
	lda spc
	sta PUF+$0d
	lda #1
	sta PUF+$0e                 ; 1 reservierter Sektor
	lda #2
	sta PUF+$10                 ; 2 FATs
	#akku16
	lda #512
	sta PUF+$11                 ; 512 Eintraege im Verzeichnis
	lda part+2
	bne +
	lda part
	sta PUF+$13
	bra ++
+	lda part
	sta PUF+$20
	lda part+2
	sta PUF+$22
+	#akku8
	lda #$f8
	sta PUF+$15
	#akku16
	lda spf
	sta PUF+$16
	lda #32
	sta PUF+$18
	lda #64
	sta PUF+$1a
	#akku8
	lda #$80
	sta PUF+$24
	lda #$29
	sta PUF+$26
	lda #$4d                    ; Seriennummer "MERI"
	sta PUF+$27
	lda #$45
	sta PUF+$28
	lda #$52
	sta PUF+$29
	lda #$49
	sta PUF+$2a
	ldx #$2b                    ; Name
	jsr name_in_puffer
	ldx #0
-	lda ROM+t_fat16,x
	sta PUF+$36,x
	inx
	cpx #8
	bne -
	lda #$55
	sta PUF+$1fe
	lda #$aa
	sta PUF+$1ff
	#akku16
	stz lba
	stz lba+2
	jsr sektor_schreiben
	bcc +
	jmp f_kein
+	; zwei FATs: jeweils erster Sektor F8 FF FF FF, Rest leer
	#akku16
	lda #1
	sta lba
	#akku8
	lda #2
	sta tmp2
_fat
	jsr puffer_leeren
	#akku16
	lda #$fff8
	sta PUF
	lda #$ffff
	sta PUF+2
	jsr sektor_schreiben
	bcc +
	jmp f_kein
+	#akku16                     ; der Rest der FAT: Nullen
	inc lba
	lda spf
	dec a
	sta idx
	jsr nullen_schreiben
	bcc +
	jmp f_kein
+	#akku8
	dec tmp2
	bne _fat
	; Verzeichnis: 32 Sektoren, im ersten der Name
	jsr puffer_leeren
	ldx #0
	jsr name_in_puffer
	lda #$08
	sta PUF+11
	jsr sektor_schreiben
	bcc +
	jmp f_kein
+	#akku16                     ; die uebrigen 31: Nullen
	inc lba
	lda #31
	sta idx
	jsr nullen_schreiben
	bcc +
	jmp f_kein
+	#akku8
	lda #$ff                    ; beim naechsten Zugriff neu aufschliessen
	sta lw
	jmp gut

name_in_puffer                  ; D_TEXT (11 Zeichen, gross) nach PUF+X
	#akku8
	ldy #0
-	tya
	cmp D_TLEN
	lda #' '
	bcs +
	lda D_TEXT,y
	cmp #'a'
	bcc +
	cmp #'z'+1
	bcs +
	and #$df
+	sta PUF,x
	inx
	iny
	cpy #11
	bne -
	rts

t_oem	.text "MERIDIAN"
t_fat16	.text "FAT16   "

; Werte von BASIC fuer PLAY (wie in befehle.asm)
P_ANZ_M    = $039F
P_WERT_M   = $03A0
P_TLEN_M   = $039C
P_TPTR_M   = $039D

	.include "musik.asm"
	.include "netz.asm"
	.include "ordner.asm"
	.include "monitor.asm"

	.cerror * > $8000, "DOS-ROM zu gross"
