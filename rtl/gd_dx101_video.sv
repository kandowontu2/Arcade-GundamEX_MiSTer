// Allumer X1-020 / NEC DX-101 scanline renderer.
//
// This first hardware renderer implements the controller's normal multi-tile
// sprite path, floating tilemaps, global/local size selection, flips,
// transparency, opacity and 2/3/4/5/6/8-bpp masks.
//
// Format and drawing rules are derived from MAME's BSD-licensed device model
// by Luca Elia and David Haywood.
// SPDX-License-Identifier: GPL-3.0-or-later

module gd_dx101_video
#(
	// Rendering ahead is safe for both ordinary and raster-sensitive lists.
	// The rowscroll-history input replays the completed preceding frame's
	// per-line descriptor update while future scanlines are prepared.
	parameter bit AHEAD_RENDER = 1'b0,
	parameter integer H_TOTAL = 410,
	parameter integer V_TOTAL = 258,
	parameter integer H_VISIBLE = 304,
	parameter integer V_VISIBLE = 232,
	// A wider game can have long runs of expensive rows. Twenty-one buffers
	// still use two M10Ks per pixel lane (1008 of 1024 addresses) and provide
	// the largest reservoir available without consuming another RAM block.
	parameter integer BUFFER_COUNT = 21
)
(
	input  logic        clk,
	input  logic        reset,
	// The sprite RAM's video port is temporarily borrowed while the DX-101
	// snapshots a new display list. Pause the in-flight row without throwing
	// away completed line buffers; resetting here produces a visible band of
	// repeated scanlines while the look-ahead reservoir refills.
	input  logic        render_pause,
	input  logic        ce_pix,
	input  logic  [8:0] h_count,
	input  logic  [8:0] v_count,
	input  logic        hblank,
	input  logic        vblank,
	input  logic        raster_active,
	input  logic        rowscroll_override_valid,
	input  logic [14:0] rowscroll_override_record,
	input  logic [15:0] rowscroll_override_data,
	input  logic [15:0] video_control,
	input  logic        rotate_180,
	input  logic [26:0] video_x_offset,
	input  logic [26:0] video_x_zoom,
	input  logic [26:0] video_y_offset,
	input  logic [26:0] video_y_zoom,

	output logic [16:0] sprite_address,
	input  logic [63:0] sprite_q,
	output logic [14:0] palette_address,
	input  logic [15:0] palette_q,

	output logic [24:0] gfx_addr,
	output logic        gfx_req,
	input  logic [63:0] gfx_dout,
	input  logic        gfx_ack,

	output logic  [7:0] red,
	output logic  [7:0] green,
	output logic  [7:0] blue,
	output logic        busy,
	output logic        line_done,
	output logic [15:0] missed_lines,
	output logic  [8:0] rowscroll_lookup_line
);

localparam integer LINE_WORDS = H_VISIBLE / 8;
localparam integer LINE_DEPTH = LINE_WORDS * BUFFER_COUNT;
localparam integer FLOAT_COLUMNS = LINE_WORDS + 2;
localparam integer V_HALF = V_TOTAL / 2;
localparam integer BUFFER_BITS = $clog2(BUFFER_COUNT);
localparam integer LINE_ADDR_BITS = $clog2(LINE_DEPTH);
localparam integer LOOKAHEAD_DISTANCE = BUFFER_COUNT - 1;

// Eight X-interleaved memories turn an eight-pixel draw into one write per
// physical RAM. Pack all look-ahead buffers into the depth of each lane so
// Quartus infers eight synchronous M10Ks rather than replicating the eight
// pixel lanes once per queued scanline.
(* ramstyle = "M10K, no_rw_check" *) logic [14:0] line_buffer_bank0 [0:LINE_DEPTH-1];
(* ramstyle = "M10K, no_rw_check" *) logic [14:0] line_buffer_bank1 [0:LINE_DEPTH-1];
(* ramstyle = "M10K, no_rw_check" *) logic [14:0] line_buffer_bank2 [0:LINE_DEPTH-1];
(* ramstyle = "M10K, no_rw_check" *) logic [14:0] line_buffer_bank3 [0:LINE_DEPTH-1];
(* ramstyle = "M10K, no_rw_check" *) logic [14:0] line_buffer_bank4 [0:LINE_DEPTH-1];
(* ramstyle = "M10K, no_rw_check" *) logic [14:0] line_buffer_bank5 [0:LINE_DEPTH-1];
(* ramstyle = "M10K, no_rw_check" *) logic [14:0] line_buffer_bank6 [0:LINE_DEPTH-1];
(* ramstyle = "M10K, no_rw_check" *) logic [14:0] line_buffer_bank7 [0:LINE_DEPTH-1];
logic [14:0] line_read_data [0:7];
logic [LINE_ADDR_BITS-1:0] line_read_address;
logic [BUFFER_BITS-1:0] display_bank;
logic [BUFFER_BITS-1:0] work_bank;
logic [BUFFER_COUNT-1:0] bank_valid;
logic [8:0] bank_line [0:BUFFER_COUNT-1];
logic       scheduler_started;
logic       schedule_pending;
logic [8:0] next_render_line;
logic [8:0] render_distance;
logic       lookahead_ready;
logic [BUFFER_COUNT-1:0] display_match;
logic       selected_bank_found;
logic [BUFFER_BITS-1:0] selected_bank;
logic       free_bank_found;
logic [BUFFER_BITS-1:0] free_bank;
logic [8:0] target_line;
logic [8:0] clear_x;
integer line_bank_index;
integer select_bank_index;
wire [8:0] physical_next_line = (v_count == V_TOTAL - 1)
	? 9'd0 : (v_count + 9'd1);
wire [9:0] recovery_line_sum = {1'b0, v_count} + LOOKAHEAD_DISTANCE;
wire [8:0] recovery_render_line = (recovery_line_sum >= V_TOTAL)
	? (recovery_line_sum - V_TOTAL) : recovery_line_sum[8:0];
wire [8:0] logical_target_line = rotate_180 && (target_line < V_VISIBLE)
	? (V_VISIBLE - 1 - target_line) : target_line;
always_comb rowscroll_lookup_line = logical_target_line;

function automatic [8:0] line_forward_distance;
	input [8:0] from_line;
	input [8:0] to_line;
	begin
		if (to_line >= from_line)
			line_forward_distance = to_line - from_line;
		else
			line_forward_distance = to_line + V_TOTAL - from_line;
	end
endfunction

// Horizontal positions use a signed 10-bit coordinate ring. Objects that
// cross +511 continue at -512; a linear range comparison drops precisely the
// wrapped columns that appear at a screen edge.
function automatic wrapped_span_contains;
	input integer first_coordinate;
	input integer span_length;
	input integer coordinate;
	integer first_normalized;
	integer last_normalized;
	integer coordinate_normalized;
	begin
		first_normalized = first_coordinate & 1023;
		if (first_normalized & 512)
			first_normalized = first_normalized - 1024;
		last_normalized = (first_coordinate + span_length - 1) & 1023;
		if (last_normalized & 512)
			last_normalized = last_normalized - 1024;
		coordinate_normalized = coordinate & 1023;
		if (coordinate_normalized & 512)
			coordinate_normalized = coordinate_normalized - 1024;
		if (last_normalized >= first_normalized)
			wrapped_span_contains = (coordinate_normalized >= first_normalized)
				&& (coordinate_normalized <= last_normalized);
		else
			wrapped_span_contains = (coordinate_normalized <= last_normalized)
				|| (coordinate_normalized >= first_normalized);
	end
endfunction

// Vertical positions use a smaller 9-bit ring for both normal sprites and
// floating tilemap windows. Seta2 games expose this directly when splitting a
// large picture or background across descriptors: 0x1f9 followed by 0x039 is
// a continuous pair of 64-line chunks across the 0x200 boundary. Treating a
// floating window's Y as 10-bit discards the wrapped first chunk, leaving the
// top of gameplay backgrounds black.
function automatic wrapped_vertical_y_contains;
	input integer first_coordinate;
	input integer span_length;
	input integer coordinate;
	integer first_normalized;
	integer last_normalized;
	integer coordinate_normalized;
	begin
		first_normalized = first_coordinate & 511;
		if (first_normalized & 256)
			first_normalized = first_normalized - 512;
		last_normalized = (first_coordinate + span_length - 1) & 511;
		if (last_normalized & 256)
			last_normalized = last_normalized - 512;
		coordinate_normalized = coordinate & 511;
		if (coordinate_normalized & 256)
			coordinate_normalized = coordinate_normalized - 512;
		if (last_normalized >= first_normalized)
			wrapped_vertical_y_contains =
				(coordinate_normalized >= first_normalized)
				&& (coordinate_normalized <= last_normalized);
		else
			wrapped_vertical_y_contains =
				(coordinate_normalized <= last_normalized)
				|| (coordinate_normalized >= first_normalized);
	end
endfunction

// A DX-101 list can contain hundreds of one-tile descriptors even though
// only a few intersect a given scanline. Scan the 64-bit records into a
// compact active list, then spend renderer cycles only on contributing rows.
(* ramstyle = "M10K" *) logic [127:0] active_records [0:127];
logic [127:0] active_record_q;
logic [7:0] active_count;
logic [7:0] active_total;
logic [7:0] active_index;

always_comb begin
	render_distance = line_forward_distance(v_count, next_render_line);
	lookahead_ready = AHEAD_RENDER
		&& (render_distance >= 9'd1)
		&& (render_distance <= LOOKAHEAD_DISTANCE);
	selected_bank_found = 1'b0;
	selected_bank = display_bank;
	for (select_bank_index = 0; select_bank_index < BUFFER_COUNT;
	     select_bank_index = select_bank_index + 1) begin
		display_match[select_bank_index] = bank_valid[select_bank_index]
			&& (bank_line[select_bank_index] == v_count);
		if (!selected_bank_found && display_match[select_bank_index]) begin
			selected_bank_found = 1'b1;
			selected_bank = select_bank_index[BUFFER_BITS-1:0];
		end
	end
	free_bank_found = 1'b0;
	free_bank = '0;
	for (select_bank_index = 0; select_bank_index < BUFFER_COUNT;
	     select_bank_index = select_bank_index + 1) begin
		if (!free_bank_found && !bank_valid[select_bank_index]
		    && (display_bank != select_bank_index[BUFFER_BITS-1:0])) begin
			free_bank_found = 1'b1;
			free_bank = select_bank_index[BUFFER_BITS-1:0];
		end
	end
end

logic [8:0] prefetch_x;
logic [8:0] display_x;
logic [14:0] scan_index;
function automatic [LINE_ADDR_BITS-1:0] packed_line_address;
	input [BUFFER_BITS-1:0] buffer_number;
	input [5:0] row_number;
	begin
		packed_line_address = buffer_number * LINE_WORDS + row_number;
	end
endfunction

always_comb begin
	if (h_count >= H_TOTAL - 2) prefetch_x = h_count - (H_TOTAL - 2);
	else prefetch_x = h_count + 9'd2;
	if (rotate_180 && (prefetch_x < H_VISIBLE))
		display_x = H_VISIBLE - 1 - prefetch_x;
	else
		display_x = prefetch_x;
	line_read_address = packed_line_address(display_bank, display_x[8:3]);
	if (prefetch_x < H_VISIBLE) begin
		case (display_x[2:0])
			3'd0: scan_index = line_read_data[0];
			3'd1: scan_index = line_read_data[1];
			3'd2: scan_index = line_read_data[2];
			3'd3: scan_index = line_read_data[3];
			3'd4: scan_index = line_read_data[4];
			3'd5: scan_index = line_read_data[5];
			3'd6: scan_index = line_read_data[6];
			default: scan_index = line_read_data[7];
		endcase
	end
	else scan_index = 15'd0;
end

always_ff @(posedge clk) begin
	if (ce_pix) begin
		palette_address <= scan_index;
		if (!hblank && !vblank && !video_control[0]) begin
			red <= {palette_q[14:10], palette_q[14:12]};
			green <= {palette_q[9:5], palette_q[9:7]};
			blue <= {palette_q[4:0], palette_q[4:2]};
		end
		else begin
			red <= 8'd0;
			green <= 8'd0;
			blue <= 8'd0;
		end
	end
end

typedef enum logic [4:0] {
	R_IDLE, R_CLEAR, R_HEADER_ISSUE, R_HEADER_WAIT, R_HEADER_CAPTURE,
	R_HEADER_PROCESS, R_SPRITE_ISSUE, R_SPRITE_WAIT, R_SPRITE_PIPE,
	R_SPRITE_CAPTURE,
	R_ACTIVE_LOAD, R_ACTIVE_WAIT, R_SPRITE_PROCESS, R_NORMAL_PREP, R_FLOAT_SELECT,
	R_TILEMAP_WAIT, R_TILEMAP_CAPTURE,
	R_TILEMAP_PROCESS, R_GFX_WAIT, R_GFX_DRAW,
	R_NEXT_SPRITE, R_NEXT_HEADER, R_DONE
} render_state_t;
render_state_t state;

logic [8:0] header_index;
logic [1:0] read_word;
logic [63:0] scan_record_q;
logic [15:0] h0, h1, h2, h3;
logic [15:0] s0, s1, s2, s3;
logic [8:0] sprites_remaining;
logic [16:0] sprite_pointer;
logic last_header;
logic use_global_size;
logic opaque;
logic [2:0] bpp_mode;
logic flip_x;
logic flip_y;
logic [18:0] tile_code;
logic signed [11:0] tile_screen_x;
logic [2:0] tile_line;
logic [3:0] tiles_x;
logic [3:0] tile_x;
logic [1:0] normal_x_exp;
logic [1:0] normal_y_exp;
logic [3:0] normal_row;
logic [10:0] color_code;
logic [63:0] gfx_line;
logic float_mode;
logic [6:0] float_x;
logic [5:0] float_columns_remaining;
logic [9:0] float_scroll_x;
logic [8:0] float_source_line;
logic [4:0] float_page;
logic float_is_16;
logic signed [11:0] float_sx;
logic signed [11:0] float_first_column;
logic signed [11:0] float_last_column;
logic signed [11:0] float_dest_x;
logic [15:0] tilemap_attr;
logic [15:0] tilemap_code;

integer calc_sy;
integer calc_sx;
integer calc_firstline;
integer calc_endline;
integer calc_size_x;
integer calc_size_y;
integer calc_line;
integer calc_row;
integer calc_base_code;
integer calc_height;
integer calc_width;
integer calc_scroll_y;
integer calc_tile_x;
integer calc_tile_y;
integer calc_tile_address;
integer calc_dest_x;
integer calc_screen_x;
integer calc_used_line;
integer calc_y_base;
logic [7:0] draw_pen [0:7];
integer draw_pixel_x [0:7];
integer draw_calc_column;
integer route_column;
integer route_address;
integer draw_route_column;
integer draw_route_address;
logic [7:0] line_write_enable;
logic [5:0] line_write_row [0:7];
logic [14:0] line_write_data [0:7];
logic [7:0] draw_write_enable;
logic [5:0] draw_write_row [0:7];
logic [14:0] draw_write_data [0:7];

function automatic [7:0] mask_pen;
	input [7:0] value;
	input [2:0] mode;
	begin
		case (mode)
			3'd1: mask_pen = (value & 8'h30) >> 4;
			3'd2: mask_pen = value & 8'h07;
			3'd4: mask_pen = value & 8'h0f;
			3'd5: mask_pen = (value & 8'hf0) >> 4;
			3'd6: mask_pen = value & 8'h3f;
			default: mask_pen = value;
		endcase
	end
endfunction

// Exact graphics row for the same normal-sprite tile four physical lines
// later. This crosses an 8-pixel tile boundary using the descriptor's
// horizontal size and vertical flip, avoiding speculative sprite-state reads.
function automatic sprite_intersects_line;
	input [15:0] fh0;
	input [15:0] fh1;
	input [15:0] fh2;
	input [15:0] fh3;
	input [15:0] fs0;
	input [15:0] fs1;
	input  [8:0] physical_line;
	input [26:0] y_offset;
	input [26:0] y_zoom;
	integer sy;
	integer first_line;
	integer end_line;
	integer height;
	integer size_y;
	integer width;
	integer used_line;
	integer y_base;
	begin
		y_base = (27'h7ffffff - y_offset) >> 16;
		if (fh0[14] || !y_zoom[26])
			used_line = physical_line;
		else
			used_line = (physical_line + y_base) & 11'h7ff;
		if (fh3[15]) begin
			sy = fs1 & 16'h01ff;
			if (sy & 9'h100) sy = sy - 512;
			if (fh0[14]) sy = sy - 16'h90;
			sy = sy & 9'h1ff;
			if (sy & 9'h100) sy = sy - 512;
			height = ((((fh0[12] ? fh2 : fs1) & 16'hfc00) >> 10) + 1);
			first_line = (sy + (fh2 & 16'h01ff)) & 9'h1ff;
			if (first_line & 9'h100) first_line = first_line - 512;
			end_line = first_line + height * 16 - 1;
			width = ((fh0[12] ? fh1 : fs0) & 16'hfc00) >> 10;
			sprite_intersects_line = (width != 0)
				&& wrapped_vertical_y_contains(first_line, height * 16,
					used_line);
		end
		else begin
			sy = fs1 & 16'h01ff;
			if (sy & 9'h100) sy = sy - 512;
			if (fh0[14]) sy = sy - 16'h90;
			size_y = 1 << ((((fh0[12] ? fh2 : fs1) & 16'h0c00) >> 10));
			first_line = (sy + (fh2 & 16'h01ff)) & 9'h1ff;
			if (first_line & 9'h100) first_line = first_line - 512;
			end_line = first_line + size_y * 8 - 1;
			sprite_intersects_line = wrapped_vertical_y_contains(
				first_line, size_y * 8, used_line);
		end
	end
endfunction

wire scan_record_visible = sprite_intersects_line(
	h0, h1, h2, h3, scan_record_q[15:0], scan_record_q[31:16],
	logical_target_line, video_y_offset, video_y_zoom);
wire [15:0] scan_s2 = rowscroll_override_valid
	&& (sprite_pointer[16:2] == rowscroll_override_record)
	? rowscroll_override_data : scan_record_q[47:32];
wire [127:0] scan_record_data = {
	h0, h1, h2, h3,
	scan_record_q[15:0], scan_record_q[31:16],
	scan_s2, scan_record_q[63:48]
};

// Keep the active list as a true synchronous one-write/one-read memory.
// Splitting the 128-bit read into fields in the main state machine causes
// Quartus 17 to implement the array as thousands of registers.
always_ff @(posedge clk) begin
	if (reset)
		scan_record_q <= 64'd0;
	else if ((state == R_SPRITE_PIPE) || (state == R_SPRITE_CAPTURE))
		scan_record_q <= sprite_q;
	if ((state == R_SPRITE_CAPTURE) && scan_record_visible
	    && (active_count < 8'd128))
		active_records[active_count] <= scan_record_data;
	if (state == R_ACTIVE_LOAD)
		active_record_q <= active_records[active_index];
end

// MAME's STEP8(0,1) plane offsets and STEP8(7*8,-8) X offsets mean that source
// byte 7 supplies pen bit 7, byte 6 supplies bit 6, ... byte 0 supplies bit 0.
// gfx_line holds four big-endian SDRAM words, lowest-addressed word in [15:0],
// so the two source bytes in each 16-bit word occupy reversed 8-bit slices.
function automatic [7:0] decode_pen;
	input [63:0] row;
	input [2:0] column;
	begin
		decode_pen = {
			row[55-column], row[63-column],
			row[39-column], row[47-column],
			row[23-column], row[31-column],
			row[7-column], row[15-column]
		};
	end
endfunction

always_comb begin
	for (draw_calc_column = 0; draw_calc_column < 8;
	     draw_calc_column = draw_calc_column + 1) begin
		draw_pen[draw_calc_column] = mask_pen(
			decode_pen(gfx_line, draw_calc_column[2:0]), bpp_mode);
		draw_pixel_x[draw_calc_column] = tile_screen_x + (flip_x
			? (7 - draw_calc_column) : draw_calc_column);
	end
end

// Route clear or draw writes by X[2:0]. Eight adjacent draw pixels always
// land in eight distinct banks, so every physical RAM has one write port.
always_comb begin
	draw_write_enable = 8'd0;
	for (draw_route_column = 0; draw_route_column < 8;
	     draw_route_column = draw_route_column + 1) begin
		draw_write_row[draw_route_column] = 6'd0;
		draw_write_data[draw_route_column] = 15'd0;
	end
	for (draw_route_column = 0; draw_route_column < 8;
	     draw_route_column = draw_route_column + 1) begin
		draw_route_address = draw_pixel_x[draw_route_column];
		if ((draw_route_address >= 0) && (draw_route_address < H_VISIBLE)
		    && (draw_pen[draw_route_column] != 0 || opaque)) begin
			draw_write_enable[draw_route_address & 7] = 1'b1;
			draw_write_row[draw_route_address & 7] = draw_route_address >> 3;
			draw_write_data[draw_route_address & 7] =
				({color_code, 4'd0} + draw_pen[draw_route_column]) & 15'h7fff;
		end
	end
end

always_comb begin
	line_write_enable = 8'd0;
	route_address = 0;
	for (route_column = 0; route_column < 8;
	     route_column = route_column + 1) begin
		line_write_row[route_column] = 6'd0;
		line_write_data[route_column] = 15'd0;
	end
	if (state == R_CLEAR) begin
		for (route_column = 0; route_column < 8;
		     route_column = route_column + 1) begin
			route_address = clear_x + route_column;
			line_write_enable[route_address & 7] = 1'b1;
			line_write_row[route_address & 7] = route_address >> 3;
			line_write_data[route_address & 7] = 15'd0;
		end
	end
	else if (state == R_GFX_DRAW) begin
		for (route_column = 0; route_column < 8;
		     route_column = route_column + 1) begin
			line_write_enable[route_column] = draw_write_enable[route_column];
			line_write_row[route_column] = draw_write_row[route_column];
			line_write_data[route_column] = draw_write_data[route_column];
		end
	end
end

always_ff @(posedge clk) begin
	line_read_data[0] <= line_buffer_bank0[line_read_address];
	line_read_data[1] <= line_buffer_bank1[line_read_address];
	line_read_data[2] <= line_buffer_bank2[line_read_address];
	line_read_data[3] <= line_buffer_bank3[line_read_address];
	line_read_data[4] <= line_buffer_bank4[line_read_address];
	line_read_data[5] <= line_buffer_bank5[line_read_address];
	line_read_data[6] <= line_buffer_bank6[line_read_address];
	line_read_data[7] <= line_buffer_bank7[line_read_address];
	if (line_write_enable[0]) begin
		line_buffer_bank0[packed_line_address(work_bank, line_write_row[0])]
			<= line_write_data[0];
	end
	if (line_write_enable[1]) begin
		line_buffer_bank1[packed_line_address(work_bank, line_write_row[1])]
			<= line_write_data[1];
	end
	if (line_write_enable[2]) begin
		line_buffer_bank2[packed_line_address(work_bank, line_write_row[2])]
			<= line_write_data[2];
	end
	if (line_write_enable[3]) begin
		line_buffer_bank3[packed_line_address(work_bank, line_write_row[3])]
			<= line_write_data[3];
	end
	if (line_write_enable[4]) begin
		line_buffer_bank4[packed_line_address(work_bank, line_write_row[4])]
			<= line_write_data[4];
	end
	if (line_write_enable[5]) begin
		line_buffer_bank5[packed_line_address(work_bank, line_write_row[5])]
			<= line_write_data[5];
	end
	if (line_write_enable[6]) begin
		line_buffer_bank6[packed_line_address(work_bank, line_write_row[6])]
			<= line_write_data[6];
	end
	if (line_write_enable[7]) begin
		line_buffer_bank7[packed_line_address(work_bank, line_write_row[7])]
			<= line_write_data[7];
	end
end

always_ff @(posedge clk) begin
	if (reset) begin
		state <= R_IDLE;
		busy <= 1'b0;
		line_done <= 1'b0;
		display_bank <= '0;
		work_bank <= {{(BUFFER_BITS-1){1'b0}}, 1'b1};
		bank_valid <= '0;
		for (line_bank_index = 0; line_bank_index < BUFFER_COUNT;
		     line_bank_index = line_bank_index + 1)
			bank_line[line_bank_index] <= 9'd0;
		scheduler_started <= 1'b0;
		schedule_pending <= 1'b0;
		next_render_line <= 9'd0;
		target_line <= 9'd0;
		clear_x <= 9'd0;
		active_count <= 8'd0;
		active_total <= 8'd0;
		active_index <= 8'd0;
		sprite_address <= 17'd0;
		gfx_addr <= 25'd0;
		gfx_req <= 1'b0;
		missed_lines <= 16'd0;
	end
	else begin
		line_done <= 1'b0;
		if (ce_pix && (h_count == 9'd0)) begin
			// Select only the row tagged for this physical line. An expired row
			// is reclaimed below instead of feeding a long "newest late row"
			// priority chain into every bank-valid register.
			if (selected_bank_found) begin
				bank_valid[display_bank] <= 1'b0;
				display_bank <= selected_bank;
			end
			else if (scheduler_started)
				missed_lines <= missed_lines + 16'd1;

			// Reclaim completed lines that arrived after their display slot.
			for (line_bank_index = 0; line_bank_index < BUFFER_COUNT;
			     line_bank_index = line_bank_index + 1) begin
				if ((line_bank_index != display_bank)
				    && !display_match[line_bank_index]
				    && bank_valid[line_bank_index]
				    && (line_forward_distance(bank_line[line_bank_index], v_count)
				        > 9'd0)
				    && (line_forward_distance(bank_line[line_bank_index], v_count)
				        <= V_HALF))
					bank_valid[line_bank_index] <= 1'b0;
			end

			schedule_pending <= 1'b1;
			if (!scheduler_started) begin
				scheduler_started <= 1'b1;
				// Start at the far edge of the reservoir. If the first row is
				// expensive, starting only one row ahead leaves the renderer late
				// forever and duplicates every following physical scanline.
				next_render_line <= recovery_render_line;
			end
			else if ((render_distance == 9'd0) || (render_distance > V_HALF))
				// Re-lock with the same full lead after any genuine late row.
				next_render_line <= recovery_render_line;
		end

		// The scanout scheduler above must keep changing display banks while the
		// sprite port is unavailable. Only freeze the row-building state machine.
		// gd_core extends render_pause beyond buffer_busy so synchronous sprite
		// RAM has two clocks to restore the renderer's held address and data.
		if (!render_pause) case (state)
			R_IDLE: begin
				// Fill every spare bank so cheap rows accumulate enough reserve to
				// absorb consecutive expensive rows. Raster-sensitive descriptor
				// word 2 is supplied by the preceding-frame rowscroll history, so
				// those lists can use the same look-ahead queue safely.
				if (scheduler_started && free_bank_found
				    && ((lookahead_ready)
				        || ((!AHEAD_RENDER)
				            && schedule_pending))) begin
					work_bank <= free_bank;
					bank_valid[free_bank] <= 1'b0;
					target_line <= AHEAD_RENDER
						? next_render_line
						: physical_next_line;
					clear_x <= 9'd0;
					active_count <= 8'd0;
					active_total <= 8'd0;
					active_index <= 8'd0;
					busy <= 1'b1;
					schedule_pending <= 1'b0;
					state <= R_CLEAR;
				end
			end
			R_CLEAR: begin
				if (clear_x == H_VISIBLE - 8) begin
					// Do not rescan and draw the sprite list for rows hidden by
					// vertical blank. Completing those rows after clear lets the
					// reservoir refill before the next active frame.
					if (target_line >= V_VISIBLE)
						state <= R_DONE;
					else begin
						header_index <= 9'd0;
						read_word <= 2'd0;
						state <= R_HEADER_ISSUE;
					end
				end
				else clear_x <= clear_x + 9'd8;
			end

			R_HEADER_ISSUE: begin
				sprite_address <= 17'h01800 + {header_index, 2'b00};
				state <= R_HEADER_WAIT;
			end
			R_HEADER_WAIT: state <= R_HEADER_CAPTURE;
			R_HEADER_CAPTURE: begin
				h0 <= sprite_q[15:0];
				h1 <= sprite_q[31:16];
				h2 <= sprite_q[47:32];
				h3 <= sprite_q[63:48];
				state <= R_HEADER_PROCESS;
			end

			R_HEADER_PROCESS: begin
				last_header <= h0[15];
				sprites_remaining <= {1'b0, h0[7:0]} + 9'd1;
				sprite_pointer <= {h3[14:0], 2'b00};
				sprite_address <= {h3[14:0], 2'b00};
				state <= R_SPRITE_WAIT;
			end

			// The wait clocks the initial descriptor address into the four-bank
			// RAM. R_SPRITE_PIPE registers its output before the visibility
			// filter, breaking the RAM-to-filter timing path. Thereafter each
			// capture consumes one record and registers the next one, sustaining
			// one 64-bit descriptor per renderer clock.
			R_SPRITE_ISSUE: state <= R_SPRITE_WAIT;
			R_SPRITE_WAIT: begin
				if (sprites_remaining > 9'd1)
					sprite_address <= sprite_pointer + 17'd4;
				else if (!last_header)
					sprite_address <= 17'h01800
						+ {(header_index + 9'd1), 2'b00};
				state <= R_SPRITE_PIPE;
			end
			R_SPRITE_PIPE: begin
				if (sprites_remaining > 9'd2)
					sprite_address <= sprite_pointer + 17'd8;
				else if ((sprites_remaining == 9'd2) && !last_header)
					sprite_address <= 17'h01800
						+ {(header_index + 9'd1), 2'b00};
				state <= R_SPRITE_CAPTURE;
			end
			R_SPRITE_CAPTURE: begin
				if (scan_record_visible && (active_count < 8'd128)) begin
					active_count <= active_count + 8'd1;
				end

				if (sprites_remaining == 9'd1) begin
					if (last_header) begin
						active_total <= active_count
							+ ((scan_record_visible
							    && (active_count < 8'd128)) ? 8'd1 : 8'd0);
						active_index <= 8'd0;
						if ((active_count == 8'd0) && !scan_record_visible)
							state <= R_DONE;
						else state <= R_ACTIVE_LOAD;
					end
					else begin
						header_index <= header_index + 9'd1;
						state <= R_HEADER_CAPTURE;
					end
				end
				else begin
					sprites_remaining <= sprites_remaining - 9'd1;
					sprite_pointer <= sprite_pointer + 17'd4;
					if (sprites_remaining == 9'd3) begin
						if (!last_header)
							sprite_address <= 17'h01800
								+ {(header_index + 9'd1), 2'b00};
					end
					else if (sprites_remaining > 9'd3)
						sprite_address <= sprite_pointer + 17'd12;
				end
			end

			R_ACTIVE_LOAD: begin
				state <= R_ACTIVE_WAIT;
			end
			R_ACTIVE_WAIT: begin
				h0 <= active_record_q[127:112];
				h1 <= active_record_q[111:96];
				h2 <= active_record_q[95:80];
				h3 <= active_record_q[79:64];
				s0 <= active_record_q[63:48];
				s1 <= active_record_q[47:32];
				s2 <= active_record_q[31:16];
				s3 <= active_record_q[15:0];
				use_global_size <= active_record_q[124];
				opaque <= active_record_q[125];
				bpp_mode <= active_record_q[122:120];
				state <= R_SPRITE_PROCESS;
			end

			R_SPRITE_PROCESS: begin
				// P0-113A software uses the controller's negative unit Y zoom as a
				// screen flip/offset. Its programmed values transform visible
				// line Y to source line Y+128. Header bit 14 bypasses the global
				// transform and uses the physical raster line directly.
				calc_y_base = (27'h7ffffff - video_y_offset) >> 16;
				if (h0[14] || !video_y_zoom[26])
					calc_used_line = logical_target_line;
				else
					calc_used_line = (logical_target_line + calc_y_base) & 11'h7ff;
				if (h3[15]) begin
					calc_sy = s1 & 16'h01ff;
					if (calc_sy & 9'h100) calc_sy = calc_sy - 512;
					if (h0[14]) calc_sy = calc_sy - 16'h90;
					calc_sy = calc_sy & 9'h1ff;
					if (calc_sy & 9'h100) calc_sy = calc_sy - 512;
					calc_height = (((use_global_size ? h2 : s1)
						& 16'hfc00) >> 10) + 1;
					calc_firstline = (calc_sy + (h2 & 16'h01ff)) & 9'h1ff;
					if (calc_firstline & 9'h100) calc_firstline = calc_firstline - 512;
					calc_endline = calc_firstline + calc_height * 16 - 1;
					calc_sx = s0 & 16'h03ff;
					if (h0[14]) calc_sx = calc_sx - 16'h80;
					calc_width = ((use_global_size ? h1 : s0) & 16'hfc00) >> 10;
					calc_dest_x = (calc_sx + (h1 & 16'h03ff)) & 10'h3ff;
					calc_dest_x = (calc_dest_x & 10'h1ff)
						- (calc_dest_x & 10'h200);
					if ((calc_width == 0)
					    || !wrapped_vertical_y_contains(calc_firstline,
					        calc_height * 16, calc_used_line))
						state <= R_NEXT_SPRITE;
					else begin
						calc_scroll_y = s3 & 16'h01ff;
						if (h0[14]) calc_scroll_y = calc_scroll_y - 16'h90;
						float_mode <= 1'b1;
						float_scroll_x <= s2[9:0];
						float_source_line <= (calc_used_line - calc_scroll_y) & 9'h1ff;
						float_page <= s2[14:10];
						float_is_16 <= s2[15];
						float_sx <= calc_sx;
						float_first_column <= calc_dest_x;
						float_last_column <= calc_dest_x + calc_width * 16 - 1;
						// Begin at the first tile that can touch the visible
						// screen rather than walking all 128 columns. The DX-101
						// coordinate ring is 1024 pixels and each entry advances 8.
						calc_screen_x = h0[14] ? -7
							: $signed({video_x_offset[26],
							           video_x_offset[26:16]}) - 7;
						calc_dest_x = calc_sx + s2[9:0]
							+ (h1 & 16'h03ff) + 16'h10;
						calc_tile_x = (calc_screen_x - calc_dest_x) & 10'h3ff;
						float_x <= ((calc_tile_x + 7) >> 3) & 7'h7f;
						float_columns_remaining <= FLOAT_COLUMNS;
						state <= R_FLOAT_SELECT;
					end
				end
				else begin
					float_mode <= 1'b0;
					calc_sy = s1 & 16'h01ff;
					if (calc_sy & 9'h100) calc_sy = calc_sy - 512;
					if (h0[14]) calc_sy = calc_sy - 16'h90;
					calc_size_y = 1 << (((use_global_size ? h2 : s1)
						& 16'h0c00) >> 10);
					calc_firstline = (calc_sy + (h2 & 16'h01ff)) & 9'h1ff;
					if (calc_firstline & 9'h100) calc_firstline = calc_firstline - 512;
					calc_endline = calc_firstline + calc_size_y * 8 - 1;
					if (wrapped_vertical_y_contains(calc_firstline,
					    calc_size_y * 8, calc_used_line)) begin
						normal_x_exp <= ((use_global_size ? h1 : s0)
							& 16'h0c00) >> 10;
						normal_y_exp <= ((use_global_size ? h2 : s1)
							& 16'h0c00) >> 10;
						calc_size_x = 1 << (((use_global_size ? h1 : s0)
							& 16'h0c00) >> 10);
						calc_sx = ((s0 + (h1 & 16'h03ff)) & 10'h1ff)
							- ((s0 + (h1 & 16'h03ff)) & 10'h200);
						if (h0[14]) calc_sx = calc_sx - 16'h80;
						calc_line = (calc_used_line - calc_firstline) & 511;
						calc_row = calc_line >> 3;
						normal_row <= calc_row[3:0];
						flip_x <= s2[4];
						flip_y <= s2[3];
						tile_line <= s2[3] ? (3'd7 - calc_line[2:0])
							: calc_line[2:0];
						tiles_x <= calc_size_x[3:0];
						tile_x <= 4'd0;
						color_code <= h0[14] ? 11'h7ff : s2[15:5];
						// Offset X is a signed 11-bit pixel value in the high
						// half of the 27-bit register pair. Fixed-position
						// headers bypass it (their -0x80 adjustment is above).
						if (!h0[14])
							calc_sx = calc_sx
								- $signed({video_x_offset[26],
								           video_x_offset[26:16]});
						tile_screen_x <= calc_sx;
						state <= R_NORMAL_PREP;
					end
					else state <= R_NEXT_SPRITE;
				end
			end

			R_NORMAL_PREP: begin
				// Pipeline the normal-sprite tile-number calculation. Express
				// its power-of-two products as shifts so this address path does
				// not infer a DSP multiplier between sprite RAM and the cache.
				calc_size_x = 1 << normal_x_exp;
				calc_size_y = 1 << normal_y_exp;
				calc_base_code = ({s2[2:0], s3}
					& ~((1 << ({1'b0, normal_x_exp}
					             + {1'b0, normal_y_exp})) - 1))
					+ ((s2[3] ? (calc_size_y - 1 - normal_row)
						: normal_row) << normal_x_exp)
					+ (s2[4] ? calc_size_x - 1 : 0);
				tile_code <= calc_base_code[18:0];
				gfx_addr <= {calc_base_code[18:0], 6'd0}
					+ {19'd0, tile_line, 3'd0};
				gfx_req <= ~gfx_req;
				state <= R_GFX_WAIT;
			end

			R_FLOAT_SELECT: begin
				// A floating tilemap covers a 1024-pixel circular row, but
				// only the visible subset of its 128 entries can reach this
				// scanline. Reject the other entries before using
				// sprite RAM or graphics bandwidth.
				calc_dest_x = float_sx + float_scroll_x
					+ (h1 & 16'h03ff) + 16'h10 + float_x * 8;
				calc_dest_x = ((calc_dest_x + 16'h10) & 10'h3ff) - 16'h10;
				calc_dest_x = (calc_dest_x & 10'h1ff)
					- (calc_dest_x & 10'h200);
				calc_screen_x = calc_dest_x;
				if (!h0[14])
					calc_screen_x = calc_screen_x
						- $signed({video_x_offset[26],
						           video_x_offset[26:16]});
				if (!wrapped_span_contains(float_first_column - 8,
				        (float_last_column - float_first_column + 1) + 8,
				        calc_dest_x)
				    || (calc_screen_x < -7)
				    || (calc_screen_x > H_VISIBLE - 1)) begin
					if (float_columns_remaining == 6'd1)
						state <= R_NEXT_SPRITE;
					else begin
						float_x <= float_x + 7'd1;
						float_columns_remaining <= float_columns_remaining - 6'd1;
					end
				end
				else begin
					float_dest_x <= calc_screen_x;
					calc_tile_x = float_is_16 ? (float_x >> 1) : float_x;
					calc_tile_y = float_source_line >> (float_is_16 ? 4 : 3);
					calc_tile_y = calc_tile_y ^ 31;
					calc_tile_address = (float_page << 12)
						+ ((calc_tile_y & 31) << 7)
						+ ((calc_tile_x & 63) << 1);
					sprite_address <= calc_tile_address[16:0];
					read_word <= 2'd0;
					state <= R_TILEMAP_WAIT;
				end
			end

			R_TILEMAP_WAIT: state <= R_TILEMAP_CAPTURE;
			R_TILEMAP_CAPTURE: begin
				if (sprite_address[1]) begin
					tilemap_attr <= sprite_q[47:32];
					tilemap_code <= sprite_q[63:48];
				end
				else begin
					tilemap_attr <= sprite_q[15:0];
					tilemap_code <= sprite_q[31:16];
				end
				state <= R_TILEMAP_PROCESS;
			end
			R_TILEMAP_PROCESS: begin
				begin
					calc_base_code = {tilemap_attr[2:0], tilemap_code};
					if (float_is_16) begin
						calc_base_code = calc_base_code & ~3;
						if ((!tilemap_attr[4] && float_x[0])
						    || (tilemap_attr[4] && !float_x[0]))
							calc_base_code = calc_base_code + 1;
						if ((!tilemap_attr[3] && float_source_line[3])
						    || (tilemap_attr[3] && !float_source_line[3]))
							calc_base_code = calc_base_code + 2;
					end
					flip_x <= tilemap_attr[4];
					flip_y <= tilemap_attr[3];
					tile_code <= calc_base_code[18:0];
					tile_screen_x <= float_dest_x;
					tile_line <= tilemap_attr[3] ? (3'd7 - float_source_line[2:0])
						: float_source_line[2:0];
					color_code <= tilemap_attr[15:5];
					gfx_addr <= {calc_base_code[18:0], 6'd0}
						+ {19'd0, (tilemap_attr[3]
						? (3'd7 - float_source_line[2:0])
						: float_source_line[2:0]), 3'd0};
					gfx_req <= ~gfx_req;
					state <= R_GFX_WAIT;
				end
			end

			R_GFX_WAIT: if (gfx_ack == gfx_req) begin
				gfx_line <= gfx_dout;
				state <= R_GFX_DRAW;
			end
			R_GFX_DRAW: begin
				if (float_mode) begin
					if (float_columns_remaining == 6'd1)
						state <= R_NEXT_SPRITE;
					else begin
						float_x <= float_x + 7'd1;
						float_columns_remaining <= float_columns_remaining - 6'd1;
						state <= R_FLOAT_SELECT;
					end
				end
				else if (tile_x + 4'd1 < tiles_x) begin
					tile_x <= tile_x + 4'd1;
					tile_screen_x <= tile_screen_x + 12'sd8;
					tile_code <= flip_x ? tile_code - 19'd1 : tile_code + 19'd1;
					gfx_addr <= {(flip_x ? tile_code - 19'd1
						: tile_code + 19'd1), 6'd0} + {19'd0, tile_line, 3'd0};
					gfx_req <= ~gfx_req;
					state <= R_GFX_WAIT;
				end
				else state <= R_NEXT_SPRITE;
			end

			R_NEXT_SPRITE: begin
				if ((active_index + 8'd1) >= active_total)
					state <= R_DONE;
				else begin
					active_index <= active_index + 8'd1;
					state <= R_ACTIVE_LOAD;
				end
			end
			R_NEXT_HEADER: state <= R_DONE;
			R_DONE: begin
				line_done <= 1'b1;
				bank_valid[work_bank] <= 1'b1;
				bank_line[work_bank] <= target_line;
				next_render_line <= (target_line == V_TOTAL - 1)
					? 9'd0 : target_line + 9'd1;
				busy <= 1'b0;
				state <= R_IDLE;
			end
			default: state <= R_IDLE;
		endcase
	end
end

endmodule
