`timescale 1ns/1ps
// Test-only multiplexed synthesis shell. This is not a board pin assignment.
module ddr_layer_probe(
    input clk, rst_n, acc_rst_n, ddr_init_done,
    input [7:0] command,
    input [127:0] payload,
    input [5:0] native_flags,
    input [4:0] select,
    output [31:0] observe
);
reg [319:0] descriptor;
reg [255:0] rdata, video_data;
reg [95:0] ports;
wire cfg_ready, busy, layer_fault, done, fault, idle;
wire [7:0] fault_code;
wire [31:0] result_job_id;
wire mem_req_valid, mem_req_ready, mem_req_write, mem_rsp_valid, mem_rsp_ready, mem_rsp_error;
wire [31:0] mem_req_addr;
wire [127:0] mem_req_data, mem_rsp_data;
wire [15:0] mem_req_strb;
wire [63:0] mem_req_tag, mem_rsp_tag;
wire v_awready, v_arready, v_wready, v_wlast, v_rvalid, v_rlast;
wire [3:0] v_wid, v_rid;
wire [255:0] v_rdata;
wire axi_awvalid, axi_arvalid, axi_awuser_ap, axi_aruser_ap;
wire [27:0] axi_awaddr, axi_araddr;
wire [3:0] axi_awuser_id, axi_awlen, axi_aruser_id, axi_arlen;
wire [255:0] axi_wdata;
wire [31:0] axi_wstrb;
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin descriptor<=0; rdata<=0; video_data<=0; ports<=0; end
    else begin
        if(command[1] && cfg_ready) descriptor<={payload[31:0],descriptor[319:32]};
        if(command[2]) ports<=payload[95:0];
        if(command[3]) rdata<={payload,rdata[255:128]};
        if(command[6]) video_data<={payload,video_data[255:128]};
    end
end
conv_layer_dma engine(
    .clk(clk),.rst_n(rst_n && acc_rst_n),
    .cfg_valid(command[0] && !command[1]),.cfg_ready(cfg_ready),.cfg_descriptor(descriptor),
    .busy(busy),.fault(layer_fault),.fault_code(fault_code),.done(done),.result_job_id(result_job_id),
    .mem_req_valid(mem_req_valid),.mem_req_ready(mem_req_ready),.mem_req_write(mem_req_write),
    .mem_req_addr(mem_req_addr),.mem_req_data(mem_req_data),.mem_req_strb(mem_req_strb),.mem_req_tag(mem_req_tag),
    .mem_rsp_valid(mem_rsp_valid),.mem_rsp_ready(mem_rsp_ready),.mem_rsp_data(mem_rsp_data),
    .mem_rsp_tag(mem_rsp_tag),.mem_rsp_error(mem_rsp_error));
road_ddr_bridge bridge(
    .clk(clk),.rst_n(rst_n),.ddr_init_done(ddr_init_done),.acc_rst_n(acc_rst_n),
    .mem_req_valid(mem_req_valid),.mem_req_ready(mem_req_ready),.mem_req_write(mem_req_write),
    .mem_req_addr(mem_req_addr),.mem_req_data(mem_req_data),.mem_req_strb(mem_req_strb),.mem_req_tag(mem_req_tag),
    .mem_rsp_valid(mem_rsp_valid),.mem_rsp_ready(mem_rsp_ready),.mem_rsp_data(mem_rsp_data),
    .mem_rsp_tag(mem_rsp_tag),.mem_rsp_error(mem_rsp_error),.fault(fault),.idle(idle),
    .v_awvalid(command[4]),.v_awready(v_awready),.v_awaddr(ports[27:0]),.v_awid(ports[31:28]),
    .v_awlen(ports[35:32]),.v_awap(ports[36]),.v_wdata(video_data),.v_wstrb(payload[31:0]),
    .v_wready(v_wready),.v_wlast(v_wlast),.v_wid(v_wid),
    .v_arvalid(command[5]),.v_arready(v_arready),.v_araddr(ports[64:37]),.v_arid(ports[68:65]),
    .v_arlen(ports[72:69]),.v_arap(ports[73]),
    .v_rdata(v_rdata),.v_rid(v_rid),.v_rvalid(v_rvalid),.v_rlast(v_rlast),
    .axi_awvalid(axi_awvalid),.axi_awready(native_flags[0]),.axi_awaddr(axi_awaddr),
    .axi_awuser_id(axi_awuser_id),.axi_awlen(axi_awlen),.axi_awuser_ap(axi_awuser_ap),
    .axi_wdata(axi_wdata),.axi_wstrb(axi_wstrb),.axi_wready(native_flags[1]),
    .axi_wusero_last(native_flags[2]),.axi_wusero_id(ports[77:74]),
    .axi_arvalid(axi_arvalid),.axi_arready(native_flags[3]),.axi_araddr(axi_araddr),
    .axi_aruser_id(axi_aruser_id),.axi_arlen(axi_arlen),.axi_aruser_ap(axi_aruser_ap),
    .axi_rdata(rdata),.axi_rid(ports[81:78]),.axi_rvalid(native_flags[4]),.axi_rlast(native_flags[5]));
assign observe = select==0 ? {16'd0,fault_code,idle,fault,layer_fault,done,busy,cfg_ready,mem_req_valid,mem_rsp_valid} :
    select==1 ? {24'd0,v_awready,v_arready,v_wready,v_wlast,v_rvalid,v_rlast,axi_awvalid,axi_arvalid} :
    select==2 ? {4'd0,axi_awaddr} : select==3 ? {4'd0,axi_araddr} :
    select==4 ? {4'd0,axi_awuser_ap,axi_aruser_ap,axi_awlen,axi_arlen,axi_awuser_id,axi_aruser_id,v_wid,v_rid,2'd0} :
    select>=5 && select<=12 ? axi_wdata[(select-5)*32+:32] :
    select==13 ? axi_wstrb : select==14 ? result_job_id :
    select==15 ? mem_rsp_tag[31:0] : select==16 ? mem_rsp_tag[63:32] :
    select>=17 && select<=24 ? v_rdata[(select-17)*32+:32] : 32'd0;
endmodule
