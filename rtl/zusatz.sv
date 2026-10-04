//============================================================================
//  ZUSATZ - SDRAM-Steuerung fuer den Zusatzspeicher des MERIDIAN (Etappe 8)
//
//  Das SDRAM-Modul des MiSTer (16 Bit breit) wird zum Zusatzspeicher in den
//  Baenken $04-$FF: knapp 16 MB, die nur die CPU sieht (wie die Fast RAM des
//  Amiga - die Chips arbeiten weiter im Chip-RAM).
//
//  Takt 48 MHz, synchron zum 24-MHz-Systemtakt (dieselbe PLL). Das SDRAM
//  bekommt den Takt invertiert: Befehle wechseln an der steigenden Flanke,
//  das SDRAM liest sie an der fallenden - je 10 ns Luft. Gelesen wird auf
//  der fallenden Flanke 3,5 Takte nach dem READ.
//
//  Ablauf eines Zugriffs (CAS-Latenz 2, Burst 1, automatisches Vorladen):
//    t0 ACTIVE  t1 -  t2 READ/WRITE  ...  t6 Daten (Lesen)  t6 frei
//  Alle 7,5 us eine Auffrischung, wenn gerade nichts zu tun ist.
//
//  Byte-Masken: Auf den MiSTer-Modulen (128 MB) haengen die DQM-Eingaenge der
//  Chips an A11 (unten) und A12 (oben); beim READ/WRITE sind das keine
//  Adressbits. Deshalb liegt die Maske dort - und zur Sicherheit auch auf
//  den DQML/DQMH-Leitungen.
//
//  Auftraege kommen als Umschalt-Handschlag aus dem 24-MHz-Bereich: req_t
//  wechselt, wenn adr/we/din gueltig sind; ack_t folgt, wenn erledigt.
//============================================================================

module zusatz
(
	input             clk,          // 48 MHz
	input             reset,

	input             req_t,
	input      [23:0] adr,
	input             we,
	input       [7:0] din,
	output reg        ack_t,
	output reg  [7:0] q,
	output reg [15:0] q16,          // ganzes Wort (fuer den Wortpuffer)
	output reg        bereit,

	output reg [12:0] sd_a,
	output reg  [1:0] sd_ba,
	output reg        sd_ncs,
	output reg        sd_nras,
	output reg        sd_ncas,
	output reg        sd_nwe,
	output reg        sd_dqml,
	output reg        sd_dqmh,
	output reg [15:0] sd_dq_o,
	output reg        sd_dq_oe,
	input      [15:0] sd_dq_i
);

// Befehle {nCS, nRAS, nCAS, nWE}
localparam [3:0] C_NOP = 4'b0111, C_ACT = 4'b0011, C_READ = 4'b0101, C_WRITE = 4'b0100,
                 C_PRE = 4'b0010, C_REF = 4'b0001, C_MODE = 4'b0000;

localparam [2:0] Z_INIT = 3'd0, Z_RUHE = 3'd1, Z_LAUF = 3'd2, Z_AUFFR = 3'd3;

reg  [2:0] st;
reg [14:0] warte;                   // Einschaltwartezeit und Init-Schritte
reg  [3:0] schritt;
reg  [8:0] auffr_zaehler;
reg        auffr_faellig;
reg        r_we, r_byte;
reg  [7:0] r_din;
reg [15:0] dq_neg;

task befehl(input [3:0] c);
	{sd_ncs, sd_nras, sd_ncas, sd_nwe} <= c;
endtask

// Lesedaten an der fallenden Flanke abholen (Mitte des Datenfensters)
always @(negedge clk) dq_neg <= sd_dq_i;

always @(posedge clk) begin
	befehl(C_NOP);
	sd_dq_oe <= 1'b0;

	// Auffrischung alle 360 Takte (7,5 us) vormerken
	if (auffr_zaehler == 9'd359) begin
		auffr_zaehler <= 9'd0;
		auffr_faellig <= 1'b1;
	end
	else auffr_zaehler <= auffr_zaehler + 9'd1;

	case (st)
		Z_INIT: begin
			// 200 us warten, dann alles vorladen, 8 x auffrischen, Modus setzen
			if (warte != 15'd0) warte <= warte - 15'd1;
			else begin
				schritt <= schritt + 4'd1;
				warte   <= 15'd7;
				case (schritt)
					4'd0: begin befehl(C_PRE); sd_a[10] <= 1'b1; end
					4'd1, 4'd2, 4'd3, 4'd4, 4'd5, 4'd6, 4'd7, 4'd8: befehl(C_REF);
					4'd9: begin
						befehl(C_MODE);
						sd_ba <= 2'b00;
						sd_a  <= 13'h220;           // CAS 2, Burst 1, Einzelschreiben
					end
					default: begin
						st     <= Z_RUHE;
						bereit <= 1'b1;
					end
				endcase
			end
		end

		Z_RUHE: begin
			if (auffr_faellig) begin
				befehl(C_REF);
				auffr_faellig <= 1'b0;
				schritt <= 4'd0;
				st      <= Z_AUFFR;
			end
			else if (req_t != ack_t) begin
				// Wort-Adresse = adr[23:1]: Spalte 9 Bit, Bank 2 Bit, Zeile 12 Bit
				befehl(C_ACT);
				sd_ba   <= adr[11:10];
				sd_a    <= {1'b0, adr[23:12]};
				sd_dqml <= 1'b0;
				sd_dqmh <= 1'b0;
				r_we    <= we;
				r_byte  <= adr[0];
				r_din   <= din;
				schritt <= 4'd0;
				st      <= Z_LAUF;
			end
		end

		Z_LAUF: begin
			schritt <= schritt + 4'd1;
			case (schritt)
				4'd1: begin                          // tRCD erfuellt: lesen/schreiben
					sd_a[10]  <= 1'b1;                // automatisch vorladen
					sd_a[9]   <= 1'b0;
					sd_a[8:0] <= adr[9:1];
					if (r_we) begin
						befehl(C_WRITE);
						sd_dq_o   <= {r_din, r_din};
						sd_dq_oe  <= 1'b1;
						sd_a[12]  <= !r_byte;         // Maske oben (DQMH)
						sd_a[11]  <= r_byte;          // Maske unten (DQML)
						sd_dqml   <= r_byte;          // das andere Byte maskieren
						sd_dqmh   <= !r_byte;
						ack_t     <= req_t;           // Schreiben gilt als erledigt
					end
					else begin
						befehl(C_READ);
						sd_a[12:11] <= 2'b00;          // beide Bytes lesen
					end
				end
				4'd5: begin                          // Lesedaten (fallende Flanke davor)
					if (!r_we) begin
						q     <= r_byte ? dq_neg[15:8] : dq_neg[7:0];
						q16   <= dq_neg;
						ack_t <= req_t;
					end
					st <= Z_RUHE;
				end
				default: ;
			endcase
		end

		Z_AUFFR: begin                               // tRFC: 4 Takte
			schritt <= schritt + 4'd1;
			if (schritt == 4'd3) st <= Z_RUHE;
		end

		default: st <= Z_RUHE;
	endcase

	if (reset) begin
		st            <= Z_INIT;
		warte         <= 15'd9600;
		schritt       <= 4'd0;
		bereit        <= 1'b0;
		ack_t         <= req_t;
		auffr_zaehler <= 9'd0;
		auffr_faellig <= 1'b0;
		sd_dqml       <= 1'b1;
		sd_dqmh       <= 1'b1;
		befehl(C_NOP);
	end
end

endmodule
