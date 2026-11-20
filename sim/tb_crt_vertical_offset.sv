`timescale 1ns/1ps
// Exercise the complete OSD V Offset range at both PVM extremes and native
// timing. A constant-256 negative tap fails the 247/-1 case by nine lines.
module tb_crt_vertical_offset;
reg clk=0; always #5 clk=~clk;
reg [9:0] frame_lines=256;
reg signed [5:0] voffset=0;
integer x=0, y=0;
always @(posedge clk) begin
    if (x==31) begin
        x<=0;
        y<=(y==frame_lines-1) ? 0 : y+1;
    end else x<=x+1;
end
wire vs_out;
crt_adjust #(.VTOTAL(256), .HTOTAL(32), .HPOS_MODE(1)) dut (
    .clk, .pxl_cen(1'b1), .pxl2_cen(1'b1), .active(1'b1),
    .hsize(5'sd0), .hoffset(9'sd0), .voffset, .frame_lines,
    .r_in(8'ha5), .g_in(8'h6b), .b_in(8'hd6),
    .hs_in(x<4), .vs_in(y<4), .hb_in(x>=24), .vb_in(y>=224),
    .vs_out, .hs_out(), .hb_out(), .vb_out(),
    .r_out(), .g_out(), .b_out(), .hs_ref_out()
);
integer total_case, offset_case, n, expected_line, checked=0;
initial begin
    for (total_case=0;total_case<3;total_case=total_case+1) begin
        @(negedge clk);
        case(total_case)
            0: frame_lines=247;
            1: frame_lines=256;
            2: frame_lines=265;
        endcase
        for (offset_case=-8;offset_case<=7;offset_case=offset_case+1) begin
            @(negedge clk); voffset=offset_case;
            // Flush history and any frame-length transition.
            repeat(3*265*32) @(negedge clk);
            while (x!=31 || y!=frame_lines-1) @(negedge clk);
            for(n=0;n<frame_lines;n=n+1) begin
                repeat(32) @(negedge clk);
                expected_line=(y-offset_case+frame_lines)%frame_lines;
                if (vs_out !== (expected_line<4))
                    $fatal(1,"V Offset total=%0d offset=%0d line=%0d vs=%b expected=%b tap=%0d",
                        frame_lines,offset_case,y,vs_out,(expected_line<4),dut.vshift_tap);
                checked=checked+1;
            end
            $display("V Offset total=%0d offset=%0d: correct signed line displacement",frame_lines,offset_case);
        end
    end
    $display("PASS crt_vertical_offset 48 cases, %0d lines; 247-line -1 advances sync one line",checked);
    $finish;
end
initial begin #30000000; $fatal(1,"vertical offset timeout"); end
endmodule
