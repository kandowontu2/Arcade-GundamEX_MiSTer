// TMP68301 interrupt-controller and essential internal-register subset.
// Behaviour follows MAME's BSD-licensed TMP68301 device model. Timer 1 is
// implemented for the P0-113A board's housekeeping interrupt.
// The unused serial channels and timers 0/2 expose their reset/status values.
// SPDX-License-Identifier: GPL-3.0-or-later

module gd_tmp68301
(
	input  logic        clk,
	input  logic        reset,
	input  logic        cpu_ce,
	input  logic        cs,
	input  logic        write,
	input  logic  [9:0] address,
	input  logic [15:0] data,
	input  logic  [1:0] byte_enable,
	output logic [15:0] q,
	input  logic [15:0] parallel_in,
	output logic [15:0] parallel_out,

	input  logic        ext_irq0,
	input  logic        ext_irq1,
	input  logic        iack,
	output logic  [2:0] irq_level,
	output logic  [7:0] irq_vector
);

logic [7:0] icr [0:9];
logic [10:0] imr;
logic [10:0] ipr;
logic [10:0] iisr;
logic  [7:0] ivnr;
logic  [7:0] ieir;
logic  [1:0] ext_irq_d;
logic  [3:0] chosen_slot;
logic  [4:0] chosen_vector;
logic [15:0] tcr1;
logic [15:0] tmcr11;
logic [15:0] tmcr12;
logic [15:0] tctr1;
logic  [7:0] timer1_prescaler;
logic [15:0] pdir;
logic [15:0] pdr;
logic  [7:0] pcr;
logic [15:0] pmr;

wire [1:0] ext_irq = {ext_irq1, ext_irq0};

function automatic [15:0] merge_word;
	input [15:0] old_value;
	input [15:0] new_value;
	input  [1:0] enables;
	begin
		merge_word = old_value;
		if (enables[1]) merge_word[15:8] = new_value[15:8];
		if (enables[0]) merge_word[7:0]  = new_value[7:0];
	end
endfunction

integer n;
always_comb begin
	irq_level = 3'd0;
	chosen_slot = 4'd15;
	chosen_vector = 5'h1f;
	// External interrupt 0 wins an equal-level tie, matching TMP68301
	// priority ordering. Only ext0/ext1 are wired by this core.
	if (ipr[0] && !imr[0] && (icr[0][2:0] >= irq_level)
	    && (icr[0][2:0] != 3'd0)) begin
		irq_level = icr[0][2:0];
		chosen_slot = 4'd0;
		chosen_vector = 5'd0;
	end
	if (ipr[1] && !imr[1] && (icr[1][2:0] > irq_level)) begin
		irq_level = icr[1][2:0];
		chosen_slot = 4'd1;
		chosen_vector = 5'd1;
	end
	// Internal timer 1 is interrupt slot 9 and automatic vector 5. External
	// inputs win equal-level ties according to the TMP68301 priority table.
	if (ipr[9] && !imr[9] && (icr[8][2:0] > irq_level)) begin
		irq_level = icr[8][2:0];
		chosen_slot = 4'd9;
		chosen_vector = 5'd5;
	end
	irq_vector = ivnr | {3'd0, chosen_vector};
end

always_comb begin
	q = 16'hffff;
	case (address[9:0])
		10'h000: q = 16'h00ff; // AMAR0/AAMR0
		10'h002: q = 16'hff3d; // AAMR0/AACR0
		10'h004: q = 16'h00ff; // AMAR1/AAMR1
		10'h006: q = 16'hff18; // AAMR1/AACR1
		10'h008: q = 16'hff18; // AACR2
		10'h00a: q = 16'hff08; // ATOR
		10'h00c: q = 16'hfffc; // ARELR
		10'h080, 10'h082, 10'h084, 10'h086, 10'h088,
		10'h08a, 10'h08c, 10'h08e, 10'h090, 10'h092:
			q = {8'hff, icr[address[4:1]]};
		10'h094: q = {5'd0, imr};
		10'h096: q = {5'd0, ipr};
		10'h098: q = {5'd0, iisr};
		10'h09a: q = {ivnr, ivnr}; // IVNR at odd byte 9b
		10'h09c: q = {ieir, ieir}; // IEIR at odd byte 9d
		10'h100: q = pdir;
		10'h102: q = {8'hff, pcr};
		10'h104: q = 16'hff40; // PSR
		10'h106: q = 16'hff00; // PCMR
		10'h108: q = pmr;
		10'h10a: q = (pdr & pdir) | (parallel_in & ~pdir);
		10'h180: q = 16'hff30; // serial reset/status group
		10'h186, 10'h196, 10'h1a6: q = 16'hff04; // SSR: TX empty
		10'h200: q = 16'h0052; // timer 0 reset control
		10'h220: q = tcr1;
		10'h224: q = tmcr11;
		10'h228: q = tmcr12;
		10'h22c: q = tctr1;
		10'h240: q = 16'h0012; // timer 2 reset control
		10'h204, 10'h20c, 10'h244, 10'h248, 10'h24c: q = 16'h0000;
		default: q = 16'hffff;
	endcase
	if (!cs) q = 16'hffff;
end

always_comb parallel_out = pdr & pdir;

always_ff @(posedge clk) begin
	ext_irq_d <= ext_irq;
	if (reset) begin
		for (n = 0; n < 10; n = n + 1)
			icr[n] <= 8'h07;
		imr <= 11'h7f7;
		ipr <= 11'd0;
		iisr <= 11'd0;
		ivnr <= 8'd0;
		ieir <= 8'd0;
		ext_irq_d <= 2'd0;
		tcr1 <= 16'h0012;
		tmcr11 <= 16'd0;
		tmcr12 <= 16'd0;
		tctr1 <= 16'd0;
		timer1_prescaler <= 8'd0;
		pdir <= 16'd0;
		pdr <= 16'd0;
		pcr <= 8'd0;
		pmr <= 16'd0;
	end
	else begin
		// Timer 1 supports the internal-clock, repeating maximum-1 mode used
		// by P0-113A software. P values 8-15 all divide by 256 on the TMP68301.
		if (!tcr1[0]) begin
			tctr1 <= 16'd0;
			timer1_prescaler <= 8'd0;
		end
		else if (cpu_ce && !tcr1[1] && (tcr1[15:14] == 2'd0)) begin
			timer1_prescaler <= timer1_prescaler + 8'd1;
			if ((tcr1[13:10] == 4'd0)
			    || ((tcr1[13:10] == 4'd1) && timer1_prescaler[0])
			    || ((tcr1[13:10] == 4'd2) && (&timer1_prescaler[1:0]))
			    || ((tcr1[13:10] == 4'd3) && (&timer1_prescaler[2:0]))
			    || ((tcr1[13:10] == 4'd4) && (&timer1_prescaler[3:0]))
			    || ((tcr1[13:10] == 4'd5) && (&timer1_prescaler[4:0]))
			    || ((tcr1[13:10] == 4'd6) && (&timer1_prescaler[5:0]))
			    || ((tcr1[13:10] == 4'd7) && (&timer1_prescaler[6:0]))
			    || ((tcr1[13:10] >= 4'd8) && (&timer1_prescaler))) begin
				if ((tcr1[5:4] == 2'd1)
				    && (tctr1 == ((tmcr11 == 16'd0)
				    ? 16'hffff : tmcr11 - 16'd1))) begin
					tctr1 <= 16'd0;
					if (tcr1[2]) ipr[9] <= 1'b1;
				end
				else tctr1 <= tctr1 + 16'd1;
			end
		end

		// The MAME device treats an asserted input as the active state for
		// level mode and its rising transition as the event for edge mode.
		for (n = 0; n < 2; n = n + 1) begin
			if (icr[n][3]) begin
				if (ext_irq[n]) ipr[n] <= 1'b1;
				else ipr[n] <= 1'b0;
			end
			else if (ext_irq[n] && !ext_irq_d[n])
				ipr[n] <= 1'b1;
		end

		if (iack && (chosen_slot != 4'd15)) begin
			iisr[chosen_slot] <= 1'b1;
			if ((chosen_slot >= 4'd2) || !icr[chosen_slot][3])
				ipr[chosen_slot] <= 1'b0;
		end

		if (cs && write) begin
			if ((address >= 10'h080) && (address <= 10'h093)
			    && !address[0] && byte_enable[0]) begin
				if (address[4:1] < 10)
					icr[address[4:1]] <= (address[4:1] < 3)
						? (data[7:0] & 8'h1f) : (data[7:0] & 8'h07);
			end
			case (address)
				10'h100: pdir <= merge_word(pdir, data, byte_enable);
				10'h102: if (byte_enable[0]) pcr <= data[7:0] & 8'h0f;
				10'h108: pmr <= merge_word(pmr, data, byte_enable);
				10'h10a: pdr <= merge_word(pdr, data, byte_enable);
				10'h094: begin
					if (byte_enable[1]) imr[10:8] <= data[10:8];
					if (byte_enable[0]) begin
						imr[7:4] <= data[7:4];
						imr[3] <= 1'b0;
						imr[2:0] <= data[2:0];
					end
				end
				// TMP68301 clearing semantics: writing zero clears pending
				// or in-service bits; writing one preserves them.
				10'h096: begin
					if (byte_enable[1]) ipr[10:8] <= ipr[10:8] & data[10:8];
					if (byte_enable[0]) ipr[7:0] <= ipr[7:0] & data[7:0];
				end
				10'h098: begin
					if (byte_enable[1]) iisr[10:8] <= iisr[10:8] & data[10:8];
					if (byte_enable[0]) iisr[7:0] <= iisr[7:0] & data[7:0];
				end
				10'h09a: if (byte_enable[0]) ivnr <= data[7:0] & 8'he0;
				10'h09c: if (byte_enable[0]) ieir <= data[7:0] & 8'h7f;
				10'h220: begin
					tcr1 <= merge_word(tcr1, data, byte_enable) & 16'hfff7;
					if (!(byte_enable[0] ? data[0] : tcr1[0])) begin
						tctr1 <= 16'd0;
						timer1_prescaler <= 8'd0;
					end
				end
				10'h224: tmcr11 <= merge_word(tmcr11, data, byte_enable);
				10'h228: tmcr12 <= merge_word(tmcr12, data, byte_enable);
				10'h22c: begin
					tctr1 <= 16'd0;
					timer1_prescaler <= 8'd0;
				end
				default: ;
			endcase
		end
	end
end

endmodule
