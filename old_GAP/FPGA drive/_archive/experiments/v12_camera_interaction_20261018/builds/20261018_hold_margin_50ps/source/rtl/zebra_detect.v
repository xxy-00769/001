`timescale 1ns / 1ps
// Experimental longitudinal-bar crosswalk candidate detector, not road semantics.
// RGB must be unpainted. Results are published once per complete frame.
// Requires >=1 blank clock between rows and a VS pulse before active pixels.
module zebra_detect #(
    parameter H_ACTIVE = 1280,
    parameter V_ACTIVE = 720,
    parameter ROI_Y0 = V_ACTIVE/3,
    parameter ROI_X0 = H_ACTIVE/10,
    parameter ROI_X1 = H_ACTIVE*9/10,
    parameter WHITE_MIN = 144,
    parameter WHITE_SPREAD = 48,
    parameter DARK_MAX = 112,
    parameter MIN_WIDTH = 12,
    parameter MAX_WIDTH = 160,
    parameter MIN_GAP = 8,
    parameter MAX_GAP = 160,
    parameter MIN_STRIPES = 4,
    parameter MIN_SPAN = H_ACTIVE/5,
    parameter MIN_ROWS = 12,
    parameter ROW_DRIFT = 32
)(
    input clk, rst_n, de, vs,
    input [15:0] rgb_in,
    output reg result_valid,
    output reg candidate,
    output reg confirmed,
    output reg [10:0] box_x0, box_y0, box_x1, box_y1,
    output reg [4:0] stripes
);
    reg vs_d, de_d, active_frame, bad_frame;
    reg [10:0] x, y;
    wire frame_start = vs && !vs_d;
    wire row_end = de_d && !de;
    wire [7:0] r = {rgb_in[15:11], rgb_in[15:13]};
    wire [7:0] g = {rgb_in[10:5], rgb_in[10:9]};
    wire [7:0] b = {rgb_in[4:0], rgb_in[4:2]};
    wire [7:0] lo_rg = r < g ? r : g;
    wire [7:0] hi_rg = r > g ? r : g;
    wire [7:0] lo = lo_rg < b ? lo_rg : b;
    wire [7:0] hi = hi_rg > b ? hi_rg : b;
    wire in_roi = (y >= ROI_Y0) && (x >= ROI_X0) && (x < ROI_X1);
    wire white = in_roi && (lo >= WHITE_MIN) && (hi-lo <= WHITE_SPREAD);
    wire dark = in_roi && (hi <= DARK_MAX);

    reg [10:0] run_start, run_len, gap_len, dark_len;
    reg run_gap_ok;
    reg [10:0] seq_start, seq_width;
    reg [4:0] seq_count;
    reg line_hit;
    reg [10:0] line_x0, line_x1;
    reg [4:0] line_stripes;
    wire width_ok = run_len >= MIN_WIDTH && run_len <= MAX_WIDTH;
    wire similar_width = ({1'b0,run_len} <= ({1'b0,seq_width} << 1))
                         && ({1'b0,seq_width} <= ({1'b0,run_len} << 1));
    wire extend_seq = seq_count != 0 && run_gap_ok && similar_width;
    wire [4:0] next_count = extend_seq ? (seq_count == 31 ? 5'd31 : seq_count+1'b1) : 5'd1;
    wire [10:0] next_start = extend_seq ? seq_start : run_start;
    wire [10:0] next_span = x-next_start;

    reg previous_line;
    reg [10:0] previous_x0, previous_x1;
    reg [10:0] group_rows, group_x0, group_x1, group_y0;
    reg [10:0] best_rows, best_x0, best_x1, best_y0, best_y1;
    reg [4:0] best_stripes;
    wire [10:0] drift0 = line_x0 > previous_x0 ? line_x0-previous_x0 : previous_x0-line_x0;
    wire [10:0] drift1 = line_x1 > previous_x1 ? line_x1-previous_x1 : previous_x1-line_x1;
    wire row_ok = x == H_ACTIVE;
    wire hit = row_ok && line_hit;
    wire extend_group = hit && previous_line && drift0 <= ROW_DRIFT && drift1 <= ROW_DRIFT;
    wire [10:0] rows_next = !hit ? 11'd0 : (extend_group ? group_rows+1'b1 : 11'd1);
    wire [10:0] gx0 = extend_group && group_x0 < line_x0 ? group_x0 : line_x0;
    wire [10:0] gx1 = extend_group && group_x1 > line_x1 ? group_x1 : line_x1;
    wire [10:0] gy0 = extend_group ? group_y0 : y;
    wire improve = hit && rows_next >= best_rows;
    wire frame_hit = !bad_frame && row_ok && (improve ? rows_next : best_rows) >= MIN_ROWS;
    wire [10:0] fx0 = improve ? gx0 : best_x0;
    wire [10:0] fx1 = improve ? gx1 : best_x1;
    wire [10:0] fy0 = improve ? gy0 : best_y0;
    wire [10:0] fy1 = improve ? y : best_y1;
    // Confirm only spatially overlapping candidates in consecutive complete frames.
    wire overlap = fx0 <= box_x1 && fx1 >= box_x0 && fy0 <= box_y1 && fy1 >= box_y0;

    always @(posedge clk) begin
        if (!rst_n) begin
            vs_d <= 0; de_d <= 0; active_frame <= 0; bad_frame <= 0;
            x <= 0; y <= 0;
            run_start <= 0; run_len <= 0; gap_len <= 0; dark_len <= 0; run_gap_ok <= 0;
            seq_start <= 0; seq_width <= 0; seq_count <= 0;
            line_hit <= 0; line_x0 <= 0; line_x1 <= 0; line_stripes <= 0;
            previous_line <= 0; previous_x0 <= 0; previous_x1 <= 0;
            group_rows <= 0; group_x0 <= 0; group_x1 <= 0; group_y0 <= 0;
            best_rows <= 0; best_x0 <= 0; best_x1 <= 0; best_y0 <= 0; best_y1 <= 0; best_stripes <= 0;
            result_valid <= 0; candidate <= 0; confirmed <= 0;
            box_x0 <= 0; box_x1 <= 0; box_y0 <= 0; box_y1 <= 0; stripes <= 0;
        end else begin
            vs_d <= vs;
            de_d <= de && !vs;
            result_valid <= 0;
            if (frame_start) begin
                // An interrupted/empty frame invalidates temporal confirmation.
                if (active_frame) begin
                    result_valid <= 1; candidate <= 0; confirmed <= 0;
                    box_x0 <= 0; box_x1 <= 0; box_y0 <= 0; box_y1 <= 0; stripes <= 0;
                end
                active_frame <= 1;
                bad_frame <= de;
                x <= 0; y <= 0;
                run_len <= 0; gap_len <= 0; dark_len <= 0; seq_count <= 0;
                line_hit <= 0; line_stripes <= 0;
                previous_line <= 0; group_rows <= 0; best_rows <= 0;
            end else if (active_frame && !vs) begin
                if (de) begin
                    if (x != 2047) x <= x+1'b1;
                    if (x >= H_ACTIVE) bad_frame <= 1;
                    if (white) begin
                        if (run_len == 0) begin
                            run_start <= x;
                            run_gap_ok <= gap_len >= MIN_GAP && gap_len <= MAX_GAP && dark_len >= MIN_GAP;
                        end
                        if (run_len != 2047) run_len <= run_len+1'b1;
                        gap_len <= 0; dark_len <= 0;
                    end else begin
                        if (gap_len <= MAX_GAP) gap_len <= gap_len+1'b1;
                        if (!dark) dark_len <= 0;
                        else if (dark_len <= MAX_GAP) dark_len <= dark_len+1'b1;
                        run_len <= 0;
                        if (run_len != 0) begin
                            if (width_ok) begin
                                seq_start <= next_start; seq_width <= run_len; seq_count <= next_count;
                                if (next_count >= MIN_STRIPES && next_span >= MIN_SPAN
                                    && (!line_hit || next_count >= line_stripes)) begin
                                    line_hit <= 1; line_x0 <= next_start; line_x1 <= x-1'b1;
                                    line_stripes <= next_count;
                                end
                            end else seq_count <= 0;
                        end
                    end
                end
                if (row_end) begin
                    x <= 0; y <= y+1'b1;
                    run_len <= 0; gap_len <= 0; dark_len <= 0; seq_count <= 0;
                    line_hit <= 0; line_stripes <= 0;
                    if (!row_ok) bad_frame <= 1;
                    previous_line <= hit; previous_x0 <= line_x0; previous_x1 <= line_x1;
                    group_rows <= rows_next; group_x0 <= gx0; group_x1 <= gx1; group_y0 <= gy0;
                    if (improve) begin
                        best_rows <= rows_next; best_x0 <= gx0; best_x1 <= gx1;
                        best_y0 <= gy0; best_y1 <= y; best_stripes <= line_stripes;
                    end
                    if (y == V_ACTIVE-1) begin
                        active_frame <= 0;
                        result_valid <= 1;
                        candidate <= frame_hit;
                        confirmed <= frame_hit && candidate && overlap;
                        box_x0 <= frame_hit ? fx0 : 11'd0; box_x1 <= frame_hit ? fx1 : 11'd0;
                        box_y0 <= frame_hit ? fy0 : 11'd0; box_y1 <= frame_hit ? fy1 : 11'd0;
                        stripes <= frame_hit ? (improve ? line_stripes : best_stripes) : 5'd0;
                    end
                end
            end
        end
    end
endmodule
