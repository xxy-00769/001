`timescale 1ns/1ps
module road_marking_tb;
    localparam W = 1280, H = 720, LATENCY = 207;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0, de = 0, vs = 0;
    reg [15:0] rgb = 0;
    reg [7:0] lum = 0;
    reg [1:0] mode = 1, expected_marks = 0;
    wire [15:0] result;
    wire result_de, result_vs, white, yellow;
    lane_detect dut (
        .clk(clk), .rst_n(rst_n), .de(de), .vs(vs), .rgb_in(rgb),
        .luma_in(lum), .base_in(rgb), .paint_mode(mode),
        .rgb_out(result), .de_out(result_de), .vs_out(result_vs),
        .white_mark(white), .yellow_mark(yellow)
    );

    reg [31:0] vectors [0:W*H-1];
    reg [1023:0] vector_path;
    reg [LATENCY-1:0] expected_de = 0, expected_vs = 0;
    reg [15:0] expected_rgb [0:LATENCY-1];
    reg [1:0] marks_pipe [0:LATENCY-1];
    reg [15:0] paint;
    integer i, errors = 0, checked = 0, white_count = 0, yellow_count = 0;
    integer col, row, index, mode_arg, switch_mode = 0;
    integer output_row, output_col;
    always @(posedge clk) begin
        if (!rst_n) begin
            expected_de <= 0;
            expected_vs <= 0;
            for (i = 0; i < LATENCY; i = i+1) begin
                expected_rgb[i] <= 0;
                marks_pipe[i] <= 0;
            end
        end else begin
            expected_de <= {expected_de[LATENCY-2:0], de};
            expected_vs <= {expected_vs[LATENCY-2:0], vs};
            paint = expected_marks[0] ? 16'h07FF : 16'h07E0;
            expected_rgb[0] <= (mode != 0 && expected_marks != 0)
                               ? paint : (mode == 2 ? 16'h0000 : rgb);
            marks_pipe[0] <= expected_marks;
            for (i = 1; i < LATENCY; i = i+1) begin
                expected_rgb[i] <= expected_rgb[i-1];
                marks_pipe[i] <= marks_pipe[i-1];
            end
        end
        #1;
        if (result_de !== expected_de[LATENCY-1] || result_vs !== expected_vs[LATENCY-1]) begin
            if (errors < 12) $display("Control mismatch at %t", $time);
            errors = errors + 1;
        end
        if (expected_de[LATENCY-1]) begin
            output_row = (checked % (W*H)) / W;
            output_col = checked % W;
            if (output_row < H/3 && (white !== 0 || yellow !== 0)) begin
                if (errors < 12)
                    $display("Upper-third overlay leak at (%0d,%0d)", output_col, output_row);
                errors = errors + 1;
            end
            checked = checked + 1;
            if (result !== expected_rgb[LATENCY-1]
                || {white,yellow} !== marks_pipe[LATENCY-1]) begin
                if (errors < 12)
                    $display("Pixel %0d: got %h mask %b, expected %h mask %b",
                             checked-1, result, {white,yellow},
                             expected_rgb[LATENCY-1], marks_pipe[LATENCY-1]);
                errors = errors + 1;
            end
            if (white) white_count = white_count + 1;
            if (yellow) yellow_count = yellow_count + 1;
        end else if (white !== 0 || yellow !== 0) begin
            errors = errors + 1;
        end
    end

    task idle;
        input integer clocks;
        integer n;
        begin
            for (n = 0; n < clocks; n = n+1) begin
                @(negedge clk);
                de = 0; rgb = 0; lum = 0; expected_marks = 0;
            end
        end
    endtask
    task frame_sync;
        begin
            idle(64);
            @(negedge clk); vs = 1;
            idle(4);
            @(negedge clk); vs = 0;
            idle(64);
        end
    endtask

    initial begin
        if (!$value$plusargs("VECTORS=%s", vector_path))
            $fatal(1, "Missing +VECTORS");
        if ($value$plusargs("MODE=%d", mode_arg)) mode = mode_arg;
        if ($value$plusargs("SWITCH_MODE=%d", switch_mode))
            $display("Per-pixel paint-mode switching: %0d", switch_mode);
        $readmemh(vector_path, vectors);
        idle(8);
        @(negedge clk); rst_n = 1;
        frame_sync;
        for (row = 0; row < H; row = row+1) begin
            for (col = 0; col < W; col = col+1) begin
                index = row*W + col;
                @(negedge clk);
                de = 1;
                rgb = vectors[index][31:16];
                lum = vectors[index][15:8];
                expected_marks = vectors[index][1:0];
                if (switch_mode) mode = (row + col/97) % 3;
            end
            idle(40);
        end
        // Reuse RAM without reset: a following blank scene must not retain marks.
        frame_sync;
        for (row = 0; row < H; row = row+1) begin
            for (col = 0; col < W; col = col+1) begin
                @(negedge clk);
                de = 1; rgb = 16'h4228; lum = 70; expected_marks = 0;
            end
            idle(40);
        end
        idle(LATENCY+8);
        if (checked != 2*W*H) $fatal(1, "Pixel count %0d", checked);
        if (errors != 0) $fatal(1, "%0d errors", errors);
        $display("PASS: %0d pixels, white=%0d yellow=%0d, mode=%0d",
                 checked, white_count, yellow_count, mode);
        $finish;
    end
endmodule
