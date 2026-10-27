`timescale 1ns/1ps
// Extract only the proven MS7210 output configuration; no HDMI input instance.
module hdmi_tx_config #(parameter AVI_VIC=0)(input clk, rst_n, output done, output scl, inout sda);
    reg [2:0] reset_sync;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) reset_sync <= 0; else reset_sync <= {reset_sync[1:0],1'b1};
    wire [7:0] device, data_in, data_out;
    wire [15:0] address;
    wire trigger, write_read, busy, byte_done, sda_in, sda_out, sda_en;
    ms7210_ctl #(.AVI_VIC(AVI_VIC)) config_tx(.clk(clk),.rstn(reset_sync[2]),.init_over(done),
        .device_id(device),.iic_trig(trigger),.w_r(write_read),.addr(address),
        .data_in(data_in),.busy(busy),.data_out(data_out),.byte_over(byte_done));
    iic_dri #(.CLK_FRE(10000000),.IIC_FREQ(400000),.T_WR(1),
        .ADDR_BYTE(2),.LEN_WIDTH(3),.DATA_BYTE(1)) bus_tx(
        .clk(clk),.rstn(reset_sync[2]),.device_id(device),.pluse(trigger),
        .w_r(write_read),.byte_len(4'd1),.addr(address),.data_in(data_in),
        .busy(busy),.byte_over(byte_done),.data_out(data_out),
        .scl(scl),.sda_in(sda_in),.sda_out(sda_out),.sda_out_en(sda_en));
    assign sda = sda_en ? sda_out : 1'bz;
    assign sda_in = sda;
endmodule
