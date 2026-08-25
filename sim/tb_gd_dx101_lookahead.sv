`timescale 1ns/1ps
module tb_gd_dx101_lookahead;
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
logic rowscroll_override_valid=1;
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
logic [63:0] gfx_dout=0;
logic gfx_ack=0;
logic [7:0] red,green,blue;
logic busy;
logic line_done;
logic [15:0] missed_lines;
logic [8:0] rowscroll_lookup_line;

gd_dx101_video #(
	.AHEAD_RENDER(1'b1), .H_TOTAL(512), .V_TOTAL(256),
	.H_VISIBLE(384), .V_VISIBLE(224)
) dut(.*);

logic [15:0] sprite_memory [0:131071];
integer i;
integer completed_lines=0;
logic [8:0] first_target=0;
logic [8:0] second_target=0;
logic [20:0] valid_before_pause=0;
logic [8:0] clear_before_pause=0;

always_ff @(posedge clk) begin
	sprite_q <= {
		sprite_memory[{sprite_address[16:2], 2'b11}],
		sprite_memory[{sprite_address[16:2], 2'b10}],
		sprite_memory[{sprite_address[16:2], 2'b01}],
		sprite_memory[{sprite_address[16:2], 2'b00}]
	};
	if (line_done) begin
		completed_lines <= completed_lines + 1;
		if (completed_lines == 0) first_target <= dut.target_line;
		if (completed_lines == 1) second_target <= dut.target_line;
	end
end

initial begin
	for(i=0;i<131072;i=i+1) sprite_memory[i]=0;
	// One final header and one off-screen descriptor: lines finish quickly,
	// leaving this test focused on queue scheduling rather than drawing.
	sprite_memory[17'h01800]=16'h8000;
	sprite_memory[17'h01803]=16'h0100;
	sprite_memory[17'h00401]=16'h01f0;
	repeat(5) @(posedge clk); reset<=0;
	@(posedge clk); ce_pix<=1; h_count<=0; v_count<=0;
	@(posedge clk); ce_pix<=0; h_count<=1;
	wait(completed_lines >= 1);
	// Advancing one physical row opens the next slot at the same nine-line
	// lead. Raster-active mode must retain that reservoir scheduling.
	@(posedge clk); ce_pix<=1; h_count<=0; v_count<=1;
	@(posedge clk); ce_pix<=0; h_count<=1;
	wait(busy && dut.state == dut.R_CLEAR);
	@(negedge clk);
	valid_before_pause = dut.bank_valid;
	clear_before_pause = dut.clear_x;
	render_pause = 1'b1;
	repeat(8) @(posedge clk);
	if (dut.clear_x !== clear_before_pause || dut.bank_valid !== valid_before_pause)
		$fatal(1,"sprite-port pause changed row state or discarded queued lines");
	@(negedge clk); render_pause = 1'b0;
	wait(completed_lines >= 2);
	@(posedge clk);
	if (first_target !== 9'd20 || second_target !== 9'd21)
		$fatal(1,"raster look-ahead did not queue consecutive rows: %0d %0d",
			first_target,second_target);
	// Scanout must continue selecting a completed row while row construction
	// is paused; this is the operation that the old buffer-trigger reset broke.
	@(negedge clk); render_pause = 1'b1; ce_pix = 1'b1;
	h_count = 9'd0; v_count = 9'd20;
	@(posedge clk);
	@(negedge clk); ce_pix = 1'b0; h_count = 9'd1;
	@(posedge clk);
	if (dut.bank_line[dut.display_bank] !== 9'd20)
		$fatal(1,"scanout did not retain/select queued line during sprite pause");
	rotate_180 = 1'b1;
	#1;
	if ((dut.target_line < 9'd224)
	    && (rowscroll_lookup_line !== (9'd223 - dut.target_line)))
		$fatal(1,"180-degree rotation did not reverse the visible target line");
	$display("PASS gd_dx101_video preserves look-ahead queue across sprite-port pause");
	$finish;
end

initial begin
	#200000;
	$fatal(1,"timeout completed=%0d state=%0d target=%0d",
		completed_lines,dut.state,dut.target_line);
end
endmodule
