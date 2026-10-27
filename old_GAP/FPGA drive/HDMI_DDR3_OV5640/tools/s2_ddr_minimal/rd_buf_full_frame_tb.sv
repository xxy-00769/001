`timescale 1ns/1ps

// Reuses road_video_ddr_20261017's clocks, GRS, frame geometry, pattern and
// post-NBA pixel sampling. Only rd_buf and its real vendor line RAM are DUT.
module s2_rd_buf_full_frame_tb;
    reg grs_n = 0;
    GTP_GRS GRS_INST(.GRS_N(grs_n));
    initial #100 grs_n = 1;

    reg ddr_clk = 0;
    reg vout_clk = 0;
    always #5 ddr_clk = ~ddr_clk;
    always #13.468 vout_clk = ~vout_clk;

    reg ddr_rstn = 0;
    reg rd_fsync = 0;
    reg rd_en = 0;
    wire vout_de;
    wire [15:0] vout_data;
    wire ddr_rreq;
    wire [27:0] ddr_raddr;
    wire [31:0] ddr_rd_len;
    reg ddr_rdone = 0;
    reg [255:0] ddr_rdata = 0;
    reg ddr_rdata_en = 0;

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

    integer requests = 0, completions = 0, beats = 0;
    integer pixels = 0, errors = 0, address_errors = 0;
    integer row_pixels[0:719], row_errors[0:719], row_requests[0:719];
    integer request_fd, row_fd, mismatch_fd;
    integer request_row, request_addr, beat, lane;
    integer x, y, i, out_x, out_y;
    integer missing_rows = 0, line_length_errors = 0;
    reg busy = 0;
    reg [15:0] expected;

    // A line-level native-return BFM, not a DDR controller or PHY model.
    // Every requested line gets exactly 80 valid beats and one completion
    // AFTER its final accepted beat. wr_cmd_trans is deliberately absent.
    initial begin
        request_fd = $fopen("requests.csv", "w");
        row_fd = $fopen("rows.csv", "w");
        mismatch_fd = $fopen("mismatches.csv", "w");
        if (!request_fd || !row_fd || !mismatch_fd)
            $fatal(1, "Cannot open evidence files");
        $fdisplay(request_fd, "index,time_ns,address,row,wr_line,length");
        $fdisplay(row_fd, "row,pixels,errors,requests");
        $fdisplay(mismatch_fd, "index,row,column,got,expected");
        for (i = 0; i < 720; i = i + 1) begin
            row_pixels[i] = 0;
            row_errors[i] = 0;
            row_requests[i] = 0;
        end
        forever begin
            @(posedge ddr_clk);
            if (ddr_rstn && ddr_rreq) begin
                busy <= 1;
                if (ddr_rd_len !== 32'd80)
                    $fatal(1, "Unexpected line length %0d", ddr_rd_len);
                if ($isunknown(ddr_raddr) || ddr_raddr < 28'h400000 ||
                    ddr_raddr >= 28'h400000 + 720 * 640)
                    $fatal(1, "Address outside the selected full-frame allocation");
                request_addr = ddr_raddr;
                request_row = (request_addr - 28'h400000) / 640;
                if (request_addr != 28'h400000 + requests * 640)
                    address_errors = address_errors + 1;
                row_requests[request_row] = row_requests[request_row] + 1;
                $fdisplay(request_fd, "%0d,%0t,%0h,%0d,%0d,%0d",
                    requests, $time, ddr_raddr, request_row, dut.wr_line, ddr_rd_len);
                requests = requests + 1;
                repeat (3) @(negedge ddr_clk);
                for (beat = 0; beat < 80; beat = beat + 1) begin
                    for (lane = 0; lane < 16; lane = lane + 1)
                        ddr_rdata[lane*16 +: 16] = pattern(1, beat*16 + lane, request_row);
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
            if (ddr_rreq && busy) $fatal(1, "Overlapping line request in isolated BFM");
            if (ddr_rdata_en) beats = beats + 1;
            if (ddr_rdone) completions = completions + 1;
        end
    end

    always @(posedge vout_clk) begin
        #2;
        if (ddr_rstn && vout_de) begin
            out_x = pixels % 1280;
            out_y = pixels / 1280;
            if (out_y >= 720) $fatal(1, "Too many output pixels");
            expected = pattern(1, out_x, out_y);
            row_pixels[out_y] = row_pixels[out_y] + 1;
            if (vout_data !== expected) begin
                if (errors < 16)
                    $fdisplay(mismatch_fd, "%0d,%0d,%0d,%0h,%0h",
                        pixels, out_y, out_x, vout_data, expected);
                row_errors[out_y] = row_errors[out_y] + 1;
                errors = errors + 1;
            end
            pixels = pixels + 1;
        end
    end

    initial begin
        repeat (20) @(negedge ddr_clk);
        ddr_rstn = 1;
        // Settle reset CDC before the first frame prefetch, as in the old asset.
        repeat (8) @(negedge vout_clk);
        @(negedge vout_clk);
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
            if (row_requests[i] == 0) missing_rows = missing_rows + 1;
            if (row_pixels[i] != 1280) line_length_errors = line_length_errors + 1;
            $fdisplay(row_fd, "%0d,%0d,%0d,%0d", i, row_pixels[i], row_errors[i], row_requests[i]);
        end
        $display("RD_BUF_RESULT requests=%0d completions=%0d beats=%0d pixels=%0d errors=%0d last_row_errors=%0d missing_rows=%0d address_errors=%0d line_length_errors=%0d",
            requests, completions, beats, pixels, errors, row_errors[719],
            missing_rows, address_errors, line_length_errors);
        if (requests == 720 && completions == 720 && beats == 57600 &&
            pixels == 921600 && errors == 0 && missing_rows == 0 &&
            address_errors == 0 && line_length_errors == 0)
            $display("PASS: all 720 rows and their pixels read");
        else
            $display("REJECT: full-frame/last-row read incomplete");
        $fclose(request_fd);
        $fclose(row_fd);
        $fclose(mismatch_fd);
        $finish;
    end

    initial begin
        #40000000;
        $fatal(1, "Testbench timeout before a full frame result");
    end
endmodule
