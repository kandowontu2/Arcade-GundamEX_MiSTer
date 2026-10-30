`timescale 1ns/1ps
module tb_gd_crt_geometry;
logic clk_sys=0; always #5 clk_sys=~clk_sys;
logic reset=1;
wire ce_pix, hsync_n, vsync_n, hblank, vblank, frame_tick;
wire [8:0] h_count, v_count;
wire [7:0] red=8'ha5, green=8'h6b, blue=8'hd6;
logic crt_geometry=0, tube_mode=0;
logic signed [4:0] crt_hsize=0;
logic signed [8:0] crt_hshift=0;
logic signed [5:0] crt_vshift=0, crt_vsize=0;
wire video_ce, video_hsync, video_vsync, video_hblank, video_vblank;
wire [7:0] video_red, video_green, video_blue;

gd_video_timing raster (
    .clk(clk_sys), .reset, .ce_pix, .h_count, .v_count, .hblank, .vblank,
    .hsync(hsync_n), .vsync(vsync_n), .frame_tick
);
gd_crt_geometry dut (.*);
localparam integer FRAME_CLOCKS=512*256*8;
integer visible_pixels=0, unknown_pixels=0, lit_pixels=0;
integer hs_high=0, vs_high=0;
integer mode_index, size_index;

always @(negedge clk_sys) begin
    if (!reset) begin
        if (!crt_geometry) begin
            if ({video_ce,video_red,video_green,video_blue,video_hblank,video_vblank}
                !== {ce_pix,red,green,blue,hblank,vblank})
                $fatal(1,"Geometry bypass changed pixels/CE/blanking");
            if ({video_hsync,video_vsync} !== {~hsync_n,~vsync_n})
                $fatal(1,"Bypass sync was not normalized to active high");
        end
        if (video_hsync) hs_high=hs_high+1;
        if (video_vsync) vs_high=vs_high+1;
        if (video_ce && !video_hblank && !video_vblank) begin
            visible_pixels=visible_pixels+1;
            // Use reduction/case equality for simulator-portable X/Z detection.
            if ((^{video_red,video_green,video_blue}) === 1'bx) unknown_pixels=unknown_pixels+1;
            else if ({video_red,video_green,video_blue} != 24'd0) lit_pixels=lit_pixels+1;
        end
    end
end

task frame;
    repeat(FRAME_CLOCKS) @(posedge clk_sys);
    @(posedge clk_sys); // Do not race the falling-edge statistics monitor.
endtask

task check_picture;
    begin
        visible_pixels=0; unknown_pixels=0; lit_pixels=0; hs_high=0; vs_high=0;
        frame();
        if (visible_pixels < 384*150 || lit_pixels < 384*150 || unknown_pixels != 0)
            $fatal(1,"CRT picture lost mode=%0d size=%0d visible=%0d lit=%0d unknown=%0d",
                tube_mode,crt_vsize,visible_pixels,lit_pixels,unknown_pixels);
        if (hs_high == 0 || hs_high > FRAME_CLOCKS/3 || vs_high == 0 || vs_high > FRAME_CLOCKS/16)
            $fatal(1,"Wrong output sync duty mode=%0d size=%0d hs=%0d vs=%0d",
                tube_mode,crt_vsize,hs_high,vs_high);
    end
endtask

initial begin
    repeat(8) @(posedge clk_sys);
    @(posedge clk_sys); #1; reset=0;
    // Both sizing engines measure continuously, even while bypassed.
    repeat(4) frame();
    if (dut.crt_vertical.vs_lines !== 4 || dut.crt_vertical.hs_width < 350
        || dut.crt_vertical.hs_width > 400 || !dut.crt_vertical.meas_ok)
        $fatal(1,"Measured inactive intervals as sync: vs=%0d hs=%0d valid=%0d",
            dut.crt_vertical.vs_lines,dut.crt_vertical.hs_width,dut.crt_vertical.meas_ok);
    $display("CRT native measurements: HSync=%0d clocks VSync=%0d lines",
        dut.crt_vertical.hs_width,dut.crt_vertical.vs_lines);
    check_picture();
    for (mode_index=0;mode_index<2;mode_index=mode_index+1) begin
        for (size_index=0;size_index<3;size_index=size_index+1) begin
            @(posedge clk_sys); #1;
            crt_geometry=1; tube_mode=mode_index;
            case(size_index)
                0: crt_vsize=0;
                1: crt_vsize=9;
                2: crt_vsize=-9;
            endcase
            frame();
            check_picture();
            $display("CRT case mode=%0d size=%0d visible=%0d lit=%0d",tube_mode,crt_vsize,visible_pixels,lit_pixels);
        end
    end
    @(posedge clk_sys); #1; crt_geometry=0;
    check_picture();
    $display("PASS gd_crt_geometry real 512x256 raster, positive sync, bypass/PVM/Cabinet zero/enlarge/shrink");
    $finish;
end
initial begin
    #220000000;
    $fatal(1,"CRT geometry timeout");
end
endmodule
