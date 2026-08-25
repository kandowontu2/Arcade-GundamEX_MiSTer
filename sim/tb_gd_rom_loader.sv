`timescale 1ns/1ps

module tb_gd_rom_loader;
logic clk = 0;
always #5 clk = ~clk;
logic reset = 1;
logic memory_ready = 1;
logic downloading = 0;
logic ioctl_wr = 0;
logic [26:0] ioctl_addr = 0;
logic [7:0] ioctl_data = 0;
logic ioctl_wait;
logic ddr_load_wr;
logic [25:0] ddr_load_addr;
logic [7:0] ddr_load_data;
logic ddr_load_wait = 0;
logic ddr_load_idle = 1;
logic [24:0] gfx_addr;
logic [15:0] gfx_din;
logic [1:0] gfx_be;
logic gfx_rnw;
logic gfx_req;
logic gfx_ack = 0;
logic gfx_burst;
logic [63:0] gfx_burst_data;
logic eeprom_load_wr;
logic [6:0] eeprom_load_addr;
logic [7:0] eeprom_load_data;
logic rom_ready;
logic layout_error;
logic [26:0] accepted_bytes;
logic [3:0] regions_seen;

gd_rom_loader dut(.*);

integer gfx_write_count = 0;
logic [24:0] captured_addr;
logic [63:0] captured_burst_data;
logic captured_burst;
logic [25:0] captured_ddr_addr;
logic [7:0] captured_ddr_data;
logic [6:0] captured_eeprom_addr;
logic [7:0] captured_eeprom_data;
always_ff @(posedge clk) begin
	if (ddr_load_wr) begin
		captured_ddr_addr <= ddr_load_addr;
		captured_ddr_data <= ddr_load_data;
	end
	if (eeprom_load_wr) begin
		captured_eeprom_addr <= eeprom_load_addr;
		captured_eeprom_data <= eeprom_load_data;
	end
	if (gfx_req != gfx_ack) begin
		captured_addr <= gfx_addr;
		captured_burst_data <= gfx_burst_data;
		captured_burst <= gfx_burst;
		gfx_write_count <= gfx_write_count + 1;
		gfx_ack <= gfx_req;
	end
end

task automatic send_byte(input [26:0] address, input [7:0] value);
begin
	@(negedge clk);
	ioctl_addr = address;
	ioctl_data = value;
	ioctl_wr = 1;
	while (ioctl_wait) @(negedge clk);
	@(negedge clk);
	ioctl_wr = 0;
end
endtask

initial begin
	repeat (4) @(negedge clk);
	reset = 0;
	downloading = 1;
	repeat (2) @(negedge clk);

	// One complete compact 48-bit graphics row becomes 64 bits in SDRAM.
	send_byte(27'h0280000, 8'h10);
	send_byte(27'h0280001, 8'h11);
	send_byte(27'h0280002, 8'h12);
	send_byte(27'h0280003, 8'h13);
	send_byte(27'h0280004, 8'h14);
	send_byte(27'h0280005, 8'h15);
	while (gfx_write_count != 1) @(negedge clk);
	if (!captured_burst || captured_addr !== 25'd0)
		$fatal(1, "graphics row transaction mismatch");
	if (captured_burst_data !== 64'h0000_1415_1213_1011)
		$fatal(1, "expanded graphics row mismatch %h",
		       captured_burst_data);

	send_byte(27'h1480000, 8'h77);
	if (captured_ddr_addr !== 26'h0280000
	    || captured_ddr_data !== 8'h77)
		$fatal(1, "sample mapping mismatch");
	send_byte(27'h1680000, 8'h80);
	if (captured_eeprom_addr !== 7'd0
	    || captured_eeprom_data !== 8'h80)
		$fatal(1, "EEPROM mapping mismatch");
	if (regions_seen !== 4'b1110)
		$fatal(1, "region telemetry mismatch %b", regions_seen);
	$display("PASS gd_rom_loader packed compact graphics and mapped samples/EEPROM");
	$finish;
end

initial begin
	#100000;
	$fatal(1, "timeout");
end
endmodule
