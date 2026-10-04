//============================================================================
//  DRAHT - Fenster ins DDR3-RAM des MiSTer (Etappe 12)
//
//  Die CPU sieht in Bank $FD 64 KB des DDR3-Speichers, den auch der Linux-
//  Teil des MiSTer sieht (physisch $3E100000). Darueber laeuft das Postfach
//  zum Netzdienst draht.py: Der MERIDIAN schreibt eine Anfrage, der Dienst
//  antwortet. Jeder Zugriff geht einzeln ans DDR3 - ohne Zwischenspeicher,
//  denn die Gegenseite aendert die Daten jederzeit. Die CPU wartet (RDY),
//  bis ihr Byte gelesen oder geschrieben ist (einige hundert Nanosekunden).
//
//  Der DDR3-Anschluss des Cores hat damit zwei Kunden: BOTE (liest das
//  Postfach fuer Programme) und die CPU. Der Verteiler laesst immer nur einen
//  Zugriff zur Zeit laufen; BOTE kommt zuerst.
//============================================================================

module draht
#(
	parameter [28:0] FENSTER = 29'h07C20000          // physisch $3E100000
)
(
	input             clk,
	input             reset,

	// CPU (Bank $FD)
	input             zugriff,      // Buszyklus in Bank $FD
	input             schreiben,
	input      [15:0] adr,
	input       [7:0] din,
	input             weiter,       // CPU beendet den Buszyklus
	output            warten,
	output reg  [7:0] dout,

	// BOTE (liest)
	input      [28:0] b_addr,
	input             b_rd,
	output            b_busy,
	output     [63:0] b_dout,
	output            b_ready,

	// DDR3 (Avalon, 64 Bit)
	output     [28:0] ddr_addr,
	output            ddr_rd,
	output            ddr_we,
	output     [63:0] ddr_din,
	output      [7:0] ddr_be,
	input             ddr_busy,
	input      [63:0] ddr_dout,
	input             ddr_dout_ready
);

localparam [1:0] FREI = 2'd0, ANFRAGE = 2'd1, LESEN = 2'd2;

reg  [1:0] zust = FREI;
reg        fuer_cpu;                // Besitzer: 0 BOTE, 1 CPU
reg        c_an, c_fertig;          // CPU: Auftrag laeuft / erledigt
reg [15:0] c_adr;
reg        c_we;
reg  [7:0] c_din;

wire c_will = zugriff && !c_fertig && !c_an;

assign ddr_addr = fuer_cpu ? FENSTER + {16'd0, c_adr[15:3]} : b_addr;
assign ddr_rd   = (zust == ANFRAGE) && (fuer_cpu ? !c_we : 1'b1);
assign ddr_we   = (zust == ANFRAGE) && fuer_cpu && c_we;
assign ddr_din  = {8{c_din}};
assign ddr_be   = 8'b1 << c_adr[2:0];

assign b_busy   = !((zust == ANFRAGE) && !fuer_cpu && !ddr_busy);
assign b_ready  = (zust == LESEN) && !fuer_cpu && ddr_dout_ready;
assign b_dout   = ddr_dout;

assign warten   = zugriff && !c_fertig;

always @(posedge clk) begin
	case (zust)
		FREI:
			if (b_rd) begin                     // BOTE zuerst
				fuer_cpu <= 1'b0;
				zust     <= ANFRAGE;
			end
			else if (c_will) begin
				fuer_cpu <= 1'b1;
				c_an     <= 1'b1;
				c_adr    <= adr;
				c_we     <= schreiben;
				c_din    <= din;
				zust     <= ANFRAGE;
			end
		ANFRAGE:
			if (!ddr_busy) begin                // angenommen
				if (fuer_cpu && c_we) begin
					c_fertig <= 1'b1;
					c_an     <= 1'b0;
					zust     <= FREI;
				end
				else zust <= LESEN;
			end
		LESEN:
			if (ddr_dout_ready) begin
				if (fuer_cpu) begin
					dout     <= ddr_dout[{c_adr[2:0], 3'b000} +: 8];
					c_fertig <= 1'b1;
					c_an     <= 1'b0;
				end
				zust <= FREI;
			end
		default: zust <= FREI;
	endcase
	if (weiter) c_fertig <= 1'b0;

	if (reset) begin
		zust     <= FREI;
		c_an     <= 1'b0;
		c_fertig <= 1'b0;
	end
end

endmodule
