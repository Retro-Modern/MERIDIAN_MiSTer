#!/usr/bin/env python3
"""Uebersetzt Microsofts BASIC M6502 (MACRO-10-Quelle von 1978) nach 64tass.

Die Originalquelle wurde mit dem PDP-10-Assembler MACRO-10 und einer
Makrodatei M6502.UNV ueber Kreuz assembliert. Diese Makrodatei fehlt in der
Freigabe; ihre Schreibweisen ergeben sich aus dem Gebrauch:

    LDAI x      LDA #x           (Endung I: unmittelbar)
    LDADY x     LDA (x),Y        (Endung DY: indirekt indiziert)
    JMPD x      JMP (x)
    LSR A,      LSR A            (Akku)
    ADR(x)      zwei Byte Adresse
    DC"ABC"     Text, beim letzten Zeichen Bit 7 gesetzt
    XWD 1000,n  ein Byte n (SKIP1/SKIP2: der BIT-Trick)
    EXP a,b     Bytes
    BLOCK n     n Bytes Platz

Der Uebersetzer wertet Schalter und Bedingungen (IFE, IFN, ...) aus, setzt
Makros ein und schreibt 64tass-Quelltext mit allen Original-Kommentaren.
MACRO-10 unterscheidet nur die ersten sechs Zeichen eines Namens - so auch
hier.

    python3 m10.py m6502.asm einstellungen.txt > basic.s
"""
import re
import sys

# Mnemonics mit Endung I (unmittelbar) bzw. DY ((zp),Y)
IMM = {"LDA", "LDX", "LDY", "CMP", "CPX", "CPY", "ADC", "SBC", "AND", "ORA", "EOR"}
INDY = {"LDA", "STA", "CMP", "ADC", "SBC", "AND", "ORA", "EOR"}
OPCODES = set("""ADC AND ASL BCC BCS BEQ BIT BMI BNE BPL BRK BVC BVS CLC CLD CLI CLV CMP
CPX CPY DEC DEX DEY EOR INC INX INY JMP JSR LDA LDX LDY LSR NOP ORA PHA PHP PLA PLP ROL
ROR RTI RTS SBC SEC SED SEI STA STX STY TAX TAY TSX TXA TXS TYA""".split())
IGNORIEREN = {"TITLE", "SEARCH", "SALL", "SUBTTL", "PAGE", "LIST", "XLIST", "PRINTX",
              "LALL", "XALL", "TJSR", ".CREF", ".XCREF"}


class Fehler(Exception):
    pass


def name6(n):
    """MACRO-10 kennt sechs Zeichen; 64tass-taugliche Schreibweise"""
    n = n.upper()[:6]
    return n.replace("$", "S_").replace("%", "P_").replace(".", "D_")


class Uebersetzer:
    def __init__(self, vorgaben, orgs=None):
        self.orgs = orgs or {}          # ORG-Wert -> neuer Wert (None = weglassen)
        self.sym = {}                   # bekannte Zahlenwerte (fuer Bedingungen)
        self.makros = {}                # Name -> (Parameter, Rumpf)
        self.radix = 10
        self.aus = []                   # Ausgabezeilen
        self.lokal = 0
        self.vorgaben = vorgaben        # Name -> Wert, ueberschreibt die Quelle
        self.fest = set(vorgaben)
        self.zaehler = {}               # Name -> Anzahl Zuweisungen (1. Durchgang)
        self.mehrfach = set()           # im 2. Durchgang: als Variable (:=)
        self.fest_gesetzt = set()
        self.marken = set()

    # ---------------------------------------------------------- Zerlegen
    @staticmethod
    def spitz(zeile):
        """Saldo der spitzen Klammern ausserhalb von Kommentar und Text"""
        tiefe, im_text = 0, False
        for c in zeile:
            if im_text:
                if c == '"':
                    im_text = False
                continue
            if c == '"':
                im_text = True
            elif c == ";":
                break
            elif c == "<":
                tiefe += 1
            elif c == ">":
                tiefe -= 1
        return tiefe

    def anweisungen(self, text):
        """Text -> Anweisungen (mehrzeilig, solange eine < offen ist)"""
        zeilen = text.split("\n")
        i = 0
        while i < len(zeilen):
            z = zeilen[i]
            if re.match(r"^\s*COMMENT\s+(\S)", z):           # COMMENT x ... x
                trenn = re.match(r"^\s*COMMENT\s+(\S)", z).group(1)
                rest = z.split(trenn, 1)[1] if z.count(trenn) > 0 else ""
                i += 1
                if trenn not in rest:
                    while i < len(zeilen) and trenn not in zeilen[i]:
                        i += 1
                    i += 1
                continue
            tiefe = self.spitz(z)
            j = i
            while tiefe > 0 and j + 1 < len(zeilen):
                j += 1
                z += "\n" + zeilen[j]
                tiefe += self.spitz(zeilen[j])
            yield z
            i = j + 1

    @staticmethod
    def kommentar(s):
        """trennt den Kommentar ab (ausserhalb von Text und Klammern)"""
        im_text, tiefe = False, 0
        for k, c in enumerate(s):
            if im_text:
                if c == '"':
                    im_text = False
                continue
            if c == '"':
                im_text = True
            elif c == "<":
                tiefe += 1
            elif c == ">":
                tiefe -= 1
            elif c == ";" and tiefe <= 0:
                return s[:k], s[k + 1:]
        return s, None

    @staticmethod
    def klammer_ende(s, start):
        """Index der passenden > zu s[start] == '<'"""
        tiefe, im_text = 0, False
        k = start
        while k < len(s):
            c = s[k]
            if im_text:
                if c == '"':
                    im_text = False
            elif c == '"':
                im_text = True
            elif c == ";":
                k = s.find("\n", k)
                if k < 0:
                    break
                continue
            elif c == "<":
                tiefe += 1
            elif c == ">":
                tiefe -= 1
                if tiefe == 0:
                    return k
            k += 1
        raise Fehler("keine passende > in: " + s[start:start + 60])

    @staticmethod
    def teile_komma(s):
        """am ersten Komma auf oberster Ebene teilen"""
        tiefe = 0
        for k, c in enumerate(s):
            if c == "<":
                tiefe += 1
            elif c == ">":
                tiefe -= 1
            elif c == "," and tiefe == 0:
                return s[:k], s[k + 1:]
        return s, None

    # ---------------------------------------------------------- Ausdruecke
    def tokens(self, e):
        return re.findall(r'\^[OBD][0-9]+|"[^"]"|[A-Z0-9$%.]+|[-+*/&!<>()]', e.upper().replace("\t", " "))

    def zahl(self, t, radix):
        if t.startswith("^O"):
            return int(t[2:], 8)
        if t.startswith("^D"):
            return int(t[2:], 10)
        if t.startswith("^B"):
            return int(t[2:], 2)
        if t.endswith(".") and t[:-1].isdigit():
            return int(t[:-1], 10)
        # wie MACRO-10: Ziffer fuer Ziffer, ohne Pruefung gegen die Basis
        # ("8*ADDPRC+230" im Oktalbereich ist 8 + 152)
        v = 0
        for c in t:
            v = v * radix + int(c)
        return v

    def wert(self, e):
        """Ausdruck jetzt berechnen (fuer Bedingungen); None wenn unbekannt"""
        py = []
        for t in self.tokens(e):
            if t[0].isdigit() or t[0] == "^":
                py.append(str(self.zahl(t, self.radix)))
            elif t.startswith('"'):
                py.append(str(ord(t[1])))
            elif t == "<":
                py.append("(")
            elif t == ">":
                py.append(")")
            elif t == "!":
                py.append("|")
            elif t == "/":
                py.append("//")
            elif t in "+-*&()":
                py.append(t)
            else:
                n = name6(t)
                if n not in self.sym:
                    return None
                py.append(str(self.sym[n]))
        if not py:
            return 0
        try:
            return int(eval(" ".join(py)))
        except Exception:
            return None

    def ausdruck(self, e):
        """Ausdruck in 64tass-Schreibweise"""
        aus = []
        for t in self.tokens(e):
            if t[0].isdigit() or t[0] == "^":
                v = self.zahl(t, self.radix)
                aus.append(str(v) if v < 10 else f"${v:x}")
            elif t.startswith('"'):
                aus.append(str(ord(t[1])))
            elif t == "<":
                aus.append("[")                 # 64tass: ( ) hiesse indirekt
            elif t == ">":
                aus.append("]")
            elif t == "!":
                aus.append("|")
            elif t == ".":
                aus.append("*")
            elif t in "+-*/&()":
                aus.append(t)
            else:
                aus.append(name6(t))
        return self.entklammern("".join(aus))

    @staticmethod
    def entklammern(a):
        """doppelte Klammern [[x]] -> [x]; 64tass liest sie sonst als Liste"""
        while True:
            paare, stapel = {}, []
            for k, c in enumerate(a):
                if c == "[":
                    stapel.append(k)
                elif c == "]":
                    paare[stapel.pop()] = k
            weg = None
            for i, j in paare.items():
                if a[i + 1:i + 2] == "[" and paare.get(i + 1) == j - 1:
                    weg = (i, j)
                    break
            if not weg:
                return a
            i, j = weg
            a = a[:i] + a[i + 1:j] + a[j + 1:]

    # ---------------------------------------------------------- Ausgabe
    def emit(self, marke, befehl, kommentar):
        z = ""
        if marke:
            z = marke
        if befehl:
            z += "\t" + befehl if marke else "\t" + befehl
        if kommentar is not None:
            z = (z + "\t" if z else "") + ";" + kommentar.rstrip()
        self.aus.append(z)

    def text_bytes(self, s, hoch):
        b = [ord(c) for c in s]
        if hoch and b:
            b[-1] |= 0x80
        return ", ".join(f"${v:02x}" for v in b)

    # ---------------------------------------------------------- Verarbeitung
    def verarbeite(self, text):
        for anw in self.anweisungen(text):
            self.anweisung(anw)

    def anweisung(self, s):
        roh, kom = self.kommentar(s)
        roh = roh.rstrip()
        if not roh.strip():
            self.emit(None, None, kom)
            return
        # Marken
        marke = None
        m = re.match(r"^\s*([A-Z0-9$%.]+)::?!?", roh, re.I)
        if m and not re.match(r"^\s*([A-Z0-9$%.]+)\s*==?", roh, re.I):
            marke = name6(m.group(1))
            self.marken.add(marke)
            roh = roh[m.end():]
            if marke in self.sym:
                pass
        rest = roh.strip()
        if not rest:
            self.emit(marke + ":", None, kom)
            return
        if marke:
            self.emit(marke + ":", None, None)
        self.befehl(rest, kom)

    def befehl(self, rest, kom):
        m = re.match(r"^([A-Z0-9$%.]+)\s*(==?|=:)\s*(.*)$", rest, re.I | re.S)
        if m:                                           # Zuweisung
            n = name6(m.group(1))
            if n in self.fest:
                v = self.vorgaben[n]
                self.sym[n] = v
                if n in self.fest_gesetzt:
                    self.emit(None, None, f"{n} bleibt {v} (Vorgabe MERIDIAN)")
                else:
                    self.fest_gesetzt.add(n)
                    self.emit(f"{n} = ${v:x}", None, (kom or "") + " (Vorgabe MERIDIAN)")
                return
            self.zaehler[n] = self.zaehler.get(n, 0) + 1
            v = self.wert(m.group(3))
            if v is not None:
                self.sym[n] = v
            else:
                self.sym.pop(n, None)
            op = ":=" if n in self.mehrfach else "="
            self.emit(f"{n} {op} {self.ausdruck(m.group(3))}", None, kom)
            return
        m = re.match(r"^([A-Z0-9$%.]+)\s*(.*)$", rest, re.I | re.S)
        if not m:                                       # etwa ^O200 oder "A": ein Byte
            return self.emit(None, f".byte {self.ausdruck(rest)}", kom)
        wort = m.group(1).upper()
        arg = m.group(2)

        if wort in ("IFE", "IFN", "IFG", "IFL", "IFGE", "IFLE", "IF1", "IF2", "IFDEF", "IFNDEF", "IFDIF", "IFIDN"):
            return self.bedingung(wort, arg, kom)
        if wort == "DEFINE":
            return self.definiere(arg, kom)
        if wort == "REPEAT":
            n, rumpf = self.teile_komma(arg)
            k = rumpf.index("<")
            inhalt = rumpf[k + 1:self.klammer_ende(rumpf, k)]
            for _ in range(self.wert(n)):
                self.verarbeite(inhalt)
            return
        if wort == "RADIX":
            self.radix = int(arg.strip())
            self.emit(None, None, f"RADIX {self.radix}" + (f"  ;{kom}" if kom else ""))
            return
        if wort in IGNORIEREN:
            self.emit(None, None, f"{wort} {arg.strip()}".rstrip())
            return
        if wort == "END":
            self.emit(None, None, "END " + arg.strip())
            return
        if wort == "ORG":
            v = self.wert(arg)
            if v in self.orgs:
                neu = self.orgs[v]
                if neu is None:
                    self.emit(None, None, f"ORG {arg.strip()} entfaellt (MERIDIAN)" + (f"  ;{kom}" if kom else ""))
                else:
                    self.emit(None, f"* = ${neu:x}", (kom or "") + f" (statt ORG {arg.strip()}, MERIDIAN)")
                return
            self.emit(None, f"* = {self.ausdruck(arg)}", kom)
            return
        if wort == "BLOCK":
            self.emit(None, f".fill {self.ausdruck(arg)}", kom)
            return
        if wort == "EXP":
            teile = [t for t in re.split(r",", arg) if t.strip()]
            self.emit(None, ".byte " + ", ".join(self.ausdruck(t) for t in teile), kom)
            return
        if wort == "XWD":
            a, b = self.teile_komma(arg)
            self.emit(None, f".byte {self.ausdruck(b)}", (kom or "") + f" (XWD {a.strip()},{b.strip()})")
            return
        if wort == "ADR":
            self.emit(None, f".word {self.ausdruck(arg.strip()[1:-1])}", kom)
            return
        if wort in ("DT", "DC"):
            t = re.match(r'^\s*"([^"]*)"', arg) or re.match(r'^\s*\(\s*"([^"]*)"\s*\)', arg)
            if not t:
                raise Fehler("Text erwartet: " + rest)
            self.emit(None, ".byte " + self.text_bytes(t.group(1), wort == "DC"), kom)
            return
        if wort == "IRPC":
            raise Fehler("IRPC nur in DT erwartet")
        if wort in self.makros:
            return self.makro(wort, arg, kom)
        return self.instruktion(wort, arg, kom, rest)

    def bedingung(self, wort, arg, kom):
        if wort in ("IF1", "IF2"):
            ausdr, rumpf = None, arg.lstrip(",")
            gilt = wort == "IF1"                      # einmal genuegt
            gilt = False                              # Meldungen (PRINTX) unterdruecken
        elif wort in ("IFDEF", "IFNDEF"):
            ausdr, rumpf = self.teile_komma(arg)
            n = name6(ausdr.strip())
            gilt = (n in self.sym or n in self.marken) == (wort == "IFDEF")
        elif wort in ("IFDIF", "IFIDN"):
            raise Fehler("IFDIF/IFIDN nicht unterstuetzt: " + arg[:40])
        else:
            ausdr, rumpf = self.teile_komma(arg)
            v = self.wert(ausdr)
            if v is None:
                raise Fehler(f"Bedingung nicht berechenbar: {wort} {ausdr}")
            gilt = {"IFE": v == 0, "IFN": v != 0, "IFG": v > 0, "IFL": v < 0,
                    "IFGE": v >= 0, "IFLE": v <= 0}[wort]
        k = rumpf.index("<")
        e = self.klammer_ende(rumpf, k)
        inhalt = rumpf[k + 1:e]
        danach = rumpf[e + 1:]
        if gilt:
            self.verarbeite(inhalt)
        if danach.strip() or kom:
            self.emit(None, None, (danach.strip() + " " if danach.strip() else "") + (kom or ""))

    def definiere(self, arg, kom):
        m = re.match(r"^\s*([A-Z0-9$%.]+)\s*(\(([^)]*)\))?\s*,", arg, re.I)
        name = m.group(1).upper()
        params = [p.strip().upper() for p in (m.group(3) or "").split(",") if p.strip()]
        rest = arg[m.end():]
        k = rest.index("<")
        rumpf = rest[k + 1:self.klammer_ende(rest, k)]
        if name in ("DT",):                          # eingebaut
            return
        self.makros[name] = (params, rumpf)
        self.emit(None, None, f"Makro {name}({','.join(params)})" + (f" ;{kom}" if kom else ""))

    def makro(self, name, arg, kom):
        params, rumpf = self.makros[name]
        arg = arg.strip()
        if arg.startswith("(") and arg.endswith(")"):
            arg = arg[1:-1]
        werte = []
        if params:
            tiefe, akt = 0, ""
            for c in arg:
                if c == "<":
                    tiefe += 1
                elif c == ">":
                    tiefe -= 1
                if c == "," and tiefe == 0 and len(werte) < len(params) - 1:
                    werte.append(akt)
                    akt = ""
                else:
                    akt += c
            werte.append(akt)
        text = rumpf
        for p, w in zip(params, werte):
            text = re.sub(r"(?<![A-Z0-9$%.])" + re.escape(p) + r"(?![A-Z0-9$%.])", w.strip(), text)
        # lokale Marken %Q
        if "%" in text:
            self.lokal += 1
            text = re.sub(r"%([A-Z0-9]+)", lambda m: f"L{self.lokal}{m.group(1)}", text)
        self.emit(None, None, f"{name} {arg}" + (f"  ;{kom}" if kom else ""))
        self.verarbeite(text)

    def operand(self, e):
        a = self.ausdruck(e)
        return "0+" + a if a.startswith("[") else a

    def instruktion(self, wort, arg, kom, roh):
        a = arg.strip()
        if a.endswith(","):
            a = a[:-1].rstrip()
        if wort == "JMPD":
            return self.emit(None, f"jmp ({self.ausdruck(a)})", kom)
        if wort.endswith("DY") and wort[:-2] in INDY:
            return self.emit(None, f"{wort[:-2].lower()} ({self.ausdruck(a)}),y", kom)
        if wort.endswith("I") and wort[:-1] in IMM:
            return self.emit(None, f"{wort[:-1].lower()} #{self.ausdruck(a)}", kom)
        if wort in OPCODES:
            if not a:
                return self.emit(None, wort.lower(), kom)
            if a.upper() == "A":
                return self.emit(None, f"{wort.lower()} a", kom)
            m = re.match(r"^(.*),\s*([XY])$", a, re.I | re.S)
            if m:
                return self.emit(None, f"{wort.lower()} {self.operand(m.group(1))},{m.group(2).lower()}", kom)
            return self.emit(None, f"{wort.lower()} {self.operand(a)}", kom)
        # sonst: ein Byte (Zahl oder Ausdruck), etwa "LINWID: LINLEN"
        if re.match(r'^[-+<>A-Z0-9$%."^ \t*/&!()]+$', roh, re.I):
            return self.emit(None, f".byte {self.ausdruck(roh)}", kom)
        raise Fehler("unbekannt: " + roh[:60])


def main():
    quelle = open(sys.argv[1], encoding="latin-1").read().replace("\r", "")
    # DT ist eingebaut; die Original-Definition enthaelt ein einzelnes " und
    # ist mit unseren Mitteln nicht zu zerlegen
    quelle = quelle.replace('DEFINE\tDT(Q),<\nIRPC\tQ,<IFDIF <Q><">,<EXP "Q">>>', '; DT(Q): eingebaut')
    vorgaben, orgs = {}, {}
    if len(sys.argv) > 2:
        for z in open(sys.argv[2]):
            z = z.split("#")[0].strip()
            if not z:
                continue
            n, v = [t.strip() for t in z.split("=")]
            if n.upper().startswith("ORG "):
                orgs[int(n[4:], 0)] = None if v == "weg" else int(v, 0)
            else:
                vorgaben[name6(n)] = int(v, 0)
    try:
        erster = Uebersetzer(vorgaben, orgs)       # zaehlt Mehrfachzuweisungen
        erster.verarbeite(quelle)
        u = Uebersetzer(vorgaben, orgs)
        u.mehrfach = {n for n, k in erster.zaehler.items() if k > 1}
        u.verarbeite(quelle)
    except Fehler as f:
        sys.stderr.write(f"Fehler: {f}\n")
        sys.exit(1)
    print("\n".join(u.aus))


if __name__ == "__main__":
    main()
