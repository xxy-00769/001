`timescale 1ns/1ps
// Network frames publish only after all packet DDR writes complete. Independent
// display pin drains native commands before swap/release (same M2 reader).
module m3_right_store(input clk,rst_n,pc,fs,selected,quarter,request,
 input begin_frame,publish,input [31:0] frame_id,
 output reg begin_ack,output reg write_bank,output reg ready,
 output de,output [15:0] pixel,
 output [27:0] araddr,output [3:0] arlen,output arvalid,input arready,
 input [255:0] rdata,input rvalid,rlast);
 reg pending,pbank,held,rbank,enabled,busy;reg [31:0] pending_id;
 reg [11:0] lines;wire [11:0] gray=(lines>>1)^lines;
 wire sof,cmd,cmdready,done,issue;wire [27:0] addr;wire [31:0] len;
 reg [1:0] sel;
 always @(posedge clk or negedge rst_n) begin
 if(!rst_n) begin pending<=0;pbank<=0;held<=0;rbank<=0;enabled<=0;busy<=0;
 begin_ack<=0;write_bank<=0;ready<=0;pending_id<=0;lines<=0;sel<=0;end
 else begin
 sel<={sel[0],selected};begin_ack<=0;
 if(issue) busy<=1;
 if(done && busy) begin busy<=0;lines<=lines+1'b1;end
 if(begin_frame && !begin_ack && !sof) begin
  write_bank<=held ? !rbank : !write_bank;begin_ack<=1;
  if(pending && pbank==(held ? !rbank : !write_bank)) pending<=0;
 end
 if(publish) begin pending<=1;pbank<=write_bank;pending_id<=frame_id;ready<=1;end
 if(!sel[1]) begin enabled<=0;if(!busy && cmdready) held<=0;end
 if(sof) begin
  lines<=0;
  if(busy || !cmdready) enabled<=0;
  else if(sel[1]) begin
   if(pending) begin rbank<=pbank;held<=1;pending<=0;end
   enabled<=pending || held;
  end
 end else if(cmd && enabled && (busy || !cmdready)) enabled<=0;
 end end
 assign issue=cmd && cmdready && enabled && sel[1] && !busy && !sof;
 wire rawde;wire [15:0] raw;
 m2_rd_buf reader(.ddr_clk(clk),.ddr_rstn(rst_n),.vout_clk(pc),.rd_fsync(fs),
 .rd_en(request),.quarter(quarter),.selected(sel[1]),.enabled(enabled),
 .vout_de(rawde),.vout_data(raw),.ddr_rreq(cmd),.ddr_raddr(addr),.ddr_rd_len(len),
 .ddr_rrdy(cmdready),.ddr_rdone(done),.ddr_rdata(rdata),.ddr_rdata_en(rvalid),.frame_start_event(sof));
 wire [27:0] owned={3'd0,2'd3,rbank,addr[21:0]};
 wr_rd_ctrl_top #(.CTRL_ADDR_WIDTH(28),.MEM_DQ_WIDTH(32)) native(
 .clk(clk),.rstn(rst_n),.wr_cmd_en(1'b0),.wr_cmd_addr(28'd0),.wr_cmd_len(32'd0),
 .wr_ctrl_data(256'd0),.rd_cmd_en(issue),.rd_cmd_addr(owned),.rd_cmd_len(len),
 .rd_cmd_ready(cmdready),.rd_cmd_done(done),.read_ready(1'b1),
 .axi_awready(1'b0),.axi_wlast(1'b0),.axi_wready(1'b0),.axi_bid(4'd0),.axi_bresp(2'd0),.axi_bvalid(1'b0),
 .axi_araddr(araddr),.axi_arlen(arlen),.axi_arvalid(arvalid),.axi_arready(arready),
 .axi_rdata(rdata),.axi_rvalid(rvalid),.axi_rlast(rlast),.axi_rid(4'd0),.axi_rresp(2'd0));
 reg [11:0] g1,g2,rows;reg [1:0] ev;reg rd,underflow;
 wire [11:0] count;genvar i;generate for(i=0;i<12;i=i+1) begin: decode
 assign count[i]=^(g2>>i);end endgenerate
 always @(posedge pc or negedge rst_n) begin
 if(!rst_n) begin g1<=0;g2<=0;rows<=0;ev<=0;rd<=0;underflow<=1;end
 else begin g1<=gray;g2<=g1;ev<={ev[0],enabled};rd<=request;
  if(fs) begin rows<=0;underflow<=0;end
  else if(request && !rd) begin rows<=rows+1'b1;if(!ev[1] || count<=rows) underflow<=1;end
 end end
 assign de=rawde;assign pixel=ev[1] && !underflow ? raw : 16'd0;
endmodule
