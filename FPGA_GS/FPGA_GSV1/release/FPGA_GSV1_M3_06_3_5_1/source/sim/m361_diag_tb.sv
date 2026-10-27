`timescale 1ns/1ps
module m361_diag_tb;
 reg c=0,rst=0;always #10 c=~c;
 reg [703:0] values,expected;wire tx;
 m361_uart_hex #(.TICKS(20000)) u(.clk(c),.rst_n(rst),.values(values),.tx(tx));
 reg [7:0] got[0:206];reg [7:0] v;integer n=0;reg [3:0] h;reg [7:0] want;
 initial begin
  for(integer i=0;i<22;i++) values[703-i*32-:32]=32'h01234567+i*32'h01010101;
  expected=values;
  #101;rst=1;
  for(integer i=0;i<207;i++) begin
   @(negedge tx);#13020;
   for(integer k=0;k<8;k++) begin v[k]=tx;#8680;end
   if(!tx) $fatal(1,"UART stop bit");got[i]=v;n++;
  end
  if({got[0],got[1],got[2],got[3],got[4],got[5],got[6]}!=="N2 351 " || got[205]!=13 || got[206]!=10) $fatal(1,"UART framing/prefix");
  for(integer i=7;i<205;i++) begin
   if((i-7)%9==8) want=" ";else begin
    h=expected[703-(((i-7)/9)*8+(i-7)%9)*4-:4];want=h<10 ? "0"+h:"A"+h-10;
   end
   if(got[i]!==want) $fatal(1,"UART field byte=%0d got=%h want=%h",i,got[i],want);
  end
  $display("M361_DIAG_PASS uart_8N1=1 actual_baud_div=434 bit_ns=8680 atomic_22_words=1 characters=%0d",n);$finish;
 end
 initial begin #500000;values=0;end
 initial begin #30000000;$fatal(1,"diagnostic timeout n=%0d",n);end
endmodule
