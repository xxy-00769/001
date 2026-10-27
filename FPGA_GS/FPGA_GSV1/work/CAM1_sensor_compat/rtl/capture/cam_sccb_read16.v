`timescale 1ns/1ps
// Read-only sensor identification transport. 7-bit address is explicit;
// address bytes are MSB first. Repeated START follows OV3660 v1.3 section
// 6.3/figure 6-2. No sensor register DATA byte is ever written by this module.
module cam_sccb_read16 #(
    parameter CLOCK_HZ=50000000,
    parameter SCCB_HZ=100000,
    parameter WAIT_TICKS=400
)(
    input clk,rst_n,start,
    input [6:0] address,
    input [15:0] register_address,
    inout scl,sda,
    output reg busy,done,
    output reg [7:0] data,
    output reg [3:0] nack_mask,
    output reg bus_timeout
);
    localparam DIV=CLOCK_HZ/(4*SCCB_HZ);
    localparam IDLE=0,START_IDLE=1,START_SDA=2,START_LOW=3,
      SEND_LOW=4,SEND_RISE=5,SEND_HIGH=6,SEND_FALL=7,
      ACK_LOW=8,ACK_RISE=9,ACK_HIGH=10,ACK_FALL=11,
      READ_LOW=12,READ_RISE=13,READ_HIGH=14,READ_FALL=15,
      NACK_LOW=16,NACK_RISE=17,NACK_HIGH=18,NACK_FALL=19,
      STOP_LOW=20,STOP_RISE=21,STOP_RELEASE=22,STOP_GAP=23,
      RESTART_LOW=24,RESTART_RISE=25,RESTART_HIGH=26;
    reg [4:0] state;
    reg [15:0] divider,wait_count;
    reg scl_low,sda_low;
    reg [1:0] byte_index;
    reg [2:0] bit_index;
    reg [7:0] send_byte;
    reg [6:0] held_address;
    reg [15:0] held_register;
    reg [1:0] scl_sync,sda_sync;
    assign scl=scl_low ? 1'b0:1'bz;
    assign sda=sda_low ? 1'b0:1'bz;
    always @(posedge clk or negedge rst_n)
      if(!rst_n) begin scl_sync<=3; sda_sync<=3; end
      else begin scl_sync<={scl_sync[0],scl};sda_sync<={sda_sync[0],sda};end
    wire tick=divider==DIV-1;
    always @(posedge clk or negedge rst_n)
      if(!rst_n) divider<=0;
      else if(tick) divider<=0;
      else divider<=divider+1'b1;
    wire waiting=(state==START_IDLE && (!scl_sync[1] || !sda_sync[1]))
      || ((state==SEND_RISE || state==ACK_RISE || state==READ_RISE
          || state==NACK_RISE || state==STOP_RISE || state==RESTART_RISE) && !scl_sync[1]);
    always @(posedge clk or negedge rst_n) begin
      if(!rst_n) begin
        state<=IDLE;scl_low<=0;sda_low<=0;busy<=0;done<=0;
        data<=0;nack_mask<=15;bus_timeout<=0;wait_count<=0;
        byte_index<=0;bit_index<=7;send_byte<=0;
        held_address<=0;held_register<=0;
      end else begin
        done<=0;
        if(state==IDLE && start) begin
          held_address<=address;held_register<=register_address;
          send_byte<={address,1'b0};byte_index<=0;bit_index<=7;
          data<=0;nack_mask<=15;bus_timeout<=0;busy<=1;
          wait_count<=0;state<=START_IDLE;
        end else if(tick && state!=IDLE) begin
          if(waiting && wait_count==WAIT_TICKS-1) begin
            // Release both pins on timeout; never report an ACKed result.
            scl_low<=0;sda_low<=0;bus_timeout<=1;
            busy<=0;done<=1;state<=IDLE;wait_count<=0;
          end else begin
            if(waiting) wait_count<=wait_count+1'b1;
            else wait_count<=0;
            case(state)
              START_IDLE:if(scl_sync[1] && sda_sync[1]) state<=START_SDA;
              START_SDA:begin sda_low<=1;state<=START_LOW;end
              START_LOW:begin scl_low<=1;state<=SEND_LOW;end
              SEND_LOW:begin sda_low<=!send_byte[bit_index];state<=SEND_RISE;end
              SEND_RISE:begin scl_low<=0;if(scl_sync[1]) state<=SEND_HIGH;end
              SEND_HIGH:state<=SEND_FALL;
              SEND_FALL:begin
                scl_low<=1;
                if(bit_index==0) state<=ACK_LOW;
                else begin bit_index<=bit_index-1'b1;state<=SEND_LOW;end
              end
              ACK_LOW:begin sda_low<=0;state<=ACK_RISE;end
              ACK_RISE:begin scl_low<=0;if(scl_sync[1]) state<=ACK_HIGH;end
              ACK_HIGH:begin nack_mask[byte_index]<=sda_sync[1];state<=ACK_FALL;end
              ACK_FALL:begin
                scl_low<=1;bit_index<=7;
                if(nack_mask[byte_index]) state<=STOP_LOW;
                else case(byte_index)
                  0:begin byte_index<=1;send_byte<=held_register[15:8];state<=SEND_LOW;end
                  1:begin byte_index<=2;send_byte<=held_register[7:0];state<=SEND_LOW;end
                  2:begin
                    byte_index<=3;send_byte<={held_address,1'b1};state<=RESTART_LOW;
                  end
                  3:state<=READ_LOW;
                endcase
              end
              RESTART_LOW:begin sda_low<=0;state<=RESTART_RISE;end
              RESTART_RISE:begin scl_low<=0;if(scl_sync[1]) state<=RESTART_HIGH;end
              RESTART_HIGH:state<=START_SDA;
              READ_LOW:begin sda_low<=0;state<=READ_RISE;end
              READ_RISE:begin scl_low<=0;if(scl_sync[1]) state<=READ_HIGH;end
              READ_HIGH:begin data[bit_index]<=sda_sync[1];state<=READ_FALL;end
              READ_FALL:begin
                scl_low<=1;
                if(bit_index==0) state<=NACK_LOW;
                else begin bit_index<=bit_index-1'b1;state<=READ_LOW;end
              end
              NACK_LOW:begin sda_low<=0;state<=NACK_RISE;end
              NACK_RISE:begin scl_low<=0;if(scl_sync[1]) state<=NACK_HIGH;end
              NACK_HIGH:state<=NACK_FALL;
              NACK_FALL:begin scl_low<=1;state<=STOP_LOW;end
              STOP_LOW:begin sda_low<=1;state<=STOP_RISE;end
              STOP_RISE:begin scl_low<=0;if(scl_sync[1]) state<=STOP_RELEASE;end
              STOP_RELEASE:begin sda_low<=0;state<=STOP_GAP;end
              STOP_GAP:begin
                busy<=0;done<=1;state<=IDLE;
              end
              default:state<=IDLE;
            endcase
          end
        end
      end
    end
endmodule
