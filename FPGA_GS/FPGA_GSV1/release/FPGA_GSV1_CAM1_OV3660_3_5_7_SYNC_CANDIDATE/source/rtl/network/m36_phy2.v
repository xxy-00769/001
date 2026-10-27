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

// Independent PHY2 management. RTL8211E 001c:c915 only.
// Linux/U-Boot: page7, ext A4, reg1C: bit13 override, bit12 TX, bit11 RX.
// The adjacent historical Linux prose reverses TX/RX; use named definitions.
module m36_phy2 #(parameter START_CYCLES=2500000,POLL_CYCLES=500000,
 parameter MDIO_HALF=25, STRAP_ONLY=0, TX_DELAY_ENABLE=1, RX_DELAY_ENABLE=1)
(input clk,rst_n,phy_rstn,rx_clock,output mdc,inout mdio,output ready,
 output reg configured,output reg [4:0] address,output reg [15:0] status,
 output [127:0] diagnostics);
 localparam [15:0] DELAY_MASK=16'h3800;
 localparam [15:0] DELAY_BITS=16'h2000 | (TX_DELAY_ENABLE ? 16'h1000:16'h0000)
                                           | (RX_DELAY_ENABLE ? 16'h0800:16'h0000);
 localparam PAGE0=0, ID1=1, ID2=2, PAGE7=3, EXTA4=4, READ_DELAY=5,
            WRITE_DELAY=6, VERIFY=7, RESTORE=8, CHECK_PAGE=9, POLL=10, RECOVER=11;
 reg start,read_op;reg [4:0] regaddr;reg [15:0] wd;
 wire busy,done,ack;wire [15:0] rd;
 m36_mdio #(.HALF_PERIOD(MDIO_HALF)) bus(.clk(clk),.rst_n(rst_n && phy_rstn),
 .start(start),.read_op(read_op),.phy(address),.regaddr(regaddr),.write_data(wd),
 .mdio(mdio),.mdc(mdc),.busy(busy),.done(done),.ack(ack),.read_data(rd));
 reg [23:0] wait_count;reg [3:0] step;reg waiting,verified,scan_next;
 reg [15:0] delay_value,id1,id2,delay_read,no_ack,wrong_id,delay_fail;
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
 assign diagnostics={id1,id2,delay_read,no_ack,wrong_id,delay_fail,status,
  configured,ready,clock_alive,1'b0,step,3'd0,address};
 assign ready=configured && verified && status[15:14]==2'b10 && status[13]
                      && status[11] && status[10] && clock_alive;
 always @(posedge clk or negedge rst_n) if(!rst_n) begin
  start<=0;read_op<=1;regaddr<=31;wd<=0;configured<=0;verified<=0;
  address<=1;status<=0;wait_count<=START_CYCLES;step<=PAGE0;waiting<=0;
  delay_value<=0;scan_next<=0;id1<=0;id2<=0;delay_read<=0;
  no_ack<=0;wrong_id<=0;delay_fail<=0;
 end else if(!phy_rstn) begin
  start<=0;configured<=0;verified<=0;address<=1;status<=0;
  wait_count<=START_CYCLES;step<=PAGE0;waiting<=0;scan_next<=0;
 end else begin
  start<=0;
  if(wait_count!=0) wait_count<=wait_count-1'b1;
  else if(!waiting && !busy && !start) begin
   start<=1;waiting<=1;read_op<=1;wd<=0;
   case(step)
    PAGE0,RESTORE,RECOVER:begin regaddr<=31;read_op<=0;wd<=0;end
    ID1:regaddr<=2;
    ID2:regaddr<=3;
    PAGE7:begin regaddr<=31;read_op<=0;wd<=7;end
    EXTA4:begin regaddr<=30;read_op<=0;wd<=16'h00a4;end
    READ_DELAY,VERIFY:regaddr<=28;
    WRITE_DELAY:begin
     regaddr<=28;read_op<=STRAP_ONLY;
     wd<=(delay_value & ~DELAY_MASK) | DELAY_BITS;
    end
    CHECK_PAGE:regaddr<=31;
    POLL:regaddr<=17;
    default:regaddr<=31;
   endcase
  end else if(done && waiting) begin
   waiting<=0;
   if(!ack || (step==ID1 && rd!=16'h001c) ||
      (step==ID2 && rd!=16'hc915)) begin
    if(!ack) no_ack<=no_ack+1'b1;else wrong_id<=wrong_id+1'b1;
    configured<=0;verified<=0;status<=0;
    scan_next<=step==ID1 || step==ID2;
    step<=RECOVER;wait_count<=POLL_CYCLES;
   end else case(step)
    ID1:begin id1<=rd;step<=ID2;end
    ID2:begin id2<=rd;step<=PAGE7;end
    READ_DELAY:begin delay_value<=rd;step<=WRITE_DELAY;end
    VERIFY:begin
     delay_read<=rd;
     if(STRAP_ONLY || (rd & DELAY_MASK)==DELAY_BITS) begin verified<=1;step<=RESTORE;end
     else begin delay_fail<=delay_fail+1'b1;verified<=0;configured<=0;status<=0;step<=RECOVER;wait_count<=POLL_CYCLES;end
    end
    CHECK_PAGE:begin
     if(rd==0 && verified) begin configured<=1;step<=POLL;end
     else begin configured<=0;verified<=0;status<=0;delay_fail<=delay_fail+1'b1;step<=RECOVER;wait_count<=POLL_CYCLES;end
    end
    POLL:begin status<=rd;wait_count<=POLL_CYCLES;end
    RECOVER:begin
     if(scan_next) address<=address==31 ? 1:address+1'b1;
     scan_next<=0;step<=PAGE0;wait_count<=POLL_CYCLES;
    end
    default:step<=step+1'b1;
   endcase
  end
 end
endmodule
