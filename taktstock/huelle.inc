;============================================================================
;  TAKTSTOCK - Aufbau einer Huellkurve (64 Byte je Instrument, wie FastTracker 2)
;  Eingebunden vom Abspieler (spieler.asm) und vom Modul (XM-Import).
;============================================================================

; Huellkurve eines Instruments (wie FastTracker 2)
HK_ART     = 0                  ; Bit 0 an, Bit 1 Sustain, Bit 2 Schleife
HK_N       = 1                  ; Punkte 1-12
HK_SUS     = 2                  ; Sustain-Punkt
HK_LA      = 3                  ; Schleife von Punkt ...
HK_LE      = 4                  ; ... bis Punkt
HK_AUS     = 6                  ; 2: Ausklingen je Tick (von 32768, 0 = keins)
HK_PUNKTE  = 8                  ; 12 x 4 Byte: Tick (2), Wert 0-64, frei
