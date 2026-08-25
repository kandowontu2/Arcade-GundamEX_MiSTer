`timescale 1ns/1ps
module tb_gd_dx101_video;
logic clk=0; always #5 clk=~clk;
logic reset=1;
logic render_pause=0;
logic rotate_180=0;
logic ce_pix=0;
logic [8:0] h_count=0;
logic [8:0] v_count=0;
logic hblank=0;
logic vblank=0;
logic raster_active=1;
logic rowscroll_override_valid=0;
logic [14:0] rowscroll_override_record=0;
logic [15:0] rowscroll_override_data=0;
logic [15:0] video_control=0;
logic [26:0] video_x_offset=0;
logic [26:0] video_x_zoom=27'h0010000;
logic [26:0] video_y_offset=0;
logic [26:0] video_y_zoom=0;
logic [16:0] sprite_address;
logic [63:0] sprite_q=0;
logic [14:0] palette_address;
logic [15:0] palette_q=0;
logic [24:0] gfx_addr;
logic gfx_req;
logic [24:0] gfx_prefetch_addr;
logic gfx_prefetch_valid;
logic [63:0] gfx_dout=0;
logic gfx_ack=0;
logic [7:0] red,green,blue;
logic busy;
logic line_done;
logic [15:0] missed_lines;
logic [8:0] rowscroll_lookup_line;

// Keep the drawing-format test demand-driven. Raster look-ahead has a
// dedicated regression below so its queue cannot race these memory edits.
gd_dx101_video #(.AHEAD_RENDER(1'b0)) dut(.*);
logic [15:0] sprite_memory [0:131071];
logic gfx_req_d=0;

function automatic [14:0] line_buffer0_at(input integer pixel);
	case (pixel & 7)
		0: line_buffer0_at = dut.line_buffer_bank0[pixel >> 3];
		1: line_buffer0_at = dut.line_buffer_bank1[pixel >> 3];
		2: line_buffer0_at = dut.line_buffer_bank2[pixel >> 3];
		3: line_buffer0_at = dut.line_buffer_bank3[pixel >> 3];
		4: line_buffer0_at = dut.line_buffer_bank4[pixel >> 3];
		5: line_buffer0_at = dut.line_buffer_bank5[pixel >> 3];
		6: line_buffer0_at = dut.line_buffer_bank6[pixel >> 3];
		default: line_buffer0_at = dut.line_buffer_bank7[pixel >> 3];
	endcase
endfunction

function automatic [14:0] line_buffer1_at(input integer pixel);
	case (pixel & 7)
		0: line_buffer1_at = dut.line_buffer_bank0[38 + (pixel >> 3)];
		1: line_buffer1_at = dut.line_buffer_bank1[38 + (pixel >> 3)];
		2: line_buffer1_at = dut.line_buffer_bank2[38 + (pixel >> 3)];
		3: line_buffer1_at = dut.line_buffer_bank3[38 + (pixel >> 3)];
		4: line_buffer1_at = dut.line_buffer_bank4[38 + (pixel >> 3)];
		5: line_buffer1_at = dut.line_buffer_bank5[38 + (pixel >> 3)];
		6: line_buffer1_at = dut.line_buffer_bank6[38 + (pixel >> 3)];
		default: line_buffer1_at = dut.line_buffer_bank7[38 + (pixel >> 3)];
	endcase
endfunction

always_ff @(posedge clk) begin
	sprite_q <= {
		sprite_memory[{sprite_address[16:2], 2'b11}],
		sprite_memory[{sprite_address[16:2], 2'b10}],
		sprite_memory[{sprite_address[16:2], 2'b01}],
		sprite_memory[{sprite_address[16:2], 2'b00}]
	};
	gfx_req_d <= gfx_req;
	gfx_ack <= gfx_req_d;
	// Eight planes encode displayed pixel pens 1 through 8.
	gfx_dout <= 64'h0000_0000_1e01_aa66;
	palette_q <= {1'b0,palette_address};
end

integer i;
initial begin
	for(i=0;i<131072;i=i+1) sprite_memory[i]=0;
	// A recorded raster scroll word replaces only the matching packed
	// descriptor's word 2 before it enters the active scanline list.
	force dut.sprite_pointer = 17'h00040;
	force dut.scan_record_q = 64'h1234_5678_9abc_def0;
	rowscroll_override_valid = 1'b1;
	rowscroll_override_record = 15'h0010;
	rowscroll_override_data = 16'h7bf2;
	#1;
	if (dut.scan_s2 !== 16'h7bf2)
		$fatal(1, "matching rowscroll history did not override descriptor");
	rowscroll_override_record = 15'h0011;
	#1;
	if (dut.scan_s2 !== 16'h5678)
		$fatal(1, "rowscroll history changed a different descriptor");
	rowscroll_override_valid = 1'b0;
	release dut.sprite_pointer;
	release dut.scan_record_q;
	// The output prefetch and line scheduler must wrap at the native
	// 410x258 raster, not the old synthetic 512x256 MAME geometry.
	h_count=9'd408; v_count=9'd257; #1;
	if (dut.prefetch_x !== 9'd0 || dut.physical_next_line !== 9'd0)
		$fatal(1,"native raster wrap prefetch=%0d next=%0d",
			dut.prefetch_x,dut.physical_next_line);
	h_count=9'd409; #1;
	if (dut.prefetch_x !== 9'd1)
		$fatal(1,"native prefetch wrap second pixel=%0d",dut.prefetch_x);
	if (!dut.wrapped_span_contains(508,16,-510)
	    || dut.wrapped_span_contains(508,16,-490))
		$fatal(1,"signed 10-bit wrapped span comparison failed");
	// DX-101 vertical displacement wraps at 0x200. This is the multi-header
	// boundary used by the intro pictures and floating backgrounds.
	if (!dut.wrapped_vertical_y_contains(252,16,-252)
	    || dut.wrapped_vertical_y_contains(252,16,-236)
	    || !dut.wrapped_vertical_y_contains(-225,49,287))
		$fatal(1,"signed 9-bit normal-sprite Y comparison failed");
	// Header Y=0x1fa (-6 on the normal-sprite ring) plus local Y=8
	// starts at line 2. A 10-bit interpretation instead places it at -510.
	if (!dut.sprite_intersects_line(16'h8000,16'h0000,16'h01fa,
	        16'h0100,16'h0000,16'h0008,9'd2,27'd0,27'd0)
	    || dut.sprite_intersects_line(16'h8000,16'h0000,16'h01fa,
	        16'h0100,16'h0000,16'h0008,9'd10,27'd0,27'd0))
		$fatal(1,"normal-sprite header Y did not wrap at 0x200");
	// The gameplay background uses 0x1f9 -> 0x039 for consecutive
	// floating-tilemap chunks across the same vertical boundary.
	if (!dut.sprite_intersects_line(16'h0400,16'h0000,16'h0080,
	        16'h8100,16'h5000,16'h0df9,9'd0,
	        27'h77f0000,27'h7ff0000)
	    || dut.sprite_intersects_line(16'h0400,16'h0000,16'h0080,
	        16'h8100,16'h5000,16'h0df9,9'd57,
	        27'h77f0000,27'h7ff0000))
		$fatal(1,"floating background Y did not wrap at 0x200");
	h_count=0; v_count=0;
	// One final list header pointing to one 8x8 normal sprite.
	sprite_memory[17'h01800]=16'h8000;
	sprite_memory[17'h01801]=16'h0000;
	sprite_memory[17'h01802]=16'h0000;
	sprite_memory[17'h01803]=16'h0100;
	sprite_memory[17'h00400]=16'h000a;
	sprite_memory[17'h00401]=16'h0001;
	sprite_memory[17'h00402]=16'h0020;
	sprite_memory[17'h00403]=16'h0000;
	repeat(5) @(posedge clk); reset<=0;
	@(posedge clk); ce_pix<=1; h_count<=0; v_count<=0;
	@(posedge clk); ce_pix<=0; h_count<=1;
	wait(busy);
	wait(!busy && dut.state==dut.R_IDLE);
	@(posedge clk);
	for(i=0;i<8;i=i+1)
		if(line_buffer1_at(10+i) !== (15'h0011+i))
			$fatal(1,"pixel %0d=%h",i,line_buffer1_at(10+i));

	// Replace it with a 16-pixel-wide floating tilemap window. A -16
	// scroll value cancels the controller's documented +0x10 origin.
	sprite_memory[17'h01803]=16'h8100;
	sprite_memory[17'h00400]=16'h040a;
	sprite_memory[17'h00401]=16'h0001;
	sprite_memory[17'h00402]=16'h03f0;
	sprite_memory[17'h00403]=16'h0000;
	sprite_memory[17'h00f80]=16'h0040;
	sprite_memory[17'h00f81]=16'h0001;
	sprite_memory[17'h00f82]=16'h0040;
	sprite_memory[17'h00f83]=16'h0001;
	@(posedge clk); ce_pix<=1; h_count<=0; v_count<=1;
	@(posedge clk); ce_pix<=0; h_count<=1;
	wait(busy);
	wait(!busy && dut.state==dut.R_IDLE);
	@(posedge clk);
	for(i=0;i<8;i=i+1)
		if(line_buffer0_at(10+i) !== (15'h0021+i))
			$fatal(1,"floating pixel %0d=%h",i,line_buffer0_at(10+i));
	$display("PASS gd_dx101_video drew normal and floating-tilemap 8bpp rows");
	$finish;
end
initial begin
	#200000;
	$display("timeout state=%0d busy=%b float_x=%0d sprite_addr=%h gfx_req=%b gfx_ack=%b target=%0d",
		dut.state, busy, dut.float_x, sprite_address, gfx_req, gfx_ack,
		dut.target_line);
	$fatal(1,"timeout");
end
endmodule
