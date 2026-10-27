`timescale 1ns/1ps
// Status panel only: no geometric claim that a candidate matches the displayed frame.
module lane_change_overlay #(
    parameter H_ACTIVE = 1280,
    parameter V_ACTIVE = 720
) (
    input clk, rst_n, de, vs,
    input [15:0] rgb_in,
    input test_mode, fresh, alarm,
    input [1:0] decision, requested_direction, effective_direction,
    input [15:0] source_frame,
    output [15:0] rgb_out
);
    localparam PANEL_X = H_ACTIVE-320;
    reg vs_d, de_d;
    reg [10:0] x, y;
    reg shown_test, shown_fresh, shown_alarm;
    reg [1:0] shown_decision, shown_request, shown_effective;
    reg [15:0] shown_frame;
    always @(posedge clk) begin
        if (!rst_n) begin
            vs_d <= 0; de_d <= 0; x <= 0; y <= 0;
            shown_test <= 0; shown_fresh <= 0; shown_alarm <= 0;
            shown_decision <= 0; shown_request <= 0; shown_effective <= 0; shown_frame <= 0;
        end else begin
            vs_d <= vs; de_d <= de;
            if (vs && !vs_d) begin
                x <= 0; y <= 0;
                shown_test <= test_mode; shown_fresh <= fresh; shown_alarm <= alarm;
                shown_decision <= decision; shown_request <= requested_direction;
                shown_effective <= effective_direction; shown_frame <= source_frame;
            end else if (de_d && !de) begin x <= 0; y <= y == V_ACTIVE-1 ? 11'd0 : y+1'b1; end
            else if (de) x <= x+1'b1;
        end
    end
    wire panel = x >= PANEL_X && x < PANEL_X+304 && y >= 16 && y < 64;
    wire [10:0] px = x-PANEL_X, py = y-16;
    wire [4:0] col = px/12;
    wire [1:0] row = py/16;
    wire [2:0] gx = (px%12)>>1, gy = py[3:1];
    reg [7:0] ch;
    function [7:0] hex_char;
        input [3:0] value;
        begin hex_char = value < 10 ? "0"+value : "A"+value-10; end
    endfunction
    always @* begin
        ch = " ";
        if (row == 0) begin
            if (shown_test) begin
                case (col)
                    0:ch="R"; 1:ch="U"; 2:ch="L"; 3:ch="E";
                    5:ch="T"; 6:ch="E"; 7:ch="S"; 8:ch="T";
                endcase
            end else begin
                case (col)
                    0:ch="L"; 1:ch="O"; 2:ch="C"; 3:ch="A"; 4:ch="L";
                    6:ch="C"; 7:ch="A"; 8:ch="N"; 9:ch="D"; 10:ch="I";
                    11:ch="D"; 12:ch="A"; 13:ch="T"; 14:ch="E";
                endcase
            end
        end else if (row == 1) begin
            if (!shown_fresh || shown_decision == 0) begin
                case (col) 0:ch="U"; 1:ch="N"; 2:ch="K"; 3:ch="N"; 4:ch="O"; 5:ch="W"; 6:ch="N"; endcase
            end else if (shown_alarm) begin
                case (col) 0:ch="S"; 1:ch="O"; 2:ch="L"; 3:ch="I"; 4:ch="D";
                    6:ch="A"; 7:ch="L"; 8:ch="A"; 9:ch="R"; 10:ch="M"; endcase
            end else case (shown_decision)
                1:case (col) 0:ch="S"; 1:ch="T"; 2:ch="R"; 3:ch="A"; 4:ch="I"; 5:ch="G"; 6:ch="H"; 7:ch="T"; endcase
                2:case (col) 0:ch="D"; 1:ch="A"; 2:ch="S"; 3:ch="H"; 4:ch="E"; 5:ch="D";
                    7:ch="R"; 8:ch="E"; 9:ch="Q"; endcase
                3:case (col) 0:ch="B"; 1:ch="L"; 2:ch="O"; 3:ch="C"; 4:ch="K"; 5:ch="E"; 6:ch="D"; endcase
            endcase
        end else if (row == 2) begin
            case (col)
                0:ch="F"; 1:ch=":"; 2:ch=hex_char(shown_frame[15:12]);
                3:ch=hex_char(shown_frame[11:8]); 4:ch=hex_char(shown_frame[7:4]); 5:ch=hex_char(shown_frame[3:0]);
                7:ch="R"; 8:ch="E"; 9:ch="Q"; 10:ch=":";
                11:ch=shown_request==1 ? "L" : (shown_request==2 ? "R" : "-");
            endcase
        end
    end
    function [34:0] glyph;
        input [7:0] c;
        begin
            case (c)
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
                "Q":glyph={5'b01110,5'b10001,5'b10001,5'b10001,5'b10101,5'b10010,5'b01101};
                "R":glyph={5'b11110,5'b10001,5'b10001,5'b11110,5'b10100,5'b10010,5'b10001};
                "S":glyph={5'b01111,5'b10000,5'b10000,5'b01110,5'b00001,5'b00001,5'b11110};
                "T":glyph={5'b11111,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100};
                "U":glyph={5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b01110};
                "W":glyph={5'b10001,5'b10001,5'b10001,5'b10101,5'b10101,5'b10101,5'b01010};
                ":":glyph={5'b00000,5'b00100,5'b00100,5'b00000,5'b00100,5'b00100,5'b00000};
                "-":glyph={5'b00000,5'b00000,5'b00000,5'b11111,5'b00000,5'b00000,5'b00000};
                default:glyph=0;
            endcase
        end
    endfunction
    wire [34:0] bits = glyph(ch);
    wire ink = panel && px < 240 && gx < 5 && gy < 7 && bits[34-gy*5-gx];
    wire [1:0] arrow_dir = shown_decision == 3 ? shown_request : shown_effective;
    wire vertical_arrow = arrow_dir == 0 &&
        ((px >= 264 && px < 272 && py >= 20 && py < 40) ||
         (py >= 8 && py < 22 && px >= 268-(py-8) && px <= 268+(py-8)));
    wire left_arrow = arrow_dir == 1 &&
        ((px >= 260 && px < 288 && py >= 20 && py < 28) ||
         (px >= 248 && px < 264 && py >= 24-(px-248) && py <= 24+(px-248)));
    wire right_arrow = arrow_dir == 2 &&
        ((px >= 248 && px < 276 && py >= 20 && py < 28) ||
         (px >= 272 && px < 288 && py >= 24-(287-px) && py <= 24+(287-px)));
    wire arrow = panel && shown_fresh && shown_decision != 0 &&
        (vertical_arrow || left_arrow || right_arrow);
    wire [15:0] color = shown_alarm ? 16'hf800 :
        shown_decision == 3 ? 16'hfd20 : shown_decision == 2 ? 16'hffe0 : 16'hffff;
    wire border = panel && shown_alarm && (py == 0 || py == 47 || px == 0 || px == 303);
    wire [15:0] dim = {1'b0,rgb_in[15:12],1'b0,rgb_in[10:6],1'b0,rgb_in[4:1]};
    assign rgb_out = !rst_n || !de || !panel ? rgb_in :
        border || arrow ? color : ink ? (row == 1 ? color : 16'hffff) : dim;
endmodule
