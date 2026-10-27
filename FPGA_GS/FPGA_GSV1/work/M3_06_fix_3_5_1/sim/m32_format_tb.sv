`timescale 1ns/10fs
// Real production PLL primitive (no replacement clock) drives the complete
// output pipeline. Source pixels are static; image correctness is tested by
// m32_display_tb, here every output sync/DE period is counted independently.
module m32_format_tb;
 GTP_GRS GRS_INST(.GRS_N(1'b1));
 reg sys=0,rst=0;always #10 sys=~sys;
 wire pc,locked; m31_pixel_pll pll(.clkin1(sys),.clkout0(pc),.clkout1(),.clkout2(),.pll_lock(locked));
 wire hs,vs,de,fs;wire [23:0] rgb;wire [3:0] selected,request;
 m31_video_output video(.clk(pc),.rst_n(rst),.timing_rst_n(rst),
  .selected_view(3'd4),.selected_mode(3'd0),.source_rgb(64'd0),
  .source_de(4'b1111),.show_video(4'b1111),.feedback(3'd0),
  .hint_visible(1'b0),.hint_code(4'd0),.frame_sync(fs),
  .source_selected(selected),.source_request(request),
  .hs_out(hs),.vs_out(vs),.de_out(de),.rgb_out(rgb));
 realtime t0,period,high_time,rise,previous,start_time;
 integer i;
 initial begin
  wait(locked); repeat(20) @(posedge pc);
  @(posedge pc);t0=$realtime;
  for(i=0;i<1000;i=i+1) @(posedge pc);
  period=($realtime-t0)/1000;
  @(posedge pc);rise=$realtime;@(negedge pc);high_time=$realtime-rise;
  if(period<6.7338 || period>6.7342 || high_time<3.3668 || high_time>3.3672)
   $fatal(1,"real PLL wrong period=%0.8f high=%0.8f",period,high_time);
  $display("REAL_PLL period_ns=%0.8f MHz=%0.6f high_ns=%0.8f",period,1000/period,high_time);$fflush();
  @(negedge pc);rst=1;
 end
 integer cycles=0,hs_count=0,vs_count=0,pixels=0,lines=0,line_pixels=0;
 integer line_cycles=0,line_hs=0;reg prev_hs=0,prev_vs=0,prev_de=0,counting=0,line_valid=0;
 always @(posedge pc) begin
  #0.0001;
  if(rst) begin
   if(vs && !prev_vs) begin
    if(counting) begin
     if(cycles!=2475000 || hs_count!=49500 || vs_count!=11000 || pixels!=2073600 || lines!=1080)
      $fatal(1,"format cycles=%0d HS=%0d VS=%0d DE=%0d lines=%0d",cycles,hs_count,vs_count,pixels,lines);
     $display("M32_FORMAT_PASS real_vendor_PLL=1 cycles=%0d HTotal=2200 VTotal=1125 HSwidth=44 VSwidth=5 active=1920x1080 polarity=positive_positive frame_ns=%0.3f fps=%0.6f",cycles,$realtime-start_time,1e9/($realtime-start_time));$finish;
    end
    counting=1;start_time=$realtime;
   end
   if(counting) begin
    cycles++;if(hs) hs_count++;if(vs) vs_count++;if(de) pixels++;
    if(hs && !prev_hs) begin
     if(line_valid && (line_cycles!=2200 || line_hs!=44)) $fatal(1,"horizontal total/width");
     line_valid=1;line_cycles=0;line_hs=0;
    end
    if(line_valid) begin line_cycles++;if(hs) line_hs++;end
    if(de) line_pixels++;
    if(!de && prev_de) begin
     if(line_pixels!=1920) $fatal(1,"DE width=%0d",line_pixels);
     lines++;line_pixels=0;
    end
   end
   prev_hs=hs;prev_vs=vs;prev_de=de;
  end
 end
 initial begin #20000000;$fatal(1,"PLL/format timeout");end
endmodule
