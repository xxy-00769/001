`timescale 1ns/1ps
// Small tuple delay lets the raw geometry verdict arrive before the next VS
// reaches the owner. Pixel data, VS/DE and opening frame tags remain aligned.
module capture_pipe(input clk, rst_n, input vs, de, input [15:0] rgb,
    input [31:0] frame_id, frame_time,
    output out_vs, out_de, output [15:0] out_rgb,
    output [31:0] out_id, out_time);
    reg [1:0] vs_d, de_d;
    reg [15:0] rgb_d[0:1];
    reg [31:0] id_d[0:1], time_d[0:1];
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            vs_d<=0; de_d<=0;
            for(i=0;i<2;i=i+1) begin rgb_d[i]<=0; id_d[i]<=0; time_d[i]<=0; end
        end else begin
            vs_d<={vs_d[0],vs}; de_d<={de_d[0],de};
            rgb_d[0]<=rgb; rgb_d[1]<=rgb_d[0];
            id_d[0]<=frame_id; id_d[1]<=id_d[0];
            time_d[0]<=frame_time; time_d[1]<=time_d[0];
        end
    end
    assign out_vs=vs_d[1]; assign out_de=de_d[1]; assign out_rgb=rgb_d[1];
    assign out_id=id_d[1]; assign out_time=time_d[1];
endmodule
