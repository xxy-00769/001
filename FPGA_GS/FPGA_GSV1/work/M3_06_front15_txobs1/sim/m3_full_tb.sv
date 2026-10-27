`timescale 1ns/1ps
module m3_full_tb #(parameter PROCESSING_ENABLE=1);
 GTP_GRS GRS_INST(.GRS_N(1'b1));
 localparam HEIGHT=720;
 reg clk=0,pc=0,v0=0,v1=0,v2=0,rst=0;
 always #5 clk=~clk;
 always #16.923077 pc=~pc;
 always #11.9 v0=~v0;
 initial begin #3;forever #11.9 v1=~v1;end
 initial begin #1.7;forever #6.7340067 v2=~v2;end
 wire [2:0] vc={v2,v1,v0};reg [2:0] online=7;wire [3:0] req;
 reg [2:0] view=0;
 wire quad=view==4;
 wire [3:0] selected; wire fs; reg timing_rst=0;
 reg [3:0] decode_glitch=0;reg sof_glitch=0;
 wire [3:0] sampled_request=req & ~decode_glitch;
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
 wire [139:0] saw,sar;wire [19:0] swlen,srlen;
 wire [4:0] swv,srv,swr,srr,sready,slast,svalid,srlast;
 wire [1279:0] swdata;
 wire [27:0] aw,ar;wire [3:0] wl,rl;wire awv,arv;wire [255:0] wd;
 reg awr=0,arr=0,wr=0,last=0,rv=0,rlast=0;reg [255:0] rd=0;
 dual_ddr_arbiter #(.PORTS(5)) arb(.clk(clk),.rst_n(rst),
 .s_awaddr(saw),.s_awlen(swlen),.s_awvalid(swv),.s_awready(swr),
 .s_wdata(swdata),.s_wstrb({160{1'b1}}),.s_wready(sready),.s_wlast(slast),
 .s_araddr(sar),.s_arlen(srlen),.s_arvalid(srv),.s_arready(srr),.s_rvalid(svalid),.s_rlast(srlast),
 .awaddr(aw),.awlen(wl),.awvalid(awv),.awready(awr),.wdata(wd),.wstrb(),.wready(wr),.wlast(last),
 .araddr(ar),.arlen(rl),.arvalid(arv),.arready(arr),.rvalid(rv),.rlast(rlast));
 wire [3:0] valid,init;
 wire [63:0] pixel;
 wire [95:0] display_ids,pubs,faults;
 wire acquire,release_frame,grant,held;wire [1:0] net_bank;
 wire [31:0] net_id,net_time,latest_id;
 genvar s;
 generate for(s=0;s<3;s=s+1) begin: source
  m3_source #(.FRONT(s==0),.SOURCE(s),.HEIGHT(HEIGHT),.RASTER(1)) input_source(
   .net_acquire(s==0 ? acquire : 1'b0),.net_release(s==0 ? release_frame : 1'b0),
   .core_clk(clk),.video_clk(vc[s]),.out_clk(pc),.rst_n(rst),.out_vs(sampled_sof),
   .out_de(sampled_request[s]),.selected(selected[s]),.quarter(quad),.online(online[s]),
   .awaddr(saw[s*28+:28]),.araddr(sar[s*28+:28]),.awlen(swlen[s*4+:4]),.arlen(srlen[s*4+:4]),
   .awvalid(swv[s]),.arvalid(srv[s]),.wdata(swdata[s*256+:256]),.awready(swr[s]),
   .wready(sready[s]),.wlast(slast[s]),.arready(srr[s]),.rvalid(svalid[s]),.rlast(srlast[s]),.rdata(rd));
  if(s==0) begin
   assign grant=input_source.net_grant;assign held=input_source.net_held;
   assign net_bank=input_source.net_bank;assign net_id=input_source.net_id;
   assign net_time=input_source.net_time;assign latest_id=input_source.latest_frame_id;
  end
  assign valid[s]=input_source.valid;
  assign pixel[s*16+:16]=input_source.pixel;
  assign init[s]=input_source.init_done;
  assign display_ids[s*32+:32]=input_source.dut.display_id;
  assign pubs[s*32+:32]=input_source.dut.published_count;
  assign faults[s*32+:32]=input_source.dut.read_fault_count;
  if(s==0) begin
   always @(posedge clk) if(rst && input_source.dut.write_issue &&
    ((input_source.dut.front_three_slots.owner.have_reader && input_source.dut.write_bank==input_source.dut.read_bank) ||
     (held && input_source.dut.write_bank==net_bank))) $fatal(1,"front overwrites independent reader");
  end else begin
   always @(posedge clk) if(rst && input_source.dut.write_issue &&
    input_source.dut.two_slots.owner.have_reader && input_source.dut.write_bank==input_source.dut.read_bank)
    $fatal(1,"capture overwrites display");
  end
 end endgenerate

 reg [7:0] packram[0:8191];reg [3:0] rx_pending=0;wire [3:0] rack;
 reg [63:0] rx_lengths=0;wire [12:0] rx_address;reg [7:0] rx_byte;
 always @(posedge clk) rx_byte<=packram[rx_address];
 wire tx_we,tx_req;wire [10:0] tx_address;wire [7:0] tx_byte;wire [15:0] tx_length;reg tx_ack=0;
 wire right_begin,right_ack,right_bank,right_publish,right_healthy;wire [31:0] right_id,right_frames;
 wire online_net,tick_ms;wire [7:0] fps;wire fragment_ready,fragment_taken;wire [31:0] fid,ft,off;
 wire [15:0] fi;wire [8:0] word_address;wire [31:0] word_data,upload_frames;
 m3_net_core core(.clk(clk),.rst_n(rst),.rx_reset_n(1'b1),.rx_pending(rx_pending),.rx_ack(rack),.rx_lengths(rx_lengths),.rx_addr(rx_address),.rx_data(rx_byte),
 .tx_we(tx_we),.tx_addr(tx_address),.tx_data(tx_byte),.tx_req(tx_req),.tx_length(tx_length),.tx_ack(tx_ack),
 .right_begin(right_begin),.right_begin_ack(right_ack),.right_bank(right_bank),.right_publish(right_publish),.right_id(right_id),.right_healthy(right_healthy),
 .awaddr(saw[84+:28]),.awlen(swlen[12+:4]),.awvalid(swv[3]),.awready(swr[3]),.wdata(swdata[768+:256]),.wstrb(),.wready(sready[3]),.wlast(slast[3]),
 .key_event(1'b0),.key_code(4'd0),.latest_front_id(latest_id),.feedback(),.online(online_net),.tick_ms(tick_ms),.upload_fps(fps),
 .fragment_ready(fragment_ready),.fragment_taken(fragment_taken),.front_id(fid),.front_time(ft),.front_offset(off),.front_index(fi),.front_word_addr(word_address),.front_word_data(word_data),.session(),.rx_packets(),.bad_packets(),.right_frames(right_frames),.right_drops(),.control_events());
 m3_right_store right_store(.clk(clk),.rst_n(rst),.pc(pc),.fs(sampled_sof),.selected(selected[3]),.quarter(quad),.request(sampled_request[3]),
 .begin_frame(right_begin),.begin_ack(right_ack),.write_bank(right_bank),.publish(right_publish),.frame_id(right_id),.ready(init[3]),
 .de(valid[3]),.pixel(pixel[48+:16]),.araddr(sar[84+:28]),.arlen(srlen[12+:4]),.arvalid(srv[3]),.arready(srr[3]),.rdata(rd),.rvalid(svalid[3]),.rlast(srlast[3]));
 integer right_tags[0:1];always @(posedge clk) if(right_publish) right_tags[right_bank]<=right_id;
 m3_upload upload(.clk(clk),.rst_n(rst),.online(online_net),.tick_ms(tick_ms),.fps(fps),
 .acquire(acquire),.release_frame(release_frame),.grant(grant),.held(held),.bank(net_bank),.identity(net_id),.stamp(net_time),
 .fragment_ready(fragment_ready),.fragment_taken(fragment_taken),.frame_id(fid),.frame_time(ft),.offset(off),.index(fi),.word_addr(word_address),.word_data(word_data),
 .araddr(sar[112+:28]),.arlen(srlen[16+:4]),.arvalid(srv[4]),.arready(srr[4]),.rdata(rd),.rvalid(svalid[4]),.rlast(srlast[4]),.frames(upload_frames),.aborts());
 assign saw[112+:28]=0;assign swlen[16+:4]=0;assign swv[4]=0;assign swdata[1024+:256]=0;
 reg [7:0] txram[0:2047];always @(posedge clk) if(tx_we) txram[tx_address]<=tx_byte;
 integer raw_packets=0,txi,raw_index,raw_frame,raw_pixel;reg [15:0] raw_expected;
 reg tx_seen=0;
 initial begin wait(rst);forever begin
  wait(tx_req!=tx_seen);@(negedge clk);tx_seen=tx_req;
  if(txram[47]==17) begin
   raw_frame={txram[54],txram[55],txram[56],txram[57]};raw_index={txram[72],txram[73]};
   if(raw_index!=raw_packets%1440 || tx_length!=1370) $fatal(1,"raw sequence/size");
   for(txi=0;txi<640;txi++) begin
    raw_pixel=raw_index*640+txi;raw_expected=pattern(0,raw_frame,raw_pixel/1280,raw_pixel%1280);
    if({txram[91+txi*2],txram[90+txi*2]}!==raw_expected) $fatal(1,"raw oracle frame=%0d fragment=%0d pixel=%0d",raw_frame,raw_index,txi);
   end
   raw_packets++;
  end
  // Real gigabit packet duration, plus IFG; control waits at packet boundary.
  #(8*(tx_length+24));@(negedge clk);tx_ack=tx_req;
 end end
 task put16(input integer o,input integer v);begin packram[o]=v>>8;packram[o+1]=v;end endtask
 task put32(input integer o,input reg [31:0] v);begin packram[o]=v>>24;packram[o+1]=v>>16;packram[o+2]=v>>8;packram[o+3]=v;end endtask
 task packet(input integer kind,input integer sid,input integer fid,input integer idx,input integer eid,input integer seq,input integer ttl,input integer code,input integer reason,input integer corrupt);
 integer n,p,i,s,u,old_ack;reg [15:0] pix;begin
 n=kind==16 ? 1370:90;for(i=0;i<n;i++) packram[i]=0;
 packram[0]=2;packram[2]=8'h47;packram[3]=8'h53;packram[4]=8'h56;packram[5]=8'h31;
 for(i=6;i<12;i++) packram[i]=8'ha0+i;
 put16(12,16'h0800);packram[14]=8'h45;put16(16,n-14);put16(20,16'h4000);packram[22]=64;packram[23]=17;
 put32(26,32'hc0a83201);put32(30,32'hc0a83202);put16(34,50000);put16(36,50000);put16(38,n-34);
 put32(42,32'h47535633);packram[46]=1;packram[47]=kind;packram[48]=kind==16 ? 3:0;packram[49]=1;
 put32(50,sid);put32(54,fid);put32(58,100);put16(62,1280);put16(64,720);
 put32(66,idx*1280);put16(70,kind==16 ? 1280:0);put16(72,idx);put16(74,kind==16 ? 1440:0);
 put32(78,eid);put32(82,seq);put16(86,ttl);packram[88]=code;packram[89]=reason;
 if(kind==16) for(i=0;i<640;i++) begin pix=pattern(3,fid,(idx*640+i)/1280,(idx*640+i)%1280);packram[90+i*2]=pix;packram[91+i*2]=pix>>8;end
 s=0;for(i=14;i<34;i+=2)s=s+{packram[i],packram[i+1]};s=(s&65535)+(s>>16);put16(24,~s);
 s=16'hc0a8+16'h3201+16'hc0a8+16'h3202+17+n-34;
 for(i=34;i<n;i+=2)s=s+{packram[i],packram[i+1]};s=(s&65535)+(s>>16);s=(s&65535)+(s>>16);put16(40,(~s)&65535);
 if(corrupt) packram[80]=packram[80]^1;
 @(negedge clk);old_ack=rack[0];rx_lengths=n;rx_pending=1;wait(rack[0]!=old_ack);@(negedge clk);rx_pending=0;repeat(5) @(negedge clk);
 end endtask

 initial begin
 wait(rst);repeat(20) @(negedge clk);
 packet(1,32'h12345678,0,0,0,0,2000,0,5,0);
 for(integer f=1;f<=4;f++) begin
  for(integer chunk=0;chunk<1440;chunk++) begin
   packet(16,32'h12345678,f,chunk,0,0,2000,0,0,0);
   repeat(50) @(negedge clk);
  end
  $display("RIGHT_FRAME_SENT id=%0d published=%0d",f,right_frames);$fflush();
 end
 end

 reg [255:0] memory[0:518399]; // nine physical slots, all full720p
 function integer idx(input [27:0] a);
  integer source,slot,offset;
  begin
   source=(a>>23)&3;slot=(a>>22)&1;offset=a&4194303;
   if(offset>=460800 || a%8!=0 || a>=28'h2080000) $fatal(1,"invalid address %h",a);
   idx=(a>=28'h2000000 ? 8 : source*2+slot)*57600+offset/8;
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
    0:tag=source[0].input_source.dut.front_three_slots.owner.active_id;
    1:tag=source[1].input_source.dut.two_slots.owner.active_id;
    2:tag=source[2].input_source.dut.two_slots.owner.active_id;
    3:tag=right_id;
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
   wait(arv);@(negedge clk);ra=idx(ar);rn=rl+1;rs=arb.rgrant;while(cycle%8<5) @(negedge clk);arr=1;

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
 m3_video_output #(.PROCESSING_ENABLE(PROCESSING_ENABLE)) video(
  .clk(pc),.rst_n(rst),.timing_rst_n(timing_rst),.selected_view(view),.selected_mode(3'd0),
  .feedback(3'd0),.source_rgb(pixel),.source_de(valid),.show_video(init),.hint_visible(1'b0),.hint_code(4'd0),
  .frame_sync(fs),.source_selected(selected),.source_request(req),
  .hs_out(oh),.vs_out(ov),.de_out(od),.rgb_out(output_rgb));
 // Independent raster counter at the actual output, without DUT coordinates.
 reg osd_delayed;always @(posedge pc) osd_delayed<=video.osd_area;
 reg fault_allowed=0;integer black_pixels=0;
 integer xx=0,yy=0,frames=0,pixels=0,j,srcx,srcy,ss;
 integer tags[0:3]; reg prev_de=0,prev_vs=1,checking=0;
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
    if(ss<4) begin
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
   tags[3]=right_tags[right_store.rbank];
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
  frame(4);frame(3);frame(0);frame(3);
  if(faults!=0) $fatal(1,"normal full load read faults %h",faults);
  wait(upload_frames>=1);
  if(raw_packets<1440 || right_frames<1 || early_r==0 || early_w==0) $fatal(1,"coverage");
  $display("M3_FULL_PASS frames=%0d display_pixels=%0d write_pixels=%0d raw_packets=%0d right_frames=%0d bursts=%0d/%0d earliest=%0d/%0d full_height=720 four_inputs=1 independent_upload=1",frames,pixels,wpixels,raw_packets,right_frames,wb,rb,early_w,early_r);$finish;
 end
 initial begin
  forever begin #10000000;
   $display("FULL_PROGRESS ns=%0t init=%b pubs=%0d/%0d/%0d rejected=%0d/%0d/%0d",$time,init,pubs[31:0],pubs[63:32],pubs[95:64],source[0].input_source.dut.rejected_count,source[1].input_source.dut.rejected_count,source[2].input_source.dut.rejected_count);$fflush();
  end
 end
 initial begin #600000000;$fatal(1,"full timeout");end
endmodule
