`timescale 1ns/1ps
// Single-key adaptation of the archived v11 release/repress debounce behavior.
module video_mode_key #(
    parameter STABLE_CYCLES = 1000000 // 20 ms at the board's 50 MHz reference
) (
    input ref_clk, video_clk,
    input rst_n, video_rst_n,
    input key_n,
    output reg [2:0] requested_mode
);
    localparam CW = STABLE_CYCLES < 2 ? 1 : $clog2(STABLE_CYCLES + 1);
    reg meta, synced, stable, armed;
    reg [1:0] sync_ready;
    reg [CW-1:0] count;
    // The CDC relies on this exact six-state Gray ring, not FSM recoding.
    reg [2:0] mode_gray /* synthesis syn_encoding = "original" */;
    always @(posedge ref_clk or negedge rst_n) begin
        if (!rst_n) begin
            meta <= 1; synced <= 1; stable <= 1; armed <= 0;
            sync_ready <= 0; count <= 0; mode_gray <= 0;
        end else begin
            meta <= key_n;
            synced <= meta;
            sync_ready <= {sync_ready[0], 1'b1};
            if (!sync_ready[1]) count <= 0;
            else if (synced != stable) begin
                if (count == STABLE_CYCLES-1) begin
                    count <= 0;
                    stable <= synced;
                    if (synced) armed <= 1;
                    else begin
                        armed <= 0;
                        // A six-state Gray ring: every press, including wrap,
                        // changes exactly one bit at the CDC source register.
                        if (armed) case (mode_gray)
                            3'b000: mode_gray <= 3'b001;
                            3'b001: mode_gray <= 3'b011;
                            3'b011: mode_gray <= 3'b010;
                            3'b010: mode_gray <= 3'b110;
                            3'b110: mode_gray <= 3'b100;
                            default: mode_gray <= 3'b000;
                        endcase
                    end
                end else count <= count + 1'b1;
            end else if (synced && !armed) begin
                if (count == STABLE_CYCLES-1) begin
                    count <= 0;
                    armed <= 1;
                end else count <= count + 1'b1;
            end else count <= 0;
        end
    end

    reg [2:0] gray_meta, gray_sync;
    always @(posedge video_clk or negedge video_rst_n) begin
        if (!video_rst_n) begin
            gray_meta <= 0;
            gray_sync <= 0;
        end else begin
            gray_meta <= mode_gray;
            gray_sync <= gray_meta;
        end
    end
    always @* begin
        case (gray_sync)
            3'b001: requested_mode = 1;
            3'b011: requested_mode = 2;
            3'b010: requested_mode = 3;
            3'b110: requested_mode = 4;
            3'b100: requested_mode = 5;
            default: requested_mode = 0;
        endcase
    end
endmodule
