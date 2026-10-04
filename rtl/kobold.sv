//============================================================================
//  KOBOLD - Sprite-Einheit des MERIDIAN (Etappe 5), sitzt in PINSEL
//
//  32 Sprites zu 16x16 Pixeln, 16 Farben (Palettenbank je Sprite), spiegelbar,
//  auf Wunsch doppelt gross (32x32), vor oder hinter Ebene B. Keine Grenze
//  pro Zeile: alle 32 duerfen auf derselben Zeile stehen.
//
//  KOBOLD hat seinen eigenen Musterspeicher (16 KB = 128 Muster, 64 Bit
//  breit: eine Sprite-Zeile pro Takt) und rendert parallel zu den Ebenen in
//  einen eigenen Zeilenpuffer. Er braucht deshalb keine Zugriffe auf das
//  Chip-RAM. Sprite 0 liegt vorn, Sprite 31 hinten.
//
//  Sprite-Tabelle ab $00:C300, 8 Byte je Sprite (n = 0..31):
//   +0/+1  X (9 Bit), Bildschirm-X = X - 32 (X 16..31 ragt links hinaus)
//   +2/+3  Y (9 Bit), Bildschirm-Y = Y - 32
//   +4     Muster 0-127
//   +5     Bits 0-3 Palettenbank, 4 spiegeln X, 5 spiegeln Y,
//          6 hinter Ebene B, 7 doppelt gross
//   +6     Bit 0: an
//  Steuerung ab $00:C400:
//   $00/$01 MADR    Byte-Adresse im Musterspeicher (14 Bit)
//   $02     MDATEN  schreiben: Byte ablegen, MADR zaehlt weiter
//   $03     STEUER  Bit 0: Sprites an
//   $04-$07 KOLL    Bit n: Sprite n hat einen anderen beruehrt (Lesen);
//                   Schreiben auf $04 loescht alle
//  Muster: 16 Zeilen zu 8 Byte, linkes Pixel im oberen Halbbyte, 0 = durchsichtig.
//============================================================================

module kobold
(
	input             clk,
	input             reset,

	// CPU: a[8] = 0 Sprite-Tabelle ($C3xx), 1 Steuerung ($C4xx)
	input       [8:0] reg_addr,
	input       [7:0] reg_din,
	output reg  [7:0] reg_dout,
	input             reg_we,

	// Zeilensteuerung aus PINSEL
	input             start,          // naechste Zeile rendern
	input       [8:0] zeile,          // diese Zeile (0..239)
	input             puffer,         // in diesen Puffer schreiben

	// Ausgabe: Lesen fuer die angezeigte Zeile
	input       [9:0] aus_addr,       // {Puffer, Eintrag}
	output            aus_gueltig,
	output      [7:0] aus_farbe,
	output            aus_hinten
);

//////////////////////////////  Sprite-Tabelle  /////////////////////////////

reg  [8:0] sp_x   [0:31];
reg  [8:0] sp_y   [0:31];
reg  [6:0] sp_m   [0:31];
reg  [7:0] sp_att [0:31];
reg        sp_an  [0:31];

reg [13:0] madr;
reg        an;
reg [31:0] koll;

wire [4:0] cs = reg_addr[7:3];

always @* begin
	if (!reg_addr[8]) begin
		case (reg_addr[2:0])
			3'd0: reg_dout = sp_x[cs][7:0];
			3'd1: reg_dout = {7'd0, sp_x[cs][8]};
			3'd2: reg_dout = sp_y[cs][7:0];
			3'd3: reg_dout = {7'd0, sp_y[cs][8]};
			3'd4: reg_dout = {1'b0, sp_m[cs]};
			3'd5: reg_dout = sp_att[cs];
			3'd6: reg_dout = {7'd0, sp_an[cs]};
			default: reg_dout = 8'h00;
		endcase
	end
	else begin
		case (reg_addr[7:0])
			8'h00: reg_dout = madr[7:0];
			8'h01: reg_dout = {2'd0, madr[13:8]};
			8'h03: reg_dout = {7'd0, an};
			8'h04: reg_dout = koll[7:0];
			8'h05: reg_dout = koll[15:8];
			8'h06: reg_dout = koll[23:16];
			8'h07: reg_dout = koll[31:24];
			default: reg_dout = 8'hFF;
		endcase
	end
end

//////////////////////////////  Musterspeicher  /////////////////////////////

// Acht Bytebahnen zu 2048 Byte: zusammen eine 64-Bit-Zeile pro Takt
reg  [7:0] mb0 [0:2047], mb1 [0:2047], mb2 [0:2047], mb3 [0:2047];
reg  [7:0] mb4 [0:2047], mb5 [0:2047], mb6 [0:2047], mb7 [0:2047];
reg [10:0] m_raddr;
reg [63:0] m_q;
wire       m_we = reg_we && reg_addr == 9'h102;
wire [10:0] m_waddr = madr[13:3];

always @(posedge clk) begin
	if (m_we && madr[2:0] == 3'd0) mb0[m_waddr] <= reg_din;
	if (m_we && madr[2:0] == 3'd1) mb1[m_waddr] <= reg_din;
	if (m_we && madr[2:0] == 3'd2) mb2[m_waddr] <= reg_din;
	if (m_we && madr[2:0] == 3'd3) mb3[m_waddr] <= reg_din;
	if (m_we && madr[2:0] == 3'd4) mb4[m_waddr] <= reg_din;
	if (m_we && madr[2:0] == 3'd5) mb5[m_waddr] <= reg_din;
	if (m_we && madr[2:0] == 3'd6) mb6[m_waddr] <= reg_din;
	if (m_we && madr[2:0] == 3'd7) mb7[m_waddr] <= reg_din;
	m_q <= {mb0[m_raddr], mb1[m_raddr], mb2[m_raddr], mb3[m_raddr],
	        mb4[m_raddr], mb5[m_raddr], mb6[m_raddr], mb7[m_raddr]};
end

//////////////////////////////  Zeilenpuffer  ///////////////////////////////

// Eintrag: Farbe (8), hinter Ebene B (1). Ob ein Eintrag fuer die Zeile gilt,
// sagt das Belegt-Register des Puffers (320 Bit): Es wird beim Zeilenstart in
// einem Takt geloescht, der RAM-Puffer selbst muss nie geloescht werden.
reg  [8:0] spuf [0:1023];
reg        s_we;
reg  [9:0] s_waddr;
reg  [8:0] s_wdata;
reg  [8:0] s_q;
reg        s_beleg;
reg [319:0] beleg0, beleg1;
always @(posedge clk) begin
	if (s_we) spuf[s_waddr] <= s_wdata;
	s_q     <= spuf[aus_addr];
	s_beleg <= aus_addr[9] ? beleg1[aus_addr[8:0]] : beleg0[aus_addr[8:0]];
end
assign aus_gueltig = s_beleg && (s_q[7:0] != 8'd0);
assign aus_farbe   = s_q[7:0];
assign aus_hinten  = s_q[8];

//////////////////////////////  CPU-Schreibzugriffe  ////////////////////////

always @(posedge clk) begin
	if (reg_we && !reg_addr[8]) begin
		case (reg_addr[2:0])
			3'd0: sp_x[cs][7:0] <= reg_din;
			3'd1: sp_x[cs][8]   <= reg_din[0];
			3'd2: sp_y[cs][7:0] <= reg_din;
			3'd3: sp_y[cs][8]   <= reg_din[0];
			3'd4: sp_m[cs]      <= reg_din[6:0];
			3'd5: sp_att[cs]    <= reg_din;
			3'd6: sp_an[cs]     <= reg_din[0];
			default: ;
		endcase
	end
	if (reg_we && reg_addr[8]) begin
		case (reg_addr[7:0])
			8'h00: madr[7:0]  <= reg_din;
			8'h01: madr[13:8] <= reg_din[5:0];
			8'h02: madr       <= madr + 14'd1;
			8'h03: an         <= reg_din[0];
			default: ;
		endcase
	end
	if (reset) an <= 1'b0;
end

//////////////////////////////  Renderer  ///////////////////////////////////

localparam [2:0] K_RUHE = 3'd0, K_PRUEF = 3'd1, K_WARTE1 = 3'd2, K_WARTE2 = 3'd3,
                 K_MALEN = 3'd4;

reg  [2:0] k_st;
reg  [4:0] k_s;                    // aktueller Sprite
reg  [5:0] k_px;                   // Pixel in der Spritezeile (0..31)
reg  [8:0] k_zeile;
reg        k_puf;
reg [63:0] k_reihe;                // Musterzeile
reg  [4:0] wer [0:319];            // welcher Sprite dort sitzt (Kollision)
wire       k_belegt = k_puf ? beleg1[g_x[8:0]] : beleg0[g_x[8:0]];

// Pruefen: liegt Sprite s auf dieser Zeile?
wire [8:0] p_yy   = k_zeile + 9'd32 - sp_y[k_s];
wire       p_gross = sp_att[k_s][7];
wire       p_drin  = sp_an[k_s] && (p_gross ? p_yy < 9'd32 : p_yy < 9'd16);
wire [4:0] p_r0    = p_gross ? p_yy[5:1] : p_yy[4:0];
wire [3:0] p_reihe = sp_att[k_s][5] ? ~p_r0[3:0] : p_r0[3:0];

// Malen: Pixel k_px
wire       g_gross = sp_att[k_s][7];
wire [5:0] g_w     = g_gross ? 6'd32 : 6'd16;
wire [4:0] g_spx   = g_gross ? k_px[5:1] : k_px[4:0];
wire [3:0] g_sp    = sp_att[k_s][4] ? ~g_spx[3:0] : g_spx[3:0];
wire [3:0] g_nib   = k_reihe[63 - {g_sp, 2'b00} -: 4];
wire [9:0] g_x     = {1'b0, sp_x[k_s]} + {4'd0, k_px} - 10'd32;
wire       g_auf   = (g_x < 10'd320) && (g_nib != 4'd0);

always @(posedge clk) begin
	s_we <= 1'b0;
	if (start) begin
		k_zeile <= zeile;
		k_puf   <= puffer;
		k_s     <= 5'd0;
		if (puffer) beleg1 <= 320'd0; else beleg0 <= 320'd0;
		k_st    <= an ? K_PRUEF : K_RUHE;
	end
	else begin
		case (k_st)
			K_PRUEF: begin
				if (p_drin) begin
					m_raddr <= {sp_m[k_s], p_reihe};
					k_st    <= K_WARTE1;
				end
				else if (k_s == 5'd31) k_st <= K_RUHE;
				else k_s <= k_s + 5'd1;
			end
			K_WARTE1: k_st <= K_WARTE2;
			K_WARTE2: begin
				k_reihe <= m_q;
				k_px    <= 6'd0;
				k_st    <= K_MALEN;
			end
			K_MALEN: begin
				if (g_auf) begin
					if (!k_belegt) begin
						s_we          <= 1'b1;
						s_waddr       <= {k_puf, g_x[8:0]};
						s_wdata       <= {sp_att[k_s][6], sp_att[k_s][3:0], g_nib};
						if (k_puf) beleg1[g_x[8:0]] <= 1'b1; else beleg0[g_x[8:0]] <= 1'b1;
						wer[g_x[8:0]] <= k_s;
					end
					else begin                       // schon besetzt: Kollision
						koll[k_s]      <= 1'b1;
						koll[wer[g_x[8:0]]] <= 1'b1;
					end
				end
				k_px <= k_px + 6'd1;
				if (k_px == g_w - 6'd1) begin
					if (k_s == 5'd31) k_st <= K_RUHE;
					else begin
						k_s  <= k_s + 5'd1;
						k_st <= K_PRUEF;
					end
				end
			end
			default: ;
		endcase
	end
	if (reg_we && reg_addr == 9'h104) koll <= 32'd0;
	if (reset) begin
		k_st <= K_RUHE;
		koll <= 32'd0;
	end
end

endmodule
