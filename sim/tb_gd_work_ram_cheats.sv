`timescale 1ns/1ps

module tb_gd_work_ram_cheats;
logic [23:0] address = 0;
logic [15:0] ram_q = 0;
logic [15:0] cpu_write_data = 0;
logic [1:0] cpu_write_be = 0;
logic cheat_infinite_credits = 0;
logic cheat_infinite_time = 0;
logic cheat_p1_energy = 0;
logic cheat_p2_energy = 0;
logic [15:0] cpu_read_data;
logic [15:0] ram_write_data;

gd_work_ram_cheats dut(.*);

initial begin
	ram_q = 16'h1234;
	cpu_write_data = 16'h5678;
	cpu_write_be = 2'b11;
	#1;
	if (cpu_read_data !== 16'h1234 || ram_write_data !== 16'h5678)
		$fatal(1, "disabled cheat changed ordinary RAM");

	address = 24'h2034ee;
	cheat_infinite_credits = 1'b1;
	#1;
	if (cpu_read_data !== 16'h1209 || ram_write_data !== 16'h5609)
		$fatal(1, "credit clamp mismatch");

	address = 24'h2035a2;
	cheat_infinite_time = 1'b1;
	#1;
	if (cpu_read_data !== 16'h0b9b || ram_write_data !== 16'h0b9b)
		$fatal(1, "time clamp mismatch");

	address = 24'h204568;
	cheat_p1_energy = 1'b1;
	#1;
	if (cpu_read_data !== 16'h1293 || ram_write_data !== 16'h5693)
		$fatal(1, "P1 energy clamp mismatch");

	address = 24'h2045be;
	cheat_p2_energy = 1'b1;
	#1;
	if (cpu_read_data !== 16'h1293 || ram_write_data !== 16'h5693)
		$fatal(1, "P2 energy clamp mismatch");

	cpu_write_be = 2'b10;
	cpu_write_data = 16'habcd;
	#1;
	if (ram_write_data !== 16'habcd)
		$fatal(1, "disabled low byte was altered on a high-only write");

	$display("PASS gd_work_ram_cheats clamps verified work-RAM values");
	$finish;
end
endmodule
