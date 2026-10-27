`timescale 1ns/1ps
module lane_local_ui #(
    parameter H_ACTIVE = 1280,
    parameter V_ACTIVE = 720,
    parameter RULE_TEST = 0,
    parameter DEBOUNCE_CYCLES = 371250,
    parameter STALE_CYCLES = 18562500,
    parameter COMMAND_CYCLES = 74250000,
    parameter TEST_FRAMES = 120
) (
    input reset_n, src_clk, src_valid,
    input [255:0] src_snapshot,
    input pix_clk, de, vs,
    input [3:0] key_n,
    input [15:0] rgb_in,
    output [15:0] rgb_out,
    output [1:0] requested_direction, effective_direction, decision,
    output fresh, alarm,
    output [15:0] source_frame, dropped_snapshots, rejected_results
);
    reg [1:0] release_sync;
    reg vs_d;
    always @(posedge pix_clk or negedge reset_n)
        if (!reset_n) release_sync <= 0;
        else release_sync <= {release_sync[0],1'b1};
    wire rst_n = release_sync[1];
    always @(posedge pix_clk) if (!rst_n) vs_d <= 0; else vs_d <= vs;
    wire result_valid;
    wire [255:0] snapshot;
    generate if (RULE_TEST) begin : g_rule_test
        assign dropped_snapshots = 0;
        lane_rule_test_source #(.FRAMES_PER_SCENE(TEST_FRAMES)) test_source (
            .clk(pix_clk),.rst_n(rst_n),.frame_start(vs && !vs_d),
            .valid(result_valid),.snapshot(snapshot)
        );
    end else begin : g_camera
        lane_snapshot_cdc mailbox (
            .reset_n(reset_n),.src_clk(src_clk),.src_valid(src_valid),.src_snapshot(src_snapshot),
            .src_busy(),.dropped(dropped_snapshots),.dst_clk(pix_clk),
            .dst_valid(result_valid),.dst_snapshot(snapshot)
        );
    end endgenerate
    wire [3:0] pressed;
    lane_button_events #(.STABLE_CYCLES(DEBOUNCE_CYCLES)) keys (
        .clk(pix_clk),.rst_n(rst_n),.key_n(key_n),.pressed(pressed)
    );
    lane_change_control #(.STALE_CYCLES(STALE_CYCLES),.COMMAND_CYCLES(COMMAND_CYCLES)) control (
        .clk(pix_clk),.rst_n(rst_n),.result_valid(result_valid),.snapshot(snapshot),.pressed(pressed),
        .fresh(fresh),.requested_direction(requested_direction),.effective_direction(effective_direction),
        .decision(decision),.alarm(alarm),.source_frame(source_frame),.rejected_results(rejected_results)
    );
    lane_change_overlay #(.H_ACTIVE(H_ACTIVE),.V_ACTIVE(V_ACTIVE)) overlay (
        .clk(pix_clk),.rst_n(rst_n),.de(de),.vs(vs),.rgb_in(rgb_in),.test_mode(RULE_TEST != 0),
        .fresh(fresh),.alarm(alarm),.decision(decision),.requested_direction(requested_direction),
        .effective_direction(effective_direction),.source_frame(source_frame),.rgb_out(rgb_out)
    );
endmodule
