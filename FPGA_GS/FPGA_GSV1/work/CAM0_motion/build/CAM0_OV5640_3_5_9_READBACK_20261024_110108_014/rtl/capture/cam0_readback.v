`timescale 1ns/1ps
// CAM0 ONLY, read-only after the unchanged legacy initializer has released SCCB.
// OV5640 v2.01: exposure 3500..2 is in sixteenths of a line; gain is /16.
// The two high exposure bytes are re-read to reject a torn AEC update.
module cam0_readback #(parameter CLOCK_HZ=50000000, SCCB_HZ=100000)(
 input clk,rst_n,enable,inout scl,sda,
 output reg [351:0] registers,output reg valid,
 output reg [7:0] sequence_number,errors,
 output reg [3:0] last_nack,output reg last_timeout);
 function [15:0] address(input [5:0] i);
 begin case(i)
 0:address=16'h300a;1:address=16'h300b;
 2:address=16'h3034;3:address=16'h3035;4:address=16'h3036;
 5:address=16'h3037;6:address=16'h3108;7:address=16'h3039;
 8:address=16'h3500;9:address=16'h3501;10:address=16'h3502;
 11:address=16'h3500;12:address=16'h3501;13:address=16'h3503;
 14:address=16'h350a;15:address=16'h350b;
 16:address=16'h350c;17:address=16'h350d;
 18:address=16'h380c;19:address=16'h380d;
 20:address=16'h380e;21:address=16'h380f;
 22:address=16'h3a00;23:address=16'h3a02;24:address=16'h3a03;
 25:address=16'h3a14;26:address=16'h3a15;
 27:address=16'h3a18;28:address=16'h3a19;
 29:address=16'h3a08;30:address=16'h3a09;
 31:address=16'h3a0a;32:address=16'h3a0b;
 33:address=16'h3a0d;34:address=16'h3a0e;
 35:address=16'h3c00;36:address=16'h3c01;37:address=16'h3c0c;
 38:address=16'h3824;39:address=16'h460c;
 40:address=16'h5000;41:address=16'h5001;
 42:address=16'h5308;43:address=16'h5306;
 default:address=16'h300a;
 endcase end endfunction
 reg [351:0] staging;
 reg [5:0] index;
 reg [1:0] state;
 reg [25:0] wait_count;
 reg start;
 wire done,busy,timeout;
 wire [7:0] data;
 wire [3:0] nack;
 cam_sccb_read16 #(.CLOCK_HZ(CLOCK_HZ),.SCCB_HZ(SCCB_HZ)) reader(
  .clk(clk),.rst_n(rst_n && enable),.start(start),.address(7'h3c),
  .register_address(address(index)),.scl(scl),.sda(sda),
  .busy(busy),.done(done),.data(data),.nack_mask(nack),.bus_timeout(timeout));
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   registers<=0;staging<=0;valid<=0;sequence_number<=0;errors<=0;
   last_nack<=0;last_timeout<=0;index<=0;state<=0;start<=0;wait_count<=0;
  end else begin
   start<=0;
   if(!enable) begin valid<=0;state<=0;wait_count<=0;end
   else case(state)
    0:if(wait_count==CLOCK_HZ-1) begin
       wait_count<=0;index<=0;state<=1;
      end else wait_count<=wait_count+1'b1;
    1:begin start<=1;state<=2;end
    2:if(done) begin
       if(timeout || nack!=0) begin
        valid<=0;last_nack<=nack;last_timeout<=timeout;
        if(errors!=255) errors<=errors+1'b1;
        state<=0;
       end else begin
        staging[351-index*8 -: 8]<=data;
        if(index==43) state<=3;
        else begin index<=index+1'b1;state<=1;end
       end
      end
    3:begin
       // Commit the entire successful sweep atomically, never stale/partial bytes.
       registers<=staging;valid<=1;sequence_number<=sequence_number+1'b1;
       last_nack<=0;last_timeout<=0;state<=0;
      end
   endcase
  end
 end
endmodule

// Measure mean physical active-row spacing in the existing 50MHz reference
// domain, independent of PCLK gating/dividers/PLL assumptions. Never span VS.
module cam0_row_period(input clk,rst_n,href,vs,output reg [15:0] ticks);
 (* ASYNC_REG="TRUE" *) reg [1:0] hs,vsync;
 reg old_h,old_v,have_line;
 reg [23:0] elapsed,total;
 reg [7:0] intervals;
 wire hr=hs[1] && !old_h;
 wire vr=vsync[1] && !old_v;
 always @(posedge clk or negedge rst_n)
  if(!rst_n) begin
   hs<=0;vsync<=0;old_h<=0;old_v<=0;have_line<=0;
   elapsed<=0;total<=0;intervals<=0;ticks<=0;
  end else begin
   hs<={hs[0],href};vsync<={vsync[0],vs};old_h<=hs[1];old_v<=vsync[1];
   if(elapsed!=24'hffffff) elapsed<=elapsed+1'b1;
   if(vr) begin have_line<=0;total<=0;intervals<=0;end
   else if(hr && !vsync[1]) begin
    elapsed<=0;have_line<=1;
    if(have_line) begin
     if(elapsed>=65535) begin have_line<=0;ticks<=0;total<=0;intervals<=0;end
     else if(intervals==255) begin
      ticks<=(total+elapsed+1'b1)>>8;total<=0;intervals<=0;
     end else begin total<=total+elapsed+1'b1;intervals<=intervals+1'b1;end
    end
   end
  end
endmodule
