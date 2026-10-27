`timescale 1ns / 1ps
// Multi-marking candidate extraction, not lane identity or driving decisions.
// White paint uses smoothed local contrast; yellow uses RGB opponent tests.
// Candidates need connected rows and darker neutral background on both sides.
// Broad runs are rejected before painting. Total delay: 207 clocks.
module lane_detect #(
    parameter H_ACTIVE = 1280,
    parameter V_ACTIVE = 720,
    parameter ROI_Y0 = V_ACTIVE / 3,
    parameter WHITE_Y = 112,
    parameter WHITE_CONTRAST = 20,
    parameter MIN_ROWS = 10
)(
    input             clk,
    input             rst_n,
    input             de,
    input             vs,
    input      [15:0]  rgb_in,
    input      [7:0]   luma_in,
    input      [15:0]  base_in,
    input      [1:0]   paint_mode, // 0=base, 1=overlay, 2=mask
    output     [15:0]  rgb_out,
    output            de_out,
    output            vs_out,
    output            white_mark,
    output            yellow_mark
);
    localparam CR = 96;
    localparam BORDER = 8;
    localparam SR = 6;
    localparam LAST = SR + 1;
    localparam AW = 11;

    reg [10:0] x, y;
    reg de_d, vs_d;
    wire frame_start = vs & ~vs_d;

    always @(posedge clk) begin
        if (!rst_n) begin
            x <= 0;
            y <= 0;
            de_d <= 0;
            vs_d <= 0;
        end else begin
            de_d <= de;
            vs_d <= vs;
            if (frame_start) begin
                x <= 0;
                y <= 0;
            end else if (de_d && !de) begin
                x <= 0;
                y <= (y == V_ACTIVE-1) ? 0 : y + 1'b1;
            end else if (de) begin
                x <= x + 1'b1;
            end
        end
    end

    reg [7:0] lum_delay [0:2*CR];
    reg [15:0] rgb_delay [0:CR], base_delay [0:CR];
    reg [10:0] x_delay [0:CR], y_delay [0:CR];
    reg [1:0] mode_delay [0:CR];
    reg [CR:0] de_delay, vs_delay;
    reg [2*CR:0] road_delay;
    wire [8:0] input_r = {1'b0, rgb_in[15:11], rgb_in[15:13]};
    wire [8:0] input_g = {1'b0, rgb_in[10:5], rgb_in[10:9]};
    wire [8:0] input_b = {1'b0, rgb_in[4:0], rgb_in[4:2]};
    wire [8:0] input_lo_rg = (input_r < input_g) ? input_r : input_g;
    wire [8:0] input_hi_rg = (input_r > input_g) ? input_r : input_g;
    wire [8:0] input_lo = (input_lo_rg < input_b) ? input_lo_rg : input_b;
    wire [8:0] input_hi = (input_hi_rg > input_b) ? input_hi_rg : input_b;
    wire neutral_background = de && (input_hi - input_lo <= 64)
                               && (input_g <= input_r + 9'd20)
                               && (input_g <= input_b + 9'd20)
                               && (luma_in >= 24) && (luma_in <= 192);
    integer i;
    always @(posedge clk) begin
        if (!rst_n) begin
            de_delay <= 0;
            vs_delay <= 0;
            road_delay <= 0;
            for (i = 0; i <= 2*CR; i = i+1)
                lum_delay[i] <= 0;
            for (i = 0; i <= CR; i = i+1) begin
                rgb_delay[i] <= 0;
                base_delay[i] <= 0;
                x_delay[i] <= 0;
                y_delay[i] <= 0;
                mode_delay[i] <= 0;
            end
        end else begin
            de_delay <= {de_delay[CR-1:0], de};
            vs_delay <= {vs_delay[CR-1:0], vs};
            road_delay <= {road_delay[2*CR-1:0], neutral_background};
            lum_delay[0] <= luma_in;
            for (i = 1; i <= 2*CR; i = i+1)
                lum_delay[i] <= lum_delay[i-1];
            rgb_delay[0] <= rgb_in;
            base_delay[0] <= base_in;
            x_delay[0] <= x;
            y_delay[0] <= y;
            mode_delay[0] <= paint_mode;
            for (i = 1; i <= CR; i = i+1) begin
                rgb_delay[i] <= rgb_delay[i-1];
                base_delay[i] <= base_delay[i-1];
                x_delay[i] <= x_delay[i-1];
                y_delay[i] <= y_delay[i-1];
                mode_delay[i] <= mode_delay[i-1];
            end
        end
    end

    wire [15:0] pixel = rgb_delay[CR];
    wire [8:0] r = {1'b0, pixel[15:11], pixel[15:13]};
    wire [8:0] g = {1'b0, pixel[10:5], pixel[10:9]};
    wire [8:0] b = {1'b0, pixel[4:0], pixel[4:2]};
    wire [8:0] lo_rg = (r < g) ? r : g;
    wire [8:0] hi_rg = (r > g) ? r : g;
    wire [8:0] lo_rgb = (lo_rg < b) ? lo_rg : b;
    wire [8:0] hi_rgb = (hi_rg > b) ? hi_rg : b;
    wire [8:0] background = (lum_delay[CR-BORDER] < lum_delay[CR+BORDER])
                            ? {1'b0, lum_delay[CR-BORDER]}
                            : {1'b0, lum_delay[CR+BORDER]};
    wire is_yellow = (r >= 96) && (g >= 80)
                      && (r >= b + 9'd28) && (g >= b + 9'd20)
                      && (r + 9'd12 >= g) && (g + 9'd80 >= r);
    wire is_white = (lo_rgb >= 96) && (hi_rgb - lo_rgb <= 56)
                    && (lum_delay[CR] >= WHITE_Y)
                    && ({1'b0, lum_delay[CR]} >= background + WHITE_CONTRAST)
                    && !is_yellow;

    wire [10:0] cx = x_delay[CR], cy = y_delay[CR];
    function [7:0] min5;
        input [7:0] a, b, c, d, e;
        reg [7:0] ab, cd, abcd;
        begin
            ab = (a < b) ? a : b;
            cd = (c < d) ? c : d;
            abcd = (ab < cd) ? ab : cd;
            min5 = (abcd < e) ? abcd : e;
        end
    endfunction
    wire [7:0] left_sample [0:4], right_sample [0:4];
    genvar tap;
    generate
        for (tap = 0; tap < 5; tap = tap+1) begin : road_sides
            localparam RADIUS = (tap == 0) ? 8 : ((tap == 1) ? 16
                                : ((tap == 2) ? 32 : ((tap == 3) ? 64 : 96)));
            wire valid_column = (cx >= RADIUS) && (cx < H_ACTIVE-RADIUS);
            assign left_sample[tap] = (valid_column && road_delay[CR+RADIUS])
                                      ? lum_delay[CR+RADIUS] : 8'hFF;
            assign right_sample[tap] = (valid_column && road_delay[CR-RADIUS])
                                       ? lum_delay[CR-RADIUS] : 8'hFF;
        end
    endgenerate
    wire [7:0] left_background = min5(left_sample[0], left_sample[1],
                                     left_sample[2], left_sample[3], left_sample[4]);
    wire [7:0] right_background = min5(right_sample[0], right_sample[1],
                                      right_sample[2], right_sample[3], right_sample[4]);
    wire [8:0] stripe_background = (left_background > right_background)
                                   ? {1'b0, left_background} : {1'b0, right_background};
    wire white_stripe = {1'b0, lum_delay[CR]} >= stripe_background + WHITE_CONTRAST;
    wire yellow_stripe = {1'b0, lum_delay[CR]} >= stripe_background + 9'd12;
    wire [11:0] distance_x = (cx >= H_ACTIVE/2)
                             ? cx - H_ACTIVE/2 : H_ACTIVE/2 - cx;
    wire [11:0] depth = (cy >= ROI_Y0) ? cy - ROI_Y0 : 0;
    wire [11:0] near_depth = (cy >= V_ACTIVE/2) ? cy - V_ACTIVE/2 : 0;
    wire [12:0] half_width = H_ACTIVE/32 + depth + (depth >> 1) + (near_depth << 1);
    wire in_roi = de_delay[CR] && (cy >= ROI_Y0) && (cy < V_ACTIVE-2)
                   && (cx >= BORDER) && (cx < H_ACTIVE-BORDER)
                   && (distance_x <= half_width);
    wire raw_white = in_roi && is_white;
    wire raw_yellow = in_roi && is_yellow;

    // Opposite parity banks avoid read/write collisions. Only the previous
    // row is read; row zero ignores old RAM, so frames cannot retain locks.
    reg [3:0] history [0:(1<<(AW+1))-1];
    reg [3:0] previous_score;
    reg [3:0] score_window [0:2*SR];
    reg [15:0] base_pipe [0:LAST];
    reg [10:0] x_pipe [0:LAST], y_pipe [0:LAST];
    reg [1:0] mode_pipe [0:LAST];
    reg [LAST:0] white_pipe, yellow_pipe, de_pipe, vs_pipe;
    reg [LAST:0] white_stripe_pipe, yellow_stripe_pipe;
    reg [3:0] best_score;
    integer k;
    always @* begin
        best_score = 0;
        for (k = 0; k <= 2*SR; k = k+1)
            if (score_window[k] > best_score)
                best_score = score_window[k];
    end
    wire candidate = white_pipe[LAST] | yellow_pipe[LAST];
    wire [3:0] score = !candidate ? 4'd0
                       : (best_score == 15 ? 4'd15 : best_score + 1'b1);

    always @(posedge clk) begin
        if (de_delay[CR])
            previous_score <= history[{~cy[0], cx}];
        else
            previous_score <= 0;
        if (rst_n && de_pipe[LAST])
            history[{y_pipe[LAST][0], x_pipe[LAST]}] <= score;
    end

    integer j;
    always @(posedge clk) begin
        if (!rst_n) begin
            white_pipe <= 0;
            yellow_pipe <= 0;
            white_stripe_pipe <= 0;
            yellow_stripe_pipe <= 0;
            de_pipe <= 0;
            vs_pipe <= 0;
            for (j = 0; j <= 2*SR; j = j+1)
                score_window[j] <= 0;
            for (j = 0; j <= LAST; j = j+1) begin
                base_pipe[j] <= 0;
                x_pipe[j] <= 0;
                y_pipe[j] <= 0;
                mode_pipe[j] <= 0;
            end
        end else begin
            white_pipe <= {white_pipe[LAST-1:0], raw_white};
            yellow_pipe <= {yellow_pipe[LAST-1:0], raw_yellow};
            white_stripe_pipe <= {white_stripe_pipe[LAST-1:0], white_stripe};
            yellow_stripe_pipe <= {yellow_stripe_pipe[LAST-1:0], yellow_stripe};
            de_pipe <= {de_pipe[LAST-1:0], de_delay[CR]};
            vs_pipe <= {vs_pipe[LAST-1:0], vs_delay[CR]};
            score_window[0] <= (de_pipe[0] && y_pipe[0] != 0)
                               ? previous_score : 4'd0;
            for (j = 1; j <= 2*SR; j = j+1)
                score_window[j] <= score_window[j-1];
            base_pipe[0] <= base_delay[CR];
            x_pipe[0] <= cx;
            y_pipe[0] <= cy;
            mode_pipe[0] <= mode_delay[CR];
            for (j = 1; j <= LAST; j = j+1) begin
                base_pipe[j] <= base_pipe[j-1];
                x_pipe[j] <= x_pipe[j-1];
                y_pipe[j] <= y_pipe[j-1];
                mode_pipe[j] <= mode_pipe[j-1];
            end
        end
    end

    wire supported_white = de_pipe[LAST] && white_pipe[LAST] && (score >= MIN_ROWS);
    wire supported_yellow = de_pipe[LAST] && yellow_pipe[LAST] && (score >= MIN_ROWS);
    localparam MARK_MIN_WIDTH = 12;
    localparam MARK_MAX_WIDTH = 96;
    wire [10:0] marking_depth = (y_pipe[LAST] >= ROI_Y0)
                               ? y_pipe[LAST] - ROI_Y0 : 11'd0;
    wire [11:0] width_ramp = MARK_MIN_WIDTH + (marking_depth >> 2);
    wire [6:0] width_limit = (width_ramp > MARK_MAX_WIDTH)
                             ? MARK_MAX_WIDTH : width_ramp[6:0];

    // Close holes up to four pixels for measurement only; never paint the holes.
    // Metadata: {limit, vs, de, yellow, white, mode, base_rgb}.
    reg [8:0] marking_near;
    reg [28:0] close_meta [0:4];
    integer c;
    always @(posedge clk) begin
        if (!rst_n) begin
            marking_near <= 0;
            for (c = 0; c <= 4; c = c+1)
                close_meta[c] <= 0;
        end else begin
            marking_near <= {marking_near[7:0], supported_white | supported_yellow};
            close_meta[0] <= {width_limit, vs_pipe[LAST], de_pipe[LAST],
                             supported_yellow && yellow_stripe_pipe[LAST],
                             supported_white && white_stripe_pipe[LAST],
                             mode_pipe[LAST], base_pipe[LAST]};
            for (c = 1; c <= 4; c = c+1)
                close_meta[c] <= close_meta[c-1];
        end
    end
    wire closed_candidate = close_meta[4][20]
                             && (|marking_near[4:0]) && (|marking_near[5:1])
                             && (|marking_near[6:2]) && (|marking_near[7:3])
                             && (|marking_near[8:4]);

    function [3:0] prefix8;
        input [7:0] value;
        begin
            casez (value)
                8'b0???????: prefix8 = 0;
                8'b10??????: prefix8 = 1;
                8'b110?????: prefix8 = 2;
                8'b1110????: prefix8 = 3;
                8'b11110???: prefix8 = 4;
                8'b111110??: prefix8 = 5;
                8'b1111110?: prefix8 = 6;
                8'b11111110: prefix8 = 7;
                8'b11111111: prefix8 = 8;
                default: prefix8 = 0;
            endcase
        end
    endfunction
    function [4:0] prefix16;
        input [15:0] value;
        begin
            prefix16 = (&value[15:8]) ? 5'd8 + prefix8(value[7:0])
                                       : {1'b0, prefix8(value[15:8])};
        end
    endfunction
    function [5:0] prefix32;
        input [31:0] value;
        begin
            prefix32 = (&value[31:16]) ? 6'd16 + prefix16(value[15:0])
                                        : {1'b0, prefix16(value[31:16])};
        end
    endfunction
    function [6:0] prefix96;
        input [95:0] value;
        begin
            if (!(&value[95:64]))
                prefix96 = {1'b0, prefix32(value[95:64])};
            else if (!(&value[63:32]))
                prefix96 = 7'd32 + prefix32(value[63:32]);
            else
                prefix96 = 7'd64 + prefix32(value[31:0]);
        end
    endfunction

    // Look ahead by the maximum allowed width so a rejected run cannot leak
    // its leading edge. Blank DE samples break runs even at short line gaps.
    reg [MARK_MAX_WIDTH:0] closed_window;
    reg [6:0] left_count;
    wire [6:0] next_left = !closed_candidate ? 7'd0
                           : (left_count >= MARK_MAX_WIDTH+1
                              ? 7'd97 : left_count + 1'b1);
    reg [35:0] width_meta [0:MARK_MAX_WIDTH];
    integer w;
    always @(posedge clk) begin
        if (!rst_n) begin
            closed_window <= 0;
            left_count <= 0;
            for (w = 0; w <= MARK_MAX_WIDTH; w = w+1)
                width_meta[w] <= 0;
        end else begin
            closed_window <= {closed_window[MARK_MAX_WIDTH-1:0], closed_candidate};
            left_count <= next_left;
            width_meta[0] <= {next_left, close_meta[4]};
            for (w = 1; w <= MARK_MAX_WIDTH; w = w+1)
                width_meta[w] <= width_meta[w-1];
        end
    end
    wire [6:0] final_left, final_limit;
    wire final_vs, final_de, final_yellow, final_white;
    wire [1:0] final_mode;
    wire [15:0] final_base;
    assign {final_left, final_limit, final_vs, final_de,
            final_yellow, final_white, final_mode, final_base}
            = width_meta[MARK_MAX_WIDTH];
    wire [7:0] run_width = {1'b0, final_left}
                           + {1'b0, prefix96(closed_window[95:0])};
    assign white_mark = rst_n && final_de && final_white
                         && (run_width <= {1'b0, final_limit});
    assign yellow_mark = rst_n && final_de && final_yellow
                          && (run_width <= {1'b0, final_limit});
    wire [15:0] paint = yellow_mark ? 16'h07FF : 16'h07E0;
    assign rgb_out = ((final_mode != 0) && (white_mark || yellow_mark))
                      ? paint : (final_mode == 2 ? 16'h0000 : final_base);
    assign de_out = rst_n && final_de;
    assign vs_out = rst_n && final_vs;
endmodule
