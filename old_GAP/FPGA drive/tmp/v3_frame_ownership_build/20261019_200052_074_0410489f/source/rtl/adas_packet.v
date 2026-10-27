`timescale 1ns/1ps
// Transport-neutral result bytes. No UART/SPI/ethernet pins are implied.
// A5 5A 01 20, 32 payload bytes (LSB first), CRC16 low/high.
// CRC covers version, length, payload: poly 1021, init FFFF, no reflection/xor.
module adas_packet(
    input clk,rst_n,sample_valid,
    input [255:0] sample,
    output sample_ready,
    output reg [15:0] dropped_samples,
    output [7:0] data,
    output valid,
    input ready
);
    reg busy;
    reg [5:0] index;
    reg [255:0] captured;
    reg [15:0] crc;
    function [15:0] crc_byte;
        input [15:0] previous;
        input [7:0] value;
        reg [15:0] c;
        integer i;
        begin
            c=previous^{value,8'd0};
            for(i=0;i<8;i=i+1) c=c[15] ? (c<<1)^16'h1021 : c<<1;
            crc_byte=c;
        end
    endfunction
    assign sample_ready=!busy;
    assign valid=busy;
    assign data=index==0 ? 8'hA5 : index==1 ? 8'h5A : index==2 ? 8'h01
                : index==3 ? 8'd32 : index==36 ? crc[7:0] : index==37 ? crc[15:8]
                : (captured >> ((index-4)*8));
    always @(posedge clk) begin
        if(!rst_n) begin busy<=0; index<=0; captured<=0; crc<=16'hFFFF; dropped_samples<=0; end
        else begin
            if(sample_valid && !sample_ready && dropped_samples!=65535) dropped_samples<=dropped_samples+1'b1;
            if(sample_valid && sample_ready) begin busy<=1; index<=0; captured<=sample; crc<=16'hFFFF; end
            else if(valid && ready) begin
                if(index>=2 && index<36) crc<=crc_byte(crc,data);
                if(index==37) busy<=0;
                else index<=index+1'b1;
            end
        end
    end
endmodule
