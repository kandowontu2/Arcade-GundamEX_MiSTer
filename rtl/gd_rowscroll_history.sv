// DX-101 raster rowscroll write history.
//
// Seta2 software rewrites word 2 of packed floating-tilemap descriptors at
// every even raster position.  A software renderer can draw completed rows
// immediately, but this FPGA renderer must prepare a row before it is sent to
// the monitor.  Preserve the complete preceding frame of raster writes and
// replay the matching scroll word while that row's descriptor is scanned.
// SPDX-License-Identifier: GPL-3.0-or-later

module gd_rowscroll_history
#(
	parameter integer VISIBLE_LINES = 232
)
(
	input  logic        clk,
	input  logic        reset,
	input  logic        ce_pix,
	input  logic  [8:0] h_count,
	input  logic  [8:0] v_count,
	input  logic        capture_enable,
	input  logic  [8:0] raster_position,
	input  logic        write,
	input  logic [16:0] write_address,
	input  logic [15:0] write_data,
	input  logic  [1:0] write_byte_enable,
	input  logic  [8:0] lookup_line,
	output logic        lookup_valid,
	output logic [14:0] lookup_record,
	output logic [15:0] lookup_data
);

// Raster positions are programmed on even lines, and each scroll word is
// held for the corresponding pair of output lines.
(* ramstyle = "MLAB" *) logic [14:0] record_bank0 [0:115];
(* ramstyle = "MLAB" *) logic [14:0] record_bank1 [0:115];
(* ramstyle = "MLAB" *) logic [15:0] data_bank0 [0:115];
(* ramstyle = "MLAB" *) logic [15:0] data_bank1 [0:115];
logic [115:0] valid_bank0;
logic [115:0] valid_bank1;
logic write_bank;
logic read_bank;
wire [6:0] write_index = raster_position[7:1];
wire [6:0] read_index = lookup_line[7:1];

// Packed descriptors are four 16-bit words.  Only word 2 is the floating
// tilemap X-scroll/page word changed by a raster handler.
wire capture_write = capture_enable && write
	&& (write_address[1:0] == 2'd2)
	&& (write_byte_enable == 2'b11)
	&& !raster_position[0] && (raster_position < VISIBLE_LINES);

always_ff @(posedge clk) begin
	if (reset) begin
		valid_bank0 <= 116'd0;
		valid_bank1 <= 116'd0;
		write_bank <= 1'b0;
		read_bank <= 1'b1;
	end
	else begin
		if (capture_write) begin
			if (!write_bank) begin
				record_bank0[write_index] <= write_address[16:2];
				data_bank0[write_index] <= write_data;
				valid_bank0[write_index] <= 1'b1;
			end
			else begin
				record_bank1[write_index] <= write_address[16:2];
				data_bank1[write_index] <= write_data;
				valid_bank1[write_index] <= 1'b1;
			end
		end

		// Freeze the just-completed history at the start of vertical blank.
		// The other bank is then collected without racing the video scanner.
		if (ce_pix && (h_count == 9'd0) && (v_count == VISIBLE_LINES)) begin
			read_bank <= write_bank;
			write_bank <= ~write_bank;
			if (write_bank)
				valid_bank0 <= 116'd0;
			else
				valid_bank1 <= 116'd0;
		end
	end
end

always_comb begin
	lookup_valid = 1'b0;
	lookup_record = 15'd0;
	lookup_data = 16'd0;
	if (capture_enable && (lookup_line < VISIBLE_LINES)) begin
		if (!read_bank) begin
			lookup_valid = valid_bank0[read_index];
			lookup_record = record_bank0[read_index];
			lookup_data = data_bank0[read_index];
		end
		else begin
			lookup_valid = valid_bank1[read_index];
			lookup_record = record_bank1[read_index];
			lookup_data = data_bank1[read_index];
		end
	end
end

endmodule
