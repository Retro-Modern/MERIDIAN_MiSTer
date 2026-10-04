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
//============================================================================

module truhe
(
	input             clk,
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
	output reg  [2:0] sd_rd,
	output reg  [2:0] sd_wr,
	input       [2:0] sd_ack,
	input      [13:0] sd_buff_addr,
	input       [7:0] sd_buff_dout,
	output      [7:0] sd_buff_din,
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

assign sd_lba     = block;
assign sd_blk_cnt = {2'b00, anzahl_m1};

// Puffer, 8 KB mit einem einzigen Port: Solange ein Auftrag laeuft, gehoert
// er dem Rahmenwerk, sonst der CPU (die waehrenddessen nur STATUS liest).
// Zwei Schreibports legte Quartus nicht in M10K-Bloecke, sondern baute den
// Puffer aus Logik. Beim Schreiben liefert der Port die neuen Daten.
reg  [7:0] puffer [0:8191];
reg  [7:0] puf_q;
wire [12:0] p_adr = arbeitet ? {basis + sd_buff_addr[12:9], sd_buff_addr[8:0]} : {seite, adr};
wire        p_we  = arbeitet ? (sd_buff_wr && (|sd_ack)) : (we && sel_puf);
wire  [7:0] p_din = arbeitet ? sd_buff_dout : din;

always @(posedge clk) begin
	if (p_we) begin
		puffer[p_adr] <= p_din;
		puf_q         <= p_din;
	end
	else puf_q <= puffer[p_adr];
end
assign sd_buff_din = puf_q;

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
	ack_war <= |(sd_ack & lw_bit);
	if (sd_ack & lw_bit) begin
		sd_rd <= 3'd0;
		sd_wr <= 3'd0;
	end
	if (arbeitet && ack_war && !(sd_ack & lw_bit)) arbeitet <= 1'b0;

	if (we && sel_reg) begin
		case (adr[3:0])
			4'h0: if (!arbeitet) begin
				if (!(eingelegt & lw_bit) || (din[1] && (schreibschutz & lw_bit)))
					fehler <= 1'b1;
				else if (din[0] || din[1]) begin
					fehler   <= 1'b0;
					arbeitet <= 1'b1;
					basis    <= seite;
					if (din[0]) sd_rd <= lw_bit;
					else        sd_wr <= lw_bit;
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
		sd_rd     <= 3'd0;
		sd_wr     <= 3'd0;
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
