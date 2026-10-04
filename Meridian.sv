//============================================================================
//
//  MERIDIAN 816 - ein Heimcomputer zwischen C64 und Amiga
//  MiSTer-Huelle (Aufbau nach Template_MiSTer)
//
//  Copyright (c) 2026 retro-modern.net
//  GPL-3.0-or-later (CPU-Kern P65C816 von srg320 steht unter GPL-3)
//
//============================================================================

module emu
(
	`include "sys/emu_ports.vh"
);

///////// Nicht benutzte Anschluesse /////////
assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
// DDR3: nur lesend, fuer das Netz-Postfach von BOTE
assign DDRAM_CLK      = clk_sys;
assign DDRAM_BURSTCNT = 8'd1;

assign VGA_SL = 0;
assign VGA_F1 = 0;
assign VGA_SCALER  = 0;
assign VGA_DISABLE = 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;

// ORGEL liefert Stereo mit Vorzeichen; Mischung waehlbar im Menue
wire [15:0] audio_l, audio_r;
assign AUDIO_S   = 1;
assign AUDIO_L   = audio_l;
assign AUDIO_R   = audio_r;
assign AUDIO_MIX = status[5:4];

assign LED_DISK  = 0;
assign LED_POWER = 0;
assign LED_USER  = 0;
assign BUTTONS   = 0;

//////////////////////////////////////////////////////////////////

wire [1:0] ar = status[122:121];

assign VIDEO_ARX = (!ar) ? 12'd4 : (ar - 1'd1);
assign VIDEO_ARY = (!ar) ? 12'd3 : 12'd0;

`include "build_id.v"
localparam CONF_STR = {
	"MERIDIAN;;",
	"-;",
	"O[122:121],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"O[2],Video,NTSC 60 Hz,PAL 50 Hz;",
	"O[3],Keyboard,German PC,German Mac;",
	"O[5:4],Stereo,Full,75 %,50 %,Mono;",
	"-;",
	"F1,MER,Load program;",
	"S1,DSKIMGHDF,Drive 1;",
	"S2,DSKIMGHDF,Drive 2;",
	"-;",
	"FS2,MOD,Insert cartridge;",
	"O[6],Cartridge start,Auto,Off;",
	"T[7],Eject cartridge;",
	"-;",
	"J1,Fire A,Fire B,Fire C,Fire D,Start,Select;",
	"-;",
	"T[0],Reset;",
	"R[0],Reset & close menu;",
	"v,0;",
	"V,v",`BUILD_DATE
};

wire   [1:0] buttons;
wire [127:0] status;
wire  [10:0] ps2_key;
wire  [24:0] ps2_mouse;
wire  [15:0] ps2_mouse_ext;
wire  [64:0] rtc;
wire  [31:0] joystick_0, joystick_1;
wire         ioctl_download, ioctl_wr;
wire  [15:0] ioctl_index;
wire  [26:0] ioctl_addr;
wire   [7:0] ioctl_dout;
wire         ioctl_wait;

// Laufwerke (TRUHE): Index 0 Speicherstand eines Moduls (legt der MiSTer
// beim Einstecken als /saves/MERIDIAN/<modul>.sav an, "FS2"), 1 und 2 Images
wire  [2:0] img_mounted;
wire        img_readonly;
wire [63:0] img_size;
wire [31:0] sd_lba;
wire  [5:0] sd_blk_cnt;
wire  [2:0] sd_rd, sd_wr, sd_ack;
wire [13:0] sd_buff_addr;
wire  [7:0] sd_buff_dout, sd_buff_din;
wire        sd_buff_wr;
wire [31:0] sd_lba_n [3];
wire  [5:0] sd_blk_cnt_n [3];
wire  [7:0] sd_buff_din_n [3];
genvar lw;
generate
	for (lw = 0; lw < 3; lw = lw + 1) begin : laufwerke
		assign sd_lba_n[lw]      = sd_lba;
		assign sd_blk_cnt_n[lw]  = sd_blk_cnt;          // Bloecke je Auftrag - 1 (TRUHE)
		assign sd_buff_din_n[lw] = sd_buff_din;
	end
endgenerate

hps_io #(.CONF_STR(CONF_STR), .VDNUM(3)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),
	.gamma_bus(),

	.buttons(buttons),
	.status(status),
	.status_menumask(16'd0),
	.ps2_key(ps2_key),
	.ps2_mouse(ps2_mouse),
	.ps2_mouse_ext(ps2_mouse_ext),
	.RTC(rtc),
	.joystick_0(joystick_0),
	.joystick_1(joystick_1),

	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_wait(ioctl_wait),

	.img_mounted(img_mounted),
	.img_readonly(img_readonly),
	.img_size(img_size),
	.sd_lba(sd_lba_n),
	.sd_blk_cnt(sd_blk_cnt_n),
	.sd_rd(sd_rd),
	.sd_wr(sd_wr),
	.sd_ack(sd_ack),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(sd_buff_din_n),
	.sd_buff_wr(sd_buff_wr)
);

///////////////////////   TAKT   ///////////////////////////////

wire clk_sys;   // 24 MHz
wire clk_48;    // 48 MHz, phasengleich: SDRAM
pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_sys),
	.outclk_1(clk_48)
);

// SDRAM-Takt invertiert ausgeben: Befehle wechseln an der steigenden Flanke,
// das SDRAM uebernimmt sie in der Mitte des Takts
altddio_out
#(
	.extend_oe_disable("OFF"),
	.intended_device_family("Cyclone V"),
	.invert_output("OFF"),
	.lpm_hint("UNUSED"),
	.lpm_type("altddio_out"),
	.oe_reg("UNREGISTERED"),
	.power_up_high("OFF"),
	.width(1)
)
sdramclk_ddr
(
	.datain_h(1'b0),
	.datain_l(1'b1),
	.outclock(clk_48),
	.dataout(SDRAM_CLK),
	.aclr(1'b0),
	.aset(1'b0),
	.oe(1'b1),
	.outclocken(1'b1),
	.sclr(1'b0),
	.sset(1'b0)
);

wire [15:0] sd_dq_o;
wire        sd_dq_oe;
assign SDRAM_DQ  = sd_dq_oe ? sd_dq_o : 16'hZZZZ;
assign SDRAM_CKE = 1'b1;

wire reset = RESET | status[0] | buttons[1];

//////////////////////////////////////////////////////////////////

wire       ce_pix, hblank, vblank, hsync, vsync;
wire [7:0] r, g, b;

meridian_core core
(
	.clk(clk_sys),
	.clk48(clk_48),
	.reset(reset),
	.pal(status[2]),

	.ps2_key(ps2_key),
	.ps2_mouse(ps2_mouse),
	.ps2_mouse_ext(ps2_mouse_ext[7:0]),
	.rtc(rtc),
	.joy0(joystick_0[15:0]),
	.joy1(joystick_1[15:0]),
	.layout_mac(status[3]),

	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index[7:0]),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_wait(ioctl_wait),
	.modul_aus(status[6]),
	.modul_raus(status[7]),
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
	.sd_buff_wr(sd_buff_wr),

	.ddr_addr(DDRAM_ADDR),
	.ddr_rd(DDRAM_RD),
	.ddr_we(DDRAM_WE),
	.ddr_din(DDRAM_DIN),
	.ddr_be(DDRAM_BE),
	.ddr_busy(DDRAM_BUSY),
	.ddr_dout(DDRAM_DOUT),
	.ddr_dout_ready(DDRAM_DOUT_READY),

	.ce_pix(ce_pix),
	.hblank(hblank),
	.vblank(vblank),
	.hsync(hsync),
	.vsync(vsync),
	.r(r),
	.g(g),
	.b(b),

	.audio_l(audio_l),
	.audio_r(audio_r),
	.sd_a(SDRAM_A),
	.sd_ba(SDRAM_BA),
	.sd_ncs(SDRAM_nCS),
	.sd_nras(SDRAM_nRAS),
	.sd_ncas(SDRAM_nCAS),
	.sd_nwe(SDRAM_nWE),
	.sd_dqml(SDRAM_DQML),
	.sd_dqmh(SDRAM_DQMH),
	.sd_dq_o(sd_dq_o),
	.sd_dq_oe(sd_dq_oe),
	.sd_dq_i(SDRAM_DQ),
	.dbg_addr(),
	.dbg_ce()
);

assign CLK_VIDEO = clk_sys;
assign CE_PIXEL  = ce_pix;

assign VGA_DE = ~(hblank | vblank);
assign VGA_HS = hsync;
assign VGA_VS = vsync;
assign VGA_R  = r;
assign VGA_G  = g;
assign VGA_B  = b;

endmodule
