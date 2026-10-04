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

module adder4(A, B, CI, S, CO);
   input [3:0]  A;
   input [3:0]  B;
   input        CI;
   output [3:0] S;
   output       CO;


   wire         CO0;
   wire         CO1;
   wire         CO2;


   bit_adder b_add0(A[0], B[0], CI, S[0], CO0);

   bit_adder b_add1(A[1], B[1], CO0, S[1], CO1);

   bit_adder b_add2(A[2], B[2], CO1, S[2], CO2);

   bit_adder b_add3(A[3], B[3], CO2, S[3], CO);

endmodule
