`timescale 1ns/1ps
// The real bundled hps_io protocol, actual Microwire writes and a host-side
// 128-byte save image. No game ROM is needed or redistributed.
module tb_gd_eeprom_nvram;
reg clk=0; always #5 clk=~clk;
reg cold_reset=1, factory_ready=0, factory_wr=0;
reg [6:0] factory_addr=0;
reg [7:0] factory_data=0;
reg chip_select=0, serial_clock=0, data_in=0;
wire data_out, restore_busy, upload_req;
wire ioctl_download, ioctl_upload, ioctl_wr, ioctl_rd;
wire [15:0] ioctl_index;
wire [26:0] ioctl_addr;
wire [7:0] ioctl_dout, ioctl_din;
tri [45:0] HPS_BUS;
tri [35:0] EXT_BUS;
reg fp_enable=0, io_enable=0, io_strobe=0;
reg [15:0] io_din=0;
assign HPS_BUS[35]=fp_enable;
assign HPS_BUS[34]=io_enable;
assign HPS_BUS[33]=io_strobe;
assign HPS_BUS[31:16]=io_din;
assign HPS_BUS[45:38]=0;
assign EXT_BUS[32]=0;
hps_io #(.CONF_STR("Gundam EX Revue;;")) hps (
    .clk_sys(clk), .HPS_BUS, .EXT_BUS,
    .ioctl_download, .ioctl_upload, .ioctl_wr, .ioctl_rd,
    .ioctl_index, .ioctl_addr, .ioctl_dout, .ioctl_din,
    .ioctl_wait(1'b0), .ioctl_upload_req(upload_req), .ioctl_upload_index(8'd4),
    .status_in(128'd0), .status_set(1'b0), .status_menumask(16'd0),
    .info_req(1'b0), .info(8'd0), .new_vmode(1'b0), .video_rotated(1'b0),
    .sd_rd(1'b0), .sd_wr(1'b0)
);
gd_eeprom_nvram dut (.*);
reg [7:0] saved [0:127];
reg [7:0] actual [0:127];
integer requests=0;
reg old_req=0;
always @(posedge clk) begin
    old_req<=upload_req;
    if (upload_req && !old_req) requests<=requests+1;
end

task send_word(input [15:0] value);
    @(negedge clk); io_din=value; io_strobe=1;
    @(negedge clk); io_strobe=0;
    repeat(3) @(negedge clk);
endtask
task end_command;
    fp_enable=0; io_enable=0;
    repeat(5) @(negedge clk);
endtask
task poll_request(input bit expected);
    io_enable=1; send_word(16'h3c);
    if(HPS_BUS[15:0] !== (expected ? 16'h0401 : 16'h0000))
        $fatal(1,"Main upload poll=%h expected request=%b",HPS_BUS[15:0],expected);
    end_command();
endtask
task set_index(input [15:0] index);
    fp_enable=1; send_word(16'h55); send_word(index); end_command();
endtask
task start_transfer(input bit up);
    fp_enable=1; send_word(16'h53); send_word(up ? 16'haa : 16'hff); end_command();
endtask
task stop_transfer;
    fp_enable=1; send_word(16'h53); send_word(0); end_command();
endtask
task host_restore(input integer count, input bit reorder, input [15:0] index);
    set_index(index); start_transfer(0);
    fp_enable=1; send_word(16'h54);
    for(integer n=0;n<count;n=n+1) begin
        if(reorder && n==64) begin
            end_command();
            // A start address overrides the next streamed address.
            fp_enable=1; send_word(16'h53); send_word(16'hff); send_word(70); send_word(0); end_command();
            fp_enable=1; send_word(16'h54);
        end
        send_word({8'd0,saved[n%128]});
    end
    end_command(); stop_transfer();
    repeat(150) @(negedge clk);
endtask
task load_factory;
    factory_ready=0;
    for(integer n=0;n<128;n=n+1) begin
        @(negedge clk); factory_wr=1; factory_addr=n; factory_data=n^8'h5a;
    end
    @(negedge clk); factory_wr=0; factory_ready=1;
    repeat(150) @(negedge clk);
endtask
task serial_bit(input bit value, input bit leave_high);
    data_in=value; serial_clock=0; repeat(2) @(negedge clk);
    serial_clock=1; repeat(2) @(negedge clk);
    if(!leave_high) begin serial_clock=0; repeat(2) @(negedge clk); end
endtask
task command(input [8:0] value);
    chip_select=0; serial_clock=0; repeat(3) @(negedge clk);
    chip_select=1; repeat(3) @(negedge clk);
    for(integer n=8;n>=0;n=n-1) serial_bit(value[n],n==0);
endtask
task finish_serial;
    chip_select=0; serial_clock=0; repeat(4) @(negedge clk);
endtask
task write_word(input [5:0] address, input [15:0] value);
    command({3'b101,address});
    for(integer n=15;n>=0;n=n-1) serial_bit(value[n],0);
    finish_serial();
endtask
task read_word(input [5:0] address, input [15:0] expected);
    reg [15:0] value;
    command({3'b110,address});
    for(integer n=15;n>=0;n=n-1) begin
        value[n]=data_out;
        serial_clock=0; repeat(2) @(negedge clk);
        if(n!=0) begin serial_clock=1; repeat(2) @(negedge clk); end
    end
    finish_serial();
    if(value!==expected) $fatal(1,"EEPROM serial read [%0d]=%h expected %h",address,value,expected);
endtask
task read_upload(input integer count);
    fp_enable=1; send_word(16'h54);
    for(integer n=0;n<count;n=n+1) begin
        send_word(0); actual[n]=HPS_BUS[7:0];
    end
    end_command();
endtask
task compare_upload;
    for(integer n=0;n<128;n=n+1)
        if(actual[n]!==saved[n]) $fatal(1,"NVRAM byte %0d=%h expected %h",n,actual[n],saved[n]);
endtask
task save_full;
    set_index(4); start_transfer(1); read_upload(128); stop_transfer();
endtask
initial begin
    for(integer n=0;n<128;n=n+1) saved[n]=n^8'hc3;
    repeat(8) @(negedge clk); cold_reset=0;
    // Missing save: factory image still boots; reads and locked writes do not dirty it.
    load_factory(); read_word(0,16'h5a5b);
    write_word(0,16'h1234); read_word(0,16'h5a5b);
    if(upload_req) $fatal(1,"Locked WRITE dirtied EEPROM");
    command(9'b100110000); finish_serial(); // EWEN
    write_word(0,16'h1234); read_word(0,16'h1234);
    if(!upload_req) $fatal(1,"EEPROM WRITE did not request persistence");
    poll_request(1); poll_request(0);
    // Warm game reset is intentionally not connected to this block.
    // An incomplete upload cannot clear dirty state; unrelated channels cannot either.
    set_index(4); start_transfer(1); read_upload(12); stop_transfer();
    if(!upload_req) $fatal(1,"Short upload cleared dirty state");
    set_index(255); start_transfer(1); read_upload(128); stop_transfer();
    if(!upload_req) $fatal(1,"Cheat channel acknowledged EEPROM save");
    save_full();
    if(upload_req) $fatal(1,"Full upload did not acknowledge EEPROM save");
    for(integer n=0;n<128;n=n+1) saved[n]=n^8'h5a;
    saved[0]=8'h12; saved[1]=8'h34; compare_upload();
    // Start another upload, then change a later byte. The first save remains
    // byte-exact to its start snapshot and the later generation stays dirty.
    set_index(4); start_transfer(1);
    write_word(63,16'habcd);
    read_upload(128); stop_transfer(); compare_upload();
    if(!upload_req) $fatal(1,"Write during upload was lost");
    poll_request(1); // real hps_io edge latch must rearm too
    saved[126]=8'hab; saved[127]=8'hcd;
    save_full(); compare_upload();
    if(upload_req) $fatal(1,"Second generation not acknowledged");
    // A cold reload loses on-chip contents: host save MUST override all 128
    // later factory bytes (including the very last one) before CPU release.
    cold_reset=1; factory_ready=0; repeat(5) @(negedge clk); cold_reset=0;
    host_restore(128,0,4);
    if(!restore_busy) $fatal(1,"Early restore was not held for factory replay");
    load_factory();
    if(restore_busy || upload_req) $fatal(1,"Restore stuck or spuriously dirty");
    read_word(0,16'h1234); read_word(63,16'habcd);
    save_full(); compare_upload();
    // Late restore and malformed transfers, all protected by staging.
    saved[0]=8'h86; saved[1]=8'h42;
    host_restore(127,0,4); read_word(0,16'h1234);
    host_restore(129,0,4); read_word(0,16'h1234);
    host_restore(128,1,4); read_word(0,16'h1234);
    host_restore(128,0,254); read_word(0,16'h1234);
    host_restore(128,0,255); read_word(0,16'h1234);
    host_restore(128,0,0); read_word(0,16'h1234);
    host_restore(128,0,4); read_word(0,16'h8642);
    if(upload_req) $fatal(1,"Host restore requested writeback");
    // Every supported mutation reports dirty, including mass erase/write.
    command(9'b100110000); finish_serial();
    command({3'b111,6'd0}); finish_serial(); read_word(0,16'hffff);
    if(!upload_req) $fatal(1,"ERASE not dirty"); save_full();
    command(9'b100010000);
    for(integer n=15;n>=0;n=n-1) serial_bit(16'hbeef >> n,0);
    finish_serial(); read_word(0,16'hbeef); read_word(63,16'hbeef);
    if(!upload_req) $fatal(1,"WRAL not dirty"); save_full();
    command(9'b100100000); finish_serial(); read_word(0,16'hffff); read_word(63,16'hffff);
    if(!upload_req) $fatal(1,"ERAL not dirty"); save_full();
    if(upload_req) $fatal(1,"Final save not acknowledged");
    command(9'b100000000); finish_serial(); write_word(0,16'h4321);
    if(upload_req) $fatal(1,"EWDS failed");
    if(requests<4) $fatal(1,"Save request was not rearmed after prior uploads");
    $display("PASS gd_eeprom_nvram real HPS roundtrip, factory ordering, dirty/snapshot, all writes, malformed isolation");
    $finish;
end
initial begin #4000000; $fatal(1,"NVRAM timeout"); end
endmodule
