`timescale 1ns/1ps

module tb_gd_mra_cheats;
logic clk = 0;
always #5 clk = ~clk;
logic reset = 1;
logic runtime_reset = 0;
logic ioctl_download = 0;
logic [15:0] ioctl_index = 0;
logic ioctl_wr = 0;
logic [26:0] ioctl_addr = 0;
logic [7:0] ioctl_data = 0;
wire [128:0] code;
wire code_reset;
wire enable;
wire available;
logic [23:0] addr_in = 0;
logic [15:0] data_in = 16'h1234;
wire [15:0] data_out;
logic [127:0] credits, round_time, p1_energy, p2_energy;
integer stream_pos;

gd_mra_cheat_loader loader(.*);
gd_mra_cheat_engine #(.MAX_CODES(8)) engine
(
	.clk, .reset(code_reset), .enable(enable && !runtime_reset),
	.code, .available, .addr_in, .data_in, .data_out
);

task automatic begin_transfer(input [15:0] index);
	@(negedge clk);
	ioctl_download = 1;
	ioctl_index = index;
	ioctl_wr = 0;
	stream_pos = 0;
endtask

task automatic send_byte(input [7:0] next_byte);
	@(negedge clk);
	ioctl_addr = stream_pos;
	ioctl_data = next_byte;
	ioctl_wr = 1;
	stream_pos = stream_pos + 1;
endtask

task automatic send_code(input [127:0] packet);
	integer b;
	for (b = 15; b >= 0; b = b - 1) send_byte(packet[b*8 +: 8]);
endtask

task automatic end_transfer;
	@(negedge clk);
	ioctl_wr = 0;
	ioctl_download = 0;
	repeat (3) @(posedge clk);
	#1;
endtask

task automatic expect_read(input [23:0] addr, input [15:0] original,
                           input [15:0] expected);
	addr_in = addr;
	data_in = original;
	#1;
	if (data_out !== expected)
		$fatal(1, "read %h: original %h expected %h got %h", addr,
		       original, expected, data_out);
endtask

initial begin
	if (!$value$plusargs("credits=%h", credits)
	    || !$value$plusargs("time=%h", round_time)
	    || !$value$plusargs("p1=%h", p1_energy)
	    || !$value$plusargs("p2=%h", p2_energy))
		$fatal(1, "provide the four code packets parsed from the release MRA");
	repeat (3) @(negedge clk);
	reset = 0;
	expect_read(24'h2034ee, 16'h1234, 16'h1234);
	if (available) $fatal(1, "cold boot has active cheats");

	// This is Main's exact protocol: concatenated 16-byte MRA codes.
	begin_transfer(255);
	send_code(credits);
	send_code(round_time);
	send_code(p1_energy);
	send_code(p2_energy);
	#1;
	expect_read(24'h2034ee, 16'h1234, 16'h1234); // Disabled during upload.
	end_transfer();
	if (!available) $fatal(1, "full MRA code set not committed");
	expect_read(24'h2034ee, 16'h1200, 16'h1209);
	expect_read(24'h2035a2, 16'h0042, 16'h0b9b);
	expect_read(24'h204568, 16'hab00, 16'hab93);
	expect_read(24'h2045be, 16'hcd00, 16'hcd93);
	expect_read(24'h2034ec, 16'h5678, 16'h5678);
	expect_read(24'h2134ee, 16'h1234, 16'h1234); // No address alias.

	runtime_reset = 1;
	expect_read(24'h204568, 16'h1234, 16'h1234);
	runtime_reset = 0;
	expect_read(24'h204568, 16'h1234, 16'h1293);

	// Toggling replaces the entire selected set; stale codes disappear.
	begin_transfer(255);
	send_code(p1_energy);
	end_transfer();
	expect_read(24'h2034ee, 16'h1200, 16'h1200);
	expect_read(24'h2035a2, 16'h0042, 16'h0042);
	expect_read(24'h204568, 16'hab00, 16'hab93);
	expect_read(24'h2045be, 16'hcd00, 16'hcd00);

	// DIP/ROM traffic cannot be decoded as a cheat packet.
	begin_transfer(254);
	send_code(credits);
	end_transfer();
	expect_read(24'h204568, 16'h1234, 16'h1293);
	expect_read(24'h2034ee, 16'h1234, 16'h1234);
	begin_transfer(16'h01ff);
	send_code(credits);
	end_transfer();
	expect_read(24'h2034ee, 16'h1234, 16'h1234);

	// Disabling the final selection sends only two bytes through Main.
	begin_transfer(255);
	send_byte(0);
	send_byte(0);
	end_transfer();
	if (available) $fatal(1, "empty selection retained a stale cheat");
	expect_read(24'h204568, 16'h1234, 16'h1234);

	// Partial and reordered transfers must not manufacture a code.
	begin_transfer(255);
	send_byte(0);
	send_byte(0);
	send_byte(0);
	end_transfer();
	if (available) $fatal(1, "incomplete code was committed");
	begin_transfer(255);
	send_byte(0);
	stream_pos = 2;
	send_code(credits);
	end_transfer();
	if (available) $fatal(1, "reordered code was committed");

	// Exercise all four big-endian byte lanes, compare/OR/AND and a longword.
	begin_transfer(255);
	send_code(128'h00000010_00200000_00000000_000000aa);
	send_code(128'h00000010_00200001_00000000_000000bb);
	send_code(128'h00000010_00200002_00000000_000000cc);
	send_code(128'h00000010_00200003_00000000_000000dd);
	send_code(128'h00000021_00200010_00001234_00005678);
	send_code(128'h00000110_00200015_00000000_00000080);
	send_code(128'h00000220_00200018_00000000_00000f0f);
	send_code(128'h00000040_00200020_00000000_12345678);
	// Ninth code must be ignored without overwriting slot zero.
	send_code(128'h00000010_00200000_00000000_000000ff);
	end_transfer();
	expect_read(24'h200000, 16'h0102, 16'haabb);
	expect_read(24'h200002, 16'h0304, 16'hccdd);
	expect_read(24'h200010, 16'h1234, 16'h5678);
	expect_read(24'h200010, 16'h4321, 16'h4321);
	expect_read(24'h200014, 16'h1203, 16'h1283);
	expect_read(24'h200018, 16'habcd, 16'h0b0d);
	expect_read(24'h200020, 16'habcd, 16'h1234);
	expect_read(24'h200022, 16'habcd, 16'h5678);

	begin_transfer(255);
	send_code(128'h00000011_00200001_00000034_00000009);
	send_code(128'h00000020_00200006_00000000_0000beef);
	send_code(128'h00000010_00200009_00000000_00000080);
	send_code(128'h00000010_00200009_00000000_00000090);
	// Invalid alignment, address and flags cannot alter memory.
	send_code(128'h00000020_0020000b_00000000_0000ffff);
	send_code(128'h00000010_0120000d_00000000_000000ff);
	send_code(128'h00000310_0020000f_00000000_000000ff);
	send_code(128'h00000041_00200010_abcd1234_ffffffff);
	end_transfer();
	expect_read(24'h200000, 16'h1234, 16'h1209);
	expect_read(24'h200000, 16'h1235, 16'h1235);
	expect_read(24'h200006, 16'h1234, 16'hbeef);
	expect_read(24'h200008, 16'h1234, 16'h1290); // Last matching code wins.
	expect_read(24'h20000a, 16'h1234, 16'h1234);
	expect_read(24'h20000c, 16'h1234, 16'h1234);
	expect_read(24'h20000e, 16'h1234, 16'h1234);
	expect_read(24'h200010, 16'habcd, 16'habcd);

	// Cold reset/new ROM clears codes; warm reset above did not.
	@(negedge clk);
	reset = 1;
	repeat (2) @(negedge clk);
	reset = 0;
	expect_read(24'h200006, 16'h1234, 16'h1234);
	if (available) $fatal(1, "new ROM retained cheats");
	$display("PASS MRA cheats: actual MRA packets, toggles, endian lanes, flags, resets, transfer isolation and bounds");
	$finish;
end

initial begin
	#100000;
	$fatal(1, "MRA cheat regression timeout");
end
endmodule
