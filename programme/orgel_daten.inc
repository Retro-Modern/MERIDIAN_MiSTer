; Automatisch erzeugt von tools/orgel.py - nicht von Hand aendern

NOTEN_MITTEN = 82
noten_mitte
	.word 565, 599, 634, 672, 712, 754, 799, 847
	.word 897, 951, 1007, 1067, 1130, 1198, 1269, 1344
	.word 1424, 1509, 1598, 1693, 1794, 1900, 2013, 2133
	.word 2260, 2394, 2537, 2688, 2848, 3017, 3196, 3386
	.word 3588, 3801, 4027, 4266, 4520, 4789, 5074, 5375
	.word 5695, 6033, 6392, 6773, 7175, 7602, 8054, 8533
	.word 9040, 9578, 10147, 10750, 11389, 12067, 12784, 13544
	.word 14350, 15203, 16107, 17065, 18079, 19155, 20294, 21500
	.word 22779, 24133, 25568, 27089, 28700, 30406, 32214, 34130
	.word 36159, 38309, 40587, 43001, 45558, 48267, 51137, 54177
	.word 57399, 60812
noten_namen		; 4 Byte je Note
	.text "C-1", 0
	.text "C#1", 0
	.text "D-1", 0
	.text "D#1", 0
	.text "E-1", 0
	.text "F-1", 0
	.text "F#1", 0
	.text "G-1", 0
	.text "G#1", 0
	.text "A-1", 0
	.text "A#1", 0
	.text "B-1", 0
	.text "C-2", 0
	.text "C#2", 0
	.text "D-2", 0
	.text "D#2", 0
	.text "E-2", 0
	.text "F-2", 0
	.text "F#2", 0
	.text "G-2", 0
	.text "G#2", 0
	.text "A-2", 0
	.text "A#2", 0
	.text "B-2", 0
	.text "C-3", 0
	.text "C#3", 0
	.text "D-3", 0
	.text "D#3", 0
	.text "E-3", 0
	.text "F-3", 0
	.text "F#3", 0
	.text "G-3", 0
	.text "G#3", 0
	.text "A-3", 0
	.text "A#3", 0
	.text "B-3", 0
	.text "C-4", 0
	.text "C#4", 0
	.text "D-4", 0
	.text "D#4", 0
	.text "E-4", 0
	.text "F-4", 0
	.text "F#4", 0
	.text "G-4", 0
	.text "G#4", 0
	.text "A-4", 0
	.text "A#4", 0
	.text "B-4", 0
	.text "C-5", 0
	.text "C#5", 0
	.text "D-5", 0
	.text "D#5", 0
	.text "E-5", 0
	.text "F-5", 0
	.text "F#5", 0
	.text "G-5", 0
	.text "G#5", 0
	.text "A-5", 0
	.text "A#5", 0
	.text "B-5", 0
	.text "C-6", 0
	.text "C#6", 0
	.text "D-6", 0
	.text "D#6", 0
	.text "E-6", 0
	.text "F-6", 0
	.text "F#6", 0
	.text "G-6", 0
	.text "G#6", 0
	.text "A-6", 0
	.text "A#6", 0
	.text "B-6", 0
	.text "C-7", 0
	.text "C#7", 0
	.text "D-7", 0
	.text "D#7", 0
	.text "E-7", 0
	.text "F-7", 0
	.text "F#7", 0
	.text "G-7", 0
	.text "G#7", 0
	.text "A-7", 0
	.text "A#7", 0
wellen_namen		; 8 Zeichen je Eintrag
	.text "-       "
	.text "Triangle"
	.text "Saw     "
	.text "Tri+Saw "
	.text "Pulse   "
	.text "Tri+Puls"
	.text "Saw+Puls"
	.text "T+S+P   "
	.text "Noise   "
	.text "Mix     "
	.text "Mix     "
	.text "Mix     "
	.text "Mix     "
	.text "Mix     "
	.text "Mix     "
	.text "Mix     "
filter_namen		; 10 Zeichen je Eintrag
	.text "off       "
	.text "Low pass  "
	.text "Band pass "
	.text "Low+Band  "
	.text "High pass "
	.text "Notch     "
	.text "Band+High "
	.text "all three "
pan_pos
	.byte 3, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6
	.byte 0, 3, 4, 5, 5, 5, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6
	.byte 0, 2, 3, 4, 4, 5, 5, 5, 5, 5, 5, 5, 6, 6, 6, 6
	.byte 0, 1, 2, 3, 4, 4, 4, 5, 5, 5, 5, 5, 5, 5, 5, 5
	.byte 0, 1, 2, 2, 3, 4, 4, 4, 4, 5, 5, 5, 5, 5, 5, 5
	.byte 0, 1, 1, 2, 2, 3, 4, 4, 4, 4, 4, 5, 5, 5, 5, 5
	.byte 0, 0, 1, 2, 2, 2, 3, 3, 4, 4, 4, 4, 4, 5, 5, 5
	.byte 0, 0, 1, 1, 2, 2, 3, 3, 3, 4, 4, 4, 4, 4, 4, 5
	.byte 0, 0, 1, 1, 2, 2, 2, 3, 3, 3, 4, 4, 4, 4, 4, 4
	.byte 0, 0, 1, 1, 1, 2, 2, 2, 3, 3, 3, 4, 4, 4, 4, 4
	.byte 0, 0, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 4, 4, 4, 4
	.byte 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4
	.byte 0, 0, 0, 1, 1, 1, 2, 2, 2, 2, 2, 3, 3, 3, 3, 4
	.byte 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 3
	.byte 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 2, 3, 3, 3, 3
	.byte 0, 0, 0, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 3, 3, 3
TEILE = 5
teil_namen		; 12 Zeichen je Teil
	.text "Intro       "
	.text "Verse       "
	.text "Chorus      "
	.text "Filter sweep"
	.text "Finale      "
SAMPLES = 7
smp_start		; untere 16 Bit der Startadresse
	.word $0000, $150b, $20af, $3a67, $4304, $8140, $a31d
smp_bloecke		; Laenge der Huellkurve (256-Byte-Bloecke), Index = Sample * 2
	.word 22, 12, 26, 9, 63, 34, 28
smp_huelle		; Zeiger auf die Huellkurven
	.word huelle_kick, huelle_snare, huelle_klatsch, huelle_hihat, huelle_becken, huelle_meridian, huelle_orgel
smp_namen		; 8 Zeichen je Sample
	.text "Kick    "
	.text "Snare   "
	.text "Clap    "
	.text "Hi-Hat  "
	.text "Cymbal  "
	.text "MERIDIAN"
	.text "ORGEL   "
smp_raten		; 6 Zeichen je Sample
	.text "22 kHz"
	.text "22 kHz"
	.text "22 kHz"
	.text "22 kHz"
	.text "16 kHz"
	.text "16 kHz"
	.text "16 kHz"
huelle_kick
	.byte 254, 248, 236, 230, 144, 82, 74, 104, 92, 74, 54, 50, 36, 30, 28, 18
	.byte 18, 12, 14, 12, 8, 0
huelle_snare
	.byte 254, 198, 148, 94, 52, 36, 32, 16, 10, 8, 6, 2
huelle_klatsch
	.byte 254, 192, 144, 152, 92, 116, 72, 66, 48, 50, 32, 34, 32, 22, 20, 18
	.byte 14, 12, 14, 12, 10, 8, 8, 6, 6, 2
huelle_hihat
	.byte 254, 150, 72, 46, 44, 38, 20, 12, 10
huelle_becken
	.byte 200, 254, 190, 206, 158, 122, 154, 126, 100, 96, 108, 74, 62, 62, 56, 52
	.byte 48, 74, 36, 38, 34, 38, 30, 34, 34, 26, 36, 20, 26, 20, 22, 18
	.byte 18, 18, 16, 16, 22, 16, 14, 12, 10, 10, 10, 12, 8, 10, 10, 8
	.byte 8, 8, 6, 6, 6, 4, 6, 6, 4, 4, 4, 6, 4, 4, 2
huelle_meridian
	.byte 102, 118, 178, 208, 210, 224, 210, 188, 184, 200, 224, 220, 246, 246, 254, 74
	.byte 42, 120, 142, 118, 124, 136, 150, 170, 168, 164, 138, 96, 98, 80, 64, 36
	.byte 24, 12
huelle_orgel
	.byte 100, 134, 166, 198, 222, 224, 254, 198, 202, 136, 62, 34, 58, 164, 140, 180
	.byte 194, 182, 192, 178, 150, 140, 124, 88, 40, 34, 22, 8
