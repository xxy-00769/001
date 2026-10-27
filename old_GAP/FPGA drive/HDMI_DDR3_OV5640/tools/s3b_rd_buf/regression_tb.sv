`timescale 1ns/1ps

// Extends the S2 oracle to consecutive frames and a between-frame reset.
// Uses the production rd_buf, generated line RAM and real Pango primitives.
module s3b_rd_buf_tb;
    reg grs_n = 0;
    GTP_GRS GRS_INST(.GRS_N(grs_n));
    initial #100 grs_n = 1;

    reg ddr_clk = 0, vout_clk = 0;
    always #5 ddr_clk = ~ddr_clk;
    always #13.468 vout_clk = ~vout_clk;

    reg ddr_rstn = 0, rd_fsync = 0, rd_en = 0;
    wire vout_de, ddr_rreq;
    wire [15:0] vout_data;
    wire [27:0] ddr_raddr;
    wire [31:0] ddr_rd_len;
    reg ddr_rdone = 0, ddr_rdata_en = 0;
    reg [255:0] ddr_rdata = 0;

    rd_buf #(
        .ADDR_WIDTH(28), .ADDR_OFFSET(0), .H_NUM(1280), .V_NUM(720),
        .DQ_WIDTH(32), .LEN_WIDTH(32), .PIX_WIDTH(16),
        .LINE_ADDR_WIDTH(22), .FRAME_CNT_WIDTH(6)
    ) dut(
        .ddr_clk(ddr_clk), .ddr_rstn(ddr_rstn), .vout_clk(vout_clk),
        .rd_fsync(rd_fsync), .rd_en(rd_en), .vout_de(vout_de), .vout_data(vout_data),
        .init_done(1'b1), .ddr_rreq(ddr_rreq), .ddr_raddr(ddr_raddr),
        .ddr_rd_len(ddr_rd_len), .ddr_rrdy(1'b1), .ddr_rdone(ddr_rdone),
        .ddr_rdata(ddr_rdata), .ddr_rdata_en(ddr_rdata_en)
    );

    function [15:0] pattern(input integer f, input integer x, input integer y);
        begin
            pattern = ((f * 16'h29a7) ^ (y * 16'h031d) ^ (x * 16'h9e37)) & 16'hffff;
        end
    endfunction

    integer frame_id = 0, bank_base = 0;
    integer requests = 0, completions = 0, beats = 0, pixels = 0;
    integer errors = 0, address_errors = 0, line_errors = 0, missing_rows = 0;
    integer closed_lines = 0, line_pixels = 0;
    integer row_pixels[0:719], row_errors[0:719], row_requests[0:719];
    integer total_requests = 0, total_completions = 0, total_beats = 0;
    integer total_pixels = 0, total_errors = 0, passed_frames = 0;
    integer request_fd, row_fd, frame_fd, mismatch_fd;
    integer request_row, request_addr, beat, lane, i, x, y;
    reg busy = 0, frame_active = 0;
    reg [15:0] expected;

    // Native-return BFM, not a DDR controller/PHY. Completion follows beat 80.
    initial begin
        request_fd = $fopen("requests.csv", "w");
        row_fd = $fopen("rows.csv", "w");
        frame_fd = $fopen("frames.csv", "w");
        mismatch_fd = $fopen("mismatches.csv", "w");
        if (!request_fd || !row_fd || !frame_fd || !mismatch_fd)
            $fatal(1, "Cannot open evidence files");
        $fdisplay(request_fd, "frame,index,time_ps,address,row,wr_line,length");
        $fdisplay(row_fd, "frame,row,pixels,errors,requests");
        $fdisplay(frame_fd, "frame,reset_before,requests,completions,beats,pixels,errors,last_row_errors,missing_rows,address_errors,de_lines,line_errors");
        $fdisplay(mismatch_fd, "frame,index,row,column,got,expected");
        forever begin
            @(posedge ddr_clk);
            if (ddr_rstn && ddr_rreq) begin
                if (!frame_active) $fatal(1, "Request outside a frame");
                busy <= 1;
                if (ddr_rd_len !== 32'd80)
                    $fatal(1, "Unexpected request length");
                if ($isunknown(ddr_raddr) || ddr_raddr < bank_base ||
                    ddr_raddr >= bank_base + 720 * 640)
                    $fatal(1, "Address outside selected frame");
                request_addr = ddr_raddr;
                request_row = (request_addr - bank_base) / 640;
                if (request_addr != bank_base + requests * 640)
                    address_errors = address_errors + 1;
                row_requests[request_row] = row_requests[request_row] + 1;
                $fdisplay(request_fd, "%0d,%0d,%0t,%0h,%0d,%0d,%0d",
                    frame_id, requests, $time, ddr_raddr, request_row,
                    dut.wr_line, ddr_rd_len);
                requests = requests + 1;
                repeat (3) @(negedge ddr_clk);
                for (beat = 0; beat < 80; beat = beat + 1) begin
                    for (lane = 0; lane < 16; lane = lane + 1)
                        ddr_rdata[lane*16 +: 16] = pattern(frame_id, beat*16 + lane, request_row);
                    ddr_rdata_en = 1;
                    @(negedge ddr_clk);
                end
                ddr_rdata_en = 0;
                ddr_rdone = 1;
                @(negedge ddr_clk);
                ddr_rdone = 0;
                busy <= 0;
            end
        end
    end

    always @(posedge ddr_clk) begin
        if (ddr_rstn) begin
            if (ddr_rreq && busy) $fatal(1, "Overlapping line requests");
            if (ddr_rdata_en) beats = beats + 1;
            if (ddr_rdone) completions = completions + 1;
        end
    end

    // Count actual DE segments independently of the requested raster.
    always @(posedge vout_clk) begin
        #2;
        if (ddr_rstn && frame_active) begin
            if (vout_de) begin
                if (closed_lines >= 720 || line_pixels >= 1280)
                    $fatal(1, "Extra DE line or pixel");
                expected = pattern(frame_id, line_pixels, closed_lines);
                row_pixels[closed_lines] = row_pixels[closed_lines] + 1;
                if (vout_data !== expected) begin
                    if (errors < 16)
                        $fdisplay(mismatch_fd, "%0d,%0d,%0d,%0d,%0h,%0h",
                            frame_id, pixels, closed_lines, line_pixels, vout_data, expected);
                    row_errors[closed_lines] = row_errors[closed_lines] + 1;
                    errors = errors + 1;
                end
                pixels = pixels + 1;
                line_pixels = line_pixels + 1;
            end else if (line_pixels != 0) begin
                if (line_pixels != 1280) line_errors = line_errors + 1;
                closed_lines = closed_lines + 1;
                line_pixels = 0;
            end
        end
    end

    task run_frame(input integer tag, input integer reset_before);
        begin
            if (busy || ddr_rdata_en || ddr_rdone)
                $fatal(1, "Previous frame has an unfinished return");
            frame_id = tag;
            // Existing frame bank counter persists through ddr_rstn.
            bank_base = (tag % 2) * 'h400000;
            requests = 0; completions = 0; beats = 0; pixels = 0;
            errors = 0; address_errors = 0; line_errors = 0; missing_rows = 0;
            closed_lines = 0; line_pixels = 0;
            for (i = 0; i < 720; i = i + 1) begin
                row_pixels[i] = 0; row_errors[i] = 0; row_requests[i] = 0;
            end
            frame_active = 1;
            rd_fsync = 1;
            repeat (1650 * 5) @(negedge vout_clk);
            rd_fsync = 0;
            repeat (1650 * 20) @(negedge vout_clk);
            for (y = 0; y < 720; y = y + 1) begin
                for (x = 0; x < 1280; x = x + 1) begin
                    rd_en = 1;
                    @(negedge vout_clk);
                end
                rd_en = 0;
                repeat (370) @(negedge vout_clk);
            end
            repeat (1650 * 5) @(negedge vout_clk);
            for (i = 0; i < 720; i = i + 1) begin
                if (row_requests[i] != 1) missing_rows = missing_rows + 1;
                if (row_pixels[i] != 1280) line_errors = line_errors + 1;
                $fdisplay(row_fd, "%0d,%0d,%0d,%0d,%0d",
                    tag, i, row_pixels[i], row_errors[i], row_requests[i]);
            end
            $fdisplay(frame_fd, "%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",
                tag, reset_before, requests, completions, beats, pixels, errors,
                row_errors[719], missing_rows, address_errors, closed_lines, line_errors);
            $display("S3B_FRAME frame=%0d reset_before=%0d requests=%0d completions=%0d beats=%0d pixels=%0d errors=%0d last_row_errors=%0d de_lines=%0d",
                tag, reset_before, requests, completions, beats, pixels,
                errors, row_errors[719], closed_lines);
            if (requests != 720 || completions != 720 || beats != 57600 ||
                pixels != 921600 || errors != 0 || missing_rows != 0 ||
                address_errors != 0 || closed_lines != 720 || line_errors != 0 ||
                line_pixels != 0 || busy)
                $fatal(1, "Full-frame regression failed in frame %0d", tag);
            passed_frames = passed_frames + 1;
            total_requests = total_requests + requests;
            total_completions = total_completions + completions;
            total_beats = total_beats + beats;
            total_pixels = total_pixels + pixels;
            total_errors = total_errors + errors;
            frame_active = 0;
        end
    endtask

    initial begin
        repeat (20) @(negedge ddr_clk);
        ddr_rstn = 1;
        repeat (9) @(negedge vout_clk);
        run_frame(1, 0);
        run_frame(2, 0);
        // Reset only between completed frames; no mid-line abort is claimed.
        ddr_rstn = 0;
        repeat (20) @(negedge ddr_clk);
        ddr_rstn = 1;
        repeat (9) @(negedge vout_clk);
        run_frame(3, 1);
        $display("S3B_RESULT frames=%0d requests=%0d completions=%0d beats=%0d pixels=%0d errors=%0d",
            passed_frames, total_requests, total_completions, total_beats,
            total_pixels, total_errors);
        $fclose(request_fd); $fclose(row_fd); $fclose(frame_fd); $fclose(mismatch_fd);
        $finish;
    end

    initial begin
        #110000000;
        $fatal(1, "Three-frame regression timed out");
    end
endmodule
