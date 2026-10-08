#!/usr/bin/python3
"""Prueft die Akkubreite bei 64tass-Quellen fuer den 65816: mit welcher Breite
(.as/.al, #akku8/#akku16, sep/rep #$20) eine Routine zurueckkehrt und womit
der Aufrufer nach dem jsr weiterrechnet. Passt das nicht und folgt kein
Moduswechsel, meldet es die Stelle - dort wird sonst ein Immediate zu lang
oder zu kurz (BRK) oder Rechnungen laufen in der falschen Breite.

    akkubreite.py welle.asm modul.asm ...        Verdachtsstellen
    akkubreite.py welle.asm ... --aus            Ausgaenge der we_*-Routinen

Grob: liest die Dateien der Reihe nach, verfolgt Spruenge nicht.
"""
import re, sys
dateien = [a for a in sys.argv[1:] if not a.startswith("--")]
zeilen = []
for d in dateien:
    for i, l in enumerate(open(d, encoding="utf-8", errors="replace")):
        zeilen.append((d, i + 1, l.rstrip("\n")))

def code(l):
    l = l.split(";")[0]
    return l
routinen = {}   # name -> {'ein': st, 'aus': set(), 'jmp': set()}
aufrufe = []    # (datei, zeile, name, zustand, naechste)
st = None
akt = None
im_makro = False
for k, (d, n, l) in enumerate(zeilen):
    c = code(l)
    if re.search(r"\.macro", c): im_makro = True; continue
    if re.search(r"\.endm", c): im_makro = False; continue
    if im_makro: continue
    m = re.match(r"([A-Za-z]\w*)\b(.*)", c)
    if m and "=" not in m.group(2) and not m.group(2).strip().startswith(".macro"):
        name = m.group(1)
        if not re.match(r"\s*\.(byte|word|long|dword|null|text|fill|ptext)", m.group(2)):
            akt = name
            routinen[akt] = {'ein': st, 'aus': set(), 'jmp': set(), 'ort': (d, n)}
            rest = m.group(2)
            c = rest
    t = c.strip()
    t = re.sub(r"^[+-]+\s*", "", t)
    t = re.sub(r"^_\w+\s*", "", t)
    if t in (".as", "#akku8") or re.match(r"sep\s+#\$(20|30)", t):
        st = 8
    elif t in (".al", "#akku16") or re.match(r"rep\s+#\$(20|30)", t):
        st = 16
    elif t.startswith(("#mov24", "#add24", "#sub24", "#tay8", "#tax8", "#melde", "#schreibe")):
        st = 8
    if akt and routinen[akt]['ein'] is None and st is not None and t in (".as", ".al"):
        routinen[akt]['ein'] = st
    if re.match(r"rt[sl]\b", t) and akt:
        routinen[akt]['aus'].add(st)
    m2 = re.match(r"jmp\s+(\w+)$", t)
    if m2 and akt:
        routinen[akt]['jmp'].add(m2.group(1))
    m3 = re.match(r"jsr\s+(\w+)$", t)
    if m3:
        # naechste Codezeile
        nx = ""
        for j in range(k + 1, min(k + 4, len(zeilen))):
            cc = code(zeilen[j][2]).strip()
            if cc:
                nx = cc; break
        aufrufe.append((d, n, m3.group(1), st, nx))

def aus(name, tiefe=0):
    r = routinen.get(name)
    if not r or tiefe > 8: return set()
    s = set(x for x in r['aus'] if x)
    for j in r['jmp']:
        s |= aus(j, tiefe + 1)
    return s

for d, n, name, s, nx in aufrufe:
    if not d.endswith(sys.argv[1].split("/")[-1]) and "--alle" not in sys.argv: pass
    a = aus(name)
    if not a or s is None: continue
    if a == {s}: continue
    if re.match(r"(\.as|\.al|#akku8|#akku16|sep|rep|#mov24|#add24|#sub24|#tay8|#tax8|#melde|#schreibe|rt[sl]|jmp|jsr|pl[xy]|ph[xy]|bra)", re.sub(r"^[+-]+\s*","",nx)):
        # Moduswechsel oder harmlos -> nur melden, wenn danach Akku benutzt wird? grob: ueberspringen
        if not re.match(r"(pl[xy]|ph[xy]|jsr|bra)", re.sub(r"^[+-]+\s*","",nx)):
            continue
    print(f"{d}:{n}: jsr {name} (Ausgang {sorted(a)}) Aufrufer {s} -> {nx}")

if "--aus" in sys.argv:
    for n, r in routinen.items():
        if n.startswith("we_"):
            print(n, r['ein'], sorted(x for x in r['aus'] if x is not None), sorted(r['jmp']))
