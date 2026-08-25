`timescale 1ns/1ps

module tb_gd_sprite_ram;
logic clk = 0;
always #5 clk = ~clk;
logic reset = 1;
logic buffer_trigger = 0;
logic buffer_busy;
logic [16:0] address = 0;
logic [15:0] data = 0;
logic [1:0] byte_enable = 2'b11;
logic write = 0;
logic [15:0] q;
logic [16:0] video_address = 0;
logic [63:0] video_q;
integer header;

gd_sprite_ram dut
(
	.clk, .reset, .buffer_trigger, .address, .data, .byte_enable,
	.write, .q, .video_clk(clk), .video_address, .video_q, .buffer_busy
);

task automatic write_word(input [16:0] a, input [15:0] d);
	begin
		address <= a;
		data <= d;
		write <= 1'b1;
		@(posedge clk);
		write <= 1'b0;
		@(posedge clk);
	end
endtask

task automatic expect_record(input [16:0] a, input [63:0] expected);
	begin
		video_address <= a;
		repeat (2) @(posedge clk);
		#1;
		if (video_q !== expected)
			$fatal(1, "record %h: expected %h, got %h",
				a, expected, video_q);
	end
endtask

initial begin
	repeat (3) @(posedge clk);
	reset <= 1'b0;
	repeat (2) @(posedge clk);

	// Two base headers reference three non-contiguous source descriptors.
	write_word(17'h01800, 16'h0001);
	write_word(17'h01801, 16'h1111);
	write_word(17'h01802, 16'h2222);
	write_word(17'h01803, 16'h8800);
	write_word(17'h01804, 16'h8000);
	write_word(17'h01805, 16'h3333);
	write_word(17'h01806, 16'h4444);
	write_word(17'h01807, 16'h8810);

	write_word(17'h02000, 16'ha000);
	write_word(17'h02001, 16'ha001);
	write_word(17'h02002, 16'ha002);
	write_word(17'h02003, 16'ha003);
	write_word(17'h02004, 16'hb000);
	write_word(17'h02005, 16'hb001);
	write_word(17'h02006, 16'hb002);
	write_word(17'h02007, 16'hb003);
	write_word(17'h02040, 16'hc000);
	write_word(17'h02041, 16'hc001);
	write_word(17'h02042, 16'hc002);
	write_word(17'h02043, 16'hc003);

	// The private list is empty until the DX-101 buffer transaction fires.
	expect_record(17'h01800, 64'd0);
	buffer_trigger <= 1'b1;
	@(posedge clk);
	buffer_trigger <= 1'b0;
	@(posedge clk);
	if (!buffer_busy) $fatal(1, "buffer transaction did not start");
	while (buffer_busy) @(posedge clk);
	repeat (2) @(posedge clk);

	// Header pointers are rewritten to packed record indices 0 and 2.
	expect_record(17'h01800, 64'h8000_2222_1111_0001);
	expect_record(17'h01804, 64'h8002_4444_3333_8000);
	expect_record(17'h00000, 64'ha003_a002_a001_a000);
	expect_record(17'h00004, 64'hb003_b002_b001_b000);
	expect_record(17'h00008, 64'hc003_c002_c001_c000);

	// Source edits wait for the next trigger, while low packed-record writes
	// remain live for raster effects.
	write_word(17'h02000, 16'hdddd);
	expect_record(17'h00000, 64'ha003_a002_a001_a000);
	write_word(17'h00003, 16'hd00d);
	expect_record(17'h00000, 64'hd00d_a002_a001_a000);

	// An early boot trigger may see an unfinished all-zero base list. The
	// hardware scan must terminate instead of holding the CPU forever.
	for (header = 0; header < 32; header = header + 1) begin
		write_word(17'h01800 + header * 4 + 0, 16'h0000);
		write_word(17'h01800 + header * 4 + 1, 16'h0000);
		write_word(17'h01800 + header * 4 + 2, 16'h0000);
		write_word(17'h01800 + header * 4 + 3, 16'h0000);
	end
	buffer_trigger <= 1'b1;
	@(posedge clk);
	buffer_trigger <= 1'b0;
	@(posedge clk);
	if (!buffer_busy) $fatal(1, "unterminated transaction did not start");
	while (buffer_busy) @(posedge clk);
	repeat (2) @(posedge clk);
	expect_record(17'h0187c, 64'h001f_0000_0000_8000);

	$display("PASS gd_sprite_ram performed DX-101 list buffering");
	$finish;
end

initial begin
	#20000;
	$fatal(1, "timeout");
end
endmodule
