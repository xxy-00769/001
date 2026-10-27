`timescale 1ns/1ps
// Network frames publish only after all packet DDR writes complete. Independent
// display pin drains native commands before swap/release (same M2 reader).
module m3_right_store #(parameter HD_DISPLAY=0)(input clk,rst_n,pc,fs,selected,quarter,request,
 input begin_frame,publish,input [31:0] frame_id,
 output reg begin_ack,output reg [1:0] write_bank,output reg ready,
 output reg [31:0] displayed_frames,
 output de,output [15:0] pixel,
 output [27:0] araddr,output [3:0] arlen,output arvalid,input arready,
 input [255:0] rdata,input rvalid,rlast);
 reg pending,held,enabled,busy;reg [1:0] pbank,rbank;reg [31:0] pending_id,display_id;reg [31:0] publish_serial,pending_serial,read_serial;
 wire [1:0] free_bank=(!held || rbank!=0) && (!pending || pbank!=0) ? 0 :
                      (!held || rbank!=1) && (!pending || pbank!=1) ? 1 : 2;
 reg [11:0] lines;wire [11:0] gray=(lines>>1)^lines;
 wire sof,cmd,cmdready,done,issue;wire [27:0] addr;wire [31:0] len;
 reg [1:0] sel;
 always @(posedge clk or negedge rst_n) begin
 if(!rst_n) begin pending<=0;pbank<=0;held<=0;rbank<=0;enabled<=0;busy<=0;
 begin_ack<=0;write_bank<=0;ready<=0;pending_id<=0;display_id<=0;publish_serial<=0;pending_serial<=0;read_serial<=0;lines<=0;sel<=0;end
 else begin
 sel<={sel[0],selected};begin_ack<=0;
 if(issue) busy<=1;
 if(done && busy) begin busy<=0;lines<=lines+1'b1;end
 if(begin_frame && !begin_ack && !sof) begin
  // Two references (display + latest complete) leave one of three slots
  // free even when a network SOF arrives immediately after publication.
  // Aborted assemblies may reuse only that unreferenced slot.
  write_bank<=free_bank;begin_ack<=1;
 end
 if(!sel[1]) begin
  enabled<=0;
  if(!busy && cmdready) begin
   held<=0;
   if(held && !pending) begin pending<=1;pbank<=rbank;end
  end
 end
 if(sof) begin
  lines<=0;
  if(busy || !cmdready) enabled<=0;
  else if(sel[1]) begin
   if(pending) begin rbank<=pbank;held<=1;pending<=0;display_id<=pending_id;
    read_serial<=pending_serial;
   end
   enabled<=pending || held;
  end
 end else if(cmd && enabled && (busy || !cmdready)) enabled<=0;
 // New publication wins over simultaneous SOF / old-reader retirement.
 if(publish) begin pending<=1;pbank<=write_bank;pending_id<=frame_id;publish_serial<=publish_serial+1'b1;pending_serial<=publish_serial+1'b1;ready<=1;end
 end end
 assign issue=cmd && cmdready && enabled && sel[1] && !busy && !sof;
 wire rawde;wire [15:0] raw;
 generate if(HD_DISPLAY) begin: hd
 m31_rd_buf reader(.ddr_clk(clk),.ddr_rstn(rst_n),.vout_clk(pc),.rd_fsync(fs),
 .rd_en(request),.quarter(quarter),.selected(sel[1]),.enabled(enabled),
 .vout_de(rawde),.vout_data(raw),.ddr_rreq(cmd),.ddr_raddr(addr),.ddr_rd_len(len),
 .ddr_rrdy(cmdready),.ddr_rdone(done),.ddr_rdata(rdata),.ddr_rdata_en(rvalid),.frame_start_event(sof));
 end else begin: sd
 m2_rd_buf reader(.ddr_clk(clk),.ddr_rstn(rst_n),.vout_clk(pc),.rd_fsync(fs),
 .rd_en(request),.quarter(quarter),.selected(sel[1]),.enabled(enabled),
 .vout_de(rawde),.vout_data(raw),.ddr_rreq(cmd),.ddr_raddr(addr),.ddr_rd_len(len),
 .ddr_rrdy(cmdready),.ddr_rdone(done),.ddr_rdata(rdata),.ddr_rdata_en(rvalid),.frame_start_event(sof));
 end endgenerate
 wire [27:0] owned=(rbank==2 ? 28'h2400000 : (28'h1800000+{rbank[0],22'd0}))+{6'd0,addr[21:0]};
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
 // Count a new publication only when a valid, protected pixel actually
 // leaves this source, not merely when a 60Hz SOF reacquires its descriptor.
 // read_serial changes only at drained SOF and is stable well before DE;
 // the two pixel registers settle during the production vertical prefetch.
 reg [31:0] serial1,serial2,last_shown,shown_count;reg have_shown;
 wire [31:0] shown_gray=(shown_count>>1)^shown_count;
 reg [31:0] shown_g1,shown_g2;wire [31:0] shown_binary;
 genvar sb;generate for(sb=0;sb<32;sb=sb+1) begin: shown_decode
 assign shown_binary[sb]=^(shown_g2>>sb);end endgenerate
 always @(posedge pc or negedge rst_n) if(!rst_n) begin
  serial1<=0;serial2<=0;last_shown<=0;shown_count<=0;have_shown<=0;
 end else begin
  serial1<=read_serial;serial2<=serial1;
  if(request && rawde && ev[1] && !underflow && serial2!=0 && (!have_shown || last_shown!=serial2)) begin
   last_shown<=serial2;have_shown<=1;shown_count<=shown_count+1'b1;
  end
 end
 always @(posedge clk or negedge rst_n) if(!rst_n) begin shown_g1<=0;shown_g2<=0;displayed_frames<=0;end
 else begin shown_g1<=shown_gray;shown_g2<=shown_g1;displayed_frames<=shown_binary;end
 assign de=rawde;assign pixel=ev[1] && !underflow ? raw : 16'd0;
endmodule
