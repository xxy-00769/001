`timescale 1ns/1ps
module m3_control_tb;
 reg clk=0,pc=0,rst=0,fs=0;always #10 clk=~clk;always #16.923077 pc=~pc;
 reg [5:0] key=63;wire [3:0] led;wire [2:0] vr,view;wire [2:0] mr,mode;
 wire [5:0] pressed;wire event_in;wire [3:0] hint_sys,hint;wire visible;
 m3_keys #(.DEBOUNCE_CYCLES(4)) dut(.clk(clk),.rst_n(rst),.key_n(key),.intent_led(led),
  .view_request(vr),.mode_request(mr),.pressed(pressed),.hint_event(event_in),.hint_code(hint_sys));
 m3_view_select sel(.sys_clk(clk),.clk(pc),.rst_n(rst),.frame_sync(fs),.view_request(vr),
  .mode_request(mr),.selected_view(view),.selected_mode(mode));
 m1_hint_cdc #(.HOLD_CYCLES(300)) h(.sys_clk(clk),.pix_clk(pc),.rst_n(rst),
  .event_in(event_in),.code_in(hint_sys),.visible(visible),.code(hint));
 integer events[0:5];integer checks=0,i;
 always @(posedge clk) if(rst) for(integer k=0;k<6;k++) if(pressed[k]) events[k]++;
 task check(input bit c,input string msg);begin checks++;if(!c) $fatal(1,"%s",msg);end endtask
 task hold(input integer k);begin @(negedge clk);key[k]=0;repeat(40) @(negedge clk);end endtask
 task release_key(input integer k);begin @(negedge clk);key[k]=1;repeat(40) @(negedge clk);end endtask
 task boundary;begin @(negedge pc);fs=1;repeat(8) @(negedge pc);fs=0;end endtask
 reg snapshot_hint=0;reg [9:0] x=0;reg [8:0] y=0;wire area,pixel;
 m3_osd osd(.x(x),.y(y),.view(view),.mode(mode),.hint_visible(snapshot_hint || visible),.hint_code(hint),
  .video_good(4'b1111),.feedback(3'd3),.area(area),.pixel(pixel));
 integer on_pixels=0,f;
 initial begin
  for(i=0;i<6;i++) events[i]=0;
  #100;rst=1;repeat(20) @(negedge clk);
  check(led==8 && view==0 && mode==0,"reset front/original/stop");
  for(i=0;i<3;i++) begin hold(i);check(led==(1<<i),"intent LED");release_key(i);end
  hold(3);hold(1);check(led==8 && hint==10,"held STOP denied actual KEY2");release_key(1);release_key(3);
  repeat(3) begin @(negedge clk);key[4]=0;@(negedge clk);key[4]=1;end
  repeat(12) @(negedge clk);check(events[4]==0,"bounce rejected");
  for(i=1;i<=5;i++) begin
   hold(4);check(view==((i-1)%5),"view waits frame boundary");boundary;
   check(view==i%5 && vr==i%5 && hint==5,"five-view cycle");
   repeat(60) @(negedge clk);boundary;check(events[4]==i,"long hold once");release_key(4);
  end
  for(i=1;i<=5;i++) begin
   hold(5);check(mode==(i-1)%5,"mode waits frame boundary");boundary;
   check(mode==i%5 && mr==i%5 && hint==6,"five-mode cycle");release_key(5);
  end
  hold(5);boundary;release_key(5);
  repeat(200) @(negedge pc);check(visible,"new event refreshes hint");
  repeat(130) @(negedge pc);check(!visible,"hint expires");
  // Export pixels evaluated by production OSD/font for visual inspection.
  hold(4);release_key(4);hold(4);release_key(4);hold(4);boundary;release_key(4);
  hold(5);boundary;release_key(5);
  snapshot_hint=1;
  f=$fopen("osd_rtl_pixels.hex","w");
  for(integer yy=0;yy<480;yy++) begin
   for(integer xx=0;xx<800;xx++) begin x=xx;y=yy;#1;$fwrite(f,"%01x\n",area && pixel);if(area && pixel) on_pixels++;end
  end
  x=300;y=440;#1;check(!area,"feedback must not wrap 8bit font columns");
  $fclose(f);check(on_pixels>300,"visible Chinese glyphs");
  $display("M3_CONTROL_PASS checks=%0d key5_events=%0d key6_events=%0d glyph_pixels=%0d mailbox=1 stop_priority=1",checks,events[4],events[5],on_pixels);$finish;
 end
endmodule
