`timescale 1ns/1ps

module tb_gd_sdram_dma;
logic clk = 1'b0;
logic reset = 1'b1;
tri [15:0] SDRAM_DQ;
logic [15:0] external_dq = 16'h0000;
assign SDRAM_DQ = external_dq;
wire [12:0] SDRAM_A;
wire [1:0] SDRAM_BA;
wire SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH;
wire SDRAM_nCS, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS;
logic [24:0] mem_addr = 25'd0;
logic [15:0] mem_din = 16'd0;
logic [1:0] mem_be = 2'b11;
logic mem_rnw = 1'b1;
logic mem_req = 1'b0;
logic mem_burst = 1'b0;
logic [63:0] mem_burst_data = 64'd0;
logic [15:0] mem_dout;
logic mem_ack;
logic video_dma_req = 1'b0;
logic [24:0] video_dma_addr = 25'h0123400;
logic video_dma_ack;
logic [63:0] video_dma_data;
logic ready;

integer read_delay = -1;
integer burst_word = 0;
integer timeout = 0;
integer first_timeout = 0;
integer same_page_timeout = 0;
integer different_page_timeout = 0;
integer write_count = 0;
integer write_activate_count = 0;
logic observing_writes = 1'b0;
logic [15:0] captured_write_data [0:3];
logic [8:0] captured_write_column [0:3];
logic captured_write_precharge [0:3];

always #4.365 clk = ~clk;

gd_sdram dut(.*);

// Minimal CAS-2, burst-length-4 SDRAM read model. Commands are sampled on
// the forwarded SDRAM clock and returned data is changed on that same edge,
// leaving it centered around the controller's following clk rising edge.
always @(posedge SDRAM_CLK) begin
	if (observing_writes
	    && ({SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} == 3'b011))
		write_activate_count = write_activate_count + 1;
	if ({SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} == 3'b100) begin
		if (write_count < 4) begin
			captured_write_data[write_count] = dut.dq_out;
			captured_write_column[write_count] = SDRAM_A[8:0];
			captured_write_precharge[write_count] = SDRAM_A[10];
		end
		write_count = write_count + 1;
	end
	if ({SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE} == 3'b101) begin
		read_delay = 2;
		burst_word = 0;
	end
	else if (read_delay > 1) begin
		read_delay = read_delay - 1;
	end
	else if (read_delay == 1) begin
		external_dq = 16'h1122;
		read_delay = 0;
		burst_word = 1;
	end
	else if (read_delay == 0 && burst_word < 4) begin
		case (burst_word)
			1: external_dq = 16'h3344;
			2: external_dq = 16'h5566;
			default: external_dq = 16'h7788;
		endcase
		burst_word = burst_word + 1;
	end
end

initial begin
	repeat (4) @(posedge clk);
	reset = 1'b0;
	while (!ready && timeout < 30000) begin
		@(posedge clk);
		timeout = timeout + 1;
	end
	if (!ready) $fatal(1, "SDRAM initialization timeout");

	@(negedge clk);
	video_dma_req = ~video_dma_req;
	timeout = 0;
	while ((video_dma_ack != video_dma_req) && timeout < 100) begin
		@(posedge clk);
		timeout = timeout + 1;
	end
	if (video_dma_ack != video_dma_req)
		$fatal(1, "DMA timeout state=%0d", dut.state);
	if (video_dma_data !== 64'h7788_5566_3344_1122)
		$fatal(1, "DMA row=%h", video_dma_data);
	first_timeout = timeout;

	// A second row in the same 1 KiB page bypasses precharge/activate/tRCD.
	@(negedge clk);
	video_dma_addr = video_dma_addr + 25'h0000040;
	video_dma_req = ~video_dma_req;
	timeout = 0;
	while ((video_dma_ack != video_dma_req) && timeout < 100) begin
		@(posedge clk);
		timeout = timeout + 1;
	end
	same_page_timeout = timeout;
	if (video_dma_ack != video_dma_req
	    || video_dma_data !== 64'h7788_5566_3344_1122)
		$fatal(1, "same-page DMA failed in %0d clocks row=%h",
			timeout, video_dma_data);
	if (same_page_timeout >= first_timeout)
		$fatal(1, "open-page DMA did not reduce latency: first=%0d same=%0d",
			first_timeout, same_page_timeout);

	// Crossing a row boundary closes the old page and activates the new one.
	@(negedge clk);
	video_dma_addr = video_dma_addr + 25'h0000400;
	video_dma_req = ~video_dma_req;
	timeout = 0;
	while ((video_dma_ack != video_dma_req) && timeout < 100) begin
		@(posedge clk);
		timeout = timeout + 1;
	end
	different_page_timeout = timeout;
	if (video_dma_ack != video_dma_req
	    || video_dma_data !== 64'h7788_5566_3344_1122)
		$fatal(1, "different-page DMA failed in %0d clocks row=%h",
			timeout, video_dma_data);
	if (different_page_timeout <= same_page_timeout)
		$fatal(1, "page crossing did not pay activation latency: same=%0d different=%0d",
			same_page_timeout, different_page_timeout);

	// A packed loader request is intentionally realized as four complete
	// single-location writes for integrated-BGA SDRAM compatibility.
	@(negedge clk);
	observing_writes = 1'b1;
	mem_addr = 25'h0012000;
	mem_din = 16'd0;
	mem_be = 2'b11;
	mem_rnw = 1'b0;
	mem_burst = 1'b1;
	mem_burst_data = 64'h7788_5566_3344_1122;
	mem_req = ~mem_req;
	timeout = 0;
	while ((mem_ack != mem_req) && timeout < 200) begin
		@(posedge clk);
		timeout = timeout + 1;
	end
	if (mem_ack != mem_req || write_count != 4)
		$fatal(1, "packed write failed count=%0d state=%0d",
		       write_count, dut.state);
	if (captured_write_data[0] !== 16'h1122
	    || captured_write_data[1] !== 16'h3344
	    || captured_write_data[2] !== 16'h5566
	    || captured_write_data[3] !== 16'h7788)
		$fatal(1, "packed write data mismatch %h %h %h %h",
		       captured_write_data[0], captured_write_data[1],
		       captured_write_data[2], captured_write_data[3]);
	if (captured_write_column[1] !== captured_write_column[0] + 9'd1
	    || captured_write_column[2] !== captured_write_column[0] + 9'd2
	    || captured_write_column[3] !== captured_write_column[0] + 9'd3)
		$fatal(1, "packed write columns were not consecutive");
	if (!captured_write_precharge[0] || !captured_write_precharge[1]
	    || !captured_write_precharge[2] || !captured_write_precharge[3])
		$fatal(1, "packed write precharge sequence mismatch");
	if (write_activate_count != 4)
		$fatal(1, "packed write did not use four independent activations: %0d",
		       write_activate_count);

	$display("PASS gd_sdram open-page DMA and portable packed loader write first=%0d same-page=%0d different-page=%0d clocks",
		first_timeout, same_page_timeout, different_page_timeout);
	$finish;
end
endmodule
