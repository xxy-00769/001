`timescale 1ns/1ps
module m365_crc_tb;
 reg clk=0,rst=0,valid=0;reg [7:0] data=0;
 always #4 clk=~clk;
 wire [31:0] frames,bad,last_id,last_crc;wire [15:0] last_length;
 m365_gmii_crc dut(.clk(clk),.rst_n(rst),.valid(valid),.data(data),
  .frames(frames),.bad_frames(bad),.last_bad_id(last_id),
  .last_bad_residue(last_crc),.last_bad_length(last_length));
 reg [7:0] bytes[0:1525];reg [31:0] crc;
 function [31:0] crc_byte(input [31:0] value,input [7:0] octet);
  reg [31:0] c;begin c=value;for(integer k=0;k<8;k++)
   c=(c[0]^octet[k]) ? (c>>1)^32'hedb88320:c>>1;crc_byte=c;end
 endfunction
 task frame(input integer length,input integer fault,input [31:0] id);
  begin
   for(integer j=0;j<7;j++) bytes[j]=8'h55;bytes[7]=8'hd5;
   for(integer j=0;j<length;j++) bytes[j+8]=(j*37)^(j>>2)^id;
   for(integer j=0;j<4;j++) bytes[62+j]=(id>>(24-8*j));
   crc=32'hffffffff;for(integer j=8;j<length+8;j++) crc=crc_byte(crc,bytes[j]);
   for(integer j=0;j<4;j++) bytes[length+8+j]=~(crc>>(8*j));
   if(fault==1) bytes[100]=bytes[100]^8'h80;
   if(fault==2) bytes[length+11]=bytes[length+11]^8'h01;
   if(fault==4) bytes[7]=8'h55;
   for(integer j=0;j<(fault==3 ? 70:length+12);j++) begin
    @(negedge clk);valid=1;data=bytes[j];
   end
   @(negedge clk);valid=0;data=0;repeat(14) @(negedge clk);
  end
 endtask
 initial begin
  #1;rst=0;#16;rst=1;
  frame(60,0,32'd1);if(frames!=1 || bad!=0) $fatal(1,"short good");
  frame(1370,0,32'd2);if(frames!=2 || bad!=0) $fatal(1,"long good");
  frame(1370,1,32'd3);if(frames!=3 || bad!=1 || last_id!=3 || last_length!=1382) $fatal(1,"payload corruption");
  frame(1370,2,32'd4);if(frames!=4 || bad!=2 || last_id!=4) $fatal(1,"FCS corruption");
  frame(1370,3,32'd5);if(frames!=5 || bad!=3 || last_length!=70) $fatal(1,"truncation");
  frame(1370,4,32'd6);if(frames!=6 || bad!=4 || last_id!=6) $fatal(1,"preamble framing");
  frame(1370,0,32'd7);if(frames!=7 || bad!=4) $fatal(1,"recovery after bad frame");
  $display("M365_CRC_PASS 7 frames, 4 deliberate errors, good recovery");$finish;
 end
 initial begin #1000000;$fatal(1,"timeout");end
endmodule
