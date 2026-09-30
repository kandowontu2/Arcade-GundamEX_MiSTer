//============================================================================
//  Copyright (C) 2026 Martin Donlon
//  Gundam EX Revue adaptation Copyright (C) 2026 OpenAI Codex
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
//  GNU General Public License for more details.
//
//  Adapted from the MiSTer IGS PGM/F2 DDR ROM loader adaptor. MiSTer Main can
//  stage an MRA image directly at physical DDR address 0x30000000. If no
//  ordinary ioctl writes were observed, this module reads that image back and
//  presents the same byte stream to the game-specific loader. Older Main
//  versions continue to use the ordinary ioctl pass-through path.
//============================================================================

module gd_ddr_rom_loader_adaptor
#(
	parameter logic [28:0] DDR_WORD_BASE = 29'h06000000
)
(
	input  logic        clk,
	input  logic        reset,

	input  logic        ioctl_download,
	input  logic [26:0] ioctl_addr,
	input  logic        ioctl_wr,
	input  logic  [7:0] ioctl_data,
	output logic        ioctl_wait,

	output logic        busy,
	input  logic        data_wait,
	output logic        data_strobe,
	output logic [26:0] data_addr,
	output logic  [7:0] data,

	output logic        ddr_acquire,
	output logic [28:0] ddr_addr,
	output logic        ddr_read,
	input  logic [63:0] ddr_rdata,
	input  logic        ddr_rdata_ready,
	input  logic        ddr_busy
);

typedef enum logic [1:0] {
	IDLE,
	DDR_READ,
	DDR_WAIT,
	OUTPUT_DATA
} state_t;

state_t state;
logic previous_download;
logic write_detected;
logic [26:0] length;
logic [26:0] offset;
logic [63:0] buffer;
logic [7:0] replay_byte;
logic [26:0] replay_addr;
logic replay_strobe;

always_comb begin
	if (state == IDLE) begin
		ioctl_wait = data_wait;
		data_strobe = ioctl_download && ioctl_wr;
		data_addr = ioctl_addr;
		data = ioctl_data;
		// Keep the loader continuously in its download reset state across
		// the HPS falling edge and the first replay state transition.
		busy = ioctl_download || (previous_download && !write_detected);
	end
	else begin
		// The HPS-side transfer has already ended during DDR replay, so it
		// must never be held waiting for the internal reconstruction pass.
		ioctl_wait = 1'b0;
		data_strobe = replay_strobe;
		data_addr = replay_addr;
		data = replay_byte;
		busy = 1'b1;
	end
end

always_ff @(posedge clk) begin
	previous_download <= ioctl_download;
	replay_strobe <= 1'b0;

	if (reset) begin
		state <= IDLE;
		previous_download <= 1'b0;
		write_detected <= 1'b0;
		length <= 27'd0;
		offset <= 27'd0;
		buffer <= 64'd0;
		replay_byte <= 8'd0;
		replay_addr <= 27'd0;
		ddr_acquire <= 1'b0;
		ddr_addr <= DDR_WORD_BASE;
		ddr_read <= 1'b0;
	end
	else begin
		if (ioctl_download && !previous_download)
			write_detected <= 1'b0;
		if (ioctl_download && ioctl_wr)
			write_detected <= 1'b1;

		case (state)
			IDLE: begin
				ddr_acquire <= 1'b0;
				ddr_read <= 1'b0;
				// With address="0x30000000", MiSTer Main writes the image
				// directly to DDR and only reports its final byte length over
				// ioctl. A normal byte-stream transfer is left untouched.
				if (previous_download && !ioctl_download
				    && !write_detected && (ioctl_addr != 27'd0)) begin
					length <= ioctl_addr;
					offset <= 27'd0;
					state <= DDR_READ;
				end
			end

			DDR_READ: begin
				ddr_acquire <= 1'b1;
				if (!ddr_busy) begin
					ddr_addr <= DDR_WORD_BASE + {5'd0, offset[26:3]};
					ddr_read <= 1'b1;
					state <= DDR_WAIT;
				end
			end

			DDR_WAIT: begin
				ddr_acquire <= 1'b1;
				if (!ddr_busy) ddr_read <= 1'b0;
				if (ddr_rdata_ready) begin
					buffer <= ddr_rdata;
					ddr_acquire <= 1'b0;
					ddr_read <= 1'b0;
					state <= OUTPUT_DATA;
				end
			end

			OUTPUT_DATA: begin
				ddr_acquire <= 1'b0;
				if (!data_wait && !replay_strobe) begin
					if (offset == length) begin
						state <= IDLE;
					end
					else begin
						replay_addr <= offset;
						replay_byte <= buffer[(offset[2:0] * 8) +: 8];
						replay_strobe <= 1'b1;
						offset <= offset + 27'd1;
						if (&offset[2:0]
						    && ((offset + 27'd1) < length))
							state <= DDR_READ;
					end
				end
			end

			default: state <= IDLE;
		endcase
	end
end

endmodule
