`timescale 1ns/1ps
// Full 1920x1080 production display/read path. DDR BFM presents four COMPLETE
// 1280x720 snapshots, independent pixel oracle, real native word addresses.
// Source capture/reader ownership is checked separately, not forced here.
module m32_display_tb;
 reg clk=0,pc=0,rst=0;always #5 clk=~clk;always #3.367003367 pc=~pc;
 reg [2:0] view=4;wire quad=view==4;wire fs;reg timing_rst=0;reg read_enabled=0;
 wire [3:0] req,sel,de;wire [63:0] pixels;
 wire [111:0] sa;wire [15:0] sl;wire [3:0] sv,sready,valid,last;
 wire [27:0] addr;wire [3:0] len;wire arv;reg ready=0,rv=0,rlast=0;reg [255:0] data=0;
 wire hs,vs,od;wire [23:0] rgb;
 m31_video_output video(.clk(pc),.rst_n(rst),.timing_rst_n(timing_rst),
 .selected_view(view),.selected_mode(3'd0),.source_rgb(pixels),.source_de(de),.show_video(4'b1111),
 .feedback(3'd0),.hint_visible(1'b0),.hint_code(4'd0),.frame_sync(fs),
 .source_selected(sel),.source_request(req),.hs_out(hs),.vs_out(vs),.de_out(od),.rgb_out(rgb));
 genvar s;
 generate for(s=0;s<4;s=s+1) begin: source
  wire cmd,cmdready,done,sof;wire [27:0] a;wire [31:0] n;
  m31_rd_buf reader(.ddr_clk(clk),.ddr_rstn(rst),.vout_clk(pc),.rd_fsync(fs),.rd_en(req[s]),
   .quarter(quad),.selected(sel[s]),.enabled(read_enabled),.vout_de(de[s]),.vout_data(pixels[s*16+:16]),
   .ddr_rreq(cmd),.ddr_raddr(a),.ddr_rd_len(n),.ddr_rrdy(cmdready),.ddr_rdone(done),
   .ddr_rdata(data),.ddr_rdata_en(valid[s]),.frame_start_event(sof));
  wr_rd_ctrl_top #(.CTRL_ADDR_WIDTH(28),.MEM_DQ_WIDTH(32)) native(
   .clk(clk),.rstn(rst),.wr_cmd_en(1'b0),.wr_cmd_addr(28'd0),.wr_cmd_len(32'd0),.wr_ctrl_data(256'd0),
   .rd_cmd_en(cmd),.rd_cmd_addr({3'd0,s[1:0],1'b0,a[21:0]}),.rd_cmd_len(n),
   .rd_cmd_ready(cmdready),.rd_cmd_done(done),.read_ready(1'b1),
   .axi_awready(1'b0),.axi_wlast(1'b0),.axi_wready(1'b0),.axi_bid(4'd0),.axi_bresp(2'd0),.axi_bvalid(1'b0),
   .axi_araddr(sa[s*28+:28]),.axi_arlen(sl[s*4+:4]),.axi_arvalid(sv[s]),.axi_arready(sready[s]),
   .axi_rdata(data),.axi_rvalid(valid[s]),.axi_rlast(last[s]),.axi_rid(4'd0),.axi_rresp(2'd0));
 end endgenerate
 dual_ddr_arbiter #(.PORTS(4)) arb(.clk(clk),.rst_n(rst),.s_awaddr(112'd0),.s_awlen(16'd0),.s_awvalid(4'd0),
  .s_wdata(1024'd0),.s_wstrb(128'd0),.awready(1'b0),.wready(1'b0),.wlast(1'b0),
  .s_araddr(sa),.s_arlen(sl),.s_arvalid(sv),.s_arready(sready),.s_rvalid(valid),.s_rlast(last),
  .araddr(addr),.arlen(len),.arvalid(arv),.arready(ready),.rvalid(rv),.rlast(rlast));
 function [15:0] pattern(input integer source_id,input integer y,input integer x);
  pattern=((source_id+1)*16'h2a13)^(y*16'h071d)^(x*16'h9e37);
 endfunction
 function [23:0] gain(input [15:0] c);
  integer r,g,b;begin r={c[15:11],c[15:13]};g={c[10:5],c[10:9]};b={c[4:0],c[4:2]};
   r=r+(r>>2);g=g+(g>>2);b=b+(b>>2);
   gain={(r>255?8'd255:r[7:0]),(g>255?8'd255:g[7:0]),(b>255?8'd255:b[7:0])};end
 endfunction
 integer cycle=0,bursts=0,earliest=0;
 always @(posedge clk) cycle<=cycle+1;
 integer a,n,k,l,ss,off,y,x;


 initial begin wait(rst);forever begin
  wait(arv);@(negedge clk);a=addr;n=len+1;ss=(a>>23)&3;off=a&22'h3fffff;
  if(off+n*8>460800 || off%8) $fatal(1,"DDR bounds/units");
  while(cycle%8<5) @(negedge clk);ready=1;
  if(bursts%2) begin @(posedge clk);@(negedge clk);ready=0;end else earliest++;
  for(k=0;k<n;k++) begin
   if(k%5==2) repeat(2) @(negedge clk);
   // Same conservative 3/8 read service as M3 combined-load test.
   while(cycle%8<5) @(negedge clk);
   for(l=0;l<16;l++) begin y=(off*2+k*16+l)/1280;x=(off*2+k*16+l)%1280;
    data[l*16+:16]=pattern(ss,y,x);end
   rv=1;rlast=k==n-1;@(posedge clk);@(negedge clk);ready=0;rv=0;rlast=0;
  end
  bursts++;
 end end
 integer xx=0,yy=0,frames=0,checked=0,image_checked=0,source_id,sx,sy;
 reg prev_de=0,prev_vs=0,checking=0,osd_d;reg [23:0] wanted;
 always @(posedge pc) begin osd_d<=video.osd_area;#0.2;
  if(vs && !prev_vs) begin xx=0;yy=0;end
  if(od) begin
   if(!prev_de) xx=0;
   if(checking) begin
    wanted=0;
    if(quad || (xx>=320 && xx<1600 && yy>=180 && yy<900)) begin
     source_id=quad ? (xx/960+2*(yy/540)) : view;
     sx=quad ? (xx%960)*4/3 : xx-320;sy=quad ? (yy%540)*4/3 : yy-180;
     wanted=gain(pattern(source_id,sy,sx));image_checked++;
    end
    if(!osd_d && rgb!==wanted) $fatal(1,"HD pixel view=%0d at=%0d,%0d src=%0d xy=%0d,%0d got=%h wanted=%h",view,xx,yy,source_id,sx,sy,rgb,wanted);
    checked++;
   end
   xx++;
  end
  if(!od && prev_de) begin if(xx!=1920) $fatal(1,"HD line width %0d",xx);yy++;end
  prev_de=od;prev_vs=vs;
 end
 task scan(input [2:0] v);begin
  checking=0;wait(fs);@(negedge pc);view=v;repeat(100) @(negedge pc);checking=1;
  @(negedge fs);@(posedge fs);checking=0;
  if(yy!=1080) $fatal(1,"HD height %0d",yy);
  frames++;$display("HD_FRAME view=%0d checked=%0d image=%0d bursts=%0d",v,checked,image_checked,bursts);$fflush();
 end endtask
 initial begin #100;rst=1;repeat(50) @(negedge pc);timing_rst=1;repeat(40) @(negedge clk);read_enabled=1;
  scan(4);scan(0);
  $display("M32_DISPLAY_PASS frames=%0d full_output=1920x1080 all_pixels=%0d image_pixels=%0d bursts=%0d earliest=%0d",frames,checked,image_checked,bursts,earliest);$finish;
 end
 initial begin #100000000;$fatal(1,"HD timeout");end
endmodule
