// Native OSD cheats for Gundam EX Revue's 68000 work RAM.
// Address/value pairs are from the public MAME cheat collection and were
// independently checked against the supported gundamex ROM set.
// SPDX-License-Identifier: GPL-3.0-or-later

module gd_work_ram_cheats
(
	input  logic [23:0] address,
	input  logic [15:0] ram_q,
	input  logic [15:0] cpu_write_data,
	input  logic  [1:0] cpu_write_be,
	input  logic        cheat_infinite_credits,
	input  logic        cheat_infinite_time,
	input  logic        cheat_p1_energy,
	input  logic        cheat_p2_energy,
	output logic [15:0] cpu_read_data,
	output logic [15:0] ram_write_data
);

always_comb begin
	cpu_read_data = ram_q;
	ram_write_data = cpu_write_data;

	case (address)
		24'h2034ee: if (cheat_infinite_credits) begin
			cpu_read_data[7:0] = 8'h09;
			if (cpu_write_be[0]) ram_write_data[7:0] = 8'h09;
		end

		24'h2035a2: if (cheat_infinite_time) begin
			cpu_read_data = 16'h0b9b;
			if (cpu_write_be[1]) ram_write_data[15:8] = 8'h0b;
			if (cpu_write_be[0]) ram_write_data[7:0] = 8'h9b;
		end

		24'h204568: if (cheat_p1_energy) begin
			cpu_read_data[7:0] = 8'h93;
			if (cpu_write_be[0]) ram_write_data[7:0] = 8'h93;
		end

		24'h2045be: if (cheat_p2_energy) begin
			cpu_read_data[7:0] = 8'h93;
			if (cpu_write_be[0]) ram_write_data[7:0] = 8'h93;
		end

		default: begin end
	endcase
end

endmodule
