`timescale 1ns/1ps
// Independent analysis branch. Never replaces or filters the display stream.
// Each output is the floor of a SCALE x SCALE RGB888 box mean, then RGB565.
// A frame is committed only at the next clean VS edge after exact dimensions.
module road_thumbnail #(
    parameter H_ACTIVE = 1280,
    parameter V_ACTIVE = 720,
    parameter SCALE_LOG2 = 3
)(
    input clk, rst_n, de, vs,
    input [15:0] rgb,
    output reg pixel_valid,
    output reg [15:0] pixel_rgb,
    output reg [10:0] pixel_x, pixel_y,
    output reg frame_start, frame_done, frame_error
);
    localparam SCALE = 1 << SCALE_LOG2;
    localparam OUT_W = H_ACTIVE >> SCALE_LOG2;
    localparam HS_BITS = 8 + SCALE_LOG2;
    localparam SUM_BITS = 8 + 2*SCALE_LOG2;
    reg [10:0] x, y;
    reg de_d, vs_d, active, bad;
    wire start = vs && !vs_d;
    wire row_end = de_d && !de;
    wire [7:0] r = {rgb[15:11], rgb[15:13]};
    wire [7:0] g = {rgb[10:5], rgb[10:9]};
    wire [7:0] b = {rgb[4:0], rgb[4:2]};
    reg [HS_BITS-1:0] hr, hg, hb;
    wire [HS_BITS-1:0] next_hr = (x[SCALE_LOG2-1:0] == 0) ? r : hr + r;
    wire [HS_BITS-1:0] next_hg = (x[SCALE_LOG2-1:0] == 0) ? g : hg + g;
    wire [HS_BITS-1:0] next_hb = (x[SCALE_LOG2-1:0] == 0) ? b : hb + b;
    reg [3*SUM_BITS-1:0] sums [0:OUT_W-1];
    reg [3*SUM_BITS-1:0] previous_sum;
    reg pending, first_row, last_row;
    reg [10:0] block_x, block_y;
    reg [HS_BITS-1:0] pr, pg, pb;
    wire [SUM_BITS-1:0] old_r = first_row ? 0 : previous_sum[3*SUM_BITS-1:2*SUM_BITS];
    wire [SUM_BITS-1:0] old_g = first_row ? 0 : previous_sum[2*SUM_BITS-1:SUM_BITS];
    wire [SUM_BITS-1:0] old_b = first_row ? 0 : previous_sum[SUM_BITS-1:0];
    wire [SUM_BITS-1:0] total_r = old_r + pr;
    wire [SUM_BITS-1:0] total_g = old_g + pg;
    wire [SUM_BITS-1:0] total_b = old_b + pb;
    // Synchronous RAM ports; the first row of every block overwrites old sums.
    always @(posedge clk) begin
        if (rst_n && active && de && !vs && x < H_ACTIVE && y < V_ACTIVE)
            previous_sum <= sums[x >> SCALE_LOG2];
        if (rst_n && pending && !start)
            sums[block_x] <= {total_r, total_g, total_b};
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            x<=0; y<=0; de_d<=0; vs_d<=0; active<=0; bad<=0;
            hr<=0; hg<=0; hb<=0; pending<=0; first_row<=0; last_row<=0;
            pr<=0; pg<=0; pb<=0; block_x<=0; block_y<=0;
            pixel_valid<=0; pixel_rgb<=0; pixel_x<=0; pixel_y<=0;
            frame_start<=0; frame_done<=0; frame_error<=0;
        end else begin
            de_d<=de; vs_d<=vs;
            pixel_valid<=0; frame_start<=0; frame_done<=0; frame_error<=0;
            pending<=0;
            if (pending && !start && !bad) begin
                if (last_row) begin
                    pixel_valid<=1;
                    pixel_x<=block_x; pixel_y<=block_y;
                    pixel_rgb<={total_r[SUM_BITS-1:2*SCALE_LOG2+3],
                                total_g[SUM_BITS-1:2*SCALE_LOG2+2],
                                total_b[SUM_BITS-1:2*SCALE_LOG2+3]};
                end
            end
            if (start) begin
                frame_done<=active && !bad && y==V_ACTIVE && x==0 && !de;
                frame_error<=de || (active && (bad || y!=V_ACTIVE || x!=0));
                frame_start<=!de;
                active<=!de; bad<=de;
                x<=0; y<=0; hr<=0; hg<=0; hb<=0;
            end else if (active) begin
                if (vs && de) bad<=1;
                if (!vs && de) begin
                    if (x<2047) x<=x+1'b1;
                    if (x>=H_ACTIVE || y>=V_ACTIVE) bad<=1;
                    else if (!bad) begin
                        hr<=next_hr; hg<=next_hg; hb<=next_hb;
                        if (x[SCALE_LOG2-1:0]==SCALE-1) begin
                            pending<=1;
                            pr<=next_hr; pg<=next_hg; pb<=next_hb;
                            block_x<=x >> SCALE_LOG2;
                            block_y<=y >> SCALE_LOG2;
                            first_row<=y[SCALE_LOG2-1:0]==0;
                            last_row<=y[SCALE_LOG2-1:0]==SCALE-1;
                        end
                    end
                end
                if (row_end && !vs) begin
                    if (x!=H_ACTIVE || y>=V_ACTIVE) bad<=1;
                    x<=0;
                    if (y<2047) y<=y+1'b1;
                end
            end
        end
    end
endmodule
