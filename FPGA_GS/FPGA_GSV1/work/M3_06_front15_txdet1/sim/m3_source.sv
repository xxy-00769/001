`timescale 1ns/1ps
module m3_source #(parameter SOURCE=0, parameter FRONT=0, parameter HEIGHT=16, parameter RASTER=0, parameter HD_DISPLAY=0)(
    input net_acquire,net_release,output net_grant,net_held,
    output [1:0] net_bank,output [31:0] net_id,net_time,latest_frame_id,
    input core_clk,video_clk,out_clk,rst_n,out_vs,out_de,selected,quarter,online,
    output [27:0] awaddr, araddr, output [3:0] awlen, arlen,
    output awvalid, arvalid, output [255:0] wdata,
    input awready,wready,wlast,arready,rvalid,rlast,
    input [255:0] rdata, output reg stall_reads=0, output reg finished=0, output reg bad_capture=0
);
    localparam W=1280, H=HEIGHT, OW=640, OH=HEIGHT/2;

    reg vs=0,de=0;
    reg [15:0] rgb=0;
    wire pipeline_running, clean_vs, clean_de;
    wire [15:0] clean_rgb;
    wire [31:0] open_id, open_time, clean_id, clean_time, result_id;
    wire result_valid;
    wire [7:0] result_errors;
    video_capture_status #(.SOURCE_ID(SOURCE),.H_ACTIVE(W),.V_ACTIVE(H),.REF_HZ(100000000), .TIMEOUT_MS(200)) monitor (
        .ref_clk(core_clk), .video_clk(video_clk), .rst_n(rst_n),
        .source_ready(online), .video_vs(vs), .video_de(de),
        .pipeline_rst_n(pipeline_running),
        .frame_open_id(open_id), .frame_open_time(open_time),
        .frame_result_valid(result_valid), .frame_result_id(result_id),
        .frame_result_errors(result_errors)
    );
    capture_pipe processor(.clk(video_clk),.rst_n(pipeline_running),
        .rgb(rgb),.vs(vs),.de(de),.frame_id(open_id),.frame_time(open_time),
        .out_rgb(clean_rgb),.out_vs(clean_vs),.out_de(clean_de),
        .out_id(clean_id),.out_time(clean_time));
    wire init_done, valid;
    wire [15:0] pixel;
    fram_buf #(.HD_DISPLAY(HD_DISPLAY),.M2_READER(1),.M3_FRONT(FRONT),.SOURCE_ID(SOURCE),.H_NUM(W),.V_NUM(H),.DISPLAY_HALF(1)) dut (
        .net_acquire(net_acquire),.net_release(net_release),.net_grant(net_grant),.net_held(net_held),.net_bank(net_bank),.net_id(net_id),.net_time(net_time),.latest_frame_id(latest_frame_id),
        .vin_clk(video_clk), .wr_fsync(clean_vs), .wr_en(clean_de), .wr_data(clean_rgb),
        .pipeline_running(pipeline_running),
        .wr_frame_id(clean_id), .wr_frame_time(clean_time),
        .source_result_valid(result_valid), .source_result_id(result_id),
        .source_result_errors(result_errors),
        .ddr_clk(core_clk), .ddr_rstn(rst_n), .init_done(init_done),
        .vout_clk(out_clk), .display_selected(selected),.display_quarter(quarter), .rd_fsync(out_vs), .rd_en(out_de),
        .vout_de(valid), .vout_data(pixel),
        .axi_awaddr(awaddr), .axi_awlen(awlen), .axi_awvalid(awvalid), .axi_awready(awready),
        .axi_wdata(wdata), .axi_wvalid(wvalid), .axi_wready(wready), .axi_wlast(wlast),
        .axi_bid(4'd0), .axi_araddr(araddr), .axi_arlen(arlen),
        .axi_arvalid(arvalid), .axi_arready(arready),
        .axi_rdata(rdata), .axi_rvalid(rvalid), .axi_rlast(rlast), .axi_rid(4'd0)
    );
    function [15:0] pattern(input integer tag, input integer row, input integer col);
        pattern=(SOURCE<<14)|(((tag*16'h19d7)^(row*16'h031d)^(col*16'h9e37))&16'h3fff);
    endfunction
    integer tag,y,x;
    initial begin
      wait(rst_n);repeat(SOURCE ? 83 : 40) @(negedge video_clk);
      forever begin
        while(!online) @(negedge video_clk);
        tag=open_id;vs=1;repeat(8) @(negedge video_clk);vs=0;
        repeat(20) @(negedge video_clk);
        for(y=0;y<H;y=y+1) begin
          for(x=0;x<W;x=x+1) begin de=1;rgb=pattern(tag,y,x);@(negedge video_clk);end
          de=0;repeat(RASTER ? (SOURCE==2 ? 370 : 612) : 100) @(negedge video_clk);
        end
        repeat(RASTER ? (SOURCE==2 ? 1650*30-28 : 1892*20-28) : 200) @(negedge video_clk);
      end
    end
endmodule
