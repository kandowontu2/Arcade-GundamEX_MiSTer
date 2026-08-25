// Convert MiSTer's signed left-stick axes to the digital directions used by
// the P0-113A arcade inputs. The HPS format is Y in [15:8], X in [7:0],
// with each axis ranging from -127 to +127.
// SPDX-License-Identifier: GPL-3.0-or-later

module gd_analog_to_digital
#(
	parameter signed [7:0] DEAD_ZONE = 8'sd32
)
(
	input  logic [31:0] digital_in,
	input  logic [15:0] analog_xy,
	output logic [31:0] joystick_out
);

wire signed [7:0] analog_x = $signed(analog_xy[7:0]);
wire signed [7:0] analog_y = $signed(analog_xy[15:8]);

always_comb begin
	joystick_out = digital_in;

	// MiSTer direction bits: right, left, down, up. A mapped D-pad has
	// priority over an analog axis so opposite directions cannot be asserted
	// merely because both controls are being touched.
	if (!(digital_in[0] || digital_in[1])) begin
		joystick_out[0] = (analog_x > DEAD_ZONE);
		joystick_out[1] = (analog_x < -DEAD_ZONE);
	end

	if (!(digital_in[2] || digital_in[3])) begin
		joystick_out[2] = (analog_y > DEAD_ZONE);
		joystick_out[3] = (analog_y < -DEAD_ZONE);
	end
end

endmodule
