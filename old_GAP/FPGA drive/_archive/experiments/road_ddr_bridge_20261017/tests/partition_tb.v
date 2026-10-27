`timescale 1ns/1ps
module partition_case #(
    parameter [31:0] BASE=32'h00200000,
    parameter [31:0] LIMIT=32'h00400000
) (input clk,rst_n,output reg done=0);
wire ready, rsp_valid, error, awvalid, arvalid;
reg valid=0;
wire [63:0] tag;
wire [127:0] data;
road_ddr_bridge #(.ACC_BASE_WORD(BASE),.ACC_LIMIT_WORD(LIMIT)) dut(
    .clk(clk),.rst_n(rst_n),.ddr_init_done(1'b1),.acc_rst_n(1'b1),
    .mem_req_valid(valid),.mem_req_ready(ready),.mem_req_write(1'b1),
    .mem_req_addr(BASE),.mem_req_data(128'd0),.mem_req_strb(16'hffff),.mem_req_tag(64'h88),
    .mem_rsp_valid(rsp_valid),.mem_rsp_ready(1'b0),.mem_rsp_error(error),.mem_rsp_tag(tag),.mem_rsp_data(data),
    .v_awvalid(1'b0),.v_arvalid(1'b0),.v_awaddr(28'd0),.v_awlen(4'd0),.v_awid(4'd0),
    .v_awap(1'b0),.v_wdata(256'd0),.v_wstrb(32'd0),.v_araddr(28'd0),.v_arlen(4'd0),
    .v_arid(4'd0),.v_arap(1'b0),
    .axi_awvalid(awvalid),.axi_awready(1'b0),.axi_wready(1'b0),.axi_wusero_last(1'b0),
    .axi_wusero_id(4'd0),.axi_arvalid(arvalid),.axi_arready(1'b0),.axi_rdata(256'd0),
    .axi_rid(4'd0),.axi_rvalid(1'b0),.axi_rlast(1'b0));
initial begin
    wait(rst_n);
    @(negedge clk); #1; valid=1;
    @(posedge clk); if(!ready) $fatal(1,"Partition request not accepted");
    @(negedge clk); #1; valid=0;
    repeat(5) begin
        @(negedge clk); #1;
        if(awvalid || arvalid || !rsp_valid || !error || tag!==64'h88 || data!==128'd0)
            $fatal(1,"Unsafe partition accepted base=%h limit=%h",BASE,LIMIT);
    end
    done=1;
end
endmodule
module partition_tb;
reg clk=0,rst_n=0;
always #5 clk=~clk;
wire [4:0] done;
partition_case #(.BASE(32'h00200001)) odd_base(clk,rst_n,done[0]);
partition_case #(.LIMIT(32'h00400001)) odd_limit(clk,rst_n,done[1]);
partition_case #(.BASE(32'h001ffffe)) overlaps_video(clk,rst_n,done[2]);
partition_case #(.LIMIT(32'h00200000)) empty_range(clk,rst_n,done[3]);
partition_case #(.LIMIT(32'h04000002)) native_overflow(clk,rst_n,done[4]);
initial begin
    #2; rst_n=0; #20; rst_n=1;
    wait(&done);
    $display("PASS: native partition 5 unsafe maps rejected without DDR traffic");
    $finish;
end
initial begin #10000; $fatal(1,"Partition test timeout"); end
endmodule
