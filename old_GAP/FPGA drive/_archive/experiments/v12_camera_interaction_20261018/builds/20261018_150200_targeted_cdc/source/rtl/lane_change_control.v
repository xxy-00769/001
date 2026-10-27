`timescale 1ns/1ps
// Local rule demonstration only. Dashed means a request, never a safety verdict.
module lane_change_control #(
    parameter STALE_CYCLES = 18562500,
    parameter COMMAND_CYCLES = 74250000
) (
    input clk, rst_n, result_valid,
    input [255:0] snapshot,
    input [3:0] pressed,
    output fresh,
    output reg [1:0] requested_direction,
    output reg [1:0] effective_direction,
    output reg [1:0] decision,
    output reg alarm,
    output reg [15:0] source_frame,
    output reg [15:0] rejected_results
);
    localparam AW = STALE_CYCLES < 2 ? 1 : $clog2(STALE_CYCLES + 1);
    localparam CW = COMMAND_CYCLES < 2 ? 1 : $clog2(COMMAND_CYCLES + 1);
    reg [AW-1:0] age;
    reg [CW-1:0] command_age;
    reg have_result, seen_frame, result_good, forced;
    reg [1:0] left_kind, right_kind;
    wire [15:0] delta = snapshot[31:16] - source_frame;
    wire accept_result = result_valid &&
        (!seen_frame || (delta != 0 && !delta[15]));
    wire new_good = snapshot[2:0] == 3'b111 && !snapshot[5] &&
        (snapshot[9:8] == 1 || snapshot[9:8] == 2) &&
        (snapshot[11:10] == 1 || snapshot[11:10] == 2);
    wire usable_now = accept_result ? new_good :
        (have_result && result_good && age < STALE_CYCLES-1);
    wire [1:0] selected_kind = requested_direction == 1 ? left_kind : right_kind;
    assign fresh = have_result && result_good && age < STALE_CYCLES;

    always @(posedge clk) begin
        if (!rst_n) begin
            age <= 0; have_result <= 0; seen_frame <= 0; result_good <= 0; forced <= 0;
            command_age <= 0; requested_direction <= 0; source_frame <= 0;
            left_kind <= 0; right_kind <= 0; rejected_results <= 0;
        end else begin
            if (age < STALE_CYCLES) age <= age + 1'b1;
            if (age >= STALE_CYCLES-1) have_result <= 0;
            if (accept_result) begin
                age <= 0; have_result <= 1; seen_frame <= 1; result_good <= new_good;
                source_frame <= snapshot[31:16];
                left_kind <= snapshot[9:8]; right_kind <= snapshot[11:10];
            end else if (result_valid && rejected_results != 16'hffff)
                rejected_results <= rejected_results + 1'b1;

            if (!usable_now || pressed[3] || (pressed[0] && pressed[1])) begin
                requested_direction <= 0; forced <= 0; command_age <= 0;
            end else if (pressed[0] || pressed[1]) begin
                requested_direction <= pressed[0] ? 2'd1 : 2'd2;
                forced <= pressed[2]; command_age <= 0;
            end else if (pressed[2] && requested_direction != 0) begin
                forced <= 1; command_age <= 0;
            end else if (requested_direction != 0) begin
                if (command_age >= COMMAND_CYCLES-1) begin
                    requested_direction <= 0; forced <= 0; command_age <= 0;
                end else command_age <= command_age + 1'b1;
            end
        end
    end
    always @* begin
        effective_direction = 0; decision = 0; alarm = 0;
        if (fresh) begin
            if (requested_direction == 0) decision = 1;
            else if (selected_kind == 2) begin
                decision = 2; effective_direction = requested_direction;
            end else if (selected_kind == 1) begin
                decision = 3; alarm = forced;
            end
        end
    end
endmodule
