`timescale 1ns/1ps
module img_proc_overlay_tb;
    localparam W = 1280, H = 720;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0, de = 0, vs = 0;
    reg [15:0] rgb = 0;
    wire [15:0] result;
    wire result_de, result_vs;
    img_proc #(.MODE(4), .DIAG_CYCLE(0)) dut (
        .clk(clk), .rst_n(rst_n), .rgb_in(rgb), .de_in(de), .vs_in(vs),
        .rgb_out(result), .de_out(result_de), .vs_out(result_vs)
    );
    reg [31:0] vectors [0:W*H-1];
    reg [1023:0] vector_path;
    reg previous_vs = 0, previous_input_vs = 0;
    reg [15:0] expected_rgb;
    reg [1:0] expected_marks, actual_marks;
    integer input_frame = -1, output_frame = -1;
    integer prepared = 0, count = 0, checked = 0, errors = 0;
    integer white_count = 0, yellow_count = 0;
    integer frame, row, col;

    always @(posedge clk) begin
        if (rst_n) begin
            if (dut.window_vs && !previous_input_vs) begin
                input_frame = input_frame + 1;
                prepared = 0;
            end
            previous_input_vs = dut.window_vs;
            if (dut.c_pix[16]) begin
                if (dut.u_lane.x !== prepared%W || dut.u_lane.y !== prepared/W) begin
                    if (errors < 8)
                        $display("ROI coordinates differ at pixel %0d: x=%0d y=%0d",
                                 prepared, dut.u_lane.x, dut.u_lane.y);
                    errors = errors + 1;
                end
                if (input_frame == 0 && prepared < W*H
                    && (dut.c_pix[15:0] !== vectors[prepared][31:16]
                        || dut.smooth_sum[11:4] !== vectors[prepared][15:8])) begin
                    if (errors < 8)
                        $display("Window mismatch at %0d: rgb=%h luma=%d expected=%h/%d",
                                 prepared, dut.c_pix[15:0], dut.smooth_sum[11:4],
                                 vectors[prepared][31:16], vectors[prepared][15:8]);
                    errors = errors + 1;
                end
                prepared = prepared + 1;
            end
        end
        actual_marks = {dut.u_lane.white_mark, dut.u_lane.yellow_mark};
        #1;
        if (rst_n) begin
            if (result_vs && !previous_vs) begin
                if (output_frame >= 0 && count != W*H) begin
                    $display("Frame %0d: got %0d pixels, expected %0d", output_frame, count, W*H);
                    errors = errors + 1;
                end
                output_frame = output_frame + 1;
                count = 0;
            end
            previous_vs = result_vs;
            if (result_de === 1'b1) begin
                if (output_frame == 0 && count < W*H) begin
                    expected_marks = vectors[count][1:0];
                    expected_rgb = expected_marks[0] ? 16'h07FF
                                    : (expected_marks[1] ? 16'h07E0 : vectors[count][31:16]);
                end else begin
                    expected_marks = 0;
                    expected_rgb = 16'h4228;
                end
                if (output_frame < 0 || output_frame > 1 || count >= W*H
                    || result !== expected_rgb || actual_marks !== expected_marks) begin
                    if (errors < 8)
                        $display("Frame %0d pixel %0d: got %h/%b expected %h/%b",
                                 output_frame, count, result, actual_marks,
                                 expected_rgb, expected_marks);
                    errors = errors + 1;
                end
                if (count/W < H*9/16 && actual_marks !== 0) begin
                    if (errors < 8) $display("Overlay above ROI at pixel %0d", count);
                    errors = errors + 1;
                end
                if (actual_marks[1]) white_count = white_count + 1;
                if (actual_marks[0]) yellow_count = yellow_count + 1;
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
                @(negedge clk); de = 0; rgb = 0;
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
        if (!$value$plusargs("VECTORS=%s", vector_path)) $fatal(1, "Missing VECTORS");
        $readmemh(vector_path, vectors);
        idle(16);
        @(negedge clk); rst_n = 1;
        for (frame = 0; frame < 2; frame = frame+1) begin
            frame_sync;
            for (row = 0; row < H; row = row+1) begin
                for (col = 0; col < W; col = col+1) begin
                    @(negedge clk);
                    de = 1;
                    rgb = (frame == 0) ? vectors[row*W+col][31:16] : 16'h4228;
                end
                idle(612 + (row%3)*7);
            end
            idle(20000);
        end
        frame_sync;
        if (errors != 0 || checked != 2*W*H || count != W*H || output_frame != 1)
            $fatal(1, "%0d errors, %0d compared pixels, frame %0d count %0d",
                   errors, checked, output_frame, count);
        $display("PASS: %0d pixels; full RGB/window/ROI/overlay check; white=%0d yellow=%0d",
                 checked, white_count, yellow_count);
        $finish;
    end
endmodule
