// Completed-video CRT geometry boundary. The native raster uses active-low
// sync; normalize once here so both geometry stages and the MiSTer mixer see
// positive pulses, including the geometry-disabled bypass path.
// OpenAI Codex and kandowontu; SPDX-License-Identifier: GPL-3.0-or-later
module gd_crt_geometry (
	input wire clk_sys, reset, ce_pix,
	input wire hsync_n, vsync_n, hblank, vblank,
	input wire [7:0] red, green, blue,
	input wire crt_geometry, tube_mode,
	input wire signed [4:0] crt_hsize,
	input wire signed [8:0] crt_hshift,
	input wire signed [5:0] crt_vshift, crt_vsize,
	output wire video_ce, video_hsync, video_vsync,
	output wire video_hblank, video_vblank,
	output wire [7:0] video_red, video_green, video_blue
);
wire hsync = ~hsync_n;
wire vsync = ~vsync_n;

wire [7:0] crt_vz_red;
wire [7:0] crt_vz_green;
wire [7:0] crt_vz_blue;
wire crt_vz_hsync;
wire crt_vz_vsync;
wire crt_vz_de;
wire crt_vz_vblank;
wire crt_vz_ce;

// PVM mode changes line cadence while preserving unique source lines.
// Cabinet mode keeps native sync and simulates tube geometry photometrically.
crt_vsize #(.RING_LINES(22), .LINE_PX(384)) crt_vertical
(
	.clk(clk_sys), .pxl_cen(ce_pix), .active(crt_geometry),
	.tube_mode(tube_mode), .vsize(crt_vsize),
	.r_in(red), .g_in(green), .b_in(blue),
	.hs_in(hsync), .vs_in(vsync), .de_in(~(hblank | vblank)),
	.vb_in(vblank), .r_out(crt_vz_red), .g_out(crt_vz_green),
	.b_out(crt_vz_blue), .hs_out(crt_vz_hsync),
	.vs_out(crt_vz_vsync), .de_out(crt_vz_de),
	.vb_out(crt_vz_vblank), .ce_out(crt_vz_ce)
);

wire crt_hs_reference;
logic crt_hs_reference_d;
logic [7:0] crt_read_accumulator;
wire crt_hs_reference_rise = crt_hs_reference
	&& !crt_hs_reference_d;
// Native pixels arrive every eight clk_sys cycles. Quarter-clock arithmetic
// gives one signed H-size step roughly 3.1 percent of the native pixel period.
wire [7:0] crt_read_period = 8'd32
	+ {{3{crt_hsize[4]}}, crt_hsize};
wire [8:0] crt_read_sum = {1'b0, crt_read_accumulator} + 9'd4;
wire crt_read_tick = (crt_read_sum >= {1'b0, crt_read_period});

always_ff @(posedge clk_sys) begin
	crt_hs_reference_d <= crt_hs_reference;
	if (reset || crt_hs_reference_rise)
		crt_read_accumulator <= 8'd0;
	else if (crt_read_tick)
		crt_read_accumulator <= crt_read_sum[7:0] - crt_read_period;
	else
		crt_read_accumulator <= crt_read_sum[7:0];
end

wire [7:0] crt_out_red;
wire [7:0] crt_out_green;
wire [7:0] crt_out_blue;
wire crt_out_hsync;
wire crt_out_vsync;
wire crt_out_hblank;
wire crt_out_vblank;

crt_adjust #(
	.VTOTAL(256), .HTOTAL(512), .HPOS_MODE(1)
) crt_horizontal (
	.clk(clk_sys), .pxl_cen(crt_vz_ce), .pxl2_cen(crt_read_tick),
	.active(crt_geometry), .hsize(crt_hsize), .hoffset(crt_hshift),
	.voffset(crt_vshift), .r_in(crt_vz_red), .g_in(crt_vz_green),
	.b_in(crt_vz_blue), .hs_in(crt_vz_hsync), .vs_in(crt_vz_vsync),
	.hb_in(~crt_vz_de), .vb_in(crt_vz_vblank), .r_out(crt_out_red),
	.g_out(crt_out_green), .b_out(crt_out_blue),
	.hs_out(crt_out_hsync), .vs_out(crt_out_vsync),
	.hb_out(crt_out_hblank), .vb_out(crt_out_vblank),
	.hs_ref_out(crt_hs_reference)
);

assign video_ce = crt_geometry ? crt_read_tick : ce_pix;
assign video_red = crt_geometry ? crt_out_red : red;
assign video_green = crt_geometry ? crt_out_green : green;
assign video_blue = crt_geometry ? crt_out_blue : blue;
assign video_hsync = crt_geometry ? crt_out_hsync : hsync;
assign video_vsync = crt_geometry ? crt_out_vsync : vsync;
assign video_hblank = crt_geometry ? crt_out_hblank : hblank;
assign video_vblank = crt_geometry ? crt_out_vblank : vblank;

endmodule

