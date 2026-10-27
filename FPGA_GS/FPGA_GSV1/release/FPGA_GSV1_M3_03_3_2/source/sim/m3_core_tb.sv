`timescale 1ns/1ps
module m3_core_tb;
 reg c=0,rst=0;always #5 c=~c;
 reg [7:0] memory[0:8191];wire [12:0] ra;reg [7:0] rd;
 always @(posedge c) rd<=memory[ra];
 reg [3:0] pending=0;wire [3:0] ack;reg [63:0] lengths=0;
 wire tw,tr;wire [10:0] ta;wire [7:0] td;wire [15:0] tl;reg tack=0;
 wire rb,rp;reg rack=0,rbank=0;wire [31:0] rid;wire healthy;
 wire [27:0] aw;wire [3:0] wl;wire av;wire [255:0] wd;wire [31:0] strb;
 reg wr=0;wire ar=av;reg ke=0;reg [3:0] kc=0;wire [2:0] feedback;
 wire online,tick;wire [7:0] fps;wire [31:0] session,packets,bad,frames,drops,events;
 reg frag=0;wire ft;wire [8:0] fwa;reg [31:0] fwd=32'hf80007e0;
 m3_net_core #(.MS_CYCLES(100)) dut(.clk(c),.rst_n(rst),.rx_pending(pending),.rx_ack(ack),.rx_lengths(lengths),.rx_addr(ra),.rx_data(rd),
 .tx_we(tw),.tx_addr(ta),.tx_data(td),.tx_req(tr),.tx_length(tl),.tx_ack(tack),
 .right_begin(rb),.right_begin_ack(rack),.right_bank(rbank),.right_publish(rp),.right_id(rid),.right_healthy(healthy),
 .awaddr(aw),.awlen(wl),.awvalid(av),.awready(ar),.wdata(wd),.wstrb(strb),.wready(wr),.wlast(wr),
 .key_event(ke),.key_code(kc),.latest_front_id(32'd55),.feedback(feedback),.online(online),.tick_ms(tick),.upload_fps(fps),
 .fragment_ready(frag),.fragment_taken(ft),.front_id(32'd99),.front_time(32'd100),.front_offset(32'd0),.front_index(16'd0),.front_word_addr(fwa),.front_word_data(fwd),
 .session(session),.rx_packets(packets),.bad_packets(bad),.right_frames(frames),.right_drops(drops),.control_events(events));
 integer writes=0,txpack=0,eventpack=0,resultacks=0;reg [7:0] txmem[0:2047];reg txseen=0;
 always @(posedge c) begin
  if(tw) txmem[ta]<=td;
  rack<=rb && !rack;
  if(rb && !rack) rbank<=!rbank;
 end
 // Alternate earliest first beat with a later native data request.
 reg [2:0] waitw=0;reg data_pending=0;reg [27:0] saved_aw;
 always @(negedge c) begin
  wr=0;
  if(data_pending) begin
   if(waitw==0) begin wr=1;data_pending=0;end else waitw=waitw-1;
  end else if(av) begin
   saved_aw=aw;
   if(writes%2==0) wr=1;else begin data_pending=1;waitw=2;end
  end
 end
 integer lane;reg [15:0] want;
 always @(posedge c) if(wr) begin
  if(strb!==32'hffffffff || wl!=0) $fatal(1,"write format");
  for(lane=0;lane<16;lane++) begin
   want=16'hc000|(((writes%40)*16+lane)&16'h3fff);
   if(wd[lane*16+:16]!==want) $fatal(1,"right packing write=%0d lane=%0d %h %h",writes,lane,wd[lane*16+:16],want);
  end
  if((aw & 28'h1ffffff)<28'h1800000 || aw[21:0]>=460800) $fatal(1,"right address");
  writes++;
 end
 function [31:0] gettx(input integer o);gettx={txmem[o],txmem[o+1],txmem[o+2],txmem[o+3]};endfunction
 integer sum,j;
 always @(negedge c) if(tr!=txseen) begin
  txseen=tr;txpack++;
  sum=0;for(j=14;j<34;j+=2) sum=sum+{txmem[j],txmem[j+1]};sum=(sum&65535)+(sum>>16);
  if(sum!=65535 || gettx(42)!=32'h47535633 || tl<90) $fatal(1,"TX IPv4/header");
  if(txmem[47]==4) begin
   if(gettx(54)!=55 || gettx(78)!=dut.event_id || txmem[88]!=dut.action) $fatal(1,"event metadata");eventpack++;
  end
  if(txmem[47]==7) resultacks++;
  repeat(3) @(negedge c);tack=tr;
 end
 task put16(input integer o,input integer v);begin memory[o]=v>>8;memory[o+1]=v;end endtask
 task put32(input integer o,input reg [31:0] v);begin memory[o]=v>>24;memory[o+1]=v>>16;memory[o+2]=v>>8;memory[o+3]=v;end endtask
 task packet(input integer kind,input integer sid,input integer fid,input integer idx,input integer eid,input integer seq,input integer ttl,input integer code,input integer reason,input integer corrupt);
 integer n,p,i,s,u,old_ack;reg [15:0] pix;begin
 n=kind==16 ? 1370:90;for(i=0;i<n;i++) memory[i]=0;
 memory[0]=2;memory[2]=8'h47;memory[3]=8'h53;memory[4]=8'h56;memory[5]=8'h31;
 for(i=6;i<12;i++) memory[i]=8'ha0+i;
 put16(12,16'h0800);memory[14]=8'h45;put16(16,n-14);put16(20,16'h4000);memory[22]=64;memory[23]=17;
 put32(26,32'hc0a83201);put32(30,32'hc0a83202);put16(34,50000);put16(36,50000);put16(38,n-34);
 put32(42,32'h47535633);memory[46]=1;memory[47]=kind;memory[48]=kind==16 ? 3:0;memory[49]=1;
 put32(50,sid);put32(54,fid);put32(58,100);put16(62,1280);put16(64,720);
 put32(66,idx*1280);put16(70,kind==16 ? 1280:0);put16(72,idx);put16(74,kind==16 ? 1440:0);
 put32(78,eid);put32(82,seq);put16(86,ttl);memory[88]=code;memory[89]=reason;
 if(kind==16) for(i=0;i<640;i++) begin pix=16'hc000|i;memory[90+i*2]=pix;memory[91+i*2]=pix>>8;end
 if(corrupt==2) put16(62,1279);
 if(corrupt==3) put16(70,1248);
 if(corrupt==4) put16(72,1440);
 if(corrupt==5) put32(66,32'hffffffff);
 if(corrupt==6) memory[48]=0;
 if(corrupt==7) memory[49]=0;
 s=0;for(i=14;i<34;i+=2)s=s+{memory[i],memory[i+1]};s=(s&65535)+(s>>16);put16(24,~s);
 s=16'hc0a8+16'h3201+16'hc0a8+16'h3202+17+n-34;
 for(i=34;i<n;i+=2)s=s+{memory[i],memory[i+1]};s=(s&65535)+(s>>16);s=(s&65535)+(s>>16);put16(40,(~s)&65535);
 if(corrupt==1) memory[80]=memory[80]^1;
 @(negedge c);old_ack=ack[0];lengths=n;pending=1;wait(ack[0]!=old_ack);@(negedge c);pending=0;repeat(5) @(negedge c);
 end endtask
 integer old;
 initial begin
 #100;rst=1;repeat(10) @(negedge c);
 packet(1,32'h12345678,0,0,0,0,2000,0,5,0);
 if(!online || session!=32'h12345678 || fps!=5) $fatal(1,"HELLO");
 packet(16,32'h12345678,1,0,0,0,2000,0,0,0);if(writes!=40 || frames!=0) $fatal(1,"partial publish");
 packet(16,32'h12345678,1,0,0,0,2000,0,0,0);if(writes!=40) $fatal(1,"duplicate");
 packet(16,32'h12345678,1,2,0,0,2000,0,0,0);if(drops==0 || frames!=0) $fatal(1,"gap");
 old=writes;packet(16,32'hbad,2,0,0,0,2000,0,0,0);if(writes!=old) $fatal(1,"old session writes");
 packet(16,32'h12345678,2,0,0,0,2000,0,0,1);if(writes!=old || bad==0) $fatal(1,"UDP checksum");
 for(integer malformed=2;malformed<=7;malformed++) begin
  packet(16,32'h12345678,2,0,0,0,2000,0,0,malformed);
  if(writes!=old || frames!=0) $fatal(1,"malformed video wrote/published kind=%0d",malformed);
 end
 old=drops;
 packet(16,32'h12345678,3,0,0,0,2000,0,0,0);
 for(integer heartbeat=0;heartbeat<5;heartbeat++) begin
  repeat(45000) @(negedge c);
  packet(3,32'h12345678,0,0,0,0,2000,0,0,0);
 end
 if(dut.assembly || drops<=old || frames!=0 || !online) $fatal(1,"missing-fragment timeout");
 old=writes;
 packet(16,32'h12345678,4,0,0,0,2000,0,0,0);
 packet(16,32'h12345678,4,1,0,0,2000,0,0,0);
 if(writes!=old+80 || dut.next_index!=2) $fatal(1,"next-frame recovery writes=%0d old=%0d index=%0d online=%b age=%0d",writes,old,dut.next_index,online,dut.assembly_age);
 @(negedge c);kc=1;ke=1;@(negedge c);ke=0;repeat(10) @(negedge c);
 packet(6,32'h12345678,55,0,1,1,2000,1,0,0);if(feedback!=1) $fatal(1,"ALLOW");
 packet(6,32'h12345678,55,0,1,1,2000,2,1,0);if(feedback!=1) $fatal(1,"duplicate result executed");
 @(negedge c);kc=4;ke=1;@(negedge c);ke=0;
 packet(6,32'h12345678,55,0,1,2,2000,2,1,0);if(feedback!=0) $fatal(1,"stale event");
 packet(6,32'h12345678,55,0,2,1,100,2,1,0);if(feedback!=3) $fatal(1,"alarm");
 repeat(12000) @(negedge c);if(feedback!=0) $fatal(1,"TTL");
 packet(6,32'h12345678,55,0,2,2,100,1,0,0);if(feedback!=0) $fatal(1,"expired accepted");
 repeat(210000) @(negedge c);if(online || feedback!=0) $fatal(1,"heartbeat expiry");
 packet(1,32'h87654321,0,0,0,0,2000,0,5,0);if(!online || session!=32'h87654321 || dut.event_id!=0) $fatal(1,"restart");
 packet(6,32'h87654321,54,0,1,9,2000,1,0,0);if(feedback!=0) $fatal(1,"wrong frame/cleared event accepted");
 if(eventpack==0 || resultacks==0 || events!=2) $fatal(1,"control TX coverage");
 $display("M3_CORE_PASS partial_duplicate_gap_checksum_session_bounds_timeout_recovery=1 control_stale_duplicate_ttl_restart=1 writes=%0d tx=%0d events=%0d",writes,txpack,events);$finish;
 end
 initial begin #10000000;$fatal(1,"core timeout");end
endmodule
