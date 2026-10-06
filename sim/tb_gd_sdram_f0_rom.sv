`timescale 1ns/1ps
// Adapted from Arcade-Guardians_MiSTer v1.4.1 by OpenAI Codex and kandowontu.
// SPDX-License-Identifier: GPL-3.0-or-later
// Production controller only: no diagnostic macro, sampler selector or CRC
// gate. Controlled return windows are injected tests, not board calibration.
module tb_gd_sdram_f0_rom #(parameter bit SHORT_DQ_WINDOW = 1);
localparam real HALF_PERIOD = 8.0;
localparam integer BANK_BYTES = 8192;
logic clk = 0, reset = 1;
always #(HALF_PERIOD) clk = ~clk;
tri [15:0] SDRAM_DQ;
wire [12:0] SDRAM_A;
wire [1:0] SDRAM_BA;
wire SDRAM_CLK, SDRAM_CKE, SDRAM_DQML, SDRAM_DQMH;
wire SDRAM_nCS, SDRAM_nWE, SDRAM_nCAS, SDRAM_nRAS;
logic [24:0] mem_addr = 0;
logic [15:0] mem_din = 0;
logic [1:0] mem_be = 3;
logic mem_burst = 1, mem_rnw = 0, mem_req = 0;
logic [63:0] mem_burst_data = 0;
wire [15:0] mem_dout;
wire mem_ack, ready;
logic video_dma_req = 0;
logic [24:0] video_dma_addr = 0;
wire video_dma_ack;
wire [63:0] video_dma_data;
gd_sdram dut(.*);
logic [15:0] storage [0:4*BANK_BYTES/2-1];
logic [12:0] active_row [0:3];
logic [15:0] external_dq = 16'hdead;
assign SDRAM_DQ = dut.dq_oe ? 16'hzzzz : external_dq;
integer cycle = 0, first_cycle = -100, read_word = 0, index;
integer writes = 0, reads = 0, refreshes = 0;
// The private Gundam comparison used these same synthetic windows: a word
// arrives 4 ns before the falling capture edge; narrow mode poisons it 1 ns
// afterwards. Fixed F0 must preserve scalar/DMA alignment without a selector.
always @(posedge SDRAM_CLK) begin
    cycle = cycle + 1;
    case ({SDRAM_nRAS, SDRAM_nCAS, SDRAM_nWE})
        3'b000: if (SDRAM_A !== 13'h232) $fatal(1, "CAS3/BL4 mode changed");
        3'b001: refreshes = refreshes + 1;
        3'b011: begin
            if (SDRAM_A > 7) $fatal(1, "unexpected test row %0d", SDRAM_A);
            active_row[SDRAM_BA] = SDRAM_A;
        end
        3'b100: begin
            index = {SDRAM_BA, active_row[SDRAM_BA][2:0], SDRAM_A[8:0]};
            if (!SDRAM_DQML) storage[index][7:0] = SDRAM_DQ[7:0];
            if (!SDRAM_DQMH) storage[index][15:8] = SDRAM_DQ[15:8];
            writes = writes + 1;
        end
        3'b101: begin
            read_word = {SDRAM_BA, active_row[SDRAM_BA][2:0], SDRAM_A[8:0]};
            first_cycle = cycle + 3;
            reads = reads + 1;
        end
        default: ;
    endcase
    if (cycle >= first_cycle - 1 && cycle < first_cycle + 3) begin
        external_dq <= #12 storage[read_word + cycle - first_cycle + 1];
        if (SHORT_DQ_WINDOW) external_dq <= #17 16'hdead;
    end
end
function automatic [7:0] byte_at(input integer address);
    byte_at = (address * 37) ^ (address >> 8) ^ (address >> 23) ^ 8'h5a;
endfunction
task automatic await_mem;
    integer timeout;
    begin
        timeout = 0;
        while (mem_ack != mem_req && timeout < 100) begin
            @(negedge clk); timeout = timeout + 1;
        end
        if (mem_ack != mem_req) $fatal(1, "normal access timeout");
    end
endtask
task automatic read_dma(input integer address);
    integer timeout, byte_index;
    reg [63:0] expected_row;
    begin
        @(negedge clk); video_dma_addr = address;
        video_dma_req = ~video_dma_req;
        timeout = 0;
        while (video_dma_ack != video_dma_req && timeout < 100) begin
            @(negedge clk); timeout = timeout + 1;
        end
        for (byte_index = 0; byte_index < 8; byte_index = byte_index + 1)
            expected_row[(byte_index ^ 1)*8 +: 8] = byte_at(address + byte_index);
        if (video_dma_ack != video_dma_req || video_dma_data !== expected_row)
            $fatal(1, "F0 row %h returned %h, expected %h", address, video_dma_data, expected_row);
    end
endtask
integer bank, offset, lane, address;
initial begin
    repeat (4) @(negedge clk); reset = 0;
    wait (ready);
    // Store 32 KiB across all four banks and eight physical rows per bank
    // through the unchanged four-WRITE batched loader interface.
    for (bank = 0; bank < 4; bank = bank + 1) begin
        for (offset = 0; offset < BANK_BYTES; offset = offset + 8) begin
            @(negedge clk); address = (bank << 23) + offset;
            mem_addr = address;
            for (lane = 0; lane < 8; lane = lane + 1)
                mem_burst_data[(lane ^ 1)*8 +: 8] = byte_at(address + lane);
            mem_req = ~mem_req;
            await_mem();
        end
    end
    for (bank = 0; bank < 4; bank = bank + 1)
        for (offset = 0; offset < BANK_BYTES; offset = offset + 8)
            read_dma((bank << 23) + offset);
    // Ordinary reads, not just DMA, use the fixed F0 input sample.
    for (bank = 0; bank < 4; bank = bank + 1) begin
        @(negedge clk); address = (bank << 23) + 1022;
        mem_addr = address; mem_burst = 0; mem_rnw = 1; mem_req = ~mem_req;
        await_mem();
        if (mem_dout !== {byte_at(address), byte_at(address+1)})
            $fatal(1, "normal read mismatch bank %0d: %h", bank, mem_dout);
    end
    // Restart the controller without modifying stored ROM, then read across
    // a row boundary again to check initialization and request-tag recovery.
    @(negedge clk); reset = 1; mem_req = 0; video_dma_req = 0;
    repeat (4) @(negedge clk); reset = 0;
    wait (ready);
    read_dma(1016); read_dma(1024); read_dma((3 << 23) + 1024);
    if (writes != 4*BANK_BYTES/2 || reads != 4*BANK_BYTES/8+7 || refreshes < 4)
        $fatal(1, "incomplete access coverage W=%0d R=%0d refresh=%0d", writes, reads, refreshes);
    $display("PASS production F0 32KiB, four banks, 32 physical rows, normal reads and controller reset; short=%0d", SHORT_DQ_WINDOW);
    $finish;
end
initial begin
    #20000000; $fatal(1, "production F0 test watchdog");
end
endmodule
