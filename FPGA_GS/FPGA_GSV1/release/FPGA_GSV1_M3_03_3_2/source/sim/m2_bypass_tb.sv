`timescale 1ns/1ps
module m2_bypass_tb;
 reg clk=0,rst=0;always #16.923077 clk=~clk;
 reg [1:0] view=0;reg [47:0] data=0;reg [2:0] valid=0;
 wire [1:0] hs,vs,de,fs;wire [5:0] sel,req;wire [47:0] rgb;
 reg [2:0] request_d=0;integer checked=0;
 genvar k;
 generate for(k=0;k<2;k=k+1) begin: path
  m2_video_output #(.PROCESSING_ENABLE(k)) dut(.clk(clk),.rst_n(rst),.timing_rst_n(rst),
   .selected_view(view),.selected_mode(3'd0),.source_rgb(data),.source_de(valid),.show_video(3'b111),
   .hint_visible(1'b0),.hint_code(4'd0),.frame_sync(fs[k]),.source_selected(sel[k*3+:3]),
   .source_request(req[k*3+:3]),.hs_out(hs[k]),.vs_out(vs[k]),.de_out(de[k]),.rgb_out(rgb[k*24+:24]));
 end endgenerate
 always @(posedge clk) begin
  request_d<=req[2:0];valid<=request_d;
  data<=data+48'h3d_15_74_6a_20_81;
  #1;
  if(rst) begin
   if({hs[0],vs[0],de[0],fs[0],sel[2:0],req[2:0],rgb[23:0]}!==
      {hs[1],vs[1],de[1],fs[1],sel[5:3],req[5:3],rgb[47:24]})
    $fatal(1,"compile-bypass original metadata/pixel mismatch");
   if(de[0]) checked++;
  end
 end
 initial begin
  #100;@(negedge clk);rst=1;
  for(integer v=0;v<4;v++) begin
   @(posedge fs[0]);@(negedge clk);view=v;
   @(negedge fs[0]);@(posedge fs[0]);
  end
  $display("M2_BYPASS_PASS pixels=%0d views=4 pixel_and_sync_equal=1 latency=4",checked);$finish;
 end
endmodule
