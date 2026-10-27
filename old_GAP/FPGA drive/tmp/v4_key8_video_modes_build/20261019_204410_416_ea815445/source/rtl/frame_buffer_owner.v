`timescale 1ns/1ps

// Two existing DDR banks: publish completed frames, drop whole input frames
// while both banks are occupied, and pin the display bank until reads drain.
module frame_buffer_owner #(
    parameter H_NUM = 1280,
    parameter V_NUM = 720
) (
    input wire clk, rst_n,
    input wire video_clk, pipeline_running,
    input wire video_vs, video_de,
    input wire [31:0] video_id, video_time,
    input wire result_valid,
    input wire [31:0] result_id,
    input wire [7:0] result_errors,
    output wire writer_rst_n,
    output wire writer_vs, writer_de,
    input wire line_event, write_request, write_ready, write_done,
    output wire write_issue,
    output reg write_bank,
    input wire output_sof, read_request, read_ready, read_done,
    output wire read_issue,
    output reg read_bank, read_enabled,
    output reg has_frame,
    output wire [11:0] read_completed_gray,
    output reg [31:0] published_count, rejected_count,
    output reg [31:0] read_fault_count,
    output reg [31:0] display_id, display_time
);
    localparam RESET_WRITER=0, CAPTURE=1, DRAIN=2, WAIT_BANK=3;
    reg [1:0] state;
    reg [5:0] reset_count, settle_count;
    reg grant;
    reg writer_release;
    reg pending, pending_bank, have_reader;
    reg [31:0] pending_id, pending_time;
    reg write_busy, write_bad, read_busy;
    reg [11:0] issued_lines, completed_lines, read_lines;
    // Never derive an asynchronous RAM reset from a multi-bit state decode.
    assign writer_rst_n = rst_n && writer_release;
    assign write_issue = state == CAPTURE && !write_bad && !write_busy
        && write_request && write_ready;
    assign read_issue = read_enabled && !read_busy && !output_sof
        && read_request && read_ready;
    assign read_completed_gray = (read_lines >> 1) ^ read_lines;

    reg [1:0] grant_v;
    reg used_grant, active, vs_d, de_d, clean_bad;
    reg [15:0] columns, rows;
    reg [31:0] active_id, active_time, verdict_id;
    reg verdict_valid;
    reg [7:0] verdict_errors;
    reg end_toggle;
    reg end_good;
    reg [31:0] end_id, end_time;
    wire sof = video_vs && !vs_d;
    wire accept = sof && !active && grant_v[1] != used_grant
        && pipeline_running;
    wire matching_result = result_valid && result_id == active_id;
    wire saved_result = verdict_valid && verdict_id == active_id;
    wire [7:0] active_errors = matching_result ? result_errors : verdict_errors;
    wire geometry_done = rows == V_NUM && columns == 0 && !de_d;
    assign writer_vs = accept;
    assign writer_de = active && pipeline_running && !video_vs && video_de;

    // One bundled end descriptor per grant, held until a later grant.
    always @(posedge video_clk or negedge rst_n) begin
        if (!rst_n) begin
            grant_v <= 0; used_grant <= 0; active <= 0;
            vs_d <= 0; de_d <= 0; clean_bad <= 0;
            columns <= 0; rows <= 0; active_id <= 0; active_time <= 0;
            verdict_valid <= 0; verdict_id <= 0; verdict_errors <= 0;
            end_toggle <= 0; end_good <= 0; end_id <= 0; end_time <= 0;
        end else begin
            grant_v <= {grant_v[0], grant};
            vs_d <= video_vs;
            de_d <= writer_de;
            if (result_valid) begin
                verdict_valid <= 1; verdict_id <= result_id;
                verdict_errors <= result_errors;
            end
            if (accept) begin
                used_grant <= grant_v[1]; active <= 1;
                active_id <= video_id; active_time <= video_time;
                columns <= 0; rows <= 0; clean_bad <= video_de;
            end else if (active) begin
                if (writer_de) columns <= columns + 1'b1;
                if (de_d && !writer_de) begin
                    columns <= 0; rows <= rows + 1'b1;
                    if (columns != H_NUM || rows >= V_NUM) clean_bad <= 1;
                end
                if (!pipeline_running || sof ||
                    ((matching_result || saved_result) &&
                     (active_errors != 0 || geometry_done || clean_bad))) begin
                    end_good <= pipeline_running && !sof && !clean_bad
                        && geometry_done && active_errors == 0;
                    end_id <= active_id; end_time <= active_time;
                    end_toggle <= ~end_toggle; active <= 0;
                end
            end
        end
    end

    reg [1:0] end_sync;
    reg end_seen, captured_good;
    reg [31:0] captured_id, captured_time;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            end_sync <= 0; end_seen <= 0;
            state <= RESET_WRITER; reset_count <= 0; settle_count <= 0;
            grant <= 0; writer_release <= 0; write_bank <= 0;
            pending <= 0; pending_bank <= 0; have_reader <= 0;
            pending_id <= 0; pending_time <= 0;
            read_bank <= 0; read_enabled <= 0; has_frame <= 0;
            write_busy <= 0; write_bad <= 0; read_busy <= 0;
            issued_lines <= 0; completed_lines <= 0; read_lines <= 0;
            captured_good <= 0; captured_id <= 0; captured_time <= 0;
            published_count <= 0; rejected_count <= 0; read_fault_count <= 0;
            display_id <= 0; display_time <= 0;
        end else begin
            end_sync <= {end_sync[0], end_toggle};
            if (write_issue) begin
                write_busy <= 1; issued_lines <= issued_lines + 1'b1;
            end
            if (write_done && write_busy) begin
                write_busy <= 0; completed_lines <= completed_lines + 1'b1;
            end
            if (state == CAPTURE && line_event &&
                (write_busy || write_request || issued_lines >= V_NUM))
                write_bad <= 1;
            if (read_issue) read_busy <= 1;
            if (read_done && read_busy) begin
                read_busy <= 0; read_lines <= read_lines + 1'b1;
            end
            if (output_sof) begin
                read_lines <= 0;
                // No release/swap while a native command still references it.
                if (read_busy) begin
                    read_enabled <= 0;
                    read_fault_count <= read_fault_count + 1'b1;
                end else begin
                    if (pending) begin
                        read_bank <= pending_bank; have_reader <= 1;
                        display_id <= pending_id; display_time <= pending_time;
                        pending <= 0;
                    end
                    read_enabled <= pending || have_reader;
                end
            end else if (read_request && read_enabled && (read_busy || !read_ready)) begin
                read_enabled <= 0;
                read_fault_count <= read_fault_count + 1'b1;
            end
            case (state)
                RESET_WRITER: begin
                    if (reset_count == 31) begin
                        state <= CAPTURE; grant <= ~grant; writer_release <= 1;
                    end else reset_count <= reset_count + 1'b1;
                end
                CAPTURE: if (end_sync[1] != end_seen) begin
                    end_seen <= end_sync[1]; state <= DRAIN; settle_count <= 0;
                    captured_good <= end_good;
                    captured_id <= end_id; captured_time <= end_time;
                end
                DRAIN: begin
                    if (settle_count != 31) settle_count <= settle_count + 1'b1;
                    else if (!write_busy) begin
                        if (captured_good && !write_bad &&
                            issued_lines == V_NUM && completed_lines == V_NUM) begin
                            pending <= 1; pending_bank <= write_bank; has_frame <= 1;
                            pending_id <= captured_id; pending_time <= captured_time;
                            published_count <= published_count + 1'b1;
                        end else rejected_count <= rejected_count + 1'b1;
                        state <= WAIT_BANK;
                    end
                end
                WAIT_BANK: if (!pending) begin
                    write_bank <= have_reader ? !read_bank : 1'b0;
                    state <= RESET_WRITER; reset_count <= 0; writer_release <= 0;
                    write_bad <= 0; issued_lines <= 0; completed_lines <= 0;
                end
            endcase
        end
    end
endmodule
