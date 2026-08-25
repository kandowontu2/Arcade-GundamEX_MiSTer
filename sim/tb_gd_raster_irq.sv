`timescale 1ns/1ps

module tb_gd_raster_irq;
logic clk = 1'b0;
logic reset = 1'b1;
logic ce_pix = 1'b0;
logic [8:0] h_count = 9'd0;
logic [8:0] v_count = 9'd0;
logic enable = 1'b0;
logic [8:0] position = 9'd0;
logic rearm = 1'b0;
logic irq;

always #5 clk = ~clk;

gd_raster_irq dut(.*);

task automatic pixel(input integer v, input integer h);
begin
	@(negedge clk);
	v_count = v;
	h_count = h;
	ce_pix = 1'b1;
	@(negedge clk);
	ce_pix = 1'b0;
end
endtask

task automatic program_rearm(input integer v, input integer h);
begin
	@(negedge clk);
	v_count = v;
	h_count = h;
	rearm = 1'b1;
	@(negedge clk);
	rearm = 1'b0;
end
endtask

initial begin
	repeat (2) @(negedge clk);
	reset = 1'b0;
	enable = 1'b1;
	position = 9'd5;

	pixel(5, 0);
	if (!irq) $fatal(1, "programmed line did not assert raster IRQ");
	pixel(5, 1);
	if (irq) $fatal(1, "base raster IRQ lasted more than one pixel event");

	// P0-113A software can write line zero again from its first handler. The
	// still-active source must queue another interrupt immediately; the CPU's
	// interrupt mask defers its service until the current handler returns.
	program_rearm(5, 80);
	if (!irq) $fatal(1, "same-line raster IRQ was not retriggered");
	pixel(5, 81);
	if (irq) $fatal(1, "same-line raster retrigger lasted too long");

	// A write for a future line must use the ordinary line comparator and
	// must not accidentally create a current-line delayed event.
	enable = 1'b1;
	position = 9'd12;
	program_rearm(10, 20);
	if (irq) $fatal(1, "future raster position created a retrigger");
	pixel(12, 0);
	if (!irq) $fatal(1, "future raster position did not assert normally");

	$display("gd_raster_irq: PASS");
	$finish;
end
endmodule
