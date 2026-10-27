`timescale 1ns/1ps
// One frozen analysis frame, same clock only. Consumer releases before reuse.
// No inference, semantic mask, external transport, or video-output connection.
module road_input_buffer #(
    parameter H_ACTIVE=1280, V_ACTIVE=720, SCALE_LOG2=3
)(
    input clk, rst_n, de, vs,
    input [15:0] rgb,
    input release_frame, read_en,
    input [13:0] read_addr,
    output reg read_valid,
    output reg [15:0] read_data,
    output reg frame_available,
    output reg [31:0] frame_id,
    output reg [31:0] dropped_frames, invalid_frames
);
    localparam OUT_W=H_ACTIVE >> SCALE_LOG2;
    localparam OUT_H=V_ACTIVE >> SCALE_LOG2;
    localparam PIXELS=OUT_W*OUT_H;
    // synthesis translate_off
    initial begin
        if (SCALE_LOG2<1 || SCALE_LOG2>4 || H_ACTIVE<16 || V_ACTIVE<16
            || H_ACTIVE>2040 || V_ACTIVE>2040
            || H_ACTIVE%(1<<SCALE_LOG2)!=0 || V_ACTIVE%(1<<SCALE_LOG2)!=0
            || PIXELS>=16384)
            $fatal(1,"Unsupported road_input_buffer dimensions");
    end
    // synthesis translate_on
    wire pv, fs, fd, fe;
    wire [15:0] value;
    wire [10:0] px, py;
    road_thumbnail #(.H_ACTIVE(H_ACTIVE), .V_ACTIVE(V_ACTIVE), .SCALE_LOG2(SCALE_LOG2)) thumb (
        .clk(clk), .rst_n(rst_n), .de(de), .vs(vs), .rgb(rgb),
        .pixel_valid(pv), .pixel_rgb(value), .pixel_x(px), .pixel_y(py),
        .frame_start(fs), .frame_done(fd), .frame_error(fe)
    );
    reg [15:0] pixels [0:PIXELS-1];
    reg capturing, bad_order;
    reg [13:0] count;
    reg [10:0] expected_x, expected_y;
    reg [31:0] source_id;
    wire ordered=pv && px==expected_x && py==expected_y && count<PIXELS;
    wire publish=fd && capturing && !bad_order && count==PIXELS;
    always @(posedge clk) begin
        if (rst_n && capturing && ordered && !bad_order)
            pixels[count] <= value;
        if (rst_n && frame_available && read_en && !release_frame && read_addr<PIXELS)
            read_data <= pixels[read_addr];
        else
            read_data <= 0;
    end
    always @(posedge clk) begin
        if (!rst_n) begin
            read_valid<=0; frame_available<=0; frame_id<=0;
            dropped_frames<=0; invalid_frames<=0; source_id<=0;
            capturing<=0; bad_order<=0; count<=0; expected_x<=0; expected_y<=0;
        end else begin
            read_valid<=frame_available && read_en && !release_frame && read_addr<PIXELS;
            if (release_frame) frame_available<=0;
            if (pv && capturing) begin
                if (!ordered) bad_order<=1;
                else begin
                    count<=count+1'b1;
                    if (expected_x==OUT_W-1) begin expected_x<=0; expected_y<=expected_y+1'b1; end
                    else expected_x<=expected_x+1'b1;
                end
            end
            if (fe || (fd && capturing && !publish)) invalid_frames<=invalid_frames+1'b1;
            if (fd && !capturing) dropped_frames<=dropped_frames+1'b1;
            if (publish) begin
                frame_available<=1;
                frame_id<=source_id;
            end
            // Frame start and previous-frame commit normally coincide. A newly
            // published buffer is immutable; skip this new frame even if released.
            if (fs) begin
                source_id<=source_id+1'b1;
                capturing<=(!frame_available || release_frame) && !publish;
                bad_order<=0; count<=0; expected_x<=0; expected_y<=0;
            end else if (fd || fe) capturing<=0;
        end
    end
endmodule
