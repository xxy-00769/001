`timescale 1ns/1ps
module img_proc_frame_tb;
    localparam W = 1280;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0, de = 0, vs = 0;
    reg [15:0] rgb = 0;
    wire [15:0] result;
    wire result_de, result_vs;
    img_proc #(.MODE(0), .DIAG_CYCLE(0)) dut (
        .clk(clk), .rst_n(rst_n), .rgb_in(rgb), .de_in(de), .vs_in(vs),
        .rgb_out(result), .de_out(result_de), .vs_out(result_vs)
    );

    integer rows = 12, frame, row, col, n;
    integer output_frame = -1, count = 0, errors = 0, checked = 0;
    reg previous_vs = 0;
    reg [15:0] expected;
    function [15:0] sample;
        input integer f, y, x;
        begin
            sample = ((f+1)*16'h2137) ^ (y*17) ^ (x*31);
        end
    endfunction

    always @(posedge clk) begin
        #1;
        if (rst_n) begin
            if (result_vs && !previous_vs) begin
                if (output_frame >= 0 && count != W*rows) begin
                    $display("Frame %0d: got %0d pixels, expected %0d",
                             output_frame, count, W*rows);
                    errors = errors + 1;
                end
                output_frame = output_frame + 1;
                count = 0;
            end
            previous_vs = result_vs;
            if (result_de === 1'b1 && output_frame >= 0) begin
                expected = sample(output_frame, count/W, count%W);
                if (count >= W*rows || result !== expected) begin
                    if (errors < 8)
                        $display("Frame %0d pixel %0d: got %h, expected %h",
                                 output_frame, count, result, expected);
                    errors = errors + 1;
                end
                count = count + 1;
                checked = checked + 1;
            end
        end
    end

    task idle;
        input integer cycles;
        integer k;
        begin
            for (k = 0; k < cycles; k = k+1) begin
                @(negedge clk);
                de = 0;
                rgb = 0;
            end
        end
    endtask

    task frame_sync;
        begin
            @(negedge clk); vs = 1;
            idle(8);
            @(negedge clk); vs = 0;
            idle(10000);
        end
    endtask

    initial begin
        if ($value$plusargs("ROWS=%d", rows))
            $display("Testing %0d rows per frame", rows);
        idle(16);
        @(negedge clk); rst_n = 1;
        for (frame = 0; frame < 3; frame = frame+1) begin
            frame_sync;
            for (row = 0; row < rows; row = row+1) begin
                for (col = 0; col < W; col = col+1) begin
                    @(negedge clk);
                    de = 1;
                    rgb = sample(frame, row, col);
                end
                idle(612 + (row%3)*7);
            end
            idle(20000);
        end
        frame_sync;
        if (count != 0) $fatal(1, "Pixels emitted without a new frame: %0d", count);
        if (errors != 0) $fatal(1, "%0d frame integrity errors", errors);
        $display("PASS: %0d unchanged pixels across 3 frames, no blanking ghosts", checked);
        $finish;
    end
endmodule
