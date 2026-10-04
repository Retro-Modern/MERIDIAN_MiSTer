; Automatisch erzeugt von tools/opcodes.py - nicht von Hand aendern
; 65C816: 92 Mnemonics, 256 Opcodes, 26 Adressierungsarten

A_IMP   = 0
A_AKKU  = 1
A_IMM_M = 2
A_IMM_X = 3
A_IMM8  = 4
A_DP    = 5
A_DPX   = 6
A_DPY   = 7
A_DPI   = 8
A_DPIX  = 9
A_DPIY  = 10
A_DPL   = 11
A_DPLY  = 12
A_ABS   = 13
A_ABSX  = 14
A_ABSY  = 15
A_LONG  = 16
A_LONGX = 17
A_ABSI  = 18
A_ABSIX = 19
A_ABSL  = 20
A_REL   = 21
A_RELL  = 22
A_SR    = 23
A_SRIY  = 24
A_BLOCK = 25
MN_ANZAHL = 92
MN_BRK = 11
MN_COP = 20
MN_WDM = 89
MN_JMP = 31
MN_JSR = 33
MN_JML = 30
MN_JSL = 32
MN_REP = 58
MN_SEP = 68
MN_MVN = 38
MN_MVP = 39
MN_PER = 44
MN_BRL = 12

mo_mnemonics
	.text "ADC", "AND", "ASL", "BCC", "BCS", "BEQ", "BIT", "BMI"
	.text "BNE", "BPL", "BRA", "BRK", "BRL", "BVC", "BVS", "CLC"
	.text "CLD", "CLI", "CLV", "CMP", "COP", "CPX", "CPY", "DEC"
	.text "DEX", "DEY", "EOR", "INC", "INX", "INY", "JML", "JMP"
	.text "JSL", "JSR", "LDA", "LDX", "LDY", "LSR", "MVN", "MVP"
	.text "NOP", "ORA", "PEA", "PEI", "PER", "PHA", "PHB", "PHD"
	.text "PHK", "PHP", "PHX", "PHY", "PLA", "PLB", "PLD", "PLP"
	.text "PLX", "PLY", "REP", "ROL", "ROR", "RTI", "RTL", "RTS"
	.text "SBC", "SEC", "SED", "SEI", "SEP", "STA", "STP", "STX"
	.text "STY", "STZ", "TAX", "TAY", "TCD", "TCS", "TDC", "TRB"
	.text "TSB", "TSC", "TSX", "TXA", "TXS", "TXY", "TYA", "TYX"
	.text "WAI", "WDM", "XBA", "XCE"

mo_op_mn                        ; je Opcode: Mnemonic
	.byte 11, 41, 20, 41, 80, 41, 2, 41, 49, 41, 2, 47, 80, 41, 2, 41
	.byte 9, 41, 41, 41, 79, 41, 2, 41, 15, 41, 27, 77, 79, 41, 2, 41
	.byte 33, 1, 32, 1, 6, 1, 59, 1, 55, 1, 59, 54, 6, 1, 59, 1
	.byte 7, 1, 1, 1, 6, 1, 59, 1, 65, 1, 23, 81, 6, 1, 59, 1
	.byte 61, 26, 89, 26, 39, 26, 37, 26, 45, 26, 37, 48, 31, 26, 37, 26
	.byte 13, 26, 26, 26, 38, 26, 37, 26, 17, 26, 51, 76, 30, 26, 37, 26
	.byte 63, 0, 44, 0, 73, 0, 60, 0, 52, 0, 60, 62, 31, 0, 60, 0
	.byte 14, 0, 0, 0, 73, 0, 60, 0, 67, 0, 57, 78, 31, 0, 60, 0
	.byte 10, 69, 12, 69, 72, 69, 71, 69, 25, 6, 83, 46, 72, 69, 71, 69
	.byte 3, 69, 69, 69, 72, 69, 71, 69, 86, 69, 84, 85, 73, 69, 73, 69
	.byte 36, 34, 35, 34, 36, 34, 35, 34, 75, 34, 74, 53, 36, 34, 35, 34
	.byte 4, 34, 34, 34, 36, 34, 35, 34, 18, 34, 82, 87, 36, 34, 35, 34
	.byte 22, 19, 58, 19, 22, 19, 23, 19, 29, 19, 24, 88, 22, 19, 23, 19
	.byte 8, 19, 19, 19, 43, 19, 23, 19, 16, 19, 50, 70, 30, 19, 23, 19
	.byte 21, 64, 68, 64, 21, 64, 27, 64, 28, 64, 40, 90, 21, 64, 27, 64
	.byte 5, 64, 64, 64, 42, 64, 27, 64, 66, 64, 56, 91, 33, 64, 27, 64

mo_op_art                       ; je Opcode: Adressierungsart
	.byte A_IMM8, A_DPIX, A_IMM8, A_SR, A_DP, A_DP, A_DP, A_DPL, A_IMP, A_IMM_M, A_AKKU, A_IMP, A_ABS, A_ABS, A_ABS, A_LONG
	.byte A_REL, A_DPIY, A_DPI, A_SRIY, A_DP, A_DPX, A_DPX, A_DPLY, A_IMP, A_ABSY, A_AKKU, A_IMP, A_ABS, A_ABSX, A_ABSX, A_LONGX
	.byte A_ABS, A_DPIX, A_LONG, A_SR, A_DP, A_DP, A_DP, A_DPL, A_IMP, A_IMM_M, A_AKKU, A_IMP, A_ABS, A_ABS, A_ABS, A_LONG
	.byte A_REL, A_DPIY, A_DPI, A_SRIY, A_DPX, A_DPX, A_DPX, A_DPLY, A_IMP, A_ABSY, A_AKKU, A_IMP, A_ABSX, A_ABSX, A_ABSX, A_LONGX
	.byte A_IMP, A_DPIX, A_IMM8, A_SR, A_BLOCK, A_DP, A_DP, A_DPL, A_IMP, A_IMM_M, A_AKKU, A_IMP, A_ABS, A_ABS, A_ABS, A_LONG
	.byte A_REL, A_DPIY, A_DPI, A_SRIY, A_BLOCK, A_DPX, A_DPX, A_DPLY, A_IMP, A_ABSY, A_IMP, A_IMP, A_LONG, A_ABSX, A_ABSX, A_LONGX
	.byte A_IMP, A_DPIX, A_RELL, A_SR, A_DP, A_DP, A_DP, A_DPL, A_IMP, A_IMM_M, A_AKKU, A_IMP, A_ABSI, A_ABS, A_ABS, A_LONG
	.byte A_REL, A_DPIY, A_DPI, A_SRIY, A_DPX, A_DPX, A_DPX, A_DPLY, A_IMP, A_ABSY, A_IMP, A_IMP, A_ABSIX, A_ABSX, A_ABSX, A_LONGX
	.byte A_REL, A_DPIX, A_RELL, A_SR, A_DP, A_DP, A_DP, A_DPL, A_IMP, A_IMM_M, A_IMP, A_IMP, A_ABS, A_ABS, A_ABS, A_LONG
	.byte A_REL, A_DPIY, A_DPI, A_SRIY, A_DPX, A_DPX, A_DPY, A_DPLY, A_IMP, A_ABSY, A_IMP, A_IMP, A_ABS, A_ABSX, A_ABSX, A_LONGX
	.byte A_IMM_X, A_DPIX, A_IMM_X, A_SR, A_DP, A_DP, A_DP, A_DPL, A_IMP, A_IMM_M, A_IMP, A_IMP, A_ABS, A_ABS, A_ABS, A_LONG
	.byte A_REL, A_DPIY, A_DPI, A_SRIY, A_DPX, A_DPX, A_DPY, A_DPLY, A_IMP, A_ABSY, A_IMP, A_IMP, A_ABSX, A_ABSX, A_ABSY, A_LONGX
	.byte A_IMM_X, A_DPIX, A_IMM8, A_SR, A_DP, A_DP, A_DP, A_DPL, A_IMP, A_IMM_M, A_IMP, A_IMP, A_ABS, A_ABS, A_ABS, A_LONG
	.byte A_REL, A_DPIY, A_DPI, A_SRIY, A_DPI, A_DPX, A_DPX, A_DPLY, A_IMP, A_ABSY, A_IMP, A_IMP, A_ABSL, A_ABSX, A_ABSX, A_LONGX
	.byte A_IMM_X, A_DPIX, A_IMM8, A_SR, A_DP, A_DP, A_DP, A_DPL, A_IMP, A_IMM_M, A_IMP, A_IMP, A_ABS, A_ABS, A_ABS, A_LONG
	.byte A_REL, A_DPIY, A_DPI, A_SRIY, A_ABS, A_DPX, A_DPX, A_DPLY, A_IMP, A_ABSY, A_IMP, A_IMP, A_ABSIX, A_ABSX, A_ABSX, A_LONGX

; je Art: Vorsatz (0 oder Zeichen), Operand (siehe opcodes.py), Nachsatz
mo_arten
	.byte 0, 0, 0	; IMP
	.byte 0, 9, 0	; AKKU
	.byte '#', 4, 0	; IMM_M
	.byte '#', 5, 0	; IMM_X
	.byte '#', 1, 0	; IMM8
	.byte 0, 1, 0	; DP
	.byte 0, 1, 1	; DPX
	.byte 0, 1, 2	; DPY
	.byte '(', 1, 3	; DPI
	.byte '(', 1, 4	; DPIX
	.byte '(', 1, 5	; DPIY
	.byte '[', 1, 6	; DPL
	.byte '[', 1, 7	; DPLY
	.byte 0, 2, 0	; ABS
	.byte 0, 2, 1	; ABSX
	.byte 0, 2, 2	; ABSY
	.byte 0, 3, 0	; LONG
	.byte 0, 3, 1	; LONGX
	.byte '(', 2, 3	; ABSI
	.byte '(', 2, 4	; ABSIX
	.byte '[', 2, 6	; ABSL
	.byte 0, 6, 0	; REL
	.byte 0, 7, 0	; RELL
	.byte 0, 1, 8	; SR
	.byte '(', 1, 9	; SRIY
	.byte 0, 8, 0	; BLOCK

mo_nachsaetze                   ; Nachsaetze, je mit 0 abgeschlossen
mo_ns0	.byte 0
mo_ns1	.text ",X", 0
mo_ns2	.text ",Y", 0
mo_ns3	.text ")", 0
mo_ns4	.text ",X)", 0
mo_ns5	.text "),Y", 0
mo_ns6	.text "]", 0
mo_ns7	.text "],Y", 0
mo_ns8	.text ",S", 0
mo_ns9	.text ",S),Y", 0
mo_ns_tab
	.word mo_ns0, mo_ns1, mo_ns2, mo_ns3, mo_ns4, mo_ns5, mo_ns6, mo_ns7, mo_ns8, mo_ns9
