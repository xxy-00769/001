`timescale 1ns/1ps
module GRS_INST; wire GRSNET=1'b1; endmodule
module cam1_rotate25_tb;
 reg bc=0,dc=0,sc=0,pc=0,rst=0;
 always #6.944444444 bc=~bc; // actual byte72MHz, not accelerated geometry
 always #5 dc=~dc;
 always #10 sc=~sc;
 always #3.367003367 pc=~pc; // actual1080p60
 reg vs=0,href=0;reg [7:0] octet=0;
 wire vc,ivs,ide,byte_bad;wire [15:0] rgb;
 cam3660_dvp gearbox(.pclk(bc),.rst_n(rst),.de_i(href),.vs_i(vs),.pdata_i(octet),
  .pixel_clk(vc),.de_o(ide),.vs_o(ivs),.frame_bad(byte_bad),.pdata_o(rgb));
 wire running,result_valid;wire [31:0] open_id,open_time,result_id;
 wire [7:0] errors;wire [255:0] status;
 video_capture_status #(.SOURCE_ID(1)) monitor(.ref_clk(sc),.video_clk(vc),.rst_n(rst),
  .source_ready(rst),.video_vs(ivs),.video_de(ide),.pipeline_rst_n(running),
  .snapshot(status),.frame_open_id(open_id),.frame_open_time(open_time),
  .frame_result_valid(result_valid),.frame_result_id(result_id),.frame_result_errors(errors));
 reg vs_old=0,closed_bad=0;
 always @(posedge vc or negedge rst) if(!rst) begin vs_old<=0;closed_bad<=0;end
  else begin vs_old<=ivs;if(ivs&&!vs_old) closed_bad<=byte_bad;end
 wire cvs,cde;wire [15:0] crgb;wire [31:0] cid,ctime;
 capture_pipe pipe(.clk(vc),.rst_n(running),.vs(ivs),.de(ide),.rgb(rgb),
  .frame_id(open_id),.frame_time(open_time),.out_vs(cvs),.out_de(cde),.out_rgb(crgb),
  .out_id(cid),.out_time(ctime));
 wire fs,req;wire [10:0] x,y;reg quad=0,selected=1;
 m31_timing raster(.clk(pc),.rst_n(rst),.quad(quad),.frame_sync(fs),.read_request(req),
  .raw_x(x),.raw_y(y));
 wire ren=selected && req && (!quad || (x>=960 && y<540));
 wire [27:0] aw,ar;wire [3:0] al,rl;wire av,rvd;wire [255:0] wd;
 reg awr=0,wr=0,wl=0,arr=0,rv=0,rla=0;reg [255:0] rd=0;
 wire de,init;wire [15:0] pixel;wire [31:0] published,displayed;
 fram_buf #(.SOURCE_ID(1),.CAM1_CONTINUOUS(1),.HD_DISPLAY(1),.M2_READER(1)) dut(
  .vin_clk(vc),.wr_fsync(cvs),.wr_en(cde),.wr_data(crgb),.pipeline_running(running),
  .wr_frame_id(cid),.wr_frame_time(ctime),.source_result_valid(result_valid),
  .source_result_id(result_id),.source_result_errors(errors|{7'd0,closed_bad}),
  .ddr_clk(dc),.ddr_rstn(rst),.vout_clk(pc),.rd_fsync(fs),
  .display_selected(selected),.display_quarter(quad),.rd_en(ren),.vout_de(de),.vout_data(pixel),
  .init_done(init),.capture_published(published),.display_new_frames(displayed),
  .axi_awaddr(aw),.axi_awlen(al),.axi_awvalid(av),.axi_awready(awr),
  .axi_wdata(wd),.axi_wready(wr),.axi_wlast(wl),.axi_bid(4'd0),
  .axi_araddr(ar),.axi_arlen(rl),.axi_arvalid(rvd),.axi_arready(arr),
  .axi_rdata(rd),.axi_rvalid(rv),.axi_rlast(rla),.axi_rid(4'd0));
 // Independent source pattern: all corners differ; both coordinates reverse.
 function automatic [15:0] pattern(input integer f,yy,xx);
  pattern=(f*16'h2937)^((719-yy)*16'h317) ^ ((1279-xx)*16'h65);
 endfunction
 task automatic idle(input integer n);repeat(n) @(negedge bc);endtask
 task automatic frame(input integer number);
  integer yy,xx,w,tag;reg [15:0] value;
  begin
   tag=open_id;vs=1;href=0;idle(7200);vs=0; //2*HTS SYS cycles
   idle(3600*14); // total blank16 rows before active
   for(yy=0;yy<720;yy=yy+1) begin
    w=(number==5 && yy==311) ? 1279:1280;
    for(xx=0;xx<w;xx=xx+1) begin
     value=pattern(tag,yy,xx);href=1;octet=value[15:8];idle(1);
     octet=value[7:0];idle(1);
    end
    href=0;idle(3600-2*w);
   end
   idle(3600*64); // exactly1800*800 SYS cycles,40ms per new input
  end
 endtask
 reg [255:0] memory[0:172799];
 function automatic integer idx(input [27:0] a);
  integer bank,offset;
  begin
   bank=a>=28'h2800000 ? 2:(a[22]?1:0);offset=a[21:0];
   if((a[27:22]!=6'h02 && a[27:22]!=6'h03 && a[27:22]!=6'h0a)
     || offset>=460800 || a%8) $fatal(1,"CAM1 escaped bank map %h",a);
   idx=bank*57600+offset/8;
  end
 endfunction
 integer beats=0,checked_w=0,checked_r=0,third_writes=0,wraps=0;
 integer a,n,b,yy,xx,tag,lane;
 initial begin wait(rst);forever begin
  wait(av);@(negedge dc);a=idx(aw);n=al+1;
  yy=aw[21:0]/640;xx=(aw[21:0]%640)*2;tag=dut.front_three_slots.owner.active_id;
  if(aw>=28'h2800000) third_writes++;
  awr=1;@(posedge dc);@(negedge dc);awr=0;
  for(b=0;b<n;b++) begin
   if(b%5==2) repeat(3) @(negedge dc); // legal production DDR gaps
   wr=1;wl=b==n-1;@(posedge dc);
   for(lane=0;lane<16;lane++) begin
    // The deliberate short row has no last pixel. Its stale last RAM half
    // is not an expected source pixel; the whole frame MUST be rejected.
    if(!(tag==4 && yy==311 && xx+b*16+lane==1279)
       && wd[lane*16+:16]!==pattern(tag,yy,xx+b*16+lane))
     $fatal(1,"write byte/row/frame oracle id%0d y%0d x%0d got%h",tag,yy,xx+b*16+lane,wd[lane*16+:16]);
    checked_w++;
   end
   memory[a+b]=wd;beats++;@(negedge dc);wr=0;wl=0;
  end
 end end
 integer ra,rn,k;
 initial begin wait(rst);forever begin
  wait(rvd);@(negedge dc);ra=idx(ar);rn=rl+1;arr=1;
  @(posedge dc);@(negedge dc);arr=0;
  for(k=0;k<rn;k++) begin
   if(k%9==8) repeat(3) @(negedge dc);
   rd=memory[ra+k];rv=1;rla=k==rn-1;@(posedge dc);
   @(negedge dc);rv=0;rla=0;
  end
 end end
 reg [15:0] e0,e1;reg v0,v1;integer display_tag,rx,ry;
 reg old_ren=0;integer independent_displays=0,last_completed=-1;
 always @(posedge pc) if(rst) begin
  v1<=v0;v0<=ren;e1<=e0;
  rx=quad ? ((x-960)*4/3):(x-320);
  ry=quad ? (y*4/3):(y-180);
  if(ren) e0<=pattern(dut.display_id,ry,rx);
  if(ren && !old_ren && ry==0) display_tag=dut.display_id;
  if(old_ren && !ren && y==(quad?539:899) && init && !dut.output_bad
     && display_tag!=last_completed) begin independent_displays++;last_completed=display_tag;end
  old_ren<=ren;
  #0.2;
  if(de && init && !dut.output_bad && dut.enabled_v[1]) begin
   if(pixel!==e1) $fatal(1,"display oracle q%0d got%h want%h id%0d",quad,pixel,e1,dut.display_id);
   checked_r++;
  end
 end
 always @(posedge dc) if(rst && dut.write_issue)
  if((dut.front_three_slots.owner.have_reader && dut.write_bank==dut.read_bank)
   || (dut.front_three_slots.owner.pending && dut.write_bank==dut.front_three_slots.owner.pending_bank))
   $fatal(1,"CAM1 write touched pinned/pending slot");
 integer frame_done=0;realtime previous_pub=0;integer consecutive=0;
 reg [31:0] old_pub=0;
 always @(posedge dc) if(published!=old_pub) begin
  if(published>=2 && published<=4) begin
   if($realtime-previous_pub<39990000 || $realtime-previous_pub>40010000)
    $fatal(1,"publication is not25fps interval=%0.1f",$realtime-previous_pub);
   consecutive++;
  end
  previous_pub=$realtime;old_pub=published;
  $display("CAM1_PUBLICATION count=%0d id=%0d ns=%0t",published,dut.front_three_slots.owner.pending_id,$time);$fflush();
 end
 initial begin
  rst=1;#1;rst=0;#999;rst=1;idle(100);
  for(integer f=1;f<=6;f++) begin frame(f);frame_done=f;end
  vs=1;idle(7200);vs=0;idle(6000);
  if(status[143:128]!=5 || status[175:160]!=1) $fatal(1,"geometry totals %h",status);
  if(published!=5 || dut.rejected_count!=1 || consecutive!=3)
   $fatal(1,"publication good/bad %0d/%0d streak%0d",published,dut.rejected_count,consecutive);
  if(checked_w<5*921600 || checked_r<2*921600 || third_writes==0 || dut.read_fault_count!=0)
   $fatal(1,"coverage write%0d read%0d third%0d faults%0d",checked_w,checked_r,third_writes,dut.read_fault_count);
  if(displayed!=independent_displays) $fatal(1,"display counter%0d expected%0d",displayed,independent_displays);
  $display("PASS CAM1 production byte72/pixel36 DDR100 display148.5:6 full720 frames,25fps publications,180deg coordinate oracle,short row rejection/recovery,3 disjoint banks,hidden/reselect,single/960x540,DDR gaps,all write pixels=%0d display=%0d new_display=%0d",checked_w,checked_r,displayed);
  $finish;
 end
 // Mode changes only at output boundaries, as in production.
 initial begin
  wait(frame_done==1);@(posedge fs);quad=1;
  wait(frame_done==2);@(posedge fs);selected=0;
  wait(frame_done==3);@(posedge fs);selected=1;
  wait(frame_done==4);@(posedge fs);quad=0;
 end
 initial begin #250000000;$fatal(1,"CAM1 integration deadline");end
endmodule
