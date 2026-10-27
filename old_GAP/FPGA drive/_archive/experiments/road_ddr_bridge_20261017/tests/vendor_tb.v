`timescale 1ns/1ps
`define VENDOR_DDR
module vendor_tb;
localparam [31:0] ACC_BASE=32'h00200000, ACC_LIMIT=ACC_BASE+1024;
localparam MEM_WORDS=1024;
`include "harness.vh"
reg ref_clk=0, board_reset=1, grs_n=0;
always #10 ref_clk=~ref_clk;
GTP_GRS GRS_INST(.GRS_N(grs_n));
wire mem_rst_n, mem_ck, mem_ck_n, mem_cke, mem_cs_n, mem_ras_n, mem_cas_n, mem_we_n, mem_odt;
wire [14:0] mem_a;
wire [2:0] mem_ba;
wire [3:0] mem_dqs, mem_dqs_n, mem_dm;
wire [31:0] mem_dq;
wire [15:0] model_address={1'b0,mem_a};
DDR3_50H controller(
    .ref_clk(ref_clk),.resetn(board_reset),.ddr_init_done(ddr_init_done),.ddrphy_clkin(clk),.pll_lock(),
    .axi_awaddr(axi_awaddr),.axi_awuser_ap(axi_awuser_ap),.axi_awuser_id(axi_awuser_id),
    .axi_awlen(axi_awlen),.axi_awready(axi_awready),.axi_awvalid(axi_awvalid),
    .axi_wdata(axi_wdata),.axi_wstrb(axi_wstrb),.axi_wready(axi_wready),
    .axi_wusero_id(axi_wusero_id),.axi_wusero_last(axi_wusero_last),
    .axi_araddr(axi_araddr),.axi_aruser_ap(axi_aruser_ap),.axi_aruser_id(axi_aruser_id),
    .axi_arlen(axi_arlen),.axi_arready(axi_arready),.axi_arvalid(axi_arvalid),
    .axi_rdata(axi_rdata),.axi_rid(axi_rid),.axi_rlast(axi_rlast),.axi_rvalid(axi_rvalid),
    .apb_clk(1'b0),.apb_rst_n(1'b1),.apb_sel(1'b0),.apb_enable(1'b0),.apb_addr(8'd0),
    .apb_write(1'b0),.apb_ready(),.apb_wdata(16'd0),.apb_rdata(),.apb_int(),
    .mem_rst_n(mem_rst_n),.mem_ck(mem_ck),.mem_ck_n(mem_ck_n),.mem_cke(mem_cke),.mem_cs_n(mem_cs_n),
    .mem_ras_n(mem_ras_n),.mem_cas_n(mem_cas_n),.mem_we_n(mem_we_n),.mem_odt(mem_odt),
    .mem_a(mem_a),.mem_ba(mem_ba),.mem_dqs(mem_dqs),.mem_dqs_n(mem_dqs_n),.mem_dq(mem_dq),.mem_dm(mem_dm),
    .debug_data(),.debug_slice_state(),.debug_calib_ctrl(),.ck_dly_set_bin(),
    .force_ck_dly_en(1'b0),.force_ck_dly_set_bin(8'h05),.dll_step(),.dll_lock(),
    .init_read_clk_ctrl(2'd0),.init_slip_step(4'd0),.force_read_clk_ctrl(1'b0),
    .ddrphy_gate_update_en(1'b0),.update_com_val_err_flag(),.rd_fake_stop(1'b0));
wire [2:0] delayed_ck, delayed_ck_n;
assign delayed_ck[0]=mem_ck;
assign delayed_ck_n[0]=mem_ck_n;
genvar chip;
generate for(chip=0;chip<2;chip=chip+1) begin: chips
    assign #0.05 delayed_ck[chip+1]=delayed_ck[chip];
    assign #0.05 delayed_ck_n[chip+1]=delayed_ck_n[chip];
    ddr3 #(.DEBUG(0)) memory(
        .rst_n(mem_rst_n),.ck(delayed_ck[chip+1]),.ck_n(delayed_ck_n[chip+1]),
        .cs_n(mem_cs_n),.addr(model_address),.dq(mem_dq[chip*16+:16]),
        .dqs(mem_dqs[chip*2+:2]),.dqs_n(mem_dqs_n[chip*2+:2]),.dm_tdqs(mem_dm[chip*2+:2]),
        .tdqs_n(),.cke(mem_cke),.odt(mem_odt),.ras_n(mem_ras_n),.cas_n(mem_cas_n),
        .we_n(mem_we_n),.ba(mem_ba));
end endgenerate
reg req_valid=0, req_write=0, rsp_ready=0;
reg [31:0] req_addr=0;
reg [127:0] req_data=0;
reg [15:0] req_keep=0;
reg [63:0] req_tag=0;
assign mem_req_valid=req_valid;
assign mem_req_write=req_write;
assign mem_req_addr=req_addr;
assign mem_req_data=req_data;
assign mem_req_strb=req_keep;
assign mem_req_tag=req_tag;
assign mem_rsp_ready=rsp_ready;
reg [127:0] golden [0:63];
reg [127:0] value;
reg [15:0] keep;
integer i,b,waited,checks=0,count_file;
task transaction;
input wr;
input integer index;
input [127:0] data;
input [15:0] mask;
input [127:0] expected;
begin
    @(negedge clk); #1;
    req_valid=1; req_write=wr; req_addr=ACC_BASE+index; req_data=data; req_keep=mask;
    req_tag=req_tag+64'h100000001;
    @(posedge clk); while(!mem_req_ready) @(posedge clk);
    @(negedge clk); #1; req_valid=0;
    waited=0;
    while(!mem_rsp_valid && waited<100000) begin @(negedge clk); #1; waited=waited+1; end
    if(!mem_rsp_valid || mem_rsp_error || mem_rsp_tag!==req_tag || mem_rsp_data!==expected || fault)
        $fatal(1,"Vendor transaction failed index=%0d write=%b error=%b data=%h expected=%h state=%0d",index,wr,mem_rsp_error,mem_rsp_data,expected,dut.state);
    repeat(index%5) @(negedge clk);
    #1; rsp_ready=1;
    @(negedge clk); #1; rsp_ready=0;
    checks=checks+1;
end
endtask
initial begin
    #5 grs_n=1;
    #5 board_reset=0;
    #50 board_reset=1;
    wait(ddr_init_done===1'b1);
    repeat(8) @(negedge clk);
    #1; rst_n=1; acc_rst_n=1;
    $display("VENDOR_INITIALIZED time=%t",$time);
    for(i=0;i<64;i=i+1) begin
        golden[i]={4{32'h10000000+i}};
        transaction(1,i,golden[i],16'hffff,0);
    end
    // Initialize a complete video burst before introducing competing reads.
    video_read_jobs=1; video_quota=1; video_stress=1; v_araddr=512;
    wait(video_write_jobs==1 && !video_wr_pending);
    repeat(20) @(negedge clk);
    video_quota=17;
    for(i=0;i<64;i=i+1) begin
        value={4{32'hdead9000+i}};
        keep=16'(1<<(i%16)) | (i[0] ? 16'h5500 : 16'h00aa);
        for(b=0;b<16;b=b+1)
            if(keep[b]) golden[i][b*8+:8]=value[b*8+:8];
        transaction(1,i,value,keep,0);
        transaction(0,i,0,0,golden[i]);
    end
    for(i=0;i<64;i=i+1) transaction(0,i,0,0,golden[i]);
    if(fault || video_read_jobs!=17 || video_write_jobs!=17 || video_rd_pending || video_wr_pending)
        $fatal(1,"Vendor video integration failed");
    count_file=$fopen("../output/vendor_counts.txt","w");
    $fdisplay(count_file,"%0d %0d %0d %0d %0d",checks,video_reads,video_writes,native_commands,cycles);
    $fclose(count_file);
    $display("PASS: vendor DDR controller + PHY + two x16 memory models transactions=%0d video_read_beats=%0d video_write_beats=%0d",
        checks,video_reads,video_writes);
    $finish;
end
initial begin
    #800000;
    $fatal(1,"Vendor initialization/transaction timeout");
end
endmodule
`undef VENDOR_DDR
