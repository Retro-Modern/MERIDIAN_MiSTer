//============================================================================
//  PINSEL - Grafikchip des MERIDIAN (Etappe 4: zwei Ebenen, vier Modi;
//  Etappe 5: Sprite-Einheit KOBOLD, siehe kobold.sv; Etappe 7: Strahl-
//  position fuer den Copper LOTSE, beide Ebenen am Zeilenanfang uebernommen)
//
//  Bildaufbau: 12 MHz Punkttakt (24 MHz / 2), 764 Punkte pro Zeile
//  = 15,71 kHz. Sichtbar 640x240 Punkte. Grafikmodi arbeiten mit 320 Pixeln
//  (ein Pixel = zwei Punkte), Text mit 80 Zeichen nutzt alle 640 Punkte.
//  262 Zeilen = 59,9 Hz (NTSC), 312 Zeilen = 50,3 Hz (PAL).
//
//  Zwei Ebenen, A hinten und B vorn. Jede zeigt einen von vier Modi:
//    1 Text        40 oder 80 Zeichen, Zelle = Zeichen + Farbe (vorn/hinten)
//    2 Kacheln     8x8-Kacheln, 16 Farben, Welt 64x32 Kacheln (512x256),
//                  pixelweises Scrolling in X und Y
//    3 Bitmap 16   320x240, 4 Bit pro Pixel, Palettenbank waehlbar
//    4 Bitmap 256  320x240, 8 Bit pro Pixel
//  Farbe 0 ist auf Ebene B durchsichtig; auf Ebene A zeigt sie Farbe 0.
//
//  Jede Zeile wird waehrend der vorherigen gerendert, in drei Phasen: erst
//  Zeichen/Kachelnummern lesen, dann Schrift/Muster, dann die Pixel in den
//  Zeilenpuffer schreiben. Zwei Kachelebenen brauchen ~1150 von 1528 Takten.
//
//  Register ab $00:C000:
//   $00 A_TYP     0 aus, 1 Text, 2 Kacheln, 3 Bitmap 16, 4 Bitmap 256
//   $01 A_OPT     Bit 0: Text mit 80 Zeichen; Bits 4-7: Palettenbank (Bitmap 16)
//   $02-$04       A_DATEN: Bildschirmspeicher / Kachelkarte / Bild (24 Bit)
//   $05-$07       A_MUSTER: Zeichensatz / Kachelmuster (24 Bit)
//   $08 PAL_IDX   Palettenindex (zaehlt nach PAL_HI hoch)
//   $09 PAL_LO    gggg bbbb
//   $0A PAL_HI    ---- rrrr  (Schreiben uebernimmt den Eintrag)
//   $28-$2A       dasselbe noch einmal fuer LOTSE (Befehl FARBE): eigener
//                 Index und eigenes Zwischenbyte, damit Copper und CPU sich
//                 beim Palettenschreiben nicht den Index verstellen
//   $0B IRQ_EN    Bit 0 Bildende (Zeile 240), Bit 1 Rasterzeile
//   $0C IRQ_ST    gesetzte Ursachen; 1 schreiben loescht
//   $0D/$0E       lesen: Rasterzeile, schreiben: Vergleichszeile. Die
//                 Rasterzeile springt zu Beginn der Austastluecke weiter.
//   $0F BILD      Bildzaehler (lesen)
//   $10/$11       A_SX: Scrolling X (0-511, Kacheln)
//   $12           A_SY: Scrolling Y (0-255, Kacheln)
//   $20-$27       Ebene B wie $00-$07
//   $30-$32       Ebene B wie $10-$12
//   $34 TUSCHE    (MERIDIAN 1.0) Bit 0: Kontur um Sprites mit Kontur-Bit,
//                 Bit 1: Schlagschatten der Sprites mit Schatten-Bit,
//                 Bit 2: Schlagschatten von Ebene B. Nach dem Reset 0.
//   $35 TINTE     Tuschefarbe der Kontur (Palettenindex, 0 = unsichtbar)
//   $36/$37       Versatz des Schlagschattens X (0-7) und Y (1-7 Zeilen)
//                 Sprites werfen ihren Schatten auf beide Ebenen, Ebene B nur auf
//                 Ebene A; wo ein Sprite sichtbar ist, faellt kein Schatten. Der
//                 Schatten macht halb so hell.
//   $40-$4E       GLANZ (MERIDIAN 1.0): 16 Glanzkanaele. Ein Kanal schreibt in
//                 der Austastluecke vor jeder Zeile y von VON bis BIS die Farbe
//                 START + (y - VON) * SCHRITT in den Paletteneintrag FARBE, mit
//                 8 Bit je Kanal - Verlaeufe ohne Stufen. Mehrere Kanaele auf
//                 derselben Farbe mit aneinander liegenden Zeilen ergeben einen
//                 Verlauf mit mehreren Abschnitten.
//                 $40 NR (0-15) waehlt den Kanal fuer $41-$4C:
//                 $41 FARBE, $42 VON, $43 BIS (Zeilen 0-239),
//                 $44-$46 START rot, gruen, blau (0-255),
//                 $47/$48, $49/$4A, $4B/$4C SCHRITT rot, gruen, blau je Zeile
//                 (8.8 mit Vorzeichen, unten das Nachkomma-Byte).
//                 $4D/$4E AN: Bit n = Kanal n (0-7, 8-15). Nach dem Reset aus.
//                 Die Palette ist intern 24 Bit breit; was die CPU schreibt
//                 (4 Bit je Kanal), wird wie bisher verdoppelt (F -> FF).
//   $50 LM_IDX    LEUCHTEN (MERIDIAN 1.0): Byte 0-31 der Leuchtmaske
//   $51 LM_DATEN  8 Leuchtbits (Farben LM_IDX*8 .. +7, Bit 0 die erste);
//                 Schreiben zaehlt LM_IDX weiter
//   $52 LEUCHTEN  Staerke 0-15, 0 = aus (nach dem Reset). Um Punkte in
//                 Leuchtfarben legt PINSEL einen Lichthof: waagrecht ein
//                 Dreieck ueber +-15 Punkte, senkrecht 1-2-1 ueber die Zeilen
//                 y-2..y (er sitzt eine Zeile tiefer - PINSEL zeichnet nur
//                 eine Zeile voraus). Bild und Syncs laufen dafuer 20 Punkte
//                 spaeter hinaus; bei Staerke 0 ist jeder Punkt wie bisher.
//
//  Kachelkarte: 64x32 Eintraege zu 2 Byte: Bits 0-9 Kachel, 10 spiegeln X,
//  11 spiegeln Y, 12-15 Palettenbank. Kachel = 32 Byte, 8 Zeilen zu 4 Byte,
//  linkes Pixel im oberen Halbbyte.
//
//  Registeraenderungen wirken ab der naechsten gerenderten Zeile; die
//  Palette wirkt sofort (sie wird erst bei der Ausgabe nachgeschlagen).
//  Genau: Am Ende jeder Strahlzeile n uebernimmt PINSEL die Register beider
//  Ebenen fuer Zeile n+2 (gerendert waehrend Zeile n+1). Was in der
//  Austastluecke vor Zeile n geschrieben wird, wirkt also ab Zeile n+1.
//============================================================================

module pinsel
(
	input             clk,          // 24 MHz
	input             reset,
	input             pal,

	// CPU-Seite (Register)
	input       [7:0] reg_addr,
	input       [7:0] reg_din,
	output reg  [7:0] reg_dout,
	input             reg_we,
	output            irq,

	// KOBOLD (Sprites): $C3xx Tabelle, $C4xx Steuerung -> kob_addr[8] = 1
	input       [8:0] kob_addr,
	input       [7:0] kob_din,
	output      [7:0] kob_dout,
	input             kob_we,

	// Chip-RAM, zweiter Port (nur lesen, ein Takt Latenz)
	output reg [17:0] vram_addr,
	input       [7:0] vram_q,

	// Bildausgabe
	output reg        ce_pix,
	output reg        hblank,
	output reg        vblank,
	output reg        hsync,
	output reg        vsync,
	output reg  [7:0] r,
	output reg  [7:0] g,
	output reg  [7:0] b,

	// Strahlposition fuer den Copper (Punkt 0-763, Zeile, letzte Zeile)
	output      [9:0] strahl_h,
	output      [8:0] strahl_v,
	output      [8:0] strahl_ende
);

localparam [9:0] H_TOTAL = 10'd764;
localparam [9:0] H_VIS   = 10'd640;
localparam [9:0] HS_BEG  = 10'd664;
localparam [9:0] HS_END  = 10'd720;
localparam [8:0] V_VIS   = 9'd240;

//////////////////////////////  Register  ///////////////////////////////////

reg  [2:0] typ    [0:1];
reg  [7:0] opt    [0:1];
reg [23:0] daten  [0:1];
reg [23:0] muster [0:1];
reg  [8:0] sx     [0:1];
reg  [7:0] sy     [0:1];

reg  [2:0] tusche;                                     // $34
reg  [7:0] tinte;                                      // $35
reg  [2:0] sch_dx, sch_dy;                             // $36/$37
reg  [7:0] pal_idx, pal_lo;
reg  [7:0] cpal_idx, cpal_lo;                           // Satz fuer LOTSE
reg  [1:0] irq_en, irq_st;
reg  [8:0] ras_cmp, ras_line;
reg  [7:0] frame;
reg        pal_we;
reg  [7:0] pal_widx;
reg [11:0] pal_wdata;

// Leuchten
reg [255:0] lmaske;
reg  [4:0] lm_idx;
reg  [3:0] leucht;

// Glanz: 16 Kanaele
reg  [3:0] gl_nr;
reg [15:0] gl_an;
reg  [7:0] gl_idx [0:15];
reg  [7:0] gl_von [0:15], gl_bis [0:15];
reg  [7:0] gl_r0  [0:15], gl_g0 [0:15], gl_b0 [0:15];
reg [15:0] gl_dr  [0:15], gl_dg [0:15], gl_db [0:15];

wire       reg_eb  = reg_addr[5];                       // $2x/$3x = Ebene B
wire [4:0] reg_r   = {reg_addr[4], reg_addr[3:0]};
wire       reg_ebn = reg_addr[7:6] == 2'b00 &&           // Ebenenregister,
                     !(reg_addr[4] == 1'b0 && reg_addr[3]);  // nicht $08-$0F/$28-$2F

always @(posedge clk) begin
	pal_we <= 1'b0;
	if (reg_we) begin
		case (reg_addr)
			8'h08: pal_idx <= reg_din;
			8'h09: pal_lo  <= reg_din;
			8'h0A: begin
				pal_we    <= 1'b1;
				pal_widx  <= pal_idx;
				pal_wdata <= {reg_din[3:0], pal_lo};
				pal_idx   <= pal_idx + 8'd1;
			end
			// $28-$2A: zweiter Satz fuer den Copper (gleicher Schreibweg in die
			// Palette, aber eigener Index - vorher konnte eine Copper-Zeile
			// zwischen PAL_IDX und PAL_HI der CPU fallen)
			8'h28: cpal_idx <= reg_din;
			8'h29: cpal_lo  <= reg_din;
			8'h2A: begin
				pal_we    <= 1'b1;
				pal_widx  <= cpal_idx;
				pal_wdata <= {reg_din[3:0], cpal_lo};
				cpal_idx  <= cpal_idx + 8'd1;
			end
			8'h0B: irq_en       <= reg_din[1:0];
			8'h34: tusche       <= reg_din[2:0];
			8'h35: tinte        <= reg_din;
			8'h36: sch_dx       <= reg_din[2:0];
			8'h37: sch_dy       <= reg_din[2:0];
			8'h40: gl_nr        <= reg_din[3:0];
			8'h41: gl_idx[gl_nr] <= reg_din;
			8'h42: gl_von[gl_nr] <= reg_din;
			8'h43: gl_bis[gl_nr] <= reg_din;
			8'h44: gl_r0[gl_nr]  <= reg_din;
			8'h45: gl_g0[gl_nr]  <= reg_din;
			8'h46: gl_b0[gl_nr]  <= reg_din;
			8'h47: gl_dr[gl_nr][7:0]  <= reg_din;
			8'h48: gl_dr[gl_nr][15:8] <= reg_din;
			8'h49: gl_dg[gl_nr][7:0]  <= reg_din;
			8'h4A: gl_dg[gl_nr][15:8] <= reg_din;
			8'h4B: gl_db[gl_nr][7:0]  <= reg_din;
			8'h4C: gl_db[gl_nr][15:8] <= reg_din;
			8'h4D: gl_an[7:0]   <= reg_din;
			8'h4E: gl_an[15:8]  <= reg_din;
			8'h50: lm_idx       <= reg_din[4:0];
			8'h51: begin
				lmaske[{lm_idx, 3'b000} +: 8] <= reg_din;
				lm_idx <= lm_idx + 5'd1;
			end
			8'h52: leucht       <= reg_din[3:0];
			8'h0D: ras_cmp[7:0] <= reg_din;
			8'h0E: ras_cmp[8]   <= reg_din[0];
			default: ;
		endcase
		if (reg_ebn) begin
			case (reg_r)
				5'h00: typ[reg_eb]           <= reg_din[2:0];
				5'h01: opt[reg_eb]           <= reg_din;
				5'h02: daten[reg_eb][7:0]    <= reg_din;
				5'h03: daten[reg_eb][15:8]   <= reg_din;
				5'h04: daten[reg_eb][23:16]  <= reg_din;
				5'h05: muster[reg_eb][7:0]   <= reg_din;
				5'h06: muster[reg_eb][15:8]  <= reg_din;
				5'h07: muster[reg_eb][23:16] <= reg_din;
				5'h10: sx[reg_eb][7:0]       <= reg_din;
				5'h11: sx[reg_eb][8]         <= reg_din[0];
				5'h12: sy[reg_eb]            <= reg_din;
				default: ;
			endcase
		end
	end
	if (reset) begin
		typ[0]    <= 3'd1;
		opt[0]    <= 8'd0;
		daten[0]  <= 24'h000400;
		muster[0] <= 24'h001800;
		typ[1]    <= 3'd0;
		opt[1]    <= 8'd0;
		sx[0] <= 9'd0; sy[0] <= 8'd0;
		sx[1] <= 9'd0; sy[1] <= 8'd0;
		irq_en    <= 2'b00;
		ras_cmp   <= 9'd0;
		tusche    <= 3'd0;
		tinte     <= 8'd0;
		sch_dx    <= 3'd2;
		sch_dy    <= 3'd2;
		gl_an     <= 16'd0;
		gl_nr     <= 4'd0;
		lmaske    <= 256'd0;
		lm_idx    <= 5'd0;
		leucht    <= 4'd0;
		pal_idx   <= 8'd0;
		cpal_idx  <= 8'd0;
	end
end

always @* begin
	case (reg_addr)
		8'h08:   reg_dout = pal_idx;
		8'h28:   reg_dout = cpal_idx;
		8'h0B:   reg_dout = {6'd0, irq_en};
		8'h0C:   reg_dout = {6'd0, irq_st};
		8'h0D:   reg_dout = ras_line[7:0];
		8'h0E:   reg_dout = {7'd0, ras_line[8]};
		8'h0F:   reg_dout = frame;
		8'h00:   reg_dout = {5'd0, typ[0]};
		8'h01:   reg_dout = opt[0];
		8'h02:   reg_dout = daten[0][7:0];
		8'h03:   reg_dout = daten[0][15:8];
		8'h04:   reg_dout = daten[0][23:16];
		8'h05:   reg_dout = muster[0][7:0];
		8'h06:   reg_dout = muster[0][15:8];
		8'h07:   reg_dout = muster[0][23:16];
		8'h10:   reg_dout = sx[0][7:0];
		8'h11:   reg_dout = {7'd0, sx[0][8]};
		8'h12:   reg_dout = sy[0];
		8'h20:   reg_dout = {5'd0, typ[1]};
		8'h21:   reg_dout = opt[1];
		8'h22:   reg_dout = daten[1][7:0];
		8'h23:   reg_dout = daten[1][15:8];
		8'h24:   reg_dout = daten[1][23:16];
		8'h25:   reg_dout = muster[1][7:0];
		8'h26:   reg_dout = muster[1][15:8];
		8'h27:   reg_dout = muster[1][23:16];
		8'h30:   reg_dout = sx[1][7:0];
		8'h31:   reg_dout = {7'd0, sx[1][8]};
		8'h32:   reg_dout = sy[1];
		8'h34:   reg_dout = {5'd0, tusche};
		8'h35:   reg_dout = tinte;
		8'h36:   reg_dout = {5'd0, sch_dx};
		8'h37:   reg_dout = {5'd0, sch_dy};
		8'h40:   reg_dout = {4'd0, gl_nr};
		8'h41:   reg_dout = gl_idx[gl_nr];
		8'h42:   reg_dout = gl_von[gl_nr];
		8'h43:   reg_dout = gl_bis[gl_nr];
		8'h44:   reg_dout = gl_r0[gl_nr];
		8'h45:   reg_dout = gl_g0[gl_nr];
		8'h46:   reg_dout = gl_b0[gl_nr];
		8'h47:   reg_dout = gl_dr[gl_nr][7:0];
		8'h48:   reg_dout = gl_dr[gl_nr][15:8];
		8'h49:   reg_dout = gl_dg[gl_nr][7:0];
		8'h4A:   reg_dout = gl_dg[gl_nr][15:8];
		8'h4B:   reg_dout = gl_db[gl_nr][7:0];
		8'h4C:   reg_dout = gl_db[gl_nr][15:8];
		8'h4D:   reg_dout = gl_an[7:0];
		8'h4E:   reg_dout = gl_an[15:8];
		8'h50:   reg_dout = {3'd0, lm_idx};
		8'h51:   reg_dout = lmaske[{lm_idx, 3'b000} +: 8];
		8'h52:   reg_dout = {4'd0, leucht};
		default: reg_dout = 8'hFF;
	endcase
end

//////////////////////////////  Raster  /////////////////////////////////////

always @(posedge clk) ce_pix <= ~ce_pix;

reg [9:0] hc;
reg [8:0] vc;
wire [8:0] v_last   = pal ? 9'd311 : 9'd261;
wire       line_end = (hc == H_TOTAL - 10'd1);
wire [8:0] v_next   = (vc == v_last) ? 9'd0 : vc + 9'd1;
assign strahl_h    = hc;
assign strahl_v    = vc;
assign strahl_ende = v_last;

always @(posedge clk) begin
	if (ce_pix) begin
		hc <= line_end ? 10'd0 : hc + 10'd1;
		if (line_end) begin
			vc <= v_next;
			if (v_next == V_VIS) frame <= frame + 8'd1;
		end
	end
	if (reset) frame <= 8'd0;
end

// Rasterzeile und Interrupts zu Beginn der Austastluecke
always @(posedge clk) begin
	if (ce_pix && hc == H_VIS - 10'd1) begin
		ras_line <= v_next;
		if (v_next == V_VIS && irq_en[0]) irq_st[0] <= 1'b1;
		if (v_next == ras_cmp && irq_en[1]) irq_st[1] <= 1'b1;
	end
	if (reg_we && reg_addr == 8'h0C) irq_st <= irq_st & ~reg_din[1:0];
	if (reset) irq_st <= 2'b00;
end
assign irq = |irq_st;

//////////////////////////////  Palette  ////////////////////////////////////

// Intern 24 Bit (Glanz); die CPU schreibt 12 Bit, verdoppelt wie bisher bei
// der Ausgabe - fuer alles, was keine Glanzfarbe nutzt, aendert sich nichts.
reg [23:0] palette [0:255];
reg [23:0] pal_q;
wire [7:0] lb_q;
reg        gl_we;
reg  [7:0] gl_widx;
reg [23:0] gl_wdata;
always @(posedge clk) begin
	if (pal_we)
		palette[pal_widx] <= {pal_wdata[11:8], pal_wdata[11:8], pal_wdata[7:4], pal_wdata[7:4],
		                      pal_wdata[3:0], pal_wdata[3:0]};
	else if (gl_we)
		palette[gl_widx] <= gl_wdata;
	pal_q <= palette[lb_q];
end

//////////////////////////////  Glanz  //////////////////////////////////////

// In der Austastluecke vor Zeile y = v_next: Kanal fuer Kanal weiterrechnen
// und schreiben. Schreibt gerade die CPU oder LOTSE in die Palette (oder
// kommt ihr Schreiben im naechsten Takt), wartet Glanz.
reg [15:0] gl_ar [0:15], gl_ag [0:15], gl_ab [0:15];   // 8.8
reg        gl_lauf;
reg  [3:0] gl_k;
reg  [7:0] gl_y;
function [15:0] gl_plus(input [15:0] a, input [15:0] d);
	reg [16:0] t;
	begin
		t = {1'b0, a} + {d[15], d};                      // 17 Bit mit Vorzeichen
		gl_plus = !t[16] ? t[15:0] :                      // 0 .. 255,99
		          d[15]  ? 16'h0000 : 16'hFFFF;           // darunter / darueber
	end
endfunction
wire        gl_drin  = gl_an[gl_k] && (gl_y >= gl_von[gl_k]) && (gl_y <= gl_bis[gl_k]);
wire        gl_erste = (gl_y == gl_von[gl_k]);
wire [15:0] gl_nr_   = gl_erste ? {gl_r0[gl_k], 8'h80} : gl_plus(gl_ar[gl_k], gl_dr[gl_k]);
wire [15:0] gl_ng_   = gl_erste ? {gl_g0[gl_k], 8'h80} : gl_plus(gl_ag[gl_k], gl_dg[gl_k]);
wire [15:0] gl_nb_   = gl_erste ? {gl_b0[gl_k], 8'h80} : gl_plus(gl_ab[gl_k], gl_db[gl_k]);
always @(posedge clk) begin
	gl_we <= 1'b0;
	if (ce_pix && hc == H_VIS && v_next < V_VIS && gl_an != 16'd0) begin
		gl_lauf <= 1'b1;
		gl_k    <= 4'd0;
		gl_y    <= v_next[7:0];
	end
	else if (gl_lauf && !pal_we && !gl_we && !(reg_we && (reg_addr == 8'h0A || reg_addr == 8'h2A))) begin
		if (gl_drin) begin
			gl_ar[gl_k] <= gl_nr_;
			gl_ag[gl_k] <= gl_ng_;
			gl_ab[gl_k] <= gl_nb_;
			gl_we    <= 1'b1;
			gl_widx  <= gl_idx[gl_k];
			gl_wdata <= {gl_nr_[15:8], gl_ng_[15:8], gl_nb_[15:8]};
		end
		gl_k <= gl_k + 4'd1;
		if (gl_k == 4'd15) gl_lauf <= 1'b0;
	end
	if (reset) gl_lauf <= 1'b0;
end

//////////////////////////////  Zeilenpuffer  ///////////////////////////////

// Zwei Puffer zu 320 Eintraegen; jeder Eintrag = zwei Punkte (gerade und
// ungerade). So werden Grafikpixel in einem Takt doppelt breit geschrieben,
// und Text mit 80 Zeichen kann trotzdem jeden Punkt einzeln setzen.
// Bit 8 eines Eintrags: das Pixel stammt von Ebene B (fuer Sprites "hinten").
reg  [8:0] lb_g [0:1023];
reg  [8:0] lb_u [0:1023];
reg        front;
reg        lbw_g, lbw_u;
reg  [9:0] lbw_addr;
reg  [8:0] lbw_dg, lbw_du;
reg  [8:0] lb_gq, lb_uq;
reg        lb_sel;
wire [9:0] lb_raddr = {front, hc[9:1]};

always @(posedge clk) begin
	if (lbw_g) lb_g[lbw_addr] <= lbw_dg;
	if (lbw_u) lb_u[lbw_addr] <= lbw_du;
	lb_gq  <= lb_g[lb_raddr];
	lb_uq  <= lb_u[lb_raddr];
	lb_sel <= hc[0];
end
wire [8:0] lb_e = lb_sel ? lb_uq : lb_gq;

// Sprites daruebermischen: vor allem, oder hinter Pixeln von Ebene B
wire       k_gueltig, k_hinten, k_schatten;
wire [7:0] k_farbe;
assign lb_q = (k_gueltig && !(k_hinten && lb_e[8])) ? k_farbe : lb_e[7:0];

//////////////////////////////  Schlagschatten  /////////////////////////////

// Gedaechtnis der letzten acht Zeilen: wirft Punkt x Schatten (Bit 0 ein
// Sprite, Bit 1 Ebene B)? Beim Ausgeben schreibt jede Zeile ihre Bits,
// gelesen wird (y - DY, x - DX). Der Schatten eines Sprites faellt auf jeden
// Punkt ohne sichtbaren Sprite, der von Ebene B nur auf Ebene A.
reg  [1:0] sch_mem [0:4095];          // {Zeile mod 8, x}
reg  [1:0] sch_q, sch_wirft_d;
reg        sch_rok, sch_d;
reg        sch_we;
reg [11:0] sch_waddr;
wire [2:0] sch_dyw = (sch_dy == 3'd0) ? 3'd1 : sch_dy;
wire [8:0] sch_x   = hc[9:1] - {6'd0, sch_dx};
wire [8:0] sch_y   = vc - {6'd0, sch_dyw};
wire       sch_kob = k_gueltig && !(k_hinten && lb_e[8]);    // Sprite sichtbar
wire [1:0] sch_wirft = {lb_e[8] && tusche[2], k_gueltig && k_schatten && tusche[1]};
reg  [8:0] sch_px;
reg        sch_vis;
always @(posedge clk) begin
	if (sch_we) sch_mem[sch_waddr] <= sch_wirft_d;
	sch_q   <= sch_mem[{sch_y[2:0], sch_x}];
	sch_rok <= (hc[9:1] >= {6'd0, sch_dx}) && (vc >= {6'd0, sch_dyw}) && (hc < H_VIS) && (vc < V_VIS);
	sch_px  <= hc[9:1];
	sch_vis <= (hc < H_VIS) && (vc < V_VIS) && !hc[0];
	// eine Stufe spaeter (wie lb_e): schreiben und entscheiden
	sch_we    <= sch_vis && (tusche[1] || tusche[2]);
	sch_waddr <= {vc[2:0], sch_px};
	sch_wirft_d <= sch_wirft;
	sch_d     <= sch_rok && !sch_kob && ((sch_q[0] && tusche[1]) || (sch_q[1] && tusche[2] && !lb_e[8]));
end

//////////////////////////////  Renderer  ///////////////////////////////////

localparam [3:0] S_IDLE   = 4'd0,  S_START  = 4'd1,  S_LOESCH = 4'd2,
                 S_HOLEN1 = 4'd3,  S_HOLEN2 = 4'd4,  S_MALEN  = 4'd5,
                 S_STROM  = 4'd6,  S_WEITER = 4'd7;

reg  [3:0] st;
reg        ebene;                 // 0 = A, 1 = B
reg  [8:0] r_line;                // gerenderte Zeile 0..239

// Konfiguration beider Ebenen, am Zeilenende festgehalten (sonst wuerde
// Ebene B ihre Register erst mitten in der Zeile lesen)
reg  [2:0] z_typ    [0:1];
reg  [7:0] z_opt    [0:1];
reg [17:0] z_daten  [0:1];
reg [17:0] z_muster [0:1];
reg  [8:0] z_sx     [0:1];
reg  [7:0] z_sy     [0:1];
integer    zi;

// Konfiguration der Ebene, die gerade gerendert wird
reg  [2:0] l_typ;
reg  [7:0] l_opt;
reg [17:0] l_daten, l_muster;
reg  [8:0] l_sx;
reg  [7:0] l_sy;

wire       l_80   = l_opt[0];
wire [6:0] l_cols = l_80 ? 7'd80 : 7'd40;
wire [7:0] wy     = r_line[7:0] + l_sy;         // Weltzeile (Kacheln)

// Puffer fuer die Holphasen
reg  [7:0] buf_a [0:127];         // Text: Zeichen; Kacheln: Karte low
reg  [7:0] buf_b [0:127];         // Text: Farbe;   Kacheln: Karte high
reg  [7:0] buf_c [0:255];         // Text: Schrift; Kacheln: Muster (4 je Kachel)

// Lesepipeline: Adresse -> RAM -> Daten
reg  [8:0] iss;                   // naechster Index
reg  [8:0] iss_n;                 // Anzahl
reg        p1_v, p2_v;
reg  [8:0] p1_i, p2_i;
reg  [8:0] x;                     // Malposition 0..319
reg  [7:0] strom_halb;            // Bitmap 16: zweites Pixel
reg        strom_rest;
reg  [8:0] strom_x;

// Leseadresse fuer Index 'iss' in der aktuellen Phase
reg [17:0] h_addr;
reg [17:0] t_zeile;
reg  [5:0] t_spalte;
reg  [7:0] t_lo, t_hi;
reg  [2:0] t_ty;
always @* begin
	t_zeile  = l_daten + {6'd0, wy[7:3], 7'd0};          // Kachelzeile * 128
	t_spalte = l_sx[8:3] + iss[6:1];
	t_lo     = buf_a[iss[8:2]];
	t_hi     = buf_b[iss[8:2]];
	t_ty     = t_hi[3] ? ~wy[2:0] : wy[2:0];
	case ({l_typ, st == S_HOLEN2})
		{3'd1, 1'b0}: h_addr = l_daten + ({13'd0, r_line[7:3]} * (l_80 ? 18'd160 : 18'd80)) + {9'd0, iss};
		{3'd1, 1'b1}: h_addr = l_muster + {7'd0, buf_a[iss[6:0]], r_line[2:0]};
		{3'd2, 1'b0}: h_addr = t_zeile + {11'd0, t_spalte, iss[0]};
		{3'd2, 1'b1}: h_addr = l_muster + {3'd0, t_hi[1:0], t_lo, t_ty, iss[1:0]};
		{3'd3, 1'b0}: h_addr = l_daten + {3'd0, r_line[7:0], 7'd0} + {5'd0, r_line[7:0], 5'd0} + {10'd0, iss[8:1]};
		default:      h_addr = l_daten + {2'd0, r_line[7:0], 8'd0} + {4'd0, r_line[7:0], 6'd0} + {9'd0, iss};
	endcase
end

// Farbe der Malposition x (Text und Kacheln)
reg  [7:0] m_g, m_u;              // Farbe gerader/ungerader Punkt
reg        m_tg, m_tu;            // durchsichtig?
reg  [8:0] m_wx;
reg  [5:0] m_t;
reg  [2:0] m_p;
reg  [7:0] m_byte, m_fnt, m_att, m_hi;
reg  [3:0] m_nib;
reg  [6:0] m_c;
reg  [2:0] m_p0;
always @* begin
	m_g = 8'd0; m_u = 8'd0; m_tg = 1'b0; m_tu = 1'b0;
	m_wx = 9'd0; m_t = 6'd0; m_p = 3'd0; m_byte = 8'd0; m_nib = 4'd0;
	m_fnt = 8'd0; m_att = 8'd0; m_hi = 8'd0; m_c = 7'd0; m_p0 = 3'd0;
	if (l_typ == 3'd2) begin
		m_wx   = x + {6'd0, l_sx[2:0]};
		m_t    = m_wx[8:3];
		m_hi   = buf_b[{1'b0, m_t}];
		m_p    = m_hi[2] ? ~m_wx[2:0] : m_wx[2:0];
		m_byte = buf_c[{m_t, m_p[2:1]}];
		m_nib  = m_p[0] ? m_byte[3:0] : m_byte[7:4];
		m_g    = (m_nib == 4'd0) ? 8'd0 : {m_hi[7:4], m_nib};
		m_u    = m_g;
		m_tg   = (m_nib == 4'd0);
		m_tu   = m_tg;
	end
	else begin                         // Text
		if (l_80) begin
			m_c  = {1'b0, x[8:2]};
			m_p0 = {x[1:0], 1'b0};
		end
		else begin
			m_c  = {2'b00, x[8:3]};
			m_p0 = x[2:0];
		end
		m_fnt = buf_c[{1'b0, m_c}];
		m_att = buf_b[m_c];
		m_g   = m_fnt[3'd7 - m_p0] ? {4'd0, m_att[3:0]} : {4'd0, m_att[7:4]};
		m_u   = l_80 ? (m_fnt[3'd6 - m_p0] ? {4'd0, m_att[3:0]} : {4'd0, m_att[7:4]}) : m_g;
		m_tg  = (m_g == 8'd0);
		m_tu  = (m_u == 8'd0);
	end
end

// Pixel schreiben; auf Ebene B bleiben durchsichtige Punkte stehen
task punkt(input [8:0] pos, input [7:0] dg, input [7:0] du, input tg, input tu);
	begin
		lbw_addr <= {~front, pos};
		lbw_dg   <= {ebene, dg};
		lbw_du   <= {ebene, du};
		lbw_g    <= !(ebene && tg);
		lbw_u    <= !(ebene && tu);
	end
endtask

always @(posedge clk) begin
	lbw_g <= 1'b0;
	lbw_u <= 1'b0;

	// Lesepipeline: Daten zwei Takte nach der Adresse abholen
	p2_v <= p1_v;
	p2_i <= p1_i;
	p1_v <= 1'b0;
	if (p2_v) begin
		case (l_typ)
			3'd1, 3'd2: begin
				if (st == S_HOLEN1) begin
					if (p2_i[0]) buf_b[p2_i[7:1]] <= vram_q;
					else         buf_a[p2_i[7:1]] <= vram_q;
				end
				else buf_c[p2_i[7:0]] <= vram_q;
			end
			3'd3: begin                                   // Bitmap 16: zwei Pixel
				punkt({p2_i[7:0], 1'b0}, {l_opt[7:4], vram_q[7:4]}, {l_opt[7:4], vram_q[7:4]},
				      vram_q[7:4] == 4'd0, vram_q[7:4] == 4'd0);
				strom_halb <= {l_opt[7:4], vram_q[3:0]};
				strom_rest <= 1'b1;
				strom_x    <= {p2_i[7:0], 1'b1};
			end
			default: punkt(p2_i, vram_q, vram_q, vram_q == 8'd0, vram_q == 8'd0);  // Bitmap 256
		endcase
	end
	else if (strom_rest) begin
		punkt(strom_x, strom_halb, strom_halb, strom_halb[3:0] == 4'd0, strom_halb[3:0] == 4'd0);
		strom_rest <= 1'b0;
	end

	// Ablauf
	if (ce_pix && line_end) begin
		for (zi = 0; zi < 2; zi = zi + 1) begin
			z_typ[zi]    <= typ[zi];
			z_opt[zi]    <= opt[zi];
			z_daten[zi]  <= daten[zi][17:0];
			z_muster[zi] <= muster[zi][17:0];
			z_sx[zi]     <= sx[zi];
			z_sy[zi]     <= sy[zi];
		end
		front <= ~front;
		if (v_next < V_VIS - 9'd1 || v_next == v_last) begin
			r_line <= (v_next == v_last) ? 9'd0 : v_next + 9'd1;
			ebene  <= 1'b0;
			st     <= S_START;
		end
		else st <= S_IDLE;
	end
	else begin
		case (st)
			S_START: begin
				l_typ    <= z_typ[ebene];
				l_opt    <= z_opt[ebene];
				l_daten  <= z_daten[ebene];
				l_muster <= z_muster[ebene];
				l_sx     <= z_sx[ebene];
				l_sy     <= z_sy[ebene];
				iss      <= 9'd0;
				x        <= 9'd0;
				case (z_typ[ebene])
					3'd1: begin iss_n <= z_opt[ebene][0] ? 9'd160 : 9'd80; st <= S_HOLEN1; end
					3'd2: begin iss_n <= 9'd82;  st <= S_HOLEN1; end
					3'd3, 3'd4: begin iss_n <= 9'd320; st <= S_STROM; end
					default: st <= ebene ? S_IDLE : S_LOESCH;
				endcase
			end
			S_LOESCH: begin                          // Ebene A aus: Farbe 0
				punkt(x, 8'd0, 8'd0, 1'b0, 1'b0);
				x <= x + 9'd1;
				if (x == 9'd319) st <= S_WEITER;
			end
			S_HOLEN1, S_HOLEN2: begin
				if (iss != iss_n) begin
					vram_addr <= h_addr;
					p1_v      <= 1'b1;
					p1_i      <= iss;
					iss       <= iss + 9'd1;
				end
				else if (!p1_v && !p2_v) begin       // Pipeline leer
					iss <= 9'd0;
					if (st == S_HOLEN1) begin
						st    <= S_HOLEN2;
						iss_n <= (l_typ == 3'd1) ? {2'd0, l_cols} : 9'd164;
					end
					else st <= S_MALEN;
				end
			end
			S_MALEN: begin
				punkt(x, m_g, m_u, m_tg, m_tu);
				x <= x + 9'd1;
				if (x == 9'd319) st <= S_WEITER;
			end
			S_STROM: begin
				if (iss != iss_n) begin
					if (l_typ == 3'd4 || !iss[0]) begin   // Bitmap 16: nur jeden zweiten Takt
						vram_addr <= h_addr;
						p1_v      <= 1'b1;
						p1_i      <= (l_typ == 3'd4) ? iss : {1'b0, iss[8:1]};
					end
					iss <= iss + 9'd1;
				end
				else if (!p1_v && !p2_v && !strom_rest) st <= S_WEITER;
			end
			S_WEITER: begin
				if (!ebene) begin
					ebene <= 1'b1;
					st    <= S_START;
				end
				else st <= S_IDLE;
			end
			default: ;
		endcase
	end
	if (reset) begin
		st         <= S_IDLE;
		strom_rest <= 1'b0;
	end
end

//////////////////////////////  KOBOLD  /////////////////////////////////////

wire k_start = ce_pix && line_end && (v_next < V_VIS - 9'd1 || v_next == v_last);

kobold kobold
(
	.clk(clk),
	.reset(reset),
	.reg_addr(kob_addr),
	.reg_din(kob_din),
	.reg_dout(kob_dout),
	.reg_we(kob_we),
	.start(k_start),
	.zeile((v_next == v_last) ? 9'd0 : v_next + 9'd1),
	.puffer(front),
	.aus_addr(lb_raddr),
	.aus_gueltig(k_gueltig),
	.aus_farbe(k_farbe),
	.aus_hinten(k_hinten),
	.aus_schatten(k_schatten),
	.kontur_an(tusche[0]),
	.tinte(tinte)
);

//////////////////////////////  Ausgabe  ////////////////////////////////////

// Pufferadresse folgt dem Zaehler; ein Takt spaeter liegt der Index vor,
// noch einen Takt spaeter die Farbe. Stufe a beim uebernaechsten ce_pix,
// deshalb laufen die Syncs eine Stufe (d_*) mit. Danach Leuchten: Bild und
// Syncs laufen gemeinsam durch eine Verzoegerung, waehrend zwei Kasten-
// filter (je 16 Punkte) die Leuchtpunkte waagrecht verteilen.
reg d_vis, d_hbl, d_vbl, d_hs, d_vs;
reg        lm_d;                          // Leuchtbit des Punktes (wie pal_q)
always @(posedge clk) lm_d <= lmaske[lb_q];

reg [28:0] a_bild;                        // Stufe a: leuchtet, Farbe, hbl, vbl, hs, vs
reg [23:0] a_l;                           // Leuchtquelle
reg [23:0] b1 [0:15];                     // Kasten 1: letzte 16 Quellpunkte
reg [11:0] s1r, s1g, s1b;
reg [35:0] b2 [0:15];                     // Kasten 2: letzte 16 Summen
reg [15:0] s2r, s2g, s2b;
reg [28:0] vz [0:16];                     // Bild 17 Punkte verzoegert (Mitte der Filter)
reg [23:0] lh, lh2;                       // Hof waagrecht, dieser Punkt
reg [28:0] lb1, lb2;                      // Bild dazu
reg  [9:0] lx;                            // Punkt in der Zeile (verzoegert)
reg  [1:0] lz;                            // Zeilenplatz 0-2 (fuer y)
reg        lhbl;
reg [23:0] hz0 [0:639], hz1 [0:639], hz2 [0:639];   // Hof der letzten Zeilen
reg [23:0] lq1, lq2;                      // y-1, y-2
wire [1:0] lz1 = (lz == 2'd0) ? 2'd2 : lz - 2'd1;
wire [1:0] lz2 = (lz1 == 2'd0) ? 2'd2 : lz1 - 2'd1;
integer    li;

function [7:0] hof_dazu(input [7:0] bild, input [7:0] m2, input [7:0] m1, input [7:0] h0, input [3:0] st);
	reg [9:0]  v;
	reg [12:0] w;
	reg [13:0] t;
	begin
		v = ({2'd0, m2} + {1'b0, m1, 1'b0} + {2'd0, h0}) >> 2;            // 1-2-1
		w = (st[0] ? {3'd0, v} : 13'd0) + (st[1] ? {2'd0, v, 1'b0} : 13'd0) +
		    (st[2] ? {1'd0, v, 2'b00} : 13'd0) + (st[3] ? {v, 3'b000} : 13'd0);
		t = {6'd0, bild} + {1'b0, w[12:3]};                               // * Staerke / 8
		hof_dazu = (t > 14'd255) ? 8'd255 : t[7:0];
	end
endfunction

always @(posedge clk) begin
	if (ce_pix) begin
		// Stufe a: der Punkt wie bisher (mit Schatten), dazu die Leuchtquelle
		a_bild[27:4] <= !d_vis ? 24'h000000 :
		                sch_d  ? {1'b0, pal_q[23:17], 1'b0, pal_q[15:9], 1'b0, pal_q[7:1]} : pal_q;
		a_bild[3:0]  <= {d_hbl, d_vbl, d_hs, d_vs};
		a_bild[28]   <= d_vis && lm_d;
		a_l          <= (d_vis && lm_d && leucht != 4'd0) ? pal_q : 24'h000000;
		// zwei Kaesten (laufende Summen) und die Verzoegerung des Bildes
		for (li = 15; li > 0; li = li - 1) begin
			b1[li] <= b1[li - 1];
			b2[li] <= b2[li - 1];
		end
		b1[0] <= a_l;
		s1r <= s1r + {4'd0, a_l[23:16]} - {4'd0, b1[15][23:16]};
		s1g <= s1g + {4'd0, a_l[15:8]}  - {4'd0, b1[15][15:8]};
		s1b <= s1b + {4'd0, a_l[7:0]}   - {4'd0, b1[15][7:0]};
		b2[0] <= {s1r, s1g, s1b};
		s2r <= s2r + {4'd0, s1r} - {4'd0, b2[15][35:24]};
		s2g <= s2g + {4'd0, s1g} - {4'd0, b2[15][23:12]};
		s2b <= s2b + {4'd0, s1b} - {4'd0, b2[15][11:0]};
		for (li = 16; li > 0; li = li - 1) vz[li] <= vz[li - 1];
		vz[0] <= a_bild;
		// Hof dieses Punktes (Summe / 256) und das Bild dazu
		lh   <= {s2r[15:8], s2g[15:8], s2b[15:8]};
		lb1  <= vz[16];
		lx   <= vz[16][3] ? 10'h3FF : lx + 10'd1;
		lhbl <= vz[16][3];
		if (lhbl && !vz[16][3]) lz <= (lz == 2'd2) ? 2'd0 : lz + 2'd1;   // neue Zeile
		// Zeilenspeicher: diese Zeile schreiben, y-1 und y-2 lesen
		if (!lb1[3]) begin
			if (lz == 2'd0) hz0[lx] <= lh;
			if (lz == 2'd1) hz1[lx] <= lh;
			if (lz == 2'd2) hz2[lx] <= lh;
		end
		lq1 <= (lz1 == 2'd0) ? hz0[lx] : (lz1 == 2'd1) ? hz1[lx] : hz2[lx];
		lq2 <= (lz2 == 2'd0) ? hz0[lx] : (lz2 == 2'd1) ? hz1[lx] : hz2[lx];
		lh2 <= lh;
		lb2 <= lb1;
		// Ausgabe: Bild plus Hof mal Staerke - Leuchtpunkte selbst behalten
		// ihre Farbe, der Hof liegt auf den Nachbarn
		r <= hof_dazu(lb2[27:20], lq2[23:16], lq1[23:16], lh2[23:16], lb2[28] ? 4'd0 : leucht);
		g <= hof_dazu(lb2[19:12], lq2[15:8],  lq1[15:8],  lh2[15:8],  lb2[28] ? 4'd0 : leucht);
		b <= hof_dazu(lb2[11:4],  lq2[7:0],   lq1[7:0],   lh2[7:0],   lb2[28] ? 4'd0 : leucht);
		hblank <= lb2[3];
		vblank <= lb2[2];
		hsync  <= lb2[1];
		vsync  <= lb2[0];
		d_vis  <= (hc < H_VIS) && (vc < V_VIS);
		d_hbl  <= (hc >= H_VIS);
		d_vbl  <= (vc >= V_VIS);
		d_hs   <= (hc >= HS_BEG) && (hc < HS_END);
		d_vs   <= pal ? (vc >= 9'd270 && vc < 9'd273) : (vc >= 9'd244 && vc < 9'd247);
	end
end

endmodule
