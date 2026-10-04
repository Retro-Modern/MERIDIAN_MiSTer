#!/usr/bin/env python3
"""Passt das uebersetzte BASIC (m6502.s, Apple-Variante) an MERIDIAN an.

Jede Anpassung ersetzt einen Textblock, der genau einmal vorkommen muss -
so faellt sofort auf, wenn sich der Uebersetzer aendert.

    python3 anpassen.py m6502.s basic.s
"""
import sys

ANPASSUNGEN = [
    ("Zeileneingabe ueber den Bildschirmeditor des Kerns (statt Apple GETLN)",
     """INLIN:
	ldx #$80	;NO PROMPT CHARACTER
	stx CQPRMP
	jsr CQINLN	;GET A LINE ONTO PAGE 2
	cpx #BUFLEN-1
	bcs GDBUFS	;NOT TOO MANY CHARACTERS
	ldx #BUFLEN-1
GDBUFS:
	lda #0	;PUT A ZERO AT THE END
	sta BUF,x
	txa
	beq NOCHR
LOPBHT:
	lda BUF-1,x
	and #$7f
	sta BUF-1,x
	dex
	bne LOPBHT
NOCHR:""",
     """INLIN:
	lda #0	;MERIDIAN: Befehle in Grossbuchstaben
INLIN2:
	jsr K_ZEILE	;MERIDIAN: Zeile nach BUF, mit 0 abgeschlossen
NOCHR:"""),

    ("Antworten auf INPUT bleiben, wie sie getippt wurden",
     "GINLIN:\n"
     "\tjmp INLIN",
     "GINLIN:\n"
     "\tlda #1\n"
     "\tjmp INLIN2"),

    ("Taste ohne Apple-Hochbit",
     """	jsr CQINCH	;FD0C FOR APPLE COMPUTER.
	and #$7f""",
     """	jsr K_GETIN	;MERIDIAN: Taste holen (0 = keine)"""),

    ("Esc bricht ab (statt Strg-C von der Apple-Tastatur bei $C000)",
     """ISCNTC:
	lda $c000	;CHECK THE CHARACTER
	cmp #$83
	beq ISCCAP
	rts
ISCCAP:
	jsr INCHR
	cmp #$83""",
     """ISCNTC:
	jsr K_STOPP	;MERIDIAN: A = 3, wenn Esc gedrueckt wurde
	cmp #3
	beq ISCCAP
	rts
ISCCAP:
	cmp #3	;Z und C gesetzt: STOP"""),

    ("Ausgabe ohne Apple-Hochbit (MERIDIAN braucht Bit 7 fuer Umlaute)",
     """	ora #$80
;TURN ON B7 FOR APPLE.

OUTLOC:
	jsr OUTCH
;OUTPUT THE CHARACTER.
;GET Y BACK.
	and #$7f
;GET [A] BACK FROM APPLE.""",
     """OUTLOC:
	jsr K_CHROUT	;MERIDIAN: Zeichen ausgeben"""),

    ("GET wartet nicht (wie beim C64): keine Taste = leere Zeichenkette",
     """	jsr CZGETL	;DON'T WANT INCHR. JUST ONE.

	and #$7f
	sta BUF	;MAKE IT FIRST CHARACTER.""",
     """	jsr K_GETIN	;MERIDIAN: wartet nicht
	sta BUF	;MAKE IT FIRST CHARACTER.
	lda #0
	sta BUF+1"""),

    ("GET springt immer weiter (A kann jetzt 0 sein)",
     """;BNEA DATBK
	bne DATBK""",
     """;BNEA DATBK
	jmp DATBK	;MERIDIAN: immer"""),

    ("SAVE in den Zusatzspeicher statt auf Kassette",
     """	jsr VARTIO
	jsr CQCOUT	;WRITE PROGRAM SIZE [POKER]
	jsr PROGIO
	jmp CQCOUT	;WRITE PROGRAM.""",
     """	jmp M_SAVE	;MERIDIAN: Programm nach Bank $10"""),

    ("LOAD aus dem Zusatzspeicher",
     """LOAD:
	jsr VARTIO
	jsr CQCSIN	;READ SIZE OF PROGRAM INTO POKER""",
     """LOAD:
	jsr M_LOAD	;MERIDIAN: Laenge nach POKER, Programm zurueck"""),

    ("LOAD liest das Programm schon in M_LOAD",
     """	jsr PROGIO
	jsr CQCSIN	;READ PROGRAM.""",
     """	;MERIDIAN: Programm steht schon im Speicher"""),

    ("Keine Fragen nach Speichergroesse und Zeilenbreite: der Speicher endet vor dem BASIC-Code",
     """	lda #[[MEMORY]&$ff]
	ldy #[[MEMORY]/$100]
	jsr STROUT
	jsr QINLIN	;GET A LINE OF INPUT.""",
     """	jmp M_SPEICHER	;MERIDIAN: Speicher bis ROMLOC, keine Fragen
	jsr QINLIN	;GET A LINE OF INPUT."""),

    ("READY. wie beim C64 und bei MERIDIAN (statt OK)",
     """REDDY:
;ACRLF

	.byte $d
	.byte $a

	.byte $4f, $4b""",
     """REDDY:
	.byte $d
	.byte $a
	.text "READY.\""""),

    ("Begruessung",
     """	.byte $41, $50, $50, $4c, $45, $20, $42, $41, $53, $49, $43, $20, $56, $31, $2e, $31""",
     """	.text "MERIDIAN 816 BASIC V1.1\""""),

    # Microsoft durchsucht die Schluesselwortliste mit einem 8-Bit-Index:
    # mehr als 256 Bytes gehen nicht. Die MERIDIAN-Befehle stehen deshalb in
    # einer eigenen Liste (meridian.s) mit den Token nach GO.
    ("Eigene Schluesselwortliste nach dem Ende der Microsoft-Liste",
     "\tlda RESLST,y\t;YES. IS IT THE END?\n"
     "\tbne RESCON\t;NO, TRY THE NEXT WORD.\n"
     "\tlda BUFOFS,x\t;YES, END OF TABLE. GET 1ST CHR.\n"
     "\tbpl GETBPT\t;STORE IT AWAY (ALWAYS BRANCHES).",
     "\tlda RESLST,y\t;YES. IS IT THE END?\n"
     "\tbne RESCON\t;NO, TRY THE NEXT WORD.\n"
     "\tjmp M_SUCHE\t;MERIDIAN: weiter in der eigenen Liste"),

    ("Eigene Befehle ausfuehren (Token nach GO)",
     "SNERRX:\n"
     "\tcmp #GOTK-ENDTK\n"
     "\tbne SNERR1",
     "SNERRX:\n"
     "\tcmp #GOTK-ENDTK+1\n"
     "\tbcc *+5\n"
     "\tjmp M_GONE\t;MERIDIAN-Befehl\n"
     "\tcmp #GOTK-ENDTK\n"
     "\tbne SNERR1"),

    ("GO ist keine Funktion; eigene Token: M_FUNKTION (Etappe 11)",
     "\tcmp #ONEFUN\t;A FUNCTION NAME?\n"
     "\tbcc PARCHK\t;FUNCTIONS ARE THE HIGHEST NUMBERED\n"
     "\tjmp ISFUN\t;CHARACTERS SO NO NEED TO CHECK",
     "\tcmp #ONEFUN\t;A FUNCTION NAME?\n"
     "\tbcc PARCHK\n"
     "\tcmp #GOTK\n"
     "\tbcc *+5\n"
     "\tjmp M_FUNKTION\n"
     "\tjmp ISFUN"),

    ("LIST: eigene Befehle, Umlaute in Anfuehrungszeichen und nach REM",
     "QPLOP:\n"
     "\tbpl PLOOP\t;NO, HEAD FOR PRINTER.",
     "QPLOP:\n"
     "\tjmp M_QPLOP\n"
     "QPLOP2:"),

    ("LIST: jede Zeile beginnt ausserhalb von Anfuehrungszeichen",
     "\tjsr LINPRT\t;PRINT AS INT WITHOUT LEADING SPACE.\n"
     "\tlda #32\t;ALWAYS PRINT SPACE AFTER NUMBER.",
     "\tjsr LINPRT\t;PRINT AS INT WITHOUT LEADING SPACE.\n"
     "\tlda #0\n"
     "\tsta M_ROH\n"
     "\tlda #32\t;ALWAYS PRINT SPACE AFTER NUMBER."),
    # Etappe 13: gleich beim Umbruch auf 0, nicht erst beim naechsten Zeichen -
    # sonst hielt PRINT eine Zahl hinter einer genau vollen Zeile fuer zu lang
    # und schickte ein zusaetzliches Zeilenende (Leerzeile)
    ("Umbruch macht der Kern (logische Zeilen) - BASIC zaehlt nur die Spalte neu",
     "\tlda TRMPOS\n"
     "\tcmp LINWID\t;LENGTH = TERMINAL WIDTH?\n"
     "\tbne OUTDO1\n"
     "\tjsr CRDO\t;YES, TYPE CRLF\n"
     "OUTDO1:\n"
     "INCTRM:\n"
     "\tinc TRMPOS\t;INCREMENT COUNT.",
     "OUTDO1:\n"
     "INCTRM:\n"
     "\tinc TRMPOS\t;INCREMENT COUNT.\n"
     "\tlda TRMPOS\t;MERIDIAN: Zeile voll - der Kern bricht um, BASIC zaehlt ab 0\n"
     "\tcmp LINWID\n"
     "\tbne TRYOUT\n"
     "\tlda #0\n"
     "\tsta TRMPOS"),

    ("Nach LOAD: READY. wie beim C64",
     "\tjsr STROUT\n"
     "\tjmp FINI\n"
     "\n"
     "TPDONE:",
     "\tjsr STROUT\n"
     "\tjsr RUNC\n"
     "\tjsr LNKPRG\n"
     "\tjmp READY\n"
     "\n"
     "TPDONE:"),
    # PEEK, POKE und WAIT mit 24-Bit-Adressen ueber einen langen Zeiger:
    # unabhaengig von BASICs Datenbank, Adressen unter 65536 meinen Bank 0.
    ("PEEK: 24-Bit-Adresse",
     "\tjsr GETADR\n"
     "\tldy #0\n"
     ";GIVE HIM ZERO FOR AN ANSWER.\n"
     "GETCON:\n"
     "\tlda (POKER),y\t;GET THAT BYTE.",
     "\tjsr M_ADR24\n"
     "\tldy #0\n"
     "GETCON:\n"
     "\tlda [LZ],y\t;MERIDIAN: langer Zeiger"),

    ("POKE: 24-Bit-Adresse",
     "POKE:\n"
     "\tjsr GETNUM\n"
     "\ttxa\n"
     "\tldy #0\n"
     "\tsta (POKER),y\t;STORE VALUE AWAY.",
     "POKE:\n"
     "\tjsr M_GETNUM\n"
     "\ttxa\n"
     "\tldy #0\n"
     "\tsta [LZ],y\t;MERIDIAN: langer Zeiger"),

    ("WAIT: 24-Bit-Adresse",
     "FNWAIT:\n"
     "\tjsr GETNUM",
     "FNWAIT:\n"
     "\tjsr M_GETNUM"),

    ("WAIT: langer Zeiger",
     "WAITER:\n"
     "\tlda (POKER),y",
     "WAITER:\n"
     "\tlda [LZ],y"),

    ("IF falsch: nach ELSE suchen (Etappe 13)",
     "\tlda FACEXP\t;0=FALSE. ALL OTHERS TRUE.\n"
     "\tbne DOCOND\t;TRUE !\n"
     "REM:",
     "\tlda FACEXP\t;0=FALSE. ALL OTHERS TRUE.\n"
     "\tbne DOCOND\t;TRUE !\n"
     "\tjmp M_WENN_NEIN\t;MERIDIAN: ELSE suchen\n"
     "REM:"),

    ("FNDFOR geht ueber WHILE- und REPEAT-Rahmen hinweg (Etappe 13)",
     "\tcmp #FORTK\t;IS IT A \"FOR\" TOKEN?\n"
     "\tbne FFRTS\t;NO, NO \"FOR\" LOOPS WITH THIS PNTR.",
     "\tcmp #FORTK\t;IS IT A \"FOR\" TOKEN?\n"
     "\tbeq *+5\n"
     "\tjmp M_FFANDERE\t;MERIDIAN: WHILE/REPEAT ueberspringen"),

    ("FRE ohne Vorzeichen (mehr als 32767 Bytes frei)",
     "\tlda FRETOP+1\n"
     "\tsbc STREND+1\n"
     "\n"
     "GIVAYF:",
     "\tlda FRETOP+1\n"
     "\tsbc STREND+1\n"
     "\tjmp M_FREI\n"
     "\n"
     "GIVAYF:"),
]


def main():
    text = open(sys.argv[1], encoding="latin-1").read()
    for titel, alt, neu in ANPASSUNGEN:
        n = text.count(alt)
        if n != 1:
            sys.exit(f"Anpassung '{titel}': Ausgangstext {n}-mal gefunden")
        text = text.replace(alt, f";--- MERIDIAN: {titel}\n{neu}")
    open(sys.argv[2], "w", encoding="latin-1").write(text)
    print(f"{len(ANPASSUNGEN)} Anpassungen")


if __name__ == "__main__":
    main()
