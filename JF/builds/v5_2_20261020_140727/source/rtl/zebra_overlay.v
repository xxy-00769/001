`timescale 1ns / 1ps
// Freeze result geometry for a whole output frame; never fill the road region.
// Icon: grey=no candidate, amber=one frame, magenta=two-frame confirmation.
module zebra_overlay #(
    parameter H_ACTIVE = 1280,
    parameter V_ACTIVE = 720
)(
    input clk, rst_n, de, vs, enable,
    input [15:0] rgb_in,
    input result_valid, candidate, confirmed,
    input [10:0] box_x0, box_y0, box_x1, box_y1,
    output [15:0] rgb_out
);
    reg vs_d, de_d;
    reg [10:0] x, y;
    reg [1:0] pending_state, show_state;
    reg [10:0] px0, px1, py0, py1, sx0, sx1, sy0, sy1;
    wire frame_start = vs && !vs_d;
    wire [1:0] incoming_state = confirmed ? 2'd2 : (candidate ? 2'd1 : 2'd0);
    always @(posedge clk) begin
        if (!rst_n) begin
            vs_d <= 0; de_d <= 0; x <= 0; y <= 0;
            pending_state <= 0; show_state <= 0;
            px0 <= 0; px1 <= 0; py0 <= 0; py1 <= 0;
            sx0 <= 0; sx1 <= 0; sy0 <= 0; sy1 <= 0;
        end else begin
            vs_d <= vs; de_d <= de;
            if (result_valid) begin
                pending_state <= incoming_state;
                px0 <= box_x0; px1 <= box_x1; py0 <= box_y0; py1 <= box_y1;
            end
            if (frame_start) begin
                x <= 0; y <= 0;
                show_state <= result_valid ? incoming_state : pending_state;
                sx0 <= result_valid ? box_x0 : px0; sx1 <= result_valid ? box_x1 : px1;
                sy0 <= result_valid ? box_y0 : py0; sy1 <= result_valid ? box_y1 : py1;
            end else if (de_d && !de) begin
                x <= 0; y <= y == V_ACTIVE-1 ? 11'd0 : y+1'b1;
            end else if (de) x <= x+1'b1;
        end
    end
    wire icon = x >= 16 && x < 48 && y >= 16 && y < 40 && x[2:0] < 4;
    wire box = show_state == 2 && x >= sx0 && x <= sx1 && y >= sy0 && y <= sy1
               && (x == sx0 || x == sx1 || y == sy0 || y == sy1);
    wire [15:0] status_color = show_state == 2 ? 16'hF81F : (show_state == 1 ? 16'hFD20 : 16'h8410);
    assign rgb_out = !rst_n || !de || !enable ? rgb_in
                     : (icon ? status_color : (box ? 16'hF81F : rgb_in));
endmodule
