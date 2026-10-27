`timescale 1ns/1ps
// OV5640 v2.01 tables 4-8,7-8. CAM0 only, after legacy mode setup.
// Measured row=45.04us: 222 rows=9.99888ms. No clock/FOV/ISP changes.
// All writes are read-modify-write, then compare ALL bits including preserved bits.
module cam0_ae_profile #(
 parameter CLOCK_HZ=50000000,SCCB_HZ=100000,
 parameter [15:0] EXPOSURE_ROWS=222,
 parameter [9:0] GAIN_SIXTEENTHS=128,
 parameter [9:0] BAND50_ROWS=222,BAND60_ROWS=185,
 parameter MAINS_50HZ=1
)(input clk,rst_n,enable,inout scl,sda,
 output reg configured,failed,output reg [15:0] last_register,
 output reg [3:0] error_code);
 function [15:0] addr(input [4:0] i);
 begin case(i)
 0:addr=16'h300a;1:addr=16'h300b;
 2:addr=16'h3503;3:addr=16'h3a00;
 4:addr=16'h3a02;5:addr=16'h3a03;
 6:addr=16'h3a14;7:addr=16'h3a15;
 8:addr=16'h3a18;9:addr=16'h3a19;
 10:addr=16'h3a08;11:addr=16'h3a09;
 12:addr=16'h3a0a;13:addr=16'h3a0b;
 14:addr=16'h3a0d;15:addr=16'h3a0e;
 16:addr=16'h3c00;17:addr=16'h3c01;
 default:addr=16'h300a;endcase end endfunction
 function [7:0] mask(input [4:0] i);
 begin case(i)
 2:mask=8'h03;3:mask=8'h04;6:mask=8'h0f;
 8,10,12:mask=8'h03;16:mask=8'h04;17:mask=8'h80;
 default:mask=8'hff;endcase end endfunction
 function [7:0] bits(input [4:0] i);
 begin case(i)
 0:bits=8'h56;1:bits=8'h40;2,3:bits=0;
 4,6:bits=EXPOSURE_ROWS[15:8];5,7:bits=EXPOSURE_ROWS[7:0];
 8:bits={6'b0,GAIN_SIXTEENTHS[9:8]};9:bits=GAIN_SIXTEENTHS[7:0];
 10:bits={6'b0,BAND50_ROWS[9:8]};11:bits=BAND50_ROWS[7:0];
 12:bits={6'b0,BAND60_ROWS[9:8]};13:bits=BAND60_ROWS[7:0];
 // One full illumination band fits under this profile's exposure cap.
 14,15:bits=1;16:bits=MAINS_50HZ ? 8'h04:8'h00;17:bits=8'h80;
 default:bits=0;endcase end endfunction
 reg [4:0] index;
 reg [3:0] state;
 reg rs,ws;
 reg [7:0] write_value;
 wire rd,wd,rt,wt;wire [3:0] rn,wn;wire [7:0] data;
 cam_sccb_read16 #(.CLOCK_HZ(CLOCK_HZ),.SCCB_HZ(SCCB_HZ)) reader(
 .clk(clk),.rst_n(rst_n && enable),.start(rs),.address(7'h3c),
 .register_address(addr(index)),.scl(scl),.sda(sda),.busy(),
 .done(rd),.data(data),.nack_mask(rn),.bus_timeout(rt));
 cam_sccb_write16 #(.CLOCK_HZ(CLOCK_HZ),.SCCB_HZ(SCCB_HZ)) writer(
 .clk(clk),.rst_n(rst_n && enable),.start(ws),.address(7'h3c),
 .register_address(addr(index)),.value(write_value),.scl(scl),.sda(sda),
 .busy(),.done(wd),.nack_mask(wn),.bus_timeout(wt));
 // error:1 read ACK,2 read timeout,3 wrong ID,4 write ACK,
 // 5 write timeout,6 verify mismatch. Sticky until camera reset.
 always @(posedge clk or negedge rst_n) begin
 if(!rst_n) begin
  configured<=0;failed<=0;last_register<=0;error_code<=0;
  state<=0;index<=0;rs<=0;ws<=0;write_value<=0;
 end else begin
  rs<=0;ws<=0;
  if(enable && !failed && !configured) case(state)
   0:begin last_register<=addr(index);rs<=1;state<=1;end
   1:if(rd) begin
    if(rt || rn!=0) begin failed<=1;error_code<=rt?2:1;end
    else if(index<2) begin
     if(data!=bits(index)) begin failed<=1;error_code<=3;end
     else begin index<=index+1'b1;state<=0;end
    end else begin write_value<=(data & ~mask(index)) | (bits(index)&mask(index));state<=2;end
   end
   2:begin ws<=1;state<=3;end
   3:if(wd) begin
    if(wt || wn!=0) begin failed<=1;error_code<=wt?5:4;end
    else state<=4;
   end
   4:begin rs<=1;state<=5;end
   5:if(rd) begin
    if(rt || rn!=0) begin failed<=1;error_code<=rt?2:1;end
    else if(data!=write_value) begin failed<=1;error_code<=6;end
    else if(index==17) configured<=1;
    else begin index<=index+1'b1;state<=0;end
   end
  endcase
 end end
endmodule
