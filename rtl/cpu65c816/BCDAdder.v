//============================================================================
//  65C816 CPU core
//
//  SystemVerilog conversion of the VHDL 65C816 core written by srg320 for
//  SNES_MiSTer (https://github.com/MiSTer-devel/SNES_MiSTer), with
//  modifications for the Apple IIgs. See README.md in this directory.
//
//  Copyright (c) srg320 -- original VHDL implementation
//  Copyright (c) 2026 Alan Steremberg -- Verilog conversion and IIgs changes
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 3 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program. If not, see <https://www.gnu.org/licenses/>.
//============================================================================

module BCDAdder(A, B, CI, S, CO, VO, ADD, BCD);
   input [3:0]  A;
   input [3:0]  B;
   input        CI;

   output [3:0] S;
   output       CO;
   output       VO;

   input        ADD;
   input        BCD;


   wire [3:0]   B2;
   wire [3:0]   BIN_S;
   wire         BIN_CO;
   wire [3:0]   BCD_B;
   wire         BCD_CO;
   wire         BCD_CORR_CO;  // Unused correction carry output

   assign B2 = B ^ {4{~ADD}};


   adder4 bin_adder(.A(A), .B(B2), .CI(CI), .S(BIN_S), .CO(BIN_CO));

   assign BCD_CO = (((BIN_S[3] & BIN_S[2]) | (BIN_S[3] & BIN_S[1])) & ADD) | ((~(BIN_CO ^ ADD)));
   assign BCD_B = {(~ADD), ((BCD_CO & BCD) ^ (~ADD)), ((BCD_CO & BCD) ^ (~ADD)), (~ADD)};


   adder4 bcd_corr_adder(.A(BIN_S), .B(BCD_B), .CI((~ADD)), .S(S), .CO(BCD_CORR_CO));

   assign CO = (BCD == 1'b0) ? BIN_CO :
               BCD_CO ^ (~ADD);
   assign VO = ((~(A[3] ^ B2[3]))) & (A[3] ^ BIN_S[3]);

endmodule
