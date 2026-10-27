`timescale 1ns/1ps

// Reuses img_proc_frame_tb's deterministic raster approach. The oracle is
// independent of the DUT's row banks and checks real DE segments and all edges.
module s4_clean_video_tb #(
    parameter H = 720,
    parameter FRAMES = 6,
    parameter COMPARE_DIAGNOSTICS = 0
);
    localparam W = 1280;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0, de = 0, vs = 0;
    reg [15:0] rgb = 0;
    wire [15:0] clean_rgb, compare_rgb, diagnostic_rgb;
    wire clean_de, clean_vs, compare_de, compare_vs, diagnostic_de, diagnostic_vs;

    img_proc #(.MODE(0), .H_ACTIVE(W), .V_ACTIVE(H)) baseline (
        .clk(clk), .rst_n(rst_n), .rgb_in(rgb), .de_in(de), .vs_in(vs),
        .clean_rgb_out(clean_rgb), .clean_de_out(clean_de), .clean_vs_out(clean_vs)
    );
    generate if (COMPARE_DIAGNOSTICS) begin : g_compare
        img_proc #(.MODE(4), .ZEBRA_ENABLE(1), .ADAS_ENABLE(1),
                   .H_ACTIVE(W), .V_ACTIVE(H)) diagnostics (
            .clk(clk), .rst_n(rst_n), .rgb_in(rgb), .de_in(de), .vs_in(vs),
            .clean_rgb_out(compare_rgb), .clean_de_out(compare_de), .clean_vs_out(compare_vs),
            .rgb_out(diagnostic_rgb), .de_out(diagnostic_de), .vs_out(diagnostic_vs)
        );
    end else begin : g_single
        assign compare_rgb = clean_rgb;
        assign compare_de = clean_de;
        assign compare_vs = clean_vs;
        assign diagnostic_rgb = 0;
        assign diagnostic_de = 0;
        assign diagnostic_vs = 0;
    end endgenerate

    function [15:0] sample(input integer f, input integer y, input integer x);
        begin
            case (f)
                0: sample = 16'hF800;
                1: sample = 16'h07E0;
                2: sample = 16'h001F;
                3: sample = ((x ^ y) & 1) ? 16'hFFFF : 16'h0000;
                4: sample = ((y * 16'h031d) ^ (x * 16'h9e37)) & 16'hffff;
                default: sample = ((f * 16'h29a7) ^ (y * 17) ^ (x * 31)) & 16'hffff;
            endcase
            if (f >= 4) begin
                if (y == 0) sample = 16'hA000 ^ x;
                if (y == H-1) sample = 16'h5000 ^ x;
                if (x == 0) sample = 16'hC000 ^ y;
                if (x == W-1) sample = 16'h3000 ^ y;
            end
        end
    endfunction

    integer output_frame = -1, pixels = 0, total_pixels = 0;
    integer rows = 0, row_pixels = 0, errors = 0, reset_checks = 0;
    integer diagnostic_frame = -1, diagnostic_pixels = 0, diagnostic_changes = 0;
    integer frames_checked = 0, row_fd, frame_fd, f, y, x;
    reg previous_vs = 0, previous_diagnostic_vs = 0;
    reg [15:0] expected;

    task check_frame;
        begin
            if (pixels != W*H || rows != H || row_pixels != 0)
                $fatal(1, "Frame %0d incomplete: pixels=%0d rows=%0d tail=%0d",
                    output_frame, pixels, rows, row_pixels);
            $fdisplay(frame_fd, "%0d,%0d,%0d,%0d", output_frame, pixels, rows, errors);
            $display("S4_FRAME frame=%0d pixels=%0d rows=%0d errors=%0d",
                output_frame, pixels, rows, errors);
            frames_checked = frames_checked + 1;
        end
    endtask

    always @(posedge clk) begin
        #1;
        if ({clean_vs,clean_de,clean_rgb} !== {compare_vs,compare_de,compare_rgb})
            $fatal(1, "Diagnostic configuration changed the clean stream");
        if (!rst_n) begin
            if ({clean_vs,clean_de,clean_rgb} !== 18'd0)
                $fatal(1, "Clean output not cleared during reset");
            reset_checks = reset_checks + 1;
            previous_vs = 0;
            previous_diagnostic_vs = 0;
        end else begin
            if (clean_vs) begin
                if (previous_vs || clean_de)
                    $fatal(1, "Frame marker is not one blank pixel clock");
                if (output_frame >= 0 && frames_checked != output_frame+1)
                    check_frame();
                output_frame = output_frame + 1;
                pixels = 0; rows = 0; row_pixels = 0;
            end
            if (previous_vs && !clean_de)
                $fatal(1, "First pixel does not follow its own frame marker");
            previous_vs = clean_vs;
            if (clean_de) begin
                if (output_frame < 0 || output_frame >= FRAMES || rows >= H || row_pixels >= W)
                    $fatal(1, "Unexpected pixel outside the full raster");
                expected = sample(output_frame, rows, row_pixels);
                if (clean_rgb !== expected) begin
                    if (errors < 8)
                        $display("Mismatch f=%0d y=%0d x=%0d got=%h expected=%h",
                            output_frame, rows, row_pixels, clean_rgb, expected);
                    errors = errors + 1;
                end
                pixels = pixels + 1;
                total_pixels = total_pixels + 1;
                row_pixels = row_pixels + 1;
            end else if (row_pixels != 0) begin
                if (row_pixels != W)
                    $fatal(1, "Wrong DE line length %0d", row_pixels);
                $fdisplay(row_fd, "%0d,%0d,%0d,%0d", output_frame, rows, row_pixels, errors);
                rows = rows + 1;
                row_pixels = 0;
            end
            if (COMPARE_DIAGNOSTICS) begin
                if (diagnostic_vs && !previous_diagnostic_vs) begin
                    diagnostic_frame = diagnostic_frame + 1;
                    diagnostic_pixels = 0;
                end
                previous_diagnostic_vs = diagnostic_vs;
                if (diagnostic_de) begin
                    if (diagnostic_frame < 0 || diagnostic_frame >= FRAMES || diagnostic_pixels >= W*H)
                        $fatal(1, "Unexpected legacy diagnostic pixel");
                    if (diagnostic_rgb !== sample(diagnostic_frame, diagnostic_pixels/W, diagnostic_pixels%W))
                        diagnostic_changes = diagnostic_changes + 1;
                    diagnostic_pixels = diagnostic_pixels + 1;
                end
            end
        end
    end

    task idle(input integer cycles);
        integer k;
        begin
            de = 0; rgb = 0;
            for (k = 0; k < cycles; k = k+1) @(negedge clk);
        end
    endtask

    initial begin
        row_fd = $fopen("rows.csv", "w");
        frame_fd = $fopen("frames.csv", "w");
        if (!row_fd || !frame_fd) $fatal(1, "Cannot create evidence CSV");
        $fdisplay(row_fd, "frame,row,pixels,cumulative_errors");
        $fdisplay(frame_fd, "frame,pixels,rows,cumulative_errors");
        repeat (16) @(negedge clk);
        rst_n = 1;
        // Unframed active pixels must not escape after startup.
        de = 1; rgb = 16'hDEAD;
        repeat (W+10) @(negedge clk);
        idle(16);
        for (f = 0; f < FRAMES; f = f+1) begin
            if (f == 3) begin
                check_frame();
                rst_n = 0;
                idle(16);
                rst_n = 1;
                idle(16);
            end
            vs = 1; idle(8);
            vs = 0; idle(10000);
            for (y = 0; y < H; y = y+1) begin
                for (x = 0; x < W; x = x+1) begin
                    de = 1; rgb = sample(f,y,x);
                    @(negedge clk);
                end
                idle(37 + (y%3)*7);
            end
            idle(20000);
        end
        check_frame();
        if (frames_checked != FRAMES || total_pixels != FRAMES*W*H || errors != 0)
            $fatal(1, "Wrong complete-frame totals");
        if (COMPARE_DIAGNOSTICS && diagnostic_changes == 0)
            $fatal(1, "Diagnostic comparison never exercised a painted/HUD pixel");
        $display("S4_RESULT frames=%0d pixels=%0d errors=%0d reset_checks=%0d diagnostic_changes=%0d",
            frames_checked, total_pixels, errors, reset_checks, diagnostic_changes);
        $fclose(row_fd); $fclose(frame_fd);
        $finish;
    end
    initial begin
        #100000000;
        $fatal(1, "Clean video regression timeout");
    end
endmodule

module s4_clean_fullframe_tb;
    s4_clean_video_tb test();
endmodule

module s4_clean_diagnostics_tb;
    s4_clean_video_tb #(.H(72), .FRAMES(2), .COMPARE_DIAGNOSTICS(1)) test();
endmodule
