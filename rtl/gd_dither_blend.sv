// Conditional one-pixel dither blending for digital displays.
//
// The DX-101 artwork uses A/B/A/B checkerboards as an analogue-CRT color
// blend. Uneven HDMI scaling can turn those single-pixel patterns into broad
// vertical bands. Average only a confirmed horizontal A/B/A run, leaving
// solid colors, edges, text and ordinary sprite detail untouched.
// SPDX-License-Identifier: GPL-3.0-or-later

module gd_dither_blend
(
	input  logic        clk,
	input  logic        reset,
	input  logic        ce_pix,
	input  logic        enable,
	input  logic        hblank,
	input  logic        vblank,
	input  logic  [7:0] red_in,
	input  logic  [7:0] green_in,
	input  logic  [7:0] blue_in,
	output logic  [7:0] red_out,
	output logic  [7:0] green_out,
	output logic  [7:0] blue_out
);

logic [23:0] previous_pixel;
logic [23:0] previous_two_pixel;
logic previous_valid;
logic previous_two_valid;
wire [23:0] current_pixel = {red_in, green_in, blue_in};
wire alternating = enable && !hblank && !vblank && previous_two_valid
	&& (current_pixel == previous_two_pixel)
	&& (current_pixel != previous_pixel);

function automatic [7:0] average_channel;
	input [7:0] first;
	input [7:0] second;
	begin
		average_channel = ({1'b0, first} + {1'b0, second} + 9'd1) >> 1;
	end
endfunction

always_comb begin
	red_out = red_in;
	green_out = green_in;
	blue_out = blue_in;
	if (alternating) begin
		red_out = average_channel(red_in, previous_pixel[23:16]);
		green_out = average_channel(green_in, previous_pixel[15:8]);
		blue_out = average_channel(blue_in, previous_pixel[7:0]);
	end
end

always_ff @(posedge clk) begin
	if (reset || (ce_pix && (hblank || vblank))) begin
		previous_pixel <= 24'd0;
		previous_two_pixel <= 24'd0;
		previous_valid <= 1'b0;
		previous_two_valid <= 1'b0;
	end
	else if (ce_pix) begin
		previous_two_pixel <= previous_pixel;
		previous_pixel <= current_pixel;
		previous_two_valid <= previous_valid;
		previous_valid <= 1'b1;
	end
end

endmodule
