`timescale 1ns/1ps
// Shared by the board top and full-size integration verification.
module m31_video_output #(parameter DISPLAY_GAIN_ENABLE=1,PROCESSING_ENABLE=1)(
 input clk,rst_n,timing_rst_n,input [2:0] selected_view,input [2:0] selected_mode,
 input [63:0] source_rgb,input [3:0] source_de,show_video,
 input [2:0] feedback,input hint_visible,input [3:0] hint_code,
 output frame_sync,output [3:0] source_selected,source_request,
 output reg hs_out,vs_out,de_out,output reg [23:0] rgb_out);
 wire quad=selected_view==4;
 wire read_request,panel_hs,panel_vs,panel_de,panel_image;
 wire [10:0] panel_x,raw_x;wire [10:0] panel_y,raw_y;
 m31_timing timing_panel(.clk(clk),.rst_n(timing_rst_n),.quad(quad),
  .frame_sync(frame_sync),.read_request(read_request),.hs(panel_hs),.vs(panel_vs),
  .de(panel_de),.image_area(panel_image),
  .active_x(panel_x),.active_y(panel_y),.raw_x(raw_x),.raw_y(raw_y));
 assign source_selected=quad ? 4'b1111 : (4'b0001<<selected_view);
 assign source_request[0]=read_request && (quad ? raw_y<540 && raw_x<960 : selected_view==0);
 assign source_request[1]=read_request && (quad ? raw_y<540 && raw_x>=960 : selected_view==1);
 assign source_request[2]=read_request && (quad ? raw_y>=540 && raw_x<960 : selected_view==2);
 assign source_request[3]=read_request && (quad ? raw_y>=540 && raw_x>=960 : selected_view==3);
 wire [1:0] pixel_source=quad ? (panel_y<540 ? (panel_x<960 ? 0 : 1) : (panel_x<960 ? 2 : 3)) : selected_view[1:0];
    wire [15:0] selected_rgb=source_de[pixel_source] && show_video[pixel_source]
            ? source_rgb[pixel_source*16+:16] : 16'd0;
    wire [23:0] display_rgb;
    m1_display_gain #(.ENABLE(DISPLAY_GAIN_ENABLE)) display_gain(
        .rgb(selected_rgb),.bypass(1'b0),.adjusted(display_rgb));
    wire [23:0] processed_rgb;
    wire phs,pvs,pde,pimage;wire [10:0] px;wire [10:0] py;
    generate if(PROCESSING_ENABLE) begin: processing_enabled
    m31_processing process_display(.clk(clk),.rst_n(rst_n),.rgb(display_rgb),
        .hs(panel_hs),.vs(panel_vs),.de(panel_de),.image(panel_image),.x(panel_x),.y(panel_y),
        .quad(quad),.mode(PROCESSING_ENABLE ? selected_mode : 3'd0),.out_rgb(processed_rgb),.out_hs(phs),.out_vs(pvs),
        .out_de(pde),.out_image(pimage),.out_x(px),.out_y(py));
    end else begin: processing_bypass
        // Exactly four registers for pixels AND all metadata. No filter instance.
        reg [49:0] delay[0:3]; integer k;
        always @(posedge clk or negedge rst_n) begin
            if(!rst_n) for(k=0;k<4;k=k+1) delay[k]<=0;
            else begin
                delay[0]<={display_rgb,panel_hs,panel_vs,panel_de,panel_image,panel_x,panel_y};
                for(k=1;k<4;k=k+1) delay[k]<=delay[k-1];
            end
        end
        assign {processed_rgb,phs,pvs,pde,pimage,px,py}=delay[3];
    end endgenerate
    wire osd_area,osd_pixel;
    m31_osd osd(.x(px),.y(py),.view(selected_view),.mode(PROCESSING_ENABLE ? selected_mode : 3'd0),
        .hint_visible(hint_visible),.hint_code(hint_code),.video_good(show_video),.feedback(feedback),
        .area(osd_area),.pixel(osd_pixel));
    always @(posedge clk) begin
        vs_out<=pvs;hs_out<=phs;de_out<=pde;
        if(pde && osd_area) rgb_out<=osd_pixel ? ((feedback>=3 && py>=1052) ? 24'hff3030 : 24'hffff00) : 0;
        else if(pimage) rgb_out<=processed_rgb;
        else rgb_out<=0;
    end

endmodule
