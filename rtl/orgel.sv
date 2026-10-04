//============================================================================
//  ORGEL - Klangchip des MERIDIAN (Etappe 6)
//
//  Vier Synthesestimmen mit SID-Seele und vier Samplekanaele mit Paula-Seele,
//  gemischt in Stereo. Alles laeuft im Mikrosekundentakt (1 MHz).
//
//  Synthesestimmen wie beim SID: 24-Bit-Phasenzaehler, Frequenz 16 Bit
//  (f = F * 1 MHz / 2^24 = F * 0,0596 Hz - SID-Notentabellen passen),
//  Dreieck, Saegezahn, Puls (12 Bit Pulsbreite), Rauschen (23-Bit-LFSR),
//  kombinierbar (UND); Ringmodulation und Hard-Sync mit der vorigen Stimme
//  (Stimme 1 mit Stimme 4); ADSR mit den Zeittabellen des SID, Abklingen
//  exponentiell. Mehr als beim SID: Lautstaerke und Panorama je Stimme.
//  Filter: Zustandsvariablenfilter (Tief-/Band-/Hochpass) mit Resonanz,
//  Eckfrequenz 30 Hz - 12 kHz, jede Stimme einzeln durchs Filter.
//
//  Samplekanaele wie bei Paula: 8-Bit-Samples mit Vorzeichen aus dem
//  Chip-RAM per DMA, Schrittweite 16 Bit (Abspielrate = S * 15,26 Hz),
//  Laenge bis 64 KB, Schleife, Lautstaerke 0-63, Panorama.
//
//  Register ab $00:C500 (Stimmen bewusst in SID-Reihenfolge):
//   Stimme n = 0..3 ab $00 + n*$10:
//    +0/+1 FREQ   +2/+3 PULS (12 Bit)
//    +4 STEUER    Bit 0 Gate, 1 Sync, 2 Ring, 3 Test, 4 Dreieck, 5 Saege,
//                 6 Puls, 7 Rauschen
//    +5 AD        Attack (oben) / Decay (unten)
//    +6 SR        Sustain (oben) / Release (unten)
//    +7 LAUT      0-15 (nach dem Einschalten 15)
//    +8 PAN       links (oben) / rechts (unten), je 0-15 (Start $FF)
//    +9 HUELLE    lesen: Huellkurve 0-255
//    +A OSZ       lesen: Wellenform, obere 8 Bit
//   Filter ab $40:
//    $40/$41 ECKE (11 Bit)
//    $42     Resonanz (oben), Stimmen durchs Filter (unten, Bit n = Stimme n)
//    $43     Bit 4 Tief, 5 Band, 6 Hoch; Bits 0-3 Gesamtlautstaerke
//   Samplekanal k = 0..3 ab $80 + k*$10:
//    +0..+2 START  +3/+4 LAENGE  +5/+6 SCHLEIFE (Ruecksprung, ab Start)
//    +7/+8 SCHRITT  +9 LAUT (0-63)  +A PAN
//    +B STEUER    Bit 0 spielen, Bit 1 Schleife; Schreiben mit Bit 0 = 1
//                 startet von vorn, mit Bit 0 = 0 haelt an.
//                 Lesen: Bit 0 = spielt noch
//    +C/+D        lesen: Position im Sample
//============================================================================

module orgel
(
	input             clk,          // 24 MHz
	input             reset,

	input       [7:0] reg_addr,
	input       [7:0] reg_din,
	output reg  [7:0] reg_dout,
	input             reg_we,

	// Sample-DMA aufs Chip-RAM: dma_gnt sagt die Anfrage im selben Takt zu,
	// dma_ack kommt einen Takt danach, dann liegen die Daten an
	output            dma_req,
	output     [17:0] dma_addr,
	input             dma_gnt,
	input             dma_ack,
	input       [7:0] dma_data,

	output reg signed [15:0] links,
	output reg signed [15:0] rechts
);

//////////////////////////////  Zeitbasis  //////////////////////////////////

reg [4:0] vt;
reg       tick;                     // 1 MHz
always @(posedge clk) begin
	tick <= (vt == 5'd23);
	vt   <= (vt == 5'd23) ? 5'd0 : vt + 5'd1;
end

//////////////////////////////  Register  ///////////////////////////////////

reg [15:0] s_freq [0:3];
reg [11:0] s_puls [0:3];
reg  [7:0] s_st   [0:3];
reg  [7:0] s_ad   [0:3];
reg  [7:0] s_sr   [0:3];
reg  [3:0] s_laut [0:3];
reg  [7:0] s_pan  [0:3];

reg [10:0] f_ecke;
reg  [7:0] f_rf;                    // Resonanz / Filterstimmen
reg  [7:0] f_modus;

reg [23:0] k_start [0:3];
reg [15:0] k_len   [0:3];
reg [15:0] k_loop  [0:3];
reg [15:0] k_schr  [0:3];
reg  [5:0] k_laut  [0:3];
reg  [7:0] k_pan   [0:3];
reg        k_schl  [0:3];
reg  [3:0] k_neu;                   // Start angefordert
reg  [3:0] k_halt;                  // Stopp angefordert

wire [1:0] rn = reg_addr[5:4];      // Stimme bzw. Kanal

integer i;
always @(posedge clk) begin
	k_neu  <= 4'd0;
	k_halt <= 4'd0;
	if (reg_we) begin
		if (reg_addr[7:6] == 2'b00) begin
			case (reg_addr[3:0])
				4'h0: s_freq[rn][7:0]  <= reg_din;
				4'h1: s_freq[rn][15:8] <= reg_din;
				4'h2: s_puls[rn][7:0]  <= reg_din;
				4'h3: s_puls[rn][11:8] <= reg_din[3:0];
				4'h4: s_st[rn]         <= reg_din;
				4'h5: s_ad[rn]         <= reg_din;
				4'h6: s_sr[rn]         <= reg_din;
				4'h7: s_laut[rn]       <= reg_din[3:0];
				4'h8: s_pan[rn]        <= reg_din;
				default: ;
			endcase
		end
		else if (reg_addr[7:4] == 4'h4) begin
			case (reg_addr[3:0])
				4'h0: f_ecke[7:0]  <= reg_din;
				4'h1: f_ecke[10:8] <= reg_din[2:0];
				4'h2: f_rf         <= reg_din;
				4'h3: f_modus      <= reg_din;
				default: ;
			endcase
		end
		else if (reg_addr[7:6] == 2'b10) begin
			case (reg_addr[3:0])
				4'h0: k_start[rn][7:0]   <= reg_din;
				4'h1: k_start[rn][15:8]  <= reg_din;
				4'h2: k_start[rn][23:16] <= reg_din;
				4'h3: k_len[rn][7:0]     <= reg_din;
				4'h4: k_len[rn][15:8]    <= reg_din;
				4'h5: k_loop[rn][7:0]    <= reg_din;
				4'h6: k_loop[rn][15:8]   <= reg_din;
				4'h7: k_schr[rn][7:0]    <= reg_din;
				4'h8: k_schr[rn][15:8]   <= reg_din;
				4'h9: k_laut[rn]         <= reg_din[5:0];
				4'hA: k_pan[rn]          <= reg_din;
				4'hB: begin
					k_schl[rn] <= reg_din[1];
					if (reg_din[0]) k_neu[rn]  <= 1'b1;
					else            k_halt[rn] <= 1'b1;
				end
				default: ;
			endcase
		end
	end
	if (reset) begin
		for (i = 0; i < 4; i = i + 1) begin
			s_st[i]   <= 8'd0;
			s_laut[i] <= 4'd15;
			s_pan[i]  <= 8'hFF;
			k_laut[i] <= 6'd63;
			k_pan[i]  <= 8'hFF;
			k_schl[i] <= 1'b0;
		end
		f_rf    <= 8'h00;
		f_modus <= 8'h0F;
		k_halt  <= 4'hF;
	end
end

//////////////////////////////  Synthesestimmen  ////////////////////////////

// SID-Zeittabelle: Mikrosekunden je Huellkurvenschritt
function automatic [14:0] periode(input [3:0] r);
	case (r)
		4'd0:  periode = 15'd9;     4'd1:  periode = 15'd32;    4'd2:  periode = 15'd63;
		4'd3:  periode = 15'd95;    4'd4:  periode = 15'd149;   4'd5:  periode = 15'd220;
		4'd6:  periode = 15'd267;   4'd7:  periode = 15'd313;   4'd8:  periode = 15'd392;
		4'd9:  periode = 15'd977;   4'd10: periode = 15'd1954;  4'd11: periode = 15'd3126;
		4'd12: periode = 15'd3907;  4'd13: periode = 15'd11720; 4'd14: periode = 15'd19532;
		default: periode = 15'd31251;
	endcase
endfunction

// Exponentielles Abklingen: Zeitschritte je Huellkurvenstufe (wie SID)
function automatic [4:0] exp_periode(input [7:0] e);
	if (e > 8'd93)      exp_periode = 5'd1;
	else if (e > 8'd54) exp_periode = 5'd2;
	else if (e > 8'd26) exp_periode = 5'd4;
	else if (e > 8'd14) exp_periode = 5'd8;
	else if (e > 8'd6)  exp_periode = 5'd16;
	else                exp_periode = 5'd30;
endfunction

localparam [1:0] H_ATTACK = 2'd0, H_DECAY = 2'd1, H_RELEASE = 2'd2;

reg [23:0] acc   [0:3];
reg [22:0] lfsr  [0:3];
reg  [7:0] env   [0:3];
reg  [1:0] hst   [0:3];
reg [14:0] rcnt  [0:3];
reg  [4:0] ecnt  [0:3];
reg        gate_a[0:3];
reg        msb_a [0:3];             // Bit 23 vor dem letzten Schritt (Sync)
reg        b19_a [0:3];             // Bit 19 vor dem letzten Schritt (Rauschen)
reg [11:0] welle [0:3];

// Partner fuer Sync und Ring: die vorige Stimme, Stimme 0 nimmt Stimme 3
function automatic [1:0] vor(input [1:0] n);
	vor = n - 2'd1;
endfunction

reg [11:0] w_tri, w_saw, w_pul, w_noi, w;
reg        w_any;
reg [14:0] w_per;
integer    v;
always @(posedge clk) begin
	if (tick) begin
		for (v = 0; v < 4; v = v + 1) begin
			// Phase
			msb_a[v] <= acc[v][23];
			b19_a[v] <= acc[v][19];
			if (s_st[v][3]) acc[v] <= 24'd0;                                          // Test
			else if (s_st[v][1] && acc[vor(v[1:0])][23] && !msb_a[vor(v[1:0])])
				acc[v] <= 24'd0;                                                      // Sync
			else acc[v] <= acc[v] + {8'd0, s_freq[v]};
			// Rauschen: ein Schritt, wenn Bit 19 steigt
			if (s_st[v][3]) lfsr[v] <= 23'h7FFFF8;
			else if (acc[v][19] && !b19_a[v]) lfsr[v] <= {lfsr[v][21:0], lfsr[v][22] ^ lfsr[v][17]};

			// Wellenformen
			w_saw = acc[v][23:12];
			w_tri = (acc[v][23] ^ (s_st[v][2] && acc[vor(v[1:0])][23])) ? ~acc[v][22:11] : acc[v][22:11];
			w_pul = (acc[v][23:12] >= s_puls[v]) ? 12'hFFF : 12'h000;
			w_noi = {lfsr[v][20], lfsr[v][18], lfsr[v][14], lfsr[v][11],
			         lfsr[v][9], lfsr[v][5], lfsr[v][2], lfsr[v][0], 4'h0};
			w     = 12'hFFF;
			w_any = 1'b0;
			if (s_st[v][4]) begin w = w & w_tri; w_any = 1'b1; end
			if (s_st[v][5]) begin w = w & w_saw; w_any = 1'b1; end
			if (s_st[v][6]) begin w = w & w_pul; w_any = 1'b1; end
			if (s_st[v][7]) begin w = w & w_noi; w_any = 1'b1; end
			welle[v] <= w_any ? w : 12'h800;                                         // Mitte = still

			// Huellkurve
			gate_a[v] <= s_st[v][0];
			w_per = periode(hst[v] == H_ATTACK ? s_ad[v][7:4] :
			                hst[v] == H_DECAY  ? s_ad[v][3:0] : s_sr[v][3:0]);
			if (s_st[v][0] && !gate_a[v]) begin
				hst[v]  <= H_ATTACK;
				rcnt[v] <= 15'd0;
			end
			else if (!s_st[v][0] && gate_a[v]) begin
				hst[v]  <= H_RELEASE;
				rcnt[v] <= 15'd0;
				ecnt[v] <= 5'd0;
			end
			else if (rcnt[v] < w_per) rcnt[v] <= rcnt[v] + 15'd1;
			else begin
				rcnt[v] <= 15'd0;
				if (hst[v] == H_ATTACK) begin
					if (env[v] == 8'hFF) hst[v] <= H_DECAY;
					else begin
						env[v] <= env[v] + 8'd1;
						if (env[v] == 8'hFE) hst[v] <= H_DECAY;
					end
					ecnt[v] <= 5'd0;
				end
				else if (ecnt[v] + 5'd1 >= exp_periode(env[v])) begin
					ecnt[v] <= 5'd0;
					if (hst[v] == H_DECAY) begin
						if (env[v] > {s_sr[v][7:4], s_sr[v][7:4]}) env[v] <= env[v] - 8'd1;
					end
					else if (env[v] != 8'd0) env[v] <= env[v] - 8'd1;
				end
				else ecnt[v] <= ecnt[v] + 5'd1;
			end
		end
	end
	if (reset) begin
		for (v = 0; v < 4; v = v + 1) begin
			acc[v]  <= 24'd0;
			env[v]  <= 8'd0;
			hst[v]  <= H_RELEASE;
			rcnt[v] <= 15'd0;
			ecnt[v] <= 5'd0;
			lfsr[v] <= 23'h7FFFF8;
		end
	end
end

//////////////////////////////  Samplekanaele  //////////////////////////////

reg [15:0] k_pos  [0:3];            // Index im Sample
reg [15:0] k_frac [0:3];            // Nachkommastellen
reg        k_an   [0:3];
reg        k_hol  [0:3];            // neues Byte noetig
reg  [7:0] k_wert [0:3];
reg  [1:0] dma_k;                   // gerade bediente Anfrage
reg        dma_busy;
reg        dma_gew;                 // zugesagt, Daten kommen

reg [16:0] kf;
reg [16:0] kp;
integer    m;
always @(posedge clk) begin
	// Erst die DMA-Antwort, damit ein im selben Takt neu angefordertes Byte
	// (Schritt weiter) nicht verloren geht
	if (dma_ack) begin
		k_wert[dma_k] <= dma_data;
		k_hol[dma_k]  <= 1'b0;
		dma_busy      <= 1'b0;
		dma_gew       <= 1'b0;
	end
	else if (dma_gnt) dma_gew <= 1'b1;
	else if (!dma_busy) begin
		if      (k_hol[0]) begin dma_k <= 2'd0; dma_busy <= 1'b1; end
		else if (k_hol[1]) begin dma_k <= 2'd1; dma_busy <= 1'b1; end
		else if (k_hol[2]) begin dma_k <= 2'd2; dma_busy <= 1'b1; end
		else if (k_hol[3]) begin dma_k <= 2'd3; dma_busy <= 1'b1; end
	end
	for (m = 0; m < 4; m = m + 1) begin
		if (k_neu[m]) begin
			k_an[m]   <= (k_len[m] != 16'd0);
			k_pos[m]  <= 16'd0;
			k_frac[m] <= 16'd0;
			k_hol[m]  <= 1'b1;
		end
		else if (k_halt[m]) k_an[m] <= 1'b0;
		else if (tick && k_an[m]) begin
			kf = {1'b0, k_frac[m]} + {1'b0, k_schr[m]};
			k_frac[m] <= kf[15:0];
			if (kf[16]) begin
				kp = {1'b0, k_pos[m]} + 17'd1;
				if (kp >= {1'b0, k_len[m]}) begin
					if (k_schl[m]) begin
						k_pos[m] <= k_loop[m];
						k_hol[m] <= 1'b1;
					end
					else k_an[m] <= 1'b0;
				end
				else begin
					k_pos[m] <= kp[15:0];
					k_hol[m] <= 1'b1;
				end
			end
		end
	end
	if (reset) begin
		dma_busy <= 1'b0;
		dma_gew  <= 1'b0;
		for (m = 0; m < 4; m = m + 1) begin
			k_an[m]   <= 1'b0;
			k_hol[m]  <= 1'b0;
			k_wert[m] <= 8'd0;
		end
	end
end

wire [23:0] dma_voll = k_start[dma_k] + {8'd0, k_pos[dma_k]};
assign dma_req  = dma_busy && !dma_gew;
assign dma_addr = dma_voll[17:0];

//////////////////////////////  Filter und Mischpult  ///////////////////////

// Chamberlin-Zustandsvariablenfilter bei 1 MHz. Die Zustaende tragen 8 Bit
// Nachkommastellen, sonst bleiben tiefe Eckfrequenzen im Rundungsfehler
// stecken. F = 2*pi*fc/1MHz in Q16 (30 Hz .. 12 kHz), Daempfung in Q16
// (1,41 ohne Resonanz bis 0,14 bei Resonanz 15).
wire        [19:0] f_mal = {9'd0, f_ecke} * 20'd632;
wire        [15:0] f_F   = 16'd12 + {4'd0, f_mal[19:8]};
wire        [17:0] f_q   = 18'd92680 - {14'd0, f_rf[7:4]} * 18'd5570;
reg  signed [27:0] f_tief, f_band, f_hoch, f_ein;
reg  signed [19:0] stimme [0:3];    // Stimme nach Huellkurve und Lautstaerke
reg  signed [21:0] s_l, s_r, k_l, k_r, roh;
reg  signed [45:0] p;
reg  signed [23:0] st_a, st_b;
reg  signed [21:0] summe_l, summe_r;
reg  signed [26:0] laut_l, laut_r;

// Samplekanaele: Wert * Lautstaerke * Panorama
wire signed [17:0] k_sl [0:3];
wire signed [17:0] k_sr [0:3];
genvar g;
generate
	for (g = 0; g < 4; g = g + 1) begin : kanal_mix
		wire signed [14:0] kv = $signed(k_wert[g]) * $signed({1'b0, k_laut[g]});
		assign k_sl[g] = k_an[g] ? kv * $signed({1'b0, k_pan[g][7:4]}) : 18'sd0;
		assign k_sr[g] = k_an[g] ? kv * $signed({1'b0, k_pan[g][3:0]}) : 18'sd0;
	end
endgenerate

// Synthesestimmen am Filter vorbei: Wert * Panorama
wire signed [24:0] s_pl [0:3];
wire signed [24:0] s_pr [0:3];
generate
	for (g = 0; g < 4; g = g + 1) begin : stimme_mix
		wire signed [19:0] sv = f_rf[g] ? 20'sd0 : stimme[g];
		assign s_pl[g] = sv * $signed({1'b0, s_pan[g][7:4]});
		assign s_pr[g] = sv * $signed({1'b0, s_pan[g][3:0]});
	end
endgenerate

function automatic signed [15:0] begrenzen(input signed [26:0] x);
	if (x > 27'sd32767)       begrenzen = 16'sd32767;
	else if (x < -27'sd32767) begrenzen = -16'sd32767;
	else                      begrenzen = x[15:0];
endfunction

// Nach jedem tick ein Durchlauf: 1 Stimmen, 2 Filtereingang, 3-5 Filter,
// 6-7 Panorama, 8-9 Ausgang
reg  [3:0] phase;
integer    j;
always @(posedge clk) begin
	phase <= tick ? 4'd1 : (phase == 4'd0 || phase == 4'd10) ? 4'd0 : phase + 4'd1;
	case (phase)
		4'd1: for (j = 0; j < 4; j = j + 1) begin
			// (Welle - Mitte) * Huelle / 256 * Laut / 16: +-2048
			st_a = ($signed({12'd0, welle[j]}) - 24'sd2048) * $signed({16'd0, env[j]});
			st_b = (st_a >>> 8) * $signed({20'd0, s_laut[j]});
			stimme[j] <= 20'(st_b >>> 4);
		end
		4'd2: f_ein <= ((f_rf[0] ? 28'(stimme[0]) : 28'sd0) + (f_rf[1] ? 28'(stimme[1]) : 28'sd0) +
		                (f_rf[2] ? 28'(stimme[2]) : 28'sd0) + (f_rf[3] ? 28'(stimme[3]) : 28'sd0)) <<< 8;
		4'd3: begin                                     // tief += F * band
			p = $signed({1'b0, f_F}) * f_band;
			f_tief <= f_tief + 28'(p >>> 16);
		end
		4'd4: begin                                     // hoch = ein - tief - q * band
			p = $signed({1'b0, f_q}) * f_band;
			f_hoch <= f_ein - f_tief - 28'(p >>> 16);
		end
		4'd5: begin                                     // band += F * hoch
			p = $signed({1'b0, f_F}) * f_hoch;
			f_band <= f_band + 28'(p >>> 16);
		end
		4'd6: begin
			// ungefilterte Stimmen mit Panorama, der Filterausgang in die Mitte
			s_l <= 22'((s_pl[0] + s_pl[1] + s_pl[2] + s_pl[3]) >>> 4);
			s_r <= 22'((s_pr[0] + s_pr[1] + s_pr[2] + s_pr[3]) >>> 4);
			roh <= 22'(((f_modus[4] ? f_tief : 28'sd0) + (f_modus[5] ? f_band : 28'sd0) +
			            (f_modus[6] ? f_hoch : 28'sd0)) >>> 8);
		end
		4'd7: begin
			// Samples: +-128 * 63 * 15 / 64 = +-1890, so laut wie eine Stimme
			k_l <= (22'(k_sl[0]) + 22'(k_sl[1]) + 22'(k_sl[2]) + 22'(k_sl[3])) >>> 6;
			k_r <= (22'(k_sr[0]) + 22'(k_sr[1]) + 22'(k_sr[2]) + 22'(k_sr[3])) >>> 6;
		end
		4'd8: begin
			summe_l <= s_l + roh + k_l;
			summe_r <= s_r + roh + k_r;
		end
		4'd9: begin
			// Gesamtlautstaerke * 3/16: eine Stimme allein -16 dBFS, alle acht
			// zugleich an der Grenze erst, wenn alle ganz oben stehen
			laut_l <= (27'(summe_l) * $signed({1'b0, f_modus[3:0]}) * 27'sd3) >>> 4;
			laut_r <= (27'(summe_r) * $signed({1'b0, f_modus[3:0]}) * 27'sd3) >>> 4;
		end
		4'd10: begin
			links  <= begrenzen(laut_l);
			rechts <= begrenzen(laut_r);
		end
		default: ;
	endcase
	if (reset) begin
		f_tief <= 28'sd0;
		f_band <= 28'sd0;
		f_hoch <= 28'sd0;
		links  <= 16'sd0;
		rechts <= 16'sd0;
	end
end

//////////////////////////////  Lesen  //////////////////////////////////////

always @* begin
	reg_dout = 8'hFF;
	if (reg_addr[7:6] == 2'b00) begin
		case (reg_addr[3:0])
			4'h9: reg_dout = env[rn];
			4'hA: reg_dout = welle[rn][11:4];
			default: ;
		endcase
	end
	else if (reg_addr[7:6] == 2'b10) begin
		case (reg_addr[3:0])
			4'hB: reg_dout = {7'd0, k_an[rn]};
			4'hC: reg_dout = k_pos[rn][7:0];
			4'hD: reg_dout = k_pos[rn][15:8];
			default: ;
		endcase
	end
end

endmodule
