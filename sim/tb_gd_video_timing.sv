`timescale 1ns/1ps

module tb_gd_video_timing;
	logic clk = 1'b0;
	logic reset = 1'b1;
	logic ce_pix;
	logic [8:0] h_count;
	logic [8:0] v_count;
	logic hblank;
	logic vblank;
	logic hsync;
	logic vsync;
	logic frame_tick;
	integer clocks_since_pixel;
	integer pixel_count;

	always #5 clk = ~clk;

	gd_video_timing dut
	(
		.clk, .reset, .ce_pix, .h_count, .v_count,
		.hblank, .vblank, .hsync, .vsync, .frame_tick
	);

	initial begin
		clocks_since_pixel = 0;
		pixel_count = 0;
		repeat (3) @(posedge clk);
		reset <= 1'b0;

		while (pixel_count < 512 * 256) begin
			@(posedge clk);
			clocks_since_pixel = clocks_since_pixel + 1;
			if (ce_pix) begin
				if (pixel_count != 0 && clocks_since_pixel != 8) begin
					$display("FAIL pixel interval %0d", clocks_since_pixel);
					$fatal(1);
				end
				clocks_since_pixel = 0;
				pixel_count = pixel_count + 1;
			end
		end

		@(negedge clk);
		if (!frame_tick || h_count != 0 || v_count != 0) begin
			$display("FAIL frame wrap h=%0d v=%0d tick=%0d",
				h_count, v_count, frame_tick);
			$fatal(1);
		end
		$display("PASS gd_video_timing 512x256 Gundam EX raster");
		$finish;
	end

	initial begin
		#12000000;
		$display("FAIL timeout");
		$fatal(1);
	end
endmodule
