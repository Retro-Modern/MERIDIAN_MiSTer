//============================================================================
//  LOTSE - Copper des MERIDIAN (Etappe 7)
//
//  Ein kleiner Prozessor, der mit dem Elektronenstrahl mitfaehrt: Er liest
//  eine Befehlsliste aus dem Chip-RAM, wartet auf Strahlpositionen und
//  schreibt dann Register der anderen Chips - Rasterbalken, Farbverlaeufe,
//  geteilte Bildschirme, ohne dass die CPU etwas tun muss.
//
//  Zu Beginn der Austastluecke vor Zeile 240 (Anfang des unsichtbaren
//  Bereichs) beginnt LOTSE jedes Bild von vorn bei LISTE.
//
//  Befehle, je 4 Byte:
//   $00 -  -  -          ENDE        bis zum naechsten Bild nichts mehr
//   $01 zl zh xl         WARTE       bis Zeile z (9 Bit), Punkt x (9 Bit:
//                                    xh = Bit 1 von zh); x = $1FF heisst
//                                    "Zeilenanfang" = Beginn der
//                                    Austastluecke vor der Zeile
//   $02 rl rh w          SETZE       Register $rhrl (C000-C7FF, nicht BOTE)
//                                    auf w setzen
//   $03 al am ah         SPRUNG      weiter bei $ahamal
//   $04 -  -  -          SIGNAL      Interrupt ausloesen (wenn erlaubt)
//   $05 -  -  -          WARTE_KRAN  bis der Blitter KRAN fertig ist
//  Zeilen in Bildreihenfolge: 240 .. letzte Zeile, dann 0 .. 239.
//  Wirkung: Die Palette gilt sofort, Ebenen und Sprites ab der naechsten
//  Zeile (PINSEL zeichnet jede Zeile eine Zeile im Voraus).
//
//  Register ab $00:C700:
//   $00-$02 LISTE     Adresse der Befehlsliste (gilt ab dem naechsten Bild)
//   $03     STEUER    Bit 0: an, Bit 1: SIGNAL-Interrupt erlaubt
//   $04     STATUS    lesen: Bit 0 Signal gemeldet, 1 laeuft, 2 wartet;
//                     schreiben: Bit 0 = 1 loescht die Meldung
//   $05/$06 BEFEHLE   lesen: ausgefuehrte Befehle im letzten Bild
//============================================================================

module lotse
(
	input             clk,
	input             reset,

	input       [7:0] reg_addr,
	input       [7:0] reg_din,
	output reg  [7:0] reg_dout,
	input             reg_we,
	output            irq,

	// Strahl (aus PINSEL)
	input             ce_pix,
	input       [9:0] hc,
	input       [8:0] vc,
	input       [8:0] v_last,

	// Chip-RAM lesen: gnt im selben Takt, ack einen Takt spaeter mit mem_q
	output            mem_req,
	output     [17:0] mem_addr,
	input             mem_gnt,
	input             mem_ack,
	input       [7:0] mem_q,

	// Registerbus: io_gnt im selben Takt, dann ist geschrieben
	output            io_req,
	output     [10:0] io_addr,
	output      [7:0] io_dat,
	input             io_gnt,

	input             kran_busy,
	output            laeuft
);

//////////////////////////////  Register  ///////////////////////////////////

reg [23:0] liste;
reg  [1:0] steuer;
reg        irq_st;
reg [15:0] befehle, befehle_letzt;

//////////////////////////////  Strahl  /////////////////////////////////////

// Copper-Zeile springt wie die Rasterzeile zu Beginn der Austastluecke;
// Copper-Punkt zaehlt ab dort (0-123 Austastluecke, ab 124 sichtbar)
wire [8:0] v_next = (vc == v_last) ? 9'd0 : vc + 9'd1;
wire       hbl    = (hc >= 10'd640);
wire [8:0] cz     = hbl ? v_next : vc;
wire [9:0] cp     = hbl ? hc - 10'd640 : hc + 10'd124;

function automatic [8:0] ord(input [8:0] z, input [8:0] last);
	ord = (z >= 9'd240) ? z - 9'd240 : z + last + 9'd1 - 9'd240;
endfunction

wire [18:0] pos      = {ord(cz, v_last), cp};
wire        neustart = ce_pix && hc == 10'd639 && v_next == 9'd240;

//////////////////////////////  Vorab holen  ////////////////////////////////

localparam [2:0] L_AUS = 3'd0, L_LAUF = 3'd1, L_WARTE = 3'd2, L_SETZE = 3'd3,
                 L_WKRAN = 3'd4, L_ENDE = 3'd5, L_LEEREN = 3'd6;

reg  [2:0] st;
reg [17:0] fp;                      // naechste Leseadresse
reg [17:0] fp_neu;                  // nach dem Leeren
reg  [7:0] fifo [0:7];
reg  [2:0] wp, rp;
reg  [3:0] cnt;

wire holen = (st == L_LAUF || st == L_WARTE || st == L_SETZE || st == L_WKRAN);
assign mem_req  = holen && (cnt + {3'd0, mem_ack} < 4'd8);
assign mem_addr = fp;

wire [7:0] b0 = fifo[rp];
wire [7:0] b1 = fifo[rp + 3'd1];
wire [7:0] b2 = fifo[rp + 3'd2];
wire [7:0] b3 = fifo[rp + 3'd3];

//////////////////////////////  Ausfuehren  /////////////////////////////////

reg [18:0] ziel;
reg [10:0] w_addr;
reg  [7:0] w_dat;

assign io_req  = (st == L_SETZE);
assign io_addr = w_addr;
assign io_dat  = w_dat;
assign laeuft  = (st != L_AUS && st != L_ENDE);

wire       nimm   = (st == L_LAUF) && (cnt >= 4'd4);
wire [8:0] w_zl   = {b2[0], b1};
wire [8:0] w_x    = {b2[1], b3};
wire       w_seite_ok = (b2[7:3] == 5'b11000) && (b2[2:0] != 3'd2);

always @(posedge clk) begin
	// Daten aus dem RAM einreihen (ausser beim Leeren)
	if (mem_gnt) fp <= fp + 18'd1;
	if (mem_ack && st != L_LEEREN) begin
		fifo[wp] <= mem_q;
		wp       <= wp + 3'd1;
	end
	cnt <= cnt + {3'd0, mem_ack && st != L_LEEREN} - (nimm ? 4'd4 : 4'd0);
	if (nimm) begin
		rp      <= rp + 3'd4;
		befehle <= befehle + 16'd1;
	end

	case (st)
		L_LAUF: if (nimm) begin
			case (b0)
				8'h00: st <= L_ENDE;
				8'h01: begin
					ziel <= {ord(w_zl, v_last), (w_x == 9'h1FF) ? 10'd0 : 10'd124 + {w_x, 1'b0}};
					st   <= L_WARTE;
				end
				8'h02: if (w_seite_ok) begin
					w_addr <= {b2[2:0], b1};
					w_dat  <= b3;
					st     <= L_SETZE;
				end
				8'h03: begin
					fp_neu <= {b3[1:0], b2, b1};
					st     <= L_LEEREN;
				end
				8'h04: if (steuer[1]) irq_st <= 1'b1;
				8'h05: st <= L_WKRAN;
				default: ;
			endcase
		end
		L_WARTE: if (pos >= ziel) st <= L_LAUF;
		L_SETZE: if (io_gnt) st <= L_LAUF;
		L_WKRAN: if (!kran_busy) st <= L_LAUF;
		L_LEEREN: begin                    // kein Lesen in diesem Takt; FIFO leer
			fp  <= fp_neu;
			wp  <= 3'd0;
			rp  <= 3'd0;
			cnt <= 4'd0;
			st  <= L_LAUF;
		end
		default: ;
	endcase

	// Neues Bild: von vorn bei LISTE
	if (neustart) begin
		befehle_letzt <= befehle;
		befehle       <= 16'd0;
		if (steuer[0]) begin
			fp_neu <= liste[17:0];
			st     <= L_LEEREN;
		end
	end
	if (!steuer[0]) st <= L_AUS;

	// Register
	if (reg_we) begin
		case (reg_addr)
			8'h00: liste[7:0]   <= reg_din;
			8'h01: liste[15:8]  <= reg_din;
			8'h02: liste[23:16] <= reg_din;
			8'h03: steuer       <= reg_din[1:0];
			8'h04: if (reg_din[0]) irq_st <= 1'b0;
			default: ;
		endcase
	end
	if (reset) begin
		st     <= L_AUS;
		steuer <= 2'd0;
		irq_st <= 1'b0;
		cnt    <= 4'd0;
		wp     <= 3'd0;
		rp     <= 3'd0;
	end
end

assign irq = irq_st;

always @* begin
	case (reg_addr)
		8'h00:   reg_dout = liste[7:0];
		8'h01:   reg_dout = liste[15:8];
		8'h02:   reg_dout = liste[23:16];
		8'h03:   reg_dout = {6'd0, steuer};
		8'h04:   reg_dout = {5'd0, st == L_WARTE, laeuft, irq_st};
		8'h05:   reg_dout = befehle_letzt[7:0];
		8'h06:   reg_dout = befehle_letzt[15:8];
		default: reg_dout = 8'hFF;
	endcase
end

endmodule
