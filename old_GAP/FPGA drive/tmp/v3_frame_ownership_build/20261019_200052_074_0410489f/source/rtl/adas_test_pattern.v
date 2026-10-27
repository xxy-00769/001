`timescale 1ns/1ps
// Synthetic-only source, independent of the camera pixel clock or I2C success.
// A permanent TEST label distinguishes this build from live-camera operation.
module adas_test_pattern #(
    parameter PHASE_FRAMES=120
)(
    input clk,rst_n,
    output de,vs,
    output [15:0] rgb,
    output reg [2:0] phase
);
    localparam WIDTH=1280,HEIGHT=720,HTOTAL=1296,VTOTAL=736;
    reg [10:0] x,y;
    reg [15:0] frames;
    always @(posedge clk) begin
        if(!rst_n) begin x<=0; y<=0; frames<=0; phase<=0; end
        else if(x==HTOTAL-1) begin
            x<=0;
            if(y==VTOTAL-1) begin
                y<=0;
                if(frames==PHASE_FRAMES-1) begin frames<=0; phase<=phase==5 ? 3'd0 : phase+1'b1; end
                else frames<=frames+1'b1;
            end else y<=y+1'b1;
        end else x<=x+1'b1;
    end
    wire [10:0] image_y=y-8;
    assign vs=rst_n && x==0 && y==0;
    assign de=rst_n && x<WIDTH && y>=8 && y<HEIGHT+8;
    wire [10:0] depth=image_y>=405 ? image_y-405 : 11'd0;
    wire signed [12:0] shift=phase==1 ? -13'sd100 : (phase==2 ? 13'sd100 : 13'sd0);
    wire signed [12:0] left_x=13'sd500-$signed({2'b00,depth>>1})+shift;
    wire signed [12:0] right_x=13'sd780+$signed({2'b00,depth>>1})+shift;
    wire signed [12:0] px=$signed({2'b00,x});
    wire dash_on=image_y<=515 || (image_y>=548 && image_y<=643) || image_y>=672;
    wire lane=phase<4 && image_y>=405 && (phase!=3 || dash_on)
              && ((px>=left_x-3 && px<=left_x+3) || (px>=right_x-3 && px<=right_x+3));
    wire zebra=phase==4 && image_y>=440 && image_y<=519 && x>=400 && x<680
               && ((x-400)%80)<40;
    wire label_area=x>=32 && x<128 && image_y>=80 && image_y<108;
    wire [6:0] tx=x-32;
    wire [4:0] ty=image_y-80;
    wire [1:0] letter=tx/24;
    wire [2:0] gx=(tx%24)>>2,gy=ty>>2;
    reg [34:0] glyph;
    always @* begin
        case(letter)
            1:glyph={5'b11111,5'b10000,5'b10000,5'b11110,5'b10000,5'b10000,5'b11111};
            2:glyph={5'b01111,5'b10000,5'b10000,5'b01110,5'b00001,5'b00001,5'b11110};
            default:glyph={5'b11111,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100};
        endcase
    end
    wire label_ink=label_area && gx<5 && gy<7 && glyph[34-gy*5-gx];
    assign rgb=!de ? 16'h0000 : label_ink ? 16'hFFE0 : (lane || zebra) ? 16'hFFFF : 16'h4228;
endmodule
