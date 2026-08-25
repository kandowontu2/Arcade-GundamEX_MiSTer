`timescale 1ns/1ps

module tb_gd_gfx_arbiter;
logic clk = 0;
always #5 clk = ~clk;
logic reset = 1;
logic cache_flush = 0;
logic [24:0] loader_addr = 0;
logic [15:0] loader_din = 0;
logic [1:0] loader_be = 0;
logic loader_rnw = 0;
logic loader_req = 0;
logic loader_burst = 0;
logic [63:0] loader_burst_data = 0;
logic [15:0] loader_dout;
logic loader_ack;
logic [24:0] renderer_addr = 0;
logic renderer_req = 0;
logic [63:0] renderer_dout;
logic renderer_ack;
logic [24:0] mem_addr;
logic [15:0] mem_din;
logic [1:0] mem_be;
logic mem_rnw;
logic mem_req;
logic mem_burst;
logic [63:0] mem_burst_data;
logic [15:0] mem_dout = 0;
logic mem_ack = 0;
logic [24:0] dma_addr;
logic dma_req;
logic [63:0] dma_data = 0;
logic dma_ack = 0;

gd_gfx_arbiter dut(.*);

task automatic renderer_read(
	input [24:0] address,
	input [63:0] expected
);
	begin
		renderer_addr <= address;
		renderer_req <= ~renderer_req;
		do @(posedge clk); while (renderer_ack != renderer_req);
		if (renderer_dout !== expected)
			$fatal(1, "renderer row %h returned %h", address,
			       renderer_dout);
	end
endtask

logic first_dma_toggle;
initial begin
	repeat (5) @(posedge clk);
	reset <= 0;
	repeat (2) @(posedge clk);

	// A miss must request exactly the renderer's eight-byte row. This is the
	// latency-critical path used by the SDRAM burst-of-four port.
	renderer_addr <= 25'h0000018;
	renderer_req <= ~renderer_req;
	do @(posedge clk); while (dma_req == dma_ack);
	if (dma_addr !== 25'h0000018)
		$fatal(1, "wrong row DMA address %h", dma_addr);
	first_dma_toggle = dma_req;
	dma_data <= 64'h3333333333333333;
	dma_ack <= dma_req;
	do @(posedge clk); while (renderer_ack != renderer_req);
	if (renderer_dout !== 64'h3333333333333333)
		$fatal(1, "selected row=%h", renderer_dout);

	// Re-reading the same row must hit without another SDRAM command.
	renderer_read(25'h0000018, 64'h3333333333333333);
	if (dma_req !== first_dma_toggle)
		$fatal(1, "cached row caused another DMA request");

	// The compact loader's expanded row must cross the bridge unchanged as
	// one four-word SDRAM write transaction.
	loader_addr <= 25'h0000040;
	loader_din <= 16'd0;
	loader_be <= 2'b11;
	loader_rnw <= 1'b0;
	loader_burst <= 1'b1;
	loader_burst_data <= 64'h7788_5566_3344_1122;
	loader_req <= ~loader_req;
	do @(posedge clk); while (mem_req == mem_ack);
	if (!mem_burst || mem_addr !== 25'h0000040
	    || mem_burst_data !== 64'h7788_5566_3344_1122)
		$fatal(1, "packed loader row was not forwarded");
	mem_ack <= mem_req;
	do @(posedge clk); while (loader_ack != loader_req);

	$display("PASS gd_gfx_arbiter cached renderer rows and forwarded loader bursts");
	$finish;
end
endmodule
