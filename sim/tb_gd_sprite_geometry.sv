`timescale 1ns/1ps
module tb_gd_sprite_geometry;
logic clk=0; always #5 clk=~clk;
logic reset=1;
logic [26:0] video_y_offset=0, video_y_zoom=0;
logic [15:0] th0,th1,th2,th3,ts0,ts1;
logic [8:0] test_line;
integer sy,first_line,height,width,used_line,last_line,normalized_line;
integer seed=32'h3ad02710;
integer n, accepted=0, rejected=0;
logic expected_visible;
gd_dx101_video #(.H_TOTAL(512),.V_TOTAL(256),.H_VISIBLE(384),.V_VISIBLE(224)) dut (
    .clk,.reset,.render_pause(1'b0),.ce_pix(1'b0),.h_count(9'd0),.v_count(9'd0),
    .hblank(1'b0),.vblank(1'b0),.raster_active(1'b0),.rowscroll_override_valid(1'b0),
    .rowscroll_override_record(15'd0),.rowscroll_override_data(16'd0),
    .video_control(16'd0),.rotate_180(1'b0),.video_x_offset(27'd0),.video_x_zoom(27'd0),
    .video_y_offset,.video_y_zoom,.sprite_q(64'd0),.palette_q(16'd0),
    .gfx_dout(64'd0),.gfx_ack(1'b0)
);

// Independent transcription of the pre-refactor geometry, not the new helpers.
// Include the old floating intermediate wrap so its removal is regression-tested.
task legacy_geometry;
    begin
        used_line=test_line;
        if (!th0[14] && video_y_zoom[26])
            used_line=(test_line+((27'h7ffffff-video_y_offset)>>16)) & 2047;
        sy=ts1 & 511;
        if (sy & 256) sy=sy-512;
        if (th0[14]) sy=sy-144;
        if (th3[15]) begin
            sy=sy & 511;
            if (sy & 256) sy=sy-512;
            height=((((th0[12] ? th2 : ts1) & 16'hfc00)>>10)+1)*16;
            width=((th0[12] ? th1 : ts0) & 16'hfc00)>>10;
        end else begin
            height=(1<<(((th0[12] ? th2 : ts1) & 16'h0c00)>>10))*8;
            width=1<<(((th0[12] ? th1 : ts0) & 16'h0c00)>>10);
        end
        first_line=(sy+(th2 & 511)) & 511;
        if (first_line & 256) first_line=first_line-512;
        last_line=(first_line+height-1) & 511;
        if (last_line & 256) last_line=last_line-512;
        normalized_line=used_line & 511;
        if (normalized_line & 256) normalized_line=normalized_line-512;
        expected_visible=(last_line>=first_line)
            ? ((normalized_line>=first_line) && (normalized_line<=last_line))
            : ((normalized_line>=first_line) || (normalized_line<=last_line));
        if (th3[15] && width==0) expected_visible=0;
    end
endtask

initial begin
    repeat(3) @(posedge clk);
    @(negedge clk); reset=0;
    for(n=0;n<8192;n=n+1) begin
        @(negedge clk);
        th0=$random(seed); th1=$random(seed); th2=$random(seed);
        th3=$random(seed); ts0=$random(seed); ts1=$random(seed);
        // Exercise fixed/global/floating combinations deterministically.
        th0[14]=n[0]; th0[12]=n[1]; th3[15]=n[2];
        test_line=$random(seed); video_y_offset=$random(seed); video_y_zoom=$random(seed);
        if (n<4096) begin
            test_line=n[11:3];
            ts1[8:0]=9'h1f9; th2[8:0]=9'h039;
        end
        legacy_geometry();
        if (dut.sprite_intersects_line(th0,th1,th2,th3,ts0,ts1,test_line,video_y_offset,video_y_zoom)
            !== expected_visible) $fatal(1,"Prefilter differs from legacy vector %0d",n);
        if (dut.sprite_width_tiles(th0[12],th3[15],th1,ts0) !== width)
            $fatal(1,"Width helper differs from legacy vector %0d",n);
        // Deposit a decoded record at the existing processing stage; this
        // checks the drawing admission path, not just helper return values.
        dut.h0=th0; dut.h1=th1; dut.h2=th2; dut.h3=th3;
        dut.s0=ts0; dut.s1=ts1; dut.s2=0; dut.s3=0;
        dut.use_global_size=th0[12]; dut.target_line=test_line;
        dut.state=dut.R_SPRITE_PROCESS;
        @(posedge clk); #1;
        if (dut.calc_used_line !== used_line || dut.calc_firstline !== first_line
            || dut.calc_span_height !== height)
            $fatal(1,"Drawing geometry differs from legacy vector %0d",n);
        if (expected_visible) begin
            accepted=accepted+1;
            if (th3[15] ? (dut.calc_width !== width) : (dut.calc_size_x !== width))
                $fatal(1,"Drawing width differs from legacy vector %0d",n);
            if (th3[15] ? (dut.state !== dut.R_FLOAT_SELECT) : (dut.state !== dut.R_NORMAL_PREP))
                $fatal(1,"Drawing discarded prefilter-accepted vector %0d",n);
        end else begin
            rejected=rejected+1;
            if (dut.state !== dut.R_NEXT_SPRITE)
                $fatal(1,"Drawing accepted prefilter-rejected vector %0d",n);
        end
    end
    if (accepted==0 || rejected==0) $fatal(1,"Missing geometry coverage");
    $display("PASS gd_sprite_geometry 8192 legacy/prefilter/drawing comparisons accepted=%0d rejected=%0d",accepted,rejected);
    $finish;
end
initial begin #1000000; $fatal(1,"Sprite geometry timeout"); end
endmodule
