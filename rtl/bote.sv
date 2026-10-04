//============================================================================
//  BOTE - Programmlader des MERIDIAN (Etappe 3, Zusatzspeicher seit 9b)
//
//  Bringt Programme und Daten ins Chip-RAM (Baenke $00-$03) und in den
//  Zusatzspeicher (Baenke $04-$FE), auf zwei Wegen:
//   1. aus dem MiSTer-Menue (Datei *.MER, kommt Byte fuer Byte ueber ioctl)
//   2. ueber das Netz: der Linux-Teil des MiSTer legt das Programm in ein
//      Postfach im DDR3-RAM (physisch POSTFACH), BOTE schaut alle 2,7 ms
//      nach und kopiert neue Programme per DMA.
//  Waehrend des Kopierens haelt BOTE die CPU an (RDY). Ins Chip-RAM
//  schreibt er ein Byte je Takt; der Zusatzspeicher nimmt ein Byte erst an,
//  wenn ZUSATZ frei ist (zus_gnt) - bis dahin wartet BOTE, beim Laden aus
//  dem Menue ueber ioctl_wait auch der MiSTer. Ist im Programm
//  "Autostart" gesetzt, loest er danach einen NMI aus; das Kern-ROM
//  startet das Programm dann.
//
//  Dateiformat MER: 16 Byte Kopf, danach die Daten
//   0-3  "MER", Version 1     4-6  Ladeadresse    7  Bit 0: Autostart
//   8-10 Startadresse         11   frei           12-15 Laenge der Daten
//
//  Module (Etappe 10): Eine Datei aus dem Menue-Eintrag 2 (*.MOD) ist ein
//  ROM-Abbild wie ein Steckmodul. BOTE legt es ohne Kopf ab $40:0000 in den
//  Zusatzspeicher (hoechstens 4 MB) und merkt sich "Modul steckt"; der
//  Bereich $40:0000-$7F:FFFF ist dann schreibgeschuetzt (der Speicher-
//  verwalter ignoriert Schreibzugriffe von CPU und KRAN, BOTE laedt keine
//  Programme dorthin). Danach - und beim Auswerfen - startet BOTE den
//  Rechner neu (reset_anf); das Kern-ROM startet das Modul. "Modul steckt"
//  uebersteht jeden Reset, nur das Auswerfen loescht es.
//
//  Postfach im DDR3 (64-Bit-Woerter):
//   Wort 0: Folgenummer (Bits 0-31) - wird als Letztes geschrieben
//   Wort 1-2: MER-Kopf, ab Wort 3: Daten
//
//  Register ab $00:C200:
//   $00 STATUS   Bit 0: neues Programm geladen, Bit 1: Autostart angefordert
//                (1 schreiben loescht), Bit 2: Modul steckt, Bit 3: Modul
//                nicht starten (Menue "Modulstart: aus"), Bit 7: laedt
//   $01-$03      Ladeadresse    $04-$06 Startadresse    $07 Flags
//   $08-$0A      Laenge         $0B Quelle (1 = Menue, 2 = Netz)
//============================================================================

module bote
#(
	parameter [28:0] POSTFACH = 29'h07C00000      // physisch $3E000000
)
(
	input             clk,
	input             reset,

	// Laden aus dem MiSTer-Menue
	input             ioctl_download,
	input       [7:0] ioctl_index,
	input             ioctl_wr,
	input      [26:0] ioctl_addr,
	input       [7:0] ioctl_dout,
	output            ioctl_wait,

	// Module
	input             modul_aus,        // Menue: Modulstart aus
	input             modul_raus,       // Menue: Modul auswerfen
	output reg        modul_da = 1'b0,  // Modul steckt: $40-$7F schreibgeschuetzt
	output            reset_anf,        // Rechner neu starten

	// DDR3 (Avalon, 64 Bit)
	output reg [28:0] ddr_addr,
	output reg        ddr_rd,
	input             ddr_busy,
	input      [63:0] ddr_dout,
	input             ddr_dout_ready,

	// Chip-RAM schreiben (CPU steht solange)
	output reg        halt,
	output reg [17:0] ram_addr,
	output reg  [7:0] ram_data,
	output reg        ram_we,

	// Zusatzspeicher schreiben: zus_req haelt an, bis zus_gnt kommt
	output reg        zus_req,
	output reg [23:0] zus_addr,
	output reg  [7:0] zus_data,
	input             zus_gnt,

	// CPU-Seite
	input       [7:0] reg_addr,
	input       [7:0] reg_din,
	output reg  [7:0] reg_dout,
	input             reg_we,
	output            nmi_n
);

reg  [7:0] kopf [0:15];
reg        geladen, start_an;
reg  [1:0] quelle;
reg  [6:0] nmi_cnt;

wire [23:0] k_lade  = {kopf[6], kopf[5], kopf[4]};
wire [23:0] k_start = {kopf[10], kopf[9], kopf[8]};
wire  [7:0] k_flags = kopf[7];
wire [23:0] k_len   = {kopf[14], kopf[13], kopf[12]};
wire        k_gut   = kopf[0] == "M" && kopf[1] == "E" && kopf[2] == "R";

// Neustart nach dem Einstecken und Auswerfen; zaehlt auch waehrend des
// Resets weiter (darf von ihm nicht geloescht werden)
reg   [7:0] reset_cnt = 8'd0;
assign reset_anf = (reset_cnt != 8'd0);

assign nmi_n = (nmi_cnt == 7'd0);

//////////////////////////////  Gemeinsames Schreiben  ///////////////////////

// Schreibt ein Datenbyte mit Index i (ab 0): Baenke 0-3 sofort ins Chip-RAM,
// Baenke $04-$FE in den Zusatzspeicher (zus_req bis zus_gnt), Bank $FF nicht
// (dort liegt fuer die CPU das BASIC-ROM), ein steckendes Modul auch nicht
reg  [23:0] w_ziel;
task schreibe(input [23:0] i, input [7:0] d);
	begin
		w_ziel   = k_lade + i;
		ram_addr <= w_ziel[17:0];
		ram_data <= d;
		ram_we   <= (w_ziel[23:18] == 6'd0);
		zus_addr <= w_ziel;
		zus_data <= d;
		zus_req  <= (w_ziel[23:18] != 6'd0) && (w_ziel[23:16] != 8'hFF) &&
		            !(modul_da && w_ziel[23:22] == 2'b01);
	end
endtask

// Modul: Byte i des Abbilds nach $40:0000 + i (bis 4 MB)
task schreibe_modul(input [26:0] i, input [7:0] d);
	begin
		zus_addr <= {2'b01, i[21:0]};
		zus_data <= d;
		zus_req  <= (i[26:22] == 5'd0);
	end
endtask
wire ist_modul = (ioctl_index[5:0] == 6'd2);

// Kann ein neues Byte geschrieben werden? (kein Zusatz-Byte mehr offen)
wire frei_fuer_byte = !zus_req || zus_gnt;
assign ioctl_wait = zus_req;

//////////////////////////////  Netz: DDR3-Postfach  ////////////////////////

localparam [3:0] N_RUHE = 4'd0, N_LESEN = 4'd1, N_WARTEN = 4'd2, N_FOLGE = 4'd3,
                 N_KOPF1 = 4'd4, N_KOPF2 = 4'd5, N_DATEN = 4'd6, N_BYTES = 4'd7,
                 N_FERTIG = 4'd8;

reg  [3:0] n_state, n_weiter;
reg [15:0] n_takt;
reg [31:0] folge_alt;
reg        folge_bekannt;
reg [21:0] n_wort;          // Datenwort-Nummer
reg [23:0] n_index;         // Byte-Index in den Daten
reg [63:0] n_puffer;
reg  [2:0] n_byte;
reg [63:0] n_gelesen;

// Ein Wort lesen und danach in Zustand 'weiter' gehen
task lies(input [28:0] adr, input [3:0] weiter);
	begin
		ddr_addr <= adr;
		ddr_rd   <= 1'b1;
		n_weiter <= weiter;
		n_state  <= N_LESEN;
	end
endtask

//////////////////////////////  Ablauf  ////////////////////////////////////

reg  dl_alt;
reg [23:0] dl_len;
reg  dl_modul;                      // laufendes Menue-Laden ist ein Modul
reg  raus_alt;

reg  dl_ende;                       // Menue-Laden fertig, letztes Byte noch offen?

always @(posedge clk) begin
	ram_we <= 1'b0;
	if (zus_gnt) zus_req <= 1'b0;
	dl_alt <= ioctl_download;
	if (nmi_cnt != 7'd0) nmi_cnt <= nmi_cnt - 7'd1;
	if (reset_cnt != 8'd0) reset_cnt <= reset_cnt - 8'd1;

	// Modul auswerfen (Menue): Schutz weg, neu starten
	raus_alt <= modul_raus;
	if (modul_raus && !raus_alt && modul_da) begin
		modul_da  <= 1'b0;
		reset_cnt <= 8'hFF;
	end

	//---------------- Menue ----------------
	if (ioctl_download) begin
		halt <= 1'b1;
		if (!dl_alt) begin                     // Beginn: Modul oder Programm?
			dl_modul <= ist_modul;
			if (ist_modul) modul_da <= 1'b0;    // altes Modul ist weg
		end
		if (ioctl_wr) begin
			if (ist_modul) schreibe_modul(ioctl_addr, ioctl_dout);
			else if (ioctl_addr < 27'd16) kopf[ioctl_addr[3:0]] <= ioctl_dout;
			else if (k_gut) begin
				schreibe(ioctl_addr[23:0] - 24'd16, ioctl_dout);
				dl_len <= ioctl_addr[23:0] - 24'd15;
			end
		end
	end
	else if (dl_alt || dl_ende) begin      // Menue-Laden fertig ...
		dl_ende <= 1'b1;
		if (frei_fuer_byte) begin             // ... sobald das letzte Byte geschrieben ist
			dl_ende <= 1'b0;
			halt    <= 1'b0;
			if (dl_modul) begin                 // Modul steckt: neu starten
				modul_da  <= 1'b1;
				reset_cnt <= 8'hFF;
			end
			else if (k_gut) begin
				geladen  <= 1'b1;
				quelle   <= 2'd1;
				kopf[12] <= dl_len[7:0];
				kopf[13] <= dl_len[15:8];
				kopf[14] <= dl_len[23:16];
				kopf[15] <= 8'd0;
				if (k_flags[0]) begin
					start_an <= 1'b1;
					nmi_cnt  <= 7'd100;
				end
			end
		end
	end

	//---------------- Netz ----------------
	else begin
		case (n_state)
			N_RUHE: begin
				n_takt <= n_takt + 16'd1;
				if (n_takt == 16'hFFFF) lies(POSTFACH, N_FOLGE);
			end
			N_LESEN: if (!ddr_busy) begin       // Anfrage angenommen
				ddr_rd  <= 1'b0;
				n_state <= N_WARTEN;
			end
			N_WARTEN: if (ddr_dout_ready) begin
				n_gelesen <= ddr_dout;
				n_state   <= n_weiter;
			end
			N_FOLGE: begin
				if (!folge_bekannt) begin        // nach dem Start: alten Inhalt ignorieren
					folge_alt     <= n_gelesen[31:0];
					folge_bekannt <= 1'b1;
					n_state       <= N_RUHE;
				end
				else if (n_gelesen[31:0] != folge_alt && n_gelesen[31:0] != 32'd0) begin
					folge_alt <= n_gelesen[31:0];
					lies(POSTFACH + 29'd1, N_KOPF1);
				end
				else n_state <= N_RUHE;
			end
			N_KOPF1: begin
				{kopf[7], kopf[6], kopf[5], kopf[4], kopf[3], kopf[2], kopf[1], kopf[0]} <= n_gelesen;
				lies(POSTFACH + 29'd2, N_KOPF2);
			end
			N_KOPF2: begin
				{kopf[15], kopf[14], kopf[13], kopf[12], kopf[11], kopf[10], kopf[9], kopf[8]} <= n_gelesen;
				if (k_gut && n_gelesen[55:32] != 24'd0) begin
					halt    <= 1'b1;
					n_wort  <= 22'd0;
					n_index <= 24'd0;
					lies(POSTFACH + 29'd3, N_DATEN);
				end
				else n_state <= N_RUHE;
			end
			N_DATEN: begin
				n_puffer <= n_gelesen;
				n_byte   <= 3'd0;
				n_state  <= N_BYTES;
			end
			N_BYTES: if (frei_fuer_byte) begin
				schreibe(n_index, n_puffer[7:0]);
				n_puffer <= {8'h00, n_puffer[63:8]};
				n_index  <= n_index + 24'd1;
				n_byte   <= n_byte + 3'd1;
				if (n_index + 24'd1 == k_len) n_state <= N_FERTIG;
				else if (n_byte == 3'd7) begin
					n_wort <= n_wort + 22'd1;
					lies(POSTFACH + 29'd4 + {7'd0, n_wort}, N_DATEN);
				end
			end
			N_FERTIG: if (frei_fuer_byte) begin
				halt    <= 1'b0;
				geladen <= 1'b1;
				quelle  <= 2'd2;
				if (k_flags[0]) begin
					start_an <= 1'b1;
					nmi_cnt  <= 7'd100;
				end
				n_state <= N_RUHE;
			end
			default: n_state <= N_RUHE;
		endcase
	end

	//---------------- CPU ----------------
	if (reg_we && reg_addr == 8'h00) begin
		if (reg_din[0]) geladen  <= 1'b0;
		if (reg_din[1]) start_an <= 1'b0;
	end

	if (reset) begin
		halt          <= 1'b0;
		zus_req       <= 1'b0;
		dl_ende       <= 1'b0;
		dl_modul      <= 1'b0;
		geladen       <= 1'b0;
		start_an      <= 1'b0;
		nmi_cnt       <= 7'd0;
		ddr_rd        <= 1'b0;
		n_state       <= N_RUHE;
		n_takt        <= 16'd0;
		folge_bekannt <= 1'b0;
	end
end

always @* begin
	case (reg_addr)
		8'h00:   reg_dout = {halt, 3'd0, modul_aus, modul_da, start_an, geladen};
		8'h01:   reg_dout = kopf[4];
		8'h02:   reg_dout = kopf[5];
		8'h03:   reg_dout = kopf[6];
		8'h04:   reg_dout = kopf[8];
		8'h05:   reg_dout = kopf[9];
		8'h06:   reg_dout = kopf[10];
		8'h07:   reg_dout = kopf[7];
		8'h08:   reg_dout = kopf[12];
		8'h09:   reg_dout = kopf[13];
		8'h0A:   reg_dout = kopf[14];
		8'h0B:   reg_dout = {6'd0, quelle};
		default: reg_dout = 8'hFF;
	endcase
end

endmodule
