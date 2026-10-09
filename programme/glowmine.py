#!/usr/bin/env python3
"""GLOWMINE - ein kleines Spiel aus der Werkstatt (MERIDIAN 1.0).

Zeigt, wie ein ganzes Spiel am Geraet entsteht: Sprites, Kacheln, zwei
Karten, Klaenge, Look und Zeichensatz liegen mit dem BASIC-Programm in einer
Datei. Die Daten male ich hier von Hand als Zeichenketten (Figuren nie aus
KI-Boegen), tools/cartridge.py setzt sie im Format von rom/ws_datei.asm
zusammen. In der Werkstatt (F1-F6) laesst sich danach alles ansehen und
aendern.

  glowmine.bas.vorlage  das BASIC-Programm mit Platzhaltern
  glowmine.bas          daraus erzeugt (Muenzen, Fledermaeuse als DATA)
  daten/glowmine.mws    die Cartridge; auf der Vorfuehrdiskette GLOWMINE.BAS

    python3 programme/glowmine.py [--bilder ordner]
"""
import argparse
import os
import sys

HIER = os.path.dirname(os.path.abspath(__file__))
BASIS = os.path.dirname(HIER)
sys.path.insert(0, os.path.join(BASIS, "tools"))
import bas                                  # noqa: E402
from cartridge import Cartridge             # noqa: E402

# ---------------------------------------------------------------------------
# Palettenbaenke (je 16 Farben, Wert 0 = durchsichtig). Wo es passt, nehme ich
# die Familien der Startpalette - dann sehen die Reiter SPRITES und TILES
# auch ohne LOOK fast richtig aus; LOOK feilt nach.
B_GLUT = 2      # 32-47 orange/gold: Lava, Muenzen, Laterne, Anzeige
B_HOLZ = 3      # 48-63 ocker/holz: Planken, Tuer
B_HERZ = 1      # 16-31 rot/karmin: Herzen
B_HOEHLE = 9    # 144-159 indigo/violett: Hoehlenwand hinten, Amethyst
B_FLEDER = 10   # 160-175 purpur/magenta: Fledermaus
B_STEIN = 12    # 192-207 warmgrau/sand: Fels vorn
B_KNAPPE = 13   # 208-223: der Bergmann (eigene Farben im Look)
B_PILZ = 14     # 224-239 mint/neonpink: leuchtende Pilze

# Legenden: Zeichen -> Wert in der Bank
L_STEIN = {"#": 8, "d": 9, "1": 1, "2": 2, "3": 3, "4": 4, "5": 5, "6": 6,
           "s": 11, "S": 12, "T": 13, "U": 14, "V": 15}
L_HOLZ = {"k": 8, "d": 9, "m": 10, "w": 11, "W": 12, "l": 13, "L": 14, "h": 15,
          "1": 1, "2": 2, "3": 3, "4": 4, "5": 5, "6": 6, "7": 7}
L_GLUT = {"1": 1, "2": 2, "3": 3, "4": 4, "5": 5, "6": 6, "7": 7,
          "a": 8, "b": 9, "c": 10, "d": 11, "e": 12, "f": 13, "g": 14, "h": 15}
L_HOEHLE = {"1": 1, "2": 2, "3": 3, "4": 4, "5": 5, "6": 6, "7": 7,
            "a": 8, "b": 9, "c": 10, "d": 11, "e": 12, "f": 13, "g": 14, "h": 15}
L_PILZ = {"1": 1, "2": 2, "3": 3, "4": 4, "5": 5, "6": 6, "7": 7,
          "a": 8, "b": 9, "c": 10, "d": 11, "e": 12, "f": 13, "g": 14, "h": 15}
L_KNAPPE = {"k": 1, "s": 2, "S": 3, "p": 4, "y": 5, "Y": 6, "h": 7, "L": 8,
            "b": 9, "B": 10, "c": 11, "o": 12, "O": 13, "w": 14, "r": 15}
L_FLEDER = {"1": 1, "2": 2, "3": 3, "4": 4, "5": 5, "6": 6, "7": 7,
            "a": 8, "b": 9, "c": 10, "d": 11, "e": 12, "f": 13, "g": 14, "h": 15}

# Kachelnummern - BASIC fragt sie mit TILE() ab (Tabelle Z() im Programm)
T_FELS = 1          # 1-16: Fels mit Kanten (N + 2 O + 4 S + 8 W offen), 17-18 innen
T_PLANKE = 32       # 32-34: Planke links, Mitte, rechts (von unten durchspringbar)
T_MUENZE = 40
T_LAVA = 41         # 41 Oberflaeche, 42 innen
T_TUER = 44         # 44-49 zu (2 x 3), 50-55 offen
T_DEKO = 64         # 64- Laterne, Kette, Pilze, Tropfstein, Balken
T_WAND = 128        # 128- hinten: Hoehlenwand, Saeulen, Amethyst

# ---------------------------------------------------------------------------
# Kacheln vorn: Fels


FELS_INNEN = [
    ["23342#32",
     "2333#433",
     "1222#332",
     "####1221",
     "3443211#",
     "3332221#",
     "2221211#",
     "#####1##"],
    ["#3442123",
     "#3332#33",
     "#2221#32",
     "1####221",
     "3442#433",
     "3332#332",
     "2221#221",
     "##1#####"],
    ["33421#34",
     "33321#33",
     "2221d#22",
     "#####112",
     "4321#344",
     "3321#333",
     "2211#222",
     "1####1##"],
]


def fels(innen, n, o, s, w):
    """Felskachel mit Kanten: oben Sandkruste im Licht, unten Schatten"""
    z = [list(r) for r in innen]
    if s:
        z[7] = list("########")
        z[6] = ["d" if c in "#1" else "1" for c in z[6]]
    if w:
        for y in range(8):
            z[y][0] = "#"
            if z[y][1] not in "#d":
                z[y][1] = "4" if y < 4 else "3"
    if o:
        for y in range(8):
            z[y][7] = "#"
            if z[y][6] not in "#d":
                z[y][6] = "2" if y > 2 else "3"
    if n:
        z[0] = list("TUVUUVUT")
        z[1] = list("STTSTTSS")
        z[2] = list("dsdssdsd")
        if w:
            z[0][0], z[1][0], z[2][0] = ".", "#", "#"
            z[0][1] = "#"
        if o:
            z[0][7], z[1][7], z[2][7] = ".", "#", "#"
            z[0][6] = "#"
    if s and w:
        z[7][0] = "."
    if s and o:
        z[7][7] = "."
    return ["".join(r) for r in z]


PLANKE = [
    ["#hLLhLLL",
     "#WlWWlWW",
     "#WWwWWWw",
     "#mmwmmmw",
     ".kkkkkkk",
     "..d.....",
     "........",
     "........"],
    ["hLLhLLLh",
     "WlWWlWWl",
     "WWwWWWwW",
     "mmwmmmwm",
     "kkkkkkkk",
     ".d....d.",
     "........",
     "........"],
    ["LLhLLLh#",
     "WlWWlWW#",
     "WwWWWwW#",
     "mwmmmwm#",
     "kkkkkkk.",
     ".....d..",
     "........",
     "........"],
]
PLANKE = [[r.replace("#", "k") for r in p] for p in PLANKE]

MUENZE = ["..cddc..",
          ".dfggfd.",
          "cfgeefec",
          "dgedcded",
          "dfedcdec",
          "cedddddb",
          ".bdeedb.",
          "..bccb.."]

LAVA_OBEN = ["....7...",
             "..6766..",
             ".675576.",
             "65544556",
             "54433445",
             "43333334",
             "33233323",
             "32223322"]
LAVA_INNEN = ["32322232",
              "22233222",
              "23222322",
              "21222212",
              "22212232",
              "12221222",
              "22122212",
              "11211121"]


def tuer(offen):
    """Ausgang 16 x 24: Balkenrahmen, zu mit Brettern und Schloss, offen mit Licht"""
    b = []
    b.append("kkkkkkkkkkkkkkkk")
    b.append("khLLhLLLLhLLLhLk")
    b.append("kWlWWWlWWWWlWWWk")
    b.append("kmmmmmmmmmmmmmmk")
    b.append("kkkkkkkkkkkkkkkk")
    for y in range(5, 24):
        links, rechts = "kLWk", "kWmk"
        if offen:
            # Licht: hell in der Mitte, zu den Raendern dunkler
            innen = ""
            for x in range(8):
                d = abs(x - 3.5) + max(0, 9 - y) * 0.35
                innen += "7" if d < 1.6 else "6" if d < 2.6 else "5" if d < 3.4 else "4"
        else:
            innen = ""
            for x in range(8):
                if y in (9, 18):
                    innen += "k"
                elif y in (10, 19):
                    innen += "d"
                elif x in (2, 5):
                    innen += "m"
                else:
                    innen += "W" if x % 3 == 0 else "w"
            if 12 <= y <= 15:          # Schloss
                schloss = {12: ".33.", 13: "3663", 14: "3773", 15: "3333"}[y]
                innen = innen[:2] + "".join(s if s != "." else innen[2 + i] for i, s in enumerate(schloss)) + innen[6:]
        b.append(links + innen + rechts)
    return b


LATERNE = ["...ab...",
           "..abba..",
           ".aaaaaa.",
           ".a5hg5a.",
           ".a6hh6a.",
           ".a5gg5a.",
           ".aaaaaa.",
           "...bb..."]
KETTE = ["...a....",
         "..a.a...",
         "...a....",
         "...b....",
         "...a....",
         "..a.a...",
         "...a....",
         "...b...."]
PILZ = [["........",
         "........",
         "..cddc..",
         ".cfhgec.",
         "cdeffedc",
         "..b45b..",
         "...56...",
         "..4565.."],
        ["........",
         "...ce...",
         "..dhgd..",
         "..cddc..",
         "...45..c",
         "...56.dg",
         "...56.b5",
         "..45664."]]
TROPFSTEIN = ["d2332d..",
              ".d232d..",
              ".d23d...",
              "..d2d...",
              "..d2d...",
              "...d....",
              "...d....",
              "........"]
TROPFSTEIN2 = [".d2432d.",
               "..d33d..",
               "..d32d..",
               "...d2d..",
               "...dd...",
               "........",
               "........",
               "........"]
BALKEN = ["..dWWd..",
          "..dWwd..",
          "..dWWd..",
          "..dlWd..",
          "..dWWd..",
          "..dWwd..",
          "..dWWd..",
          "..dmWd.."]

# ---------------------------------------------------------------------------
# Kacheln hinten: Hoehlenwand in Schichten, Saeulen, Amethyst

# Hoehlenwand: Felsbrocken um Mittelpunkte, die ich von Hand gesetzt habe;
# die Fugen liegen dort, wo zwei Brocken gleich nah sind. Das Stueck ist
# 32 x 16 Punkte (4 x 2 Kacheln) gross und schliesst ringsum an sich selbst an.
WAND_KERNE = [(3, 2), (11, 4), (19, 1), (27, 3), (6, 10), (15, 12), (23, 9), (30, 13), (1, 15)]


def wand():
    import math
    b, h = 32, 16

    def abstand(p, k):
        dx = min(abs(p[0] - k[0]), b - abs(p[0] - k[0]))
        dy = min(abs(p[1] - k[1]), h - abs(p[1] - k[1]))
        return math.hypot(dx * 0.8, dy * 1.15)
    bild = []
    for y in range(h):
        r = ""
        for x in range(b):
            ds = sorted((abstand((x, y), k), i) for i, k in enumerate(WAND_KERNE))
            (d1, i1), (d2, _i) = ds[0], ds[1]
            kx, ky = WAND_KERNE[i1]
            dx = (x - kx + b // 2) % b - b // 2
            dy = (y - ky + h // 2) % h - h // 2
            schraeg = dx + dy * 1.5                 # Licht von links oben
            if d2 - d1 < 0.9:
                r += "1"                            # Fuge
            elif d2 - d1 < 1.8:
                r += "2" if schraeg > 0 else "5" if dy < -1 else "4"
            else:
                r += "4" if schraeg < -2.5 else "2" if schraeg > 3 else "3"
        bild.append(r)
    return bild


WAND = wand()
# Saeule (2 breit), wiederholt sich senkrecht
SAEULE = [
    "1123455421112111",
    "1123455421211111",
    "1234554432111121",
    "1234554321111211",
    "1123455421111111",
    "1123445421121111",
    "1123454321111111",
    "1123455421111111",
]
AMETHYST = [
    "2222222322222222",
    "2333332222322232",
    "2222222222222221",
    "111111c111111111",
    "33322cfc2213e333",
    "3321cfgec21cfc32",
    "221cefhgc1cegc22",
    "11cdefhgdcdfgd11",
    "3cdefghfdcefgd33",
    "3cdefghfdcdefd32",
    "2bcdefgedcdefc22",
    "1bcdeffedbcdec11",
    "3bbcdeedcbbcdc33",
    "33bbcddcbbbccb32",
    "221bbbbbb1bbb122",
    "1111111111111111",
]


def stueck(bild, tx, ty):
    """8 x 8 aus einem groesseren Bild"""
    return [z[tx * 8:tx * 8 + 8] for z in bild[ty * 8:ty * 8 + 8]]


# ---------------------------------------------------------------------------
# Sprites (16 x 16, von Hand)

KNAPPE_STEHT = [
    "................",
    "......kkkkk.....",
    ".....kyYYhhk....",
    "....kyYYYYkLLk..",
    "....kyYYYYkLLk..",
    "...kyyyyyyyyyyk.",
    "...kkkkkkkkkkkk.",
    ".....kSSSSpwk...",
    ".....kSSSSSkSk..",
    ".....ksSSSSSSk..",
    "......kssssk....",
    ".....kBrrrBk....",
    "....krBBcBBrk...",
    "....kSkBBBkSk...",
    ".....kbBkBbk....",
    "....kOOk.kOOk...",
]
KNAPPE_GEHT1 = [
    "................",
    "......kkkkk.....",
    ".....kyYYhhk....",
    "....kyYYYYkLLk..",
    "....kyYYYYkLLk..",
    "...kyyyyyyyyyyk.",
    "...kkkkkkkkkkkk.",
    ".....kSSSSpwk...",
    ".....kSSSSSkSk..",
    ".....ksSSSSSSk..",
    "......kssssk....",
    ".....kBrrrBkk...",
    "....krBBcBBkSk..",
    "...kSkbBBBBkk...",
    "...kk.kbBk.kBk..",
    "......kOOk..kOOk",
]
KNAPPE_GEHT2 = [
    "................",
    "......kkkkk.....",
    ".....kyYYhhk....",
    "....kyYYYYkLLk..",
    "....kyYYYYkLLk..",
    "...kyyyyyyyyyyk.",
    "...kkkkkkkkkkkk.",
    ".....kSSSSpwk...",
    ".....kSSSSSkSk..",
    ".....ksSSSSSSk..",
    "......kssssk....",
    "....kkBrrrBk....",
    "...kSkBBcBBrk...",
    "....kkBBBBbkSk..",
    "....kBk.kbBkk...",
    "..kOOk...kOOk...",
]
KNAPPE_SPRINGT = [
    "......kkkkk.....",
    ".....kyYYhhk....",
    "....kyYYYYkLLk..",
    "....kyYYYYkLLk..",
    "...kyyyyyyyyyyk.",
    "...kkkkkkkkkkkk.",
    ".....kSSSSpwk...",
    ".....kSSSSSkSk..",
    "..kk.ksSSSSSSk..",
    ".kSk..kssssk.kk.",
    ".kSrkkBrrrBkkSk.",
    "..krBBBBcBBBrk..",
    "....kbBBBBBbk...",
    "...kbBBkkbBBk...",
    "..kOOkk..kOOk...",
    "..kkk.....kk....",
]
KNAPPE_FAELLT = [   # getroffen: Helm fliegt, Arme hoch
    "...kk......kk...",
    "..kSk......kSk..",
    "..kSk.kkkk.kSk..",
    "..krkkSSSSkkrk..",
    "...krkSSSSkrk...",
    "....kSwSSwSk....",
    "....kSkSSkSk....",
    "....kSSkkSSk....",
    ".....kSSSSk.....",
    ".....kBrrBk.....",
    "....kBBBBBBk....",
    "....kbBBcBbk....",
    ".....kBBBBk.....",
    ".....kBkkBk.....",
    "....kOOk.kOOk...",
    "....kkk...kkk...",
]

FLEDER_OBEN = [
    "................",
    ".22..........22.",
    ".342........243.",
    ".3542.1..1.2453.",
    ".35542411425553.",
    "..355443344553..",
    "..3544hd5h4453..",
    "...34445544433..",
    "....344444433...",
    ".....3444433....",
    "......3443......",
    ".......33.......",
    "................",
    "................",
    "................",
    "................",
]
FLEDER_UNTEN = [
    "................",
    "................",
    "................",
    "................",
    "......1..1......",
    "......4114......",
    ".....54hd5h4....",
    "...334445544433.",
    "..35544444445553",
    ".355543444435553",
    ".3543.344443.453",
    ".342...3443...24",
    ".32.....33....23",
    ".2.............2",
    "................",
    "................",
]

# Ziffern fuer die Anzeige: 8 x 8 aus dem eigenen Zeichensatz, oben hell
MUENZE_GROSS = [
    "................",
    "................",
    ".....bbbbbb.....",
    "....bdffffdb....",
    "...bfggggggfb...",
    "..bfgheeeegfdb..",
    "..dghedddedfdb..",
    "..dghdcccddfdb..",
    "..dgedcccddedb..",
    "..dgedccdddedb..",
    "..dfeddddddedb..",
    "..bdfeeeeeedcb..",
    "...bdffeefdcb...",
    "....bbddddbb....",
    ".....bbbbbb.....",
    "................",
]
HERZ = [
    "................",
    "................",
    "...cccc..cccc...",
    "..cfggec.ceeec..",
    ".cfhgeeeceeeedc.",
    ".cgheeeeeeeedcc.",
    ".cgeeeeeeeeedcc.",
    ".ceeeeeeeeeedcb.",
    "..ceeeeeeeedcb..",
    "...ceeeeeedcb...",
    "....ceeeedcb....",
    ".....ceedcb.....",
    "......cdcb......",
    ".......cb.......",
    "................",
    "................",
]

# ---------------------------------------------------------------------------
# Zeichensatz: Grossbuchstaben und Ziffern neu, kraeftig (2 Punkte Strich)

FONT = {
    "A": ["..####..", ".##..##.", "##....##", "##....##", "########", "##....##", "##....##", "........"],
    "B": ["######..", "##...##.", "##...##.", "######..", "##....##", "##....##", "#######.", "........"],
    "C": ["..#####.", ".##...##", "##......", "##......", "##......", ".##...##", "..#####.", "........"],
    "D": ["#####...", "##..##..", "##...##.", "##....##", "##....##", "##...##.", "######..", "........"],
    "E": ["#######.", "##......", "##......", "######..", "##......", "##......", "#######.", "........"],
    "F": ["#######.", "##......", "##......", "######..", "##......", "##......", "##......", "........"],
    "G": ["..#####.", ".##.....", "##......", "##..####", "##....##", ".##...##", "..######", "........"],
    "H": ["##....##", "##....##", "##....##", "########", "##....##", "##....##", "##....##", "........"],
    "I": ["######..", "..##....", "..##....", "..##....", "..##....", "..##....", "######..", "........"],
    "J": ["....####", ".....##.", ".....##.", ".....##.", "##...##.", "##...##.", ".#####..", "........"],
    "K": ["##...##.", "##..##..", "##.##...", "####....", "##.##...", "##..##..", "##...##.", "........"],
    "L": ["##......", "##......", "##......", "##......", "##......", "##......", "#######.", "........"],
    "M": ["##....##", "###..###", "########", "##.##.##", "##....##", "##....##", "##....##", "........"],
    "N": ["##....##", "###...##", "####..##", "##.##.##", "##..####", "##...###", "##....##", "........"],
    "O": ["..####..", ".##..##.", "##....##", "##....##", "##....##", ".##..##.", "..####..", "........"],
    "P": ["######..", "##...##.", "##...##.", "######..", "##......", "##......", "##......", "........"],
    "Q": ["..####..", ".##..##.", "##....##", "##....##", "##..#.##", ".##..##.", "..###.##", "........"],
    "R": ["######..", "##...##.", "##...##.", "######..", "##.##...", "##..##..", "##...##.", "........"],
    "S": [".######.", "##......", "##......", ".######.", "......##", "......##", "#######.", "........"],
    "T": ["########", "...##...", "...##...", "...##...", "...##...", "...##...", "...##...", "........"],
    "U": ["##....##", "##....##", "##....##", "##....##", "##....##", ".##..##.", "..####..", "........"],
    "V": ["##....##", "##....##", "##....##", ".##..##.", ".##..##.", "..####..", "...##...", "........"],
    "W": ["##....##", "##....##", "##....##", "##.##.##", "########", "###..###", "##....##", "........"],
    "X": ["##....##", ".##..##.", "..####..", "...##...", "..####..", ".##..##.", "##....##", "........"],
    "Y": ["##....##", ".##..##.", "..####..", "...##...", "...##...", "...##...", "...##...", "........"],
    "Z": ["#######.", ".....##.", "....##..", "...##...", "..##....", ".##.....", "#######.", "........"],
    "0": [".#####..", "##...##.", "##..###.", "##.#.##.", "###..##.", "##...##.", ".#####..", "........"],
    "1": ["..##....", ".###....", "..##....", "..##....", "..##....", "..##....", "######..", "........"],
    "2": [".#####..", "##...##.", ".....##.", "...###..", ".###....", "##......", "#######.", "........"],
    "3": [".#####..", "##...##.", ".....##.", "..####..", ".....##.", "##...##.", ".#####..", "........"],
    "4": ["....##..", "...###..", "..####..", ".##.##..", "#######.", "....##..", "....##..", "........"],
    "5": ["#######.", "##......", "######..", ".....##.", ".....##.", "##...##.", ".#####..", "........"],
    "6": ["..####..", ".##.....", "##......", "######..", "##...##.", "##...##.", ".#####..", "........"],
    "7": ["#######.", ".....##.", "....##..", "...##...", "..##....", "..##....", "..##....", "........"],
    "8": [".#####..", "##...##.", "##...##.", ".#####..", "##...##.", "##...##.", ".#####..", "........"],
    "9": [".#####..", "##...##.", "##...##.", ".######.", ".....##.", "....##..", ".####...", "........"],
    "!": ["..##....", "..##....", "..##....", "..##....", "..##....", "........", "..##....", "........"],
    "?": [".#####..", "##...##.", ".....##.", "...###..", "...##...", "........", "...##...", "........"],
    ".": ["........", "........", "........", "........", "........", "..##....", "..##....", "........"],
    ":": ["........", "..##....", "..##....", "........", "..##....", "..##....", "........", "........"],
    "-": ["........", "........", "........", ".#####..", "........", "........", "........", "........"],
    "/": [".....##.", "....##..", "....##..", "...##...", "..##....", "..##....", ".##.....", "........"],
}

# Logo: GLOWMINE, je Buchstabe 16 x 16 (doppelt gross gezeigt: 32 x 32)
LOGO_LEGENDE = {"k": 8, "a": 9, "b": 10, "c": 11, "d": 12, "e": 13, "f": 14, "g": 15, "o": 5, "O": 6, "p": 7}


def logo_buchstabe(ch):
    """Buchstabe aus dem Zeichensatz, zweifach: oben hell (gold), unten Glut"""
    z = FONT[ch]
    farben = "gggffeeddccbbbaa"
    bild = []
    for y in range(16):
        r = ""
        for x in range(16):
            gesetzt = z[y // 2][x // 2] == "#"
            r += farben[y] if gesetzt else "."
        bild.append(r)
    # Kante unten rechts dunkler, oben links ein Glanzpunkt
    bild = [list(r) for r in bild]
    for y in range(16):
        for x in range(16):
            if bild[y][x] != ".":
                unten = y + 1 < 16 and bild[y + 1][x] == "."
                rechts = x + 1 < 16 and bild[y][x + 1] == "."
                if unten or rechts:
                    bild[y][x] = "o" if y > 9 else "c"
    return ["".join(r) for r in bild]


def ziffer(d):
    """Ziffer der Anzeige 8 x 8 oben links im Muster, oben hell"""
    z = FONT[str(d)]
    farben = "hhggfedd"
    bild = []
    for y in range(16):
        if y < 8:
            r = "".join(farben[y] if c == "#" else "." for c in z[y]) + "........"
        else:
            r = "." * 16
        bild.append(r)
    return bild


# ---------------------------------------------------------------------------
# Die Karte vorn (Karte 2): 64 x 32, Zeilen 30/31 sieht man nicht.
#   #  Fels   =  Planke   o  Muenze   ~  Lava   D  Tuer (2 x 3, linke obere Ecke)
#   l  Laterne an einer Kette bis zur Decke   m/n  Pilze   v/w  Tropfstein
#   |  Balken   P  Start
#
# Spruenge (30 Schritte je Sekunde, 2,5 Punkte je Schritt, Absprung 6,5,
# Schwere 0,65): hoch bis 4 Kacheln, weit bis 6. Ich halte mich an 3 und 4.
# Muenzen liegen in der Zeile ueber dem Boden - dort ist die Mitte des
# Bergmanns - oder im Bogen eines Sprungs.


def karte_bauen():
    g = [["."] * 64 for _ in range(32)]

    def fuell(x0, y0, x1, y1, ch):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                g[y][x] = ch

    def setz(liste, ch):
        for x, y in liste:
            g[y][x] = ch

    fuell(0, 0, 63, 2, "#")                     # Decke
    fuell(0, 0, 0, 31, "#")                     # Waende
    fuell(63, 0, 63, 31, "#")
    for x0, x1 in ((0, 4), (9, 12), (18, 25), (33, 38), (45, 51), (56, 63)):
        fuell(x0, 3, x1, 3, "#")                # Decke unregelmaessig
    setz(((2, 4), (11, 4), (20, 4), (24, 4), (36, 4), (48, 4)), "v")
    setz(((22, 4), (46, 4), (60, 4)), "w")
    # A: Start, Stufe, Planken, Sims links oben
    fuell(1, 24, 21, 31, "#")
    fuell(9, 21, 13, 23, "#")
    fuell(2, 18, 7, 18, "=")
    fuell(10, 15, 13, 15, "=")
    fuell(1, 12, 6, 13, "#")
    setz(((10, 20), (11, 20), (12, 20), (3, 17), (4, 17), (5, 17), (2, 11), (3, 11), (4, 11)), "o")
    setz(((2, 19), (2, 20), (2, 21), (2, 22), (2, 23), (7, 19), (7, 20), (7, 21), (7, 22), (7, 23)), "|")
    setz(((17, 23), (5, 11)), "m")
    setz(((15, 23),), "n")
    g[22][4] = "P"
    fuell(17, 12, 20, 12, "=")                  # Abstecher ueber der Grube
    setz(((18, 11), (19, 11)), "o")
    # B: Lavagrube mit Planke, Saeule, Planke
    fuell(22, 26, 37, 31, "~")
    fuell(24, 22, 27, 22, "=")
    fuell(30, 20, 31, 31, "#")
    fuell(34, 22, 36, 22, "=")
    setz(((25, 21), (26, 21), (30, 19), (31, 19), (35, 21), (28, 17), (33, 17)), "o")
    # C: Boden, kleine Grube, Aufstieg zum Ausgang
    fuell(38, 24, 46, 31, "#")
    fuell(47, 26, 50, 31, "~")
    fuell(51, 24, 62, 31, "#")
    fuell(41, 21, 44, 21, "=")
    fuell(46, 18, 50, 18, "#")
    fuell(52, 15, 55, 15, "=")
    fuell(57, 12, 62, 13, "#")
    setz(((41, 22), (41, 23), (44, 22), (44, 23)), "|")
    setz([(52, y) for y in range(16, 24)] + [(55, y) for y in range(16, 22)], "|")
    setz(((42, 20), (43, 20), (47, 17), (48, 17), (49, 17), (53, 14), (54, 14),
          (57, 11), (58, 11), (53, 23), (54, 23), (56, 23)), "o")
    setz(((39, 23), (60, 23)), "m")
    setz(((58, 23),), "n")
    g[9][59] = "D"
    # Laternen
    setz(((15, 5), (28, 6), (42, 5), (54, 5)), "l")
    return ["".join(z) for z in g]


KARTE = karte_bauen()
# Fledermaeuse: Start (Spalte, Zeile) und Bahn von Spalte bis Spalte
FLEDERMAEUSE = [(26, 15, 21, 37), (50, 10, 44, 57)]


def karte_pruefen():
    for y, z in enumerate(KARTE):
        if len(z) != 64:
            raise SystemExit(f"Kartenzeile {y} ist {len(z)} breit")
    if len(KARTE) != 32:
        raise SystemExit(f"{len(KARTE)} Kartenzeilen")


def bauen():
    c = Cartridge()
    # --- Kacheln vorn
    for i in range(16):
        n, o, s, w = i & 1, i >> 1 & 1, i >> 2 & 1, i >> 3 & 1
        c.kachel(T_FELS + i, fels(FELS_INNEN[0], n, o, s, w), L_STEIN, B_STEIN)
    c.kachel(17, FELS_INNEN[1], L_STEIN, B_STEIN)
    c.kachel(18, FELS_INNEN[2], L_STEIN, B_STEIN)
    for i, p in enumerate(PLANKE):
        c.kachel(T_PLANKE + i, p, L_HOLZ, B_HOLZ)
    c.kachel(T_MUENZE, MUENZE, L_GLUT, B_GLUT)
    c.kachel(T_LAVA, LAVA_OBEN, L_GLUT, B_GLUT)
    c.kachel(T_LAVA + 1, LAVA_INNEN, L_GLUT, B_GLUT)
    for offen in (0, 1):
        b = tuer(offen)
        for ty in range(3):
            for tx in range(2):
                c.kachel(T_TUER + offen * 6 + ty * 2 + tx, stueck(b, tx, ty), L_HOLZ, B_HOLZ)
    c.kachel(T_DEKO + 0, LATERNE, L_GLUT, B_GLUT)
    c.kachel(T_DEKO + 1, KETTE, L_GLUT, B_GLUT)
    c.kachel(T_DEKO + 2, PILZ[0], L_PILZ, B_PILZ)
    c.kachel(T_DEKO + 3, PILZ[1], L_PILZ, B_PILZ)
    c.kachel(T_DEKO + 4, TROPFSTEIN, L_STEIN, B_STEIN)
    c.kachel(T_DEKO + 5, TROPFSTEIN2, L_STEIN, B_STEIN)
    c.kachel(T_DEKO + 6, BALKEN, L_HOLZ, B_HOLZ)
    # --- Kacheln hinten
    for ty in range(2):
        for tx in range(4):
            c.kachel(T_WAND + ty * 4 + tx, stueck(WAND, tx, ty), L_HOEHLE, B_HOEHLE)
    for tx in range(2):
        c.kachel(T_WAND + 8 + tx, stueck(SAEULE, tx, 0), L_HOEHLE, B_HOEHLE)
    for ty in range(2):
        for tx in range(2):
            c.kachel(T_WAND + 12 + ty * 2 + tx, stueck(AMETHYST, tx, ty), L_HOEHLE, B_HOEHLE)

    # --- Karte 2 (vorn): Spielfeld
    karte_pruefen()
    fest = {(x, y) for y in range(32) for x in range(64) if KARTE[y][x] == "#"}
    muenzen, fledermaeuse, tuer_pos, start = [], FLEDERMAEUSE, None, None
    for y in range(32):
        for x in range(64):
            ch = KARTE[y][x]
            if ch == "#":
                n = (x, y - 1) not in fest and y > 0
                s = (x, y + 1) not in fest and y < 31
                w = (x - 1, y) not in fest and x > 0
                o = (x + 1, y) not in fest and x < 63
                i = n | o << 1 | s << 2 | w << 3
                if i == 0:
                    t = (T_FELS, 17, 18)[(x * 7 + y * 13) % 3]
                else:
                    t = T_FELS + i
                c.setze(2, x, y, t)
            elif ch == "=":
                links = KARTE[y][x - 1] != "="
                rechts = KARTE[y][x + 1] != "="
                c.setze(2, x, y, T_PLANKE + (0 if links else 2 if rechts else 1))
            elif ch == "o":
                c.setze(2, x, y, T_MUENZE)
                muenzen.append((x, y))
            elif ch == "~":
                c.setze(2, x, y, T_LAVA if KARTE[y - 1][x] != "~" else T_LAVA + 1)
            elif ch == "D":
                tuer_pos = (x, y)
            elif ch == "l":
                c.setze(2, x, y, T_DEKO)
                yy = y - 1
                while KARTE[yy][x] != "#":
                    c.setze(2, x, yy, T_DEKO + 1)
                    yy -= 1
            elif ch in "mn":
                c.setze(2, x, y, T_DEKO + 2 + (ch == "n"))
            elif ch in "vw":
                c.setze(2, x, y, T_DEKO + 4 + (ch == "w"))
            elif ch == "|":
                c.setze(2, x, y, T_DEKO + 6)
            elif ch == "P":
                start = (x, y)
    tx, ty = tuer_pos
    for yy in range(3):
        for xx in range(2):
            c.setze(2, tx + xx, ty + yy, T_TUER + yy * 2 + xx)
    # Lava auch unter den Zeilen, die man sieht
    for y in range(28, 32):
        for x in range(64):
            if KARTE[27][x] == "~":
                c.setze(2, x, y, T_LAVA + 1)

    # --- Karte 1 (hinten): Hoehlenwand, Saeulen, Amethyst
    for y in range(32):
        for x in range(64):
            c.setze(1, x, y, T_WAND + x % 4 + y % 2 * 4)
    for sx in (5, 19, 33, 47):                  # Saeulen
        for y in range(32):
            c.setze(1, sx, y, T_WAND + 8)
            c.setze(1, sx + 1, y, T_WAND + 9)
    for ax, ay in ((10, 6), (25, 14), (40, 4), (14, 22), (44, 19), (30, 8), (52, 11), (2, 13)):
        for yy in range(2):
            for xx in range(2):
                c.setze(1, ax + xx, ay + yy, T_WAND + 12 + yy * 2 + xx)

    # --- Sprites
    c.sprite(0, KNAPPE_STEHT, L_KNAPPE, B_KNAPPE)
    c.sprite(1, KNAPPE_GEHT1, L_KNAPPE, B_KNAPPE)
    c.sprite(5, KNAPPE_GEHT2, L_KNAPPE, B_KNAPPE)
    c.sprite(3, KNAPPE_SPRINGT, L_KNAPPE, B_KNAPPE)
    c.sprite(2, KNAPPE_FAELLT, L_KNAPPE, B_KNAPPE)
    c.sprite(8, FLEDER_OBEN, L_FLEDER, B_FLEDER)
    c.sprite(12, FLEDER_UNTEN, L_FLEDER, B_FLEDER)
    for d in range(10):
        c.sprite(16 + d, ziffer(d), L_GLUT, B_GLUT)
    c.sprite(26, MUENZE_GROSS, L_GLUT, B_GLUT)
    c.sprite(27, HERZ, L_GLUT, B_HERZ)
    for i, ch in enumerate("GLOWMINE"):
        c.sprite(32 + i, logo_buchstabe(ch), LOGO_LEGENDE, B_GLUT)

    # --- Zeichensatz
    for ch, z in FONT.items():
        c.zeichen(ord(ch), z)

    # --- Look: eigene Farben fuer den Bergmann, dunklere Hoehle hinten
    knappe = [(1, 1, 3), (11, 6, 4), (14, 10, 7), (15, 12, 10), (11, 7, 1), (15, 12, 2), (15, 15, 9),
              (15, 15, 13), (1, 3, 9), (3, 6, 13), (6, 10, 15), (3, 2, 2), (6, 4, 3), (15, 15, 15), (13, 3, 3)]
    for i, f in enumerate(knappe):
        c.farbe(B_KNAPPE * 16 + 1 + i, *f)
    hoehle = [(1, 1, 2), (1, 1, 3), (2, 2, 5), (3, 2, 6), (4, 3, 8), (5, 5, 9), (7, 6, 11)]
    for i, f in enumerate(hoehle):
        c.farbe(B_HOEHLE * 16 + 1 + i, *f)
    c.farbe(B_FLEDER * 16 + 15, 15, 5, 9)           # Augen
    c.leuchte([B_GLUT * 16 + v for v in (5, 6, 7, 13, 14, 15)]        # Lava, Muenzen, Anzeige
              + [B_HOEHLE * 16 + v for v in (14, 15)]                 # Amethyst
              + [B_KNAPPE * 16 + 8, B_FLEDER * 16 + 15]               # Lampe, Augen
              + [B_PILZ * 16 + v for v in (13, 14, 15)]               # Pilze
              + [B_HOLZ * 16 + v for v in (6, 7)], staerke=8)         # Licht im Ausgang
    c.tusche(176, 3, 3, ebene_b=True)

    # --- Klaenge
    c.klang(0, [("C-3", "rechteck", 12, "gleiten"), ("G-3", "rechteck", 11, "gleiten"),
                ("C-4", "rechteck", 9, "gleiten"), ("E-4", "rechteck", 6, "ausblenden")], tempo=2)
    c.klang(1, [("B-4", "puls25", 12, ""), ("E-5", "puls25", 12, "ausblenden"),
                ("E-5", "puls25", 6, "ausblenden")], tempo=3)
    c.klang(2, [("G-4", "saege", 14, "fallen"), ("D-4", "saege", 13, "fallen"), ("A-3", "saege", 12, "fallen"),
                ("E-3", "rauschen", 12, "fallen"), ("C-3", "rauschen", 10, "ausblenden"),
                ("C-2", "rauschen", 6, "ausblenden")], tempo=4)
    c.klang(3, [("C-4", "puls25", 12, "arp"), ("C-4", "puls25", 12, "arp"), ("F-4", "puls25", 12, "arp"),
                ("F-4", "puls25", 12, "arp"), ("G-4", "puls25", 12, "arp"), ("C-5", "puls25", 13, "arp"),
                ("C-5", "puls25", 10, "ausblenden"), ("C-5", "puls25", 5, "ausblenden")], tempo=5)
    c.klang(4, [("C-1", "rauschen", 9, "ausblenden")], tempo=3)
    c.klang(5, [("E-4", "dreieck+saege", 10, "vibrato"), ("G-4", "dreieck+saege", 10, "vibrato"),
                ("C-5", "dreieck+saege", 11, "vibrato"), ("E-5", "dreieck+saege", 11, "vibrato"),
                ("G-5", "dreieck+saege", 12, "vibrato"), ("G-5", "dreieck+saege", 12, "vibrato"),
                ("C-6", "puls25", 12, "arp_langsam"), ("C-6", "puls25", 12, "arp_langsam"),
                ("C-6", "puls25", 8, "ausblenden"), ("C-6", "puls25", 4, "ausblenden")], tempo=6)
    # Bass in a-Moll als Schleife: Am F G E, je 8 Schritte
    bass = []
    for grund, terz in (("A-1", "C-2"), ("F-1", "A-1"), ("G-1", "B-1"), ("E-1", "G#1")):
        hoch = grund[:-1] + str(int(grund[-1]) + 1)
        bass += [(grund, "dreieck", 15, "ausblenden"), None, (hoch, "dreieck", 12, "ausblenden"), None,
                 (grund, "dreieck", 14, "ausblenden"), None, (terz, "dreieck", 12, "ausblenden"), None]
    c.klang(8, bass, tempo=7, schleife=True)
    return c, muenzen, fledermaeuse, tuer_pos, start


def programm(muenzen, fledermaeuse, tuer_pos, start):
    """glowmine.bas aus der Vorlage: Platzhalter durch DATA-Zeilen ersetzen"""
    vorlage = open(os.path.join(HIER, "glowmine.bas.vorlage"), encoding="utf-8").read()
    zeilen, nr = [], 9000
    werte = [len(muenzen)] + [v for m in muenzen for v in m]
    for i in range(0, len(werte), 16):
        zeilen.append(f"{nr} data " + ",".join(map(str, werte[i:i + 16])))
        nr += 10
    werte = [len(fledermaeuse)] + [v for f in fledermaeuse for v in (f[0] * 8, f[1] * 8, f[2] * 8, f[3] * 8 - 16)]
    zeilen.append(f"{nr} data " + ",".join(map(str, werte)))
    nr += 10
    zeilen.append(f"{nr} data {tuer_pos[0]},{tuer_pos[1]},{start[0] * 8},{start[1] * 8}")
    return vorlage.replace("@DATEN@", "\n".join(zeilen))


def main():
    a = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    a.add_argument("--bilder", help="Ordner fuer Vorschaubilder (braucht PIL)")
    o = a.parse_args()
    c, muenzen, fledermaeuse, tuer_pos, start = bauen()
    if o.bilder:
        from cartridge import bilder
        bilder(c, o.bilder)
    text = programm(muenzen, fledermaeuse, tuer_pos, start)
    open(os.path.join(HIER, "glowmine.bas"), "w", encoding="utf-8").write(text)
    prog = bas.rein(os.path.join(HIER, "glowmine.bas"))
    daten = c.datei(prog)
    ziel = os.path.join(HIER, "daten", "glowmine.mws")
    open(ziel, "wb").write(daten)
    print(f"glowmine.bas: {len(prog)} Byte Programm, {len(muenzen)} Muenzen, {len(fledermaeuse)} Fledermaeuse")
    print(f"daten/glowmine.mws: {len(daten)} Byte ({', '.join(str(a) for a, _ in c.abschnitte())})")


if __name__ == "__main__":
    main()
