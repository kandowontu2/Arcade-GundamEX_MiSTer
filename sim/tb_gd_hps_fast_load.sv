`timescale 1ns/1ps

// Drive the bundled hps_io file-transfer protocol, not a simplified mock.
// A direct-DDR transfer reports its length before download starts and the
// FIO_FILE_TX stop command increments ioctl_addr despite sending no bytes.
module tb_gd_hps_fast_load;
logic clk = 0;
always #5 clk = ~clk;
logic reset = 1;
tri [45:0] HPS_BUS;
tri [35:0] EXT_BUS;
logic fp_enable = 0;
logic io_strobe = 0;
logic [15:0] io_din = 0;
assign HPS_BUS[35] = fp_enable;
assign HPS_BUS[34] = 1'b0;
assign HPS_BUS[33] = io_strobe;
assign HPS_BUS[31:16] = io_din;
assign HPS_BUS[45:38] = 8'd0;
assign EXT_BUS[32] = 1'b0;

wire ioctl_download;
wire [26:0] ioctl_addr;
wire ioctl_wr;
wire [7:0] ioctl_data;
wire ioctl_wait;
wire busy;
logic data_wait = 0;
wire data_strobe;
wire [26:0] data_addr;
wire [7:0] data;
wire ddr_acquire;
wire [28:0] ddr_addr;
wire ddr_read;
logic [63:0] ddr_rdata = 0;
logic ddr_rdata_ready = 0;
logic ddr_busy = 0;

hps_io #(.CONF_STR("GundamEX;;")) hps (
	.clk_sys(clk), .HPS_BUS(HPS_BUS), .EXT_BUS(EXT_BUS),
	.ioctl_download(ioctl_download), .ioctl_addr(ioctl_addr),
	.ioctl_wr(ioctl_wr), .ioctl_dout(ioctl_data), .ioctl_wait(ioctl_wait),
	.ioctl_upload_req(1'b0), .ioctl_upload_index(8'd0), .ioctl_din(8'd0),
	.status_in(128'd0), .status_set(1'b0), .status_menumask(16'd0),
	.info_req(1'b0), .info(8'd0), .new_vmode(1'b0), .video_rotated(1'b0),
	.sd_rd(1'b0), .sd_wr(1'b0)
);
gd_ddr_rom_loader_adaptor dut(.*);

logic pending_read = 0;
integer read_count = 0;
integer replay_count = 0;
integer expected_length = 8;
always @(posedge clk) begin
	ddr_rdata_ready <= 1'b0;
	if (ddr_read && !ddr_busy && !pending_read) begin
		pending_read <= 1'b1;
		ddr_busy <= 1'b1;
		read_count <= read_count + 1;
	end
	else if (pending_read) begin
		pending_read <= 1'b0;
		ddr_busy <= 1'b0;
		ddr_rdata_ready <= 1'b1;
		case (ddr_addr)
			29'h06000000: ddr_rdata <= 64'h0706050403020100;
			29'h06000001: ddr_rdata <= 64'h0f0e0d0c0b0a0908;
			default: $fatal(1, "unexpected DDR word address %h", ddr_addr);
		endcase
	end
	if (data_strobe) begin
		if (replay_count >= expected_length)
			$fatal(1, "extra byte after %0d-byte HPS fast load", expected_length);
		if (data_addr !== replay_count[26:0] || data !== replay_count[7:0])
			$fatal(1, "HPS fast-load byte/address mismatch at %0d", replay_count);
		replay_count <= replay_count + 1;
	end
end

task automatic send_word(input logic [15:0] word_value);
	@(negedge clk);
	io_din = word_value;
	io_strobe = 1;
	@(negedge clk);
	io_strobe = 0;
	@(negedge clk);
endtask

task automatic fast_load(input integer byte_length);
	@(negedge clk);
	fp_enable = 1;
	send_word(16'h0053); // FIO_FILE_TX
	send_word(16'h00ff); // download enable
	send_word(byte_length[15:0]);
	send_word({5'd0, byte_length[26:16]});
	fp_enable = 0;
	repeat (3) @(negedge clk);
	if (!ioctl_download || ioctl_addr !== byte_length[26:0])
		$fatal(1, "HPS did not report active staged-image length");
	if (ioctl_wr) $fatal(1, "direct-DDR load unexpectedly wrote an ioctl byte");
	fp_enable = 1;
	send_word(16'h0053);
	send_word(16'h0000); // download stop, increments address
	fp_enable = 0;
	repeat (3) @(negedge clk);
	if (ioctl_download || ioctl_addr !== (byte_length + 1))
		$fatal(1, "test did not reproduce actual hps_io stop semantics");
	wait (!busy);
	repeat (3) @(negedge clk);
	if (replay_count != byte_length)
		$fatal(1, "HPS fast-load replay length %0d expected %0d", replay_count, byte_length);
endtask

task automatic legacy_load(input integer byte_length);
	@(negedge clk);
	fp_enable = 1;
	send_word(16'h0053);
	send_word(16'h00ff);
	send_word(16'd0);
	send_word(16'd0);
	fp_enable = 0;
	repeat (3) @(negedge clk);
	fp_enable = 1;
	send_word(16'h0054); // FIO_FILE_TX_DAT: ordinary streamed bytes
	for (integer n = 0; n < byte_length; n = n + 1)
		send_word(n[15:0]);
	fp_enable = 0;
	repeat (3) @(negedge clk);
	fp_enable = 1;
	send_word(16'h0053);
	send_word(16'd0);
	fp_enable = 0;
	repeat (5) @(negedge clk);
	if (busy || replay_count != byte_length || read_count != 0)
		$fatal(1, "ordinary HPS streaming changed or triggered DDR replay");
endtask

initial begin
	repeat (4) @(negedge clk);
	reset = 0;
	fast_load(8);
	if (read_count != 1) $fatal(1, "aligned length caused an extra DDR read");
	// A second transfer with a different, non-aligned length cannot reuse
	// the previous transfer's count. Empty transfers must not replay at all.
	replay_count = 0;
	read_count = 0;
	expected_length = 11;
	fast_load(11);
	if (read_count != 2) $fatal(1, "partial final DDR word read count mismatch");
	replay_count = 0;
	read_count = 0;
	expected_length = 0;
	fast_load(0);
	if (read_count != 0) $fatal(1, "empty staged transfer started DDR replay");
	expected_length = 5;
	legacy_load(5);

	// Also exercise both length words with the actual game's image size,
	// without spending the small unit test replaying all 23+ MiB. Stall DDR
	// and inspect the captured count before aborting this transfer with reset.
	replay_count = 0;
	ddr_busy = 1;
	fp_enable = 1;
	send_word(16'h0053);
	send_word(16'h00ff);
	send_word(16'h0080);
	send_word(16'h0168);
	fp_enable = 0;
	repeat (3) @(negedge clk);
	if (!ioctl_download || ioctl_addr !== 27'h1680080)
		$fatal(1, "full Gundam image length was truncated by HPS protocol");
	fp_enable = 1;
	send_word(16'h0053);
	send_word(16'd0);
	fp_enable = 0;
	repeat (3) @(negedge clk);
	if (!busy || dut.length !== 27'h1680080 || ioctl_addr !== 27'h1680081)
		$fatal(1, "full-image replay captured the post-stop address");
	reset = 1;
	repeat (3) @(negedge clk);
	if (busy || ddr_read || ddr_acquire)
		$fatal(1, "reset did not abort stalled staged replay");
	$display("PASS gd_hps_fast_load real HPS protocol, aligned/partial/empty/full image lengths and legacy streaming");
	$finish;
end

initial begin
	#20000;
	$fatal(1, "HPS fast-load timeout");
end
endmodule
