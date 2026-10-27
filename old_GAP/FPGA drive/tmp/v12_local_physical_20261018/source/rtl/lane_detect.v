`timescale 1ns / 1ps
// Multi-marking candidate extraction, not lane identity or driving decisions.
// White paint uses smoothed local contrast; yellow uses RGB opponent tests.
// Candidates need connected rows; broad yellow runs are rejected before painting.
// Version 4 baseline. Total delay: 119 clocks.
module lane_detect #(
    parameter H_ACTIVE = 1280,
    parameter V_ACTIVE = 720,
    parameter ROI_Y0 = V_ACTIVE * 9 / 16,
    parameter WHITE_Y = 112,
    parameter WHITE_CONTRAST = 20,
    parameter MIN_ROWS = 6
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
    localparam CR = 8;
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
    integer i;
    always @(posedge clk) begin
        if (!rst_n) begin
            de_delay <= 0;
            vs_delay <= 0;
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
    wire [8:0] background = (lum_delay[0] < lum_delay[2*CR])
                            ? {1'b0, lum_delay[0]} : {1'b0, lum_delay[2*CR]};
    wire is_yellow = (r >= 96) && (g >= 80)
                      && (r >= b + 9'd28) && (g >= b + 9'd20)
                      && (r + 9'd32 >= g) && (g + 9'd80 >= r);
    wire is_white = (lo_rgb >= 96) && (hi_rgb - lo_rgb <= 56)
                    && (lum_delay[CR] >= WHITE_Y)
                    && ({1'b0, lum_delay[CR]} >= background + WHITE_CONTRAST)
                    && !is_yellow;

    wire [10:0] cx = x_delay[CR], cy = y_delay[CR];
    wire [11:0] distance_x = (cx >= H_ACTIVE/2)
                             ? cx - H_ACTIVE/2 : H_ACTIVE/2 - cx;
    wire [11:0] depth = (cy >= ROI_Y0) ? cy - ROI_Y0 : 0;
    wire [12:0] half_width = H_ACTIVE/4 + depth + (depth << 1);
    wire in_roi = de_delay[CR] && (cy >= ROI_Y0) && (cy < V_ACTIVE-2)
                   && (cx >= CR) && (cx < H_ACTIVE-CR)
                   && (distance_x <= half_width);
    wire raw_white = in_roi && is_white;
    wire raw_yellow = in_roi && is_yellow;

    // Opposite parity banks avoid read/write collisions. Only the previous
    // row is read; row zero ignores old RAM, so frames cannot retain locks.
    reg [2:0] history [0:(1<<(AW+1))-1];
    reg [2:0] previous_score;
    reg [2:0] score_window [0:2*SR];
    reg [15:0] base_pipe [0:LAST];
    reg [10:0] x_pipe [0:LAST], y_pipe [0:LAST];
    reg [1:0] mode_pipe [0:LAST];
    reg [LAST:0] white_pipe, yellow_pipe, de_pipe, vs_pipe;
    reg [2:0] best_score;
    integer k;
    always @* begin
        best_score = 0;
        for (k = 0; k <= 2*SR; k = k+1)
            if (score_window[k] > best_score)
                best_score = score_window[k];
    end
    wire candidate = white_pipe[LAST] | yellow_pipe[LAST];
    wire [2:0] score = !candidate ? 3'd0
                       : (best_score == 7 ? 3'd7 : best_score + 1'b1);

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
            de_pipe <= {de_pipe[LAST-1:0], de_delay[CR]};
            vs_pipe <= {vs_pipe[LAST-1:0], vs_delay[CR]};
            score_window[0] <= (de_pipe[0] && y_pipe[0] != 0)
                               ? previous_score : 3'd0;
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
    localparam YELLOW_MIN_WIDTH = 64;
    localparam YELLOW_MAX_WIDTH = 96;
    wire [10:0] yellow_depth = (y_pipe[LAST] >= ROI_Y0)
                               ? y_pipe[LAST] - ROI_Y0 : 11'd0;
    wire [11:0] width_ramp = YELLOW_MIN_WIDTH + (yellow_depth >> 3);
    wire [6:0] width_limit = (width_ramp > YELLOW_MAX_WIDTH)
                             ? YELLOW_MAX_WIDTH : width_ramp[6:0];

    // Close holes up to four pixels for measurement only; never paint the holes.
    // Metadata: {limit, vs, de, yellow, white, mode, base_rgb}.
    reg [8:0] yellow_near;
    reg [28:0] close_meta [0:4];
    integer c;
    always @(posedge clk) begin
        if (!rst_n) begin
            yellow_near <= 0;
            for (c = 0; c <= 4; c = c+1)
                close_meta[c] <= 0;
        end else begin
            yellow_near <= {yellow_near[7:0], supported_yellow};
            close_meta[0] <= {width_limit, vs_pipe[LAST], de_pipe[LAST],
                             supported_yellow, supported_white,
                             mode_pipe[LAST], base_pipe[LAST]};
            for (c = 1; c <= 4; c = c+1)
                close_meta[c] <= close_meta[c-1];
        end
    end
    wire closed_yellow = close_meta[4][20]
                          && (|yellow_near[4:0]) && (|yellow_near[5:1])
                          && (|yellow_near[6:2]) && (|yellow_near[7:3])
                          && (|yellow_near[8:4]);

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
    reg [YELLOW_MAX_WIDTH:0] closed_window;
    reg [6:0] left_count;
    wire [6:0] next_left = !closed_yellow ? 7'd0
                           : (left_count >= YELLOW_MAX_WIDTH+1
                              ? 7'd97 : left_count + 1'b1);
    reg [35:0] width_meta [0:YELLOW_MAX_WIDTH];
    integer w;
    always @(posedge clk) begin
        if (!rst_n) begin
            closed_window <= 0;
            left_count <= 0;
            for (w = 0; w <= YELLOW_MAX_WIDTH; w = w+1)
                width_meta[w] <= 0;
        end else begin
            closed_window <= {closed_window[YELLOW_MAX_WIDTH-1:0], closed_yellow};
            left_count <= next_left;
            width_meta[0] <= {next_left, close_meta[4]};
            for (w = 1; w <= YELLOW_MAX_WIDTH; w = w+1)
                width_meta[w] <= width_meta[w-1];
        end
    end
    wire [6:0] final_left, final_limit;
    wire final_vs, final_de, final_yellow, final_white;
    wire [1:0] final_mode;
    wire [15:0] final_base;
    assign {final_left, final_limit, final_vs, final_de,
            final_yellow, final_white, final_mode, final_base}
            = width_meta[YELLOW_MAX_WIDTH];
    wire [7:0] run_width = {1'b0, final_left}
                           + {1'b0, prefix96(closed_window[95:0])};
    assign white_mark = rst_n && final_de && final_white;
    assign yellow_mark = rst_n && final_de && final_yellow
                          && (run_width <= {1'b0, final_limit});
    wire [15:0] paint = yellow_mark ? 16'h07FF : 16'h07E0;
    assign rgb_out = ((final_mode != 0) && (white_mark || yellow_mark))
                      ? paint : (final_mode == 2 ? 16'h0000 : final_base);
    assign de_out = rst_n && final_de;
    assign vs_out = rst_n && final_vs;
endmodule
