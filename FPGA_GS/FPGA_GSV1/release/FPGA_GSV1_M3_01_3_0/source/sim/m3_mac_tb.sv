`timescale 1ns/1ps
module m3_mac_tb;
 GTP_GRS GRS_INST(.GRS_N(1'b1));
 reg n=0,c=0,rst=0;always #4 n=~n;always #5 c=~c;
 reg [7:0] rx=0;reg rv=0,re=0;wire [7:0] tx;wire tv;
 wire [3:0] pending;reg [3:0] ack=0;wire [63:0] lens;
 reg [12:0] ra=0;wire [7:0] rd;reg we=0;reg [10:0] wa=0;reg [7:0] wd=0;
 reg req=0;reg [15:0] len=1370;wire tack;wire [31:0] bad,over;
 m3_mac dut(.nc(n),.nrst(rst),.rxd(rx),.rxv(rv),.rxe(re),.txd(tx),.txv(tv),
 .dc(c),.drst(rst),.rx_pending(pending),.rx_ack(ack),.rx_lengths(lens),.rx_addr(ra),.rx_data(rd),
 .tx_we(we),.tx_addr(wa),.tx_data(wd),.tx_req(req),.tx_length(len),.tx_ack(tack),.crc_errors(bad),.rx_overruns(over));
 function [31:0] crc(input [31:0] v,input [7:0] d);
 reg [31:0] x;integer j;begin x=v;for(j=0;j<8;j++) x=(x[0]^d[j]) ? (x>>1)^32'hedb88320:x>>1;crc=x;end endfunction
 function [7:0] pat(input integer i);pat=(i*73)^(i>>3)^8'ha7;endfunction
 integer i,j,k,captured=0;reg [31:0] cv;reg [7:0] wirebuf[0:4095];reg pv=0;
 always @(posedge n) begin #1;if(tv) begin wirebuf[captured]=tx;captured++;end pv=tv;end
 task receive(input integer tag,input integer corrupt);
 begin
 @(negedge n);rv=1;rx=8'h55;repeat(7) @(negedge n);rx=8'hd5;@(negedge n);cv=~0;
 for(j=0;j<1370;j++) begin rx=pat(j+tag);cv=crc(cv,rx);@(negedge n);end
 cv=~cv;for(j=0;j<4;j++) begin rx=(cv>>(8*j)) ^ (corrupt && j==0);@(negedge n);end
 rv=0;rx=0;repeat(20) @(negedge n);
 end endtask
 initial begin
 #100;rst=1;repeat(8) @(negedge c);
 for(i=0;i<1370;i++) begin we=1;wa=i;wd=pat(i);@(negedge c);end we=0;
 repeat(4) @(negedge c);req=1;wait(tack);repeat(5) @(negedge n);
 if(captured!=1382) $fatal(1,"TX size %0d",captured);
 cv=~0;for(i=0;i<captured;i++) begin
 if(i<7 && wirebuf[i]!=8'h55) $fatal(1,"preamble");
 if(i==7 && wirebuf[i]!=8'hd5) $fatal(1,"SFD");
 if(i>=8 && i<1378 && wirebuf[i]!==pat(i-8)) $fatal(1,"TX byte %0d got=%h",i,wirebuf[i]);
 if(i>=8) cv=crc(cv,wirebuf[i]);end
 if(cv!=32'hdebb20e3) $fatal(1,"TX CRC %h",cv);
 receive(0,0);wait(pending[0]);if(lens[15:0]!=1370) $fatal(1,"length");
 for(i=0;i<1370;i++) begin @(negedge c);ra=i;repeat(2) @(negedge c);if(rd!==pat(i)) $fatal(1,"RX byte %0d %h",i,rd);end
 receive(1,1);if(bad!=1) $fatal(1,"bad FCS not rejected");
 receive(2,0);receive(3,0);receive(4,0);receive(5,0);
 if(over!=1 || pending!=15) $fatal(1,"bounded slots %h over=%0d",pending,over);
 ack=15;repeat(10) @(negedge n);receive(6,0);repeat(10) @(negedge c);
 if(pending!=1) $fatal(1,"slot recovery %h",pending);
 $display("M3_MAC_PASS tx_bytes=1370 rx_bytes=1370 fcs=1 slots=4 overrun_recovery=1 real_DRM=1");$finish;
 end
 initial begin #1000000;$fatal(1,"MAC timeout");end
endmodule
