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
module AddSubBCD
  (
   input [15:0]  A,
   input [15:0]  B,
   input         CI,
   input         ADD,
   input         BCD,
   input         w16,
   output [15:0] S,
   output        CO,
   output        VO
   );

   wire          VO0;  // Unused overflow output
   wire          VO1;
   wire          VO2;  // Unused overflow output
   wire          VO3;
   wire          CO0;
   wire          CO1;
   wire          CO2;
   wire          CO3;




   BCDAdder add0(.A(A[3:0]), .B(B[3:0]), .CI(CI), .S(S[3:0]), .CO(CO0), .VO(VO0), .ADD(ADD), .BCD(BCD));




   BCDAdder add1(.A(A[7:4]), .B(B[7:4]), .CI(CO0), .S(S[7:4]), .CO(CO1), .VO(VO1), .ADD(ADD), .BCD(BCD));




   BCDAdder add2(.A(A[11:8]), .B(B[11:8]), .CI(CO1), .S(S[11:8]), .CO(CO2), .VO(VO2), .ADD(ADD), .BCD(BCD));




   BCDAdder add3(.A(A[15:12]), .B(B[15:12]), .CI(CO2), .S(S[15:12]), .CO(CO3), .VO(VO3), .ADD(ADD), .BCD(BCD));

   assign VO = (w16 == 1'b0) ? VO1 :
               VO3;
   assign CO = (w16 == 1'b0) ? CO1 :
               CO3;

endmodule
