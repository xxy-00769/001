`timescale 1ns/1ps
module lane_button_events #(
    parameter STABLE_CYCLES = 371250
) (
    input clk, rst_n,
    input [3:0] key_n,
    output reg [3:0] pressed
);
    localparam CW = STABLE_CYCLES < 2 ? 1 : $clog2(STABLE_CYCLES + 1);
    reg [3:0] meta, synced, stable, armed;
    reg [1:0] sync_ready;
    reg [CW-1:0] count [0:3];
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            meta <= 4'hf; synced <= 4'hf; stable <= 4'hf;
            armed <= 0; pressed <= 0; sync_ready <= 0;
            for (i=0; i<4; i=i+1) count[i] <= 0;
        end else begin
            meta <= key_n; synced <= meta; pressed <= 0;
            sync_ready <= {sync_ready[0],1'b1};
            for (i=0; i<4; i=i+1) begin
                if (!sync_ready[1]) count[i] <= 0;
                else if (synced[i] != stable[i]) begin
                    if (count[i] == STABLE_CYCLES-1) begin
                        count[i] <= 0;
                        stable[i] <= synced[i];
                        if (synced[i]) armed[i] <= 1;
                        else begin pressed[i] <= armed[i]; armed[i] <= 0; end
                    end else count[i] <= count[i] + 1'b1;
                end else if (synced[i] && !armed[i]) begin
                    if (count[i] == STABLE_CYCLES-1) begin
                        count[i] <= 0; armed[i] <= 1;
                    end else count[i] <= count[i] + 1'b1;
                end else count[i] <= 0;
            end
        end
    end
endmodule
