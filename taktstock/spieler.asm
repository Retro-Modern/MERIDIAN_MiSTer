;============================================================================
;  TAKTSTOCK - Abspieler fuer .TAK-Songs
;
;  Einbinden mit SP_RAM = Anfang von $366 Byte RAM in Bank 0: die erste
;  Seite ist die direkte Seite des Abspielers, dahinter liegen die Felder
;  der acht Kanaele. Aufrufe per JSR aus der Bank des Abspielers, Akku 8 /
;  Index 16 Bit, Datenbank 0; die direkte Seite stellt der Abspieler selbst
;  ein. Eigene Tabellen liest er lang - er laeuft so auch aus dem
;  System-ROM (BASIC SONG, Bank $FF).
;
;    sp_song (3 Byte)  vorher setzen: Adresse des Songs (gern Zusatzspeicher)
;    sp_chip (3 Byte)  vorher setzen: wohin die Sampledaten kopiert wurden
;    sp_init           Kanaele leeren, Timer A nach dem BPM-Wert stellen;
;                      danach laeuft der Takt, aber kein Song (sp_an = 0)
;    sp_spielen        A = 1 Song, 2 Pattern in Schleife, ab sp_pos/sp_zeile
;    sp_halt           anhalten, alle Noten loslassen (Timer laeuft weiter)
;    sp_start          sp_init und Song von vorn (fuer TAKTTEST)
;    sp_takt           ein Tick (aus dem Timer-A-Interrupt aufrufen)
;    sp_stopp          alle Kanaele still, Timer aus (beim Beenden)
;    sp_vorhoeren      Note A mit Instrument sp_i auf Kanal X (Spur * 2)
;    sp_loslassen      Note auf Kanal X loslassen
;    sp_stumm          Bit n = Spur n stumm
;
;  Wie im ProTracker: Tempo = Ticks je Zeile, BPM bestimmt die Ticklaenge
;  (2,5 s / BPM). Timer A zaehlt Mikrosekunden - PAL und NTSC spielen gleich
;  schnell. Tonhoehen sind Perioden * 16 (C-2 = 428 * 16); FREQ bzw. SCHRITT
;  = Zaehler des Instruments / Periode. Spuren 0-3 spielen die vier
;  Synthesestimmen, Spuren 4-7 die vier Samplekanaele. Ein Zwitter oder ein
;  reines Sample auf Synthspur n spielt auf dem eigenen Samplekanal 4+n
;  (ORGEL-Seite 2 ab $CC80, Etappe 17) und wird jeden Tick nachgefuehrt.
;
;  Huellkurven (Version 3, wie FastTracker 2): je Instrument bis 12 Punkte
;  (Tick, Wert 0-64), Sustain, Schleife und Ausklingen. Sie laufen nur beim
;  Spielen; Loslassen gibt den Sustain frei und laesst ausklingen, statt
;  das Sample anzuhalten. Lautstaerke-Spalte und Huellkurven liegen in der
;  Arbeitskopie an festen Stellen, in einer Datei hinter Samples und Bildteil.
;
;  Pult (Version 4, Synth-Pult im Instrument-Editor): je Instrument 8 Byte
;  gleich hinter den Huellkurven - ENV MOD, DECAY, ACCENT, GLIDE, DRIVE,
;  ECHO, Schalter (PU_*). Wie bei der 303: Der Anschlag oeffnet das Filter um
;  ENV MOD (laute Noten ab 48 zusaetzlich um ACCENT), dann klingt es je Tick
;  ab; GLIDE gleitet zur naechsten Note, solange die vorige noch klingt, ohne
;  neuen Anschlag; DRIVE und ECHO setzen beim Anschlag den Filterausgang wie
;  Txx und Sxx. Gerechnet wird im Modul von TAKTSTOCK (pult.asm), erreicht
;  ueber sp_pvek - nur, wenn der Song ein Pult hat und sp_pvek gesetzt ist.
;  Aeltere Songs laufen wie bisher.
;
;  Ablauftabelle (wie in den SID-Playern): je Synth-Instrument 6 Schritte
;  zu 2 Byte ab Song + $CC0 + Instrument * 12. Je Tick ein Schritt: Welle
;  (STEUER ohne Gate, 0 = unveraendert, $FF = Sprung zu Schritt "Ton") und
;  Tonversatz in Halbtoenen (mit Vorzeichen). Nach dem letzten Schritt
;  bleibt der letzte Stand. Ist Schritt 0 leer, gibt es keine Tabelle.
;============================================================================

ORG     = $C500                 ; Synthesestimme n ab ORG + n*16
KAN     = $C580                 ; Samplekanal k ab KAN + k*16
KAN2    = $0700                 ; Kanal 4+n: KAN + KAN2 + n*16 ($CC80, Etappe 17)
FX      = $C5C0                 ; Effekte des Samplekanals k ab FX + k*16 (Etappe 16)
ECHO    = $C550                 ; Echo: Zeit (2), Rueck, Anteil, Bank
ECHO_BANK = $EC                 ; 64 KB Echo-Puffer im Zusatzspeicher
FILTER  = $C540
SP_TA   = $C114                 ; PFORTE Timer A
SP_TAST = $C116

; Song (.TAK)
TK_LAENGE = 24
TK_TEMPO  = 28
TK_SPEGEL = 31                  ; Samplepegel n/4 fuer die ORGEL (0: 12 = dreifach)
TK_PAN    = 32
TK_FOLGE  = $40
TK_INS    = $C0
TK_PAT    = $1000
TK_LAUT   = TK_PAT + 128 * $900 + 16 * 40   ; Arbeitskopie: Lautstaerke-Spalte (Version 2)
ZEILE_B   = 36

; Instrument
IN_ART      = 0
IN_LAUT     = 1
IN_PAN      = 2
IN_ZAEHLER  = 3
IN_WELLE    = 6
IN_AD       = 7
IN_SR       = 8
IN_PULS     = 9
IN_PWM      = 11
IN_FILTER   = 12
IN_ANFANG   = 14
IN_LAENGE   = 18
IN_SCHLEIFE = 20
IN_SLAENGE  = 22                ; Schleifenlaenge; $FFFF = bis zum Ende des Samples
IN_SHI      = 17                ; Schleife ab Bits 16-23 (lange Samples)
IN_LHI      = 31                ; Laenge Bits 16-23
IN_ZW       = 24                ; Zaehler des Samples bei Zwittern
IN_ECKE     = 27                ; Filter-Eckfrequenz / 8 beim Anschlag (0 = keine)
TK_ABLAUF   = $CC0              ; Ablauftabellen: 6 Schritte (Welle, Ton) je Instrument
; Pult je Instrument (Version 4, 8 Byte)
PU_ENV      = 0                 ; Filter-Huellkurve: Hub * 8
PU_DECAY    = 1                 ; Abklingen: je Tick um (255 - DECAY)^2 / 65536
PU_AKZENT   = 2                 ; Noten ab Lautstaerke 48: Hub + ACCENT * 4
PU_GLIDE    = 3                 ; gleiten in 1 + GLIDE/32 Ticks (0 = aus)
PU_DRIVE    = 4                 ; Filterausgang verzerren 0-15 (wie Txx)
PU_ECHO     = 5                 ; Filterausgang ins Echo 0-15 (wie Sxx)
PU_SCHALTER = 6                 ; Bit 0: DRIVE und ECHO gelten beim Anschlag
ABL_SCHRITTE = 6

	.include "huelle.inc"

PER_MIN = 113
PER_MAX = 27392

; Direkte Seite des Abspielers
sp_song   = SP_RAM+$00          ; 3: Song
sp_zeiger = SP_RAM+$03          ; 3: aktuelle Zeile
sp_hilf   = SP_RAM+$06          ; 3: Instrument-Eintrag
sp_chip   = SP_RAM+$09          ; 3: Sampledaten im Chip-RAM
sp_pos    = SP_RAM+$0C          ; Position in der Folge
sp_zeile  = SP_RAM+$0D          ; Zeile 0-63
sp_tick   = SP_RAM+$0E
sp_tempo  = SP_RAM+$0F          ; Ticks je Zeile
sp_bpm    = SP_RAM+$10
sp_laenge = SP_RAM+$11          ; Laenge der Folge
sp_neu    = SP_RAM+$12          ; Neustart-Position
sp_sprung = SP_RAM+$13          ; Bxx: Zielposition, $FF = keiner
sp_bruch  = SP_RAM+$14          ; Dxx: Zielzeile, $FF = keiner
sp_verz   = SP_RAM+$15          ; EEx: Zeile noch so oft wiederholen
sp_wdh    = SP_RAM+$16          ; 1 = die Zeile laeuft noch einmal
sp_an     = SP_RAM+$17          ; 1 = spielt
sp_halb   = SP_RAM+$18          ; BPM < 39: Timer mit halber Zeit
sp_halbz  = SP_RAM+$19
sp_ecke   = SP_RAM+$1A          ; 2: Filter-Eckfrequenz 0-2047
sp_reso   = SP_RAM+$1C          ; Resonanz (obere 4 Bit)
sp_route  = SP_RAM+$1D          ; Stimmen durchs Filter (untere 4 Bit)
sp_fart   = SP_RAM+$1E          ; Filterart (Bits 4-6)
sp_zaehler = SP_RAM+$1F         ; zaehlt jede neue Zeile (fuer die Anzeige)
sp_pat    = SP_RAM+$20          ; Pattern der aktuellen Position
sp_n      = SP_RAM+$21          ; Note der Zelle
sp_i      = SP_RAM+$22          ; Instrument der Zelle
sp_tick3  = SP_RAM+$23          ; Tick mod 3 (Arpeggio)
sp_t0     = SP_RAM+$24          ; 2: Hilfswerte
sp_t1     = SP_RAM+$26          ; 2
sp_t2     = SP_RAM+$28          ; 2
sp_t3     = SP_RAM+$2A          ; 2
sp_t4     = SP_RAM+$2C          ; 2
sp_t5     = SP_RAM+$2E          ; 2
sp_dh     = SP_RAM+$30          ; 2: Division, Dividend oben
sp_dl     = SP_RAM+$32          ; 2: Dividend unten, danach Quotient
sp_dd     = SP_RAM+$34          ; 2: Divisor
sp_dz     = SP_RAM+$36          ; 2: Zaehler
sp_aus    = SP_RAM+$38          ; 2: Periode fuer die Ausgabe
sp_reg    = SP_RAM+$3A          ; 2: Registerversatz n*16
sp_bild   = SP_RAM+$3C          ; 4: Bildspur der Zeile (fuer spaeter)
sp_stumm  = SP_RAM+$40          ; Bit n = Spur n stumm
sp_tab    = SP_RAM+$41          ; 3: Ablauftabelle des Instruments
s_adr     = SP_RAM+$44          ; 8: Anfang des Samples je Samplekanal 0-3 (Bits 0-15)
s_bank    = SP_RAM+$4C          ; 8 (Abstand 2): Bank dazu
sp_bq     = SP_RAM+$54          ; Bildspur: Schreibstelle der Warteschlange (0-7)
sp_lz     = SP_RAM+$55          ; 3: Lautstaerke-Spalte der Zeile (8 Byte, 0 = leer)
sp_lzan   = SP_RAM+$58          ; 1: Song hat die Spalte (Arbeitskopie, Version 2)
sp_lh     = SP_RAM+$59          ; Laenge Bits 16-23 beim Sample-Start
sp_sh     = SP_RAM+$5A          ; Schleife Bits 16-23
sp_hz     = SP_RAM+$5B          ; 3: Huellkurve eines Instruments
sp_hzan   = SP_RAM+$5E          ; Song hat Huellkurven (Version 3)
sp_bqueue = SP_RAM+$60          ; 8 x 4 Byte: Befehl, Wert (12 Bit), frei
sp_ezeit  = SP_RAM+$80          ; 2: zuletzt geschriebene Echo-Zeit (Pxx)
sp_pzan   = SP_RAM+$82          ; Song hat ein Pult (Version 4) und sp_pvek ist gesetzt
sp_pbasis = SP_RAM+$83          ; 3: Pult von Instrument 0
sp_pz     = SP_RAM+$86          ; 3: Pult eines Instruments (Modul)
sp_fan    = SP_RAM+$89          ; Filter-Huellkurve laeuft
sp_fbasis = SP_RAM+$8A          ; 2: Eckfrequenz ohne die Huellkurve
sp_fenv   = SP_RAM+$8C          ; 2: Huellkurve ueber der Eckfrequenz
sp_frate  = SP_RAM+$8E          ; Abklingen je Tick (x/256)
sp_gl     = SP_RAM+$8F          ; Bit n: Synthspur n gleitet (GLIDE)
g_tempo   = SP_RAM+$90          ; 8: Glide-Schritt (Periode) je Synthspur, Index Spur*2
sp_pvek   = SP_RAM+$98          ; 3: Rechnung des Pults (Modul); setzt TAKTSTOCK
                                ; ab +$A0 Pult-Editor (Modul), ab +$C0 Huellkurven-Editor

; Kanalfelder: je 16 Byte, Index X = Kanal * 2 (Byte-Werte im unteren Byte)
SP_FELD   = SP_RAM+$100
k_note    = SP_FELD+$000        ; letzte Note 1-96
k_ins     = SP_FELD+$010
k_vol     = SP_FELD+$020        ; 0-64
k_per     = SP_FELD+$030        ; Periode * 16
k_ziel    = SP_FELD+$040        ; Ziel des Ton-Portamentos
k_ptempo  = SP_FELD+$050
k_cmd     = SP_FELD+$060
k_par     = SP_FELD+$070
k_vibpos  = SP_FELD+$080
k_vibpar  = SP_FELD+$090
k_trempos = SP_FELD+$0A0
k_trempar = SP_FELD+$0B0
k_arp     = SP_FELD+$0C0        ; Halbtoene in diesem Tick
k_vdelta  = SP_FELD+$0D0        ; Vibrato (Periode, mit Vorzeichen)
k_tdelta  = SP_FELD+$0E0        ; Tremolo (Lautstaerke, mit Vorzeichen)
k_welle   = SP_FELD+$0F0        ; STEUER ohne Gate
k_puls    = SP_FELD+$100
k_pwm     = SP_FELD+$110
k_pwmpos  = SP_FELD+$120
k_pan     = SP_FELD+$130
k_klo     = SP_FELD+$140        ; Zaehler, Bits 0-15
k_khi     = SP_FELD+$150        ; Bits 16-23
k_neu     = SP_FELD+$160        ; 1 = anschlagen, 2 = loslassen
k_vnote   = SP_FELD+$170        ; EDx: verzoegerte Note
k_eigen   = SP_FELD+$180        ; Samplekanal gehoert der Spur (0: Zwitter)
k_ad      = SP_FELD+$190
k_sr      = SP_FELD+$1A0
k_filter  = SP_FELD+$1B0
k_offset  = SP_FELD+$1C0        ; 9xx: Versatz in Seiten
k_gate    = SP_FELD+$1D0
k_adneu   = SP_FELD+$1E0
k_abl     = SP_FELD+$200        ; Schritt in der Ablauftabelle, $FF = keiner
k_ablton  = SP_FELD+$210        ; Tonversatz aus der Ablauftabelle (mit Vorzeichen)
k_hpos    = SP_FELD+$220        ; Huellkurve: Tick (16 Bit)
k_hflag   = SP_FELD+$230        ; Bit 0 laeuft, Bit 1 losgelassen
k_hwert   = SP_FELD+$240        ; Wert 0-64
k_hfade   = SP_FELD+$250        ; Ausklingen 32768 .. 0 (16 Bit)
SP_ENDE   = SP_FELD+$260
sp_lbasis = SP_FELD+$260        ; 3: Lautstaerke-Spalte von Pattern 0
sp_hbasis = SP_FELD+$263        ; 3: Huellkurve von Instrument 0

	.dpage SP_RAM

;----------------------------------------------------------------------------
; Einrichten: Kanaele leer, Timer laeuft, kein Song

sp_init
	.as
	.xl
	phd
	pea SP_RAM
	pld
	php                         ; ohne Timer-Takt: sp_takt rechnet mit denselben
	sei                         ; Hilfsvariablen - kam er in sp_teilen dazwischen,
	stz sp_an                   ; stand sp_dz danach auf 0, und die Schleife lief
	stz sp_pos                  ; 65536 Runden, bis zum naechsten Takt, der sie
	stz sp_zeile                ; wieder auf 0 setzte (Laden hing, 06.10.2026)
	stz sp_bq
	jsr sp_kanaele_leeren
	jsr sp_kopf_lesen
	jsr sp_zeiger_setzen
	jsr sp_tempo_setzen
	plp
	pld
	rts

; Song (A = 1) oder Pattern in Schleife (A = 2) ab sp_pos, sp_zeile
sp_spielen
	.as
	.xl
	phd
	pea SP_RAM
	pld
	php
	sei
	pha
	stz sp_an
	jsr sp_kanaele_leeren
	jsr sp_kopf_lesen
	stz sp_tick
	stz sp_verz
	stz sp_wdh
	stz sp_halbz
	lda #$ff
	sta sp_sprung
	sta sp_bruch
	jsr sp_zeiger_setzen
	jsr sp_tempo_setzen
	inc sp_zaehler
	pla
	sta sp_an
	plp
	pld
	rts

sp_start
	.as
	.xl
	jsr sp_init
	lda #1
	jmp sp_spielen

; Anhalten: sofort alles still - Noten los, Huellkurven und Ausklingen
; vorbei, Samples und Stimmen aus, Echo aus (sp_kopf_lesen schaltet es beim
; naechsten Abspielen wieder an, der Puffer faengt dann von vorn an)
sp_halt
	.as
	.xl
	phd
	pea SP_RAM
	pld
	php
	sei
	stz sp_an
	ldx #0
-	stz k_cmd,x
	stz k_arp,x
	stz k_tdelta,x
	stz k_hflag,x
	stz k_vol,x
	#akku16
	stz k_vdelta,x
	#akku8
	lda #2
	sta k_neu,x
	inx
	inx
	cpx #16
	bne -
	jsr sp_still
	stz ECHO+4
	plp
	pld
	rts

; Note A mit Instrument sp_i auf Kanal X anschlagen (Editor: Vorhoeren)
sp_vorhoeren
	.as
	.xl
	phd
	pea SP_RAM
	pld
	php
	sei
	sta sp_n
	stz k_cmd,x
	stz k_par,x
	stz k_arp,x
	stz k_tdelta,x
	#akku16
	stz k_vdelta,x
	#akku8
	lda sp_i
	beq +
	sta k_ins,x
	jsr sp_instrument
+	jsr sp_note_an
	plp
	pld
	rts

; Tempo/BPM geaendert (sp_tempo, sp_bpm schon gesetzt): Timer neu stellen
sp_tempo_neu
	.as
	.xl
	phd
	pea SP_RAM
	pld
	php
	sei
	jsr sp_tempo_setzen
	plp
	pld
	rts

sp_loslassen
	.as
	.xl
	phd
	pea SP_RAM
	pld
	lda #2
	sta k_neu,x
	pld
	rts

; Kanalfelder leeren, Filter offen, Panorama aus dem Kopf
sp_kanaele_leeren
	.as
	stz sp_fan                  ; Pult: keine Filter-Huellkurve, niemand gleitet
	stz sp_gl
	ldx #0
-	stz SP_FELD,x
	inx
	cpx #SP_ENDE-SP_FELD
	bne -
	ldx #0
	ldy #TK_PAN
-	lda [sp_song],y
	sta k_pan,x
	lda #1
	sta k_eigen,x
	iny
	inx
	inx
	cpx #16
	bne -
	#akku16
	lda #$07ff                  ; Filter offen, Tiefpass, ohne Resonanz
	sta sp_ecke
	#akku8
	stz sp_reso
	stz sp_route
	lda #$10
	sta sp_fart
	jmp sp_still

; Laenge, Neustart, Tempo, BPM aus dem Songkopf
sp_kopf_lesen
	.as
	ldy #TK_LAENGE
	lda [sp_song],y
	bne +
	inc a
+	sta sp_laenge
	iny
	lda [sp_song],y
	sta sp_neu
	ldy #TK_TEMPO
	lda [sp_song],y
	bne +
	lda #6
+	sta sp_tempo
	iny
	lda [sp_song],y
	sta sp_bpm
	jsr sp_ebenen
	ldy #TK_SPEGEL              ; Samples gegen Synths (ORGEL $C544)
	lda [sp_song],y
	bne +
	lda #12
+	sta FILTER+4
	stz FILTER+5                ; Filterausgang: kein Echo, nicht verzerrt (Etappe 18)
	stz FILTER+6
	ldy #0                      ; Effekte der Samplekanaele aus (Etappe 16)
	lda #0
-	sta FX,y
	sta FX+KAN2,y               ; Kanaele 4-7
	iny
	cpy #$40
	bne -
	lda #ECHO_BANK              ; Echo: 3 Zeilen, Rueck 6, Anteil 10 -
	sta ECHO+4                  ; hoerbar, sobald eine Spur Nxx sendet
	lda #6
	sta ECHO+2
	lda #10
	sta ECHO+3
	lda #$ff                    ; Zeit sicher schreiben
	sta sp_ezeit
	sta sp_ezeit+1
	lda #3
	jmp e_ezeit

;----------------------------------------------------------------------------
; Anhalten: alles still, Timer aus

sp_stopp
	.as
	.xl
	phd
	pea SP_RAM
	pld
	stz sp_an
	stz SP_TAST
	jsr sp_still
	stz ECHO+4                  ; Echo aus (der Puffer gehoert TAKTSTOCK)
	pld
	rts

sp_still
	.as
	ldy #0
-	lda #0
	sta ORG+4,y                 ; Gate aus
	sta ORG+7,y                 ; leise
	sta KAN+$b,y                ; Sample anhalten
	sta KAN+9,y
	sta KAN+KAN2+$b,y           ; ... auch auf den Kanaelen 4-7
	sta KAN+KAN2+9,y
	#akku16
	tya
	clc
	adc #$0010
	tay
	#akku8
	cpy #$40
	bne -
	stz FILTER+2
	lda #$1f
	sta FILTER+3
	rts

;----------------------------------------------------------------------------
; Timer A nach BPM: 2 500 000 us / BPM; unter 39 BPM passt das nicht in
; 16 Bit, dann laeuft der Timer doppelt so schnell und jeder zweite
; Interrupt faellt aus.

sp_tempo_setzen
	.as
	stz sp_halb
	lda sp_bpm
	cmp #39
	bcs +
	inc sp_halb
+	#akku16
	lda sp_bpm
	and #$00ff
	bne +
	lda #125
+	sta sp_dd
	lda sp_halb
	and #$00ff
	bne +
	lda #$0026                  ; 2 500 000 = $2625A0
	sta sp_dh
	lda #$25a0
	bra ++
+	lda #$0013                  ; 1 250 000 = $1312D0
	sta sp_dh
	lda #$12d0
+	sta sp_dl
	jsr sp_teilen
	dec a
	sta SP_TA
	#akku8
	lda #$01
	sta SP_TAST
	rts

;----------------------------------------------------------------------------
; sp_dh:sp_dl / sp_dd -> A und sp_dl (16 Bit, bei Ueberlauf $FFFF).
; Akku 16 Bit hinein und heraus; X und Y bleiben.

sp_teilen
	.al
	lda #16
	sta sp_dz
	lda sp_dh
	cmp sp_dd
	bcs _ueber
-	asl sp_dl
	rol a
	bcs _ab
	cmp sp_dd
	bcc +
_ab	sbc sp_dd
	inc sp_dl
+	dec sp_dz
	bne -
	lda sp_dl
	rts
_ueber
	lda #$ffff
	sta sp_dl
	rts

; sp_t2 = sp_t0 * A (beide 8 Bit). Akku 8 Bit hinein und heraus.
sp_mal
	.as
	sta sp_t1
	stz sp_t1+1
	stz sp_t0+1
	#akku16
	lda #8
	sta sp_dz
	lda #0
-	lsr sp_t1
	bcc +
	clc
	adc sp_t0
+	asl sp_t0
	dec sp_dz
	bne -
	sta sp_t2
	#akku8
	rts

; Periode in A (16 Bit) auf PER_MIN..PER_MAX begrenzen
sp_per_klemmen
	.al
	bmi _min                    ; Unterlauf
	cmp #PER_MIN
	bcc _min
	cmp #PER_MAX+1
	bcc +
	lda #PER_MAX
+	rts
_min
	lda #PER_MIN
	rts

;----------------------------------------------------------------------------
; Zeiger auf die aktuelle Zeile: Song + $1000 + Pattern * $900 + Zeile * 36

sp_zeiger_setzen
	.as
	#akku16
	lda sp_pos
	and #$007f
	clc
	adc #TK_FOLGE
	tay
	#akku8
	lda [sp_song],y
	sta sp_pat
	#akku16
	and #$00ff
	sta sp_t0
	asl a
	asl a
	asl a
	clc
	adc sp_t0                   ; Pattern * 9 = Bits 8-23 des Versatzes
	sta sp_t1
	lda sp_zeile
	and #$003f
	asl a
	asl a
	sta sp_t0                   ; * 4
	asl a
	asl a
	asl a                       ; * 32
	clc
	adc sp_t0                   ; * 36
	adc #TK_PAT
	clc
	adc sp_song
	sta sp_zeiger
	#akku8
	lda sp_song+2
	adc #0
	sta sp_zeiger+2
	clc
	lda sp_zeiger+1
	adc sp_t1
	sta sp_zeiger+1
	lda sp_zeiger+2
	adc sp_t1+1
	sta sp_zeiger+2
	#akku16                     ; sp_lz = sp_lbasis + Pattern*512 + Zeile*8
	lda sp_zeile
	and #$003f
	asl a
	asl a
	asl a
	clc
	adc sp_lbasis
	sta sp_lz
	#akku8
	lda sp_lbasis+2
	adc #0
	sta sp_lz+2
	lda sp_pat
	asl a                       ; Pattern * 2 ab Bit 8 (Pattern < 128)
	clc
	adc sp_lz+1
	sta sp_lz+1
	lda sp_lz+2
	adc #0
	sta sp_lz+2
	rts

; sp_hilf = Eintrag des Instruments k_ins,x
sp_ins_zeiger
	.as
	#akku16
	lda k_ins,x
	and #$003f
	asl a
	asl a
	asl a
	asl a
	asl a
	clc
	adc #TK_INS
	adc sp_song
	sta sp_hilf
	#akku8
	lda sp_song+2
	adc #0
	sta sp_hilf+2
	rts

;----------------------------------------------------------------------------
; Ein Tick

sp_takt
	.as
	.xl
	phd
	pea SP_RAM
	pld
	lda sp_an
	bne +
	jsr sp_huellen              ; kein Song: Vorhoeren klingt weiter
	jsr sp_register
	bra _raus
+	lda sp_halb
	beq +
	lda sp_halbz
	eor #1
	sta sp_halbz
	beq _raus
+	lda sp_tick                 ; Tick mod 3 fuer Arpeggios
-	cmp #3
	bcc +
	sbc #3
	bra -
+	sta sp_tick3
	lda sp_tick
	bne _spaeter
	lda sp_wdh
	bne _wiederholt
	jsr sp_zeile_lesen
	bra _ausgeben
_wiederholt
	stz sp_wdh
_spaeter
	jsr sp_effekte
_ausgeben
	jsr sp_huellen
	jsr sp_register
	jsr sp_vorruecken
_raus
	pld
	rts

; nach jedem Tick: naechster Tick, naechste Zeile, naechste Position
sp_vorruecken
	.as
	inc sp_tick
	lda sp_tick
	cmp sp_tempo
	bcc _fertig
	stz sp_tick
	lda sp_verz
	beq +
	dec sp_verz
	lda #1
	sta sp_wdh
	rts
+	lda sp_an                   ; Pattern in Schleife: Position bleibt
	cmp #2
	bne _song
	lda #$ff
	sta sp_sprung
	lda sp_bruch
	cmp #$ff
	beq +
	sta sp_zeile
	lda #$ff
	sta sp_bruch
	bra _neu
+	inc sp_zeile
	lda sp_zeile
	cmp #64
	bcc _neu
	stz sp_zeile
	bra _neu
_song
	lda sp_bruch
	cmp #$ff
	bne _bruch
	lda sp_sprung
	cmp #$ff
	bne _sprung
	inc sp_zeile
	lda sp_zeile
	cmp #64
	bcc _neu
	stz sp_zeile
_naechste
	inc sp_pos
	bra _pruefen
_bruch
	sta sp_zeile
	lda #$ff
	sta sp_bruch
	lda sp_sprung
	cmp #$ff
	beq _naechste
	bra _springen
_sprung
	stz sp_zeile
_springen
	sta sp_pos
	lda #$ff
	sta sp_sprung
_pruefen
	lda sp_pos
	cmp sp_laenge
	bcc _neu
	lda sp_neu
	sta sp_pos
_neu
	jsr sp_zeiger_setzen
	inc sp_zaehler
_fertig
	rts

;----------------------------------------------------------------------------
; Tick 0: neue Zeile lesen

sp_zeile_lesen
	.as
	ldx #0
	ldy #0
-	phy
	jsr sp_zelle
	ply
	iny
	iny
	iny
	iny
	inx
	inx
	cpx #16
	bne -
	ldy #32                     ; Bildspur merken
-	lda [sp_zeiger],y
	sta sp_bild-32,y
	iny
	cpy #36
	bne -
	lda sp_bild                 ; Befehl da: in die Warteschlange fuer die
	beq +                       ; Buehne (die holt ihn im Hauptprogramm ab)
	lda sp_bq
	asl a
	asl a
	#akku16
	and #$00ff
	tax
	#akku8
	lda sp_bild
	sta sp_bqueue,x
	lda sp_bild+1
	sta sp_bqueue+1,x
	lda sp_bild+2
	sta sp_bqueue+2,x
	lda sp_bq
	inc a
	and #7
	sta sp_bq
+	rts

; Zelle ab Y fuer Kanal X
sp_zelle
	.as
	lda [sp_zeiger],y
	sta sp_n
	iny
	lda [sp_zeiger],y
	sta sp_i
	iny
	lda [sp_zeiger],y
	sta k_cmd,x
	iny
	lda [sp_zeiger],y
	sta k_par,x
	stz k_arp,x
	stz k_tdelta,x
	#akku16
	stz k_vdelta,x
	#akku8
	lda sp_i
	beq +
	sta k_ins,x
	jsr sp_instrument
+	jsr sp_laut_spalte
	lda sp_n
	beq _effekt
	cmp #$ff
	bne +
	lda #2                      ; === loslassen
	sta k_neu,x
	bra _effekt
+	cmp #97
	bcs _effekt
	lda k_cmd,x
	cmp #3
	beq _ziel
	cmp #5
	beq _ziel
	cmp #$0e
	bne _an
	lda k_par,x                 ; ED1-EDF: Note spaeter
	cmp #$d1
	bcc _an
	cmp #$e0
	bcs _an
	lda sp_n
	sta k_vnote,x
	bra _effekt
_an
	lda #2                      ; GLIDE (Pult): gleiten statt anschlagen
	jsr sp_pult
	bcs _effekt
	jsr sp_note_an
	bra _effekt
_ziel
	#akku16
	lda sp_n
	and #$00ff
	asl a
	phx                         ; (lang ueber X: der Abspieler laeuft auch im ROM)
	tax
	lda @l sp_perioden,x
	plx
	sta k_ziel,x
	#akku8
_effekt
	jmp sp_effekt_null

; Lautstaerke-Spalte (ab Version 2) und Huellkurven (ab Version 3): in der
; Arbeitskopie (Marke) an festen Stellen fuer 128 Patterns, in einer Datei
; hinter Samples und Bildteil (Anfang 40 + Laenge 44 + Bildteil 60)
sp_ebenen
	.as
	stz sp_lzan
	stz sp_hzan
	stz sp_pzan
	ldy #3
	lda [sp_song],y
	cmp #2
	bcs +
	rts
+	sta sp_t4                   ; Version
	ldy #63
	lda [sp_song],y
	cmp #$e7
	bne _datei
	#akku16
	lda #<>TK_LAUT
	clc
	adc sp_song
	sta sp_lbasis
	#akku8
	lda #`TK_LAUT
	adc sp_song+2
	sta sp_lbasis+2
	lda #128
	bra _basis
_datei
	#akku16
	ldy #40
	lda [sp_song],y
	clc
	ldy #44
	adc [sp_song],y
	sta sp_t0
	#akku8
	ldy #42
	lda [sp_song],y
	ldy #46
	adc [sp_song],y
	sta sp_t1
	#akku16
	lda sp_t0
	clc
	ldy #60
	adc [sp_song],y
	sta sp_t0
	#akku8
	lda sp_t1
	ldy #62
	adc [sp_song],y
	sta sp_t1
	#akku16
	lda sp_t0
	clc
	adc sp_song
	sta sp_lbasis
	#akku8
	lda sp_t1
	adc sp_song+2
	sta sp_lbasis+2
	ldy #26                     ; Patterns in der Datei
	lda [sp_song],y
_basis
	inc sp_lzan
	asl a                       ; Huellkurven = Lautstaerken + Patterns * 512
	sta sp_t0
	lda #0
	rol a
	sta sp_t0+1
	lda sp_lbasis
	sta sp_hbasis
	clc
	lda sp_lbasis+1
	adc sp_t0
	sta sp_hbasis+1
	lda sp_lbasis+2
	adc sp_t0+1
	sta sp_hbasis+2
	lda sp_t4
	cmp #3
	bcc +
	inc sp_hzan
	cmp #4                      ; Pult (Version 4) gleich hinter den Huellkurven,
	bcc +                       ; gerechnet im Modul
	lda sp_pvek+2               ; nur, wenn die Rechnung da ist (TAKTSTOCK: Modul
	beq +                       ; in Bank $E0, SONG: System-ROM; sonst keine)
	#akku16
	lda sp_hbasis
	clc
	adc #64*64
	sta sp_pbasis
	#akku8
	lda sp_hbasis+2
	adc #0
	sta sp_pbasis+2
	inc sp_pzan
+	rts

; Lautstaerke-Spalte der Zelle (nach dem Instrument, vor der Note und den
; Effekten - Cxx gewinnt): 1-65 = Lautstaerke 0-64
sp_laut_spalte
	.as
	lda sp_lzan
	beq _r
	txa
	lsr a
	#akku16
	and #$00ff
	tay
	#akku8
	lda [sp_lz],y
	beq _r
	dec a
	cmp #65
	bcc +
	lda #64
+	sta k_vol,x
_r	rts

; Instrument k_ins,x in den Kanal uebernehmen
sp_instrument
	.as
	jsr sp_ins_zeiger
	ldy #IN_ART
	lda [sp_hilf],y
	bne +
	rts
+	sta sp_t0
	ldy #IN_LAUT
	lda [sp_hilf],y
	sta k_vol,x
	ldy #IN_PAN
	lda [sp_hilf],y
	beq +
	sta k_pan,x
+	ldy #IN_ZAEHLER             ; Zaehler: Synthspur und reine Samples hier,
	cpx #8                      ; Zwitter auf einer Samplespur ab IN_ZW
	bcc +
	lda sp_t0
	cmp #3
	bne +
	ldy #IN_ZW
+	#akku16
	lda [sp_hilf],y
	sta k_klo,x
	#akku8
	iny
	iny
	lda [sp_hilf],y
	sta k_khi,x
	cpx #8
	bcs _fertig
	ldy #IN_WELLE
	lda [sp_hilf],y
	sta k_welle,x
	iny
	lda [sp_hilf],y
	sta k_ad,x
	iny
	lda [sp_hilf],y
	sta k_sr,x
	iny
	#akku16
	lda [sp_hilf],y
	sta k_puls,x
	#akku8
	ldy #IN_PWM
	lda [sp_hilf],y
	sta k_pwm,x
	ldy #IN_FILTER
	lda [sp_hilf],y
	sta k_filter,x
_fertig
	rts

; Note sp_n auf Kanal X anschlagen
sp_note_an
	.as
	lda @l sp_bit,x                ; ein neuer Anschlag gleitet nicht (GLIDE)
	trb sp_gl
	lda sp_n
	sta k_note,x
	#akku16
	and #$00ff
	asl a
	phx                         ; (lang ueber X: der Abspieler laeuft auch im ROM)
	tax
	lda @l sp_perioden,x
	plx
	sta k_per,x
	stz k_vdelta,x
	#akku8
	stz k_vibpos,x
	stz k_trempos,x
	stz k_offset,x
	lda #64                     ; Huellkurve von vorn (auch beim Vorhoeren)
	sta k_hwert,x
	stz k_hflag,x
	jsr sp_hz_setzen
	bcc +
	lda #1
	sta k_hflag,x
	#akku16
	stz k_hpos,x
	lda #32768
	sta k_hfade,x
	#akku8
+	lda #1
	sta k_neu,x
	jmp sp_ablauf_start

; Ablauftabelle des Instruments k_ins,x: sp_tab setzen, Schritt 0 oder keiner
sp_ablauf_start
	.as
	lda #$ff
	sta k_abl,x
	stz k_ablton,x
	cpx #8                      ; nur Synthesestimmen
	bcs _r
	jsr sp_tab_zeiger
	ldy #0
	lda [sp_tab],y
	iny
	ora [sp_tab],y
	beq _r
	stz k_abl,x
	jsr sp_ins_zeiger           ; Welle wieder vom Instrument
	ldy #IN_WELLE
	lda [sp_hilf],y
	sta k_welle,x
_r	rts

; sp_tab = Song + $CC0 + k_ins,x * 12
sp_tab_zeiger
	.as
	#akku16
	lda k_ins,x
	and #$003f
	asl a
	asl a
	sta sp_t0                   ; * 4
	asl a                       ; * 8
	clc
	adc sp_t0                   ; * 12
	clc
	adc #TK_ABLAUF
	adc sp_song
	sta sp_tab
	#akku8
	lda sp_song+2
	adc #0
	sta sp_tab+2
	rts

; ein Schritt der Ablauftabelle (vor der Ausgabe, jeden Tick)
sp_ablauf_schritt
	.as
	lda k_abl,x
	cmp #ABL_SCHRITTE
	bcs _r
	jsr sp_tab_zeiger
	lda #2                      ; hoechstens zwei Spruenge hintereinander
	sta sp_t2
_lesen
	lda k_abl,x
	asl a
	#akku16
	and #$00ff
	tay
	#akku8
	lda [sp_tab],y
	cmp #$ff
	bne _schritt
	iny                         ; Sprung zu Schritt "Ton"
	lda [sp_tab],y
	cmp #ABL_SCHRITTE
	bcs _ende
	sta k_abl,x
	dec sp_t2
	bne _lesen
	bra _ende
_schritt
	cmp #0
	beq +
	sta k_welle,x
+	iny
	lda [sp_tab],y
	sta k_ablton,x
	lda k_abl,x
	inc a
	cmp #ABL_SCHRITTE
	bcc +
_ende
	lda #$ff
+	sta k_abl,x
_r	rts

;----------------------------------------------------------------------------
; Effekte in Tick 0 (A = Wert, X = Kanal)

sp_effekt_null
	.as
	#akku16
	lda k_cmd,x
	and #$00ff
	cmp #30
	bcs _nichts
	asl a
	phx
	tax
	lda @l tab_null,x
	plx
	pha
	#akku8
	lda k_par,x
	rts
_nichts
	#akku8
	rts

tab_null
	.word <>e_nichts-1, <>e_nichts-1, <>e_nichts-1, <>e_ptempo-1          ; 0-3
	.word <>e_vibpar-1, <>e_nichts-1, <>e_nichts-1, <>e_trempar-1         ; 4-7
	.word <>e_pan-1, <>e_offset-1, <>e_nichts-1, <>e_sprung-1             ; 8-B
	.word <>e_laut-1, <>e_bruch-1, <>e_extra-1, <>e_tempo-1               ; C-F
	.word <>e_welle-1, <>e_puls-1, <>e_pwm-1, <>e_ecke-1                  ; G-J
	.word <>e_reso-1, <>e_nichts-1, <>e_ad-1                            ; K-M
	.word <>e_esend-1, <>e_echo-1, <>e_ezeit-1, <>e_crush-1, <>e_zerr-1      ; N-R
	.word <>e_fecho-1, <>e_fzerr-1                                    ; S-T

e_nichts
	rts

;----------------------------------------------------------------------------
; Effekte der ORGEL fuer den Samplekanal der Spur (Etappe 16). A = Wert,
; X = Spur * 2; der Samplekanal ist Spur & 3 (SYN-Spuren: der geliehene).

e_fxkanal                       ; Y = Versatz des Samplekanals ab FX
	.as
	txa
	and #6
	asl a
	asl a
	asl a
	#akku16
	and #$00ff
	cpx #8
	bcs +
	ora #KAN2                   ; SYN-Spur: ihr Kanal 4+n auf Seite 2
+	tay
	#akku8
	rts

e_esend                         ; Nxx: Anteil der Spur am Echo (0-F)
	.as
	phy
	pha
	jsr e_fxkanal
	pla
	and #$0f
	sta FX+3,y
	ply
	rts

e_echo                          ; Oxy: Rueckkopplung x, Anteil y
	.as
	pha
	and #$0f
	sta ECHO+3
	pla
	lsr a
	lsr a
	lsr a
	lsr a
	sta ECHO+2
	rts

e_crush                         ; Qxy: Bits x (0 = alle), Wert y*12 us halten
	.as
	phy
	pha
	jsr e_fxkanal
	pla
	pha
	lsr a
	lsr a
	lsr a
	lsr a
	and #7
	sta FX+0,y
	pla
	and #$0f
	sta sp_t0                   ; y*12 = y*8 + y*4
	asl a
	asl a
	sta sp_t1
	asl a
	clc
	adc sp_t1
	sta FX+1,y
	ply
	rts

e_zerr                          ; Rxy: Verzerrung x, y = 1: durchs Filter
	.as
	phy
	pha
	jsr e_fxkanal
	pla
	pha
	lsr a
	lsr a
	lsr a
	lsr a
	sta FX+2,y
	pla
	and #1
	sta FX+4,y
	ply
	rts

e_fecho                         ; Sxx: Filterausgang ins Echo 0-F (Etappe 18)
	.as
	and #$0f
	sta FILTER+5
	rts

e_fzerr                         ; Txx: Filterausgang verzerren 0-F (Etappe 18)
	.as
	and #$0f
	sta FILTER+6
	rts

; Pxx: Echo-Zeit xx Zeilen. Werte zu 32 us = xx * Tempo * 78125 / BPM,
; gerechnet als (xx * Tempo) * (78125 / BPM), hoechstens 32767 (gut 1 s).
e_ezeit
	.as
	phy
	sta sp_t0
	lda sp_tempo
	jsr sp_mal                  ; sp_t2 = xx * Tempo
	#akku16
	lda #1                      ; 78125 / BPM
	sta sp_dh
	lda #$312d
	sta sp_dl
	lda sp_bpm
	and #$00ff
	sta sp_dd
	jsr sp_teilen
	sta sp_t3
	stz sp_dh                   ; sp_dh:sp_dl = sp_t2 * sp_t3
	stz sp_dl
	ldy #16
-	asl sp_dl
	rol sp_dh
	asl sp_t2
	bcc +
	lda sp_dl
	clc
	adc sp_t3
	sta sp_dl
	lda sp_dh
	adc #0
	sta sp_dh
+	dey
	bne -
	lda sp_dh
	bne _voll
	lda sp_dl
	bpl _zeit
_voll
	lda #32767
_zeit
	cmp sp_ezeit                ; dieselbe Zeit nicht neu schreiben - das
	beq _gleich                 ; finge das Echo von vorn an (Fahne weg)
	sta sp_ezeit
	sta ECHO                    ; Zeit (schreibt unten, dann oben)
_gleich
	#akku8
	ply
	rts

e_ptempo                        ; 3xx: Tempo merken
	.as
	beq +
	sta k_ptempo,x
+	rts

e_vibpar                        ; 4xy: Tempo/Tiefe merken (0 = wie vorher)
	.as
	and #$0f
	beq +
	sta sp_t0
	lda k_vibpar,x
	and #$f0
	ora sp_t0
	sta k_vibpar,x
+	lda k_par,x
	and #$f0
	beq +
	sta sp_t0
	lda k_vibpar,x
	and #$0f
	ora sp_t0
	sta k_vibpar,x
+	rts

e_trempar                       ; 7xy
	.as
	and #$0f
	beq +
	sta sp_t0
	lda k_trempar,x
	and #$f0
	ora sp_t0
	sta k_trempar,x
+	lda k_par,x
	and #$f0
	beq +
	sta sp_t0
	lda k_trempar,x
	and #$0f
	ora sp_t0
	sta k_trempar,x
+	rts

e_pan                           ; 8xx: 00 links, 80 Mitte, FF rechts
	.as
	sta sp_t0
	lsr a
	lsr a
	lsr a
	cmp #16
	bcc +
	lda #15
+	sta sp_t1                   ; rechts
	lda sp_t0
	eor #$ff
	lsr a
	lsr a
	lsr a
	cmp #16
	bcc +
	lda #15
+	asl a
	asl a
	asl a
	asl a
	ora sp_t1
	sta k_pan,x
	rts

e_offset                        ; 9xx
	.as
	sta k_offset,x
	rts

e_sprung                        ; Bxx
	.as
	sta sp_sprung
	rts

e_laut                          ; Cxx
	.as
	cmp #65
	bcc +
	lda #64
+	sta k_vol,x
	rts

e_bruch                         ; Dxy: weiter in Zeile x*10+y
	.as
	sta sp_t0
	lsr a
	lsr a
	lsr a
	lsr a
	sta sp_t1
	asl a
	asl a
	clc
	adc sp_t1
	asl a
	sta sp_t1
	lda sp_t0
	and #$0f
	clc
	adc sp_t1
	cmp #64
	bcc +
	lda #0
+	sta sp_bruch
	rts

e_tempo                         ; Fxx: unter 32 Tempo, sonst BPM; F00 Ende
	.as
	cmp #0
	bne +
	stz sp_an
	jmp sp_still
+	cmp #32
	bcs +
	sta sp_tempo
	rts
+	sta sp_bpm
	jmp sp_tempo_setzen

e_welle                         ; Gxy: x Wellen (1 Dreieck 2 Saege 4 Puls 8 Rauschen), y 1 Sync 2 Ring
	.as
	sta sp_t0
	and #$f0
	sta sp_t1
	lda sp_t0
	and #$03
	asl a
	ora sp_t1
	sta k_welle,x
	rts

e_puls                          ; Hxx: Pulsbreite xx * 16
	.as
	#akku16
	and #$00ff
	asl a
	asl a
	asl a
	asl a
	sta k_puls,x
	#akku8
	rts

e_pwm                           ; Ixy
	.as
	sta k_pwm,x
	rts

e_ecke                          ; Jxx: Eckfrequenz xx * 8
	.as
	#akku16
	and #$00ff
	asl a
	asl a
	asl a
	sta sp_ecke
	sta sp_fbasis               ; Grundlage der Filter-Huellkurve (Pult)
	#akku8
	rts

e_reso                          ; Kxy: Resonanz x, Art y (1 Tief 2 Band 4 Hoch)
	.as
	sta sp_t0
	and #$f0
	sta sp_reso
	lda sp_t0
	and #$07
	beq +
	asl a
	asl a
	asl a
	asl a
	sta sp_fart
+	rts

e_ad                            ; Mxy: Attack/Decay neu
	.as
	sta k_ad,x
	lda #1
	sta k_adneu,x
	rts

e_extra                         ; Exy
	.as
	#akku16
	and #$00f0
	lsr a
	lsr a
	lsr a
	phx
	tax
	lda @l tab_extra,x
	plx
	pha
	#akku8
	lda k_par,x
	and #$0f
	rts

tab_extra
	.word <>e_nichts-1, <>e_fein_hoch-1, <>e_fein_runter-1, <>e_nichts-1  ; E0-E3
	.word <>e_nichts-1, <>e_nichts-1, <>e_nichts-1, <>e_nichts-1          ; E4-E7
	.word <>e_pan_grob-1, <>e_nichts-1, <>e_lauter-1, <>e_leiser-1        ; E8-EB
	.word <>e_schnitt0-1, <>e_nichts-1, <>e_verzoegern-1, <>e_nichts-1    ; EC-EF

e_fein_hoch                     ; E1x
	.as
	#akku16
	and #$000f
	asl a
	asl a
	asl a
	asl a
	sta sp_t0
	lda k_per,x
	sec
	sbc sp_t0
	jsr sp_per_klemmen
	sta k_per,x
	#akku8
	rts

e_fein_runter                   ; E2x
	.as
	#akku16
	and #$000f
	asl a
	asl a
	asl a
	asl a
	clc
	adc k_per,x
	jsr sp_per_klemmen
	sta k_per,x
	#akku8
	rts

e_pan_grob                      ; E8x
	.as
	sta sp_t0
	asl a
	asl a
	asl a
	asl a
	ora sp_t0
	jmp e_pan

e_lauter                        ; EAx
	.as
	clc
	adc k_vol,x
	cmp #65
	bcc +
	lda #64
+	sta k_vol,x
	rts

e_leiser                        ; EBx
	.as
	sta sp_t0
	lda k_vol,x
	sec
	sbc sp_t0
	bcs +
	lda #0
+	sta k_vol,x
	rts

e_schnitt0                      ; EC0: sofort stumm
	.as
	bne +
	stz k_vol,x
+	rts

e_verzoegern                    ; EEx: Zeile x-mal wiederholen
	.as
	sta sp_verz
	rts

;----------------------------------------------------------------------------
; Effekte in den Ticks danach

sp_effekte
	.as
	ldx #0
-	jsr sp_effekt_tick
	inx
	inx
	cpx #16
	bne -
	rts

sp_effekt_tick
	.as
	#akku16
	lda k_cmd,x
	and #$00ff
	cmp #30
	bcs _nichts
	asl a
	phx
	tax
	lda @l tab_tick,x
	plx
	pha
	#akku8
	lda k_par,x
	rts
_nichts
	#akku8
	rts

tab_tick
	.word <>e_arp-1, <>e_hoch-1, <>e_runter-1, <>e_porta-1                ; 0-3
	.word <>e_vibrato-1, <>e_porta_gleiten-1, <>e_vibrato_gleiten-1, <>e_tremolo-1
	.word <>e_nichts-1, <>e_nichts-1, <>e_gleiten-1, <>e_nichts-1         ; 8-B
	.word <>e_nichts-1, <>e_nichts-1, <>e_extra_tick-1, <>e_nichts-1      ; C-F
	.word <>e_nichts-1, <>e_nichts-1, <>e_nichts-1, <>e_nichts-1          ; G-J
	.word <>e_nichts-1, <>e_filter-1, <>e_nichts-1                      ; K-M
	.word <>e_nichts-1, <>e_nichts-1, <>e_nichts-1, <>e_nichts-1, <>e_nichts-1 ; N-R
	.word <>e_nichts-1, <>e_nichts-1                                  ; S-T

e_arp                           ; 0xy
	.as
	cmp #0
	beq _r
	sta sp_t0
	lda sp_tick3
	beq _null
	cmp #1
	bne _zwei
	lda sp_t0
	lsr a
	lsr a
	lsr a
	lsr a
	bra _setzen
_zwei
	lda sp_t0
	and #$0f
	bra _setzen
_null
	lda #0
_setzen
	sta k_arp,x
_r	rts

e_hoch                          ; 1xx: Periode kleiner
	.as
	#akku16
	and #$00ff
	asl a
	asl a
	asl a
	asl a
	sta sp_t0
	lda k_per,x
	sec
	sbc sp_t0
	jsr sp_per_klemmen
	sta k_per,x
	#akku8
	rts

e_runter                        ; 2xx: Periode groesser
	.as
	#akku16
	and #$00ff
	asl a
	asl a
	asl a
	asl a
	clc
	adc k_per,x
	jsr sp_per_klemmen
	sta k_per,x
	#akku8
	rts

e_porta                         ; 3xx: zur Zielnote gleiten
	.as
	#akku16
	lda k_ptempo,x
	and #$00ff
	asl a
	asl a
	asl a
	asl a
	sta sp_t0
	lda k_ziel,x
	beq _fertig
	cmp k_per,x
	beq _fertig
	bcc _hoch                   ; Ziel kleiner: Periode verkleinern
	lda k_per,x
	clc
	adc sp_t0
	cmp k_ziel,x
	bcc +
	lda k_ziel,x
+	sta k_per,x
	bra _fertig
_hoch
	lda k_per,x
	sec
	sbc sp_t0
	bcc _ziel
	cmp k_ziel,x
	bcs +
_ziel
	lda k_ziel,x
+	sta k_per,x
_fertig
	#akku8
	rts

e_porta_gleiten                 ; 5xy
	.as
	jsr e_porta
	jmp e_gleiten

e_vibrato_gleiten               ; 6xy
	.as
	jsr e_vibrato
	jmp e_gleiten

e_vibrato                       ; 4xy
	.as
	lda k_vibpos,x
	#akku16
	and #$001f
	phx
	tax
	#akku8
	lda @l sp_sinus,x
	plx
	sta sp_t0
	lda k_vibpar,x
	and #$0f
	jsr sp_mal                  ; sp_t2 = Sinus * Tiefe
	#akku16
	lda sp_t2
	lsr a                       ; * 16 / 128 (Periode * 16)
	lsr a
	lsr a
	sta sp_t2
	#akku8
	lda k_vibpos,x
	and #$20
	#akku16
	beq +
	lda #0
	sec
	sbc sp_t2
	sta sp_t2
+	lda sp_t2
	sta k_vdelta,x
	#akku8
	lda k_vibpar,x
	lsr a
	lsr a
	lsr a
	lsr a
	clc
	adc k_vibpos,x
	and #$3f
	sta k_vibpos,x
	rts

e_tremolo                       ; 7xy
	.as
	lda k_trempos,x
	#akku16
	and #$001f
	phx
	tax
	#akku8
	lda @l sp_sinus,x
	plx
	sta sp_t0
	lda k_trempar,x
	and #$0f
	jsr sp_mal
	#akku16
	lda sp_t2
	lsr a                       ; / 64
	lsr a
	lsr a
	lsr a
	lsr a
	lsr a
	sta sp_t2
	#akku8
	lda k_trempos,x
	and #$20
	beq +
	lda #0
	sec
	sbc sp_t2
	bra ++
+	lda sp_t2
+	sta k_tdelta,x
	lda k_trempar,x
	lsr a
	lsr a
	lsr a
	lsr a
	clc
	adc k_trempos,x
	and #$3f
	sta k_trempos,x
	rts

e_gleiten                       ; Axy (auch 5, 6): x lauter, y leiser
	.as
	lda k_par,x
	and #$f0
	beq _runter
	lsr a
	lsr a
	lsr a
	lsr a
	clc
	adc k_vol,x
	cmp #65
	bcc +
	lda #64
+	sta k_vol,x
	rts
_runter
	lda k_par,x
	and #$0f
	sta sp_t0
	lda k_vol,x
	sec
	sbc sp_t0
	bcs +
	lda #0
+	sta k_vol,x
	rts

e_extra_tick                    ; E9x Wiederholen, ECx Abschneiden, EDx Verzoegern
	.as
	and #$f0
	cmp #$90
	beq _wieder
	cmp #$c0
	beq _schnitt
	cmp #$d0
	beq _verz
	rts
_wieder
	lda k_par,x
	and #$0f
	beq _r
	sta sp_t0
	lda sp_tick
-	sec
	sbc sp_t0
	beq _neu
	bcs -
_r	rts
_neu
	lda #1
	sta k_neu,x
	rts
_schnitt
	lda k_par,x
	and #$0f
	cmp sp_tick
	bne _r
	stz k_vol,x
	rts
_verz
	lda k_par,x
	and #$0f
	cmp sp_tick
	bne _r
	lda k_vnote,x
	beq _r
	sta sp_n
	jmp sp_note_an

e_filter                        ; Lxy: Eckfrequenz x hoch / y runter je Tick
	.as
	lsr a
	lsr a
	lsr a
	lsr a
	beq _runter
	#akku16
	and #$00ff
	clc
	adc sp_ecke
	cmp #2048
	bcc +
	lda #2047
+	sta sp_ecke
	#akku8
	rts
_runter
	lda k_par,x
	#akku16
	and #$000f
	sta sp_t0
	lda sp_ecke
	sec
	sbc sp_t0
	bcs +
	lda #0
+	sta sp_ecke
	#akku8
	rts

;----------------------------------------------------------------------------
; Jeden Tick: alles in die ORGEL schreiben

sp_register
	.as
	ldx #0
-	#akku16
	txa
	asl a
	asl a
	asl a
	sta sp_reg
	#akku8
	jsr sp_stimme
	inx
	inx
	cpx #8
	bne -
-	#akku16
	txa
	sec
	sbc #8
	asl a
	asl a
	asl a
	sta sp_reg
	#akku8
	jsr sp_probe
	inx
	inx
	cpx #16
	bne -
	#akku16
	lda sp_ecke
	sta FILTER
	#akku8
	lda sp_reso
	ora sp_route
	sta FILTER+2
	lda sp_fart
	ora #$0f
	sta FILTER+3
	rts

; Periode fuer die Ausgabe: Arpeggio und Vibrato -> sp_aus
sp_periode
	.as
	lda k_arp,x
	clc
	adc k_ablton,x
	beq _ohne
	#akku16                     ; Note + Versatz, mit Vorzeichen, 1-96
	and #$00ff
	cmp #$0080
	bcc +
	ora #$ff00
+	sta sp_t0
	lda k_note,x
	and #$00ff
	clc
	adc sp_t0
	bmi _tief
	beq _tief
	cmp #97
	bcc +
	lda #96
	bra +
_tief
	lda #1
+	asl a
	phx                         ; (lang ueber X: der Abspieler laeuft auch im ROM)
	tax
	lda @l sp_perioden,x
	plx
	bra _vib
_ohne
	#akku16
	lda k_per,x
_vib
	clc
	adc k_vdelta,x
	jsr sp_per_klemmen
	sta sp_aus
	#akku8
	rts

; Zaehler / sp_aus -> sp_dl
sp_rate
	.as
	#akku16
	lda k_khi,x
	and #$00ff
	sta sp_dh
	lda k_klo,x
	sta sp_dl
	lda sp_aus
	sta sp_dd
	jsr sp_teilen
	#akku8
	rts

; Lautstaerke mit Tremolo, 0-64 -> A
sp_lautstaerke
	.as
	jsr sp_laut_roh
	pha
	lda k_hflag,x
	bne +
	pla
	rts
+	lda k_hwert,x               ; mal Huellkurve / 64
	sta sp_t0
	pla
	jsr sp_mal
	#akku16
	lda sp_t2
	asl a
	asl a
	#akku8
	xba
	pha
	lda k_hflag,x               ; losgelassen: mal Ausklingen / 32768
	and #2
	beq +
	lda k_hfade+1,x
	sta sp_t0
	pla
	jsr sp_mal
	#akku16
	lda sp_t2
	asl a
	#akku8
	xba
	rts
+	pla
	rts

sp_laut_roh
	.as
	lda @l sp_bit,x
	and sp_stumm
	beq +
	lda #0
	rts
+	lda k_tdelta,x
	bmi _minus
	clc
	adc k_vol,x
	cmp #65
	bcc _ok
	lda #64
	rts
_minus
	clc
	adc k_vol,x
	bcs _ok
	lda #0
_ok	rts

; Pulsbreite mit PWM -> sp_t2
sp_pulsbreite
	.as
	lda k_pwm,x
	beq _ohne
	lsr a                       ; Tempo * 2 je Tick
	lsr a
	lsr a
	asl a
	clc
	adc k_pwmpos,x
	sta k_pwmpos,x
	bpl +
	eor #$ff                    ; Dreieck 0-127
+	sec
	sbc #64                     ; -64 .. 63
	sta sp_t4
	lda k_pwm,x
	and #$0f
	asl a                       ; Tiefe * 2
	sta sp_t5
	lda sp_t4
	bpl _plus
	eor #$ff
	inc a
	sta sp_t0
	lda sp_t5
	jsr sp_mal
	#akku16
	lda k_puls,x
	sec
	sbc sp_t2
	bcs _klemm
	lda #0
	bra _klemm
_plus
	sta sp_t0
	lda sp_t5
	jsr sp_mal
	#akku16
	lda k_puls,x
	clc
	adc sp_t2
_klemm
	cmp #4096
	bcc +
	lda #4095
+	sta sp_t2
	#akku8
	rts
_ohne
	#akku16
	lda k_puls,x
	sta sp_t2
	#akku8
	rts

; Synthesestimme (X = Kanal * 2, sp_reg = n * 16)
sp_stimme
	.as
	lda k_neu,x
	beq _laufend
	cmp #2
	bne _an
	stz k_gate,x                ; loslassen
	lda k_hflag,x               ; Sample der Spur: mit Huellkurve ausklingen
	beq +
	ora #2
	sta k_hflag,x
	bra _laufend
+	ldy sp_reg                  ; ... sonst anhalten
	lda #0
	sta KAN+KAN2+$b,y
	bra _laufend
_an
	ldy sp_reg
	lda #0                      ; ein Sample der Spur endet mit dem neuen Ton
	sta KAN+KAN2+$b,y
	lda k_welle,x               ; Gate aus: die Huellkurve beginnt neu
	sta ORG+4,y
	lda k_ad,x
	sta ORG+5,y
	lda k_sr,x
	sta ORG+6,y
	lda #1
	sta k_gate,x
	stz k_pwmpos,x
	lda k_filter,x              ; Stimme durchs Filter?
	bmi +
	lda @l sp_bit,x
	eor #$ff
	and sp_route
	bra ++
+	lda @l sp_bit,x
	ora sp_route
+	sta sp_route
	jsr sp_ins_zeiger
	lda k_filter,x              ; Filter-Vorgabe des Instruments
	bpl _kein_filter
	and #$7f
	beq +
	pha
	and #$0f
	asl a
	asl a
	asl a
	asl a
	sta sp_reso
	pla
	and #$70
	beq +
	sta sp_fart
+	ldy #IN_ECKE
	lda [sp_hilf],y
	beq _kein_filter
	#akku16
	and #$00ff
	asl a
	asl a
	asl a
	sta sp_ecke
	#akku8
_kein_filter
	lda #0                      ; Pult: Filter-Huellkurve, Drive, Echo
	jsr sp_pult
	ldy #IN_ART                 ; Zwitter oder reines Sample: auf dem
	lda [sp_hilf],y             ; Samplekanal 4+n starten
	cmp #3
	bne +
	ldy #IN_ZW
	bra _sample
+	cmp #2
	bne _laufend
	ldy #IN_ZAEHLER
_sample
	jsr sp_zwitter
_laufend
	jsr sp_syn_probe            ; Sample der Spur nachfuehren
	jsr sp_ablauf_schritt
	lda k_adneu,x
	beq +
	stz k_adneu,x
	ldy sp_reg
	lda k_ad,x
	sta ORG+5,y
+	jsr sp_periode
	jsr sp_rate
	ldy sp_reg
	#akku16
	lda sp_dl
	sta ORG+0,y                 ; FREQ
	#akku8
	jsr sp_pulsbreite
	ldy sp_reg
	#akku16
	lda sp_t2
	sta ORG+2,y                 ; PULS
	#akku8
	jsr sp_lautstaerke
	#akku16
	and #$00ff
	phx
	tax
	#akku8
	lda @l sp_laut15,x
	plx
	ldy sp_reg
	sta ORG+7,y
	lda k_pan,x
	sta ORG+8,y
	lda k_welle,x
	ora k_gate,x
	sta ORG+4,y                 ; Gate (wieder) an
	stz k_neu,x
	rts

sp_bit
	.byte 1, 0, 2, 0, 4, 0, 8, 0, 16, 0, 32, 0, 64, 0, 128, 0

; Pult (Version 4): A = 0 Anschlag, 1 Tick, 2 GLIDE pruefen (C = 1: gleitet).
; Die Rechnung liegt im Modul von TAKTSTOCK (pult.asm) - ohne Pult nichts, C = 0
sp_pult
	.as
	pha
	lda sp_pzan
	beq _ohne
	pla
	phk
	per sp_pult_zurueck-1       ; (globale Marke: ein Umsetzer fuer andere Assembler rechnet nicht mit lokalen)
	jml [sp_pvek]
_ohne
	pla
	clc
sp_pult_zurueck
	rts

; Sample des Instruments sp_hilf auf dem Samplekanal 4+n der SYN-Spur n
; starten, Zaehler ab Y (Zwitter: IN_ZW, reines Sample: IN_ZAEHLER).
; Seit Etappe 17 hat jede SYN-Spur ihren eigenen Kanal - die SMP-Spur n
; behaelt ihren.
sp_zwitter
	.as
	jsr sp_zw_setzen
	#akku16                     ; sp_probe_an schreibt ab KAN + sp_reg
	lda sp_reg
	clc
	adc #KAN2
	sta sp_reg
	#akku8
	jsr sp_probe_an
	#akku16
	lda sp_reg
	sec
	sbc #KAN2
	sta sp_reg
	#akku8
	rts

; SCHRITT, LAUT und PAN des Kanals 4+n, Zaehler ab Y
sp_zw_setzen
	.as
	#akku16
	lda [sp_hilf],y
	sta sp_dl
	iny
	iny
	lda [sp_hilf],y
	and #$00ff
	sta sp_dh
	lda k_per,x
	sta sp_dd
	jsr sp_teilen
	ldy sp_reg
	sta KAN+KAN2+7,y            ; SCHRITT
	#akku8
	jsr sp_lautstaerke
	cmp #64
	bcc +
	lda #63
+	ldy sp_reg
	sta KAN+KAN2+9,y
	lda k_pan,x
	sta KAN+KAN2+$a,y
	rts

; jeden Tick: hat die SYN-Spur ein Sample-Instrument, dessen Kanal 4+n
; nachfuehren (Vibrato, Gleiten, Lautstaerke wirken so auch dort)
sp_syn_probe
	.as
	lda k_ins,x
	bne +
	rts
+	jsr sp_ins_zeiger
	ldy #IN_ART
	lda [sp_hilf],y
	cmp #2
	beq _rein
	cmp #3
	bne _r
	ldy #IN_ZW
	jmp sp_zw_setzen
_rein
	ldy #IN_ZAEHLER
	jmp sp_zw_setzen
_r	rts

; Samplekanal (X = Kanal * 2, sp_reg = k * 16)
sp_probe
	.as
	lda k_neu,x
	beq _laufend
	cmp #2
	bne _an
	stz k_neu,x
	lda k_hflag,x               ; mit Huellkurve: ausklingen lassen
	beq +
	ora #2
	sta k_hflag,x
	bra _laufend
+	ldy sp_reg                  ; sonst: loslassen = anhalten
	lda #0
	sta KAN+$b,y
	rts
_an
	stz k_neu,x
	lda #1
	sta k_eigen,x
	jsr sp_ins_zeiger
	ldy #IN_ART
	lda [sp_hilf],y
	and #2
	beq _fertig
	jsr sp_kanal_setzen
	jmp sp_probe_an
_laufend
	lda k_eigen,x
	beq _fertig
	jsr sp_kanal_setzen
_fertig
	rts

sp_kanal_setzen                 ; SCHRITT, LAUT, PAN
	.as
	jsr sp_periode
	jsr sp_rate
	ldy sp_reg
	#akku16
	lda sp_dl
	sta KAN+7,y
	#akku8
	jsr sp_lautstaerke
	cmp #64
	bcc +
	lda #63
+	ldy sp_reg
	sta KAN+9,y
	lda k_pan,x
	sta KAN+$a,y
	rts

; sp_hz = Huellkurve des Instruments k_ins,x. C = 1: sie ist an
sp_hz_setzen
	.as
	lda sp_hzan
	beq _nein
	#akku16
	lda k_ins,x
	and #$003f
	xba
	lsr a
	lsr a                       ; * 64
	clc
	adc sp_hbasis
	sta sp_hz
	#akku8
	lda sp_hbasis+2
	adc #0
	sta sp_hz+2
	lda [sp_hz]                 ; HK_ART Bit 0
	lsr a
	rts
_nein
	clc
	rts

; je Tick beim Spielen: Huellkurven aller Spuren, dann das Pult
sp_huellen
	.as
	ldx #0
-	lda k_hflag,x
	beq +
	jsr sp_huelle
+	inx
	inx
	cpx #16
	bne -
	lda #1
	jmp sp_pult

; Spur X: Wert an der Stelle k_hpos (zwischen zwei Punkten geradlinig),
; dann einen Tick weiter - Sustain haelt bis zum Loslassen, die Schleife
; springt zurueck; losgelassen klingt die Spur um HK_AUS je Tick aus
sp_huelle
	.as
	jsr sp_hz_setzen            ; Instrument ohne Huellkurve: aus
	bcs +
	stz k_hflag,x
	lda #64
	sta k_hwert,x
	rts
+	ldy #HK_N
	lda [sp_hz],y
	sta sp_t3                   ; Punkte
	stz sp_t4                   ; Punkt i
	ldy #HK_PUNKTE
_suchen
	lda sp_t4
	inc a
	cmp sp_t3
	bcs _letzter
	iny                         ; Y auf Punkt i+1
	iny
	iny
	iny
	#akku16
	lda [sp_hz],y
	cmp k_hpos,x
	#akku8
	beq +
	bcs _zwischen               ; Punkt i+1 liegt hinter der Stelle
+	inc sp_t4
	bra _suchen
_letzter
	iny                         ; Wert des Punkts i
	iny
	lda [sp_hz],y
	bra _setzen
_zwischen
	#akku16                     ; Anteil = (Stelle - t1) * 256 / (t2 - t1)
	lda [sp_hz],y
	sta sp_t0
	dey
	dey
	dey
	dey
	lda [sp_hz],y
	sta sp_t1
	lda sp_t0
	sec
	sbc sp_t1
	sta sp_dd
	lda k_hpos,x
	sec
	sbc sp_t1
	xba
	pha
	and #$00ff
	sta sp_dh
	pla
	and #$ff00
	sta sp_dl
	jsr sp_teilen
	#akku8
	sta sp_t0                   ; Anteil 0-255
	iny
	iny
	lda [sp_hz],y               ; v1
	sta sp_t5
	iny
	iny
	iny
	iny
	lda [sp_hz],y               ; v2
	sec
	sbc sp_t5
	bcs _hoch
	eor #$ff                    ; abwaerts: v1 - |v2 - v1| * Anteil / 256
	inc a
	jsr sp_mal
	lda sp_t5
	sec
	sbc sp_t2+1
	bra _setzen
_hoch
	jsr sp_mal
	lda sp_t2+1
	clc
	adc sp_t5
_setzen
	cmp #65
	bcc +
	lda #64
+	sta k_hwert,x
	lda k_hflag,x               ; Sustain: halten, bis losgelassen
	and #2
	bne _frei
	lda [sp_hz]
	and #2
	beq _frei
	ldy #HK_SUS
	jsr sp_hk_tick
	.al
	cmp k_hpos,x
	#akku8
	beq _ausklingen
_frei
	lda [sp_hz]                 ; Schleife: am Ende zurueck zum Anfang
	and #4
	beq _weiter
	ldy #HK_LE
	jsr sp_hk_tick
	.al
	cmp k_hpos,x
	#akku8
	bne _weiter
	ldy #HK_LA
	jsr sp_hk_tick
	.al
	sta k_hpos,x
	#akku8
	bra _ausklingen
_weiter
	#akku16
	inc k_hpos,x
	#akku8
_ausklingen
	lda k_hflag,x
	and #2
	beq _r
	#akku16
	ldy #HK_AUS
	lda k_hfade,x
	sec
	sbc [sp_hz],y
	bcs +
	lda #0
+	sta k_hfade,x
	#akku8
_r	rts

; Tick des Punkts, dessen Nummer bei [sp_hz],Y steht -> A (Akku 16 danach)
sp_hk_tick
	.as
	lda [sp_hz],y
	#akku16
	and #$000f
	asl a
	asl a
	adc #HK_PUNKTE              ; (C ist nach asl 0: Punkt < 16)
	tay
	lda [sp_hz],y
	rts

; Sample des Instruments sp_hilf auf Kanal sp_reg starten (Versatz k_offset).
; Laenge und Schleife sind 24 Bit (Bits 16-23 in IN_LHI / IN_SHI).
sp_probe_an
	.as
	ldy sp_reg
	lda #0
	sta KAN+$b,y                ; erst anhalten
	#akku16
	ldy #IN_ANFANG
	lda [sp_hilf],y
	clc
	adc sp_chip
	sta sp_t0                   ; Anfang Bits 0-15
	#akku8
	ldy #IN_ANFANG+2
	lda [sp_hilf],y
	adc sp_chip+2
	sta sp_t1                   ; Bank
	ldy #IN_LHI
	lda [sp_hilf],y
	sta sp_lh
	#akku16
	ldy #IN_LAENGE
	lda [sp_hilf],y
	sta sp_t2                   ; Laenge sp_lh:sp_t2
	ldy #IN_SLAENGE
	lda [sp_hilf],y
	cmp #3
	bcc _keine
	sta sp_t5
	ldy #IN_SCHLEIFE
	lda [sp_hilf],y
	sta sp_t3                   ; Schleife ab sp_sh:sp_t3
	#akku8
	ldy #IN_SHI
	lda [sp_hilf],y
	sta sp_sh
	#akku16
	lda sp_t5
	cmp #$ffff
	beq _lang                   ; bis zum Ende
	clc                         ; Ende der Schleife = ab + Schleifenlaenge
	adc sp_t3
	sta sp_t5
	#akku8
	lda sp_sh
	adc #0
	sta sp_t4
	cmp sp_lh
	bcc _kuerzer
	bne _lang
	#akku16
	lda sp_t5
	cmp sp_t2
	bcs _lang
_kuerzer                        ; die Schleife endet vor dem Sample
	#akku16
	lda sp_t5
	sta sp_t2
	#akku8
	lda sp_t4
	sta sp_lh
_lang
	#akku8
	lda #3                      ; spielen mit Schleife
	bra _steuer
_keine
	#akku8
	stz sp_t3
	stz sp_t3+1
	stz sp_sh
	lda #1
_steuer
	sta sp_t4
	lda k_offset,x              ; 9xx: Versatz in Seiten
	beq _schreiben
	sta sp_t5+1
	stz sp_t5
	lda sp_lh
	bne +
	#akku16
	lda sp_t5
	cmp sp_t2
	#akku8
	bcc +
	rts                         ; hinter dem Ende: still
+	#akku16                     ; Anfang weiter, Laenge und Schleife kuerzer
	lda sp_t0
	clc
	adc sp_t5
	sta sp_t0
	#akku8
	lda sp_t1
	adc #0
	sta sp_t1
	#akku16
	lda sp_t2
	sec
	sbc sp_t5
	sta sp_t2
	#akku8
	lda sp_lh
	sbc #0
	sta sp_lh
	#akku16
	lda sp_t3
	sec
	sbc sp_t5
	sta sp_t3
	#akku8
	lda sp_sh
	sbc #0
	sta sp_sh
	bcs _schreiben
	stz sp_sh
	stz sp_t3
	stz sp_t3+1
_schreiben
	#akku16
	lda sp_reg                  ; Anfang je Samplekanal 0-3 merken (Oszilloskope).
	cmp #KAN2                   ; Die Kanaele 4-7 der SYN-Spuren zeigt KLANG nicht -
	bcs _ohne_oszi              ; ihr Index laege mitten in k_vol und k_per
	phx
	lsr a
	lsr a
	lsr a
	tax
	lda sp_t0
	sta s_adr,x
	#akku8
	lda sp_t1
	sta s_bank,x
	#akku16
	plx
_ohne_oszi
	ldy sp_reg
	lda sp_t0
	sta KAN+0,y
	lda sp_t2
	sta KAN+3,y                 ; LAENGE
	lda sp_t3
	sta KAN+5,y                 ; SCHLEIFE
	#akku8
	lda sp_t1
	sta KAN+2,y
	lda sp_lh                   ; Bits 16-23 erst nach +3/+5 (die loeschen sie)
	sta KAN+$e,y
	lda sp_sh
	sta KAN+$f,y
	lda sp_t4
	sta KAN+$b,y                ; los
	rts

	.include "perioden.inc"

	.dpage 0
