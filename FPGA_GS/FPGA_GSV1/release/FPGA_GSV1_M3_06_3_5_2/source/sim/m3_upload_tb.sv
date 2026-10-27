`timescale 1ns/1ps
module m3_upload_tb;
 reg c=0,rst=0,online=1;always #5 c=~c;
 reg [16:0] count=0;reg fast_tick=0;always @(posedge c) count<=count==99999 ? 0:count+1;
 wire acquire,release_frame;reg grant=0,held=0;
 wire ready;reg taken=0;wire [31:0] fid,ft,off;wire [15:0] fi;
 reg [8:0] wa=0;wire [31:0] word;
 wire [27:0] ar;wire [3:0] len;wire av;reg arr=0,rv=0,last=0;reg [255:0] rd=0;
 wire [31:0] frames,aborts;
 m3_upload dut(.clk(c),.rst_n(rst),.online(online),.tick_ms(count==0 || fast_tick),.fps(8'd5),
 .acquire(acquire),.release_frame(release_frame),.grant(grant),.held(held),.bank(2'd2),.identity(32'd123),.stamp(32'd456),
 .fragment_ready(ready),.fragment_taken(taken),.frame_id(fid),.frame_time(ft),.offset(off),.index(fi),
 .word_addr(wa),.word_data(word),.araddr(ar),.arlen(len),.arvalid(av),.arready(arr),.rdata(rd),.rvalid(rv),.rlast(last),.frames(frames),.aborts(aborts));
 always @(posedge c) begin
 grant<=0;
 if(acquire && !held) begin grant<=1;held<=1;end
 if(release_frame) held<=0;
 end
 function [15:0] pat(input integer pixel);pat=(((pixel/1280)*16'h031d)^((pixel%1280)*16'h9e37)^16'h19d7)&16'h3fff;endfunction
 integer burst=0,a,n,j,k,pix,checks=0,fragments=0;reg outstanding=0;
 initial begin
 wait(rst);
 forever begin
 wait(av);@(negedge c);a=ar;n=len+1;
 if(a<28'h2000000 || a>=28'h2070800 || a%8) $fatal(1,"upload slot/address %h",a);
 arr=1;outstanding=1;
 if(burst%2) begin @(posedge c);@(negedge c);arr=0;end
 for(j=0;j<n;j++) begin
  if(j%3==2) repeat(2) @(negedge c);
  for(k=0;k<16;k++) rd[k*16+:16]=pat((a-28'h2000000)*2+j*16+k);
  rv=1;last=j==n-1;@(posedge c);@(negedge c);arr=0;rv=0;last=0;
 end
 outstanding=0;burst++;
 end end
 always @(posedge c) if(rst && release_frame && outstanding) $fatal(1,"released before DDR drains");
 integer i,f;
 initial begin
 #100;rst=1;
 for(f=0;f<1440;f++) begin
  wait(ready);if(fi!=f || off!=f*1280 || fid!=123 || ft!=456 || !held) $fatal(1,"descriptor");
  for(i=0;i<320;i++) begin
   @(negedge c);wa=i;repeat(2) @(negedge c);pix=f*640+i*2;
   if(word!=={pat(pix+1),pat(pix)}) $fatal(1,"upload oracle frag=%0d word=%0d %h",f,i,word);checks++;
  end
  if(f==20) repeat(300) @(negedge c);
  taken=1;@(negedge c);taken=0;fragments++;wait(!ready);
 end
 repeat(5) @(negedge c);if(frames!=1 || held) $fatal(1,"frame release");
 fast_tick=1;wait(av);@(negedge c);fast_tick=0;online=0;
 wait(aborts==1);repeat(5) @(negedge c);if(held) $fatal(1,"abort leaked pin");
 online=1;fast_tick=1;wait(av);fast_tick=0;wait(ready);online=0;wait(aborts==2);repeat(5) @(negedge c);if(held) $fatal(1,"staged abort leak");
 $display("M3_UPLOAD_PASS fragments=%0d raw_words=%0d earliest_and_gapped_returns=1 backpressure_abort_reconnect=1",fragments,checks);$finish;
 end
 initial begin #100000000;$fatal(1,"upload timeout");end
endmodule
