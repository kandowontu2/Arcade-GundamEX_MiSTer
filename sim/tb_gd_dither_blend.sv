`timescale 1ns/1ps

module tb_gd_dither_blend;
logic clk = 1'b0;
always #5 clk = ~clk;
logic reset = 1'b1;
logic ce_pix = 1'b1;
logic [1:0] mode = 2'd0;
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

	// Safe/default mode leaves a short A/B/A detail untouched.
	present_pixel(24'h204060, 24'h204060);
	present_pixel(24'h80a0c0, 24'h80a0c0);
	present_pixel(24'h204060, 24'h204060);

	// It blends only after a seven-pixel alternating run is confirmed.
	present_pixel(24'h80a0c0, 24'h80a0c0);
	present_pixel(24'h204060, 24'h204060);
	present_pixel(24'h80a0c0, 24'h80a0c0);
	present_pixel(24'h204060, 24'h507090);
	present_pixel(24'h80a0c0, 24'h507090);

	// Raw preserves the source exactly even inside a confirmed run.
	mode = 2'd1;
	present_pixel(24'h204060, 24'h204060);

	// Blanking clears history so the next active pixels cannot blend with the
	// preceding line.
	mode = 2'd0;
	hblank = 1'b1;
	present_pixel(24'h000000, 24'h000000);
	hblank = 1'b0;
	present_pixel(24'h204060, 24'h204060);
	present_pixel(24'h80a0c0, 24'h80a0c0);
	present_pixel(24'h204060, 24'h204060);

	// Strong mode deliberately retains the old three-pixel behavior.
	mode = 2'd2;
	hblank = 1'b1;
	present_pixel(24'h000000, 24'h000000);
	hblank = 1'b0;
	present_pixel(24'h204060, 24'h204060);
	present_pixel(24'h80a0c0, 24'h80a0c0);
	present_pixel(24'h204060, 24'h507090);

	$display("PASS gd_dither_blend defaults safe and separates raw/strong modes");
	$finish;
end
endmodule
