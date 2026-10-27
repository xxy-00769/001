`timescale 1ns/1ps
module m34_camera_tb;
 GTP_GRS GRS_INST(.GRS_N(1'b1));
 reg p=0;always #5.95 p=~p;
 reg rst=0,vs=0,de=0;reg [7:0] data=0;
 // Actual production local-I/O capture and global-clock transfer.
 wire vd,dd;wire [7:0] d;
 m34_input_capture #(.WIDTH(10)) pads(.clk(p),.data({vs,de,data}),.captured({vd,dd,d}));
 wire pc,valid;wire [15:0] pixel;
 cmos_8_16bit dut(.pclk(p),.rst_n(rst),.de_i(dd),.pdata_i(d),.vs_i(vd),
   .pixel_clk(pc),.de_o(valid),.pdata_o(pixel));
 function [15:0] pattern(input integer row,col);
  pattern=16'h81e3 ^ (row*16'h49d3) ^ (col*16'h197b);
 endfunction
 integer got=0,rows=0,cols=0,firsts=0,lasts=0;reg prev=0;
 always @(posedge pc) begin
  #0.1;
  if(valid) begin
   if(pixel!==pattern(rows,cols)) $fatal(1,"CAMERA_PIXEL row=%0d col=%0d got=%h expected=%h",rows,cols,pixel,pattern(rows,cols));
   if(cols==0) firsts++;
   if(cols==1279) lasts++;
   cols++;got++;
  end
  if(prev && !valid) begin
   if(cols!=1280) $fatal(1,"CAMERA_LINE row=%0d cols=%0d",rows,cols);
   rows++;cols=0;
  end
  prev=valid;
 end
 initial begin
  repeat(8) @(negedge p);rst=1;
  repeat(8) @(negedge p);vs=1;
  repeat(20) @(negedge p);vs=0;
  for(integer y=0;y<720;y++) begin
   // Both possible line phases relative to the generated /2 clock.
   repeat(11+(y%2)) @(negedge p);
   for(integer x=0;x<1280;x++) begin
    de=1;data=pattern(y,x)>>8;@(negedge p);
    data=pattern(y,x);@(negedge p);
   end
   de=0;data=8'h5a;
  end
  repeat(30) @(negedge p);
  if(rows!=720 || got!=921600 || firsts!=720 || lasts!=720) $fatal(1,"CAMERA_COUNTS rows=%0d pixels=%0d",rows,got);
  $display("M34_CAMERA_PASS full_height=720 pixels=%0d first_last=%0d/%0d alternating_line_phase=1 RGB565=1",got,firsts,lasts);$finish;
 end
 initial begin #30000000;$fatal(1,"camera timeout");end
endmodule
