`timescale 1ns/1ps

module tb_gd_ddr_memory;
logic clk = 0;
always #5 clk = ~clk;
logic reset = 1;
logic load_wr = 0;
logic [25:0] load_addr = 0;
logic [7:0] load_data = 0;
logic load_wait;
logic load_idle;
logic [21:0] cpu_addr = 0;
logic cpu_req = 0;
logic [15:0] cpu_dout;
logic cpu_ack;
logic [20:0] sound_addr = 0;
logic sound_req = 0;
logic [7:0] sound_dout;
logic sound_ack;
logic [16:0] ram_addr = 0;
logic ram_req = 0;
logic ram_write = 0;
logic [15:0] ram_data = 0;
logic [1:0] ram_be = 0;
logic [15:0] ram_dout;
logic ram_ack;
logic [24:0] gfx_addr = 0;
logic gfx_req = 0;
logic [255:0] gfx_dout;
logic gfx_ack;
logic ddr_clk;
logic ddr_busy = 0;
logic [7:0] ddr_burstcount;
logic [28:0] ddr_addr;
logic [63:0] ddr_dout = 0;
logic ddr_dout_ready = 0;
logic ddr_rd;
logic [63:0] ddr_din;
logic [7:0] ddr_be;
logic ddr_we;

gd_ddr_memory dut(.*);

logic [63:0] memory [0:700000];
integer busy_count = 0;
logic pending_read = 0;
logic [28:0] read_address;
integer burst_words_remaining = 0;
integer last_read_burstcount = 0;
integer read_count = 0;
integer write_count = 0;
integer lane;

always_ff @(posedge clk) begin
	ddr_dout_ready <= 0;
	if (busy_count > 0) begin
		busy_count <= busy_count - 1;
		ddr_busy <= (busy_count > 1);
		if ((busy_count == 1) && pending_read) begin
			ddr_dout <= memory[read_address - 29'h06400000];
			ddr_dout_ready <= 1;
			read_address <= read_address + 29'd1;
			if (burst_words_remaining == 1) begin
				pending_read <= 0;
				burst_words_remaining <= 0;
			end
			else begin
				burst_words_remaining <= burst_words_remaining - 1;
				busy_count <= 1;
				ddr_busy <= 1;
			end
		end
	end
	else begin
		ddr_busy <= 0;
		if (ddr_we) begin
			for(lane=0;lane<8;lane=lane+1)
				if(ddr_be[lane]) memory[ddr_addr - 29'h06400000][lane*8 +: 8]
					<= ddr_din[lane*8 +: 8];
			write_count <= write_count + 1;
			ddr_busy <= 1;
			busy_count <= 3;
		end
		else if (ddr_rd) begin
			read_count <= read_count + 1;
			read_address <= ddr_addr;
			pending_read <= 1;
			burst_words_remaining <= ddr_burstcount;
			last_read_burstcount <= ddr_burstcount;
			ddr_busy <= 1;
			busy_count <= 3;
		end
	end
end

task automatic send_byte(input [25:0] address, input [7:0] value);
	begin
		load_addr <= address;
		load_data <= value;
		load_wr <= 1;
		do @(posedge clk); while (load_wait);
		load_wr <= 0;
	end
endtask

integer i;
integer reads_before;
initial begin
	repeat(5) @(posedge clk);
	reset <= 0;
	for (i=0; i<24; i=i+1) send_byte(i[21:0], i[7:0]);
	while (!load_idle) @(posedge clk);
	repeat(5) @(posedge clk);
	if (write_count != 3) $fatal(1,"DDR writes=%0d",write_count);
	if (memory[0] !== 64'h0706050403020100) $fatal(1,"line0=%h",memory[0]);
	if (memory[1] !== 64'h0f0e0d0c0b0a0908) $fatal(1,"line1=%h",memory[1]);
	if (memory[2] !== 64'h1716151413121110) $fatal(1,"line2=%h",memory[2]);

	for (i=0; i<8; i=i+1) send_byte(26'h0400000 + i, (8'h80 + i));
	while (!load_idle) @(posedge clk);
	repeat(5) @(posedge clk);
	if (memory[29'h00080000] !== 64'h8786858483828180)
		$fatal(1,"graphics DDR line=%h",memory[29'h00080000]);
	memory[29'h00080001] = 64'h9796959493929190;
	memory[29'h00080002] = 64'ha7a6a5a4a3a2a1a0;
	memory[29'h00080003] = 64'hb7b6b5b4b3b2b1b0;
	gfx_addr <= 25'd0;
	gfx_req <= ~gfx_req;
	do @(posedge clk); while (gfx_ack != gfx_req);
	if (last_read_burstcount != 4)
		$fatal(1,"graphics burstcount=%0d",last_read_burstcount);
	if (gfx_dout[63:0] !== 64'h8687_8485_8283_8081)
		$fatal(1,"graphics row0=%h",gfx_dout[63:0]);
	if (gfx_dout[127:64] !== 64'h9697_9495_9293_9091)
		$fatal(1,"graphics row1=%h",gfx_dout[127:64]);
	if (gfx_dout[191:128] !== 64'ha6a7_a4a5_a2a3_a0a1)
		$fatal(1,"graphics row2=%h",gfx_dout[191:128]);
	if (gfx_dout[255:192] !== 64'hb6b7_b4b5_b2b3_b0b1)
		$fatal(1,"graphics row3=%h",gfx_dout[255:192]);

	cpu_addr <= 22'd2;
	cpu_req <= ~cpu_req;
	do @(posedge clk); while (cpu_ack != cpu_req);
	if (cpu_dout !== 16'h0203) $fatal(1,"cpu word=%h",cpu_dout);
	cpu_addr <= 22'd6;
	cpu_req <= ~cpu_req;
	do @(posedge clk); while (cpu_ack != cpu_req);
	if (cpu_dout !== 16'h0607) $fatal(1,"cached cpu word=%h",cpu_dout);
	reads_before = read_count;
	cpu_addr <= 22'd22;
	cpu_req <= ~cpu_req;
	do @(posedge clk); while (cpu_ack != cpu_req);
	if (cpu_dout !== 16'h1617) $fatal(1,"burst-cached cpu word=%h",cpu_dout);
	if (read_count != reads_before)
		$fatal(1,"cpu 32-byte burst cache issued another DDR read");

	memory[29'h00050000] = 64'h8786858483828180;
	memory[29'h00050001] = 64'h9796959493929190;
	sound_addr <= 21'd0;
	sound_req <= ~sound_req;
	do @(posedge clk); while (sound_ack != sound_req);
	sound_addr <= 21'd8;
	sound_req <= ~sound_req;
	do @(posedge clk); while (sound_ack != sound_req);
	reads_before = read_count;
	sound_addr <= 21'd1;
	sound_req <= ~sound_req;
	do @(posedge clk); while (sound_ack != sound_req);
	if (sound_dout !== 8'h81) $fatal(1,"multi-line sound cache byte=%h",sound_dout);
	if (read_count != reads_before)
		$fatal(1,"second PCM cache line evicted first line");

	memory[29'h000a2000] = 64'hffffffffffffffff;
	ram_addr <= 17'h10002;
	ram_data <= 16'ha1b2;
	ram_be <= 2'b11;
	ram_write <= 1;
	ram_req <= ~ram_req;
	do @(posedge clk); while (ram_ack != ram_req);
	while(ddr_busy) @(posedge clk);
	if(memory[29'h000a2000] !== 64'hffffffffb2a1ffff)
		$fatal(1,"writable DDR line=%h",memory[29'h000a2000]);
	ram_write <= 0;
	ram_req <= ~ram_req;
	do @(posedge clk); while (ram_ack != ram_req);
	if(ram_dout !== 16'ha1b2) $fatal(1,"writable DDR read=%h",ram_dout);
	$display("PASS gd_ddr_memory served program, graphics and writable board RAM");
	$finish;
end
endmodule
