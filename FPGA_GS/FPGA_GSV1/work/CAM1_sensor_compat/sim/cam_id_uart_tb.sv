`timescale 1ns/1ps
module cam_id_uart_tb;
 reg sc=0,nc=0,rst_n=0;
 always #10 sc=~sc;
 always #4 nc=~nc;
 reg [127:0] camera=128'h43314731_000e1000_070302d0_000c0000;
 wire tx;
 m365_tx_observer dut(.sc(sc),.nc(nc),.rst_n(rst_n),
  .phy(128'h001cc915_bd750000_00000000_ac02ea01),
  .pll_lock(1'b1),.phy_ready(1'b1),.txv(1'b0),.txd(8'd0),
  .camera_diagnostics(camera),.uart_tx(tx));
 defparam dut.serial.TICKS=2000;
 defparam dut.serial.BAUD_DIV=4;
 reg [7:0] text[0:368];
 task automatic read_character(output [7:0] b);
  integer k;
  begin
   @(negedge tx);repeat(6) @(posedge sc);#1;
   for(k=0;k<8;k=k+1) begin
    b[k]=tx;repeat(4) @(posedge sc);#1;
   end
   if(tx!==1) $fatal(1,"UART stop bit");
  end
 endtask
 function automatic [31:0] word_at(input integer w);
  integer i;reg [7:0] c;
  begin
   word_at=0;
   for(i=0;i<8;i=i+1) begin
    c=text[7+w*9+i];
    if(c>="0" && c<="9") word_at=(word_at<<4)|(c-"0");
    else if(c>="A" && c<="F") word_at=(word_at<<4)|(c-"A"+10);
    else $fatal(1,"invalid hex");
   end
  end
 endfunction
 integer i;
 initial begin
  repeat(8) @(negedge sc);rst_n=1;
  for(i=0;i<369;i=i+1) begin
   read_character(text[i]);
   if(i==0) camera=0; // Existing serializer must hold the whole line atomically.
  end
  if({text[0],text[1],text[2],text[3],text[4],text[5],text[6]}!=="N2 35O ")
   $fatal(1,"existing prefix changed");
  if(word_at(0)!==32'h001cc915 || word_at(1)!==32'hbd750000
    || word_at(11)!==3 || word_at(12)!==32'h43314731
    || word_at(13)!==32'h000e1000 || word_at(14)!==32'h070302d0
    || word_at(15)!==32'h000c0000)
   $fatal(1,"passive diagnostic words changed or camera status mispacked");
  for(i=16;i<40;i=i+1) if(word_at(i)!==0) $fatal(1,"reserved word not zero");
  if(text[367]!==13 || text[368]!==10) $fatal(1,"line ending changed");
  $display("PASS UART geometry: unchanged 40-word framing and PHY/ready words; original four camera words reused for pixels/rows/errors/config/counters, atomic line, reserved zeros");
  $finish;
 end
 initial begin #1000000;$fatal(1,"test deadline");end
endmodule
