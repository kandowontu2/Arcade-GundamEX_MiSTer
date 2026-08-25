`timescale 1ns/1ps

module tb_gd_rowscroll_history;
logic clk=0; always #5 clk=~clk;
logic reset=1;
logic ce_pix=0;
logic [8:0] h_count=0;
logic [8:0] v_count=0;
logic capture_enable=1;
logic [8:0] raster_position=0;
logic write=0;
logic [16:0] write_address=0;
logic [15:0] write_data=0;
logic [1:0] write_byte_enable=2'b11;
logic [8:0] lookup_line=0;
logic lookup_valid;
logic [14:0] lookup_record;
logic [15:0] lookup_data;

gd_rowscroll_history #(.VISIBLE_LINES(224)) dut(.*);

task automatic capture(input integer line, input integer address,
	input integer data);
begin
	@(negedge clk);
	raster_position=line;
	write_address=address;
	write_data=data;
	write=1;
	@(negedge clk);
	write=0;
end
endtask

task automatic swap_frame;
begin
	@(negedge clk);
	v_count=224; h_count=0; ce_pix=1;
	@(negedge clk);
	ce_pix=0;
end
endtask

initial begin
	repeat(2) @(negedge clk);
	reset=0;

	// The second line-zero handler replaces the transient first value.
	capture(0, 17'h00042, 16'h7bf2);
	capture(0, 17'h00042, 16'h7bef);
	capture(2, 17'h00042, 16'h7bf9);
	capture(64,17'h0004a, 16'h7b87);
	swap_frame();

	lookup_line=0; #1;
	if (!lookup_valid || lookup_record != 15'h0010
	    || lookup_data != 16'h7bef)
		$fatal(1, "line zero did not replay the final same-line write");
	lookup_line=1; #1;
	if (!lookup_valid || lookup_data != 16'h7bef)
		$fatal(1, "odd line did not hold its preceding even-line value");
	lookup_line=2; #1;
	if (!lookup_valid || lookup_data != 16'h7bf9)
		$fatal(1, "line two replay mismatch");
	lookup_line=64; #1;
	if (!lookup_valid || lookup_record != 15'h0012
	    || lookup_data != 16'h7b87)
		$fatal(1, "descriptor-address transition was not preserved");

	// Writes collected for the next frame must not race the frozen read bank.
	capture(0, 17'h00042, 16'h7805);
	lookup_line=0; #1;
	if (lookup_data != 16'h7bef)
		$fatal(1, "current-frame capture modified frozen history");
	swap_frame();
	lookup_line=0; #1;
	if (!lookup_valid || lookup_data != 16'h7805)
		$fatal(1, "new history was not published at frame boundary");
	lookup_line=2; #1;
	if (lookup_valid)
		$fatal(1, "stale validity survived bank reuse");

	// Non-scroll banks and partial words are deliberately ignored.
	capture(4, 17'h00043, 16'h1111);
	write_byte_enable=2'b01;
	capture(6, 17'h00042, 16'h2222);
	write_byte_enable=2'b11;
	swap_frame();
	lookup_line=4; #1;
	if (lookup_valid) $fatal(1, "non-scroll word was captured");
	lookup_line=6; #1;
	if (lookup_valid) $fatal(1, "partial scroll word was captured");

	capture_enable=0;
	lookup_line=0; #1;
	if (lookup_valid) $fatal(1, "disabled raster history remained active");

	$display("gd_rowscroll_history: PASS");
	$finish;
end
endmodule
