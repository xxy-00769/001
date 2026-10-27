`timescale 1ns/1ps
module m1_view_select(input clk,rst_n,frame_sync,view_request,
    output reg selected_view);
    reg [1:0] view_sync;
    reg fs_d;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin view_sync<=0; selected_view<=0; fs_d<=0; end
        else begin
            view_sync<={view_sync[0],view_request}; fs_d<=frame_sync;
            if(frame_sync && !fs_d) selected_view<=view_sync[1];
        end
    end
endmodule
