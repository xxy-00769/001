`timescale 1ns/1ps
module m36_full_tb #(parameter FPS=15,parameter NET_FRAMES=3);
 reg [15:0] base_pixels[0:921599];reg [255:0] base_beats[0:57599];reg [23:0] gain_lut[0:65535];
 localparam PROCESSING_ENABLE=0; // unchanged algorithms checked against frozen 3.2 evidence
 reg nc=0;always #4 nc=~nc;reg [7:0] rxd=0;reg rxv=0;wire [31:0] mac_crc,mac_over,displayed;wire [63:0] mac_stats;
 GTP_GRS GRS_INST(.GRS_N(1'b1));
 localparam HEIGHT=720;
 reg clk=0,pc=0,v0=0,v1=0,v2=0,rst=0;
 always #5 clk=~clk;
 always #3.367003367 pc=~pc;
 always #11.9 v0=~v0;
 initial begin #3;forever #11.9 v1=~v1;end
 initial begin #1.7;forever #6.7340067 v2=~v2;end
 wire [2:0] vc={v2,v1,v0};reg [2:0] online=7;wire [3:0] req;
 reg [2:0] view=4;
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
  m3_source #(.FRONT(s==0),.SOURCE(s),.HEIGHT(HEIGHT),.RASTER(1),.HD_DISPLAY(1)) input_source(
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

 reg [7:0] packram[0:8191];wire [3:0] rx_pending;wire [3:0] rack;
 wire [63:0] rx_lengths;wire [12:0] rx_address;wire [7:0] rx_byte;

 wire tx_we,tx_req;wire [10:0] tx_address;wire [7:0] tx_byte;wire [15:0] tx_length;wire tx_ack;
 wire right_begin,right_ack,right_publish,right_healthy;wire [1:0] right_bank;wire [31:0] right_id,right_frames;
 wire online_net,tick_ms;wire [7:0] fps;wire fragment_ready,fragment_taken;wire [31:0] fid,ft,off;
 wire [15:0] fi;wire [8:0] word_address;wire [31:0] word_data,upload_frames;
 m3_net_core #(.ENABLE_CONTROL(0),.ENABLE_UPLOAD(0)) core(.clk(clk),.rst_n(rst),.rx_reset_n(1'b1),.rx_pending(rx_pending),.rx_ack(rack),.rx_lengths(rx_lengths),.rx_addr(rx_address),.rx_data(rx_byte),
 .tx_we(tx_we),.tx_addr(tx_address),.tx_data(tx_byte),.tx_req(tx_req),.tx_length(tx_length),.tx_ack(tx_ack),
 .right_begin(right_begin),.right_begin_ack(right_ack),.right_bank(right_bank),.right_publish(right_publish),.right_id(right_id),.right_healthy(right_healthy),
 .awaddr(saw[84+:28]),.awlen(swlen[12+:4]),.awvalid(swv[3]),.awready(swr[3]),.wdata(swdata[768+:256]),.wstrb(),.wready(sready[3]),.wlast(slast[3]),
 .key_event(1'b0),.key_code(4'd0),.latest_front_id(latest_id),.feedback(),.online(online_net),.tick_ms(),.upload_fps(),
 .fragment_ready(1'b0),.fragment_taken(),.front_id(32'd0),.front_time(32'd0),.front_offset(32'd0),.front_index(16'd0),.front_word_addr(),.front_word_data(32'd0),.mac_crc_errors(mac_stats[63:32]),.mac_overruns(mac_stats[31:0]),.displayed_frames(displayed),
 .session(),.rx_packets(),.bad_packets(),.right_frames(right_frames),.right_drops(),.control_events());
 
 m3_right_store #(.HD_DISPLAY(1)) right_store(.clk(clk),.rst_n(rst),.pc(pc),.fs(sampled_sof),.selected(selected[3]),.quarter(quad),.request(sampled_request[3]),
 .begin_frame(right_begin),.begin_ack(right_ack),.write_bank(right_bank),.publish(right_publish),.frame_id(right_id),.ready(init[3]),.displayed_frames(displayed),
 .de(valid[3]),.pixel(pixel[48+:16]),.araddr(sar[84+:28]),.arlen(srlen[12+:4]),.arvalid(srv[3]),.arready(srr[3]),.rdata(rd),.rvalid(svalid[3]),.rlast(srlast[3]));
 integer right_tags[0:2];always @(posedge clk) if(right_publish) right_tags[right_bank]<=right_id;

 reg nc2=0;initial begin #1.137;forever #4.0008 nc2=~nc2;end
 reg [7:0] rxd2=0;reg rxv2=0,link2=1;wire online2;
 wire [3:0] pending2,ack2;wire [63:0] lengths2,stats2;wire [12:0] ra2;wire [7:0] rd2;
 wire tw2,tr2,ta2;wire [10:0] twa2;wire [7:0] twd2;wire [15:0] tl2;
 wire [31:0] session2;wire [2:0] feedback2;reg ke2=0;reg [3:0] kc2=1;
 wire [7:0] mac_tx2;wire mac_tv2;
 m3_mac mac2(.nc(nc2),.nrst(rst && link2),.rxd(rxd2),.rxv(rxv2),.rxe(1'b0),.txd(mac_tx2),.txv(mac_tv2),
 .dc(clk),.drst(rst && link2),.rx_pending(pending2),.rx_ack(ack2),.rx_lengths(lengths2),.rx_addr(ra2),.rx_data(rd2),
 .tx_we(tw2),.tx_addr(twa2),.tx_data(twd2),.tx_req(tr2),.tx_length(tl2),.tx_ack(ta2),.crc_errors(),.rx_overruns(),.rx_stats(stats2));
 m3_net_core #(.ENABLE_VIDEO(0),.REQUIRE_LINK(1),.LOCAL_MAC(48'h020047535632),.LOCAL_IP(32'hc0a83c02),.HOST_IP(32'hc0a83c01)) core2(
 .clk(clk),.rst_n(rst),.rx_reset_n(link2),.rx_pending(pending2),.rx_ack(ack2),.rx_lengths(lengths2),.rx_addr(ra2),.rx_data(rd2),
 .tx_we(tw2),.tx_addr(twa2),.tx_data(twd2),.tx_req(tr2),.tx_length(tl2),.tx_ack(ta2),
 .right_begin(),.right_begin_ack(1'b0),.right_bank(2'd0),.right_publish(),.right_id(),.right_healthy(),
 .awaddr(),.awlen(),.awvalid(),.awready(1'b0),.wdata(),.wstrb(),.wready(1'b0),.wlast(1'b0),
 .key_event(ke2),.key_code(kc2),.latest_front_id(latest_id),.feedback(feedback2),.online(online2),.tick_ms(tick_ms),.upload_fps(fps),
 .fragment_ready(fragment_ready),.fragment_taken(fragment_taken),.front_id(fid),.front_time(ft),.front_offset(off),.front_index(fi),.front_word_addr(word_address),.front_word_data(word_data),
 .mac_crc_errors(stats2[63:32]),.mac_overruns(stats2[31:0]),.displayed_frames(32'd0),.session(session2),.rx_packets(),.bad_packets(),.right_frames(),.right_drops(),.control_events());
 always @(posedge clk) if(rst && (core2.awvalid || core2.right_publish || core2.right_begin || core.upload_fps!=0 || core.feedback!=0)) $fatal(1,"role routing");

 m3_upload upload(.clk(clk),.rst_n(rst),.online(online2),.tick_ms(tick_ms),.fps(fps),
 .acquire(acquire),.release_frame(release_frame),.grant(grant),.held(held),.bank(net_bank),.identity(net_id),.stamp(net_time),
 .fragment_ready(fragment_ready),.fragment_taken(fragment_taken),.frame_id(fid),.frame_time(ft),.offset(off),.index(fi),.word_addr(word_address),.word_data(word_data),
 .araddr(sar[112+:28]),.arlen(srlen[16+:4]),.arvalid(srv[4]),.arready(srr[4]),.rdata(rd),.rvalid(svalid[4]),.rlast(srlast[4]),.frames(upload_frames),.aborts());
 assign saw[112+:28]=0;assign swlen[16+:4]=0;assign swv[4]=0;assign swdata[1024+:256]=0;
 // Real production MAC includes independent full-duplex front upload TX.
 wire [7:0] mac_tx;wire mac_tv;
 m3_mac mac(.nc(nc),.nrst(rst),.rxd(rxd),.rxv(rxv),.rxe(1'b0),.txd(mac_tx),.txv(mac_tv),
 .dc(clk),.drst(rst),.rx_pending(rx_pending),.rx_ack(rack),.rx_lengths(rx_lengths),.rx_addr(rx_address),.rx_data(rx_byte),
 .tx_we(tx_we),.tx_addr(tx_address),.tx_data(tx_byte),.tx_req(tx_req),.tx_length(tx_length),.tx_ack(tx_ack),.crc_errors(mac_crc),.rx_overruns(mac_over),.rx_stats(mac_stats));

 reg [7:0] txram[0:2047];integer tx_size=0,raw_packets=0,txi,raw_index,raw_frame,raw_pixel;
 reg [15:0] raw_expected;reg tx_active=0,tx_prev=0;reg [31:0] tx_crc;
 function [31:0] crc(input [31:0] v,input [7:0] d);
 reg [31:0] x;integer j;begin x=v;for(j=0;j<8;j++) x=(x[0]^d[j])?(x>>1)^32'hedb88320:x>>1;crc=x;end endfunction
 always @(negedge nc2) begin
  if(mac_tv2) begin
   if(!tx_active) begin if(mac_tx2==8'hd5) begin tx_active=1;tx_size=0;tx_crc=~0;end end
   else begin txram[tx_size]=mac_tx2;tx_size++;tx_crc=crc(tx_crc,mac_tx2);end
  end else if(tx_active) begin
   if(tx_crc!==32'hdebb20e3) $fatal(1,"upload/control MAC FCS");
   if(txram[47]==17) begin
    raw_frame={txram[54],txram[55],txram[56],txram[57]};raw_index={txram[72],txram[73]};
    if(raw_index!=raw_packets%1440 || tx_size!=1374) $fatal(1,"front upload sequence/size");
    for(txi=0;txi<640;txi++) begin
     raw_pixel=raw_index*640+txi;raw_expected=base_pixels[raw_pixel]^((raw_frame*16'h19d7)&16'h3fff);
     if({txram[91+txi*2],txram[90+txi*2]}!==raw_expected) $fatal(1,"clean front oracle");
    end
    raw_packets++;
   end
   tx_active=0;
  end
 end
 task wire_packet(input integer size);
 integer z;reg [31:0] cv;begin
 @(negedge nc);rxv=1;rxd=8'h55;repeat(7) @(negedge nc);rxd=8'hd5;@(negedge nc);cv=~0;
 for(z=0;z<size;z++) begin rxd=packram[z];cv=crc(cv,rxd);@(negedge nc);end
 cv=~cv;for(z=0;z<4;z++) begin rxd=cv>>(8*z);@(negedge nc);end
 rxv=0;rxd=0;repeat(12) @(negedge nc);
 end endtask
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
 @(negedge clk);wire_packet(n);
 end endtask

 reg [7:0] packram2[0:8191];
 task wire_packet2(input integer size);
 integer z;reg [31:0] cv;begin
 @(negedge nc2);rxv2=1;rxd2=8'h55;repeat(7) @(negedge nc2);rxd2=8'hd5;@(negedge nc2);cv=~0;
 for(z=0;z<size;z++) begin rxd2=packram2[z];cv=crc(cv,rxd2);@(negedge nc2);end
 cv=~cv;for(z=0;z<4;z++) begin rxd2=cv>>(8*z);@(negedge nc2);end
 rxv2=0;rxd2=0;repeat(12) @(negedge nc2);
 end endtask
 task put16b(input integer o,input integer v);begin packram2[o]=v>>8;packram2[o+1]=v;end endtask
 task put32b(input integer o,input reg [31:0] v);begin packram2[o]=v>>24;packram2[o+1]=v>>16;packram2[o+2]=v>>8;packram2[o+3]=v;end endtask
 task packet2(input integer kind,input integer sid,input integer fid,input integer idx,input integer eid,input integer seq,input integer ttl,input integer code,input integer reason,input integer corrupt);
 integer n,p,i,s,u,old_ack;reg [15:0] pix;begin
 n=kind==16 ? 1370:90;for(i=0;i<n;i++) packram2[i]=0;
 packram2[0]=2;packram2[2]=8'h47;packram2[3]=8'h53;packram2[4]=8'h56;packram2[5]=8'h32;
 for(i=6;i<12;i++) packram2[i]=8'ha0+i;
 put16b(12,16'h0800);packram2[14]=8'h45;put16b(16,n-14);put16b(20,16'h4000);packram2[22]=64;packram2[23]=17;
 put32b(26,32'hc0a83c01);put32b(30,32'hc0a83c02);put16b(34,50000);put16b(36,50000);put16b(38,n-34);
 put32b(42,32'h47535633);packram2[46]=1;packram2[47]=kind;packram2[48]=kind==16 ? 3:0;packram2[49]=1;
 put32b(50,sid);put32b(54,fid);put32b(58,100);put16b(62,1280);put16b(64,720);
 put32b(66,idx*1280);put16b(70,kind==16 ? 1280:0);put16b(72,idx);put16b(74,kind==16 ? 1440:0);
 put32b(78,eid);put32b(82,seq);put16b(86,ttl);packram2[88]=code;packram2[89]=reason;
 if(kind==16) for(i=0;i<640;i++) begin pix=pattern(3,fid,(idx*640+i)/1280,(idx*640+i)%1280);packram2[90+i*2]=pix;packram2[91+i*2]=pix>>8;end
 s=0;for(i=14;i<34;i+=2)s=s+{packram2[i],packram2[i+1]};s=(s&65535)+(s>>16);put16b(24,~s);
 s=16'hc0a8+16'h3c01+16'hc0a8+16'h3c02+17+n-34;
 for(i=34;i<n;i+=2)s=s+{packram2[i],packram2[i+1]};s=(s&65535)+(s>>16);s=(s&65535)+(s>>16);put16b(40,(~s)&65535);
 if(corrupt) packram2[80]=packram2[80]^1;
 @(negedge clk);wire_packet2(n);
 end endtask

 reg control_done=0;integer preserved_sid;
 initial begin
  wait(rst);repeat(25) @(negedge clk);
  packet2(1,32'h22345678,0,0,0,0,2000,0,5,0);wait(online2);
  // Wrong-role video must be rejected without a DDR request.
  packet2(16,32'h22345678,99,0,0,0,2000,0,0,0);
  wait(raw_packets>=1440); // a complete 720-line upload checked byte for byte
  @(negedge clk);ke2=1;@(negedge clk);ke2=0;
  repeat(20) @(negedge clk);
  packet2(6,32'h22345678,core2.event_frame,0,1,1,2000,1,0,0);
  wait(feedback2==1);
  packet2(5,32'h22345678,core2.event_frame,0,1,0,2000,0,0,0);
  preserved_sid=core2.session;
  // Expire/restart only port1 while keeping port2 alive. Port1 cannot own feedback.
  // Port1 rejects control traffic in the separate role/session test.
  if(feedback2!=1 || core2.session!=preserved_sid) $fatal(1,"port1 result changed port2");
  // Drop port2 with a live read. The accepted return must drain before release.
  // Once the clean 5fps-requested frame is complete, use the already
  // supported 15fps request solely to bring the abort test forward in time.
  packet2(1,32'h22345678,0,0,0,0,2000,0,15,0);
  wait(upload.arvalid);wait(upload.arready);@(negedge clk);link2=0;
  wait(!held);repeat(20) @(negedge clk);
  if(feedback2!=0 || core.session!=32'h12345678) $fatal(1,"port2 disconnect isolation");
  link2=1;repeat(30) @(negedge clk);
  packet2(1,32'h22345678,0,0,0,0,2000,0,5,0);wait(online2);
  control_done=1;
 end
 integer up_outstanding=0;
 always @(posedge clk) if(rst) begin
  if(release_frame && up_outstanding!=0) $fatal(1,"upload released accepted DDR before drain");
  if(srv[4] && srr[4]) up_outstanding=up_outstanding+srlen[16+:4]+1;
  if(svalid[4]) up_outstanding=up_outstanding-1;
 end
 integer sent_frames=0;realtime deadline,frame_started,packet_started;
 initial begin
 wait(rst);repeat(20) @(negedge clk);
 packet(1,32'h12345678,0,0,0,0,2000,0,5,0);wait(online_net);
 // Start with a packet phase offset relative to SOF, never wait for consumer ACK.
 #12577;
 for(integer f=1;f<=NET_FRAMES;f++) begin
  frame_started=$realtime;
  for(integer chunk=0;chunk<1440;chunk++) begin
   packet_started=$realtime;
   packet(16,32'h12345678,f,chunk,0,0,2000,0,0,0);
   // Two consecutive packets at wire speed once per frame cause pending wrap.
   // Repay this burst gap on the second packet, preserving offered fps.
   deadline=packet_started+1.0e9/(FPS*1440);
   if(chunk==81) deadline=packet_started+2.0e9/(FPS*1440)-11200;
   if(chunk!=80 && deadline>$realtime) #(deadline-$realtime);
  end
  sent_frames++;
  packet(3,32'h12345678,0,0,0,0,2000,0,0,0);
  $display("RIGHT_FRAME_SENT fps=%0d id=%0d published=%0d over=%0d drops=%0d",FPS,f,right_frames,mac_over,core.right_drops);$fflush();
 end
 end

 reg [255:0] memory[0:575999]; // nine physical slots, all full720p
 function integer idx(input [27:0] a);
  integer source,slot,offset;
  begin
   source=(a>>23)&3;slot=(a>>22)&1;offset=a&4194303;
   if(offset>=460800 || a%8!=0 || a>=28'h2480000) $fatal(1,"invalid address %h",a);
   idx=(a>=28'h2400000 ? 9 : a>=28'h2000000 ? 8 : source*2+slot)*57600+offset/8;
  end
 endfunction
 function [15:0] pattern(input integer source,tag,row,col);
  pattern=(source<<14)|(((tag*16'h19d7)^(row*16'h031d)^(col*16'h9e37))&16'h3fff);
 endfunction
 // Precompute the independent oracle once; checks still cover every pixel.
 // This avoids redoing 16 integer multiply/divides per native beat in vvp.

 integer oy,ox,oi;reg [15:0] mask;
 initial begin
  for(oy=0;oy<720;oy++) for(ox=0;ox<1280;ox++) begin
   oi=oy*1280+ox;base_pixels[oi]=pattern(0,0,oy,ox);base_beats[oi/16][(oi%16)*16+:16]=base_pixels[oi];
  end
  for(oi=0;oi<65536;oi++) gain_lut[oi]=gain(oi);
 end
 integer wb=0,rb=0,wpixels=0,early_w=0,early_r=0;
 // One shared 256-bit data bus service calendar (write 5/8, read 3/8).
 // Address channels remain independent, as in the native interface.
 reg native_write_active=0;integer cycle=0;always @(posedge clk) cycle<=cycle+1;
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
   a=idx(aw);n=wl+1;src=aw>=28'h2400000 ? 3 : aw>=28'h2000000 ? 0 : aw[24:23];
   case(src)
    0:tag=source[0].input_source.dut.front_three_slots.owner.active_id;
    1:tag=source[1].input_source.dut.two_slots.owner.active_id;
    2:tag=source[2].input_source.dut.two_slots.owner.active_id;
    3:tag=right_id;
   endcase
   if(src==3 && wb%2003==1001) #3000;
   wy=aw[21:0]/640;wx=(aw[21:0]%640)*2;// Native HMIC requests each accepted write burst contiguously. Stall
   // before its first data request; read returns retain legal internal gaps.
   while(rv) @(negedge clk);native_write_active=1;awr=1;
   if(wb%2) begin @(posedge clk);@(negedge clk);awr=0;end

   for(b=0;b<n;b++) begin

    wr=1;last=b==n-1;@(posedge clk);
    if(sready!==(1<<src)) $fatal(1,"write owner mismatch");
    memory[a+b]=wd;
    mask=(src<<14)|((tag*16'h19d7)&16'h3fff);
    if(wd!==(base_beats[(aw[21:0]>>3)+b] ^ {16{mask}}))
     $fatal(1,"write vector oracle src=%0d tag=%0d address=%h beat=%0d",src,tag,aw,b);
    wpixels+=16;
    @(negedge clk);awr=0;wr=0;last=0;
   end
   native_write_active=0;wb++;
  end
 end
 reg stall=0,allow_old_tail=0,old_bank=0;integer ra,rn,rr,rs;
 initial begin
  wait(rst);
  forever begin
   wait(arv);@(negedge clk);ra=idx(ar);rn=rl+1;rs=arb.rgrant;while(cycle%8<5 || native_write_active) @(negedge clk);arr=1;

   if(rb%2 || stall) begin @(posedge clk);@(negedge clk);arr=0;while(stall) @(negedge clk);end

   for(rr=0;rr<rn;rr++) begin
    if(rr%5==2 || rr==rn-1) repeat(2+(rb%3)) @(negedge clk);
    while(cycle%8<5 || native_write_active) @(negedge clk);
    rd=memory[ra+rr];rv=1;rlast=rr==rn-1;@(posedge clk);
    if(svalid!==(1<<rs)) $fatal(1,"return crossed source");
    @(negedge clk);arr=0;rv=0;rlast=0;
   end
   rb++;
  end
 end
 wire oh,ov,od; wire [23:0] output_rgb;
 m31_video_output #(.PROCESSING_ENABLE(PROCESSING_ENABLE)) video(
  .clk(pc),.rst_n(rst),.timing_rst_n(timing_rst),.selected_view(view),.selected_mode(3'd0),
  .feedback(3'd0),.source_rgb(pixel),.source_de(valid),.show_video(init),.hint_visible(1'b0),.hint_code(4'd0),
  .frame_sync(fs),.source_selected(selected),.source_request(req),
  .hs_out(oh),.vs_out(ov),.de_out(od),.rgb_out(output_rgb));
 // Independent final output raster, compare every visible pixel outside OSD.
 reg osd_delayed;always @(posedge pc) osd_delayed<=video.osd_area;
 integer xx=0,yy=0,frames=0,pixels=0,srcx,srcy,ss;integer tags[0:3];
 reg prev_de=0,prev_vs=0,checking=0;reg [23:0] expected888;
 function [23:0] gain(input [15:0] c);
  integer r,g,b;
  begin r={c[15:11],c[15:13]};g={c[10:5],c[10:9]};b={c[4:0],c[4:2]};
   r=r+(r>>2);g=g+(g>>2);b=b+(b>>2);
   gain={(r>255?8'd255:r[7:0]),(g>255?8'd255:g[7:0]),(b>255?8'd255:b[7:0])};
  end
 endfunction
 always @(posedge pc) begin
  #0.2;
  if(ov && !prev_vs) begin xx=0;yy=0;end
  if(od) begin
   if(!prev_de) xx=0;
   if(checking) begin
    expected888=0;
    if(quad || (xx>=320 && xx<1600 && yy>=180 && yy<900)) begin
     ss=quad ? xx/960+2*(yy/540) : view;
     srcx=quad ? (xx%960)*4/3 : xx-320;srcy=quad ? (yy%540)*4/3 : yy-180;
     expected888=gain_lut[base_pixels[srcy*1280+srcx]^((ss<<14)|((tags[ss]*16'h19d7)&16'h3fff))];
    end
    if(!osd_delayed && output_rgb!==expected888)
     $fatal(1,"FULL_HD oracle frame=%0d view=%0d source=%0d tag=%0d xy=%0d,%0d got=%h want=%h",frames,view,ss,tags[ss],xx,yy,output_rgb,expected888);
    pixels++;
   end
   xx++;
  end
  if(!od && prev_de) begin if(xx!=1920) $fatal(1,"panel width %0d",xx);yy++;end
  prev_de=od;prev_vs=ov;
 end
 task frame(input integer v);begin
  checking=0;wait(fs);@(negedge pc);view=v;
  repeat(100) @(negedge pc);
  for(integer k=0;k<3;k++) tags[k]=display_ids[k*32+:32];
  tags[3]=right_tags[right_store.rbank];checking=1;
  @(negedge fs);@(posedge fs);checking=0;
  if(yy!=1080) $fatal(1,"panel height %0d",yy);
  frames++;$display("FULL_HD_FRAME frame=%0d view=%0d pubs=%0d/%0d/%0d pixels=%0d right=%0d displayed=%0d",frames,view,pubs[31:0],pubs[63:32],pubs[95:64],pixels,right_frames,displayed);$fflush();
 end endtask
 initial begin
  #500;rst=1;@(negedge pc);timing_rst=1;
  wait(&init);
  // init can rise inside the current VS interval AFTER its ownership swap.
  // Begin the oracle at the next complete SOF, as actual startup allows.
  @(negedge fs);frame(4);frame(3);
  wait(sent_frames==NET_FRAMES && right_frames==NET_FRAMES && upload_frames>=1 && control_done);
  if(raw_packets<1440) wait(raw_packets>=1440);
  if(faults!=0 || mac_crc!=0 || mac_over!=0 || core.right_drops!=0 || core.bad_packets!=0) $fatal(1,"load faults capture=%h crc=%0d over=%0d drops=%0d bad=%0d",faults,mac_crc,mac_over,core.right_drops,core.bad_packets);
  $display("M36_FULL_PASS offered_fps=%0d network_complete_frames=%0d displayed_changes=%0d output_frames=%0d checked_pixels=%0d write_pixels=%0d front_raw_packets=%0d bursts=%0d/%0d production_MAC=2 independent_clocks=1 port2_disconnect=1 wrong_role_rejected=1 full_height=720 hd1080p60=1",FPS,right_frames,displayed,frames,pixels,wpixels,raw_packets,wb,rb);$finish;
 end

 initial begin
  forever begin #10000000;
   $display("FULL_PROGRESS ns=%0t init=%b pubs=%0d/%0d/%0d rejected=%0d/%0d/%0d",$time,init,pubs[31:0],pubs[63:32],pubs[95:64],source[0].input_source.dut.rejected_count,source[1].input_source.dut.rejected_count,source[2].input_source.dut.rejected_count);$fflush();
  end
 end
 initial begin #1200000000;$fatal(1,"full timeout");end
endmodule
