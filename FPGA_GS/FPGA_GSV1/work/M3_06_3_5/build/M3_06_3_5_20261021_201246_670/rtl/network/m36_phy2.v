`timescale 1ns/1ps
// Clause22: MDIO changes on MDC falling edges, samples on rising edges.
module m36_mdio #(parameter HALF_PERIOD=25)(input clk,rst_n,start,read_op,
 input [4:0] phy,regaddr,input [15:0] write_data,inout mdio,
 output reg mdc,output reg busy,done,ack,output reg [15:0] read_data);
 reg [63:0] bits;reg [6:0] index;reg [7:0] divider;reg reading;
 wire drive=busy && !(reading && index>=46);
 assign mdio=drive ? bits[63-index] : 1'bz;
 always @(posedge clk or negedge rst_n) if(!rst_n) begin
  mdc<=0;busy<=0;done<=0;ack<=0;read_data<=0;bits<=0;index<=0;divider<=0;reading<=0;
 end else begin
  done<=0;
  if(!busy) begin
   mdc<=0;divider<=0;
   if(start) begin
    bits<={32'hffffffff,2'b01,(read_op ? 2'b10:2'b01),phy,regaddr,2'b10,write_data};
    busy<=1;reading<=read_op;index<=0;read_data<=0;ack<=!read_op;
   end
  end else if(divider==HALF_PERIOD-1) begin
   divider<=0;mdc<=~mdc;
   if(!mdc) begin
    if(reading && index==47) ack<=mdio===1'b0;
    if(reading && index>=48) read_data<={read_data[14:0],mdio};
   end else if(index==63) begin busy<=0;done<=1;mdc<=0;end
   else index<=index+1'b1;
  end else divider<=divider+1'b1;
 end
endmodule

// Independent PHY2 management; no PLL or port1 clock/reset dependency.
// RTL8211E page7/ext A4 reg1C [13:11] enables the internal RX/TX delays.
module m36_phy2 #(parameter START_CYCLES=2500000,POLL_CYCLES=500000,
 parameter MDIO_HALF=25)(input clk,rst_n,phy_rstn,rx_clock,
 output mdc,inout mdio,output ready,output reg configured,
 output reg [4:0] address,output reg [15:0] status);
 reg start,read_op;reg [4:0] regaddr;reg [15:0] wd;
 wire busy,done,ack;wire [15:0] rd;
 m36_mdio #(.HALF_PERIOD(MDIO_HALF)) bus(.clk(clk),.rst_n(rst_n && phy_rstn),
 .start(start),.read_op(read_op),.phy(address),.regaddr(regaddr),.write_data(wd),
 .mdio(mdio),.mdc(mdc),.busy(busy),.done(done),.ack(ack),.read_data(rd));
 reg [23:0] wait_count;reg [3:0] step;reg waiting;reg [15:0] delay_value;
 reg [5:0] rx_count;wire rx_alive_bit=rx_count[5];
 always @(posedge rx_clock or negedge rst_n) if(!rst_n) rx_count<=0;else rx_count<=rx_count+1'b1;
 reg [2:0] alive_sync;reg alive_last;reg [15:0] silent;reg clock_alive;
 always @(posedge clk or negedge rst_n) if(!rst_n) begin
  alive_sync<=0;alive_last<=0;silent<=0;clock_alive<=0;
 end else begin
  alive_sync<={alive_sync[1:0],rx_alive_bit};alive_last<=alive_sync[2];
  if(alive_last!=alive_sync[2]) begin silent<=0;clock_alive<=1;end
  else if(silent==65535) clock_alive<=0;else silent<=silent+1'b1;
 end
 assign ready=configured && status[15:14]==2'b10 && status[13] && status[11] && status[10] && clock_alive;
 always @(posedge clk or negedge rst_n) if(!rst_n) begin
  start<=0;read_op<=1;regaddr<=2;wd<=0;configured<=0;address<=1;status<=0;
  wait_count<=START_CYCLES;step<=0;waiting<=0;delay_value<=0;
 end else if(!phy_rstn) begin
  start<=0;configured<=0;address<=1;status<=0;wait_count<=START_CYCLES;step<=0;waiting<=0;
 end else begin
  start<=0;
  if(wait_count!=0) wait_count<=wait_count-1'b1;
  else if(!waiting && !busy && !start) begin
   start<=1;waiting<=1;read_op<=1;wd<=0;
   case(step)
    0:regaddr<=2;
    1:regaddr<=3;
    2:begin regaddr<=31;read_op<=0;wd<=7;end
    3:begin regaddr<=30;read_op<=0;wd<=16'h00a4;end
    4:regaddr<=28;
    5:begin regaddr<=28;read_op<=0;wd<=delay_value|16'h3800;end
    6:regaddr<=28;
    7:begin regaddr<=31;read_op<=0;wd<=0;end
    8:regaddr<=17;
    9:begin regaddr<=31;read_op<=0;wd<=0;end
   endcase
  end else if(done && waiting) begin
   waiting<=0;
   if(!ack || (step==0 && rd!=16'h001c) || (step==1 && rd[15:4]!=12'hc91)) begin
    address<=address==31 ? 1:address+1'b1;configured<=0;status<=0;step<=9;wait_count<=POLL_CYCLES;
   end else case(step)
    4:begin delay_value<=rd;step<=5;end
    6:if(rd[13:11]==3'b111) step<=7;else begin step<=9;configured<=0;wait_count<=POLL_CYCLES;end
    7:begin configured<=1;step<=8;end
    8:begin status<=rd;wait_count<=POLL_CYCLES;end
    9:step<=0;
    default:step<=step+1'b1;
   endcase
  end
 end
endmodule
