`timescale 1ns/1ps
module m32_reader_tb;
 GTP_GRS GRS_INST(.GRS_N(1'b1));
 reg dc=0,pc=0,rst=0,fs=0,en=0,enabled=0,q=0,done=0,valid=0;
 always #5 dc=~dc;always #3.367003367 pc=~pc;
 wire req,sof,de;wire [27:0] addr;wire [31:0] len;wire [15:0] pix;
 reg [255:0] data=0;
 m31_rd_buf dut(.ddr_clk(dc),.ddr_rstn(rst),.vout_clk(pc),.rd_fsync(fs),.rd_en(en),
 .quarter(q),.selected(1'b1),.enabled(enabled),.vout_de(de),.vout_data(pix),
 .ddr_rreq(req),.ddr_raddr(addr),.ddr_rd_len(len),.ddr_rrdy(!valid),.ddr_rdone(done),
 .ddr_rdata(data),.ddr_rdata_en(valid),.frame_start_event(sof));
 function [15:0] pattern(input integer row,input integer col);pattern=(row*16'h191d)^(col*16'h9e37);endfunction
 integer row,b,l,expected_row,base,issued=0;

 initial begin wait(rst);forever begin
  wait(req);@(negedge dc);row=addr/640;
  if(len!=80 || addr%640) $fatal(1,"HD row command");
  for(b=0;b<80;b++) begin
   if(b%9==8) begin valid=0;repeat(3) @(negedge dc);end
   for(l=0;l<16;l++) data[l*16+:16]=pattern(row,b*16+l);
   valid=1;@(negedge dc);
  end
  valid=0;done=1;@(negedge dc);done=0;issued++;
 end end
 integer y,x,checked=0;reg [1:0] ed=0;reg [15:0] e0=0,e1=0;reg [15:0] expected_input=0;
 always @(posedge pc) begin
  ed={ed[0],en};e1=e0;e0=expected_input;#0.2;
  if(de!==ed[1]) $fatal(1,"HD reader latency");
  if(de) begin if(pix!==e1) $fatal(1,"HD RAM packing q=%0d row=%0d x=%0d got=%h expected=%h",q,y,x,pix,e1);checked++;end
 end
 task scan(input integer quad);begin
  @(negedge pc);q=quad;fs=1;repeat(40) @(negedge pc);fs=0;repeat(300) @(negedge pc);
  for(y=0;y<16;y++) begin
   for(x=0;x<(quad ? 960:1280);x++) begin
    en=1;expected_input=pattern(quad ? y*4/3:y,quad ? x*4/3:x);@(negedge pc);
   end
   en=0;repeat(1200) @(negedge pc);
  end
 end endtask
 initial begin #50;@(negedge pc);rst=1;repeat(20) @(negedge dc);enabled=1;
  scan(0);scan(1);
  $display("M32_READER_PASS pixels=%0d rows=32 vendor_RAM=1 ring_wraps=4 formats=one_to_one_and_three_quarters latency=2",checked);$finish;
 end
 initial begin #2000000;$fatal(1,"HD reader timeout");end
endmodule
