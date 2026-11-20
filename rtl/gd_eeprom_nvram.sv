// 128-byte 93C46 persistence using MiSTer's standard arcade NVRAM channel.
// OpenAI Codex and kandowontu; SPDX-License-Identifier: GPL-3.0-or-later
// Main may send index 4 before the fast ROM replay has loaded the factory
// EEPROM. Stage a complete image, then apply it after factory_ready. Index 0
// (ROM), 254 (DIPs) and 255 (cheats) are never interpreted as NVRAM.
module gd_eeprom_nvram (
	input wire clk, cold_reset, factory_ready,
	input wire factory_wr,
	input wire [6:0] factory_addr,
	input wire [7:0] factory_data,
	input wire ioctl_download, ioctl_upload, ioctl_wr, ioctl_rd,
	input wire [15:0] ioctl_index,
	input wire [26:0] ioctl_addr,
	input wire [7:0] ioctl_dout,
	output wire [7:0] ioctl_din,
	output wire upload_req,
	output wire restore_busy,
	input wire chip_select, serial_clock, data_in,
	output wire data_out
);
wire download = ioctl_download && (ioctl_index == 16'd4);
wire upload = ioctl_upload && (ioctl_index == 16'd4);
reg download_d = 0, upload_d = 0;
(* ramstyle = "MLAB" *) reg [7:0] restore_image [0:127];
reg [7:0] received = 0;
reg malformed = 0, restore_pending = 0, restoring = 0;
reg [6:0] restore_addr = 0;
reg dirty = 0, changed_during_upload = 0, upload_complete = 0;
wire wrote;
wire [7:0] save_data;
wire restore_wr = restoring && factory_ready && !factory_wr && !download;
assign restore_busy = download || download_d || restore_pending || restoring;
assign upload_req = dirty && factory_ready && !restore_busy && !upload;
assign ioctl_din = (upload && ioctl_addr < 27'd128) ? save_data : 8'd0;

gd_93c46 eeprom (
	.clk, .reset(cold_reset || !factory_ready || restore_busy),
	.load_wr(factory_wr || restore_wr),
	.load_addr(factory_wr ? factory_addr : restore_addr),
	.load_data(factory_wr ? factory_data : restore_image[restore_addr]),
	.save_snapshot(upload && !upload_d), .save_addr(ioctl_addr[6:0]),
	.save_data, .wrote, .chip_select, .serial_clock, .data_in, .data_out
);

always @(posedge clk) begin
	download_d <= download;
	upload_d <= upload;
	if (cold_reset) begin
		download_d <= 0; upload_d <= 0;
		received <= 0; malformed <= 0;
		restore_pending <= 0; restoring <= 0; restore_addr <= 0;
		dirty <= 0; changed_during_upload <= 0; upload_complete <= 0;
	end else begin
		if (download && !download_d) begin
			received <= 0;
			malformed <= 0;
			restore_pending <= 0;
		end
		if (download && ioctl_wr) begin
			if (received < 8'd128 && ioctl_addr == {19'd0, received}) begin
				restore_image[received[6:0]] <= ioctl_dout;
				received <= received + 1'b1;
			end else malformed <= 1;
		end
		// The HPS stop command increments ioctl_addr; count accepted writes
		// instead, just as the ROM adaptor does. Reject short/reordered data.
		if (!download && download_d && received == 8'd128 && !malformed)
			restore_pending <= 1;
		if (restore_pending && factory_ready && !download) begin
			restore_pending <= 0;
			restoring <= 1;
			restore_addr <= 0;
		end
		if (restore_wr) begin
			if (restore_addr == 7'd127) restoring <= 0;
			else restore_addr <= restore_addr + 1'b1;
		end

		if (upload && !upload_d) begin
			changed_during_upload <= 0;
			upload_complete <= 0;
		end
		// hps_io prefetches address zero on upload start and advances once
		// per byte read. Address 128 is reached after all 128 bytes were read.
		if (upload && ioctl_rd && ioctl_addr == 27'd128) upload_complete <= 1;
		if (!upload && upload_d && upload_complete && !changed_during_upload)
			dirty <= 0;
		if (factory_wr || restore_wr) dirty <= 0;
		if (wrote) begin
			dirty <= 1;
			if (upload || upload_d) changed_during_upload <= 1;
		end
	end
end
endmodule
