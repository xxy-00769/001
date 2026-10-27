`timescale 1ns/1ps
module m2_full_tb #(parameter PROCESSING_ENABLE=1);
 GTP_GRS GRS_INST(.GRS_N(1'b1));
 localparam HEIGHT=720;
 reg clk=0,pc=0,v0=0,v1=0,v2=0,rst=0;
 always #5 clk=~clk;
 always #16.923077 pc=~pc;
 always #11.9 v0=~v0;
 initial begin #3;forever #11.9 v1=~v1;end
 initial begin #1.7;forever #6.7340067 v2=~v2;end
 wire [2:0] vc={v2,v1,v0};reg [2:0] online=7;wire [2:0] req;
 reg [1:0] view=0;
 wire quad=view==3;
 wire [2:0] selected; wire fs; reg timing_rst=0;
 reg [2:0] decode_glitch=0;reg sof_glitch=0;
 wire [2:0] sampled_request=req & ~decode_glitch;
 wire sampled_sof=fs | sof_glitch;
 realtime last_pixel_edge=0;always @(posedge pc) last_pixel_edge=$realtime;
 integer injected_row_glitches=0,injected_sof_glitches=0;
 // Delay-free RTL misses routed binary-decode hazards. These 2ns pulses
 // intersect a DDR edge but no pixel edge, so the pixel-domain stream is
 // unchanged. This distinguishes a safe CDC from a false credit/SOF.
 task glitch_window;
  begin
   @(negedge clk);
   while(req==0 || $realtime+7>=last_pixel_edge+33.846) @(negedge clk);
   #4;
  end
 endtask
 wire [83:0] saw,sar;wire [11:0] swlen,srlen;
 wire [2:0] swv,srv,swr,srr,sready,slast,svalid,srlast;
 wire [767:0] swdata;
 wire [27:0] aw,ar;wire [3:0] wl,rl;wire awv,arv;wire [255:0] wd;
 reg awr=0,arr=0,wr=0,last=0,rv=0,rlast=0;reg [255:0] rd=0;
 dual_ddr_arbiter #(.PORTS(3)) arb(.clk(clk),.rst_n(rst),
 .s_awaddr(saw),.s_awlen(swlen),.s_awvalid(swv),.s_awready(swr),
 .s_wdata(swdata),.s_wstrb({96{1'b1}}),.s_wready(sready),.s_wlast(slast),
 .s_araddr(sar),.s_arlen(srlen),.s_arvalid(srv),.s_arready(srr),.s_rvalid(svalid),.s_rlast(srlast),
 .awaddr(aw),.awlen(wl),.awvalid(awv),.awready(awr),.wdata(wd),.wstrb(),.wready(wr),.wlast(last),
 .araddr(ar),.arlen(rl),.arvalid(arv),.arready(arr),.rvalid(rv),.rlast(rlast));
 wire [2:0] valid,init;
 wire [47:0] pixel;
 wire [95:0] display_ids,pubs,faults;
 genvar s;
 generate for(s=0;s<3;s=s+1) begin: source
  m2_source #(.SOURCE(s),.HEIGHT(HEIGHT),.RASTER(1)) input_source(
   .core_clk(clk),.video_clk(vc[s]),.out_clk(pc),.rst_n(rst),.out_vs(sampled_sof),
   .out_de(sampled_request[s]),.selected(selected[s]),.quarter(quad),.online(online[s]),
   .awaddr(saw[s*28+:28]),.araddr(sar[s*28+:28]),.awlen(swlen[s*4+:4]),.arlen(srlen[s*4+:4]),
   .awvalid(swv[s]),.arvalid(srv[s]),.wdata(swdata[s*256+:256]),.awready(swr[s]),
   .wready(sready[s]),.wlast(slast[s]),.arready(srr[s]),.rvalid(svalid[s]),.rlast(srlast[s]),.rdata(rd));
  assign valid[s]=input_source.valid;
  assign pixel[s*16+:16]=input_source.pixel;
  assign init[s]=input_source.init_done;
  assign display_ids[s*32+:32]=input_source.dut.display_id;
  assign pubs[s*32+:32]=input_source.dut.published_count;
  assign faults[s*32+:32]=input_source.dut.read_fault_count;
  always @(posedge clk) if(rst) begin
   if(input_source.dut.write_issue &&
    ((input_source.dut.owner.have_reader && input_source.dut.write_bank==input_source.dut.read_bank) ||
     (input_source.dut.owner.pending && input_source.dut.write_bank==input_source.dut.owner.pending_bank)))
    $fatal(1,"write into reader/pending slot source=%0d",s);
  end
 end endgenerate
 reg [255:0] memory[0:345599]; // 3 sources x 2 slots x 2560 beats
 function integer idx(input [27:0] a);
  integer source,slot,offset;
  begin
   source=(a>>23)&3;slot=(a>>22)&1;offset=a&4194303;
   if(a[27:25]!=0 || source>2 || offset>=640*HEIGHT || a%8!=0)
    $fatal(1,"invalid physical native address %h",a);
   idx=(source*2+slot)*(80*HEIGHT)+offset/8;
  end
 endfunction
 function [15:0] pattern(input integer source,tag,row,col);
  pattern=(source<<14)|(((tag*16'h19d7)^(row*16'h031d)^(col*16'h9e37))&16'h3fff);
 endfunction
 integer wb=0,rb=0,wpixels=0,early_w=0,early_r=0;
 // One shared 256-bit data bus service calendar (write 5/8, read 3/8).
 // Address channels remain independent, as in the native interface.
 integer cycle=0;always @(posedge clk) cycle<=cycle+1;
 always @(posedge clk) begin
  if(wr && rv) $fatal(1,"BFM overbooks shared DDR data bus");
  if(awr && awv && wr) early_w<=early_w+1;
  if(arr && arv && rv) early_r<=early_r+1;
 end
 integer a,n,b,src,tag,wy,wx,lane;
 initial begin
  wait(rst);
  forever begin
   wait(awv);@(negedge clk);
   a=idx(aw);n=wl+1;src=aw[24:23];
   case(src)
    0:tag=source[0].input_source.dut.owner.active_id;
    1:tag=source[1].input_source.dut.owner.active_id;
    2:tag=source[2].input_source.dut.owner.active_id;
   endcase
   wy=aw[21:0]/640;wx=(aw[21:0]%640)*2;while(cycle%8>=5) @(negedge clk);awr=1;
   if(wb%2) begin @(posedge clk);@(negedge clk);awr=0;end

   for(b=0;b<n;b++) begin
    if(b%5==3) repeat(3) @(negedge clk);
    while(cycle%8>=5) @(negedge clk);
    wr=1;last=b==n-1;@(posedge clk);
    if(sready!==(1<<src)) $fatal(1,"write owner mismatch");
    memory[a+b]=wd;
    for(lane=0;lane<16;lane++) begin
     if(wd[lane*16+:16]!==pattern(src,tag,wy,wx+b*16+lane))
      $fatal(1,"write oracle src=%0d row=%0d col=%0d",src,wy,wx+b*16+lane);
     wpixels++;
    end
    @(negedge clk);awr=0;wr=0;last=0;
   end
   wb++;
  end
 end
 reg stall=0,allow_old_tail=0,old_bank=0;integer ra,rn,rr,rs;
 initial begin
  wait(rst);
  forever begin
   wait(arv);@(negedge clk);ra=idx(ar);rn=rl+1;rs=ar[24:23];while(cycle%8<5) @(negedge clk);arr=1;
   if(!selected[rs] && !(allow_old_tail && rs==0 && ar[22]==old_bank && ar[21:0]<640))
    $fatal(1,"hidden new line (old in-flight line tail is allowed)");
   if(rb%2 || stall) begin @(posedge clk);@(negedge clk);arr=0;while(stall) @(negedge clk);end

   for(rr=0;rr<rn;rr++) begin
    if(rr%5==2 || rr==rn-1) repeat(2+(rb%3)) @(negedge clk);
    while(cycle%8<5) @(negedge clk);
    rd=memory[ra+rr];rv=1;rlast=rr==rn-1;@(posedge clk);
    if(svalid!==(1<<rs)) $fatal(1,"return crossed source");
    @(negedge clk);arr=0;rv=0;rlast=0;
   end
   rb++;
  end
 end
 wire oh,ov,od; wire [23:0] output_rgb;
 m2_video_output #(.PROCESSING_ENABLE(PROCESSING_ENABLE)) video(
  .clk(pc),.rst_n(rst),.timing_rst_n(timing_rst),.selected_view(view),.selected_mode(3'd0),
  .source_rgb(pixel),.source_de(valid),.show_video(init),.hint_visible(1'b0),.hint_code(4'd0),
  .frame_sync(fs),.source_selected(selected),.source_request(req),
  .hs_out(oh),.vs_out(ov),.de_out(od),.rgb_out(output_rgb));
 // Independent raster counter at the actual output, without DUT coordinates.
 reg osd_delayed;always @(posedge pc) osd_delayed<=video.osd_area;
 reg fault_allowed=0;integer black_pixels=0;
 integer xx=0,yy=0,frames=0,pixels=0,j,srcx,srcy,ss;
 integer tags[0:2]; reg prev_de=0,prev_vs=1,checking=0;
 reg [15:0] expected565;reg [23:0] expected888;integer red,green,blue;
 initial begin
  wait(checking);
  repeat(16) begin
   wait(req!=0);glitch_window;decode_glitch=req;
   #2;decode_glitch=0;injected_row_glitches++;
   repeat(8) @(posedge pc);
  end
  wait(frames==3 && checking);wait(req!=0);glitch_window;
  sof_glitch=1;#2;sof_glitch=0;injected_sof_glitches++;
 end
 function [23:0] gain(input [15:0] c);
  integer r,g,b;
  begin r={c[15:11],c[15:13]};g={c[10:5],c[10:9]};b={c[4:0],c[4:2]};
   r=r+(r>>2);g=g+(g>>2);b=b+(b>>2);
   gain={(r>255?8'd255:r[7:0]),(g>255?8'd255:g[7:0]),(b>255?8'd255:b[7:0])};
  end
 endfunction
 always @(posedge pc) begin
  #2;
  if(!ov && prev_vs) begin xx=0;yy=0;end
  if(od) begin
   if(!prev_de) xx=0;
   if(checking && xx>=80 && xx<720 && yy>=60 && yy<420) begin
    ss=quad ? (yy<240 ? (xx<400?0:1):(xx<400?2:3)) : view;
    if(ss<3) begin
     srcx=(xx-80)%(quad?320:640)*(quad?4:2);
     srcy=(yy-60)%(quad?180:360)*(quad?4:2);
     expected565=pattern(ss,tags[ss],srcy,srcx);expected888=gain(expected565);
     // OSD is an intentional overlay, independently counted outside its area.
     // Compare the selected production pixel AND final output, including borders.
     if(!osd_delayed && output_rgb!==expected888)
      if(fault_allowed && ss==0 && output_rgb===0) black_pixels++;
      else $fatal(1,"FULL oracle frame=%0d view=%0d source=%0d tag=%0d panel=%0d,%0d source_xy=%0d,%0d got=%h want=%h",frames,view,ss,tags[ss],xx,yy,srcx,srcy,output_rgb,expected888);
     pixels++;
    end
   end
   xx++;
  end
  if(!od && prev_de) begin if(xx!=800) $fatal(1,"panel width %0d",xx);yy++;end
  prev_de=od;prev_vs=ov;
 end
 task frame(input integer v);
  begin
   checking=0;
   wait(fs);@(negedge pc);view=v;
   repeat(100) @(negedge pc);
   for(integer k=0;k<3;k++) tags[k]=display_ids[k*32+:32];
   checking=1;
   @(negedge fs);@(posedge fs);checking=0;
   if(yy!=480) $fatal(1,"panel height %0d",yy);
   frames++;
   $display("FULL_FRAME frame=%0d view=%0d pubs=%0d/%0d/%0d pixels=%0d",frames,view,pubs[31:0],pubs[63:32],pubs[95:64],pixels);$fflush();
  end
 endtask
 initial begin
  #500;rst=1;@(negedge pc);timing_rst=1;
  wait(&init); // Full capture publication is required before checked scans.
  frame(0);frame(1);frame(2);frame(3);
  if(faults!=0) $fatal(1,"normal full load read faults %h",faults);
  // Keep a native line pending beyond its deadline and across the next SOF.
  // Frame guards must black the incomplete frame; then switch to another
  // source, drain the old command and strictly check hidden-source reselect.
  stall=1;fault_allowed=1;frame(0);fault_allowed=0;
  if(black_pixels==0) $fatal(1,"late-return protection not exercised");
  old_bank=source[0].input_source.dut.read_bank;allow_old_tail=1;
  fork
   frame(1);
   begin repeat(200) @(negedge pc);stall=0;end
  join
  allow_old_tail=0;frame(0);
  if(injected_row_glitches!=16 || injected_sof_glitches!=1) $fatal(1,"decode hazard coverage");
  if(early_r==0 || early_w==0) $fatal(1,"earliest first beat not covered");
  if(faults==0) $fatal(1,"old-tail SOF guard not exercised");
  $display("M2_FULL_PASS frames=%0d pixels=%0d write_pixels=%0d bursts=%0d/%0d coincident=%0d/%0d pubs=%0d/%0d/%0d full_height=720 guarded_black=%0d decode_hazards=16/1",frames,pixels,wpixels,wb,rb,early_w,early_r,pubs[31:0],pubs[63:32],pubs[95:64],black_pixels);$finish;
 end
 initial begin
  forever begin #10000000;
   $display("FULL_PROGRESS ns=%0t init=%b pubs=%0d/%0d/%0d rejected=%0d/%0d/%0d",$time,init,pubs[31:0],pubs[63:32],pubs[95:64],source[0].input_source.dut.rejected_count,source[1].input_source.dut.rejected_count,source[2].input_source.dut.rejected_count);$fflush();
  end
 end
 initial begin #400000000;$fatal(1,"full timeout");end
endmodule
