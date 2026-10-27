`timescale 1ns/1ps
// MPI7001 EDID DTD: 800/16/80/96, 480/1/3/13, +HS/-VS.
// 29.545454 MHz gives 59.9272 Hz (EDID nominal 29.57 MHz).
// The 720p stored frame is read as 640x360, centred at (80,60).
module mpi7001_timing (
    input wire clk, rst_n,
    output wire frame_sync, read_request,
    output wire hs, vs, de, image_area
);
    reg [9:0] h;
    reg [8:0] v;
    wire active = h >= 176 && h < 976 && v >= 16 && v < 496;
    wire image = h >= 256 && h < 896 && v >= 76 && v < 436;
    // Match rd_buf's two-cycle read enable / data path latency.
    reg [1:0] hs_d, vs_d, de_d, image_d;
    assign frame_sync = v < 3;
    assign read_request = rst_n && image;
    assign hs = hs_d[1];
    assign vs = vs_d[1];
    assign de = de_d[1];
    assign image_area = image_d[1];
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            h <= 0; v <= 0;
            hs_d <= 0; vs_d <= 3; de_d <= 0; image_d <= 0;
        end else begin
            if (h == 991) begin
                h <= 0;
                if (v == 496) v <= 0; else v <= v + 1'b1;
            end else h <= h + 1'b1;
            hs_d <= {hs_d[0], h < 80};
            vs_d <= {vs_d[0], !(v < 3)};
            de_d <= {de_d[0], active};
            image_d <= {image_d[0], image};
        end
    end
endmodule
