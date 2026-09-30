`timescale 1ns/1ps

module tb_gd_ddr_rom_loader_adaptor;
logic clk = 0;
always #5 clk = ~clk;
logic reset = 1;
logic ioctl_download = 0;
logic [26:0] ioctl_addr = 0;
logic ioctl_wr = 0;
logic [7:0] ioctl_data = 0;
logic ioctl_wait;
logic busy;
logic data_wait = 0;
logic data_strobe;
logic [26:0] data_addr;
logic [7:0] data;
logic ddr_acquire;
logic [28:0] ddr_addr;
logic ddr_read;
logic [63:0] ddr_rdata = 0;
logic ddr_rdata_ready = 0;
logic ddr_busy = 0;

gd_ddr_rom_loader_adaptor dut(.*);

logic pending_read = 0;
always_ff @(posedge clk) begin
	ddr_rdata_ready <= 1'b0;
	if (ddr_read && !ddr_busy && !pending_read)
		pending_read <= 1'b1;
	else if (pending_read) begin
		pending_read <= 1'b0;
		ddr_rdata_ready <= 1'b1;
		case (ddr_addr)
			29'h06000000: ddr_rdata <= 64'h0706050403020100;
			29'h06000001: ddr_rdata <= 64'h0f0e0d0c0b0a0908;
			default: $fatal(1, "unexpected DDR word address %h", ddr_addr);
		endcase
	end
end

integer replay_count = 0;
always_ff @(posedge clk) begin
	if (data_strobe && !data_wait) begin
		if (data_addr !== replay_count[26:0])
			$fatal(1, "replay address %h expected %h", data_addr,
			       replay_count[26:0]);
		if (data !== replay_count[7:0])
			$fatal(1, "replay byte %h expected %h", data,
			       replay_count[7:0]);
		replay_count <= replay_count + 1;
	end
end

initial begin
	repeat (4) @(negedge clk);
	reset = 0;

	// Ordinary MiSTer byte streaming remains a transparent fallback.
	ioctl_download = 1;
	ioctl_addr = 27'd5;
	ioctl_data = 8'ha5;
	ioctl_wr = 1;
	#1;
	if (!busy || !data_strobe || data_addr !== 27'd5 || data !== 8'ha5)
		$fatal(1, "legacy pass-through mismatch");
	data_wait = 1;
	#1;
	if (!ioctl_wait) $fatal(1, "legacy backpressure not propagated");
	@(negedge clk);
	data_wait = 0;
	ioctl_wr = 0;
	ioctl_download = 0;
	repeat (3) @(negedge clk);
	if (busy) $fatal(1, "legacy transfer did not return idle");

	// A transfer with no ioctl writes represents a direct-to-DDR preload.
	ioctl_addr = 0;
	ioctl_download = 1;
	repeat (2) @(negedge clk);
	ioctl_addr = 27'd8;
	repeat (2) @(negedge clk);
	// hps_io advances its address when FIO_FILE_TX stops the transfer.
	// The active-transfer value, not this post-stop value, is the length.
	ioctl_addr = 27'd9;
	ioctl_download = 0;
	#1;
	if (!busy)
		$fatal(1, "fast-load busy dropped between staging and replay");

	// Exercise downstream backpressure partway through replay.
	wait (replay_count == 3);
	@(negedge clk);
	data_wait = 1;
	repeat (4) @(negedge clk);
	if (replay_count != 3)
		$fatal(1, "replay advanced while downstream was waiting");
	data_wait = 0;

	wait (replay_count == 8);
	wait (!busy);
	repeat (3) @(negedge clk);
	if (replay_count != 8)
		$fatal(1, "fast-load replayed %0d bytes instead of 8", replay_count);
	if (ddr_acquire || ddr_read)
		$fatal(1, "DDR interface was not released without an extra read");

	// Frameworks that do not increment the stop address work unchanged.
	replay_count = 0;
	ioctl_addr = 27'd11;
	ioctl_download = 1;
	repeat (3) @(negedge clk);
	ioctl_download = 0;
	wait (!busy);
	repeat (3) @(negedge clk);
	if (replay_count != 11)
		$fatal(1, "unchanged stop address replayed %0d bytes", replay_count);
	$display("PASS gd_ddr_rom_loader_adaptor legacy and fast-load paths");
	$finish;
end

initial begin
	#20000;
	$fatal(1, "timeout");
end
endmodule
