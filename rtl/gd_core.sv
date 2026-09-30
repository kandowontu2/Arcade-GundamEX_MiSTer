// Gundam EX Revue core integration: direct MRA loader, SDRAM-backed graphics,
// DDR3-backed program/sample/RAM, TMP68301, X1-010 and native raster.
// SPDX-License-Identifier: GPL-3.0-or-later

module gd_core
(
	input  logic        clk,
	input  logic        cold_reset,
	input  logic        reset,
	input  logic        memory_ready,
	input  logic        service,
	input  logic        cheat_infinite_credits,
	input  logic        cheat_infinite_time,
	input  logic        cheat_p1_energy,
	input  logic        cheat_p2_energy,
	input  logic [15:0] dip_switches,
	input  logic [31:0] joystick_p1,
	input  logic [31:0] joystick_p2,
	input  logic        language_japanese,
	input  logic  [1:0] cpu_timing,
	input  logic        rotate_180,

	input  logic        rom_downloading,
	input  logic        rom_wr,
	input  logic [26:0] rom_addr,
	input  logic  [7:0] rom_data,
	output logic        rom_wait,

	output logic        ddr_clk,
	input  logic        ddr_busy,
	output logic  [7:0] ddr_burstcount,
	output logic [28:0] ddr_addr,
	input  logic [63:0] ddr_dout,
	input  logic        ddr_dout_ready,
	output logic        ddr_rd,
	output logic [63:0] ddr_din,
	output logic  [7:0] ddr_be,
	output logic        ddr_we,

	output logic [24:0] sdram_mem_addr,
	output logic [15:0] sdram_mem_din,
	output logic  [1:0] sdram_mem_be,
	output logic        sdram_mem_rnw,
	output logic        sdram_mem_req,
	output logic        sdram_mem_burst,
	output logic [63:0] sdram_mem_burst_data,
	input  logic [15:0] sdram_mem_dout,
	input  logic        sdram_mem_ack,
	output logic [24:0] sdram_dma_addr,
	output logic        sdram_dma_req,
	input  logic [63:0] sdram_dma_data,
	input  logic        sdram_dma_ack,

	output logic        ce_pix,
	output logic        hblank,
	output logic        hsync,
	output logic        vblank,
	output logic        vsync,
	output logic  [7:0] red,
	output logic  [7:0] green,
	output logic  [7:0] blue,
	output logic signed [15:0] audio_left,
	output logic signed [15:0] audio_right,
	output logic        rom_ready,
	output logic [23:0] debug_cpu_address,
	output logic [31:0] debug_bus_cycles,
	output logic [15:0] debug_unmapped_cycles
);

logic [8:0] h_count;
logic [8:0] v_count;
logic frame_tick;
gd_video_timing timing
(
	.clk, .reset(cold_reset), .ce_pix, .h_count, .v_count,
	.hblank, .vblank, .hsync, .vsync, .frame_tick
);

logic ddr_load_wr;
logic [25:0] ddr_load_addr;
logic [7:0] ddr_load_data;
logic ddr_load_wait;
logic ddr_load_idle;
logic layout_error;
logic [26:0] accepted_bytes;
logic [3:0] regions_seen;
logic [24:0] loader_gfx_addr;
logic [15:0] loader_gfx_din;
logic [1:0] loader_gfx_be;
logic loader_gfx_rnw;
logic loader_gfx_req;
logic loader_gfx_ack;
logic loader_gfx_burst;
logic [63:0] loader_gfx_burst_data;
	logic eeprom_load_wr;
	logic [6:0] eeprom_load_addr;
	logic [7:0] eeprom_load_data;
	logic loader_busy;
	logic loader_strobe;
	logic [26:0] loader_addr;
	logic [7:0] loader_data;
	logic loader_wait;
	logic adaptor_ddr_acquire;
	logic [28:0] adaptor_ddr_addr;
	logic adaptor_ddr_read;
	logic adaptor_ddr_busy;
	logic adaptor_ddr_rdata_ready;

	logic core_ddr_busy;
	logic [7:0] core_ddr_burstcount;
	logic [28:0] core_ddr_addr;
	logic core_ddr_dout_ready;
	logic core_ddr_rd;
	logic [63:0] core_ddr_din;
	logic [7:0] core_ddr_be;
	logic core_ddr_we;

	gd_ddr_rom_loader_adaptor loader_adaptor
	(
		.clk, .reset(cold_reset), .ioctl_download(rom_downloading),
		.ioctl_addr(rom_addr), .ioctl_wr(rom_wr), .ioctl_data(rom_data),
		.ioctl_wait(rom_wait), .busy(loader_busy), .data_wait(loader_wait),
		.data_strobe(loader_strobe), .data_addr(loader_addr),
		.data(loader_data), .ddr_acquire(adaptor_ddr_acquire),
		.ddr_addr(adaptor_ddr_addr), .ddr_read(adaptor_ddr_read),
		.ddr_rdata(ddr_dout), .ddr_rdata_ready(adaptor_ddr_rdata_ready),
		.ddr_busy(adaptor_ddr_busy)
	);

	gd_rom_loader loader
	(
		.clk, .reset(cold_reset), .memory_ready, .downloading(loader_busy),
		.ioctl_wr(loader_strobe), .ioctl_addr(loader_addr),
		.ioctl_data(loader_data), .ioctl_wait(loader_wait),
		.ddr_load_wr, .ddr_load_addr, .ddr_load_data,
	.ddr_load_wait, .ddr_load_idle, .gfx_addr(loader_gfx_addr),
	.gfx_din(loader_gfx_din), .gfx_be(loader_gfx_be),
	.gfx_rnw(loader_gfx_rnw), .gfx_req(loader_gfx_req),
	.gfx_ack(loader_gfx_ack), .gfx_burst(loader_gfx_burst),
	.gfx_burst_data(loader_gfx_burst_data),
	.eeprom_load_wr, .eeprom_load_addr, .eeprom_load_data, .rom_ready,
	.layout_error, .accepted_bytes, .regions_seen
);

logic [21:0] cpu_rom_addr;
logic cpu_rom_req;
logic [15:0] cpu_rom_dout;
logic cpu_rom_ack;
logic [20:0] sound_rom_addr;
logic sound_rom_req;
logic [7:0] sound_rom_dout;
logic sound_rom_ack;
logic [16:0] cpu_ram_addr;
logic cpu_ram_req;
logic cpu_ram_write;
logic [15:0] cpu_ram_data;
logic [1:0] cpu_ram_be;
logic [15:0] cpu_ram_dout;
logic cpu_ram_ack;
gd_ddr_memory rom_memory
(
	.clk, .reset(cold_reset), .load_wr(ddr_load_wr),
	.load_addr(ddr_load_addr), .load_data(ddr_load_data),
	.load_wait(ddr_load_wait), .load_idle(ddr_load_idle),
	.cpu_addr(cpu_rom_addr), .cpu_req(cpu_rom_req),
	.cpu_dout(cpu_rom_dout), .cpu_ack(cpu_rom_ack),
	.sound_addr(sound_rom_addr), .sound_req(sound_rom_req),
	.sound_dout(sound_rom_dout), .sound_ack(sound_rom_ack),
	.ram_addr(cpu_ram_addr), .ram_req(cpu_ram_req), .ram_write(cpu_ram_write),
	.ram_data(cpu_ram_data), .ram_be(cpu_ram_be), .ram_dout(cpu_ram_dout),
	.ram_ack(cpu_ram_ack),
	.gfx_addr(25'd0), .gfx_req(1'b0),
	.gfx_dout(), .gfx_ack(),
		.ddr_clk, .ddr_busy(core_ddr_busy),
		.ddr_burstcount(core_ddr_burstcount), .ddr_addr(core_ddr_addr),
		.ddr_dout, .ddr_dout_ready(core_ddr_dout_ready),
		.ddr_rd(core_ddr_rd), .ddr_din(core_ddr_din),
		.ddr_be(core_ddr_be), .ddr_we(core_ddr_we)
	);

	// The replay adaptor owns DDR only while fetching a staged 64-bit word.
	// The game memory client has priority for the packed write triggered by
	// each eighth replayed byte, so an accepted write can never be masked by
	// the following read request.
	wire adaptor_ddr_selected = adaptor_ddr_acquire
		&& !core_ddr_rd && !core_ddr_we;
	assign ddr_burstcount = adaptor_ddr_selected ? 8'd1
		: core_ddr_burstcount;
	assign ddr_addr = adaptor_ddr_selected ? adaptor_ddr_addr : core_ddr_addr;
	assign ddr_rd = adaptor_ddr_selected ? adaptor_ddr_read : core_ddr_rd;
	assign ddr_din = core_ddr_din;
	assign ddr_be = adaptor_ddr_selected ? 8'hff : core_ddr_be;
	assign ddr_we = adaptor_ddr_selected ? 1'b0 : core_ddr_we;
	assign core_ddr_busy = ddr_busy || (adaptor_ddr_acquire
		&& !core_ddr_rd && !core_ddr_we);
	assign adaptor_ddr_busy = ddr_busy || core_ddr_rd || core_ddr_we;
	assign core_ddr_dout_ready = ddr_dout_ready && !adaptor_ddr_selected;
	assign adaptor_ddr_rdata_ready = ddr_dout_ready
		&& adaptor_ddr_selected;

	wire runtime_reset = reset || !memory_ready || !rom_ready || loader_busy;
logic raster_irq;
logic [15:0] video_control;
logic [26:0] video_x_offset;
logic [26:0] video_x_zoom;
logic [26:0] video_y_offset;
logic [26:0] video_y_zoom;
logic        sprite_buffer_busy;
logic  [1:0] sprite_buffer_busy_history;
wire         renderer_pause = sprite_buffer_busy
	|| (sprite_buffer_busy_history != 2'b00);

// The buffer engine temporarily owns the synchronous sprite-RAM video port.
// Preserve the renderer's completed-line queue and hold only its row builder,
// then allow two clocks after ownership returns for address/data to settle.
always_ff @(posedge clk) begin
	if (runtime_reset)
		sprite_buffer_busy_history <= 2'b00;
	else
		sprite_buffer_busy_history <= {
			sprite_buffer_busy_history[0], sprite_buffer_busy};
end
logic [15:0] raster_enable;
logic [15:0] raster_position;
logic        raster_rearm;
logic        rowscroll_write;
logic [16:0] rowscroll_write_address;
logic [15:0] rowscroll_write_data;
logic  [1:0] rowscroll_write_byte_enable;
gd_raster_irq raster_timer
(
	.clk, .reset(runtime_reset), .ce_pix, .h_count, .v_count,
	.enable(raster_enable[0]), .position(raster_position[8:0]),
	.rearm(raster_rearm), .irq(raster_irq)
);

logic [16:0] sprite_video_address;
logic [63:0] sprite_video_q;
logic [14:0] palette_video_address;
logic [15:0] palette_video_q;
logic [4:0] video_reg_address;
logic [15:0] video_reg_q;
logic x1_write;
logic [12:0] x1_address;
logic [15:0] x1_data;
logic [1:0] x1_byte_enable;
logic [15:0] x1_q;
logic [63:0] sample_banks;
logic [31:0] debug_rom_cycles;
logic cpu_running;
logic eeprom_cs;
logic eeprom_clk;
logic eeprom_di;
logic eeprom_do;

assign video_reg_address = 5'd0;

gd_93c46 eeprom
(
	.clk, .reset(cold_reset || rom_downloading),
	.load_wr(eeprom_load_wr), .load_addr(eeprom_load_addr),
	.load_data(eeprom_load_data), .chip_select(eeprom_cs),
	.serial_clock(eeprom_clk), .data_in(eeprom_di), .data_out(eeprom_do)
);

gd_cpu_subsystem cpu
(
	.clk, .reset(runtime_reset), .vblank, .raster_irq, .dip_switches,
	.joystick_p1, .joystick_p2, .service, .language_japanese,
	.cpu_timing, .cheat_infinite_credits, .cheat_infinite_time,
	.cheat_p1_energy, .cheat_p2_energy,
	.eeprom_do, .eeprom_cs, .eeprom_clk, .eeprom_di,
	.rom_addr(cpu_rom_addr), .rom_req(cpu_rom_req),
	.rom_dout(cpu_rom_dout), .rom_ack(cpu_rom_ack),
	.ram_addr(cpu_ram_addr), .ram_req(cpu_ram_req), .ram_write(cpu_ram_write),
	.ram_data(cpu_ram_data), .ram_be(cpu_ram_be), .ram_dout(cpu_ram_dout),
	.ram_ack(cpu_ram_ack),
	.sprite_video_address, .sprite_video_q,
	.palette_video_address, .palette_video_q,
	.video_reg_address, .video_reg_q, .video_control,
	.video_x_offset, .video_x_zoom, .video_y_offset, .video_y_zoom,
	.sprite_buffer_busy,
	.raster_enable, .raster_position, .raster_rearm,
	.rowscroll_write, .rowscroll_write_address, .rowscroll_write_data,
	.rowscroll_write_byte_enable,
	.x1_write, .x1_address, .x1_data, .x1_byte_enable, .x1_q,
	.sample_banks, .debug_address(debug_cpu_address),
	.debug_bus_cycles, .debug_rom_cycles,
	.debug_unmapped_cycles, .cpu_running
);

gd_x1_010 sound
(
	.clk, .reset(runtime_reset), .cpu_write(x1_write),
	.cpu_address(x1_address), .cpu_data(x1_data),
	.cpu_byte_enable(x1_byte_enable), .cpu_q(x1_q), .sample_banks,
	.sample_addr(sound_rom_addr), .sample_req(sound_rom_req),
	.sample_dout(sound_rom_dout), .sample_ack(sound_rom_ack),
	.audio_left, .audio_right
);

logic [24:0] renderer_gfx_addr;
logic renderer_gfx_req;
logic [63:0] renderer_gfx_dout;
logic renderer_gfx_ack;
logic [7:0] renderer_red;
logic [7:0] renderer_green;
logic [7:0] renderer_blue;
logic renderer_busy;
logic renderer_line_done;
logic [15:0] renderer_missed_lines;
logic [8:0] rowscroll_lookup_line;
logic rowscroll_override_valid;
logic [14:0] rowscroll_override_record;
logic [15:0] rowscroll_override_data;
logic [15:0] unused_loader_dout;

gd_rowscroll_history #(.VISIBLE_LINES(224)) rowscroll_history
(
	.clk, .reset(runtime_reset), .ce_pix, .h_count, .v_count,
	.capture_enable(raster_enable[0]),
	.raster_position(raster_position[8:0]),
	.write(rowscroll_write), .write_address(rowscroll_write_address),
	.write_data(rowscroll_write_data),
	.write_byte_enable(rowscroll_write_byte_enable),
	.lookup_line(rowscroll_lookup_line),
	.lookup_valid(rowscroll_override_valid),
	.lookup_record(rowscroll_override_record),
	.lookup_data(rowscroll_override_data)
);

gd_gfx_arbiter gfx_arbiter
(
	.clk, .reset(cold_reset), .cache_flush(rom_downloading),
	.loader_addr(loader_gfx_addr),
	.loader_din(loader_gfx_din), .loader_be(loader_gfx_be),
	.loader_rnw(loader_gfx_rnw), .loader_req(loader_gfx_req),
	.loader_burst(loader_gfx_burst),
	.loader_burst_data(loader_gfx_burst_data),
	.loader_dout(unused_loader_dout), .loader_ack(loader_gfx_ack),
	.renderer_addr(renderer_gfx_addr), .renderer_req(renderer_gfx_req),
	.renderer_dout(renderer_gfx_dout), .renderer_ack(renderer_gfx_ack),
	.mem_addr(sdram_mem_addr), .mem_din(sdram_mem_din),
	.mem_be(sdram_mem_be), .mem_rnw(sdram_mem_rnw),
	.mem_req(sdram_mem_req), .mem_burst(sdram_mem_burst),
	.mem_burst_data(sdram_mem_burst_data), .mem_dout(sdram_mem_dout),
	.mem_ack(sdram_mem_ack),
	.dma_addr(sdram_dma_addr), .dma_req(sdram_dma_req),
	.dma_data(sdram_dma_data), .dma_ack(sdram_dma_ack)
);

gd_dx101_video #(
	.AHEAD_RENDER(1'b1), .H_TOTAL(512), .V_TOTAL(256),
	.H_VISIBLE(384), .V_VISIBLE(224)
) video
(
	.clk, .reset(runtime_reset), .render_pause(renderer_pause),
	.ce_pix, .h_count, .v_count,
	.hblank, .vblank, .raster_active(raster_enable[0]), .video_control,
	.rotate_180,
	.rowscroll_override_valid, .rowscroll_override_record,
	.rowscroll_override_data,
	.video_x_offset, .video_x_zoom, .video_y_offset, .video_y_zoom,
	.sprite_address(sprite_video_address),
	.sprite_q(sprite_video_q), .palette_address(palette_video_address),
	.palette_q(palette_video_q), .gfx_addr(renderer_gfx_addr),
	.gfx_req(renderer_gfx_req), .gfx_dout(renderer_gfx_dout),
	.gfx_ack(renderer_gfx_ack), .red(renderer_red), .green(renderer_green),
	.blue(renderer_blue), .busy(renderer_busy),
	.line_done(renderer_line_done),
	.missed_lines(renderer_missed_lines),
	.rowscroll_lookup_line
);

always_comb begin
	// Do not draw a core-specific loading/test image. MiSTer's standard ROM
	// transfer overlay remains visible over a neutral background until the
	// complete, validated image has arrived and the game renderer starts.
	red = rom_ready ? renderer_red : 8'd0;
	green = rom_ready ? renderer_green : 8'd0;
	blue = rom_ready ? renderer_blue : 8'd0;
end

endmodule
