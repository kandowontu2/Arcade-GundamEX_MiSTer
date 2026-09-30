//============================================================================
//  MRA cheat engine for Gundam EX Revue / MiSTer FPGA
//
//  Adapted from Irem M92's cheatengine_32_16 and MRA code receiver:
//  Copyright (C) 2023 Martin Donlon
//  Based on cheat code handling by Kitrinx, Apr 21, 2019
//  68000 big-endian adaptation Copyright (C) 2026 OpenAI Codex
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for
//  more details. You should have received a copy of the GNU General Public
//  License along with this program. If not, see <https://www.gnu.org/licenses/>.
//============================================================================

// MiSTer Main sends the complete selected set through ioctl index 255 each
// time a cheat is toggled. All four 32-bit fields arrive most-significant byte
// first: Flags, Address, Compare, Data. An empty set is a two-byte transfer.
module gd_mra_cheat_loader
(
	input  logic         clk,
	input  logic         reset, // Cold reset or new ROM; never a warm reset.
	input  logic         ioctl_download,
	input  logic [15:0]  ioctl_index,
	input  logic         ioctl_wr,
	input  logic [26:0]  ioctl_addr,
	input  logic  [7:0]  ioctl_data,
	output logic [128:0] code,
	output logic         code_reset,
	output logic         enable
);

wire code_download = ioctl_download && ioctl_index == 16'd255;
logic [26:0] next_addr;
logic receiving;

assign code_reset = reset
	|| (code_download && ioctl_wr && ioctl_addr == 27'd0);
assign enable = !reset && !code_download;

always_ff @(posedge clk) begin
	code[128] <= 1'b0;
	if (reset) begin
		code <= 129'd0;
		next_addr <= 27'd0;
		receiving <= 1'b0;
	end
	else if (!code_download) begin
		next_addr <= 27'd0;
		receiving <= 1'b0;
	end
	else if (ioctl_wr) begin
		if (ioctl_addr == 27'd0) begin
			code[127:0] <= {120'd0, ioctl_data};
			next_addr <= 27'd1;
			receiving <= 1'b1;
		end
		else if (receiving && ioctl_addr == next_addr) begin
			code[127:0] <= {code[119:0], ioctl_data};
			code[128] <= &ioctl_addr[3:0];
			next_addr <= next_addr + 27'd1;
		end
		else receiving <= 1'b0; // Never commit a missing/reordered packet.
	end
end

endmodule

// Same Flags encoding as M92:
//   bit 0: compare, bits 6:4: size (1/2/4), bits 9:8: replace/OR/AND (0/1/2).
// Addresses are CPU byte addresses. The 68000 puts an even byte on [15:8]
// and an odd byte on [7:0], unlike the little-endian M92 processor.
// A longword override spans two CPU reads; longword compare is unsupported
// because a single read cannot observe all four original bytes.
module gd_mra_cheat_engine
#(
	parameter ADDR_WIDTH = 24,
	parameter MAX_CODES = 8
)
(
	input  logic                  clk,
	input  logic                  reset,
	input  logic                  enable,
	output logic                  available,
	input  logic [128:0]          code,
	input  logic [ADDR_WIDTH-1:0] addr_in,
	input  logic [15:0]           data_in,
	output logic [15:0]           data_out
);

localparam INDEX_SIZE = $clog2(MAX_CODES + 1);
logic [INDEX_SIZE-1:0] next_index;
logic code_change;
logic [1:0] method [0:MAX_CODES-1];
logic [3:0] value_mask [0:MAX_CODES-1];
logic [31:0] compare_mask [0:MAX_CODES-1];
logic [31:0] value [0:MAX_CODES-1];
logic [31:0] compare_value [0:MAX_CODES-1];
logic [ADDR_WIDTH-1:0] address [0:MAX_CODES-1];

wire [31:0] code_address = code[95:64];
wire [31:0] code_compare = code[63:32];
wire [31:0] code_data = code[31:0];
wire code_comp = code[96];
wire [2:0] code_width = code[102:100];
wire [1:0] code_method = code[105:104];

logic [3:0] load_mask;
logic [31:0] load_value;
logic [31:0] load_compare;
always_comb begin
	load_mask = 4'd0;
	load_value = 32'd0;
	load_compare = 32'd0;
	case ({code_address[1:0], code_width})
		5'b00_001: begin load_mask = 4'b1000; load_value = {code_data[7:0], 24'd0}; load_compare = {code_compare[7:0], 24'd0}; end
		5'b01_001: begin load_mask = 4'b0100; load_value = {8'd0, code_data[7:0], 16'd0}; load_compare = {8'd0, code_compare[7:0], 16'd0}; end
		5'b10_001: begin load_mask = 4'b0010; load_value = {16'd0, code_data[7:0], 8'd0}; load_compare = {16'd0, code_compare[7:0], 8'd0}; end
		5'b11_001: begin load_mask = 4'b0001; load_value = {24'd0, code_data[7:0]}; load_compare = {24'd0, code_compare[7:0]}; end
		5'b00_010: begin load_mask = 4'b1100; load_value = {code_data[15:0], 16'd0}; load_compare = {code_compare[15:0], 16'd0}; end
		5'b10_010: begin load_mask = 4'b0011; load_value = {16'd0, code_data[15:0]}; load_compare = {16'd0, code_compare[15:0]}; end
		5'b00_100: begin load_mask = code_comp ? 4'd0 : 4'b1111; load_value = code_data; end
		default: begin end
	endcase
	// Reject unsupported flags and addresses instead of aliasing a bad code
	// into the 24-bit CPU address space.
	if ((code[127:96] & ~32'h00000371) != 32'd0
	    || code_method == 2'd3 || (code_address >> ADDR_WIDTH) != 32'd0)
		load_mask = 4'd0;
end

assign available = |next_index;
integer n;
always_ff @(posedge clk) begin
	if (reset) begin
		next_index <= '0;
		code_change <= 1'b0;
		for (n = 0; n < MAX_CODES; n = n + 1) value_mask[n] <= 4'd0;
	end
	else begin
		code_change <= code[128];
		if (code[128] && !code_change && next_index < MAX_CODES) begin
			value_mask[next_index] <= load_mask;
			compare_mask[next_index] <= code_comp
				? {{8{load_mask[3]}}, {8{load_mask[2]}}, {8{load_mask[1]}}, {8{load_mask[0]}}}
				: 32'd0;
			address[next_index] <= code_address[ADDR_WIDTH-1:0];
			value[next_index] <= load_value;
			compare_value[next_index] <= load_compare;
			method[next_index] <= code_method;
			next_index <= next_index + 1'b1;
		end
	end
end

integer x;
integer p;
logic [31:0] original_word;
logic [31:0] overridden_word;
always_comb begin
	x = 0;
	p = 0;
	original_word = addr_in[1] ? {16'd0, data_in} : {data_in, 16'd0};
	overridden_word = original_word;
	if (enable) begin
		for (x = 0; x < MAX_CODES; x = x + 1) begin
			if (address[x][ADDR_WIDTH-1:2] == addr_in[ADDR_WIDTH-1:2]
			    && !((compare_value[x] ^ original_word) & compare_mask[x])) begin
				for (p = 0; p < 4; p = p + 1) begin
					if (value_mask[x][p]) begin
						case (method[x])
							2'd1: overridden_word[8*p +: 8] = value[x][8*p +: 8] | original_word[8*p +: 8];
							2'd2: overridden_word[8*p +: 8] = value[x][8*p +: 8] & original_word[8*p +: 8];
							default: overridden_word[8*p +: 8] = value[x][8*p +: 8];
						endcase
					end
				end
			end
		end
	end
	data_out = addr_in[1] ? overridden_word[15:0] : overridden_word[31:16];
end

endmodule
