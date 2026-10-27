`timescale 1ns/1ps
// CAM1-only, fixed-address identification. Complete two independent reads of
// both ID bytes before accepting the sensor. This does not configure a sensor
// or publish video. CAM0's released controller remains unchanged.
module cam_sensor_id #(
    parameter CLOCK_HZ=50000000,
    parameter SCCB_HZ=100000,
    parameter WAIT_TICKS=400,
    parameter EXPECTED_ID=16'h3660
)(
    input clk,rst_n,enable,
    inout scl,sda,
    output reg finished,identified,
    output reg [15:0] sensor_id,confirmation_id,
    output reg [15:0] nack_masks,
    output reg timeout_error
);
    reg [1:0] enable_sync;
    reg [2:0] step;
    reg active,read_start;
    wire busy,done,timeout;
    wire [7:0] octet;
    wire [3:0] nacks;
    cam_sccb_read16 #(.CLOCK_HZ(CLOCK_HZ),.SCCB_HZ(SCCB_HZ),
      .WAIT_TICKS(WAIT_TICKS)) reader(
      .clk(clk),.rst_n(rst_n),.start(read_start),.address(7'h3c),
      .register_address(step[0] ? 16'h300b:16'h300a),.scl(scl),.sda(sda),
      .busy(busy),.done(done),.data(octet),.nack_mask(nacks),.bus_timeout(timeout));
    always @(posedge clk or negedge rst_n) begin
      if(!rst_n) begin
        enable_sync<=0;step<=0;active<=0;read_start<=0;
        finished<=0;identified<=0;sensor_id<=0;confirmation_id<=0;
        nack_masks<=16'hffff;timeout_error<=0;
      end else begin
        enable_sync<={enable_sync[0],enable};read_start<=0;
        if(enable_sync[1] && !finished) begin
          if(!active && !busy && !read_start) begin active<=1;read_start<=1;end
          if(done) begin
            active<=0;
            case(step)
              0:begin sensor_id[15:8]<=octet;nack_masks[3:0]<=nacks;end
              1:begin sensor_id[7:0]<=octet;nack_masks[7:4]<=nacks;end
              2:begin confirmation_id[15:8]<=octet;nack_masks[11:8]<=nacks;end
              3:begin confirmation_id[7:0]<=octet;nack_masks[15:12]<=nacks;end
            endcase
            if(timeout || nacks!=0) begin
              finished<=1;identified<=0;timeout_error<=timeout;
            end else if(step==3) begin
              finished<=1;
              identified<=sensor_id==EXPECTED_ID && confirmation_id[15:8]==sensor_id[15:8]
                && octet==sensor_id[7:0];
            end else step<=step+1'b1;
          end
        end
      end
    end
endmodule
