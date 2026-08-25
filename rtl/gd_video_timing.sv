// Gundam EX Revue raster timing. The game exposes a 384x224 picture; use the
// 512x256 controller raster documented by its driver at 59.6 Hz.
// SPDX-License-Identifier: GPL-3.0-or-later

module gd_video_timing
(
	input  logic       clk,
	input  logic       reset,
	output logic       ce_pix,
	output logic [8:0] h_count,
	output logic [8:0] v_count,
	output logic       hblank,
	output logic       vblank,
	output logic       hsync,
	output logic       vsync,
	output logic       frame_tick
);

// A divide-by-eight pixel enable gives 7.8125 MHz from clk_sys. Together with
// 512x256 totals this is 59.6046 Hz and retains 4096 renderer clocks per line.
logic [2:0] pixel_divider;
assign ce_pix = (pixel_divider == 3'd0);

always_ff @(posedge clk) begin
	frame_tick <= 1'b0;
	if (reset) begin
		pixel_divider <= 3'd0;
		h_count <= 9'd0;
		v_count <= 9'd0;
	end
	else begin
		if (pixel_divider == 3'd7)
			pixel_divider <= 3'd0;
		else
			pixel_divider <= pixel_divider + 3'd1;
		if (ce_pix) begin
			if (h_count == 9'd511) begin
				h_count <= 9'd0;
				if (v_count == 9'd255) begin
					v_count <= 9'd0;
					frame_tick <= 1'b1;
				end
				else
					v_count <= v_count + 9'd1;
			end
			else
				h_count <= h_count + 9'd1;
		end
	end
end

always_comb begin
	hblank = (h_count >= 9'd384);
	vblank = (v_count >= 9'd224);
	hsync  = !((h_count >= 9'd416) && (h_count < 9'd464));
	vsync  = !((v_count >= 9'd240) && (v_count < 9'd244));
end

endmodule
