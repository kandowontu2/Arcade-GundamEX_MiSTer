`timescale 1ns/1ps

module tb_gd_analog_to_digital;
	logic [31:0] digital_in;
	logic [15:0] analog_xy;
	logic [31:0] joystick_out;

	gd_analog_to_digital dut(.*);

	task automatic expect_directions(input [3:0] expected);
		#1;
		if (joystick_out[3:0] !== expected) begin
			$display("FAIL analog=%h digital=%h got=%b expected=%b",
				analog_xy, digital_in, joystick_out[3:0], expected);
			$fatal(1);
		end
	endtask

	initial begin
		digital_in = 32'h00000100;
		analog_xy = {8'sd0, 8'sd0};
		expect_directions(4'b0000);
		if (!joystick_out[8]) $fatal(1, "non-direction button changed");

		analog_xy = {8'sd0, 8'sd33};
		expect_directions(4'b0001); // right
		analog_xy = {8'sd0, -8'sd33};
		expect_directions(4'b0010); // left
		analog_xy = {8'sd33, 8'sd0};
		expect_directions(4'b0100); // down
		analog_xy = {-8'sd33, 8'sd0};
		expect_directions(4'b1000); // up

		analog_xy = {8'sd32, 8'sd32};
		expect_directions(4'b0000); // boundary is inside dead zone

		digital_in[1:0] = 2'b10;
		analog_xy = {8'sd0, 8'sd100};
		expect_directions(4'b0010); // D-pad wins over opposite stick

		$display("PASS gd_analog_to_digital dead zone and D-pad priority");
		$finish;
	end
endmodule
