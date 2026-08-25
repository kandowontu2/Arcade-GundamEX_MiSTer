`timescale 1ns/1ps

module tb_gd_93c46;
logic clk = 0;
always #5 clk = ~clk;
logic reset = 1;
logic load_wr = 0;
logic [6:0] load_addr = 0;
logic [7:0] load_data = 0;
logic chip_select = 0;
logic serial_clock = 0;
logic data_in = 0;
logic data_out;

gd_93c46 dut(.*);

task automatic load_byte(input [6:0] address, input [7:0] value);
begin
	@(negedge clk);
	load_addr = address;
	load_data = value;
	load_wr = 1;
	@(negedge clk);
	load_wr = 0;
end
endtask

task automatic clock_command_bit(input logic value, input logic leave_high);
begin
	data_in = value;
	serial_clock = 0;
	repeat (2) @(negedge clk);
	serial_clock = 1;
	repeat (2) @(negedge clk);
	if (!leave_high) begin
		serial_clock = 0;
		repeat (2) @(negedge clk);
	end
end
endtask

logic [15:0] result;
integer bit_number;
initial begin
	load_byte(7'd0, 8'ha5);
	load_byte(7'd1, 8'h5a);
	reset = 0;
	repeat (3) @(negedge clk);
	chip_select = 1;
	repeat (3) @(negedge clk);

	// READ command: start=1, opcode=10, six-bit address=0.
	clock_command_bit(1'b1, 1'b0);
	clock_command_bit(1'b1, 1'b0);
	clock_command_bit(1'b0, 1'b0);
	for (bit_number = 5; bit_number >= 1; bit_number = bit_number - 1)
		clock_command_bit(1'b0, 1'b0);
	clock_command_bit(1'b0, 1'b1);

	for (bit_number = 15; bit_number >= 0; bit_number = bit_number - 1) begin
		result[bit_number] = data_out;
		serial_clock = 0;
		repeat (2) @(negedge clk);
		if (bit_number != 0) begin
			serial_clock = 1;
			repeat (2) @(negedge clk);
		end
	end
	if (result !== 16'ha55a)
		$fatal(1, "93C46 READ returned %h", result);
	chip_select = 0;
	$display("PASS gd_93c46 loaded and serially read a 16-bit factory word");
	$finish;
end

initial begin
	#50000;
	$fatal(1, "timeout");
end
endmodule
