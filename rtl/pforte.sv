//============================================================================
//  PFORTE - Ein-/Ausgabechip des MERIDIAN (Etappe 2: Tastatur, Joysticks;
//  Etappe 3: Timer und Mikrosekundenuhr; Etappe 11: Maus und Uhrzeit)
//
//  Tastatur: Der MiSTer liefert PS/2-Scancodes (Satz 2) als Ereignisse.
//  PFORTE sammelt sie in einem Puffer fuer 16 Ereignisse; die Umsetzung in
//  Zeichen (deutsches Layout) macht das Kern-ROM.
//  Joysticks: zwei Ports, Bits wie vom MiSTer geliefert.
//
//  Register ab $00:C100:
//   $00 TASTE      Scancode des aeltesten Ereignisses
//   $01 TASTINFO   Bit 7: Ereignis vorhanden, Bit 1: erweitert (E0),
//                  Bit 0: losgelassen
//   $02 WEITER     schreiben: aeltestes Ereignis verwerfen
//   $04 IRQ_ST     Bit 0: neue Taste, Bit 1: Timer A, Bit 2: Timer B abgelaufen;
//                  1 schreiben loescht
//   $05 IRQ_EN     gleiche Bits: Interrupt freigeben
//   $08/$09        Joystick 1: Bit 0 rechts, 1 links, 2 runter, 3 hoch,
//                  4 Feuer A, 5 Feuer B, ... (MiSTer-Belegung)
//   $0A/$0B        Joystick 2
//   $0C LAYOUT     Bit 0: Mac-Tastatur (Einstellung im MiSTer-Menue),
//                  Bit 1: MEGA65-Tastatur (nur der MEGA65-Port setzt es)
//   $10-$13 UHR    Mikrosekunden seit dem Start (32 Bit); Schreiben auf $10
//                  friert den Stand zum Lesen ein
//   $14/$15        Timer A: Schreiben = Startwert, Lesen = Zaehlerstand
//   $16 TA_STEUER  Bit 0: laeuft, Bit 1: nur einmal
//   $18/$19        Timer B, $1A TB_STEUER wie Timer A
//  Die Timer zaehlen im Mikrosekundentakt abwaerts; bei 0 laden sie den
//  Startwert neu und setzen ihr IRQ-Bit.
//
//   Maus (vom MiSTer als PS/2-Pakete):
//   $20/$21 MAUS_X   Position 0..X_MAX (schreiben setzt sie)
//   $22/$23 MAUS_Y   Position 0..Y_MAX, oben 0
//   $24 MAUS_T       Bit 0 links, 1 rechts, 2 Mitte
//   $25 MAUS_RAD     Raddrehungen (zaehlt mit Vorzeichen, laeuft ueber)
//   $26/$27 X_MAX    Grenzen (Vorgabe 319 und 239)
//   $28/$29 Y_MAX
//   $2A MAUS_FEST    schreiben: X, Y, Tasten und Rad zum Lesen festhalten
//                    (gelesen wird immer der festgehaltene Stand)
//
//   Uhr (stellt der MiSTer beim Start des Cores, danach zaehlt PFORTE selbst,
//   mit Kalender bis 2099; alles BCD):
//   $30 SEK  $31 MIN  $32 STD  $33 TAG  $34 MON  $35 JAHR (2-stellig)
//   $36 WTAG (0 = Sonntag)
//   $37 UHR_ST  lesen: Bit 0 = gestellt; schreiben: Stand festhalten
//   Schreiben auf $30-$36 stellt die Uhr.
//
//  Absichtlich keine Nebenwirkung beim Lesen: Der 65816 erzeugt bei
//  manchen Adressierungsarten Blindlesezugriffe.
//============================================================================

module pforte
(
	input             clk,
	input             reset,

	input      [10:0] ps2_key,      // [10] Wechsel = neues Ereignis, [9] gedrueckt, [8] E0, [7:0] Code
	input      [15:0] joy0,
	input      [15:0] joy1,
	input             layout_mac,
	input             layout_m65,   // MEGA65-Belegung im Kern-ROM (MiSTer: 0)

	input      [24:0] ps2_mouse,    // [24] Wechsel, [23:16] dY, [15:8] dX, [7:0] Status
	input       [7:0] ps2_mouse_ext, // Rad (Schritte mit Vorzeichen)
	input      [64:0] rtc,          // [64] Wechsel, BCD: sek min std tag mon jahr wtag

	input       [7:0] reg_addr,
	input       [7:0] reg_din,
	output reg  [7:0] reg_dout,
	input             reg_we,
	output            irq
);

//////////////////////////////  Timer  ////////////////////////////////////

reg  [4:0] vorteiler;               // 24 MHz / 24 = 1 MHz
wire       us = (vorteiler == 5'd23);
reg [31:0] uhr, uhr_fest;
reg [15:0] ta, ta_start, tb, tb_start;
reg  [1:0] ta_st, tb_st;
reg        ta_ab, tb_ab;            // abgelaufen (fuer IRQ_ST)

always @(posedge clk) begin
	vorteiler <= us ? 5'd0 : vorteiler + 5'd1;
	ta_ab <= 1'b0;
	tb_ab <= 1'b0;
	if (us) begin
		uhr <= uhr + 32'd1;
		if (ta_st[0]) begin
			if (ta == 16'd0) begin
				ta    <= ta_start;
				ta_ab <= 1'b1;
				if (ta_st[1]) ta_st[0] <= 1'b0;
			end
			else ta <= ta - 16'd1;
		end
		if (tb_st[0]) begin
			if (tb == 16'd0) begin
				tb    <= tb_start;
				tb_ab <= 1'b1;
				if (tb_st[1]) tb_st[0] <= 1'b0;
			end
			else tb <= tb - 16'd1;
		end
	end
	if (reg_we) begin
		case (reg_addr)
			8'h10: uhr_fest       <= uhr;
			8'h14: ta_start[7:0]  <= reg_din;
			8'h15: ta_start[15:8] <= reg_din;
			8'h16: begin ta_st <= reg_din[1:0]; if (reg_din[0]) ta <= ta_start; end
			8'h18: tb_start[7:0]  <= reg_din;
			8'h19: tb_start[15:8] <= reg_din;
			8'h1A: begin tb_st <= reg_din[1:0]; if (reg_din[0]) tb <= tb_start; end
			default: ;
		endcase
	end
	if (reset) begin
		uhr   <= 32'd0;
		ta_st <= 2'b00;
		tb_st <= 2'b00;
	end
end

//////////////////////////////  Maus  /////////////////////////////////////

reg [15:0] mx = 16'd160, my = 16'd120, mx_max = 16'd319, my_max = 16'd239;
reg [15:0] mx_f = 16'd160, my_f = 16'd120;
reg  [2:0] mtasten = 3'd0, mtasten_f = 3'd0;
reg  [7:0] mrad = 8'd0, mrad_f = 8'd0;
reg        m_alt = 1'b0;

// Bewegung: 9 Bit mit Vorzeichen; PS/2 zaehlt Y nach oben, der Bildschirm
// nach unten
wire signed [16:0] m_dx = {{9{ps2_mouse[4]}}, ps2_mouse[15:8]};
wire signed [16:0] m_dy = {{9{ps2_mouse[5]}}, ps2_mouse[23:16]};
wire signed [17:0] mx_neu = $signed({2'b00, mx}) + m_dx;
wire signed [17:0] my_neu = $signed({2'b00, my}) - m_dy;

always @(posedge clk) begin
	m_alt <= ps2_mouse[24];
	if (ps2_mouse[24] != m_alt) begin
		mx      <= (mx_neu < 0) ? 16'd0 : (mx_neu > $signed({2'b00, mx_max})) ? mx_max : mx_neu[15:0];
		my      <= (my_neu < 0) ? 16'd0 : (my_neu > $signed({2'b00, my_max})) ? my_max : my_neu[15:0];
		mtasten <= ps2_mouse[2:0];
		mrad    <= mrad - ps2_mouse_ext;    // positiv: Rad nach vorn (vom Benutzer weg)
	end
	if (reg_we) begin
		case (reg_addr)
			8'h20: mx[7:0]      <= reg_din;
			8'h21: mx[15:8]     <= reg_din;
			8'h22: my[7:0]      <= reg_din;
			8'h23: my[15:8]     <= reg_din;
			8'h26: mx_max[7:0]  <= reg_din;
			8'h27: mx_max[15:8] <= reg_din;
			8'h28: my_max[7:0]  <= reg_din;
			8'h29: my_max[15:8] <= reg_din;
			8'h2A: begin
				mx_f      <= mx;
				my_f      <= my;
				mtasten_f <= mtasten;
				mrad_f    <= mrad;
			end
			default: ;
		endcase
	end
end

//////////////////////////////  Uhrzeit  //////////////////////////////////

// BCD-Uhr mit Kalender. Der MiSTer schickt die Ortszeit nur beim Start des
// Cores; danach zaehlt PFORTE die Sekunden selbst (24 MHz / 24 000 000).
reg [24:0] sek_teiler = 25'd0;
// bis der MiSTer sie stellt: Donnerstag, 1. Januar 2026, 0:00 Uhr
reg  [7:0] u_sek = 8'h00, u_min = 8'h00, u_std = 8'h00, u_tag = 8'h01, u_mon = 8'h01, u_jahr = 8'h26;
reg  [2:0] u_wtag = 3'd4;
reg        u_gestellt = 1'b0;
reg [55:0] u_fest = 56'd0;
reg        rtc_alt = 1'b0;

function [7:0] bcd_plus1(input [7:0] b);
	bcd_plus1 = (b[3:0] == 4'd9) ? {b[7:4] + 4'd1, 4'd0} : {b[7:4], b[3:0] + 4'd1};
endfunction

// Tage im Monat (BCD); Schaltjahr, wenn die Jahreszahl durch 4 teilbar ist
// (10 = 2 mod 4, also zaehlt Zehner * 2 + Einer)
wire [4:0] j_mod = {u_jahr[7:4], 1'b0} + {1'b0, u_jahr[3:0]};
wire       schalt = (j_mod[1:0] == 2'd0);
reg  [7:0] monat_tage;
always @* begin
	case (u_mon)
		8'h02:                             monat_tage = schalt ? 8'h29 : 8'h28;
		8'h04, 8'h06, 8'h09, 8'h11:        monat_tage = 8'h30;
		default:                           monat_tage = 8'h31;
	endcase
end

always @(posedge clk) begin
	rtc_alt <= rtc[64];
	sek_teiler <= sek_teiler + 25'd1;
	if (sek_teiler == 25'd23_999_999) begin
		sek_teiler <= 25'd0;
		u_sek <= bcd_plus1(u_sek);
		if (u_sek == 8'h59) begin
			u_sek <= 8'h00;
			u_min <= bcd_plus1(u_min);
			if (u_min == 8'h59) begin
				u_min <= 8'h00;
				u_std <= bcd_plus1(u_std);
				if (u_std == 8'h23) begin
					u_std  <= 8'h00;
					u_wtag <= (u_wtag == 3'd6) ? 3'd0 : u_wtag + 3'd1;
					u_tag  <= bcd_plus1(u_tag);
					if (u_tag == monat_tage) begin
						u_tag <= 8'h01;
						u_mon <= bcd_plus1(u_mon);
						if (u_mon == 8'h12) begin
							u_mon  <= 8'h01;
							u_jahr <= (u_jahr == 8'h99) ? 8'h00 : bcd_plus1(u_jahr);
						end
					end
				end
			end
		end
	end
	if (rtc[64] != rtc_alt) begin              // der MiSTer stellt die Uhr
		{u_wtag, u_jahr, u_mon, u_tag, u_std, u_min, u_sek} <= {rtc[50:48], rtc[47:0]};
		sek_teiler <= 25'd0;
		u_gestellt <= 1'b1;
	end
	if (reg_we) begin
		case (reg_addr)
			8'h30: begin u_sek <= reg_din; sek_teiler <= 25'd0; u_gestellt <= 1'b1; end
			8'h31: u_min  <= reg_din;
			8'h32: u_std  <= reg_din;
			8'h33: u_tag  <= reg_din;
			8'h34: u_mon  <= reg_din;
			8'h35: u_jahr <= reg_din;
			8'h36: u_wtag <= reg_din[2:0];
			8'h37: u_fest <= {5'd0, u_wtag, u_jahr, u_mon, u_tag, u_std, u_min, u_sek};
			default: ;
		endcase
	end
end

//////////////////////////////  Tastatur  /////////////////////////////////

reg  [9:0] fifo [0:15];        // {E0, losgelassen, Code}
reg  [3:0] rd, wr;
reg  [4:0] count;
reg        last_strobe;
reg  [2:0] irq_st, irq_en;

wire       neu   = (ps2_key[10] != last_strobe);
wire       pop   = reg_we && reg_addr == 8'h02 && count != 5'd0;
wire       push  = neu && count != 5'd16;
wire [9:0] kopf  = fifo[rd];

always @(posedge clk) begin
	last_strobe <= ps2_key[10];
	if (push) begin
		fifo[wr] <= {ps2_key[8], ~ps2_key[9], ps2_key[7:0]};
		wr       <= wr + 4'd1;
	end
	if (pop) rd <= rd + 4'd1;
	count <= count + (push ? 5'd1 : 5'd0) - (pop ? 5'd1 : 5'd0);

	if (push && ps2_key[9]) irq_st[0] <= 1'b1;
	if (ta_ab) irq_st[1] <= 1'b1;
	if (tb_ab) irq_st[2] <= 1'b1;
	if (reg_we && reg_addr == 8'h04) irq_st <= irq_st & ~reg_din[2:0];
	if (reg_we && reg_addr == 8'h05) irq_en <= reg_din[2:0];

	if (reset) begin
		rd     <= 4'd0;
		wr     <= 4'd0;
		count  <= 5'd0;
		irq_st <= 3'b000;
		irq_en <= 3'b000;
	end
end

assign irq = |(irq_st & irq_en);

always @* begin
	case (reg_addr)
		8'h00:   reg_dout = kopf[7:0];
		8'h01:   reg_dout = {count != 5'd0, 5'd0, kopf[9:8]};
		8'h04:   reg_dout = {5'd0, irq_st};
		8'h05:   reg_dout = {5'd0, irq_en};
		8'h08:   reg_dout = joy0[7:0];
		8'h09:   reg_dout = joy0[15:8];
		8'h0A:   reg_dout = joy1[7:0];
		8'h0B:   reg_dout = joy1[15:8];
		8'h0C:   reg_dout = {6'd0, layout_m65, layout_mac};
		8'h10:   reg_dout = uhr_fest[7:0];
		8'h11:   reg_dout = uhr_fest[15:8];
		8'h12:   reg_dout = uhr_fest[23:16];
		8'h13:   reg_dout = uhr_fest[31:24];
		8'h14:   reg_dout = ta[7:0];
		8'h15:   reg_dout = ta[15:8];
		8'h16:   reg_dout = {6'd0, ta_st};
		8'h18:   reg_dout = tb[7:0];
		8'h19:   reg_dout = tb[15:8];
		8'h1A:   reg_dout = {6'd0, tb_st};
		8'h20:   reg_dout = mx_f[7:0];
		8'h21:   reg_dout = mx_f[15:8];
		8'h22:   reg_dout = my_f[7:0];
		8'h23:   reg_dout = my_f[15:8];
		8'h24:   reg_dout = {5'd0, mtasten_f};
		8'h25:   reg_dout = mrad_f;
		8'h26:   reg_dout = mx_max[7:0];
		8'h27:   reg_dout = mx_max[15:8];
		8'h28:   reg_dout = my_max[7:0];
		8'h29:   reg_dout = my_max[15:8];
		8'h30:   reg_dout = u_fest[7:0];
		8'h31:   reg_dout = u_fest[15:8];
		8'h32:   reg_dout = u_fest[23:16];
		8'h33:   reg_dout = u_fest[31:24];
		8'h34:   reg_dout = u_fest[39:32];
		8'h35:   reg_dout = u_fest[47:40];
		8'h36:   reg_dout = u_fest[55:48];
		8'h37:   reg_dout = {7'd0, u_gestellt};
		default: reg_dout = 8'hFF;
	endcase
end

endmodule
