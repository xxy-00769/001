`timescale 1ns/1ps
// One whole convolution layer over a tagged, single-outstanding 128-bit memory
// protocol. Addresses are WORD addresses, not vendor DDR byte addresses.
module conv_layer_dma (
    input clk, rst_n,
    input cfg_valid, output cfg_ready,
    input [319:0] cfg_descriptor,
    output busy, output reg fault, output reg [7:0] fault_code,
    output reg done, output reg [31:0] result_job_id,
    output mem_req_valid, input mem_req_ready,
    output mem_req_write, output [31:0] mem_req_addr,
    output [127:0] mem_req_data, output [15:0] mem_req_strb,
    output [63:0] mem_req_tag,
    input mem_rsp_valid, output mem_rsp_ready,
    input [127:0] mem_rsp_data, input [63:0] mem_rsp_tag, input mem_rsp_error
);
localparam IDLE=0, GEOMETRY=1, SIZES=2, ENDS=3, RANGES=4,
    TILE=5, TILE_GEOM=6, CAPACITY=7, CORE_CFG=8, LINEAR_ADDR=9,
    IN_COORD=10, IN_ROW=11, IN_ADDR=12, READ_REQ=13, READ_WAIT=14,
    LOAD_WORD=15, CORE_START=16, OUT_PREP=17, COLLECT=18,
    OUT_ROW=19, OUT_ADDR=20, WRITE_REQ=21, WRITE_WAIT=22, TILE_DONE=23,
    GEOM_PREP=24, GEOM_SHAPE=25, SIZE_ROW=26, TILE_PLANE=27, HALT=31;
reg [4:0] state;
reg [31:0] job_id, input_base, output_base, weight_base, param_base, arena_base, arena_limit;
reg [6:0] ci, co;
reg [1:0] kernel, stride;
reg [3:0] dilation;
reg [4:0] pad;
reg [9:0] input_w, input_h, output_w, output_h;
reg depthwise, reserved_bad;
reg [2:0] input_groups, output_groups;
reg [15:0] input_tail, output_tail;
reg [9:0] weight_plane;
reg [12:0] input_rows, output_rows;
reg [5:0] receptive;
reg [11:0] padded_w, padded_h, available_w, available_h;
reg [31:0] input_words, output_words, weight_words, param_words;
reg [32:0] input_end, output_end, weight_end, param_end;
reg [9:0] tile_x, tile_y;
reg [2:0] tile_w, tile_h;
reg [4:0] tile_iw, tile_ih;
reg [9:0] tile_plane;
reg [4:0] tile_area;
reg [11:0] tile_words;
reg reuse_tile, core_done_seen;
reg [1:0] load_kind;
reg [11:0] load_index;
reg [9:0] load_pos;
reg [2:0] load_group;
reg [4:0] input_x, input_y;
reg signed [13:0] gx, gy;
reg [12:0] input_row;
reg [31:0] request_addr, request_sequence;
reg [63:0] pending_tag;
reg [127:0] load_data, packet, write_data;
reg [15:0] write_keep;
reg [2:0] out_group, out_x, out_y;
reg [3:0] out_lane;
reg [15:0] expected_index;
reg [12:0] output_row;

wire [12:0] required_ow = (stride==2 ? {1'b0,available_w}>>1 : {1'b0,available_w})+1'b1;
wire [12:0] required_oh = (stride==2 ? {1'b0,available_h}>>1 : {1'b0,available_h})+1'b1;
wire geometry_ok = ci>0 && ci<=80 && co>0 && co<=80 && kernel>0 && kernel<=3 &&
    stride>0 && stride<=2 && dilation>0 && dilation<=8 && pad<=16 &&
    input_w>0 && input_h>0 && output_w>0 && output_h>0 &&
    padded_w>=receptive && padded_h>=receptive &&
    output_w==required_ow && output_h==required_oh && (!depthwise || ci==co);
wire ranges_ok = arena_base<arena_limit && input_base>=arena_base && output_base>=arena_base &&
    weight_base>=arena_base && param_base>=arena_base &&
    input_end<={1'b0,arena_limit} && output_end<={1'b0,arena_limit} &&
    weight_end<={1'b0,arena_limit} && param_end<={1'b0,arena_limit} &&
    ({1'b0,output_base}>=input_end || {1'b0,input_base}>=output_end) &&
    ({1'b0,output_base}>=weight_end || {1'b0,weight_base}>=output_end) &&
    ({1'b0,output_base}>=param_end || {1'b0,param_base}>=output_end);
wire [31:0] tile_input_bytes = ci*tile_plane;
wire [31:0] logical_weight_bytes = co*weight_plane;
wire [15:0] load_keep = load_kind==0 ? (load_group==input_groups-1 ? input_tail : 16'hffff) :
    (load_group==output_groups-1 ? output_tail : 16'hffff);
wire [11:0] load_limit = load_kind==0 ? tile_words : load_kind==1 ? weight_words[11:0] : param_words[11:0];
wire [9:0] load_plane = load_kind==1 ? weight_plane : 10'd14;
wire input_outside = gx<0 || gy<0 || gx>=$signed({4'd0,input_w}) || gy>=$signed({4'd0,input_h});
wire [6:0] out_channel_base = {out_group,4'd0};
wire [4:0] output_lanes = co-out_channel_base>=16 ? 5'd16 : co-out_channel_base;
wire last_output_word = out_group==output_groups-1 && out_x==tile_w-1 && out_y==tile_h-1;
wire last_tile = tile_x+tile_w==output_w && tile_y+tile_h==output_h;

wire core_cfg_ready, core_start_ready, core_busy, core_fault, core_done, core_out_valid, core_vec_ready;
wire core_cache_valid;
wire [31:0] core_cache_id;
wire [15:0] core_index;
wire [7:0] core_data;
wire signed [31:0] core_acc;
wire core_rst_n = rst_n && !fault;
conv_cached core (
    .clk(clk), .rst_n(core_rst_n),
    .cfg_valid(state==CORE_CFG), .cfg_ready(core_cfg_ready), .cfg_reuse(reuse_tile), .cfg_banked_load(1'b1),
    .cfg_weights_id(job_id), .cache_valid(core_cache_valid), .cached_weights_id(core_cache_id),
    .cfg_depthwise(depthwise), .cfg_ci(ci), .cfg_co(co), .cfg_kernel(kernel), .cfg_stride(stride),
    .cfg_dilation(dilation), .cfg_iw(tile_iw), .cfg_ih(tile_ih), .cfg_ow(tile_w), .cfg_oh(tile_h),
    .load_valid(1'b0), .load_ready(), .load_kind(2'd0), .load_addr(16'd0), .load_data(8'd0),
    .vec_valid(state==LOAD_WORD), .vec_ready(core_vec_ready), .vec_kind(load_kind), .vec_addr(load_index),
    .vec_data(load_data), .vec_keep(load_keep),
    .start_valid(state==CORE_START), .start_ready(core_start_ready), .busy(core_busy), .fault(core_fault), .done(core_done),
    .out_valid(core_out_valid), .out_ready(state==COLLECT && !fault), .out_index(core_index), .out_data(core_data), .out_acc(core_acc)
);
assign cfg_ready = rst_n && state==IDLE && !fault;
assign busy = state!=IDLE;
assign mem_req_valid = rst_n && !fault && (state==READ_REQ || state==WRITE_REQ);
assign mem_req_write = state==WRITE_REQ;
assign mem_req_addr = request_addr;
assign mem_req_data = mem_req_write ? write_data : 128'd0;
assign mem_req_strb = mem_req_write ? write_keep : 16'd0;
assign mem_req_tag = {job_id,request_sequence};
assign mem_rsp_ready = rst_n && !fault && (state==READ_WAIT || state==WRITE_WAIT);

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        state<=IDLE; fault<=0; fault_code<=0; done<=0; result_job_id<=0;
        job_id<=0; input_base<=0; output_base<=0; weight_base<=0; param_base<=0; arena_base<=0; arena_limit<=0;
        ci<=0; co<=0; kernel<=0; stride<=0; dilation<=0; pad<=0; input_w<=0; input_h<=0; output_w<=0; output_h<=0;
        depthwise<=0; reserved_bad<=0; input_groups<=0; output_groups<=0; input_tail<=0; output_tail<=0; weight_plane<=0;
        input_rows<=0; output_rows<=0; receptive<=0; padded_w<=0; padded_h<=0; available_w<=0; available_h<=0;
        input_words<=0; output_words<=0; weight_words<=0; param_words<=0;
        input_end<=0; output_end<=0; weight_end<=0; param_end<=0;
        tile_x<=0; tile_y<=0; tile_w<=0; tile_h<=0; tile_iw<=0; tile_ih<=0; tile_plane<=0; tile_area<=0; tile_words<=0;
        reuse_tile<=0; core_done_seen<=0; load_kind<=0; load_index<=0; load_pos<=0; load_group<=0;
        input_x<=0; input_y<=0; gx<=0; gy<=0; input_row<=0; request_addr<=0; request_sequence<=0; pending_tag<=0;
        load_data<=0; packet<=0; write_data<=0; write_keep<=0;
        out_group<=0; out_x<=0; out_y<=0; out_lane<=0; expected_index<=0; output_row<=0;
    end else begin
        done<=0;
        if(core_done) core_done_seen<=1;
        if(core_fault && state!=IDLE && state!=HALT) begin fault<=1; fault_code<=4; state<=HALT; end
        else case(state)
        IDLE: if(cfg_valid && cfg_ready) begin
            job_id<=cfg_descriptor[31:0]; input_base<=cfg_descriptor[63:32]; output_base<=cfg_descriptor[95:64];
            weight_base<=cfg_descriptor[127:96]; param_base<=cfg_descriptor[159:128];
            arena_base<=cfg_descriptor[191:160]; arena_limit<=cfg_descriptor[223:192];
            ci<=cfg_descriptor[230:224]; co<=cfg_descriptor[237:231]; kernel<=cfg_descriptor[239:238];
            stride<=cfg_descriptor[241:240]; dilation<=cfg_descriptor[245:242]; pad<=cfg_descriptor[250:246];
            input_w<=cfg_descriptor[260:251]; input_h<=cfg_descriptor[270:261];
            output_w<=cfg_descriptor[280:271]; output_h<=cfg_descriptor[290:281];
            depthwise<=cfg_descriptor[291]; reserved_bad<=|cfg_descriptor[319:292];
            request_sequence<=0; reuse_tile<=0; tile_x<=0; tile_y<=0; core_done_seen<=0; state<=GEOM_PREP;
        end
        // Geometry is infrequent control work; split it before high-fanout enables.
        GEOM_PREP: begin
            receptive<=kernel==1 ? 6'd1 : kernel==2 ? {2'd0,dilation}+1'b1 : {1'd0,dilation,1'b0}+1'b1;
            padded_w<={2'd0,input_w}+{6'd0,pad,1'b0}; padded_h<={2'd0,input_h}+{6'd0,pad,1'b0};
            state<=GEOM_SHAPE;
        end
        GEOM_SHAPE: begin available_w<=padded_w-receptive; available_h<=padded_h-receptive; state<=GEOMETRY; end
        GEOMETRY: begin
            if(!geometry_ok || reserved_bad) begin fault<=1; fault_code<=reserved_bad ? 8'd8 : 8'd1; state<=HALT; end
            else begin
                input_groups<=(ci+8'd15)>>4; output_groups<=(co+8'd15)>>4;
                input_tail<=ci[3:0]==0 ? 16'hffff : (16'hffff >> (16-ci[3:0]));
                output_tail<=co[3:0]==0 ? 16'hffff : (16'hffff >> (16-co[3:0]));
                weight_plane<=depthwise ? (kernel==1 ? 10'd1 : kernel==2 ? 10'd4 : 10'd9) :
                    kernel==1 ? {3'd0,ci} : kernel==2 ? {1'd0,ci,2'd0} : {ci,3'd0}+{3'd0,ci};
                state<=SIZE_ROW;
            end
        end
        SIZE_ROW: begin input_rows<=input_groups*input_h; output_rows<=output_groups*output_h; state<=SIZES; end
        SIZES: begin
            input_words<=input_rows*input_w; output_words<=output_rows*output_w;
            weight_words<=output_groups*weight_plane; param_words<=output_groups*32'd14; state<=ENDS;
        end
        ENDS: begin
            input_end<={1'b0,input_base}+{1'b0,input_words}; output_end<={1'b0,output_base}+{1'b0,output_words};
            weight_end<={1'b0,weight_base}+{1'b0,weight_words}; param_end<={1'b0,param_base}+{1'b0,param_words}; state<=RANGES;
        end
        RANGES: begin
            if(!ranges_ok) begin fault<=1; fault_code<=2; state<=HALT; end
            else state<=TILE;
        end
        TILE: begin
            tile_w<=output_w-tile_x>=4 ? 3'd4 : output_w-tile_x;
            tile_h<=output_h-tile_y>=4 ? 3'd4 : output_h-tile_y; state<=TILE_GEOM;
        end
        TILE_GEOM: begin
            tile_iw<=(tile_w-1'b1)*stride+(kernel-1'b1)*dilation+1'b1;
            tile_ih<=(tile_h-1'b1)*stride+(kernel-1'b1)*dilation+1'b1;
            tile_area<=tile_w*tile_h; state<=TILE_PLANE;
        end
        TILE_PLANE: begin tile_plane<=tile_iw*tile_ih; state<=CAPACITY; end
        CAPACITY: begin
            tile_words<=input_groups*tile_plane;
            if(tile_input_bytes>32768 || logical_weight_bytes>8192 || weight_words>1024) begin
                fault<=1; fault_code<=3; state<=HALT;
            end else state<=CORE_CFG;
        end
        CORE_CFG: if(core_cfg_ready) begin
            core_done_seen<=0; load_index<=0; load_pos<=0; load_group<=0; input_x<=0; input_y<=0;
            out_group<=0; out_x<=0; out_y<=0; out_lane<=0; packet<=0;
            if(reuse_tile) begin load_kind<=0; state<=IN_COORD; end
            else begin load_kind<=2; state<=LINEAR_ADDR; end
        end
        LINEAR_ADDR: begin request_addr<=(load_kind==1 ? weight_base : param_base)+load_index; state<=READ_REQ; end
        IN_COORD: begin
            gx<=$signed({1'b0,tile_x})*$signed({1'b0,stride})+$signed({1'b0,input_x})-$signed({1'b0,pad});
            gy<=$signed({1'b0,tile_y})*$signed({1'b0,stride})+$signed({1'b0,input_y})-$signed({1'b0,pad}); state<=IN_ROW;
        end
        IN_ROW: begin
            if(input_outside) begin load_data<=0; state<=LOAD_WORD; end
            else begin input_row<=load_group*input_h+gy; state<=IN_ADDR; end
        end
        IN_ADDR: begin request_addr<=input_base+input_row*input_w+gx; state<=READ_REQ; end
        READ_REQ: if(mem_req_ready) begin pending_tag<=mem_req_tag; request_sequence<=request_sequence+1'b1; state<=READ_WAIT; end
        READ_WAIT: if(mem_rsp_valid) begin
            if(mem_rsp_error || mem_rsp_tag!=pending_tag) begin fault<=1; fault_code<=mem_rsp_error ? 8'd5 : 8'd6; state<=HALT; end
            else begin load_data<=mem_rsp_data; state<=LOAD_WORD; end
        end
        LOAD_WORD: if(core_vec_ready) begin
            if(load_index==load_limit-1) begin
                load_index<=0; load_pos<=0; load_group<=0;
                if(load_kind==2) begin load_kind<=1; state<=LINEAR_ADDR; end
                else if(load_kind==1) begin load_kind<=0; input_x<=0; input_y<=0; state<=IN_COORD; end
                else state<=CORE_START;
            end else begin
                load_index<=load_index+1'b1;
                if(load_kind==0) begin
                    if(input_x==tile_iw-1) begin
                        input_x<=0;
                        if(input_y==tile_ih-1) begin input_y<=0; load_group<=load_group+1'b1; end
                        else input_y<=input_y+1'b1;
                    end else input_x<=input_x+1'b1;
                    state<=IN_COORD;
                end else begin
                    if(load_pos==load_plane-1) begin load_pos<=0; load_group<=load_group+1'b1; end
                    else load_pos<=load_pos+1'b1;
                    state<=LINEAR_ADDR;
                end
            end
        end
        CORE_START: if(core_start_ready) state<=OUT_PREP;
        OUT_PREP: begin expected_index<=out_channel_base*tile_area+out_y*tile_w+out_x; state<=COLLECT; end
        COLLECT: if(core_out_valid) begin
            if(core_index!=expected_index) begin fault<=1; fault_code<=7; state<=HALT; end
            else begin
                packet[out_lane*8+:8]<=core_data;
                if(out_lane==output_lanes-1) begin
                    write_data<=packet; write_data[out_lane*8+:8]<=core_data;
                    write_keep<=out_group==output_groups-1 ? output_tail : 16'hffff; state<=OUT_ROW;
                end else begin out_lane<=out_lane+1'b1; expected_index<=expected_index+tile_area; end
            end
        end
        OUT_ROW: begin output_row<=out_group*output_h+tile_y+out_y; state<=OUT_ADDR; end
        OUT_ADDR: begin request_addr<=output_base+output_row*output_w+tile_x+out_x; state<=WRITE_REQ; end
        WRITE_REQ: if(mem_req_ready) begin pending_tag<=mem_req_tag; request_sequence<=request_sequence+1'b1; state<=WRITE_WAIT; end
        WRITE_WAIT: if(mem_rsp_valid) begin
            if(mem_rsp_error || mem_rsp_tag!=pending_tag) begin fault<=1; fault_code<=mem_rsp_error ? 8'd5 : 8'd6; state<=HALT; end
            else begin
                packet<=0; out_lane<=0;
                if(last_output_word) state<=TILE_DONE;
                else begin
                    if(out_x==tile_w-1) begin
                        out_x<=0;
                        if(out_y==tile_h-1) begin out_y<=0; out_group<=out_group+1'b1; end
                        else out_y<=out_y+1'b1;
                    end else out_x<=out_x+1'b1;
                    state<=OUT_PREP;
                end
            end
        end
        TILE_DONE: if(core_done_seen) begin
            if(last_tile) begin done<=1; result_job_id<=job_id; state<=IDLE; end
            else begin
                if(tile_x+tile_w==output_w) begin tile_x<=0; tile_y<=tile_y+tile_h; end
                else tile_x<=tile_x+tile_w;
                reuse_tile<=1; state<=TILE;
            end
        end
        HALT: state<=HALT;
        default: begin fault<=1; fault_code<=9; state<=HALT; end
        endcase
    end
end
endmodule
