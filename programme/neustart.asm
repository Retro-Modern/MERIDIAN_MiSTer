;============================================================================
;  NEUSTART - startet MERIDIAN neu wie nach dem Einschalten (Etappe 8)
;
;  Fuer Aufnahmen: Startklang und Startmeldung, ohne den Core neu zu laden
;  (dann braucht HDMI ein paar Sekunden und der Startklang geht verloren).
;============================================================================

	.cpu "65816"

	* = $2000

	sei
	sec                             ; Emulationsmodus wie nach einem Reset
	xce
	jmp ($fffc)                     ; Reset-Vektor
