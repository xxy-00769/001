`timescale 1ns / 1ps
//============================================================================
//  img_proc.v  --  image pre-processing pipeline  (ADAS competition)
//
//    RGB565 --> luma/window --> median / Sobel / road-marking candidates
//
//  Insert point : between cmos_8_16bit and fram_buf
//  Clock        : pixel_clk (42 MHz), one 16-bit pixel per clock
//  Image        : 1280 x 720
//
//  MODE : 0 = bypass  (original picture)
//         1 = luma    (greyscale)
//         2 = median  (greyscale + 3x3 median denoise)
//         3 = sobel   (edge magnitude)
//         4 = road markings (green white-paint, cyan yellow-paint candidates)
//         5 = road-marking mask on black
//         6 = row1    (one line back)
//         7 = row2    (two lines back)
//
//  All display modes share the road-marking stage's pixel/control delay.
//
//  NOTE: comments are ASCII only on purpose - PDS/ADS handles that best.
//============================================================================
module img_proc #(
    parameter MODE       = 4,       // output mode, see header
    parameter DIAG_CYCLE = 0,       // 1 = auto-cycle modes every 64 frames
    parameter H_ACTIVE   = 1280,
    parameter V_ACTIVE   = 720,
    parameter ZEBRA_ENABLE = 0,     // opt-in experiment; preserves v6 by default
    parameter ADAS_ENABLE = 0,     // v8 lane geometry and status HUD
    parameter FRAME_TAGS = 0,
    parameter RUNTIME_MODE = 0     // 0..4 as above; 5 = legacy lane/zebra HUD
)(
    input               clk,        // pixel_clk
    input               rst_n,
    input      [15:0]   rgb_in,     // {R[4:0], G[5:0], B[4:0]}
    input               de_in,
    input               vs_in,
    output reg [15:0]   rgb_out,
    output reg          de_out,
    output reg          vs_out,
    output              adas_valid,
    output [255:0]      adas_snapshot,
    output reg [15:0]   clean_rgb_out,
    output reg          clean_de_out,
    output reg          clean_vs_out,
    input [31:0]        frame_id_in,
    input [31:0]        frame_time_in,
    output reg [31:0]   clean_frame_id,
    output reg [31:0]   clean_frame_time,
    input [2:0]        mode_request,
    output reg [31:0]  display_frame_id,
    output reg [31:0]  display_frame_time
);

    localparam AW = 11;             // Active columns only; supports up to 2048.

    //------------------------------------------------------------------------
    //  0. helpers
    //------------------------------------------------------------------------
    // RGB565 -> 8 bit luma.   Y = (77R + 150G + 29B) >> 8
    function [7:0] luma;
        input [15:0] p;
        reg   [7:0]  r8, g8, b8;
        reg   [15:0] s;
        begin
            r8  = {p[15:11], p[15:13]};     // 5 -> 8 bit
            g8  = {p[10:5],  p[10:9] };     // 6 -> 8 bit
            b8  = {p[4:0],   p[4:2]  };     // 5 -> 8 bit
            s   = 16'd77*r8 + 16'd150*g8 + 16'd29*b8;
            luma= s[15:8];
        end
    endfunction

    // 8 bit luma -> RGB565 grey
    function [15:0] to565;
        input [7:0] v;
        begin
            to565 = {v[7:3], v[7:2], v[7:3]};
        end
    endfunction

    // sort 3 values -> {max, median, min}
    function [23:0] sort3;
        input [7:0] a, b, c;
        reg   [7:0] mx, mn;
        reg   [9:0] sm;
        begin
            mx   = (a>b) ? ((a>c)?a:c) : ((b>c)?b:c);
            mn   = (a<b) ? ((a<c)?a:c) : ((b<c)?b:c);
            sm   = a + b + c - mx - mn;
            sort3= {mx, sm[7:0], mn};
        end
    endfunction

    // Three rotating active-pixel banks provide the two completed rows.
    // DE is generated from row/column events, never replayed from RAM in blanking.
    reg [15:0] row_bank0 [0:(1<<AW)-1];
    reg [15:0] row_bank1 [0:(1<<AW)-1];
    reg [15:0] row_bank2 [0:(1<<AW)-1];
    reg [15:0] bank_q0, bank_q1, bank_q2;
    reg [AW-1:0] input_col, flush_col;
    reg [10:0] input_row;
    reg [1:0] write_bank, flush_bank;
    reg vs_seen, have_frame;
    reg [63:0] input_frame_tag;
    reg flush_pending, flushing;
    wire frame_start = vs_in && !vs_seen;
    wire input_valid = rst_n && have_frame && !vs_in
                        && de_in && (input_row < V_ACTIVE);
    wire read_event = input_valid || flushing;
    wire [AW-1:0] read_col = flushing ? flush_col : input_col;

    always @(posedge clk) begin
        if (!rst_n) begin
            input_col <= 0;
            input_row <= 0;
            write_bank <= 0;
            flush_bank <= 0;
            vs_seen <= 0;
            have_frame <= 0;
            flush_pending <= 0;
            flushing <= 0;
            flush_col <= 0;
            input_frame_tag <= 0;
        end else begin
            vs_seen <= vs_in;
            if (frame_start) begin
                input_col <= 0;
                input_row <= 0;
                have_frame <= 1;
                input_frame_tag <= FRAME_TAGS ? {frame_time_in, frame_id_in} : 64'd0;
            end else begin
                if (input_valid) begin
                    if (input_col == H_ACTIVE-1) begin
                        input_col <= 0;
                        input_row <= input_row + 1'b1;
                        write_bank <= (write_bank == 2) ? 0 : write_bank + 1'b1;
                        if (input_row == V_ACTIVE-1) begin
                            flush_pending <= 1;
                            flush_bank <= (write_bank == 2) ? 0 : write_bank + 1'b1;
                        end
                    end else begin
                        input_col <= input_col + 1'b1;
                    end
                end
            end
            // Finish the old frame even if input VS has already begun the next.
            // Its final two banks remain intact while the next first row is written.
            // One idle read cycle drains the preceding row's right border first.
            if (flush_pending) begin
                flush_pending <= 0;
                flushing <= 1;
                flush_col <= 0;
            end
            if (flushing) begin
                if (flush_col == H_ACTIVE-1)
                    flushing <= 0;
                else
                    flush_col <= flush_col + 1'b1;
            end
        end
    end

    // The write bank's read value is never selected, avoiding RAM collision modes.
    always @(posedge clk) begin
        if (input_valid && !frame_start) begin
            case (write_bank)
                0: row_bank0[input_col] <= rgb_in;
                1: row_bank1[input_col] <= rgb_in;
                2: row_bank2[input_col] <= rgb_in;
            endcase
        end
        if (read_event) begin
            bank_q0 <= row_bank0[read_col];
            bank_q1 <= row_bank1[read_col];
            bank_q2 <= row_bank2[read_col];
        end
    end

    reg read_valid, read_flush;
    reg [AW-1:0] read_col_d;
    reg [10:0] read_row_d;
    reg [1:0] read_bank_d;
    reg [15:0] bottom_d;
    reg [63:0] read_frame_tag, window_frame_tag;
    always @(posedge clk) begin
        if (!rst_n) begin
            read_valid <= 0;
            read_flush <= 0;
            read_col_d <= 0;
            read_row_d <= 0;
            read_bank_d <= 0;
            bottom_d <= 0;
            read_frame_tag <= 0;
        end else begin
            read_valid <= read_event;
            read_flush <= flushing;
            read_col_d <= read_col;
            read_row_d <= flushing ? V_ACTIVE : input_row;
            read_bank_d <= flushing ? flush_bank : write_bank;
            bottom_d <= rgb_in;
            read_frame_tag <= input_frame_tag;
        end
    end

    wire [15:0] middle = (read_bank_d == 0) ? bank_q2
                         : ((read_bank_d == 1) ? bank_q0 : bank_q1);
    wire [15:0] above = (read_row_d == 1) ? middle
                        : ((read_bank_d == 0) ? bank_q1
                           : ((read_bank_d == 1) ? bank_q2 : bank_q0));
    wire [15:0] below = read_flush ? middle : bottom_d;
    reg [7:0] top_a, top_b, mid_a, mid_b, bot_a, bot_b;
    reg [15:0] mid_rgb;
    reg tail_pending;
    reg [7:0] w00, w01, w02, w10, w11, w12, w20, w21, w22;
    reg [16:0] c_pix;
    reg window_vs;
    wire window_event = read_valid && (read_row_d != 0);
    wire [7:0] top_now = window_event ? luma(above) : top_a;
    wire [7:0] mid_now = window_event ? luma(middle) : mid_a;
    wire [7:0] bot_now = window_event ? luma(below) : bot_a;

    // Replicate all four image borders; every original pixel is emitted once.
    always @(posedge clk) begin
        if (!rst_n) begin
            c_pix <= 0;
            window_vs <= 0;
            window_frame_tag <= 0;
            tail_pending <= 0;
            top_a <= 0; top_b <= 0;
            mid_a <= 0; mid_b <= 0;
            bot_a <= 0; bot_b <= 0;
            mid_rgb <= 0;
            w00 <= 0; w01 <= 0; w02 <= 0;
            w10 <= 0; w11 <= 0; w12 <= 0;
            w20 <= 0; w21 <= 0; w22 <= 0;
        end else begin
            c_pix[16] <= 0;
            // A one-clock frame marker precedes the first emitted pixel.
            // Downstream frame counters must follow buffered data, not input VS.
            window_vs <= window_event && !read_flush
                          && (read_row_d == 1) && (read_col_d == 0);
            if (window_event && !read_flush && read_row_d == 1 && read_col_d == 0)
                window_frame_tag <= read_frame_tag;
            tail_pending <= 0;
            if (window_event || tail_pending) begin
                if (window_event && read_col_d == 0) begin
                    top_b <= top_now;
                    mid_b <= mid_now;
                    bot_b <= bot_now;
                end else begin
                    w00 <= top_b; w01 <= top_a; w02 <= top_now;
                    w10 <= mid_b; w11 <= mid_a; w12 <= mid_now;
                    w20 <= bot_b; w21 <= bot_a; w22 <= bot_now;
                    c_pix <= {1'b1, mid_rgb};
                    top_b <= top_a;
                    mid_b <= mid_a;
                    bot_b <= bot_a;
                end
                top_a <= top_now;
                mid_a <= mid_now;
                bot_a <= bot_now;
                if (window_event) begin
                    mid_rgb <= middle;
                    tail_pending <= (read_col_d == H_ACTIVE-1);
                end
            end
        end
    end

    // Keep the buffered color stream independent of all diagnostic drawing.
    // Its own frame marker precedes pixel zero; never pair it with lane_de/vs.
    always @(posedge clk) begin
        if (!rst_n) begin
            clean_rgb_out <= 0;
            clean_de_out <= 0;
            clean_vs_out <= 0;
            clean_frame_id <= 0;
            clean_frame_time <= 0;
        end else begin
            clean_rgb_out <= c_pix[15:0];
            clean_de_out <= c_pix[16];
            clean_vs_out <= window_vs;
            {clean_frame_time, clean_frame_id} <= window_frame_tag;
        end
    end

    //------------------------------------------------------------------------
    //  6. 3x3 median : sort each column, then take the median of
    //     {max-of-mins, median-of-medians, min-of-maxes}
    //------------------------------------------------------------------------
    wire [23:0] s0 = sort3(w00, w10, w20);
    wire [23:0] s1 = sort3(w01, w11, w21);
    wire [23:0] s2 = sort3(w02, w12, w22);

    wire [7:0] s0max = s0[23:16], s0med = s0[15:8], s0min = s0[7:0];
    wire [7:0] s1max = s1[23:16], s1med = s1[15:8], s1min = s1[7:0];
    wire [7:0] s2max = s2[23:16], s2med = s2[15:8], s2min = s2[7:0];

    wire [7:0] max_of_min = (s0min>s1min) ? ((s0min>s2min)?s0min:s2min)
                                          : ((s1min>s2min)?s1min:s2min);
    wire [7:0] min_of_max = (s0max<s1max) ? ((s0max<s2max)?s0max:s2max)
                                          : ((s1max<s2max)?s1max:s2max);

    wire [23:0] smed      = sort3(s0med, s1med, s2med);
    wire [7:0]  med_of_med= smed[15:8];

    wire [23:0] sfin  = sort3(max_of_min, med_of_med, min_of_max);
    wire [7:0]  median= sfin[15:8];

    //------------------------------------------------------------------------
    //  7. Sobel edge magnitude   |Gx| + |Gy|
    //------------------------------------------------------------------------
    wire [11:0] px = {4'b0,w02} + {3'b0,w12,1'b0} + {4'b0,w22};
    wire [11:0] nx = {4'b0,w00} + {3'b0,w10,1'b0} + {4'b0,w20};
    wire [11:0] py = {4'b0,w20} + {3'b0,w21,1'b0} + {4'b0,w22};
    wire [11:0] ny = {4'b0,w00} + {3'b0,w01,1'b0} + {4'b0,w02};

    wire signed [12:0] gx = {1'b0,px} - {1'b0,nx};
    wire signed [12:0] gy = {1'b0,py} - {1'b0,ny};

    wire [12:0] agx = gx[12] ? (~gx + 1'b1) : gx;
    wire [12:0] agy = gy[12] ? (~gy + 1'b1) : gy;
    wire [13:0] mag = agx + agy;

    wire [7:0] sobel = (mag > 14'd255) ? 8'hFF : mag[7:0];

    //------------------------------------------------------------------------
    //  8. display selection and road-marking stage
    //------------------------------------------------------------------------
    // diagnostic mode selector: cycles 0..7 every 64 frames when DIAG_CYCLE=1
    reg  vs_d1, vs_d2, vs_d3;
    reg  [6:0]  fcnt;
    reg  [2:0]  mode_sel;

    always @(posedge clk) begin
        vs_d1 <= vs_in;
        vs_d2 <= vs_d1;
        vs_d3 <= vs_d2;
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            fcnt     <= 7'd0;
            mode_sel <= 3'd0;
        end else if (vs_d2 & ~vs_d3) begin              // vs rising edge
            if (fcnt == 7'd63) begin
                fcnt     <= 7'd0;
                mode_sel <= (mode_sel >= 3'd7) ? 3'd0 : (mode_sel + 1'b1);
            end else begin
                fcnt <= fcnt + 1'b1;
            end
        end
    end

    localparam [2:0] MODE_C = MODE;
    wire lane_de, lane_vs;
    reg [2:0] frame_mode, overlay_mode;
    always @(posedge clk) begin
        if (!rst_n) begin
            frame_mode <= 0;
            overlay_mode <= 0;
        end else begin
            // The buffered frame header, not raw VS, owns the mode. Raw VS
            // may arrive while the previous frame's last row is flushing.
            if (window_vs)
                frame_mode <= (mode_request <= 5) ? mode_request : 3'd0;
            if (lane_vs)
                overlay_mode <= frame_mode;
        end
    end
    wire [2:0] msel = RUNTIME_MODE ? frame_mode : (DIAG_CYCLE ? mode_sel : MODE_C);
    wire legacy_overlay = RUNTIME_MODE ? (overlay_mode == 5) : (msel == 4);

    wire [15:0] col_sob = to565(sobel);
    wire [15:0] col_gry = to565(median);
    wire [15:0] col_lum = to565(w11);
    wire [15:0] col_r1  = to565(w11);
    wire [15:0] col_r2  = to565(w01);

    // Gaussian luma suppresses asphalt texture before the local-contrast test.
    wire [11:0] smooth_sum = {4'b0,w00} + {3'b0,w01,1'b0} + {4'b0,w02}
                            + {3'b0,w10,1'b0} + {2'b0,w11,2'b0} + {3'b0,w12,1'b0}
                            + {4'b0,w20} + {3'b0,w21,1'b0} + {4'b0,w22};
    reg [15:0] display_rgb;
    always @* begin
        case (msel)
            3'd1: display_rgb = col_lum;
            3'd2: display_rgb = col_gry;
            3'd3: display_rgb = col_sob;
            3'd6: display_rgb = col_r1;
            3'd7: display_rgb = col_r2;
            default: display_rgb = c_pix[15:0];
        endcase
    end

    wire [1:0] paint_mode = (msel == 4 || (RUNTIME_MODE && msel == 5)) ? 2'd1
                            : ((!RUNTIME_MODE && msel == 5) ? 2'd2 : 2'd0);
    wire [15:0] lane_rgb;
    wire lane_white,lane_yellow;
    lane_detect #(.H_ACTIVE(H_ACTIVE), .V_ACTIVE(V_ACTIVE)) u_lane (
        .clk         ( clk               ),
        .rst_n       ( rst_n             ),
        .de          ( c_pix[16]         ),
        .vs          ( window_vs         ),
        .rgb_in      ( c_pix[15:0]       ),
        .luma_in     ( smooth_sum[11:4]  ),
        .base_in     ( display_rgb       ),
        .paint_mode  ( paint_mode        ),
        .rgb_out     ( lane_rgb          ),
        .de_out      ( lane_de           ),
        .vs_out      ( lane_vs           ),
        .white_mark  ( lane_white        ),
        .yellow_mark ( lane_yellow       )
    );

    wire [15:0] annotated_rgb;
    wire zebra_candidate,zebra_confirmed;
    wire [10:0] zebra_y0,zebra_y1;
    generate if (ZEBRA_ENABLE) begin : g_zebra
        wire result_valid, candidate, confirmed;
        wire [10:0] x0, y0, x1, y1;
        assign zebra_candidate=candidate;
        assign zebra_confirmed=confirmed;
        assign zebra_y0=y0;
        assign zebra_y1=y1;
        zebra_detect #(.H_ACTIVE(H_ACTIVE), .V_ACTIVE(V_ACTIVE)) u_detect (
            .clk(clk), .rst_n(rst_n), .de(c_pix[16]), .vs(window_vs),
            .rgb_in(c_pix[15:0]), .result_valid(result_valid),
            .candidate(candidate), .confirmed(confirmed),
            .box_x0(x0), .box_y0(y0), .box_x1(x1), .box_y1(y1), .stripes()
        );
        zebra_overlay #(.H_ACTIVE(H_ACTIVE), .V_ACTIVE(V_ACTIVE)) u_overlay (
            .clk(clk), .rst_n(rst_n), .de(lane_de), .vs(lane_vs),
            .enable(legacy_overlay), .rgb_in(lane_rgb),
            .result_valid(result_valid), .candidate(candidate), .confirmed(confirmed),
            .box_x0(x0), .box_y0(y0), .box_x1(x1), .box_y1(y1), .rgb_out(annotated_rgb)
        );
    end else begin : g_no_zebra
        assign annotated_rgb = lane_rgb;
        assign zebra_candidate=0;
        assign zebra_confirmed=0;
        assign zebra_y0=0;
        assign zebra_y1=0;
    end endgenerate

    wire [15:0] final_rgb;
    generate if(ADAS_ENABLE) begin : g_adas
        lane_geometry #(.H_ACTIVE(H_ACTIVE),.V_ACTIVE(V_ACTIVE)) u_geometry (
            .clk(clk),.rst_n(rst_n),.de(lane_de),.vs(lane_vs),
            .white_mark(lane_white),.yellow_mark(lane_yellow),
            .zebra_candidate(zebra_candidate),.zebra_confirmed(zebra_confirmed),
            .zebra_y0(zebra_y0),.zebra_y1(zebra_y1),
            .result_valid(adas_valid),.snapshot(adas_snapshot),
            .frame_id(),.flags(),.left_kind(),.right_kind(),.departure(),.offset_px(),.lane_width(),
            .left_x0(),.left_y0(),.left_x1(),.left_y1(),.right_x0(),.right_y0(),.right_x1(),.right_y1(),
            .left_support(),.right_support()
        );
        adas_overlay #(.H_ACTIVE(H_ACTIVE),.V_ACTIVE(V_ACTIVE)) u_overlay (
            .clk(clk),.rst_n(rst_n),.de(lane_de),.vs(lane_vs),.enable(legacy_overlay),
            .rgb_in(annotated_rgb),.result_valid(adas_valid),.snapshot(adas_snapshot),.rgb_out(final_rgb)
        );
    end else begin : g_no_adas
        assign adas_valid=0;
        assign adas_snapshot=0;
        assign final_rgb=annotated_rgb;
    end endgenerate

    always @(posedge clk) begin
        if (!rst_n) begin
            rgb_out <= 0;
            de_out <= 0;
            vs_out <= 0;
            display_frame_id <= 0;
            display_frame_time <= 0;
        end else begin
            rgb_out <= final_rgb;
            de_out <= lane_de;
            vs_out <= lane_vs;
            // At 1280 columns the buffered frame tag is stable long before
            // this delayed header; never borrow tags from raw input VS.
            if (lane_vs)
                {display_frame_time, display_frame_id} <= window_frame_tag;
        end
    end

endmodule
