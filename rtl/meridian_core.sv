//============================================================================
//  MERIDIAN 816 - Rechnerkern (Etappe 8)
//
//  65C816 mit 8 MHz (24 MHz Systemtakt, jeder dritte Takt ein Buszyklus),
//  256 KB Chip-RAM (Dual-Port: CPU und PINSEL lesen gleichzeitig),
//  12 KB Kern-ROM, Grafikchip PINSEL, Ein-/Ausgabechip PFORTE,
//  Programmlader BOTE (MiSTer-Menue und Netz ueber DDR3), Klangchip ORGEL,
//  Copper LOTSE und Blitter KRAN, Zusatzspeicher im SDRAM (ZUSATZ).
//
//  Speicherkarte (CPU):
//   $00:0000-$00:BFFF  RAM (Bank 0)
//   $00:C000-$00:C0FF  PINSEL (Grafik)
//   $00:C100-$00:C1FF  PFORTE (Tastatur, Joysticks)
//   $00:C200-$00:C2FF  BOTE (Programmlader)
//   $00:C300-$00:C4FF  KOBOLD (Sprites, Teil von PINSEL)
//   $00:C500-$00:C5FF  ORGEL (Klang)
//   $00:C600-$00:C6FF  KRAN (Blitter)
//   $00:C700-$00:C7FF  LOTSE (Copper)
//   $00:C800-$00:CFFF  frei fuer weitere Chips (liest $FF)
//   $00:D000-$00:FFFF  ROM (Kernal, Vektoren)
//   $01:0000-$03:FFFF  RAM (Baenke 1-3)
//   $04:0000-$FE:FFFF  Zusatzspeicher im SDRAM (nur fuer die CPU)
//   $FF:0000-$FF:3FFF  BASIC-ROM (der Kern kopiert es beim Start nach Bank 0)
//
//  Copyright (c) 2026 retro-modern.net. GPL-3.0-or-later,
//  weil der CPU-Kern (P65C816 von srg320) unter GPL-3 steht.
//============================================================================

module meridian_core
#(
	parameter ROM_FILE   = "rom/kern.hex",
	parameter BASIC_FILE = "rom/basic.hex",
	parameter DOS_FILE   = "rom/dos.hex",
	parameter SONG_FILE  = "rom/song.hex"
)
(
	input         clk,          // 24 MHz
	input         clk48,        // 48 MHz, phasengleich (SDRAM)
	input         reset,
	input         pal,

	input  [10:0] ps2_key,      // vom MiSTer (hps_io)
	input  [24:0] ps2_mouse,
	input   [7:0] ps2_mouse_ext,
	input  [64:0] rtc,
	input  [15:0] joy0,
	input  [15:0] joy1,
	input         layout_mac,

	input         ioctl_download,   // Laden aus dem MiSTer-Menue
	input   [7:0] ioctl_index,      // 1 Programm (*.MER), 2 Modul (*.MOD)
	input         ioctl_wr,
	input  [26:0] ioctl_addr,
	input   [7:0] ioctl_dout,
	output        ioctl_wait,       // BOTE wartet auf den Zusatzspeicher
	input         modul_aus,        // Menue: Modul beim Start nicht starten
	input         modul_raus,       // Menue: Modul auswerfen

	input   [2:0] img_mounted,      // Laufwerke (TRUHE): Images vom Rahmenwerk
	input         img_readonly,
	input  [63:0] img_size,
	output [31:0] sd_lba,
	output  [5:0] sd_blk_cnt,       // Bloecke je Auftrag - 1
	output  [2:0] sd_rd,
	output  [2:0] sd_wr,
	input   [2:0] sd_ack,
	input  [13:0] sd_buff_addr,
	input   [7:0] sd_buff_dout,
	output  [7:0] sd_buff_din,
	input         sd_buff_wr,

	output [28:0] ddr_addr,         // DDR3: Postfach (BOTE) und Fenster (DRAHT)
	output        ddr_rd,
	output        ddr_we,
	output [63:0] ddr_din,
	output  [7:0] ddr_be,
	input         ddr_busy,
	input  [63:0] ddr_dout,
	input         ddr_dout_ready,

	output        ce_pix,
	output        hblank,
	output        vblank,
	output        hsync,
	output        vsync,
	output  [7:0] r,
	output  [7:0] g,
	output  [7:0] b,

	output [15:0] audio_l,
	output [15:0] audio_r,

	output [12:0] sd_a,             // SDRAM (Zusatzspeicher)
	output  [1:0] sd_ba,
	output        sd_ncs,
	output        sd_nras,
	output        sd_ncas,
	output        sd_nwe,
	output        sd_dqml,
	output        sd_dqmh,
	output [15:0] sd_dq_o,
	output        sd_dq_oe,
	input  [15:0] sd_dq_i,

	output [23:0] dbg_addr,     // fuer die Simulation
	output        dbg_ce,
	output        dbg_we,
	output  [7:0] dbg_dout
);

//////////////////////////////  Bustakt  ////////////////////////////////////

reg [1:0] cyc = 2'd0;
always @(posedge clk) cyc <= (cyc == 2'd2) ? 2'd0 : cyc + 2'd1;
wire cpu_ce = (cyc == 2'd2);

// Neustart: von aussen (Menue, Taste) oder von BOTE (Modul eingesteckt
// oder ausgeworfen); der Zusatzspeicher (SDRAM-Steuerung) bleibt dabei
// unberuehrt, sein Inhalt - das Modul - auch
wire bote_reset;
wire modul_da;                  // Modul steckt (BOTE), $40-$7F ist ROM
wire neustart = reset | bote_reset;

reg [3:0] rst_cnt = 4'd0;
always @(posedge clk) begin
	if (neustart) rst_cnt <= 4'd0;
	else if (rst_cnt != 4'hF) rst_cnt <= rst_cnt + 4'd1;
end
wire cpu_rst_n = (rst_cnt == 4'hF);

//////////////////////////////  CPU  ////////////////////////////////////////

wire [23:0] a;
wire  [7:0] cpu_dout;
wire        cpu_we_n;
wire        vda, vpa;
reg   [7:0] cpu_din;
wire        irq_pin, irq_pfo, irq_lot, irq_kran;
wire        irq = irq_pin | irq_pfo | irq_lot | irq_kran;
wire        halt, nmi_n;
wire        schritt_nmi, schritt_scharf;    // Einzelschritt (SYSTEM, Etappe 13)
// Nach dem Laden einen Takt laenger warten: Das RAM liefert erst einen Takt
// spaeter wieder Daten zur CPU-Adresse statt zu BOTEs letzter Adresse.
reg         halt_d;
always @(posedge clk) halt_d <= halt;
wire        z_warten;
wire        n_warten;               // DRAHT: Zugriff aufs DDR3 laeuft
wire [28:0] b_ddr_addr;             // BOTE am Verteiler von DRAHT
wire        b_ddr_rd, b_ddr_busy, b_ddr_ready;
wire [63:0] b_ddr_dout;
wire  [7:0] netz_dout;
wire        cpu_rdy = !halt && !halt_d && !z_warten && !n_warten;

P65C816 cpu
(
	.CLK(clk),
	.RST_N(cpu_rst_n),
	.CE(cpu_ce),
	.RDY_IN(cpu_rdy),
	.NMI_N(nmi_n && !schritt_nmi),
	.IRQ_N(~(irq && !schritt_scharf)),
	.ABORT_N(1'b1),
	.D_IN(cpu_din),
	.D_OUT(cpu_dout),
	.A_OUT(a),
	.WE(cpu_we_n),
	.RDY_OUT(),
	.VPA(vpa),
	.VDA(vda),
	.MLB(),
	.VPB(),
	.I_FLAG()
);

assign dbg_addr = a;
assign dbg_ce   = cpu_ce;
assign dbg_we   = wr;
assign dbg_dout = cpu_dout;

//////////////////////////////  Adressdekoder  //////////////////////////////

wire bank0  = (a[23:16] == 8'h00);
wire is_ram = (bank0 && a[15:14] != 2'b11) || (a[23:16] >= 8'h01 && a[23:16] <= 8'h03);
wire is_pin = bank0 && (a[15:8] == 8'hC0);
wire is_pfo = bank0 && (a[15:8] == 8'hC1);
wire is_bot = bank0 && (a[15:8] == 8'hC2);
wire is_kob = bank0 && (a[15:8] == 8'hC3 || a[15:8] == 8'hC4);
wire is_org = bank0 && (a[15:8] == 8'hC5);
wire is_org2 = bank0 && (a[15:8] == 8'hCC);           // ORGEL Seite 2: Samplekanaele 4-7
wire is_kran = bank0 && (a[15:8] == 8'hC6);
wire is_lot = bank0 && (a[15:8] == 8'hC7);
wire is_rom = bank0 && (a[15:12] >= 4'hD);
wire is_brom = (a[23:16] == 8'hFF);
wire is_netz = (a[23:16] == 8'hFD);                   // DRAHT: Fenster ins DDR3
wire is_zus = (a[23:16] >= 8'h04) && !is_brom && !is_netz;
wire is_sys = bank0 && (a[15:8] == 8'hC8);
wire is_truhe = bank0 && (a[15:8] == 8'hC9);          // TRUHE: Register
wire is_tpuf  = bank0 && (a[15:9] == 7'b1100_101);    // TRUHE: Puffer $CA00-$CBFF

// SYSTEM ($C800), Bit 0: SPIEGEL. Bank 1 zeigt in $0000-$1FFF dieselben
// Bytes wie Bank 0 (Zeropage, Stapel, Kernseiten, Bildschirm). Damit kann
// Software mit Datenbank 1 arbeiten und erreicht trotzdem ueber absolute
// Adressen und 16-Bit-Zeiger die Zeropage und den Stapel - BASIC nutzt das
// (wie die LowRAM-Spiegelung des SNES). Nur fuer die CPU; die Chips sehen
// die echte Bank 1.
reg  sys_spiegel;
wire spiegeln = sys_spiegel && (a[23:16] == 8'h01) && (a[15:13] == 3'b000);
wire [17:0] cpu_ram_a = spiegeln ? {2'b00, a[15:0]} : a[17:0];

wire wr = cpu_ce && cpu_rdy && !cpu_we_n && vda;

always @(posedge clk) begin
	if (neustart) sys_spiegel <= 1'b0;
	else if (wr && is_sys && a[7:0] == 8'h00) sys_spiegel <= cpu_dout[0];
end

// SYSTEM Bit 1 SCHRITT, Bit 2 im Emulationsmodus (Etappe 13): Einzelschritt
// fuer den Monitor. Mit Bit 1 geschrieben wartet die Hardware auf den
// naechsten RTI und zaehlt, was er vom Stapel liest (P, PC und nativ PBR).
// Waehrend des letzten dieser Lesezugriffe zieht sie NMI: die CPU sieht die
// Flanke zu spaet fuer den RTI und nimmt den NMI nach dem ersten Befehl
// dahinter an. Bis dahin sind IRQs gesperrt (sonst liefe der Schritt in die
// Interruptroutine). Lesen: Bit 1 = der letzte NMI kam vom Schritt (bis zum
// naechsten Schreiben) - so unterscheidet der Kern ihn vom Fernstart.
reg  [1:0] s_zust;                  // 0 aus, 1 wartet auf RTI, 2 zaehlt
reg        s_emu;
reg  [1:0] s_n;
reg        s_status;
reg  [3:0] s_halten;
wire       s_takt  = cpu_ce && cpu_rdy;
wire       s_lesen = s_takt && vda && !vpa && cpu_we_n;
wire       s_letzt = (s_zust == 2'd2) && s_lesen && (s_n == (s_emu ? 2'd2 : 2'd3));
assign     schritt_nmi    = s_letzt || (s_halten != 4'd0);
assign     schritt_scharf = (s_zust != 2'd0);

always @(posedge clk) begin
	if (neustart) begin
		s_zust   <= 2'd0;
		s_status <= 1'b0;
		s_halten <= 4'd0;
	end else begin
		if (s_halten != 4'd0) s_halten <= s_halten - 4'd1;
		if (wr && is_sys && a[7:0] == 8'h00) begin
			s_status <= 1'b0;
			s_emu    <= cpu_dout[2];
			s_zust   <= cpu_dout[1] ? 2'd1 : 2'd0;
		end else case (s_zust)
			2'd1: if (s_takt && vda && vpa && cpu_din == 8'h40) begin    // RTI geholt
				s_zust <= 2'd2;
				s_n    <= 2'd0;
			end
			2'd2: if (s_lesen) begin
				if (s_letzt) begin
					s_zust   <= 2'd0;
					s_status <= 1'b1;
					s_halten <= 4'd15;
				end else s_n <= s_n + 2'd1;
			end
			default: ;
		endcase
	end
end

//////////////////////////////  Registerbus  ////////////////////////////////

// Die CPU schreibt Chipregister nur am Ende von cyc 2; in den anderen Takten
// darf LOTSE schreiben (alle Chips ausser BOTE). Gelesen wird nur von der
// CPU, und die uebernimmt ihr Byte zum Ende von cyc 2.
wire        lot_io_req;
wire [10:0] lot_io_addr;
wire  [7:0] lot_io_dat;
wire        io_lot = lot_io_req && (cyc != 2'd2);
wire [10:0] io_a   = io_lot ? lot_io_addr : a[10:0];
wire  [7:0] io_d   = io_lot ? lot_io_dat  : cpu_dout;
wire  [2:0] io_s   = lot_io_addr[10:8];
wire we_pin  = (wr && is_pin)  || (io_lot && io_s == 3'd0);
wire we_pfo  = (wr && is_pfo)  || (io_lot && io_s == 3'd1);
wire we_kob  = (wr && is_kob)  || (io_lot && (io_s == 3'd3 || io_s == 3'd4));
wire we_org  = (wr && (is_org || is_org2)) || (io_lot && io_s == 3'd5);
wire we_kran = (wr && is_kran) || (io_lot && io_s == 3'd6);
wire we_lot  = (wr && is_lot)  || (io_lot && io_s == 3'd7);

//////////////////////////////  Chip-RAM  ///////////////////////////////////

// 256 KB als echtes Dual-Port-RAM: Port A fuer CPU (oder BOTE), Port B nur
// lesend fuer PINSEL. Beim Schreiben liefert Port A die neuen Daten ("new
// data") - nur so passt es in die M10K-Bloecke. Mit "alte Daten lesen" legte
// Quartus das ganze RAM doppelt an.
reg  [7:0] ram [0:262143];
reg  [7:0] ram_q;
wire [17:0] vram_addr;
reg  [7:0] vram_q;

// Port A: Die CPU liest das RAM zum Ende von cyc 1 (sie uebernimmt das Byte
// zum Ende von cyc 2) und schreibt zum Ende von cyc 2. Jeder andere Takt ist
// frei fuer die DMA-Kunden, nach Vorrang: LOTSE (Befehle), ORGEL (Samples),
// KRAN (Bloecke). Sie bekommen gnt im selben Takt und beim Lesen die Daten
// (ack) einen Takt spaeter in ram_q. Waehrend BOTE laedt, steht die CPU, und der Port
// gehoert BOTE allein.
wire [17:0] lade_addr;
wire  [7:0] lade_data;
wire        lade_we;
wire        lot_req, org_req, kran_req, kran_we;
wire [17:0] lot_addr;
wire [23:0] org_addr;
wire        org_z = (org_addr[23:18] != 6'd0);           // Sample im Zusatzspeicher
wire        g_org_z, a_org_z;            // ORGEL am Zusatzspeicher (siehe unten)
wire        g_echo_z, a_echo_z;          // Echo der ORGEL (Etappe 16)
wire        echo_req, echo_we;
wire [23:0] echo_adr;
wire [15:0] echo_din;
reg  [15:0] z_q16_24;
wire [23:0] kran_addr;
wire  [7:0] kran_wdat;
wire        kran_chip = (kran_addr[23:18] == 6'd0);   // Baenke 0-3: Chip-RAM
wire        g_kran_z, a_kran_z;          // KRAN am Zusatzspeicher (siehe unten)
wire        bote_zreq, g_bote_z;         // BOTE am Zusatzspeicher
wire [23:0] bote_zaddr;
wire  [7:0] bote_zdata;
wire  [7:0] kran_z_q;
reg   [7:0] z_q24;
wire        cpu_liest = is_ram && (vda || vpa) && cpu_we_n;
wire        frei = !halt && ((cyc == 2'd0) || (cyc == 2'd1 && !cpu_liest) ||
                             (cyc == 2'd2 && !(wr && is_ram)));
wire        g_lot  = frei && lot_req;
wire        g_org  = frei && !lot_req && org_req && !org_z;
wire        g_kran = frei && !lot_req && !(org_req && !org_z) && kran_req && kran_chip;
reg         a_lot, a_org, a_kran;
always @(posedge clk) begin
	a_lot  <= g_lot;
	a_org  <= g_org;
	a_kran <= g_kran && !kran_we;              // nur Lesen meldet Daten
end
wire [17:0] pa_addr = halt ? lade_addr : g_lot ? lot_addr : g_org ? org_addr[17:0] :
                      g_kran ? kran_addr[17:0] : cpu_ram_a;
wire  [7:0] pa_din  = halt ? lade_data : g_kran ? kran_wdat : cpu_dout;
wire        pa_we   = halt ? lade_we   : g_kran ? kran_we : (wr && is_ram);

always @(posedge clk) begin
	if (pa_we) begin
		ram[pa_addr] <= pa_din;
		ram_q        <= pa_din;
	end
	else ram_q <= ram[pa_addr];
end

always @(posedge clk) vram_q <= ram[vram_addr];

//////////////////////////////  ROM  ////////////////////////////////////////

reg [7:0] rom [0:16383];
reg [7:0] rom_q;
initial $readmemh(ROM_FILE, rom);
always @(posedge clk) rom_q <= rom[a[13:0]];

// BASIC-ROM: Microsoft BASIC 1.1 fuer MERIDIAN, 16 KB in Bank $FF
reg [7:0] brom [0:16383];
reg [7:0] brom_q;
initial $readmemh(BASIC_FILE, brom);
always @(posedge clk) brom_q <= brom[a[13:0]];

// DOS-ROM: Bank $FF ab $4000 (Etappe 10) - Dateisystem und weitere Dienste,
// aufgerufen im nativen Modus per JSL
reg [7:0] dosrom [0:16383];
reg [7:0] dos_q;
initial $readmemh(DOS_FILE, dosrom);
always @(posedge clk) dos_q <= dosrom[a[13:0]];

// SONG-ROM: Bank $FF ab $8000 (MERIDIAN 1.0) - der Abspieler von TAKTSTOCK
// fuer BASIC SONG
reg [7:0] songrom [0:16383];
reg [7:0] song_q;
initial $readmemh(SONG_FILE, songrom);
always @(posedge clk) song_q <= songrom[a[13:0]];

//////////////////////////////  PINSEL  /////////////////////////////////////

wire [7:0] pin_dout;
wire [7:0] kob_dout;
wire [9:0] strahl_h;
wire [8:0] strahl_v, strahl_ende;

pinsel pinsel
(
	.clk(clk),
	.reset(!cpu_rst_n),
	.pal(pal),
	.reg_addr(io_a[7:0]),
	.reg_din(io_d),
	.reg_dout(pin_dout),
	.reg_we(we_pin),
	.irq(irq_pin),
	.kob_addr({io_a[10], io_a[7:0]}),
	.kob_din(io_d),
	.kob_dout(kob_dout),
	.kob_we(we_kob),
	.vram_addr(vram_addr),
	.vram_q(vram_q),
	.ce_pix(ce_pix),
	.hblank(hblank),
	.vblank(vblank),
	.hsync(hsync),
	.vsync(vsync),
	.r(r),
	.g(g),
	.b(b),
	.strahl_h(strahl_h),
	.strahl_v(strahl_v),
	.strahl_ende(strahl_ende)
);

//////////////////////////////  PFORTE  /////////////////////////////////////

wire [7:0] pfo_dout;

pforte pforte
(
	.clk(clk),
	.reset(!cpu_rst_n),
	.ps2_key(ps2_key),
	.ps2_mouse(ps2_mouse),
	.ps2_mouse_ext(ps2_mouse_ext),
	.rtc(rtc),
	.joy0(joy0),
	.joy1(joy1),
	.layout_mac(layout_mac),
	.reg_addr(io_a[7:0]),
	.reg_din(io_d),
	.reg_dout(pfo_dout),
	.reg_we(we_pfo),
	.irq(irq_pfo)
);

//////////////////////////////  BOTE  ///////////////////////////////////////

wire [7:0] bot_dout;

bote bote
(
	.clk(clk),
	.reset(!cpu_rst_n),
	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.modul_aus(modul_aus),
	.modul_raus(modul_raus),
	.modul_da(modul_da),
	.reset_anf(bote_reset),
	.ddr_addr(b_ddr_addr),
	.ddr_rd(b_ddr_rd),
	.ddr_busy(b_ddr_busy),
	.ddr_dout(b_ddr_dout),
	.ddr_dout_ready(b_ddr_ready),
	.halt(halt),
	.ram_addr(lade_addr),
	.ram_data(lade_data),
	.ram_we(lade_we),
	.zus_req(bote_zreq),
	.zus_addr(bote_zaddr),
	.zus_data(bote_zdata),
	.zus_gnt(g_bote_z),
	.ioctl_wait(ioctl_wait),
	.reg_addr(a[7:0]),
	.reg_din(cpu_dout),
	.reg_dout(bot_dout),
	.reg_we(wr && is_bot),
	.nmi_n(nmi_n)
);

//////////////////////////////  ORGEL  //////////////////////////////////////

wire [7:0] org_dout;

orgel orgel
(
	.clk(clk),
	.reset(!cpu_rst_n),
	.reg_addr(io_a[7:0]),
	.reg_din(io_d),
	.reg_dout(org_dout),
	.reg_we(we_org),
	.reg_seite(is_org2 && !io_lot),
	.dma_req(org_req),
	.dma_addr(org_addr),
	.dma_gnt(g_org || g_org_z),
	.dma_ack(a_org || a_org_z),
	.dma_data(ram_q),
	.dma_wort(a_org_z),
	.dma_data16(z_q16_24),
	.e_req(echo_req),
	.e_we(echo_we),
	.e_adr(echo_adr),
	.e_din(echo_din),
	.e_gnt(g_echo_z),
	.e_ack(a_echo_z),
	.links(audio_l),
	.rechts(audio_r)
);

//////////////////////////////  KRAN  ///////////////////////////////////////

wire [7:0] kran_dout;
wire       kran_busy;

kran kran
(
	.clk(clk),
	.reset(!cpu_rst_n),
	.reg_addr(io_a[7:0]),
	.reg_din(io_d),
	.reg_dout(kran_dout),
	.reg_we(we_kran),
	.irq(irq_kran),
	.mem_req(kran_req),
	.mem_addr(kran_addr),
	.mem_we(kran_we),
	.mem_wdat(kran_wdat),
	.mem_gnt(g_kran || g_kran_z),
	.mem_ack(a_kran || a_kran_z),
	.mem_q(a_kran_z ? kran_z_q : ram_q),
	.busy(kran_busy)
);

//////////////////////////////  LOTSE  //////////////////////////////////////

wire [7:0] lot_dout;

lotse lotse
(
	.clk(clk),
	.reset(!cpu_rst_n),
	.reg_addr(io_a[7:0]),
	.reg_din(io_d),
	.reg_dout(lot_dout),
	.reg_we(we_lot),
	.irq(irq_lot),
	.ce_pix(ce_pix),
	.hc(strahl_h),
	.vc(strahl_v),
	.v_last(strahl_ende),
	.mem_req(lot_req),
	.mem_addr(lot_addr),
	.mem_gnt(g_lot),
	.mem_ack(a_lot),
	.mem_q(ram_q),
	.io_req(lot_io_req),
	.io_addr(lot_io_addr),
	.io_dat(lot_io_dat),
	.io_gnt(io_lot),
	.kran_busy(kran_busy),
	.laeuft()
);

//////////////////////////////  Zusatzspeicher  /////////////////////////////

// Drei Kunden: BOTE (laedt, die CPU steht dann), die CPU und KRAN. Ein
// Auftrag ist zur Zeit unterwegs; BOTE hat Vorrang, dann die CPU, KRAN
// bekommt die Luecken. Die CPU stellt ihren Auftrag
// in cyc 0 oder 1 (oder spaeter, wenn noch einer laeuft). Schreiben haelt
// sie nicht auf; Lesen wartet, bis ihre Daten da sind. Jeder Kunde bekommt
// nur die Antworten auf seine eigenen Lesezugriffe.
//
// Wortpuffer: Das SDRAM liefert beim Lesen immer ein ganzes 16-Bit-Wort.
// Das letzte gelesene Wort bleibt stehen; wer das andere Byte (oder dasselbe
// noch einmal) liest, bekommt es sofort - die CPU ohne Wartezyklus, KRAN
// im naechsten Takt. Schreibzugriffe auf das Wort aendern den Puffer mit.
//
// Steckt ein Modul, ist $40:0000-$7F:FFFF ROM: Schreibzugriffe der CPU und
// von KRAN gelten sofort als erledigt, ohne das SDRAM zu beruehren.
//
// Vorrang am SDRAM: BOTE, dann ORGEL (Samples aus dem Zusatzspeicher, Etappe
// 15 - sonst knackt es), dann ihr Echo (Etappe 16, liest und schreibt ganze
// Woerter), dann CPU, dann KRAN. Die ORGEL bekommt das ganze Wort und laesst
// den Wortpuffer der CPU in Ruhe; schreibt das Echo in dessen Wort, gilt er
// nicht mehr.
wire        zus_zugriff = is_zus && (vda || vpa) && !halt;
wire        cpu_schutz  = zus_zugriff && !cpu_we_n && modul_da && a[23:22] == 2'b01;
wire        kran_schutz = kran_req && !kran_chip && kran_we && modul_da && kran_addr[23:22] == 2'b01;
reg         z_req_t;
reg  [23:0] z_adr;
reg         z_we;
reg   [7:0] z_din;
wire        z_ack_t;
wire  [7:0] z_q;
wire [15:0] z_q16;
reg         wp_gueltig;                 // Wortpuffer
reg  [22:0] wp_adr;
reg  [15:0] wp_daten;
reg         z_ack24;
reg         z_laeuft;                   // ein Auftrag ist unterwegs ...
reg   [1:0] z_wer;                      // ... von 0: CPU, 1: KRAN/BOTE, 2: ORGEL, 3: Echo
reg         z_w16;                      // Wort schreiben (Echo)
reg  [15:0] z_din16;
reg         z_cpu_an, z_cpu_da;         // CPU: Auftrag gestellt / Lesedaten da
reg   [7:0] z_cpu_q;
wire        z_erledigt = z_laeuft && (z_ack24 == z_req_t);
wire        z_bereit   = !z_laeuft || z_erledigt;
// Treffer im Wortpuffer - nur, wenn der Kunde selbst keinen Lesezugriff
// mehr unterwegs hat (sonst kaeme die Antwort in falscher Reihenfolge)
wire        cpu_treffer  = zus_zugriff && cpu_we_n && wp_gueltig && a[23:1] == wp_adr && !z_cpu_an;
wire        kran_liest_z = z_laeuft && z_wer == 2'd1 && !z_we;
wire        kran_treffer = kran_req && !kran_chip && !kran_we && wp_gueltig &&
                           kran_addr[23:1] == wp_adr && !kran_liest_z;
wire  [7:0] wp_byte_cpu  = a[0] ? wp_daten[15:8] : wp_daten[7:0];
assign      g_bote_z   = bote_zreq && z_bereit;
assign      g_org_z    = org_req && org_z && z_bereit && !g_bote_z;
assign      a_org_z    = z_erledigt && z_wer == 2'd2;
assign      g_echo_z   = echo_req && z_bereit && !g_bote_z && !g_org_z;
assign      a_echo_z   = z_erledigt && z_wer == 2'd3;
wire        z_cpu_geht = zus_zugriff && !cpu_treffer && !cpu_schutz && !z_cpu_an && z_bereit && cyc != 2'd2 && !g_bote_z && !g_org_z && !g_echo_z;
wire        g_kran_zs  = kran_req && !kran_chip && !kran_treffer && !kran_schutz && z_bereit && !z_cpu_geht && !g_bote_z && !g_org_z && !g_echo_z;
reg         a_kran_wp;                  // Treffer: Daten im naechsten Takt
reg   [7:0] kran_wp_q;
assign      g_kran_z   = g_kran_zs || kran_treffer || kran_schutz;
assign      a_kran_z   = (z_erledigt && z_wer == 2'd1 && !z_we) || a_kran_wp;
assign      kran_z_q   = a_kran_wp ? kran_wp_q : z_q24;
// Kommt ein gelesenes Wort gerade an, gilt fuer Schreibzugriffe schon seine Adresse
wire        wp_neu     = z_erledigt && !z_we && z_wer[1] == 1'b0;
wire        wp_g_n     = wp_neu || wp_gueltig;
wire [22:0] wp_adr_n   = wp_neu ? z_adr[23:1] : wp_adr;
// Lesedaten der CPU gelten schon in dem Takt, in dem sie ankommen (z_q24)
wire        z_cpu_jetzt = z_erledigt && z_wer == 2'd0 && !z_we;
assign      z_warten   = zus_zugriff && (cpu_we_n ? !(cpu_treffer || z_cpu_da || z_cpu_jetzt) : !(z_cpu_an || cpu_schutz));

always @(posedge clk) begin
	z_ack24   <= z_ack_t;
	z_q24     <= z_q;
	z_q16_24  <= z_q16;
	a_kran_wp <= kran_treffer;
	kran_wp_q <= kran_addr[0] ? wp_daten[15:8] : wp_daten[7:0];
	if (z_erledigt) begin
		z_laeuft <= 1'b0;
		if (z_wer == 2'd0 && !z_we) begin
			z_cpu_da <= 1'b1;
			z_cpu_q  <= z_q24;
		end
		if (!z_we && z_wer[1] == 1'b0) begin    // gelesenes Wort merken (nicht ORGEL/Echo)
			wp_gueltig <= 1'b1;
			wp_adr     <= z_adr[23:1];
			wp_daten   <= z_q16_24;
		end
	end
	// Schreiben auf das Wort im Puffer: Puffer mit aendern
	if (g_bote_z && wp_g_n && bote_zaddr[23:1] == wp_adr_n) begin
		if (bote_zaddr[0]) wp_daten[15:8] <= bote_zdata; else wp_daten[7:0] <= bote_zdata;
	end
	else if (z_cpu_geht && !cpu_we_n && wp_g_n && a[23:1] == wp_adr_n) begin
		if (a[0]) wp_daten[15:8] <= cpu_dout; else wp_daten[7:0] <= cpu_dout;
	end
	else if (g_kran_zs && kran_we && wp_g_n && kran_addr[23:1] == wp_adr_n) begin
		if (kran_addr[0]) wp_daten[15:8] <= kran_wdat; else wp_daten[7:0] <= kran_wdat;
	end
	// (Adresse, Richtung und Daten bleiben stehen, bis der naechste Auftrag
	// kommt - das SDRAM uebernimmt ihn vielleicht erst nach dem Auffrischen)
	if (g_bote_z) begin
		z_adr    <= bote_zaddr;
		z_w16    <= 1'b0;
		z_we     <= 1'b1;
		z_din    <= bote_zdata;
		z_req_t  <= ~z_req_t;
		z_laeuft <= 1'b1;
		z_wer    <= 2'd1;
	end
	else if (g_org_z) begin
		z_adr    <= org_addr;
		z_we     <= 1'b0;
		z_w16    <= 1'b0;
		z_req_t  <= ~z_req_t;
		z_laeuft <= 1'b1;
		z_wer    <= 2'd2;
	end
	else if (g_echo_z) begin
		z_adr    <= echo_adr;
		z_we     <= echo_we;
		z_w16    <= echo_we;
		z_din16  <= echo_din;
		z_req_t  <= ~z_req_t;
		z_laeuft <= 1'b1;
		z_wer    <= 2'd3;
		if (echo_we && wp_g_n && echo_adr[23:1] == wp_adr_n)
			wp_gueltig <= 1'b0;
	end
	else if (z_cpu_geht) begin
		z_adr    <= a;
		z_we     <= !cpu_we_n;
		z_w16    <= 1'b0;
		z_din    <= cpu_dout;
		z_req_t  <= ~z_req_t;
		z_laeuft <= 1'b1;
		z_wer    <= 2'd0;
		z_cpu_an <= 1'b1;
	end
	else if (g_kran_zs) begin
		z_adr    <= kran_addr;
		z_we     <= kran_we;
		z_w16    <= 1'b0;
		z_din    <= kran_wdat;
		z_req_t  <= ~z_req_t;
		z_laeuft <= 1'b1;
		z_wer    <= 2'd1;
	end
	if (cpu_ce && cpu_rdy) begin
		z_cpu_an <= 1'b0;
		z_cpu_da <= 1'b0;
	end
	if (reset) begin
		z_req_t    <= 1'b0;
		z_laeuft   <= 1'b0;
		z_w16      <= 1'b0;
		wp_gueltig <= 1'b0;
		z_cpu_an <= 1'b0;
		z_cpu_da <= 1'b0;
	end
end

zusatz zusatz
(
	.clk(clk48),
	.reset(reset),
	.req_t(z_req_t),
	.adr(z_adr),
	.we(z_we),
	.din(z_din),
	.w16(z_w16),
	.din16(z_din16),
	.ack_t(z_ack_t),
	.q(z_q),
	.q16(z_q16),
	.bereit(),
	.sd_a(sd_a),
	.sd_ba(sd_ba),
	.sd_ncs(sd_ncs),
	.sd_nras(sd_nras),
	.sd_ncas(sd_ncas),
	.sd_nwe(sd_nwe),
	.sd_dqml(sd_dqml),
	.sd_dqmh(sd_dqmh),
	.sd_dq_o(sd_dq_o),
	.sd_dq_oe(sd_dq_oe),
	.sd_dq_i(sd_dq_i)
);

//////////////////////////////  TRUHE  //////////////////////////////////////

wire [7:0] truhe_dout;

truhe truhe
(
	.clk(clk),
	.reset(!cpu_rst_n),
	.adr(a[8:0]),
	.sel_reg(is_truhe),
	.sel_puf(is_tpuf),
	.we(wr && (is_truhe || is_tpuf)),
	.din(cpu_dout),
	.dout(truhe_dout),
	.img_mounted(img_mounted),
	.img_readonly(img_readonly),
	.img_size(img_size),
	.sd_lba(sd_lba),
	.sd_blk_cnt(sd_blk_cnt),
	.sd_rd(sd_rd),
	.sd_wr(sd_wr),
	.sd_ack(sd_ack),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(sd_buff_din),
	.sd_buff_wr(sd_buff_wr)
);

//////////////////////////////  DRAHT  //////////////////////////////////////

draht draht
(
	.clk(clk),
	.reset(!cpu_rst_n),
	.zugriff(is_netz && (vda || vpa) && !halt),
	.schreiben(!cpu_we_n),
	.adr(a[15:0]),
	.din(cpu_dout),
	.weiter(cpu_ce && cpu_rdy),
	.warten(n_warten),
	.dout(netz_dout),
	.b_addr(b_ddr_addr),
	.b_rd(b_ddr_rd),
	.b_busy(b_ddr_busy),
	.b_dout(b_ddr_dout),
	.b_ready(b_ddr_ready),
	.ddr_addr(ddr_addr),
	.ddr_rd(ddr_rd),
	.ddr_we(ddr_we),
	.ddr_din(ddr_din),
	.ddr_be(ddr_be),
	.ddr_busy(ddr_busy),
	.ddr_dout(ddr_dout),
	.ddr_dout_ready(ddr_dout_ready)
);

//////////////////////////////  Datenbus zur CPU  ///////////////////////////

always @* begin
	if (is_rom)      cpu_din = rom_q;
	else if (is_ram) cpu_din = ram_q;
	else if (is_pin) cpu_din = pin_dout;
	else if (is_pfo) cpu_din = pfo_dout;
	else if (is_bot) cpu_din = bot_dout;
	else if (is_kob) cpu_din = kob_dout;
	else if (is_org || is_org2) cpu_din = org_dout;
	else if (is_kran) cpu_din = kran_dout;
	else if (is_lot) cpu_din = lot_dout;
	else if (is_zus) cpu_din = cpu_treffer ? wp_byte_cpu : z_cpu_da ? z_cpu_q : z_q24;
	else if (is_netz) cpu_din = netz_dout;
	else if (is_brom) cpu_din = (a[15:14] == 2'b00) ? brom_q : (a[15:14] == 2'b01) ? dos_q : (a[15:14] == 2'b10) ? song_q : 8'hFF;
	else if (is_truhe || is_tpuf) cpu_din = truhe_dout;
	else if (is_sys && a[7:0] == 8'h00) cpu_din = {6'b0, s_status, sys_spiegel};
	else             cpu_din = 8'hFF;
end

endmodule
