// Conditional one-pixel dither blending for digital displays.
//
// The DX-101 artwork uses A/B/A/B checkerboards as an analogue-CRT color
// blend. Uneven HDMI scaling can turn those single-pixel patterns into broad
// vertical bands. Strict mode requires a seven-pixel A/B run before blending,
// avoiding the false positives that a three-pixel detector creates in normal
// sprite detail. Strong mode retains the short detector for comparison.
// SPDX-License-Identifier: GPL-3.0-or-later

module gd_dither_blend
(
	input  logic        clk,
	input  logic        reset,
	input  logic        ce_pix,
	input  logic  [1:0] mode,
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
logic [23:0] previous_three_pixel;
logic [23:0] previous_four_pixel;
logic [23:0] previous_five_pixel;
logic [23:0] previous_six_pixel;
logic  [2:0] valid_count;
wire [23:0] current_pixel = {red_in, green_in, blue_in};
wire alternating_short = (valid_count >= 3'd2)
	&& (current_pixel == previous_two_pixel)
	&& (current_pixel != previous_pixel);
wire alternating_long = (valid_count >= 3'd6)
	&& (current_pixel == previous_two_pixel)
	&& (current_pixel == previous_four_pixel)
	&& (current_pixel == previous_six_pixel)
	&& (previous_pixel == previous_three_pixel)
	&& (previous_pixel == previous_five_pixel)
	&& (current_pixel != previous_pixel);
wire alternating = !hblank && !vblank
	&& (((mode == 2'd1) && alternating_long)
	    || ((mode == 2'd2) && alternating_short));

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
		previous_three_pixel <= 24'd0;
		previous_four_pixel <= 24'd0;
		previous_five_pixel <= 24'd0;
		previous_six_pixel <= 24'd0;
		valid_count <= 3'd0;
	end
	else if (ce_pix) begin
		previous_six_pixel <= previous_five_pixel;
		previous_five_pixel <= previous_four_pixel;
		previous_four_pixel <= previous_three_pixel;
		previous_three_pixel <= previous_two_pixel;
		previous_two_pixel <= previous_pixel;
		previous_pixel <= current_pixel;
		if (valid_count != 3'd7)
			valid_count <= valid_count + 3'd1;
	end
end

endmodule
