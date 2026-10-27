`timescale 1ns/1ps
// Four-phase mailbox: the multi-bit payload stays fixed until acknowledgement.
// Both domains must share reset assertion; samples while busy are counted/dropped.
module lane_snapshot_cdc (
    input reset_n, src_clk, src_valid,
    input [255:0] src_snapshot,
    output src_busy,
    output reg [15:0] dropped,
    input dst_clk,
    output reg dst_valid,
    output reg [255:0] dst_snapshot
);
    reg [1:0] src_release, dst_release;
    reg req, ack, ack_meta, ack_sync, req_meta, req_sync /* synthesis syn_preserve = 1 */;
    reg [255:0] held /* synthesis syn_preserve = 1 */;
    always @(posedge src_clk or negedge reset_n)
        if (!reset_n) src_release <= 0;
        else src_release <= {src_release[0],1'b1};
    always @(posedge dst_clk or negedge reset_n)
        if (!reset_n) dst_release <= 0;
        else dst_release <= {dst_release[0],1'b1};
    assign src_busy = req || ack_sync || !src_release[1];
    always @(posedge src_clk or negedge reset_n) begin
        if (!reset_n) begin
            req <= 0; ack_meta <= 0; ack_sync <= 0; held <= 0; dropped <= 0;
        end else if (!src_release[1]) begin
            req <= 0; ack_meta <= 0; ack_sync <= 0; held <= 0; dropped <= 0;
        end else begin
            ack_meta <= ack; ack_sync <= ack_meta;
            if (req && ack_sync) req <= 0;
            if (src_valid) begin
                if (!src_busy) begin held <= src_snapshot; req <= 1; end
                else if (dropped != 16'hffff) dropped <= dropped + 1'b1;
            end
        end
    end
    always @(posedge dst_clk or negedge reset_n) begin
        if (!reset_n) begin
            req_meta <= 0; req_sync <= 0; ack <= 0;
            dst_valid <= 0; dst_snapshot <= 0;
        end else if (!dst_release[1]) begin
            req_meta <= 0; req_sync <= 0; ack <= 0;
            dst_valid <= 0; dst_snapshot <= 0;
        end else begin
            req_meta <= req; req_sync <= req_meta; dst_valid <= 0;
            if (req_sync && !ack) begin
                dst_snapshot <= held; dst_valid <= 1; ack <= 1;
            end else if (!req_sync) ack <= 0;
        end
    end
endmodule
