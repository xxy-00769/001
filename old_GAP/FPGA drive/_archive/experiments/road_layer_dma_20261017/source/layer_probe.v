`timescale 1ns/1ps
// Test-only multiplexed shell so internal memory ports are not package pins.
module layer_probe (
    input clk, rst_n,
    input [3:0] command,
    input [127:0] payload,
    input mem_req_ready, mem_rsp_error,
    input [3:0] select,
    output [31:0] observe
);
reg [319:0] descriptor;
reg [63:0] response_tag;
wire cfg_ready, busy, fault, done;
wire [7:0] fault_code;
wire [31:0] result_job_id;
wire mem_req_valid, mem_req_write, mem_rsp_ready;
wire [31:0] mem_req_addr;
wire [127:0] mem_req_data;
wire [15:0] mem_req_strb;
wire [63:0] mem_req_tag;
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin descriptor<=0; response_tag<=0; end
    else begin
        if(command[1] && cfg_ready) descriptor<={payload[31:0],descriptor[319:32]};
        if(command[2]) response_tag<=payload[63:0];
    end
end
conv_layer_dma engine (
    .clk(clk), .rst_n(rst_n), .cfg_valid(command[0] && !command[1]), .cfg_ready(cfg_ready), .cfg_descriptor(descriptor),
    .busy(busy), .fault(fault), .fault_code(fault_code), .done(done), .result_job_id(result_job_id),
    .mem_req_valid(mem_req_valid), .mem_req_ready(mem_req_ready), .mem_req_write(mem_req_write),
    .mem_req_addr(mem_req_addr), .mem_req_data(mem_req_data), .mem_req_strb(mem_req_strb), .mem_req_tag(mem_req_tag),
    .mem_rsp_valid(command[3]), .mem_rsp_ready(mem_rsp_ready), .mem_rsp_data(payload), .mem_rsp_tag(response_tag), .mem_rsp_error(mem_rsp_error)
);
assign observe = select==0 ? {10'd0,fault_code,7'd0,mem_rsp_ready,mem_req_write,mem_req_valid,done,fault,busy,cfg_ready} :
    select==1 ? mem_req_addr : select==2 ? mem_req_tag[31:0] : select==3 ? mem_req_tag[63:32] :
    select==4 ? mem_req_data[31:0] : select==5 ? mem_req_data[63:32] : select==6 ? mem_req_data[95:64] :
    select==7 ? mem_req_data[127:96] : select==8 ? {16'd0,mem_req_strb} : select==9 ? result_job_id : 32'd0;
endmodule
