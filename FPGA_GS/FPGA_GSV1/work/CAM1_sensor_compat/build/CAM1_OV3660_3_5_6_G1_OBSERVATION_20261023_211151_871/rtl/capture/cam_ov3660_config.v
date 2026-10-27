`timescale 1ns/1ps
// Fixed CAM1 OV3660: two physical ID reads, ACK-checked dedicated table,
// mandatory waits, then critical register readback. Failure never raises ready.
module cam_ov3660_config #(
  parameter CLOCK_HZ=50000000,SCCB_HZ=100000,WAIT_TICKS=400
)(input clk,rst_n,enable,inout scl,sda,
  output id_finished,identified,output [15:0] sensor_id,confirmation_id,nack_masks,
  output id_timeout,output reg configured,failed,
  output reg [15:0] last_register,output reg [7:0] error_code);
  localparam WAIT_ID=0,ENTRY=1,WRITE_WAIT=2,DELAY=3,VERIFY=4,READ_WAIT=5,STOP=6;
  localparam LAST_ENTRY=234, LAST_CHECK=18;
  reg [2:0] state;
  reg [8:0] index;
  reg [4:0] check_index;
  reg [31:0] wait_count;
  reg write_start,read_start;
  wire [23:0] entry;
  wire write_busy,write_done,write_timeout,read_busy,read_done,read_timeout;
  wire [3:0] write_nacks,read_nacks;
  wire [7:0] read_value;
  cam_sensor_id #(.CLOCK_HZ(CLOCK_HZ),.SCCB_HZ(SCCB_HZ),.WAIT_TICKS(WAIT_TICKS)) id(
    .clk(clk),.rst_n(rst_n),.enable(enable),.scl(scl),.sda(sda),
    .finished(id_finished),.identified(identified),.sensor_id(sensor_id),
    .confirmation_id(confirmation_id),.nack_masks(nack_masks),.timeout_error(id_timeout));
  cam_ov3660_table table_rom(.index(index),.entry(entry));
  cam_sccb_write16 #(.CLOCK_HZ(CLOCK_HZ),.SCCB_HZ(SCCB_HZ),.WAIT_TICKS(WAIT_TICKS)) writer(
    .clk(clk),.rst_n(rst_n),.start(write_start),.address(7'h3c),
    .register_address(entry[23:8]),.value(entry[7:0]),.scl(scl),.sda(sda),
    .busy(write_busy),.done(write_done),.nack_mask(write_nacks),.bus_timeout(write_timeout));
  function [23:0] expected;
    input [4:0] n;
    begin case(n)
      0:expected=24'h380805;1:expected=24'h380900;
      2:expected=24'h380a02;3:expected=24'h380bd0;
      4:expected=24'h501f01;5:expected=24'h430061;
      6:expected=24'h474023;7:expected=24'h303a00;
      8:expected=24'h303b18;9:expected=24'h303c12;
      10:expected=24'h303d20;11:expected=24'h382401;
      12:expected=24'h460c22;13:expected=24'h382040;
      14:expected=24'h382100;15:expected=24'h381411;
      16:expected=24'h381511;17:expected=24'h5001a3;
      default:expected=24'h300802;
    endcase end
  endfunction
  wire [23:0] check_entry=expected(check_index);
  // 3008 reset is self-clearing; verify reset/standby both cleared, not RSVD.
  wire [7:0] check_mask=check_index==LAST_CHECK ? 8'hc0:8'hff;
  cam_sccb_read16 #(.CLOCK_HZ(CLOCK_HZ),.SCCB_HZ(SCCB_HZ),.WAIT_TICKS(WAIT_TICKS)) reader(
    .clk(clk),.rst_n(rst_n),.start(read_start),.address(7'h3c),
    .register_address(check_entry[23:8]),.scl(scl),.sda(sda),
    .busy(read_busy),.done(read_done),.data(read_value),
    .nack_mask(read_nacks),.bus_timeout(read_timeout));
  always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
      state<=WAIT_ID;index<=0;check_index<=0;wait_count<=0;
      write_start<=0;read_start<=0;configured<=0;failed<=0;last_register<=0;error_code<=0;
    end else begin
      write_start<=0;read_start<=0;
      case(state)
        WAIT_ID:if(id_finished) begin
          if(!identified) begin failed<=1;error_code<=1;state<=STOP;end
          else state<=ENTRY;
        end
        ENTRY:begin
          if(entry[23:8]==16'hffff) begin
            wait_count<=(CLOCK_HZ/1000)*entry[7:0];state<=DELAY;
          end else if(!write_busy) begin
            last_register<=entry[23:8];write_start<=1;state<=WRITE_WAIT;
          end
        end
        WRITE_WAIT:if(write_done) begin
          if(write_timeout || write_nacks!=0) begin
            failed<=1;error_code<=write_timeout ? 8'd3:8'd2;state<=STOP;
          end else if(index==LAST_ENTRY) state<=VERIFY;
          else begin index<=index+1'b1;state<=ENTRY;end
        end
        DELAY:if(wait_count!=0) wait_count<=wait_count-1'b1;
          else if(index==LAST_ENTRY) state<=VERIFY;
          else begin index<=index+1'b1;state<=ENTRY;end
        VERIFY:if(!read_busy) begin
          last_register<=check_entry[23:8];read_start<=1;state<=READ_WAIT;
        end
        READ_WAIT:if(read_done) begin
          if(read_timeout || read_nacks!=0) begin
            failed<=1;error_code<=read_timeout ? 8'd3:8'd4;state<=STOP;
          end else if((read_value & check_mask)!=(check_entry[7:0] & check_mask)) begin
            failed<=1;error_code<=5;state<=STOP;
          end else if(check_index==LAST_CHECK) begin configured<=1;state<=STOP;end
          else begin check_index<=check_index+1'b1;state<=VERIFY;end
        end
        default:state<=STOP;
      endcase
    end
  end
endmodule
