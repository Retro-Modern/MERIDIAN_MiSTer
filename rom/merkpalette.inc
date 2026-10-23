; Gemeinsame Adressen im Zusatzspeicher (Systembank $FE) fuer Kern,
; System-ROM und Werkstatt - siehe rom/palette.asm
GL_TAB      = $FE1400           ; SHINE: Anzahl, dann je Punkt Farbe, Zeile, r, g, b
PAL_GUELTIG = $FE15FF           ; Merkpalette: 0 Startfarben, 1 PAL_MERK gilt
PAL_MERK    = $FE1600           ; Merkpalette: 256 x gggg bbbb / ---- rrrr
