`timescale 1ns/1ps
// Frame-frozen experimental HUD and thin image-space lane segments.
module adas_overlay #(
    parameter H_ACTIVE=1280,V_ACTIVE=720
)(
    input clk,rst_n,de,vs,enable,
    input [15:0] rgb_in,
    input result_valid,
    input [255:0] snapshot,
    output [15:0] rgb_out
);
    reg [255:0] pending,shown;
    reg vs_d,de_d;
    reg [10:0] x,y;
    always @(posedge clk) begin
        if(!rst_n) begin pending<=0; shown<=0; vs_d<=0; de_d<=0; x<=0; y<=0; end
        else begin
            vs_d<=vs; de_d<=de;
            if(result_valid) pending<=snapshot;
            if(vs && !vs_d) begin
                x<=0; y<=0; shown<=result_valid ? snapshot : pending;
            end else if(de_d && !de) begin x<=0; y<=y==V_ACTIVE-1 ? 11'd0 : y+1'b1; end
            else if(de) x<=x+1'b1;
        end
    end
    wire [7:0] flags=shown[7:0];
    wire [1:0] lk=shown[9:8],rk=shown[11:10],warning=shown[13:12];
    wire signed [15:0] offset_px=shown[47:32];
    wire [15:0] magnitude=offset_px[15] ? -offset_px : offset_px;
    wire [9:0] decimal_value=magnitude>999 ? 10'd999 : magnitude[9:0];
    wire [10:0] lx0=shown[74:64],ly0=shown[90:80],lx1=shown[106:96],ly1=shown[122:112];
    wire [10:0] rx0=shown[138:128],ry0=shown[154:144],rx1=shown[170:160],ry1=shown[186:176];
    wire signed [11:0] ldx=$signed({1'b0,lx1})-$signed({1'b0,lx0});
    wire signed [11:0] ldy=$signed({1'b0,ly1})-$signed({1'b0,ly0});
    wire signed [11:0] rdx=$signed({1'b0,rx1})-$signed({1'b0,rx0});
    wire signed [11:0] rdy=$signed({1'b0,ry1})-$signed({1'b0,ry0});
    wire signed [11:0] lpx=$signed({1'b0,x})-$signed({1'b0,lx0});
    wire signed [11:0] lpy=$signed({1'b0,y})-$signed({1'b0,ly0});
    wire signed [11:0] rpx=$signed({1'b0,x})-$signed({1'b0,rx0});
    wire signed [11:0] rpy=$signed({1'b0,y})-$signed({1'b0,ry0});
    wire signed [24:0] le=lpx*ldy-lpy*ldx;
    wire signed [24:0] re=rpx*rdy-rpy*rdx;
    wire left_line=flags[0] && y>=ly0 && y<=ly1 && ly1>ly0 && le<=ldy && le>=-ldy
                   && (lk!=2 || y[3]);
    wire right_line=flags[1] && y>=ry0 && y<=ry1 && ry1>ry0 && re<=rdy && re>=-rdy
                    && (rk!=2 || y[3]);
    wire [11:0] center_sum={1'b0,lx1}+{1'b0,rx1};
    wire [10:0] center=center_sum[11:1];
    wire center_tick=flags[2] && y>=V_ACTIVE-40 && y<V_ACTIVE-24
                     && x>=center && x<=center+1;
    wire camera_tick=flags[2] && y>=V_ACTIVE-20 && y<V_ACTIVE-8
                     && x>=H_ACTIVE/2 && x<=H_ACTIVE/2+1;

    function [7:0] kind_char;
        input valid;
        input [1:0] kind;
        begin kind_char=!valid ? "-" : (kind==1 ? "S" : (kind==2 ? "D" : "?")); end
    endfunction
    function [7:0] hex_char;
        input [3:0] value;
        begin hex_char=value<10 ? "0"+value : "A"+value-10; end
    endfunction
    reg [7:0] ch;
    wire hud=x>=64 && x<424 && y>=16 && y<48;
    wire [10:0] hx=x-64,hy=y-16;
    wire [5:0] text_col=hx/12;
    wire [2:0] gx=(hx%12)>>1,gy=hy[3:1];
    always @* begin
        ch=" ";
        if(!hy[4]) begin
            case(text_col)
                0:ch="L"; 1:ch=":"; 2:ch=kind_char(flags[0],lk);
                4:ch="R"; 5:ch=":"; 6:ch=kind_char(flags[1],rk);
                8:ch="O"; 9:ch="F"; 10:ch="F"; 11:ch=":";
                12:ch=!flags[2] ? "?" : (offset_px[15] ? "-" : "+");
                13:ch=!flags[2] ? "-" : "0"+decimal_value/100;
                14:ch=!flags[2] ? "-" : "0"+(decimal_value/10)%10;
                15:ch=!flags[2] ? "-" : "0"+decimal_value%10;
                17:ch="P"; 18:ch="X";
                20:ch="Z"; 21:ch=":"; 22:ch=flags[4] ? "1" : (flags[3] ? "?" : "0");
                24:ch="F"; 25:ch=":"; 26:ch=hex_char(shown[31:28]);
                27:ch=hex_char(shown[27:24]); 28:ch=hex_char(shown[23:20]); 29:ch=hex_char(shown[19:16]);
                default:ch=" ";
            endcase
        end else begin
            if(text_col<10) begin
                if(!flags[2]) begin
                    case(text_col) 0:ch="N"; 1:ch="O"; 3:ch="P"; 4:ch="A"; 5:ch="I"; 6:ch="R"; default:ch=" "; endcase
                end else if(warning!=0) begin
                    case(text_col)
                        0:ch="W"; 1:ch="A"; 2:ch="R"; 3:ch="N";
                        5:ch=warning==1 ? "L" : "R"; 6:ch=warning==1 ? "E" : "I";
                        7:ch=warning==1 ? "F" : "G"; 8:ch=warning==1 ? "T" : "H";
                        9:ch=warning==1 ? " " : "T"; default:ch=" ";
                    endcase
                end else begin
                    case(text_col) 0:ch="T"; 1:ch="R"; 2:ch="A"; 3:ch="C"; 4:ch="K"; 5:ch="I"; 6:ch="N"; 7:ch="G"; default:ch=" "; endcase
                end
            end else begin
                case(text_col)
                    15:ch="E"; 16:ch="X"; 17:ch="P"; 18:ch="E"; 19:ch="R";
                    20:ch="I"; 21:ch="M"; 22:ch="E"; 23:ch="N"; 24:ch="T";
                    default:ch=" ";
                endcase
            end
        end
    end
    function [34:0] glyph;
        input [7:0] c;
        begin
            case(c)
                "0":glyph={5'b01110,5'b10001,5'b10011,5'b10101,5'b11001,5'b10001,5'b01110};
                "1":glyph={5'b00100,5'b01100,5'b00100,5'b00100,5'b00100,5'b00100,5'b01110};
                "2":glyph={5'b01110,5'b10001,5'b00001,5'b00010,5'b00100,5'b01000,5'b11111};
                "3":glyph={5'b11110,5'b00001,5'b00001,5'b01110,5'b00001,5'b00001,5'b11110};
                "4":glyph={5'b00010,5'b00110,5'b01010,5'b10010,5'b11111,5'b00010,5'b00010};
                "5":glyph={5'b11111,5'b10000,5'b10000,5'b11110,5'b00001,5'b00001,5'b11110};
                "6":glyph={5'b01110,5'b10000,5'b10000,5'b11110,5'b10001,5'b10001,5'b01110};
                "7":glyph={5'b11111,5'b00001,5'b00010,5'b00100,5'b01000,5'b01000,5'b01000};
                "8":glyph={5'b01110,5'b10001,5'b10001,5'b01110,5'b10001,5'b10001,5'b01110};
                "9":glyph={5'b01110,5'b10001,5'b10001,5'b01111,5'b00001,5'b00001,5'b01110};
                "A":glyph={5'b01110,5'b10001,5'b10001,5'b11111,5'b10001,5'b10001,5'b10001};
                "B":glyph={5'b11110,5'b10001,5'b10001,5'b11110,5'b10001,5'b10001,5'b11110};
                "C":glyph={5'b01111,5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b01111};
                "D":glyph={5'b11110,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b11110};
                "E":glyph={5'b11111,5'b10000,5'b10000,5'b11110,5'b10000,5'b10000,5'b11111};
                "F":glyph={5'b11111,5'b10000,5'b10000,5'b11110,5'b10000,5'b10000,5'b10000};
                "G":glyph={5'b01111,5'b10000,5'b10000,5'b10111,5'b10001,5'b10001,5'b01111};
                "H":glyph={5'b10001,5'b10001,5'b10001,5'b11111,5'b10001,5'b10001,5'b10001};
                "I":glyph={5'b01110,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100,5'b01110};
                "K":glyph={5'b10001,5'b10010,5'b10100,5'b11000,5'b10100,5'b10010,5'b10001};
                "L":glyph={5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b11111};
                "M":glyph={5'b10001,5'b11011,5'b10101,5'b10101,5'b10001,5'b10001,5'b10001};
                "N":glyph={5'b10001,5'b11001,5'b10101,5'b10011,5'b10001,5'b10001,5'b10001};
                "O":glyph={5'b01110,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b01110};
                "P":glyph={5'b11110,5'b10001,5'b10001,5'b11110,5'b10000,5'b10000,5'b10000};
                "R":glyph={5'b11110,5'b10001,5'b10001,5'b11110,5'b10100,5'b10010,5'b10001};
                "S":glyph={5'b01111,5'b10000,5'b10000,5'b01110,5'b00001,5'b00001,5'b11110};
                "T":glyph={5'b11111,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100};
                "W":glyph={5'b10001,5'b10001,5'b10001,5'b10101,5'b10101,5'b10101,5'b01010};
                "X":glyph={5'b10001,5'b10001,5'b01010,5'b00100,5'b01010,5'b10001,5'b10001};
                "Z":glyph={5'b11111,5'b00001,5'b00010,5'b00100,5'b01000,5'b10000,5'b11111};
                ":":glyph={5'b00000,5'b00100,5'b00100,5'b00000,5'b00100,5'b00100,5'b00000};
                "+":glyph={5'b00000,5'b00100,5'b00100,5'b11111,5'b00100,5'b00100,5'b00000};
                "-":glyph={5'b00000,5'b00000,5'b00000,5'b11111,5'b00000,5'b00000,5'b00000};
                "?":glyph={5'b01110,5'b10001,5'b00001,5'b00010,5'b00100,5'b00000,5'b00100};
                default:glyph=0;
            endcase
        end
    endfunction
    wire [34:0] bits=glyph(ch);
    wire ink=hud && gx<5 && gy<7 && bits[34-gy*5-gx];
    wire [15:0] dim={1'b0,rgb_in[15:12],1'b0,rgb_in[10:6],1'b0,rgb_in[4:1]};
    wire [15:0] ink_color=warning!=0 && hy[4] && text_col<10 ? 16'hF800 : 16'hFFFF;
    assign rgb_out=!rst_n || !de || !enable ? rgb_in
                   : ink ? ink_color : hud ? dim
                   : left_line ? 16'h041F : right_line ? 16'hFD20
                   : (center_tick || camera_tick) ? 16'hFFFF : rgb_in;
endmodule
