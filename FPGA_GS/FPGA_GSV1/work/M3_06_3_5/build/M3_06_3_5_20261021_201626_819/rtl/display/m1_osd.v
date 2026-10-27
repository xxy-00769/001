`timescale 1ns/1ps
module m1_osd(input [9:0] x,input [8:0] y,input rear,output area, pixel);
    wire [5:0] dx=x-10'd12;
    wire [3:0] row=y-9'd12;
    wire [1:0] glyph=dx[4] ? 2'd2 : (rear ? 2'd1 : 2'd0);
    reg [15:0] bits;
    assign area=x>=12 && x<44 && y>=12 && y<28;
    assign pixel=area && bits[15-dx[3:0]];
    always @* begin
        bits=0;
        case({glyph,row})
            6'd0: bits=16'h0820;
            6'd1: bits=16'hfffe;
            6'd2: bits=16'h0000;
            6'd3: bits=16'h3e08;
            6'd4: bits=16'h2248;
            6'd5: bits=16'h2248;
            6'd6: bits=16'h3e48;
            6'd7: bits=16'h2248;
            6'd8: bits=16'h2248;
            6'd9: bits=16'h3e48;
            6'd10: bits=16'h2208;
            6'd11: bits=16'h2208;
            6'd12: bits=16'h2a28;
            6'd13: bits=16'h2410;
            6'd14: bits=16'h0000;
            6'd15: bits=16'h0000;
            6'd16: bits=16'h1f00;
            6'd17: bits=16'h1000;
            6'd18: bits=16'h1000;
            6'd19: bits=16'h1ffe;
            6'd20: bits=16'h1000;
            6'd21: bits=16'h1000;
            6'd22: bits=16'h1000;
            6'd23: bits=16'h17f8;
            6'd24: bits=16'h1408;
            6'd25: bits=16'h2408;
            6'd26: bits=16'h2408;
            6'd27: bits=16'h4408;
            6'd28: bits=16'h87f8;
            6'd29: bits=16'h0408;
            6'd30: bits=16'h0000;
            6'd31: bits=16'h0000;
            6'd32: bits=16'h1108;
            6'd33: bits=16'h11f8;
            6'd34: bits=16'hfd08;
            6'd35: bits=16'h11f8;
            6'd36: bits=16'h110e;
            6'd37: bits=16'h17f8;
            6'd38: bits=16'h1808;
            6'd39: bits=16'h37bc;
            6'd40: bits=16'hd0a4;
            6'd41: bits=16'h12a4;
            6'd42: bits=16'h1128;
            6'd43: bits=16'h1290;
            6'd44: bits=16'h54a8;
            6'd45: bits=16'h2846;
            6'd46: bits=16'h0000;
            6'd47: bits=16'h0000;
            default: bits=0;
        endcase
    end
endmodule
