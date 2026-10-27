`timescale 1ns/1ps
// Exact 50MHz / 5 and / 2. Explicit global buffers; no fabric-gated clock.
// cfg_clk is 10MHz (40/60 duty); camera clock stays 25MHz (50/50).
module m364_ref_dividers(input clkin1,output cfg_clk,camera_clk,ready);
 reg [2:0] phase=0;
 reg cfg_raw=0,camera_raw=0;
 reg [4:0] startup=0;
 always @(posedge clkin1) begin
  phase<=phase==4 ? 0:phase+1'b1;
  if(phase==0) cfg_raw<=1;
  if(phase==2) cfg_raw<=0;
  camera_raw<=!camera_raw;
  startup<={startup[3:0],1'b1};
 end
 GTP_CLKBUFG cfg_buffer(.CLKIN(cfg_raw),.CLKOUT(cfg_clk));
 GTP_CLKBUFG camera_buffer(.CLKIN(camera_raw),.CLKOUT(camera_clk));
 assign ready=startup[4];
endmodule
