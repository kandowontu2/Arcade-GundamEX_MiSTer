`timescale 1ns/1ps

module tb_gd_dither_blend;
logic clk = 1'b0;
always #5 clk = ~clk;
logic reset = 1'b1;
logic ce_pix = 1'b1;
logic enable = 1'b1;
logic hblank = 1'b0;
logic vblank = 1'b0;
logic [7:0] red_in = 8'd0;
logic [7:0] green_in = 8'd0;
logic [7:0] blue_in = 8'd0;
logic [7:0] red_out;
logic [7:0] green_out;
logic [7:0] blue_out;

gd_dither_blend dut(.*);

task automatic present_pixel(
	input [23:0] pixel,
	input [23:0] expected
);
	begin
		@(negedge clk);
		{red_in, green_in, blue_in} = pixel;
		#1;
		if ({red_out, green_out, blue_out} !== expected)
			$fatal(1, "pixel %h produced %h, expected %h",
				pixel, {red_out, green_out, blue_out}, expected);
		@(posedge clk);
	end
endtask

initial begin
	repeat (2) @(posedge clk);
	reset = 1'b0;

	// The third and following pixels in an A/B/A/B checkerboard are blended.
	present_pixel(24'h204060, 24'h204060);
	present_pixel(24'h80a0c0, 24'h80a0c0);
	present_pixel(24'h204060, 24'h507090);
	present_pixel(24'h80a0c0, 24'h507090);

	// Disabling the filter preserves the source exactly.
	enable = 1'b0;
	present_pixel(24'h204060, 24'h204060);

	// Blanking clears history so the next active pixels cannot blend with the
	// preceding line.
	enable = 1'b1;
	hblank = 1'b1;
	present_pixel(24'h000000, 24'h000000);
	hblank = 1'b0;
	present_pixel(24'h204060, 24'h204060);
	present_pixel(24'h80a0c0, 24'h80a0c0);
	present_pixel(24'h204060, 24'h507090);

	$display("PASS gd_dither_blend suppresses A/B/A HDMI alias patterns");
	$finish;
end
endmodule
