//============================================================================
//  KRAN - Blitter des MERIDIAN (Etappe 7, Zusatzspeicher seit Etappe 9)
//
//  Bewegt rechteckige Speicherbloecke im Chip-RAM und im Zusatzspeicher
//  (SDRAM, Baenke $04-$FE), waehrend die CPU weiterarbeitet: kopieren, fuellen, kopieren mit Durchsicht (ein Farbwert wird
//  uebersprungen, ganzes Byte oder je Halbbyte fuer Bitmap 16). Ein Auftrag
//  beschreibt ein Rechteck: Breite in Bytes, Hoehe in Zeilen und fuer
//  Quelle und Ziel den Abstand von Zeile zu Zeile (mit Vorzeichen, also
//  auch rueckwaerts nach oben).
//
//  KRAN kann einzelne Auftraege ausfuehren (Register setzen, starten) oder
//  eine ganze Auftragsliste im Speicher abarbeiten: Jeder Auftrag sind
//  16 Byte im selben Aufbau wie die Register $00-$0F; im letzten ist Bit 7
//  von MODUS gesetzt.
//
//  Alle Adressen haben 24 Bit. Baenke $00-$03 sind Chip-RAM, ab $04 der
//  Zusatzspeicher - Quelle, Ziel und Auftragsliste duerfen ueberall liegen.
//  Der Speicher antwortet unterschiedlich schnell; KRAN wartet beim Lesen
//  immer auf die Fertigmeldung (mem_ack).
//
//  Register ab $00:C600:
//   $00-$02 QUELLE      $03-$05 ZIEL
//   $06/$07 BREITE (Bytes)   $08/$09 HOEHE (Zeilen)
//   $0A/$0B Q_ABSTAND   $0C/$0D Z_ABSTAND (je 16 Bit mit Vorzeichen)
//   $0E     WERT        Fuellwert bzw. durchsichtiger Farbwert
//   $0F     MODUS       Bits 0-1: 0 kopieren, 1 fuellen, 2 kopieren ohne
//                       Bytes = WERT, 3 kopieren ohne Halbbytes = WERT
//                       (Bits 0-3); Bit 2: Zeile rueckwaerts (von rechts);
//                       Bit 7: letzter Auftrag der Liste
//   $10     BEFEHL      schreiben: Bit 0 Auftrag aus den Registern starten,
//                       Bit 1 Auftragsliste ab LISTE starten, Bit 2 abbrechen,
//                       Bit 3 Fertig-Meldung loeschen
//           STATUS      lesen: Bit 0 arbeitet, Bit 1 fertig gemeldet
//   $11-$13 LISTE       Adresse der Auftragsliste
//   $14     STEUER      Bit 0: Interrupt, wenn fertig
//  Start, waehrend KRAN arbeitet, wird ignoriert.
//============================================================================

module kran
(
	input             clk,
	input             reset,

	input       [7:0] reg_addr,
	input       [7:0] reg_din,
	output reg  [7:0] reg_dout,
	input             reg_we,
	output            irq,

	// Speicher: gnt, wenn der Zugriff angenommen ist; beim Lesen ack mit mem_q
	// (Chip-RAM einen Takt spaeter, Zusatzspeicher einige Takte spaeter)
	output            mem_req,
	output reg [23:0] mem_addr,
	output            mem_we,
	output      [7:0] mem_wdat,
	input             mem_gnt,
	input             mem_ack,
	input       [7:0] mem_q,

	output            busy
);

//////////////////////////////  Register  ///////////////////////////////////

reg  [7:0] r [0:15];                // Auftrag in den Registern $00-$0F
reg [23:0] r_liste;
reg        r_steuer;
reg        irq_st;

//////////////////////////////  Ablauf  /////////////////////////////////////

localparam [3:0] K_RUHE = 4'd0, K_LADEN = 4'd1, K_START = 4'd2, K_LIES = 4'd3,
                 K_LIESW = 4'd4, K_LIESZ = 4'd5, K_LIESZW = 4'd6, K_SCHREIB = 4'd7;

reg  [3:0] st;
reg  [7:0] jb [0:15];               // laufender Auftrag
reg        liste_an;
reg [23:0] lp;
reg  [4:0] n_req, n_ack;

reg [23:0] s_ptr, d_ptr, s_zeile, d_zeile;
reg [15:0] x_rest, y_rest;
reg  [7:0] w, src;

wire [15:0] j_breite = {jb[7], jb[6]};
wire [15:0] j_hoehe  = {jb[9], jb[8]};
wire [23:0] j_qa     = {{8{jb[11][7]}}, jb[11], jb[10]};
wire [23:0] j_za     = {{8{jb[13][7]}}, jb[13], jb[12]};
wire  [7:0] j_wert   = jb[14];
wire  [1:0] j_art    = jb[15][1:0];
wire        j_rueck  = jb[15][2];
wire        j_letzt  = jb[15][7];
wire [23:0] schritt  = j_rueck ? 24'hFFFFFF : 24'd1;

// Halbbytes der Quelle durchsichtig?
wire        t_hi = (mem_q[7:4] == j_wert[3:0]);
wire        t_lo = (mem_q[3:0] == j_wert[3:0]);

assign busy     = (st != K_RUHE);
assign mem_req  = (st == K_LADEN && n_req != 5'd16) || st == K_LIES || st == K_LIESZ || st == K_SCHREIB;
assign mem_we   = (st == K_SCHREIB);
assign mem_wdat = w;
assign irq      = irq_st;

always @* begin
	case (st)
		K_LADEN: mem_addr = lp;
		K_LIES:  mem_addr = s_ptr;
		default: mem_addr = d_ptr;
	endcase
end

integer i;
always @(posedge clk) begin
	case (st)
		K_LADEN: begin
			if (mem_gnt) begin
				lp    <= lp + 24'd1;
				n_req <= n_req + 5'd1;
			end
			if (mem_ack) begin
				jb[n_ack[3:0]] <= mem_q;
				n_ack <= n_ack + 5'd1;
				if (n_ack == 5'd15) st <= K_START;
			end
		end
		K_START: begin
			s_ptr   <= {jb[2], jb[1], jb[0]};
			s_zeile <= {jb[2], jb[1], jb[0]};
			d_ptr   <= {jb[5], jb[4], jb[3]};
			d_zeile <= {jb[5], jb[4], jb[3]};
			x_rest  <= j_breite;
			y_rest  <= j_hoehe;
			w       <= j_wert;
			if (j_breite == 16'd0 || j_hoehe == 16'd0) fertig();
			else st <= (j_art == 2'd1) ? K_SCHREIB : K_LIES;
		end
		K_LIES: if (mem_gnt) st <= K_LIESW;
		K_LIESW: if (mem_ack) begin
			case (j_art)
				2'd2: begin
					w <= mem_q;
					if (mem_q == j_wert) weiter();
					else st <= K_SCHREIB;
				end
				2'd3: begin
					w   <= mem_q;
					src <= mem_q;
					if (t_hi && t_lo) weiter();
					else if (!t_hi && !t_lo) st <= K_SCHREIB;
					else st <= K_LIESZ;
				end
				default: begin
					w  <= mem_q;
					st <= K_SCHREIB;
				end
			endcase
		end
		K_LIESZ: if (mem_gnt) st <= K_LIESZW;
		K_LIESZW: if (mem_ack) begin          // Ziel lesen, Halbbytes mischen
			w  <= {(src[7:4] == j_wert[3:0]) ? mem_q[7:4] : src[7:4],
			       (src[3:0] == j_wert[3:0]) ? mem_q[3:0] : src[3:0]};
			st <= K_SCHREIB;
		end
		K_SCHREIB: if (mem_gnt) weiter();
		default: ;
	endcase

	// Register und Befehle
	if (reg_we) begin
		if (reg_addr[7:4] == 4'h0) r[reg_addr[3:0]] <= reg_din;
		case (reg_addr)
			8'h10: begin
				if (reg_din[3]) irq_st <= 1'b0;
				if (reg_din[2]) st <= K_RUHE;
				else if (st == K_RUHE) begin
					if (reg_din[0]) begin
						for (i = 0; i < 16; i = i + 1) jb[i] <= r[i];
						liste_an <= 1'b0;
						st       <= K_START;
					end
					else if (reg_din[1]) begin
						lp       <= r_liste;
						n_req    <= 5'd0;
						n_ack    <= 5'd0;
						liste_an <= 1'b1;
						st       <= K_LADEN;
					end
				end
			end
			8'h11: r_liste[7:0]   <= reg_din;
			8'h12: r_liste[15:8]  <= reg_din;
			8'h13: r_liste[23:16] <= reg_din;
			8'h14: r_steuer       <= reg_din[0];
			default: ;
		endcase
	end
	if (reset) begin
		st       <= K_RUHE;
		irq_st   <= 1'b0;
		r_steuer <= 1'b0;
	end
end

// Naechstes Byte, naechste Zeile oder Auftrag fertig
task weiter;
	begin
		if (x_rest == 16'd1) begin
			if (y_rest == 16'd1) fertig();
			else begin
				y_rest  <= y_rest - 16'd1;
				x_rest  <= j_breite;
				s_zeile <= s_zeile + j_qa;
				d_zeile <= d_zeile + j_za;
				s_ptr   <= s_zeile + j_qa;
				d_ptr   <= d_zeile + j_za;
				st      <= (j_art == 2'd1) ? K_SCHREIB : K_LIES;
			end
		end
		else begin
			x_rest <= x_rest - 16'd1;
			s_ptr  <= s_ptr + schritt;
			d_ptr  <= d_ptr + schritt;
			st     <= (j_art == 2'd1) ? K_SCHREIB : K_LIES;
		end
	end
endtask

task fertig;
	begin
		if (liste_an && !j_letzt) begin
			n_req <= 5'd0;
			n_ack <= 5'd0;
			st    <= K_LADEN;
		end
		else begin
			st <= K_RUHE;
			if (r_steuer) irq_st <= 1'b1;
		end
	end
endtask

always @* begin
	if (reg_addr[7:4] == 4'h0) reg_dout = r[reg_addr[3:0]];
	else case (reg_addr)
		8'h10:   reg_dout = {6'd0, irq_st, busy};
		8'h11:   reg_dout = r_liste[7:0];
		8'h12:   reg_dout = r_liste[15:8];
		8'h13:   reg_dout = r_liste[23:16];
		8'h14:   reg_dout = {7'd0, r_steuer};
		default: reg_dout = 8'hFF;
	endcase
end

endmodule
