// Seta X1-010 16-voice PCM/wavetable sound generator.
// Register layout, rate and phase arithmetic follow MAME's BSD-licensed
// x1_010 device model. The sample ROM is fetched through a toggle interface.
// SPDX-License-Identifier: GPL-3.0-or-later

module gd_x1_010
(
	input  logic        clk,
	input  logic        reset,
	input  logic        cpu_write,
	input  logic [12:0] cpu_address,
	input  logic [15:0] cpu_data,
	input  logic  [1:0] cpu_byte_enable,
	output logic [15:0] cpu_q,
	input  logic [63:0] sample_banks,

	output logic [20:0] sample_addr,
	output logic        sample_req,
	input  logic  [7:0] sample_dout,
	input  logic        sample_ack,
	output logic signed [15:0] audio_left,
	output logic signed [15:0] audio_right
);

wire [15:0] ram_q;
logic [12:0] sound_ram_address;
wire [15:0] sound_ram_q;
gd_word_ram #(.ADDR_WIDTH(13)) register_ram
(
	.clk(clk), .address(cpu_address), .data(cpu_data),
	.byte_enable(cpu_byte_enable), .write(cpu_write), .q(ram_q),
	.video_clk(clk), .video_address(sound_ram_address), .video_q(sound_ram_q)
);

// The 128 channel bytes are cached as registers so all six parameters can
// be inspected without duplicating the 8 KiB waveform/envelope RAM.
logic [7:0] channel_reg [0:127];
logic [27:0] sample_offset [0:15];
logic [27:0] envelope_offset [0:15];

always_comb begin
	cpu_q = ram_q;
	if (cpu_address < 13'h080)
		cpu_q[7:0] = channel_reg[cpu_address[6:0]];
end

// The P0-113A board clocks the X1-010 at 32.53047 MHz / 2. Its PCM mixer
// advances at clock / 512, or approximately 31.768 kHz.
localparam logic [31:0] SAMPLE_INCREMENT = 32'd2183083;
logic [31:0] sample_accumulator;
logic [32:0] sample_sum;
wire sample_tick = sample_sum[32];
always_comb sample_sum = {1'b0, sample_accumulator}
	+ {1'b0, SAMPLE_INCREMENT};

typedef enum logic [3:0] {
	S_IDLE, S_CHECK, S_PCM_WAIT, S_WAVE_ADDR, S_WAVE_FETCH,
	S_ENV_ADDR, S_ENV_FETCH, S_ADVANCE, S_FINISH
} sound_state_t;
sound_state_t state;

logic [4:0] voice;
logic signed [19:0] mix_left;
logic signed [19:0] mix_right;
logic signed [7:0] wave_sample;
logic [7:0] wave_volume;
logic [6:0] channel_base;
logic [19:0] logical_sample_address;
logic [3:0] selected_bank;
logic signed [12:0] scaled_left;
logic signed [12:0] scaled_right;

always_comb begin
	channel_base = {voice[3:0], 3'b000};
	logical_sample_address = {channel_reg[channel_base + 7'd4], 12'd0}
		+ sample_offset[voice[3:0]][23:4];
	case (logical_sample_address[19:17])
		3'd0: selected_bank = sample_banks[3:0];
		3'd1: selected_bank = sample_banks[11:8];
		3'd2: selected_bank = sample_banks[19:16];
		3'd3: selected_bank = sample_banks[27:24];
		3'd4: selected_bank = sample_banks[35:32];
		3'd5: selected_bank = sample_banks[43:40];
		3'd6: selected_bank = sample_banks[51:48];
		default: selected_bank = sample_banks[59:56];
	endcase
	// VOL_BASE / 256 is approximately 2.13. A factor of two gives the
	// hardware mix headroom and matches MAME closely without a large divider.
	scaled_left = $signed(wave_sample)
		* $signed({1'b0, channel_reg[channel_base + 7'd1][7:4]}) * 2;
	scaled_right = $signed(wave_sample)
		* $signed({1'b0, channel_reg[channel_base + 7'd1][3:0]}) * 2;
end

function automatic signed [15:0] saturate16;
	input signed [19:0] value;
	begin
		if (value > 20'sd32767) saturate16 = 16'sh7fff;
		else if (value < -20'sd32768) saturate16 = -16'sh8000;
		else saturate16 = value[15:0];
	end
endfunction

integer n;
always_ff @(posedge clk) begin
	sample_accumulator <= sample_sum[31:0];
	if (reset) begin
		sample_accumulator <= 32'd0;
		state <= S_IDLE;
		voice <= 5'd0;
		mix_left <= 20'sd0;
		mix_right <= 20'sd0;
		wave_sample <= 8'sd0;
		wave_volume <= 8'd0;
		sound_ram_address <= 13'd0;
		sample_addr <= 21'd0;
		sample_req <= 1'b0;
		audio_left <= 16'sd0;
		audio_right <= 16'sd0;
		for (n = 0; n < 128; n = n + 1) channel_reg[n] <= 8'd0;
		for (n = 0; n < 16; n = n + 1) begin
			sample_offset[n] <= 28'd0;
			envelope_offset[n] <= 28'd0;
		end
	end
	else begin
		if (cpu_write && (cpu_address < 13'h080) && cpu_byte_enable[0]) begin
			if ((cpu_address[2:0] == 3'd0)
			    && !channel_reg[cpu_address[6:0]][0] && cpu_data[0]) begin
				sample_offset[cpu_address[6:3]] <= 28'd0;
				envelope_offset[cpu_address[6:3]] <= 28'd0;
			end
			channel_reg[cpu_address[6:0]] <= cpu_data[7:0];
		end

		case (state)
			S_IDLE: if (sample_tick) begin
				voice <= 5'd0;
				mix_left <= 20'sd0;
				mix_right <= 20'sd0;
				state <= S_CHECK;
			end

			S_CHECK: begin
				if (voice == 5'd16) state <= S_FINISH;
				else if (!channel_reg[channel_base][0]) state <= S_ADVANCE;
				else if (!channel_reg[channel_base][1]) begin
					if (logical_sample_address >=
					    ({12'd0, (8'h00 - channel_reg[channel_base + 7'd5])} << 12)) begin
						channel_reg[channel_base][0] <= 1'b0;
						state <= S_ADVANCE;
					end
					else begin
						sample_addr <= {selected_bank, logical_sample_address[16:0]};
						sample_req <= ~sample_req;
						state <= S_PCM_WAIT;
					end
				end
				else begin
					sound_ram_address <= 13'h1000
						+ {channel_reg[channel_base + 7'd1], 7'd0}
						+ sample_offset[voice[3:0]][16:10];
					state <= S_WAVE_ADDR;
				end
			end

			S_PCM_WAIT: if (sample_ack == sample_req) begin
				wave_sample <= sample_dout;
				// Use the returned byte directly because nonblocking assignment
				// would otherwise mix the previous voice's sample.
				mix_left <= mix_left + $signed(sample_dout)
					* $signed({1'b0, channel_reg[channel_base + 7'd1][7:4]}) * 2;
				mix_right <= mix_right + $signed(sample_dout)
					* $signed({1'b0, channel_reg[channel_base + 7'd1][3:0]}) * 2;
				sample_offset[voice[3:0]] <= sample_offset[voice[3:0]]
					+ (channel_reg[channel_base][7]
					? {21'd0, channel_reg[channel_base + 7'd2][7:1]}
					: {20'd0, channel_reg[channel_base + 7'd2]});
				state <= S_ADVANCE;
			end

			S_WAVE_ADDR: state <= S_WAVE_FETCH;
			S_WAVE_FETCH: begin
				wave_sample <= sound_ram_q[7:0];
				sound_ram_address <= {channel_reg[channel_base + 7'd5], 7'd0}
					+ envelope_offset[voice[3:0]][16:10];
				state <= S_ENV_ADDR;
			end
			S_ENV_ADDR: state <= S_ENV_FETCH;
			S_ENV_FETCH: begin
				wave_volume <= sound_ram_q[7:0];
				mix_left <= mix_left + $signed(wave_sample)
					* $signed({1'b0, sound_ram_q[7:4]}) * 2;
				mix_right <= mix_right + $signed(wave_sample)
					* $signed({1'b0, sound_ram_q[3:0]}) * 2;
				sample_offset[voice[3:0]] <= sample_offset[voice[3:0]]
					+ ({channel_reg[channel_base + 7'd3],
						channel_reg[channel_base + 7'd2]} >> channel_reg[channel_base][7]);
				envelope_offset[voice[3:0]] <= envelope_offset[voice[3:0]]
					+ channel_reg[channel_base + 7'd4];
				if (channel_reg[channel_base][2]
				    && (envelope_offset[voice[3:0]][17:10] >= 8'h80))
					channel_reg[channel_base][0] <= 1'b0;
				state <= S_ADVANCE;
			end

			S_ADVANCE: begin
				voice <= voice + 5'd1;
				state <= S_CHECK;
			end
			S_FINISH: begin
				audio_left <= saturate16(mix_left);
				audio_right <= saturate16(mix_right);
				state <= S_IDLE;
			end
			default: state <= S_IDLE;
		endcase
	end
end

endmodule
