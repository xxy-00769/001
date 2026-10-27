`timescale 1ns/1ps

// Observes the normalized source tuple, before img_proc can reshape bad rows.
// A report closes at the NEXT VS rising edge; it is NOT a DDR commit record.
module video_capture_status #(
    parameter H_ACTIVE = 1280,
    parameter V_ACTIVE = 720,
    parameter SOURCE_ID = 0,
    parameter REF_HZ = 50000000,
    parameter TIMEOUT_MS = 250,
    parameter CHECK_BYTE_ERRORS = 0
) (
    input wire ref_clk,
    input wire video_clk,
    input wire rst_n,
    input wire source_ready,
    input wire video_vs,
    input wire video_de,
    input wire byte_frame_error,
    output wire pipeline_rst_n,
    output reg healthy,
    output reg timed_out,
    output reg [31:0] timeout_count,
    output reg snapshot_valid,
    output reg [255:0] snapshot,
    output wire [31:0] frame_open_id,
    output wire [31:0] frame_open_time,
    output reg frame_result_valid,
    output reg [31:0] frame_result_id,
    output reg [7:0] frame_result_errors
);
    localparam TICK_CYCLES = REF_HZ / 1000;
    localparam [7:0] SOURCE_TAG = SOURCE_ID;
    reg [31:0] tick_count, milliseconds, milliseconds_gray;
    reg [1:0] ready_ref;
    wire ms_tick = tick_count == TICK_CYCLES-1;
    wire [31:0] next_ms = milliseconds + 1'b1;
    always @(posedge ref_clk or negedge rst_n) begin
        if (!rst_n) begin
            tick_count <= 0;
            milliseconds <= 0;
            milliseconds_gray <= 0;
            ready_ref <= 0;
        end else begin
            ready_ref <= {ready_ref[0], source_ready};
            if (ms_tick) begin
                tick_count <= 0;
                milliseconds <= next_ms;
                milliseconds_gray <= (next_ms >> 1) ^ next_ms;
            end else tick_count <= tick_count + 1'b1;
        end
    end

    function [31:0] gray_to_binary;
        input [31:0] gray;
        integer i;
        begin
            gray_to_binary[31] = gray[31];
            for (i=30; i>=0; i=i-1)
                gray_to_binary[i] = gray_to_binary[i+1] ^ gray[i];
        end
    endfunction
    reg [31:0] time_v1, time_v2;
    reg [1:0] ready_video, timeout_video;
    reg ack_v1, ack_v2;
    reg request, acknowledge;
    reg [255:0] mailbox;
    always @(posedge video_clk or negedge rst_n) begin
        if (!rst_n) begin
            time_v1 <= 0; time_v2 <= 0;
            ready_video <= 0; timeout_video <= 0;
            ack_v1 <= 0; ack_v2 <= 0;
        end else begin
            time_v1 <= milliseconds_gray;
            time_v2 <= time_v1;
            ready_video <= {ready_video[0], source_ready};
            timeout_video <= {timeout_video[0], timed_out};
            ack_v1 <= acknowledge;
            ack_v2 <= ack_v1;
        end
    end

    reg vs_d, de_d, have_frame;
    reg [31:0] frame_id, frame_time, pixels;
    reg [15:0] columns, rows;
    reg [7:0] errors;
    reg [31:0] good_frames, bad_frames, mailbox_drops;
    wire sof = video_vs && !vs_d;
    wire close_line = de_d && (!video_de || video_vs);
    wire [16:0] final_rows = {1'b0, rows} + (de_d ? 17'd1 : 17'd0);
    wire [15:0] reported_rows = final_rows[16] ? 16'hffff : final_rows[15:0];
    wire [7:0] final_errors = errors
        | ((de_d && columns != H_ACTIVE) ? 8'h01 : 8'h00)
        | ((final_rows != V_ACTIVE) ? 8'h02 : 8'h00)
        | (video_de ? 8'h04 : 8'h00)
        | (final_rows[16] ? 8'h08 : 8'h00)
        | (timeout_video[1] ? 8'h10 : 8'h00);
    wire [7:0] complete_errors=final_errors
        | ((CHECK_BYTE_ERRORS && byte_frame_error) ? 8'h20:8'h00);
    // Sample opening tags only on the input VS edge, in video_clk.
    assign frame_open_id = frame_id + (have_frame ? 32'd1 : 32'd0);
    assign frame_open_time = gray_to_binary(time_v2);

    always @(posedge video_clk or negedge rst_n) begin
        if (!rst_n) begin
            vs_d <= 0; de_d <= 0; have_frame <= 0;
            frame_id <= 0; frame_time <= 0; pixels <= 0;
            columns <= 0; rows <= 0; errors <= 0;
            good_frames <= 0; bad_frames <= 0; mailbox_drops <= 0;
            mailbox <= 0; request <= 0;
            frame_result_valid <= 0; frame_result_id <= 0; frame_result_errors <= 0;
        end else begin
            frame_result_valid <= 0;
            vs_d <= video_vs;
            de_d <= video_de && !video_vs && ready_video[1];
            if (!ready_video[1]) begin
                // Disable cancels the partial frame, but preserves counters,
                // IDs and an outstanding mailbox transaction.
                have_frame <= 0; de_d <= 0; vs_d <= 0;
                columns <= 0; rows <= 0; pixels <= 0; errors <= 0;
            end else if (sof) begin
                if (have_frame) begin
                    frame_result_valid <= 1;
                    frame_result_id <= frame_id;
                    frame_result_errors <= complete_errors;
                    if (complete_errors == 0) good_frames <= good_frames + 1'b1;
                    else bad_frames <= bad_frames + 1'b1;
                    if (request == ack_v2) begin
                        // Bundled data stays unchanged until the reference
                        // domain acknowledges the synchronized request.
                        mailbox <= {32'd0, mailbox_drops,
                            bad_frames + ((complete_errors != 0) ? 32'd1 : 32'd0),
                            good_frames + ((complete_errors == 0) ? 32'd1 : 32'd0),
                            SOURCE_TAG, complete_errors, reported_rows,
                            pixels, frame_time, frame_id};
                        request <= ~request;
                    end else mailbox_drops <= mailbox_drops + 1'b1;
                    frame_id <= frame_id + 1'b1;
                end
                have_frame <= 1;
                frame_time <= gray_to_binary(time_v2);
                pixels <= 0; columns <= 0; rows <= 0;
                errors <= video_de ? 8'h04 : 8'h00;
            end else if (have_frame) begin
                if (timeout_video[1]) errors[4] <= 1;
                if (video_vs && video_de) errors[2] <= 1;
                if (video_de && !video_vs) begin
                    if (&pixels) errors[3] <= 1;
                    else pixels <= pixels + 1'b1;
                    if (&columns) errors[3] <= 1;
                    else columns <= columns + 1'b1;
                end
                if (close_line) begin
                    if (columns != H_ACTIVE) errors[0] <= 1;
                    if (&rows) errors[3] <= 1;
                    else rows <= rows + 1'b1;
                    columns <= 0;
                end
            end
        end
    end

    reg req_r1, req_r2;
    reg [31:0] silence_ms;
    always @(posedge ref_clk or negedge rst_n) begin
        if (!rst_n) begin
            req_r1 <= 0; req_r2 <= 0; acknowledge <= 0;
            healthy <= 0; timed_out <= 0; timeout_count <= 0;
            silence_ms <= 0; snapshot_valid <= 0; snapshot <= 0;
        end else begin
            req_r1 <= request;
            req_r2 <= req_r1;
            snapshot_valid <= 0;
            if (!ready_ref[1]) begin
                healthy <= 0;
                timed_out <= 0;
                silence_ms <= 0;
                // Drain old reports while disabled; never advertise them as
                // a healthy frame after re-enabling the source.
                acknowledge <= req_r2;
            end else if (req_r2 != acknowledge) begin
                snapshot <= mailbox;
                snapshot_valid <= 1;
                acknowledge <= req_r2;
                healthy <= mailbox[119:112] == 0;
                timed_out <= 0;
                silence_ms <= 0;
            end else if (ms_tick && !timed_out) begin
                if (silence_ms == TIMEOUT_MS-1) begin
                    timed_out <= 1;
                    healthy <= 0;
                    timeout_count <= timeout_count + 1'b1;
                end else silence_ms <= silence_ms + 1'b1;
            end
        end
    end

    // The watchdog runs from ref_clk, including when video_clk is stopped.
    // Only the processing pipeline is reset: monitoring must remain alive to
    // observe a returning source. Release is synchronous to video_clk.
    wire permit_pipeline = rst_n && source_ready && !timed_out;
    reg [1:0] pipeline_release;
    always @(posedge video_clk or negedge permit_pipeline) begin
        if (!permit_pipeline) pipeline_release <= 0;
        else pipeline_release <= {pipeline_release[0], 1'b1};
    end
    assign pipeline_rst_n = pipeline_release[1];
endmodule

// Keeps HDMI timing running. Black while unhealthy; resume on the second
// output VS edge after health returns. This is a display guard, not DDR
// bank ownership or proof that an entire frame has been committed.
module video_present_guard (
    input wire clk,
    input wire rst_n,
    input wire healthy,
    input wire vs,
    output reg show_video
);
    reg [1:0] health_sync;
    reg vs_d, first_boundary;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            health_sync <= 0; vs_d <= 0;
            first_boundary <= 0; show_video <= 0;
        end else begin
            health_sync <= {health_sync[0], healthy};
            vs_d <= vs;
            if (!health_sync[1]) begin
                first_boundary <= 0; show_video <= 0;
            end else if (vs && !vs_d) begin
                first_boundary <= 1;
                if (first_boundary) show_video <= 1;
            end
        end
    end
endmodule
