`timescale 1ns/1ps
// Isolated integration shell. The framebuffer and vendor RAMs are unmodified.
module video_ddr_probe (
    input clk, rst_n, ddr_init_done, acc_rst_n,
    input vin_clk, wr_fsync, wr_en,
    input [15:0] wr_data,
    input vout_clk, rd_fsync, rd_en,
    output init_done, vout_de,
    output [15:0] vout_data,
    input mem_req_valid, mem_req_write,
    output mem_req_ready,
    input [31:0] mem_req_addr,
    input [127:0] mem_req_data,
    input [15:0] mem_req_strb,
    input [63:0] mem_req_tag,
    output mem_rsp_valid,
    input mem_rsp_ready,
    output [127:0] mem_rsp_data,
    output [63:0] mem_rsp_tag,
    output mem_rsp_error, fault, idle,
    output axi_awvalid,
    input axi_awready,
    output [27:0] axi_awaddr,
    output [3:0] axi_awuser_id, axi_awlen,
    output axi_awuser_ap,
    output [255:0] axi_wdata,
    output [31:0] axi_wstrb,
    input axi_wready, axi_wusero_last,
    input [3:0] axi_wusero_id,
    output axi_arvalid,
    input axi_arready,
    output [27:0] axi_araddr,
    output [3:0] axi_aruser_id, axi_arlen,
    output axi_aruser_ap,
    input [255:0] axi_rdata,
    input [3:0] axi_rid,
    input axi_rvalid, axi_rlast
);
wire v_awvalid, v_awready, v_arvalid, v_arready;
wire [27:0] v_awaddr, v_araddr;
wire [3:0] v_awid, v_awlen, v_arid, v_arlen, v_wid, v_rid;
wire [255:0] v_wdata, v_rdata;
wire [31:0] v_wstrb;
wire v_wready, v_wlast, v_rvalid, v_rlast;
wire v_awap=1'b0, v_arap=1'b0;
wire video_reset_n=rst_n && ddr_init_done && !fault;
fram_buf video (
    .ddr_clk(clk), .ddr_rstn(video_reset_n),
    .vin_clk(vin_clk), .wr_fsync(wr_fsync), .wr_en(wr_en), .wr_data(wr_data),
    .vout_clk(vout_clk), .rd_fsync(rd_fsync), .rd_en(rd_en),
    .vout_de(vout_de), .vout_data(vout_data), .init_done(init_done),
    .axi_awaddr(v_awaddr), .axi_awid(v_awid), .axi_awlen(v_awlen),
    .axi_awsize(), .axi_awburst(), .axi_awvalid(v_awvalid), .axi_awready(v_awready),
    .axi_wdata(v_wdata), .axi_wstrb(v_wstrb), .axi_wlast(v_wlast),
    .axi_wvalid(), .axi_wready(v_wready), .axi_bid(4'd0),
    .axi_araddr(v_araddr), .axi_arid(v_arid), .axi_arlen(v_arlen),
    .axi_arsize(), .axi_arburst(), .axi_arvalid(v_arvalid), .axi_arready(v_arready),
    .axi_rready(), .axi_rdata(v_rdata), .axi_rvalid(v_rvalid),
    .axi_rlast(v_rlast), .axi_rid(v_rid)
);
road_ddr_bridge bridge(.*);
endmodule
