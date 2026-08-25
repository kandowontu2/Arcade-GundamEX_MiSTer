// 93C46 Microwire EEPROM in 64 x 16-bit organization.
// Gundam EX Revue connects DI, SK, CS and DO to TMP68301 parallel-port bits
// 0, 1, 2 and 3 respectively. The MRA supplies the board's 128-byte factory
// image; writes remain valid until the core is reloaded.
// SPDX-License-Identifier: GPL-3.0-or-later

module gd_93c46
(
	input  logic       clk,
	input  logic       reset,
	input  logic       load_wr,
	input  logic [6:0] load_addr,
	input  logic [7:0] load_data,
	input  logic       chip_select,
	input  logic       serial_clock,
	input  logic       data_in,
	output logic       data_out
);

typedef enum logic [2:0] {
	EEP_COMMAND, EEP_READ, EEP_WRITE, EEP_WRITE_ALL, EEP_DONE
} eeprom_state_t;

(* ramstyle = "MLAB" *) logic [15:0] memory [0:63];
eeprom_state_t state;
logic chip_select_d;
logic serial_clock_d;
logic [8:0] command_shift;
logic [3:0] command_bits;
logic [15:0] data_shift;
logic [4:0] data_bits;
logic [15:0] read_shift;
logic [4:0] read_bits;
logic [5:0] word_address;
logic write_enabled;
wire [8:0] completed_command = {command_shift[7:0], data_in};
integer index;

initial begin
	for (index = 0; index < 64; index = index + 1)
		memory[index] = 16'hffff;
end

always_ff @(posedge clk) begin
	chip_select_d <= chip_select;
	serial_clock_d <= serial_clock;

	if (load_wr) begin
		if (!load_addr[0]) memory[load_addr[6:1]][15:8] <= load_data;
		else memory[load_addr[6:1]][7:0] <= load_data;
	end

	if (reset) begin
		state <= EEP_COMMAND;
		chip_select_d <= 1'b0;
		serial_clock_d <= 1'b0;
		command_shift <= 9'd0;
		command_bits <= 4'd0;
		data_shift <= 16'd0;
		data_bits <= 5'd0;
		read_shift <= 16'd0;
		read_bits <= 5'd0;
		word_address <= 6'd0;
		write_enabled <= 1'b0;
		data_out <= 1'b1;
	end
	else if (!chip_select) begin
		state <= EEP_COMMAND;
		command_shift <= 9'd0;
		command_bits <= 4'd0;
		data_bits <= 5'd0;
		data_out <= 1'b1;
	end
	else if (chip_select && !chip_select_d) begin
		state <= EEP_COMMAND;
		command_shift <= 9'd0;
		command_bits <= 4'd0;
		data_bits <= 5'd0;
		data_out <= 1'b1;
	end
	else begin
		// Commands and write data are sampled on SK rising edges.
		if (serial_clock && !serial_clock_d) begin
			case (state)
				EEP_COMMAND: begin
					command_shift <= {command_shift[7:0], data_in};
					if (command_bits == 4'd8) begin
						command_bits <= 4'd0;
						if (completed_command[8]) begin
							word_address <= completed_command[5:0];
							case (completed_command[7:6])
								2'b10: begin // READ
									read_shift <= memory[completed_command[5:0]];
									read_bits <= 5'd15;
									data_out <= memory[completed_command[5:0]][15];
									state <= EEP_READ;
								end
								2'b01: begin // WRITE
									data_shift <= 16'd0;
									data_bits <= 5'd0;
									state <= EEP_WRITE;
								end
								2'b11: begin // ERASE
									if (write_enabled)
										memory[completed_command[5:0]] <= 16'hffff;
									data_out <= 1'b1;
									state <= EEP_DONE;
								end
								default: begin
									case (completed_command[5:4])
										2'b11: write_enabled <= 1'b1; // EWEN
										2'b00: write_enabled <= 1'b0; // EWDS
										2'b10: if (write_enabled) begin // ERAL
											for (index = 0; index < 64; index = index + 1)
												memory[index] <= 16'hffff;
										end
										default: begin // WRAL
											data_shift <= 16'd0;
											data_bits <= 5'd0;
											state <= EEP_WRITE_ALL;
										end
									endcase
									if (completed_command[5:4] != 2'b01)
										state <= EEP_DONE;
									data_out <= 1'b1;
								end
							endcase
						end
						else begin
							command_shift <= 9'd0;
							state <= EEP_COMMAND;
						end
					end
					else command_bits <= command_bits + 4'd1;
				end

				EEP_WRITE: begin
					data_shift <= {data_shift[14:0], data_in};
					if (data_bits == 5'd15) begin
						if (write_enabled)
							memory[word_address] <= {data_shift[14:0], data_in};
						data_out <= 1'b1;
						state <= EEP_DONE;
					end
					else data_bits <= data_bits + 5'd1;
				end

				EEP_WRITE_ALL: begin
					data_shift <= {data_shift[14:0], data_in};
					if (data_bits == 5'd15) begin
						if (write_enabled) begin
							for (index = 0; index < 64; index = index + 1)
								memory[index] <= {data_shift[14:0], data_in};
						end
						data_out <= 1'b1;
						state <= EEP_DONE;
					end
					else data_bits <= data_bits + 5'd1;
				end

				default: ;
			endcase
		end

		// READ data advances on falling edges so DO is stable for the host's
		// high-clock sample. Sequential reads wrap through the 64-word array.
		if (!serial_clock && serial_clock_d && (state == EEP_READ)) begin
			if (read_bits == 5'd0) begin
				word_address <= word_address + 6'd1;
				read_shift <= memory[word_address + 6'd1];
				read_bits <= 5'd15;
				data_out <= memory[word_address + 6'd1][15];
			end
			else begin
				read_shift <= {read_shift[14:0], 1'b0};
				read_bits <= read_bits - 5'd1;
				data_out <= read_shift[14];
			end
		end
	end
end

endmodule
