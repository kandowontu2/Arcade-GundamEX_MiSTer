`timescale 1ns/1ps
module tb_gd_tmp68301;
logic clk=0; always #5 clk=~clk;
logic reset=1;
logic cpu_ce=0;
logic cs=0;
logic write=0;
logic [9:0] address=0;
logic [15:0] data=0;
logic [1:0] byte_enable=0;
logic [15:0] q;
logic ext_irq0=0;
logic ext_irq1=0;
logic iack=0;
logic [15:0] parallel_in=0;
logic [15:0] parallel_out;
logic [2:0] irq_level;
logic [7:0] irq_vector;

gd_tmp68301 dut(.*);

task automatic write_word(input [9:0] a, input [15:0] d);
begin
	@(posedge clk);
	cs <= 1; write <= 1; address <= a; data <= d; byte_enable <= 2'b11;
	@(posedge clk);
	cs <= 0; write <= 0; byte_enable <= 0;
end
endtask

integer i;
initial begin
	repeat(4) @(posedge clk);
	reset <= 0;
	// Timer 1 is ICR register 8, interrupt slot 9, automatic vector 5.
	write_word(10'h090, 16'h0004);
	write_word(10'h094, 16'h0000);
	write_word(10'h09a, 16'h0040);
	write_word(10'h224, 16'h0004);
	// Internal clock, divide 1, repeat, max-1, IRQ enabled, running/start.
	write_word(10'h220, 16'h0095);
	for(i=0;i<4;i=i+1) begin
		@(posedge clk); cpu_ce <= 1;
		@(posedge clk); cpu_ce <= 0;
	end
	@(posedge clk);
	if(irq_level !== 3'd4 || irq_vector !== 8'h45)
		$fatal(1,"timer irq level/vector %0d/%h",irq_level,irq_vector);
	iack <= 1;
	@(posedge clk); iack <= 0;
	@(posedge clk);
	if(irq_level !== 3'd0)
		$fatal(1,"timer irq did not clear on acknowledge");
	$display("PASS gd_tmp68301 generated and acknowledged timer-1 vector 45");
	$finish;
end
initial begin #20000; $fatal(1,"timeout"); end
endmodule
