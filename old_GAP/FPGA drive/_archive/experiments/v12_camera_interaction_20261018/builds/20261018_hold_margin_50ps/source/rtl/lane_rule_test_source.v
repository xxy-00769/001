`timescale 1ns/1ps
// Synthetic, explicitly labelled rule input; not a camera detector.
module lane_rule_test_source #(
    parameter FRAMES_PER_SCENE = 120
) (
    input clk, rst_n, frame_start,
    output reg valid,
    output reg [255:0] snapshot
);
    localparam CW = FRAMES_PER_SCENE < 2 ? 1 : $clog2(FRAMES_PER_SCENE);
    reg [CW-1:0] count;
    reg [1:0] scene;
    reg [15:0] frame_id;
    always @(posedge clk) begin
        if (!rst_n) begin
            valid <= 0; snapshot <= 0; count <= 0; scene <= 0; frame_id <= 0;
        end else begin
            valid <= 0;
            if (frame_start) begin
                valid <= 1; frame_id <= frame_id + 1'b1;
                snapshot <= 0;
                snapshot[31:16] <= frame_id;
                snapshot[7:0] <= scene == 3 ? 8'h40 : 8'h47;
                case (scene)
                    0: snapshot[11:8] <= 4'ha; // Both dashed.
                    1: snapshot[11:8] <= 4'h9; // Left solid, right dashed.
                    2: snapshot[11:8] <= 4'h6; // Left dashed, right solid.
                    3: snapshot[11:8] <= 0;    // Unknown: no lane pair.
                endcase
                if (count == FRAMES_PER_SCENE-1) begin count <= 0; scene <= scene + 1'b1; end
                else count <= count + 1'b1;
            end
        end
    end
endmodule
