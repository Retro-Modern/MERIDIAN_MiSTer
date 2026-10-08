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
//   +6     Bit 0: an, Bit 1: Kontur, Bit 2: Schlagschatten (MERIDIAN 1.0,
//          wirken nur mit dem Schalter TUSCHE in PINSEL, $C034)
//  Steuerung ab $00:C400:
//   $00/$01 MADR    Byte-Adresse im Musterspeicher (14 Bit)
//   $02     MDATEN  schreiben: Byte ablegen, MADR zaehlt weiter
//   $03     STEUER  Bit 0: Sprites an
//   $04-$07 KOLL    Bit n: Sprite n hat einen anderen beruehrt (Lesen);
//                   Schreiben auf $04 loescht alle
//  Muster: 16 Zeilen zu 8 Byte, linkes Pixel im oberen Halbbyte, 0 = durchsichtig.
//
//  Tusche (MERIDIAN 1.0): Ein Sprite mit Kontur bekommt einen Rand von einem
//  Bildschirmpunkt in der Tuschefarbe - auch doppelt gross nur einen Punkt.
//  KOBOLD holt dafuer drei Musterzeilen (die Zeile und ihre Nachbarn auf dem
//  Schirm) und malt w+2 Punkte; der Sprite reicht dann eine Zeile hoeher und
//  tiefer. Randpunkte decken wie Spritepunkte (Sprite 0 vorn), zaehlen aber
//  nicht als Kollision. Ohne Kontur laeuft alles wie bisher.
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
	output            aus_hinten,
	output            aus_schatten,   // der Punkt wirft einen Schlagschatten

	// Tusche aus PINSEL
	input             kontur_an,      // Schalter: Kontur fuer Sprites mit +6 Bit 1
	input       [7:0] tinte           // Tuschefarbe
);

//////////////////////////////  Sprite-Tabelle  /////////////////////////////

reg  [8:0] sp_x   [0:31];
reg  [8:0] sp_y   [0:31];
reg  [6:0] sp_m   [0:31];
reg  [7:0] sp_att [0:31];
reg  [2:0] sp_fl  [0:31];          // +6: Bit 0 an, 1 Kontur, 2 Schatten

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
			3'd6: reg_dout = {5'd0, sp_fl[cs]};
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

// Eintrag: Farbe (8), hinter Ebene B (1), wirft Schatten (1). Ob ein Eintrag
// fuer die Zeile gilt, sagt das Belegt-Register des Puffers (320 Bit): Es wird
// beim Zeilenstart in einem Takt geloescht, der RAM-Puffer selbst muss nie
// geloescht werden.
reg  [9:0] spuf [0:1023];
reg        s_we;
reg  [9:0] s_waddr;
reg  [9:0] s_wdata;
reg  [9:0] s_q;
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
assign aus_schatten = s_q[9];

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
			3'd6: sp_fl[cs]     <= reg_din[2:0];
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
                 K_MALEN = 3'd4, K_KHOL = 3'd5, K_KW1 = 3'd6, K_KW2 = 3'd7;

reg  [2:0] k_st;
reg  [4:0] k_s;                    // aktueller Sprite
reg  [5:0] k_px;                   // Pixel in der Spritezeile (0..31)
reg  [8:0] k_zeile;
reg        k_puf;
reg [63:0] k_reihe;                // Musterzeile
reg  [4:0] wer [0:319];            // welcher Sprite dort sitzt (Kollision)
reg [319:0] tinte_da;              // dort sitzt ein Randpunkt (keine Kollision)
reg        k_kont;                 // dieser Sprite hat Kontur
reg  [6:0] k_q;                    // Kontur: Schirmzeile im Sprite + 1 (0..33)
reg  [1:0] k_hol;                  // Kontur: welche der drei Zeilen geholt wird
reg [15:0] k_m0, k_m2;             // Kontur: Deckung der Zeilen darueber/darunter

// Pruefen: liegt Sprite s auf dieser Zeile?
wire [8:0] p_yy   = k_zeile + 9'd32 - sp_y[k_s];
wire       p_gross = sp_att[k_s][7];
wire       p_drin  = sp_fl[k_s][0] && (p_gross ? p_yy < 9'd32 : p_yy < 9'd16);
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

// Kontur: liegt der Sprite (mit Rand) auf dieser Zeile? q = Zeile im Sprite + 1
wire [9:0] t_q     = {1'b0, k_zeile} + 10'd33 - {1'b0, sp_y[k_s]};
wire       t_kont  = kontur_an && sp_fl[k_s][1];
wire       t_drin  = sp_fl[k_s][0] && (t_q < (p_gross ? 10'd34 : 10'd18));

// Kontur holen: Schirmzeile s der Holung k_hol (0 die Zeile, 1 darueber, 2 darunter)
wire [6:0] h_s     = (k_hol == 2'd0) ? k_q - 7'd1 : (k_hol == 2'd1) ? k_q - 7'd2 : k_q;
wire       h_ok    = !h_s[6] && (g_gross ? h_s < 7'd32 : h_s < 7'd16);
wire [4:0] h_r0    = g_gross ? h_s[5:1] : h_s[4:0];
wire [3:0] h_reihe = sp_att[k_s][5] ? ~h_r0[3:0] : h_r0[3:0];

function [15:0] deckung(input [63:0] reihe);
	integer i;
	begin
		for (i = 0; i < 16; i = i + 1) deckung[i] = |reihe[63 - 4 * i -: 4];
	end
endfunction

// Deckt Spalte c (Schirm, im Sprite, mit Vorzeichen) in der Maske m?
function deckt(input [15:0] m, input [6:0] c, input gross, input spx);
	reg [4:0] pc;
	reg [3:0] p;
	begin
		pc    = gross ? c[5:1] : c[4:0];
		p     = spx ? ~pc[3:0] : pc[3:0];
		deckt = !c[6] && (gross ? c < 7'd32 : c < 7'd16) && m[p];
	end
endfunction

// Kontur malen: Spalte c = k_px - 1 (-1 .. w)
wire [15:0] t_m1   = deckung(k_reihe);
wire [6:0] t_c     = {1'b0, k_px} - 7'd1;
wire       t_spx   = sp_att[k_s][4];
wire       t_eigen = deckt(t_m1, t_c, g_gross, t_spx);
wire       t_rand  = !t_eigen && (deckt(t_m1, t_c - 7'd1, g_gross, t_spx) || deckt(t_m1, t_c + 7'd1, g_gross, t_spx) ||
                                  deckt(k_m0, t_c, g_gross, t_spx) || deckt(k_m2, t_c, g_gross, t_spx));
wire [4:0] t_pc    = g_gross ? t_c[5:1] : t_c[4:0];
wire [3:0] t_p     = t_spx ? ~t_pc[3:0] : t_pc[3:0];
wire [3:0] t_nib   = k_reihe[63 - {t_p, 2'b00} -: 4];
wire [9:0] t_x     = {1'b0, sp_x[k_s]} + {{3{t_c[6]}}, t_c} - 10'd32;
wire       t_auf   = t_x < 10'd320;

wire [9:0] m_x      = k_kont ? t_x : g_x;            // Malposition auf dem Schirm
wire       k_belegt = k_puf ? beleg1[m_x[8:0]] : beleg0[m_x[8:0]];

always @(posedge clk) begin
	s_we <= 1'b0;
	if (start) begin
		k_zeile <= zeile;
		k_puf   <= puffer;
		k_s     <= 5'd0;
		if (puffer) beleg1 <= 320'd0; else beleg0 <= 320'd0;
		tinte_da <= 320'd0;
		k_st    <= an ? K_PRUEF : K_RUHE;
	end
	else begin
		case (k_st)
			K_PRUEF: begin
				if (t_kont && t_drin) begin              // mit Kontur: drei Zeilen holen
					k_kont <= 1'b1;
					k_q    <= t_q[6:0];
					k_hol  <= 2'd0;
					k_st   <= K_KHOL;
				end
				else if (p_drin && !t_kont) begin
					k_kont  <= 1'b0;
					m_raddr <= {sp_m[k_s], p_reihe};
					k_st    <= K_WARTE1;
				end
				else if (k_s == 5'd31) k_st <= K_RUHE;
				else k_s <= k_s + 5'd1;
			end
			K_KHOL: begin
				m_raddr <= {sp_m[k_s], h_reihe};
				k_st    <= K_KW1;
			end
			K_KW1: k_st <= K_KW2;
			K_KW2: begin
				case (k_hol)
					2'd0:    k_reihe <= h_ok ? m_q : 64'd0;
					2'd1:    k_m0    <= h_ok ? deckung(m_q) : 16'd0;
					default: k_m2    <= h_ok ? deckung(m_q) : 16'd0;
				endcase
				if (k_hol == 2'd2) begin
					k_px <= 6'd0;
					k_st <= K_MALEN;
				end
				else begin
					k_hol <= k_hol + 2'd1;
					k_st  <= K_KHOL;
				end
			end
			K_WARTE1: k_st <= K_WARTE2;
			K_WARTE2: begin
				k_reihe <= m_q;
				k_px    <= 6'd0;
				k_st    <= K_MALEN;
			end
			K_MALEN: begin
				if (k_kont ? (t_auf && t_eigen) : g_auf) begin
					if (!k_belegt) begin
						s_we          <= 1'b1;
						s_waddr       <= {k_puf, m_x[8:0]};
						s_wdata       <= {sp_fl[k_s][2], sp_att[k_s][6], sp_att[k_s][3:0], k_kont ? t_nib : g_nib};
						if (k_puf) beleg1[m_x[8:0]] <= 1'b1; else beleg0[m_x[8:0]] <= 1'b1;
						wer[m_x[8:0]] <= k_s;
					end
					else if (!tinte_da[m_x[8:0]]) begin   // schon besetzt: Kollision
						koll[k_s]      <= 1'b1;
						koll[wer[m_x[8:0]]] <= 1'b1;
					end
				end
				else if (k_kont && t_auf && t_rand && !k_belegt) begin   // Randpunkt
					s_we     <= 1'b1;
					s_waddr  <= {k_puf, m_x[8:0]};
					s_wdata  <= {sp_fl[k_s][2], sp_att[k_s][6], tinte};
					if (k_puf) beleg1[m_x[8:0]] <= 1'b1; else beleg0[m_x[8:0]] <= 1'b1;
					tinte_da[m_x[8:0]] <= 1'b1;
				end
				k_px <= k_px + 6'd1;
				if (k_px == (k_kont ? g_w + 6'd1 : g_w - 6'd1)) begin
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
