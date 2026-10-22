; Automatisch erzeugt von rom/bauen.sh (tools/bas.py): die Kopfzeilen
SX_DATATK = 131
sx_kopf
	.byte 45, $8e, $20, $53, $50, $52, $49, $54, $45, $20, $50, $41, $54, $54, $45, $52, $4e, $53, $20, $46, $52, $4f, $4d, $20, $54, $48, $45, $20, $57, $4f, $52, $4b, $53, $48, $4f, $50, $20, $2d, $20, $47, $4f, $53, $55, $42, $20, $01	; REM SPRITE PATTERNS FROM THE WORKSHOP - GOSUB *+0
	.byte 11, $85, $20, $50, $42, $28, $31, $32, $37, $29, $3a, $8b	; DIM PB(127):RESTORE
	.byte 27, $86, $20, $41, $24, $3a, $8a, $20, $41, $24, $ac, $aa, $22, $53, $50, $52, $49, $54, $45, $44, $41, $54, $41, $22, $20, $a0, $20, $03	; READ A$:IF A$<>"SPRITEDATA" THEN *+20
	.byte 13, $86, $20, $4d, $3a, $8a, $20, $4d, $ac, $30, $20, $a0, $20, $8d	; READ M:IF M<0 THEN RETURN
	.byte 38, $86, $20, $50, $42, $28, $4d, $29, $3a, $81, $20, $5a, $ab, $30, $20, $9d, $20, $31, $35, $3a, $86, $20, $41, $24, $3a, $d3, $20, $4d, $2c, $5a, $2c, $41, $24, $3a, $82, $3a, $88, $20, $04	; READ PB(M):FOR Z=0 TO 15:READ A$:PATTERN M,Z,A$:NEXT:GOTO *+30
	.byte 12, $83, $20, $53, $50, $52, $49, $54, $45, $44, $41, $54, $41	; DATA SPRITEDATA
	.byte 0
