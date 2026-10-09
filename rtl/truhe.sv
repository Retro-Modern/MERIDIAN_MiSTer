//============================================================================
//  TRUHE - Laufwerke des MERIDIAN (Etappe 10)
//
//  Bindet Image-Dateien auf der SD-Karte des MiSTer als Blockgeraete an
//  (512 Byte je Block, lesen und schreiben). Das Rahmenwerk (hps_io) haengt
//  die Images ein, die im Menue gewaehlt werden:
//    Laufwerk 0  Speicherstand eines Moduls (legt der MiSTer selbst an)
//    Laufwerk 1  Diskette oder Platte
//    Laufwerk 2  Diskette oder Platte
//
//  Die CPU schreibt Laufwerk und Blocknummer, gibt den Befehl und wartet,
//  bis TRUHE nicht mehr arbeitet. Der Puffer fasst 8 KB = 16 Seiten zu je
//  einem Block; die CPU sieht die gewaehlte Seite bei $00:CA00-$00:CBFF.
//  Ein Auftrag kann bis zu 16 Bloecke umfassen (ANZAHL) und beginnt bei der
//  gewaehlten Seite. Das lohnt sich: Der MiSTer schreibt jeden Auftrag
//  sofort fest auf die SD-Karte (O_SYNC) - 15 Bloecke auf einmal kosten
//  kaum mehr Zeit als einer.
//
//  Register ab $00:C900:
//   $00 BEFEHL  schreiben: 1 Block lesen (Image -> Puffer),
//                          2 Block schreiben (Puffer -> Image)
//       STATUS  lesen: Bit 0 arbeitet, Bit 1 Fehler (kein Image,
//               schreibgeschuetzt)
//   $01 LAUFWERK 0-2
//   $02-$05 BLOCK   Blocknummer (32 Bit)
//   $06 EINGELEGT  lesen: Bit n = Image in Laufwerk n, Bit 4+n = nur lesen
//   $07 WECHSEL    lesen: Bit n = Image n neu eingehaengt; 1 schreiben loescht
//   $08-$0B BLOECKE  Groesse des Images im gewaehlten Laufwerk (Bloecke)
//   $0C SEITE   Seite des Puffers (0-15): bei $CA00 sichtbar, erste des
//               naechsten Auftrags
//   $0D ANZAHL  Bloecke je Auftrag (1-16)
//
//  Seit MERIDIAN 1.0 laeuft hps_io mit 16 Bit Breite (WIDE): Das Rahmenwerk
//  schreibt und liest den Puffer wortweise (kleines Byte zuerst), die CPU
//  weiter byteweise - doppelter Durchsatz zwischen ARM und FPGA.
//
//  Parameter WIDE (Vorgabe 1, MiSTer): 0 schaltet auf den 8-Bit-Pfad mit
//  14 Adressbits, wie ihn MiSTer2MEGA65 (vdrives) kann. Dort laeuft die
//  Seite des Rahmenwerks (sd_rd/sd_wr/sd_ack, sd_buff_*) im Takt clk_sd
//  (QNICE, 50 MHz): Der Puffer hat dann zwei Ports in zwei Takten (CPU und
//  Rahmenwerk), Anfrage und Antwort laufen ueber Synchronisierstufen.
//  Mit WIDE = 1 ist clk_sd unbenutzt.
//============================================================================

module truhe
#(
	parameter WIDE = 1                  // 1: 16 Bit (MiSTer hps_io), 0: 8 Bit (MEGA65)
)
(
	input             clk,
	input             clk_sd,           // Takt des Rahmenwerks (nur WIDE = 0)
	input             reset,

	// CPU: Register ($C900) und Puffer ($CA00)
	input       [8:0] adr,
	input             sel_reg,
	input             sel_puf,
	input             we,
	input       [7:0] din,
	output reg  [7:0] dout,

	// Rahmenwerk (hps_io), drei Images
	input       [2:0] img_mounted,
	input             img_readonly,
	input      [63:0] img_size,
	output     [31:0] sd_lba,
	output      [5:0] sd_blk_cnt,
	output      [2:0] sd_rd,
	output      [2:0] sd_wr,
	input       [2:0] sd_ack,
	input  [(WIDE ? 12 : 13):0] sd_buff_addr,   // WIDE: Wortadresse, sonst Byte
	input  [(WIDE ? 15 :  7):0] sd_buff_dout,
	output [(WIDE ? 15 :  7):0] sd_buff_din,
	input             sd_buff_wr
);

reg  [1:0] laufwerk;
reg [31:0] block;
reg  [3:0] seite, basis;            // CPU-Fenster / erste Seite des Auftrags
reg  [3:0] anzahl_m1;               // Bloecke je Auftrag - 1
// Eingehaengte Images meldet das Rahmenwerk nur einmal - diese Merker
// ueberstehen deshalb jeden Reset (nur beim Einschalten 0)
reg  [2:0] eingelegt = 3'd0, schreibschutz = 3'd0, wechsel = 3'd0;
reg [31:0] bloecke [0:2];
reg        arbeitet, fehler, ack_war;
reg  [2:0] lese_anf, schreib_anf;   // Anfrage an das Rahmenwerk
wire [2:0] ack;                     // seine Antwort im Takt clk
wire [7:0] puf_q;                   // Puffer, Byte fuer die CPU

assign sd_lba     = block;
assign sd_blk_cnt = {2'b00, anzahl_m1};

generate if (WIDE) begin : breit

// Puffer, 8 KB als zwei Haelften (gerade und ungerade Bytes) mit je einem
// Port: Solange ein Auftrag laeuft, gehoeren sie dem Rahmenwerk (ein Wort
// je Zugriff), sonst der CPU (ein Byte; waehrenddessen liest sie nur
// STATUS). Zwei Schreibports legte Quartus nicht in M10K-Bloecke, sondern
// baute den Puffer aus Logik. Beim Schreiben liefert der Port die neuen
// Daten.
reg  [7:0] puf_g [0:4095];
reg  [7:0] puf_u [0:4095];
reg  [7:0] q_g, q_u;
reg        q_ungerade;              // die CPU las ein ungerades Byte
wire [11:0] p_adr  = arbeitet ? {basis + sd_buff_addr[11:8], sd_buff_addr[7:0]} : {seite, adr[8:1]};
wire        p_hps  = sd_buff_wr && (|sd_ack);
wire        p_we_g = arbeitet ? p_hps : (we && sel_puf && !adr[0]);
wire        p_we_u = arbeitet ? p_hps : (we && sel_puf &&  adr[0]);
wire  [7:0] din_g  = arbeitet ? sd_buff_dout[7:0]  : din;
wire  [7:0] din_u  = arbeitet ? sd_buff_dout[15:8] : din;

always @(posedge clk) begin
	if (p_we_g) begin
		puf_g[p_adr] <= din_g;
		q_g          <= din_g;
	end
	else q_g <= puf_g[p_adr];
	if (p_we_u) begin
		puf_u[p_adr] <= din_u;
		q_u          <= din_u;
	end
	else q_u <= puf_u[p_adr];
	q_ungerade <= adr[0];
end
assign sd_buff_din = {q_u, q_g};
assign puf_q       = q_ungerade ? q_u : q_g;
assign ack         = sd_ack;
assign sd_rd       = lese_anf;
assign sd_wr       = schreib_anf;

end else begin : schmal

// 8 Bit (MEGA65): Puffer mit zwei Ports - A fuer die CPU (clk), B fuer das
// Rahmenwerk (clk_sd, Byteadresse). Beim Schreiben liefern beide Ports die
// neuen Daten. Die Anfrage geht ueber zwei Stufen nach clk_sd, die Antwort
// (sd_ack) ueber zwei Stufen nach clk. Block, Anzahl und erste Seite stehen
// fest, bevor die Anfrage drueben ankommt; die Seite geht wie die Anfrage
// ueber zwei Stufen.
reg  [7:0] puffer [0:8191];
reg  [7:0] q_a, q_b;
(* ASYNC_REG = "TRUE" *) reg [3:0] basis_s1, basis_s2;
always @(posedge clk_sd) begin
	basis_s1 <= basis;
	basis_s2 <= basis_s1;
end
wire [12:0] a_adr = {seite, adr};
wire [12:0] b_adr = {basis_s2 + sd_buff_addr[12:9], sd_buff_addr[8:0]};
wire        a_we  = we && sel_puf;
wire        b_we  = sd_buff_wr && (|sd_ack);

always @(posedge clk) begin
	if (a_we) begin
		puffer[a_adr] <= din;
		q_a           <= din;
	end
	else q_a <= puffer[a_adr];
end
always @(posedge clk_sd) begin
	if (b_we) begin
		puffer[b_adr] <= sd_buff_dout;
		q_b           <= sd_buff_dout;
	end
	else q_b <= puffer[b_adr];
end
assign sd_buff_din = q_b;
assign puf_q       = q_a;

(* ASYNC_REG = "TRUE" *) reg [2:0] ack_s1, ack_s2;
always @(posedge clk) begin
	ack_s1 <= sd_ack;
	ack_s2 <= ack_s1;
end
assign ack = ack_s2;

(* ASYNC_REG = "TRUE" *) reg [5:0] anf_s1, anf_s2;
always @(posedge clk_sd) begin
	anf_s1 <= {schreib_anf, lese_anf};
	anf_s2 <= anf_s1;
end
assign sd_rd = anf_s2[2:0];
assign sd_wr = anf_s2[5:3];

end endgenerate

wire [2:0] lw_bit = 3'b001 << laufwerk;

always @(posedge clk) begin
	// eingehaengte Images merken
	if (img_mounted[0] | img_mounted[1] | img_mounted[2]) begin
		eingelegt     <= (eingelegt & ~img_mounted) | (img_size != 64'd0 || img_mounted[0] ? img_mounted : 3'd0);
		schreibschutz <= (schreibschutz & ~img_mounted) | (img_readonly ? img_mounted : 3'd0);
		wechsel       <= wechsel | img_mounted;
		if (img_mounted[0]) bloecke[0] <= img_size[40:9];
		if (img_mounted[1]) bloecke[1] <= img_size[40:9];
		if (img_mounted[2]) bloecke[2] <= img_size[40:9];
	end

	// laufender Auftrag: Anfrage halten, bis das Rahmenwerk antwortet,
	// fertig, wenn seine Antwort endet
	ack_war <= |(ack & lw_bit);
	if (ack & lw_bit) begin
		lese_anf    <= 3'd0;
		schreib_anf <= 3'd0;
	end
	if (arbeitet && ack_war && !(ack & lw_bit)) arbeitet <= 1'b0;

	if (we && sel_reg) begin
		case (adr[3:0])
			4'h0: if (!arbeitet) begin
				if (!(eingelegt & lw_bit) || (din[1] && (schreibschutz & lw_bit)))
					fehler <= 1'b1;
				else if (din[0] || din[1]) begin
					fehler   <= 1'b0;
					arbeitet <= 1'b1;
					basis    <= seite;
					if (din[0]) lese_anf    <= lw_bit;
					else        schreib_anf <= lw_bit;
				end
			end
			4'h1: if (!arbeitet) laufwerk <= (din[1:0] == 2'd3) ? 2'd2 : din[1:0];
			4'h2: if (!arbeitet) block[7:0]   <= din;
			4'h3: if (!arbeitet) block[15:8]  <= din;
			4'h4: if (!arbeitet) block[23:16] <= din;
			4'h5: if (!arbeitet) block[31:24] <= din;
			4'h7: wechsel <= wechsel & ~din[2:0];
			4'hC: if (!arbeitet) seite <= din[3:0];
			4'hD: if (!arbeitet) anzahl_m1 <= (din == 8'd0) ? 4'd0 : (din > 8'd16) ? 4'd15 : din[3:0] - 4'd1;
			default: ;
		endcase
	end

	if (reset) begin
		lese_anf    <= 3'd0;
		schreib_anf <= 3'd0;
		arbeitet  <= 1'b0;
		fehler    <= 1'b0;
		laufwerk  <= 2'd1;
		seite     <= 4'd0;
		basis     <= 4'd0;
		anzahl_m1 <= 4'd0;
	end
end

wire [31:0] groesse = bloecke[laufwerk];

always @* begin
	if (sel_puf) dout = puf_q;
	else case (adr[3:0])
		4'h0: dout = {6'd0, fehler, arbeitet};
		4'h1: dout = {6'd0, laufwerk};
		4'h2: dout = block[7:0];
		4'h3: dout = block[15:8];
		4'h4: dout = block[23:16];
		4'h5: dout = block[31:24];
		4'h6: dout = {1'b0, schreibschutz, 1'b0, eingelegt};
		4'h7: dout = {5'd0, wechsel};
		4'h8: dout = groesse[7:0];
		4'h9: dout = groesse[15:8];
		4'hA: dout = groesse[23:16];
		4'hB: dout = groesse[31:24];
		4'hC: dout = {4'd0, seite};
		4'hD: dout = {3'd0, {1'b0, anzahl_m1} + 5'd1};
		default: dout = 8'hFF;
	endcase
end

endmodule
