// Mobile Suit Gundam EX Revue TMP68301 main CPU subsystem.
// Implements the board address map around the fx68k 68000 core.
// SPDX-License-Identifier: GPL-3.0-or-later

module gd_cpu_subsystem
(
	input  logic        clk,
	input  logic        reset,
	input  logic        vblank,
	input  logic        raster_irq,
	input  logic [15:0] dip_switches,
	input  logic [31:0] joystick_p1,
	input  logic [31:0] joystick_p2,
	input  logic        service,
	input  logic        language_japanese,
	input  logic  [1:0] cpu_timing,
	input  logic        cheat_infinite_credits,
	input  logic        cheat_infinite_time,
	input  logic        cheat_p1_energy,
	input  logic        cheat_p2_energy,
	input  logic        eeprom_do,
	output logic        eeprom_cs,
	output logic        eeprom_clk,
	output logic        eeprom_di,

	output logic [21:0] rom_addr,
	output logic        rom_req,
	input  logic [15:0] rom_dout,
	input  logic        rom_ack,
	output logic [16:0] ram_addr,
	output logic        ram_req,
	output logic        ram_write,
	output logic [15:0] ram_data,
	output logic  [1:0] ram_be,
	input  logic [15:0] ram_dout,
	input  logic        ram_ack,

	input  logic [16:0] sprite_video_address,
	output logic [63:0] sprite_video_q,
	input  logic [14:0] palette_video_address,
	output logic [15:0] palette_video_q,
	input  logic  [4:0] video_reg_address,
	output logic [15:0] video_reg_q,
	output logic [15:0] video_control,
	output logic [26:0] video_x_offset,
	output logic [26:0] video_x_zoom,
	output logic [26:0] video_y_offset,
	output logic [26:0] video_y_zoom,
	output logic        sprite_buffer_busy,
	output logic [15:0] raster_enable,
	output logic [15:0] raster_position,
	output logic        raster_rearm,
	output logic        rowscroll_write,
	output logic [16:0] rowscroll_write_address,
	output logic [15:0] rowscroll_write_data,
	output logic  [1:0] rowscroll_write_byte_enable,

	output logic        x1_write,
	output logic [12:0] x1_address,
	output logic [15:0] x1_data,
	output logic  [1:0] x1_byte_enable,
	input  logic [15:0] x1_q,

	output logic [63:0] sample_banks,
	output logic [23:0] debug_address,
	output logic [31:0] debug_bus_cycles,
	output logic [31:0] debug_rom_cycles,
	output logic [15:0] debug_unmapped_cycles,
	output logic        cpu_running
);

// fx68k advances on alternating Phi1/Phi2 enables. The P0-113A board derives
// 32.53047 MHz phase events, and therefore a 16.265235 MHz CPU clock, from its
// dedicated crystal. Gundam EX Revue is CPU-bound during battles and is also
// marked imperfect-timing in MAME, so the OSD offers compensated CPU rates.
// Audio, video, and the TMP68301 timer below remain at their board rates.
localparam logic [31:0] PCB_CPU_EVENT_INCREMENT = 32'd2235476876;
localparam logic [31:0] MOD_CPU_EVENT_INCREMENT = 32'd2794346095;
localparam logic [31:0] COMP_CPU_EVENT_INCREMENT = 32'd3353215314;
localparam logic [31:0] MAX_CPU_EVENT_INCREMENT = 32'd4123168604;
localparam logic [31:0] TMP_TIMER_INCREMENT = 32'd1117738438;
logic [31:0] cpu_event_increment;
logic [31:0] cpu_clock_accumulator;
logic [32:0] cpu_clock_sum;
logic        cpu_half_phase;
logic        cpu_phi1;
logic        cpu_phi2;
logic [31:0] tmp_clock_accumulator;
logic [32:0] tmp_clock_sum;
logic        tmp_cpu_ce;

always_comb begin
	case (cpu_timing)
		2'd0: cpu_event_increment = COMP_CPU_EVENT_INCREMENT;
		2'd1: cpu_event_increment = PCB_CPU_EVENT_INCREMENT;
		2'd2: cpu_event_increment = MOD_CPU_EVENT_INCREMENT;
		default: cpu_event_increment = MAX_CPU_EVENT_INCREMENT;
	endcase
	cpu_clock_sum = {1'b0, cpu_clock_accumulator}
		+ {1'b0, cpu_event_increment};
	tmp_clock_sum = {1'b0, tmp_clock_accumulator}
		+ {1'b0, TMP_TIMER_INCREMENT};
end

always_ff @(posedge clk) begin
	cpu_phi1 <= 1'b0;
	cpu_phi2 <= 1'b0;
	tmp_cpu_ce <= 1'b0;
	if (reset) begin
		cpu_clock_accumulator <= 32'd0;
		cpu_half_phase <= 1'b0;
		tmp_clock_accumulator <= 32'd0;
	end
	else begin
		cpu_clock_accumulator <= cpu_clock_sum[31:0];
		tmp_clock_accumulator <= tmp_clock_sum[31:0];
		tmp_cpu_ce <= tmp_clock_sum[32];
		// DX-101 list buffering is a bus-master transaction. Keep the 68000
		// stopped until the referenced records have been packed; otherwise a
		// long gameplay list can be rewritten by software while its tail is
		// still being copied, producing persistent column/checkerboard damage.
		if (cpu_clock_sum[32] && !sprite_buffer_busy) begin
			if (cpu_half_phase) cpu_phi2 <= 1'b1;
			else cpu_phi1 <= 1'b1;
			cpu_half_phase <= ~cpu_half_phase;
		end
	end
end

wire        cpu_rw;
wire        cpu_as_n;
wire        cpu_lds_n;
wire        cpu_uds_n;
wire  [2:0] cpu_fc;
wire [15:0] cpu_data_out;
logic [15:0] cpu_data_in;
wire [23:1] cpu_word_addr;
logic        cpu_dtack_n;
wire [23:0] cpu_even_address = {cpu_word_addr, 1'b0};
wire [23:0] cpu_bus_address = {cpu_word_addr,
	(!cpu_lds_n && cpu_uds_n)};
wire [1:0] cpu_byte_enable = {~cpu_uds_n, ~cpu_lds_n};
wire cpu_data_strobe = !cpu_uds_n || !cpu_lds_n;
wire cpu_iack_cycle = !cpu_as_n && (&cpu_fc);

logic [2:0] tmp_irq_level;
logic [7:0] tmp_irq_vector;
wire [2:0] cpu_ipl_n = ~tmp_irq_level;
logic tmp_iack;

fx68k main_cpu
(
	.clk(clk), .HALTn(1'b1), .extReset(reset), .pwrUp(reset),
	.enPhi1(cpu_phi1), .enPhi2(cpu_phi2),
	.eRWn(cpu_rw), .ASn(cpu_as_n), .LDSn(cpu_lds_n), .UDSn(cpu_uds_n),
	.E(), .VMAn(), .FC0(cpu_fc[0]), .FC1(cpu_fc[1]), .FC2(cpu_fc[2]),
	.BGn(), .oRESETn(), .oHALTEDn(), .DTACKn(cpu_dtack_n),
	.VPAn(1'b1), .BERRn(1'b1), .BRn(1'b1), .BGACKn(1'b1),
	.IPL0n(cpu_ipl_n[0]), .IPL1n(cpu_ipl_n[1]),
	.IPL2n(cpu_ipl_n[2]), .iEdb(cpu_data_in),
	.oEdb(cpu_data_out), .eab(cpu_word_addr)
);

logic cpu_data_strobe_seen;
always_ff @(posedge clk) begin
	if (reset || cpu_as_n) cpu_data_strobe_seen <= 1'b0;
	else if (cpu_data_strobe) cpu_data_strobe_seen <= 1'b1;
end

wire cs_program = (cpu_even_address <= 24'h1ffffe);
wire cs_work = (cpu_even_address >= 24'h200000)
	&& (cpu_even_address <= 24'h20fffe);
wire cs_extra_rom = (cpu_even_address >= 24'h500000)
	&& (cpu_even_address <= 24'h57fffe);
wire cs_dsw1 = (cpu_even_address == 24'h600000);
wire cs_dsw2 = (cpu_even_address == 24'h600002);
wire cs_p1 = (cpu_even_address == 24'h700000);
wire cs_p2 = (cpu_even_address == 24'h700002);
wire cs_system = (cpu_even_address == 24'h700004);
wire cs_p1_extra = (cpu_even_address == 24'h700008);
wire cs_p2_extra = (cpu_even_address == 24'h70000a);
wire cs_watchdog = (cpu_even_address == 24'h70000c);
wire cs_coin = (cpu_even_address == 24'h800000);
wire cs_x1 = (cpu_even_address >= 24'hb00000)
	&& (cpu_even_address <= 24'hb03ffe);
wire cs_sprite = (cpu_even_address >= 24'hc00000)
	&& (cpu_even_address <= 24'hc3fffe);
wire cs_palette = (cpu_even_address >= 24'hc40000)
	&& (cpu_even_address <= 24'hc4fffe);
wire cs_extra_palette = (cpu_even_address >= 24'hc50000)
	&& (cpu_even_address <= 24'hc5fffe);
wire cs_video_regs = (cpu_even_address >= 24'hc60000)
	&& (cpu_even_address <= 24'hc6003e);
wire cs_sample_bank = (cpu_even_address >= 24'he00010)
	&& (cpu_even_address <= 24'he0001e);
wire cs_tmp = (cpu_even_address >= 24'hfffc00);
wire mapped_cycle = cs_program || cs_extra_rom || cs_work || cs_dsw1 || cs_dsw2
	|| cs_p1 || cs_p2 || cs_system || cs_p1_extra || cs_p2_extra
	|| cs_watchdog || cs_coin || cs_x1
	|| cs_sprite || cs_palette || cs_extra_palette || cs_video_regs
	|| cs_sample_bank || cs_tmp;

typedef enum logic [2:0] {
	BUS_IDLE, BUS_ROM_WAIT, BUS_RAM_WAIT, BUS_ACK
} bus_state_t;
bus_state_t bus_state;

wire local_write = !cpu_as_n && !cpu_iack_cycle && cpu_data_strobe
	&& cpu_data_strobe_seen && !cpu_rw && (bus_state == BUS_IDLE);

always_comb begin
	rowscroll_write = local_write && cs_sprite;
	rowscroll_write_address = cpu_even_address[17:1];
	rowscroll_write_data = cpu_data_out;
	rowscroll_write_byte_enable = cpu_byte_enable;
end

wire [15:0] work_q;
wire [15:0] work_video_unused;
wire [15:0] work_read_data;
wire [15:0] work_write_data;
gd_work_ram_cheats work_ram_cheats
(
	.address(cpu_even_address), .ram_q(work_q),
	.cpu_write_data(cpu_data_out), .cpu_write_be(cpu_byte_enable),
	.cheat_infinite_credits, .cheat_infinite_time,
	.cheat_p1_energy, .cheat_p2_energy,
	.cpu_read_data(work_read_data), .ram_write_data(work_write_data)
);

gd_word_ram #(.ADDR_WIDTH(15)) work_ram
(
	.clk(clk), .address(cpu_even_address[15:1]), .data(work_write_data),
	.byte_enable(cpu_byte_enable), .write(local_write && cs_work), .q(work_q),
	.video_clk(clk), .video_address(15'd0), .video_q(work_video_unused)
);

wire [15:0] sprite_q;
wire sprite_buffer_trigger = local_write && cs_video_regs
	&& (cpu_even_address[5:1] == 5'h13)
	&& ((cpu_byte_enable[1] && (cpu_data_out[15:8] != 8'd0))
	    || (cpu_byte_enable[0] && (cpu_data_out[7:0] != 8'd0)));
// Writing one to register 0x3c re-arms the raster timer. P0-113A software can
// use the special case where register 0x3e still names the current line: the
// still-active source queues a second service after the handler returns, then
// that second service advances to line two and begins the rowscroll chain.
always_comb raster_rearm = local_write && cs_video_regs
	&& (cpu_even_address[5:1] == 5'h1e)
	&& cpu_byte_enable[0] && cpu_data_out[0];
gd_sprite_ram sprite_ram
(
	.clk(clk), .reset, .buffer_trigger(sprite_buffer_trigger),
	.address(cpu_even_address[17:1]), .data(cpu_data_out),
	.byte_enable(cpu_byte_enable), .write(local_write && cs_sprite), .q(sprite_q),
	.video_clk(clk), .video_address(sprite_video_address), .video_q(sprite_video_q),
	.buffer_busy(sprite_buffer_busy)
);

wire [15:0] palette_q;
gd_word_ram #(.ADDR_WIDTH(15)) palette_ram
(
	.clk(clk), .address(cpu_even_address[15:1]), .data(cpu_data_out),
	.byte_enable(cpu_byte_enable), .write(local_write && cs_palette), .q(palette_q),
	.video_clk(clk), .video_address(palette_video_address), .video_q(palette_video_q)
);

logic [15:0] video_registers [0:31];
integer vr;
always_ff @(posedge clk) begin
	if (reset) begin
		for (vr = 0; vr < 32; vr = vr + 1) video_registers[vr] <= 16'd0;
	end
	else if (local_write && cs_video_regs) begin
		if (cpu_byte_enable[1]) video_registers[cpu_even_address[5:1]][15:8]
			<= cpu_data_out[15:8];
		if (cpu_byte_enable[0]) video_registers[cpu_even_address[5:1]][7:0]
			<= cpu_data_out[7:0];
	end
end
always_comb video_reg_q = video_registers[video_reg_address];
always_comb begin
	video_control = video_registers[24];
	video_x_offset = {video_registers[9][10:0], video_registers[8]};
	video_x_zoom = {video_registers[11][10:0], video_registers[10]};
	video_y_offset = {video_registers[13][10:0], video_registers[12]};
	video_y_zoom = {video_registers[15][10:0], video_registers[14]};
	raster_enable = video_registers[30];
	raster_position = video_registers[31];
end
wire [15:0] cpu_video_reg_q = video_registers[cpu_even_address[5:1]];

logic [15:0] p1_port;
logic [15:0] p2_port;
logic [15:0] system_port;
logic [15:0] p1_extra_port;
logic [15:0] p2_extra_port;
logic [7:0] dsw1_port;
always_comb begin
	p1_port = 16'hffff;
	p2_port = 16'hffff;
	system_port = 16'hffff;
	p1_extra_port = 16'hffff;
	p2_extra_port = 16'hffff;
	dsw1_port = dip_switches[7:0];
	// SW1:8 is the board's active-low service switch.
	if (service) dsw1_port[7] = 1'b0;
	// MAME bit order: left, right, up, down, B1, B2, B3, start.
	p1_port[0] = ~joystick_p1[1]; p2_port[0] = ~joystick_p2[1];
	p1_port[1] = ~joystick_p1[0]; p2_port[1] = ~joystick_p2[0];
	p1_port[2] = ~joystick_p1[3]; p2_port[2] = ~joystick_p2[3];
	p1_port[3] = ~joystick_p1[2]; p2_port[3] = ~joystick_p2[2];
	p1_port[4] = ~joystick_p1[4]; p2_port[4] = ~joystick_p2[4];
	p1_port[5] = ~joystick_p1[5]; p2_port[5] = ~joystick_p2[5];
	p1_port[6] = ~joystick_p1[6]; p2_port[6] = ~joystick_p2[6];
	p1_port[7] = ~joystick_p1[8]; p2_port[7] = ~joystick_p2[8];
	p1_extra_port[0] = ~joystick_p1[7];
	p2_extra_port[0] = ~joystick_p2[7];
	system_port[0] = ~joystick_p1[9];
	system_port[1] = ~joystick_p2[9];
	system_port[2] = ~(joystick_p1[10] | joystick_p2[10]);
	// The P0-113A language jumper is active low for Japanese.
	system_port[5] = ~language_japanese;
end

wire [15:0] tmp_q;
logic [15:0] tmp_parallel_out;
gd_tmp68301 tmp68301_regs
(
	.clk(clk), .reset(reset), .cpu_ce(tmp_cpu_ce), .cs(cs_tmp),
	.write(local_write && cs_tmp),
	.address(cpu_even_address[9:0]), .data(cpu_data_out),
	.byte_enable(cpu_byte_enable), .q(tmp_q), .ext_irq0(vblank),
	.parallel_in({12'd0, eeprom_do, 3'd0}),
	.parallel_out(tmp_parallel_out),
	.ext_irq1(raster_irq), .iack(tmp_iack), .irq_level(tmp_irq_level),
	.irq_vector(tmp_irq_vector)
);
always_comb begin
	eeprom_cs = tmp_parallel_out[2];
	eeprom_clk = tmp_parallel_out[1];
	eeprom_di = tmp_parallel_out[0];
end

always_ff @(posedge clk) begin
	x1_write <= 1'b0;
	if (reset) begin
		x1_address <= 13'd0;
		x1_data <= 16'd0;
		x1_byte_enable <= 2'd0;
		sample_banks <= 64'd0;
	end
	else begin
		if (local_write && cs_x1) begin
			x1_write <= 1'b1;
			x1_address <= cpu_even_address[13:1];
			x1_data <= cpu_data_out;
			x1_byte_enable <= cpu_byte_enable;
		end
		if (local_write && cs_sample_bank && cpu_byte_enable[0])
			sample_banks[cpu_even_address[3:1]*8 +: 8] <= cpu_data_out[7:0];
	end
end

always_ff @(posedge clk) begin
	debug_address <= cpu_bus_address;
	tmp_iack <= 1'b0;
	if (reset) begin
		bus_state <= BUS_IDLE;
		cpu_dtack_n <= 1'b1;
		cpu_data_in <= 16'hffff;
		rom_addr <= 22'd0;
		rom_req <= 1'b0;
		ram_addr <= 17'd0;
		ram_req <= 1'b0;
		ram_write <= 1'b0;
		ram_data <= 16'd0;
		ram_be <= 2'd0;
		debug_address <= 24'd0;
		debug_bus_cycles <= 32'd0;
		debug_rom_cycles <= 32'd0;
		debug_unmapped_cycles <= 16'd0;
		cpu_running <= 1'b0;
		tmp_iack <= 1'b0;
	end
	else begin
		case (bus_state)
			BUS_IDLE: begin
				cpu_dtack_n <= 1'b1;
				if (!cpu_as_n && cpu_data_strobe && cpu_data_strobe_seen) begin
					debug_bus_cycles <= debug_bus_cycles + 32'd1;
					if (cpu_iack_cycle) begin
						cpu_data_in <= {8'hff, tmp_irq_vector};
						tmp_iack <= 1'b1;
						cpu_dtack_n <= 1'b0;
						bus_state <= BUS_ACK;
					end
					else if ((cs_program || cs_extra_rom) && cpu_rw) begin
						if (cs_extra_rom)
							rom_addr <= 22'h200000
								+ (cpu_even_address - 24'h500000);
						else
							rom_addr <= cpu_even_address[21:0];
						rom_req <= ~rom_req;
						debug_rom_cycles <= debug_rom_cycles + 32'd1;
						cpu_running <= 1'b1;
						bus_state <= BUS_ROM_WAIT;
					end
					else if (cs_extra_palette) begin
						ram_addr <= {1'b1, cpu_even_address[15:0]};
						ram_write <= !cpu_rw;
						ram_data <= cpu_data_out;
						ram_be <= cpu_byte_enable;
						ram_req <= ~ram_req;
						bus_state <= BUS_RAM_WAIT;
					end
					else begin
						if (!mapped_cycle)
							debug_unmapped_cycles <= debug_unmapped_cycles + 16'd1;
						if (cs_work) cpu_data_in <= work_read_data;
						else if (cs_dsw1) cpu_data_in <= {8'hff, dsw1_port};
						else if (cs_dsw2) cpu_data_in <= {8'hff, dip_switches[15:8]};
						else if (cs_p1) cpu_data_in <= p1_port;
						else if (cs_p2) cpu_data_in <= p2_port;
						else if (cs_system) cpu_data_in <= system_port;
						else if (cs_p1_extra) cpu_data_in <= p1_extra_port;
						else if (cs_p2_extra) cpu_data_in <= p2_extra_port;
						else if (cs_x1) cpu_data_in <= x1_q;
						else if (cs_sprite) cpu_data_in <= sprite_q;
						else if (cs_palette) cpu_data_in <= palette_q;
						else if (cs_video_regs) cpu_data_in <= cpu_video_reg_q;
						else if (cs_tmp) cpu_data_in <= tmp_q;
						else cpu_data_in <= 16'hffff;
						cpu_dtack_n <= 1'b0;
						bus_state <= BUS_ACK;
					end
				end
			end

			BUS_ROM_WAIT: if (rom_ack == rom_req) begin
				cpu_data_in <= rom_dout;
				cpu_dtack_n <= 1'b0;
				bus_state <= BUS_ACK;
			end

			BUS_RAM_WAIT: if (ram_ack == ram_req) begin
				cpu_data_in <= ram_dout;
				cpu_dtack_n <= 1'b0;
				bus_state <= BUS_ACK;
			end

			BUS_ACK: if (cpu_as_n) begin
				cpu_dtack_n <= 1'b1;
				bus_state <= BUS_IDLE;
			end
			default: bus_state <= BUS_IDLE;
		endcase
	end
end

endmodule
