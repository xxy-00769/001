`timescale 1ns/1ps
module m36_roles_tb;
 GTP_GRS GRS_INST(.GRS_N(1'b1));
 reg c=0,rst=0;always #5 c=~c;
 reg [1:0] link=3,ke=0;reg [3:0] keycode=1;
 reg [7:0] mem[0:16383];reg [3:0] req[0:1];wire [3:0] ack[0:1];
 reg [63:0] lengths[0:1];wire [12:0] ra[0:1];reg [7:0] rd[0:1];
 wire [31:0] session[0:1],ev[0:1],bad[0:1];wire [2:0] fb[0:1];wire [7:0] fps[0:1];wire [1:0] online;
 wire [1:0] tw,tr,av,rp,beginframe;wire [10:0] ta[0:1];wire [7:0] td[0:1];wire [15:0] tl[0:1];reg [1:0] tack=0;
 integer writes[0:1],results[0:1],events[0:1],txkind[0:1],prod[0:1];
 genvar g;generate for(g=0;g<2;g++) begin: ep
  always @(posedge c) rd[g]<=mem[g*8192+ra[g]];
  m3_net_core #(.ENABLE_VIDEO(g==0),.ENABLE_CONTROL(g==1),.ENABLE_UPLOAD(g==1),.REQUIRE_LINK(1),.MS_CYCLES(100),
   .LOCAL_MAC(g==0 ? 48'h020047535631:48'h020047535632),.LOCAL_IP(g==0 ? 32'hc0a83202:32'hc0a83c02),.HOST_IP(g==0 ? 32'hc0a83201:32'hc0a83c01)) u(
   .clk(c),.rst_n(rst),.rx_reset_n(link[g]),.rx_pending(req[g]^ack[g]),.rx_ack(ack[g]),.rx_lengths(lengths[g]),.rx_addr(ra[g]),.rx_data(rd[g]),
   .tx_we(tw[g]),.tx_addr(ta[g]),.tx_data(td[g]),.tx_req(tr[g]),.tx_length(tl[g]),.tx_ack(tack[g]),
   .right_begin(beginframe[g]),.right_begin_ack(1'b1),.right_bank(2'd0),.right_publish(rp[g]),.right_id(),.right_healthy(),
   .awaddr(),.awlen(),.awvalid(av[g]),.awready(1'b1),.wdata(),.wstrb(),.wready(1'b1),.wlast(1'b1),
   .key_event(ke[g]),.key_code(keycode),.latest_front_id(32'd55),.feedback(fb[g]),.online(online[g]),.tick_ms(),.upload_fps(fps[g]),
   .fragment_ready(1'b0),.fragment_taken(),.front_id(32'd0),.front_time(32'd0),.front_offset(32'd0),.front_index(16'd0),.front_word_addr(),.front_word_data(32'd0),
   .mac_crc_errors(32'd0),.mac_overruns(32'd0),.displayed_frames(32'd0),.session(session[g]),.rx_packets(),.bad_packets(bad[g]),.right_frames(),.right_drops(),.control_events(ev[g]));
  always @(posedge c) if(rst) begin
   if(av[g]) writes[g]=writes[g]+1;
   if(tw[g] && ta[g]==47) txkind[g]=td[g];
   if(tr[g]!=tack[g]) begin
    if(txkind[g]==7) results[g]=results[g]+1;
    if(txkind[g]==4) events[g]=events[g]+1;
    tack[g]<=tr[g];
   end
  end
 end endgenerate
 reg [7:0] packetmem[0:1370];
 task put16(input integer o,v);begin packetmem[o]=v>>8;packetmem[o+1]=v;end endtask
 task put32(input integer o,input [31:0] v);begin packetmem[o]=v>>24;packetmem[o+1]=v>>16;packetmem[o+2]=v>>8;packetmem[o+3]=v;end endtask
 task packet(input integer port,kind,input [31:0] sid,input integer frame,eid,seq,ttl,code,reason);
 integer n,i,s,slot;reg prior;begin
  n=kind==16 ? 1370:90;for(i=0;i<n;i++) packetmem[i]=0;
  packetmem[0]=2;packetmem[2]=8'h47;packetmem[3]=8'h53;packetmem[4]=8'h56;packetmem[5]=8'h31+port;
  for(i=6;i<12;i++) packetmem[i]=8'hb0+i;
  put16(12,16'h0800);packetmem[14]=8'h45;put16(16,n-14);put16(20,16'h4000);packetmem[22]=64;packetmem[23]=17;
  put32(26,port==0 ? 32'hc0a83201:32'hc0a83c01);put32(30,port==0 ? 32'hc0a83202:32'hc0a83c02);
  put16(34,50000);put16(36,50000);put16(38,n-34);
  put32(42,32'h47535633);packetmem[46]=1;packetmem[47]=kind;packetmem[48]=kind==16 ? 3:0;packetmem[49]=1;
  put32(50,sid);put32(54,frame);put16(62,1280);put16(64,720);put16(70,kind==16 ? 1280:0);put16(74,kind==16 ? 1440:0);
  put32(78,eid);put32(82,seq);put16(86,ttl);packetmem[88]=code;packetmem[89]=reason;
  s=0;for(i=14;i<34;i+=2) s=s+{packetmem[i],packetmem[i+1]};s=(s&65535)+(s>>16);put16(24,~s);
  // UDP checksum zero is legal and does not bypass the IPv4/header checks.
  slot=prod[port];for(i=0;i<n;i++) mem[port*8192+slot*2048+i]=packetmem[i];
  @(negedge c);prior=ack[port][slot];lengths[port][slot*16+:16]=n;req[port][slot]=~req[port][slot];
  wait(ack[port][slot]!=prior);@(negedge c);prod[port]=(slot+1)%4;repeat(8) @(negedge c);
 end endtask
 initial begin
  for(integer p=0;p<2;p++) begin req[p]=0;lengths[p]=0;writes[p]=0;results[p]=0;events[p]=0;txkind[p]=0;prod[p]=0;end
  #100;rst=1;
  packet(0,1,32'h1111,0,0,0,2000,0,30);packet(1,1,32'h2222,0,0,0,2000,0,5);
  if(online!=3 || fps[0]!=0 || fps[1]!=5) $fatal(1,"role HELLO");
  packet(1,16,32'h2222,1,0,0,2000,0,0);
  if(writes[1]!=0 || beginframe[1] || bad[1]==0) $fatal(1,"port2 video accepted");
  @(negedge c);ke=3;@(negedge c);ke=0;repeat(5) @(negedge c);
  if(ev[0]!=0 || ev[1]!=1) $fatal(1,"key role");
  packet(0,6,32'h1111,55,1,1,2000,2,1);
  packet(1,6,32'h2222,55,1,1,2000,1,0);if(fb[1]!=1 || fb[0]!=0) $fatal(1,"result role");
  packet(1,6,32'h2222,54,1,2,2000,2,1);if(fb[1]!=1) $fatal(1,"wrong frame");
  packet(1,6,32'h1111,55,1,3,2000,2,1);if(fb[1]!=1) $fatal(1,"wrong session");
  packet(1,6,32'h2222,55,1,1,2000,2,1);if(fb[1]!=1) $fatal(1,"duplicate result");
  // Only port1 times out and starts a new session while port2 stays alive.
  for(integer h=0;h<6;h++) begin
   repeat(40000) @(negedge c);packet(1,3,32'h2222,0,0,0,2000,0,0);
  end
  if(online[0] || !online[1] || fb[1]!=0) $fatal(1,"independent timeout/TTL");
  packet(0,1,32'h3333,0,0,0,2000,0,0);
  if(session[1]!=32'h2222 || ev[1]!=1) $fatal(1,"port1 restart reset port2");
  @(negedge c);keycode=4;ke=2;@(negedge c);ke=0;
  packet(1,6,32'h2222,55,2,1,2000,2,1);if(fb[1]!=3) $fatal(1,"alarm");
  link[0]=0;repeat(5) @(negedge c);req[0]=0;prod[0]=0;
  if(fb[1]!=3 || !online[1]) $fatal(1,"port1 PHY reset changed port2");
  link[0]=1;repeat(10) @(negedge c);
  link[1]=0;repeat(5) @(negedge c);req[1]=0;prod[1]=0;
  if(fb[1]!=0 || !online[0]) $fatal(1,"port2 link loss/isolation");
  link[1]=1;repeat(10) @(negedge c);
  packet(1,1,32'h2222,0,0,0,2000,0,5);
  packet(0,16,32'h3333,1,0,0,2000,0,0);if(writes[0]!=40) $fatal(1,"port1 video after reconnect");
  if(results[0]!=0 || events[0]!=0 || ev[0]!=0 || writes[1]!=0) $fatal(1,"cross-role traffic");
  $display("M36_ROLES_PASS endpoint_mac_ip=1 session_isolation=1 wrong_role=1 key_binding=1 stale_result=1 timeout=1 PHY_epoch=1 writes=%0d/%0d",writes[0],writes[1]);$finish;
 end
 initial begin #10000000;$fatal(1,"roles timeout");end
endmodule
