`timescale 1ns/1ps
// MPI7001 EDID DTD: 800/16/80/96, 480/1/3/13, +HS/-VS.
// 29.545454 MHz gives 59.9272 Hz (EDID nominal 29.57 MHz).
// The 720p stored frame is read as 640x360, centred at (80,60).
module mpi7001_timing (
    input wire clk, rst_n,
    output wire frame_sync, read_request,
    output wire hs, vs, de, image_area,
    output wire [23:0] diagnostic_rgb
);
    reg [9:0] h;
    reg [8:0] v;
    wire active = h >= 176 && h < 976 && v >= 16 && v < 496;
    wire image = h >= 256 && h < 896 && v >= 76 && v < 436;
    // Match rd_buf's two-cycle read enable / data path latency.
    reg [1:0] hs_d, vs_d, de_d, image_d;
    // A low level during reset guarantees a first SOF edge to rd_buf.
    assign frame_sync = rst_n && v < 3;
    assign read_request = rst_n && image;
    assign hs = hs_d[1];
    assign vs = vs_d[1];
    assign de = de_d[1];
    assign image_area = image_d[1];
    // Independent display-path probes in the unused margins; no DDR/camera data.
    reg [23:0] probe, probe_d0, probe_d1;
    assign diagnostic_rgb = probe_d1;
    always @(*) begin
        probe = 24'h000000;
        if (active && v >= 24 && v < 56) begin
            if      (h < 276) probe = 24'hffffff;
            else if (h < 376) probe = 24'hffff00;
            else if (h < 476) probe = 24'h00ffff;
            else if (h < 576) probe = 24'h00ff00;
            else if (h < 676) probe = 24'hff00ff;
            else if (h < 776) probe = 24'hff0000;
            else if (h < 876) probe = 24'h0000ff;
        end else if (active && v >= 456 && v < 488)
            probe = (h[0] ^ v[0]) ? 24'hffffff : 24'h000000;
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            h <= 0; v <= 0;
            hs_d <= 0; vs_d <= 3; de_d <= 0; image_d <= 0;
            probe_d0 <= 0; probe_d1 <= 0;
        end else begin
            if (h == 991) begin
                h <= 0;
                if (v == 496) v <= 0; else v <= v + 1'b1;
            end else h <= h + 1'b1;
            hs_d <= {hs_d[0], h < 80};
            vs_d <= {vs_d[0], !(v < 3)};
            de_d <= {de_d[0], active};
            image_d <= {image_d[0], image};
            probe_d0 <= probe; probe_d1 <= probe_d0;
        end
    end
endmodule
