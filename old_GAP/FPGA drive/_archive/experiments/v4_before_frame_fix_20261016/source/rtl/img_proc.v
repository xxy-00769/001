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
    parameter DIAG_CYCLE = 0        // 1 = auto-cycle modes every 64 frames
)(
    input               clk,        // pixel_clk
    input               rst_n,
    input      [15:0]   rgb_in,     // {R[4:0], G[5:0], B[4:0]}
    input               de_in,
    input               vs_in,
    output reg [15:0]   rgb_out,
    output reg          de_out,
    output reg          vs_out
);

    localparam AW = 12;             // 2^12 = 4096 slots, must exceed LINE PERIOD

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

    //------------------------------------------------------------------------
    //  1. line buffer addressing
    //
    //  The address counter runs over the WHOLE line period (active pixels AND
    //  horizontal blanking) and EVERY clock is written into the buffer.  The
    //  line restarts on the rising edge of de.
    //
    //  Why this matters:
    //    If the counter only advanced on active pixels, the read port would
    //    keep returning the same de=1 pixel for the whole blanking interval,
    //    so the delayed de would stay high through blanking.  fram_buf would
    //    then see far more than H_NUM pixels per line, every line would be
    //    shifted a bit further, and the picture smears into horizontal bands.
    //
    //  The buffer is used as a ping-pong of two halves (par / ~par) so the
    //  write and read addresses can never collide, which makes the result
    //  independent of the RAM read/write ordering.
    //------------------------------------------------------------------------
    reg  [AW-1:0] addr;
    reg           par;
    reg           de_d;
    wire          line_start = de_in & ~de_d;

    // column / parity valid for THIS clock
    wire [AW-1:0] col   = line_start ? {AW{1'b0}} : addr;
    wire          par_n = line_start ? ~par         : par;

    always @(posedge clk) begin
        if (!rst_n) begin
            addr <= {AW{1'b0}};
            par  <= 1'b0;
            de_d <= 1'b0;
        end else begin
            de_d <= de_in;
            par  <= par_n;
            if (line_start) addr <= {{(AW-1){1'b0}}, 1'b1};
            else            addr <= addr + 1'b1;
        end
    end

    wire [AW:0] waddr1 = {par_n,  col};
    wire [AW:0] raddr1 = {~par_n, col};

    //------------------------------------------------------------------------
    //  2. line buffer 1  ->  q1 = same position, one line earlier
    //------------------------------------------------------------------------
    wire [16:0] pack = {de_in, rgb_in};

    reg  [16:0] lb1 [0:(1<<(AW+1))-1];
    reg  [16:0] q1;

    always @(posedge clk) begin
        lb1[waddr1] <= pack;
        q1 <= lb1[raddr1];
    end

    //------------------------------------------------------------------------
    //  3. line buffer 2  ->  q2 = two lines earlier
    //------------------------------------------------------------------------
    reg  [16:0] lb2 [0:(1<<(AW+1))-1];
    reg  [AW:0] raddr1_d;
    reg  [16:0] q2;

    always @(posedge clk) begin
        raddr1_d <= raddr1;
        lb2[raddr1_d] <= q1;
        q2 <= lb2[{~raddr1_d[AW], raddr1_d[AW-1:0]}];
    end

    //------------------------------------------------------------------------
    //  4. bring the three rows onto the same column
    //       row0 = current line      (pack delayed 2)
    //       row1 = one line earlier  (q1   delayed 1)
    //       row2 = two lines earlier (q2   delayed 1)
    //------------------------------------------------------------------------
    reg  [16:0] p0_d1, p0_d2, q1_d1, q2_d1;

    always @(posedge clk) begin
        p0_d1 <= pack;
        p0_d2 <= p0_d1;
        q1_d1 <= q1;
        q2_d1 <= q2;
    end

    wire [7:0] y0 = luma(p0_d2[15:0]);      // current line
    wire [7:0] y1 = luma(q1_d1[15:0]);      // one line earlier (window centre row)
    wire [7:0] y2 = luma(q2_d1[15:0]);      // two lines earlier

    // centre pixel (colour + its de), aligned with the 3x3 window centre
    reg  [16:0] c_pix;
    always @(posedge clk) c_pix <= q1_d1;

    //------------------------------------------------------------------------
    //  5. 3x3 window  (column shift registers)
    //------------------------------------------------------------------------
    reg [7:0] y0a, y0b, y1a, y1b, y2a, y2b;

    always @(posedge clk) begin
        y0a <= y0;  y0b <= y0a;
        y1a <= y1;  y1b <= y1a;
        y2a <= y2;  y2b <= y2a;
    end

    wire [7:0] w00 = y2b, w01 = y2a, w02 = y2;
    wire [7:0] w10 = y1b, w11 = y1a, w12 = y1;
    wire [7:0] w20 = y0b, w21 = y0a, w22 = y0;

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
    wire [2:0] msel = DIAG_CYCLE ? mode_sel : MODE_C;

    wire [15:0] col_sob = to565(sobel);
    wire [15:0] col_gry = to565(median);
    wire [15:0] col_lum = to565(w11);
    wire [15:0] col_r1  = to565(y1a);
    wire [15:0] col_r2  = to565(y2a);

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

    wire [1:0] paint_mode = (msel == 4) ? 2'd1 : ((msel == 5) ? 2'd2 : 2'd0);
    wire [15:0] lane_rgb;
    wire lane_de, lane_vs;
    lane_detect u_lane (
        .clk         ( clk               ),
        .rst_n       ( rst_n             ),
        .de          ( c_pix[16]         ),
        .vs          ( vs_in             ),
        .rgb_in      ( c_pix[15:0]       ),
        .luma_in     ( smooth_sum[11:4]  ),
        .base_in     ( display_rgb       ),
        .paint_mode  ( paint_mode        ),
        .rgb_out     ( lane_rgb          ),
        .de_out      ( lane_de           ),
        .vs_out      ( lane_vs           ),
        .white_mark  (                   ),
        .yellow_mark (                   )
    );

    always @(posedge clk) begin
        rgb_out <= lane_rgb;
        de_out <= lane_de;
        vs_out <= lane_vs;
    end

endmodule
