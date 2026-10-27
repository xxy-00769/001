`timescale 1ns/1ps
// Passive CAM1-only frequency/rate observation. No output controls capture,
// clocking, ownership or network. Prescaled count measures actual sensor PCLK
// against the existing 50MHz board reference; it is not an XCLK measurement.
module cam1_rate_status #(parameter REF_HZ=50000000)(
 input sc,pclk,dc,vc,rst_n,visible,input [31:0] published,displayed,
 output [31:0] counts,output reg [31:0] milliseconds,pclk_hz);
 reg [7:0] byte_count;
 always @(posedge pclk or negedge rst_n)
  if(!rst_n) byte_count<=0;
  else byte_count<=byte_count+1'b1;
 // Single-bit /256 envelope; each half lasts128 PCLK cycles (~1.78us),
 // safely sampled at50MHz. No asynchronous multi-bit counter bus.
 (* ASYNC_REG="TRUE" *) reg [1:0] prescale_sync;
 reg prescale_old;
 reg [19:0] pulse_count;
 wire pulse=prescale_sync[1] && !prescale_old;
 reg [25:0] second_tick;
 reg [15:0] millisecond_tick;
 reg valid_window;
 always @(posedge sc or negedge rst_n)
  if(!rst_n) begin
   prescale_sync<=0;prescale_old<=0;pulse_count<=0;
   second_tick<=0;millisecond_tick<=0;
   milliseconds<=0;pclk_hz<=0;valid_window<=0;
  end else begin
   prescale_sync<={prescale_sync[0],byte_count[7]};
   prescale_old<=prescale_sync[1];
   if(pulse) pulse_count<=pulse_count+1'b1;
   if(millisecond_tick==REF_HZ/1000-1) begin
    millisecond_tick<=0;milliseconds<=milliseconds+1'b1;
   end else millisecond_tick<=millisecond_tick+1'b1;
   if(second_tick==REF_HZ-1) begin
    second_tick<=0;pulse_count<=0;valid_window<=1;
    if(valid_window) pclk_hz<={4'd0,(pulse_count+{19'd0,pulse}),8'd0};
   end else second_tick<=second_tick+1'b1;
  end
 reg [15:0] last_display,visible_count;
 always @(posedge vc or negedge rst_n)
  if(!rst_n) begin last_display<=0;visible_count<=0;end
  else begin
   last_display<=displayed[15:0];
   // The source counter already checks distinct ID, full rows and underflow.
   // Exclude images hidden by the existing final health/presentation guard.
   if(visible && displayed[15:0]!=last_display) visible_count<=visible_count+1'b1;
  end
 wire [15:0] p,d;
 m361_snapshot #(.W(16)) pub(.sc(dc),.dc(sc),.rst_n(rst_n),
  .value(published[15:0]),.snapshot(p));
 m361_snapshot #(.W(16)) disp(.sc(vc),.dc(sc),.rst_n(rst_n),
  .value(visible_count),.snapshot(d));
 assign counts={p,d};
endmodule
