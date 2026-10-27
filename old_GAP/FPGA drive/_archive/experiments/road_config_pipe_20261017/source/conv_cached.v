`timescale 1ns/1ps
// Sixteen output-channel lanes with retained weights and 128-bit banked ingress.
// Configuration is captured before staged geometry/capacity validation.
module conv_cached (
    input clk, rst_n,
    input cfg_valid, output cfg_ready,
    input cfg_reuse, cfg_banked_load,
    input [31:0] cfg_weights_id,
    output reg cache_valid,
    output reg [31:0] cached_weights_id,
    input cfg_depthwise,
    input [6:0] cfg_ci, cfg_co,
    input [1:0] cfg_kernel, cfg_stride,
    input [3:0] cfg_dilation,
    input [4:0] cfg_iw, cfg_ih,
    input [2:0] cfg_ow, cfg_oh,
    input load_valid, output load_ready,
    input [1:0] load_kind,
    input [15:0] load_addr,
    input [7:0] load_data,
    input vec_valid, output vec_ready,
    input [1:0] vec_kind,
    input [11:0] vec_addr,
    input [127:0] vec_data,
    input [15:0] vec_keep,
    input start_valid, output start_ready,
    output busy, output reg fault, output reg done,
    output reg out_valid, input out_ready,
    output reg [15:0] out_index,
    output reg [7:0] out_data,
    output reg signed [31:0] out_acc
);
localparam CONFIG=0, LOAD=1, PARAM_READ=2, PARAM_LATCH=3, RUN=4, EMIT=5,
    CFG_PLANE=6, CFG_SIZE=7, CFG_CHECK=8, CFG_APPLY=9;
reg [3:0] state;
reg depthwise, issuing, banked_load;
reg [6:0] ci, co, ic, oc_base;
reg [1:0] kernel, stride, ky, kx;
reg [3:0] dilation, param_index;
reg [4:0] iw, ih;
reg [2:0] ow, oh, oy, ox;
reg [15:0] input_count, weight_count, param_count;
reg [15:0] input_size, weight_size, param_size;
reg [9:0] input_plane, weight_plane;
reg [6:0] load_ic, load_oc, load_pc;
reg [9:0] load_ip, load_wp;
reg [3:0] load_pp;
reg [11:0] load_ib;
reg [9:0] load_wb;
reg [6:0] load_pb;
reg [4:0] input_vec_bytes, weight_vec_bytes, param_vec_bytes;
reg [15:0] input_vec_keep, weight_vec_keep, param_vec_keep;
reg [4:0] input_tail_bytes, output_tail_bytes;
reg [15:0] input_tail_keep, output_tail_keep;
reg [2:0] input_last_group, output_last_group;
reg [3:0] valid_pipe, last_pipe;
reg [7:0] pixel_row;
reg [5:0] pixel_column;
reg [11:0] weight_row;
reg [1:0] weight_column;
reg [11:0] pixel_addr;
reg [9:0] weight_addr;
reg [3:0] select_0, select_1, select_2;
wire [7:0] pixel_read [0:15];
wire signed [31:0] accumulators [0:15];
wire signed [47:0] gains [0:15];
wire signed [63:0] offsets [0:15];

reg pending_reuse, pending_banked, pending_depthwise, pending_basic_ok, pending_reuse_ok, pending_geometry_ok;
reg [31:0] pending_id;
reg [6:0] pending_ci, pending_co;
reg [1:0] pending_kernel, pending_stride;
reg [3:0] pending_dilation;
reg [4:0] pending_iw, pending_ih;
reg [2:0] pending_ow, pending_oh;
reg [9:0] new_input_plane;
reg [10:0] new_weight_plane;
reg [16:0] new_input_size;
reg [17:0] new_weight_size;
reg [13:0] new_input_words;
reg [14:0] new_weight_words;
reg [3:0] new_input_groups, new_output_groups;
reg [5:0] required_w, required_h;
wire [6:0] new_ci_minus_one = pending_ci-1'b1;
wire [6:0] new_co_minus_one = pending_co-1'b1;
wire [4:0] new_input_tail_bytes = pending_ci[3:0]==0 ? 5'd16 : {1'b0,pending_ci[3:0]};
wire [4:0] new_output_tail_bytes = pending_co[3:0]==0 ? 5'd16 : {1'b0,pending_co[3:0]};
wire [15:0] new_input_tail_keep = 16'hffff >> (5'd16-new_input_tail_bytes);
wire [15:0] new_output_tail_keep = 16'hffff >> (5'd16-new_output_tail_bytes);
wire basic_config_ok = cfg_ci>0 && cfg_ci<=80 && cfg_co>0 && cfg_co<=80 &&
    cfg_kernel>0 && cfg_kernel<=3 && cfg_stride>0 && cfg_stride<=2 &&
    cfg_dilation>0 && cfg_dilation<=8 && cfg_ow>0 && cfg_ow<=4 && cfg_oh>0 && cfg_oh<=4 &&
    (!cfg_depthwise || cfg_ci==cfg_co);
wire [15:0] expected_addr = load_kind==0 ? input_count : load_kind==1 ? weight_count : param_count;
wire ordered = load_addr==expected_addr && load_kind!=3;
wire vec_ordered;
wire reuse_ok = cache_valid && cfg_weights_id==cached_weights_id &&
    cfg_ci==ci && cfg_co==co && cfg_kernel==kernel && cfg_depthwise==depthwise;
assign cfg_ready = rst_n && state==CONFIG && !fault;
assign load_ready = rst_n && state==LOAD && !fault && !banked_load &&
    (load_kind==0 ? input_count<input_size : load_kind==1 ? weight_count<weight_size :
     load_kind==2 ? param_count<param_size : 1'b1);
assign vec_ready = rst_n && state==LOAD && !fault && banked_load &&
    (vec_kind==0 ? input_count<input_size : vec_kind==1 ? weight_count<weight_size :
     vec_kind==2 ? param_count<param_size : 1'b1);
assign start_ready = rst_n && state==LOAD && !fault && input_count==input_size &&
    weight_count==weight_size && param_count==param_size &&
    !(load_valid && load_ready && !ordered) && !(vec_valid && vec_ready && !vec_ordered);
assign busy = state!=CONFIG;
wire write_accept = load_valid && load_ready && ordered;
wire [11:0] input_write_addr = load_ib + load_ip;
wire [9:0] weight_write_addr = load_wb + load_wp;
wire [6:0] param_write_addr = load_pb + load_pp;
wire [11:0] expected_vec_addr = vec_kind==0 ? input_write_addr :
    vec_kind==1 ? {2'd0,weight_write_addr} : {5'd0,param_write_addr};
wire [4:0] vec_bytes = vec_kind==0 ? input_vec_bytes : vec_kind==1 ? weight_vec_bytes : param_vec_bytes;
wire [15:0] expected_keep = vec_kind==0 ? input_vec_keep : vec_kind==1 ? weight_vec_keep : param_vec_keep;
assign vec_ordered = vec_kind!=3 && vec_addr==expected_vec_addr && vec_keep==expected_keep;
wire vec_accept = vec_valid && vec_ready && vec_ordered;
wire [6:0] coefficient_addr = oc_base[6:4]*7'd14 + param_index;
wire [4:0] active_lanes = co-oc_base>=16 ? 5'd16 : co-oc_base;
wire last_term = kx==kernel-1 && ky==kernel-1 && (depthwise || ic==ci-1);

reg [4:0] quant_lane;
reg qvalid_select, qlast_select;
reg signed [31:0] qacc_select;
reg signed [47:0] qgain_select;
reg signed [63:0] qoffset_select;
reg [15:0] qindex_select;
reg qvalid0, qvalid1, qlast0, qlast1, out_last;
reg signed [79:0] qproduct;
reg signed [63:0] qoffset;
reg signed [80:0] qsum;
reg signed [31:0] qacc0, qacc1;
reg [15:0] qindex0, qindex1;
wire advance = !out_valid || out_ready;
wire emit_last = state==EMIT && out_valid && out_ready && out_last;
wire clear_acc = (start_valid && start_ready) || emit_last;
wire signed [80:0] rounded = qsum + (81'sd1 <<< 35);
wire [7:0] quantized = qsum<=0 ? 8'd0 : qsum>=(81'sd255 <<< 36) ? 8'd255 : rounded[43:36];

genvar lane;
generate for(lane=0; lane<16; lane=lane+1) begin: banks
    reg [7:0] pixels [0:4095];
    reg signed [7:0] weights [0:1023];
    reg [7:0] coefficients [0:127];
    reg [7:0] pixel_reg, param_byte;
    reg signed [7:0] weight_reg;
    reg signed [16:0] product;
    reg signed [31:0] accumulator;
    reg signed [47:0] gain;
    reg signed [63:0] offset;
    wire signed [8:0] pixel_value = $signed({1'b0,depthwise ? pixel_read[lane] : pixel_read[select_2]});
    assign pixel_read[lane] = pixel_reg;
    assign accumulators[lane] = accumulator;
    assign gains[lane] = gain;
    assign offsets[lane] = offset;
    // Unreset synchronous RAM: only a completely loaded descriptor may execute.
    always @(posedge clk) begin
        if((write_accept && load_kind==0 && load_ic[3:0]==lane) || (vec_accept && vec_kind==0 && vec_keep[lane]))
            pixels[banked_load ? vec_addr : input_write_addr]<=banked_load ? vec_data[lane*8+:8] : load_data;
        if((write_accept && load_kind==1 && load_oc[3:0]==lane) || (vec_accept && vec_kind==1 && vec_keep[lane]))
            weights[banked_load ? vec_addr[9:0] : weight_write_addr]<=banked_load ? vec_data[lane*8+:8] : load_data;
        if((write_accept && load_kind==2 && load_pc[3:0]==lane) || (vec_accept && vec_kind==2 && vec_keep[lane]))
            coefficients[banked_load ? vec_addr[6:0] : param_write_addr]<=banked_load ? vec_data[lane*8+:8] : load_data;
        if(rst_n && valid_pipe[1]) begin
            pixel_reg<=pixels[pixel_addr];
            weight_reg<=weights[weight_addr];
        end
        if(rst_n && state==PARAM_READ) param_byte<=coefficients[coefficient_addr];
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin product<=0; accumulator<=0; gain<=0; offset<=0; end
        else begin
            if(state==PARAM_LATCH) begin
                if(param_index<6) gain<={param_byte,gain[47:8]};
                else offset<={param_byte,offset[63:8]};
            end
            if(valid_pipe[2]) product<=oc_base+lane<co ? pixel_value*weight_reg : 17'sd0;
            if(clear_acc) accumulator<=0;
            else if(valid_pipe[3]) accumulator<=accumulator+{{15{product[16]}},product};
        end
    end
end endgenerate

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        state<=CONFIG; fault<=0; done<=0; out_valid<=0; out_index<=0; out_data<=0; out_acc<=0;
        depthwise<=0; ci<=0; co<=0; kernel<=0; stride<=0; dilation<=0;
        banked_load<=0; cache_valid<=0; cached_weights_id<=0;
        pending_reuse<=0; pending_banked<=0; pending_depthwise<=0; pending_basic_ok<=0;
        pending_reuse_ok<=0; pending_geometry_ok<=0; pending_id<=0; pending_ci<=0; pending_co<=0;
        pending_kernel<=0; pending_stride<=0; pending_dilation<=0; pending_iw<=0; pending_ih<=0;
        pending_ow<=0; pending_oh<=0; new_input_plane<=0; new_weight_plane<=0;
        new_input_size<=0; new_weight_size<=0; new_input_words<=0; new_weight_words<=0;
        new_input_groups<=0; new_output_groups<=0; required_w<=0; required_h<=0;
        iw<=0; ih<=0; ow<=0; oh<=0; ic<=0; oc_base<=0; kx<=0; ky<=0; ox<=0; oy<=0;
        input_size<=0; weight_size<=0; param_size<=0; input_count<=0; weight_count<=0; param_count<=0;
        input_plane<=0; weight_plane<=0; load_ic<=0; load_oc<=0; load_pc<=0;
        load_ip<=0; load_wp<=0; load_pp<=0; load_ib<=0; load_wb<=0; load_pb<=0;
        input_vec_bytes<=0; weight_vec_bytes<=0; param_vec_bytes<=0;
        input_vec_keep<=0; weight_vec_keep<=0; param_vec_keep<=0;
        input_tail_bytes<=0; output_tail_bytes<=0; input_tail_keep<=0; output_tail_keep<=0;
        input_last_group<=0; output_last_group<=0;
        param_index<=0; valid_pipe<=0; last_pipe<=0; issuing<=0;
        pixel_row<=0; pixel_column<=0; weight_row<=0; weight_column<=0; pixel_addr<=0; weight_addr<=0;
        select_0<=0; select_1<=0; select_2<=0;
        quant_lane<=0; qvalid0<=0; qvalid1<=0; qlast0<=0; qlast1<=0; out_last<=0;
        qvalid_select<=0; qlast_select<=0; qacc_select<=0; qgain_select<=0; qoffset_select<=0; qindex_select<=0;
        qproduct<=0; qoffset<=0; qsum<=0; qacc0<=0; qacc1<=0; qindex0<=0; qindex1<=0;
    end else begin
        done<=0;
        // Address, RAM read, multiply, accumulate: one term/lane each clock.
        valid_pipe<={valid_pipe[2:0],state==RUN && issuing};
        last_pipe<={last_pipe[2:0],state==RUN && issuing && last_term};
        if(state==RUN && issuing) begin
            pixel_row<=(depthwise ? oc_base[6:4] : ic[6:4])*ih + oy*stride + ky*dilation;
            pixel_column<=ox*stride + kx*dilation;
            weight_row<=(depthwise ? oc_base[6:4] : oc_base[6:4]*ci+ic)*kernel + ky;
            weight_column<=kx; select_0<=ic[3:0];
        end
        if(valid_pipe[0]) begin
            pixel_addr<=pixel_row*iw + pixel_column;
            weight_addr<=weight_row*kernel + weight_column; select_1<=select_0;
        end
        if(valid_pipe[1]) select_2<=select_1;
        case(state)
        CONFIG: if(cfg_valid && cfg_ready) begin
            pending_reuse<=cfg_reuse; pending_banked<=cfg_banked_load; pending_id<=cfg_weights_id;
            pending_depthwise<=cfg_depthwise; pending_ci<=cfg_ci; pending_co<=cfg_co;
            pending_kernel<=cfg_kernel; pending_stride<=cfg_stride; pending_dilation<=cfg_dilation;
            pending_iw<=cfg_iw; pending_ih<=cfg_ih; pending_ow<=cfg_ow; pending_oh<=cfg_oh;
            pending_basic_ok<=basic_config_ok; pending_reuse_ok<=!cfg_reuse || reuse_ok;
            if(!cfg_reuse) cache_valid<=0;
            state<=CFG_PLANE;
        end
        CFG_PLANE: begin
            new_input_plane<=pending_iw*pending_ih;
            new_weight_plane<=pending_depthwise ?
                (pending_kernel==1 ? 11'd1 : pending_kernel==2 ? 11'd4 : 11'd9) :
                pending_kernel==1 ? {4'd0,pending_ci} : pending_kernel==2 ? {2'd0,pending_ci,2'd0} :
                {1'd0,pending_ci,3'd0}+{4'd0,pending_ci};
            new_input_groups<=({1'b0,pending_ci}+8'd15)>>4;
            new_output_groups<=({1'b0,pending_co}+8'd15)>>4;
            required_w<=({3'd0,pending_ow}-6'd1)*pending_stride+
                ({4'd0,pending_kernel}-6'd1)*pending_dilation+1'b1;
            required_h<=({3'd0,pending_oh}-6'd1)*pending_stride+
                ({4'd0,pending_kernel}-6'd1)*pending_dilation+1'b1;
            state<=CFG_SIZE;
        end
        CFG_SIZE: begin
            new_input_size<=pending_ci*new_input_plane;
            new_weight_size<=pending_co*new_weight_plane;
            new_input_words<=new_input_groups*new_input_plane;
            new_weight_words<=new_output_groups*new_weight_plane;
            pending_geometry_ok<={1'b0,pending_iw}==required_w && {1'b0,pending_ih}==required_h;
            state<=CFG_CHECK;
        end
        CFG_CHECK: begin
            if(!pending_basic_ok || !pending_reuse_ok || !pending_geometry_ok ||
                new_input_size>32768 || new_weight_size>8192 || new_input_words>4096 || new_weight_words>1024)
                begin fault<=1; cache_valid<=0; state<=CONFIG; end
            else state<=CFG_APPLY;
        end
        CFG_APPLY: begin
                banked_load<=pending_banked;
                if(!pending_reuse) cached_weights_id<=pending_id;
                depthwise<=pending_depthwise; ci<=pending_ci; co<=pending_co; kernel<=pending_kernel;
                stride<=pending_stride; dilation<=pending_dilation; iw<=pending_iw; ih<=pending_ih; ow<=pending_ow; oh<=pending_oh;
                input_size<=new_input_size[15:0]; weight_size<=new_weight_size[15:0]; param_size<=pending_co*16'd14;
                input_plane<=new_input_plane[9:0]; weight_plane<=new_weight_plane[9:0];
                // Tail masks change only at a channel-group boundary, not on every byte.
                input_tail_bytes<=new_input_tail_bytes; output_tail_bytes<=new_output_tail_bytes;
                input_tail_keep<=new_input_tail_keep; output_tail_keep<=new_output_tail_keep;
                input_last_group<=new_ci_minus_one[6:4]; output_last_group<=new_co_minus_one[6:4];
                input_vec_bytes<=pending_ci<=16 ? new_input_tail_bytes : 5'd16;
                weight_vec_bytes<=pending_co<=16 ? new_output_tail_bytes : 5'd16;
                param_vec_bytes<=pending_co<=16 ? new_output_tail_bytes : 5'd16;
                input_vec_keep<=pending_ci<=16 ? new_input_tail_keep : 16'hffff;
                weight_vec_keep<=pending_co<=16 ? new_output_tail_keep : 16'hffff;
                param_vec_keep<=pending_co<=16 ? new_output_tail_keep : 16'hffff;
                input_count<=0;
                weight_count<=pending_reuse ? new_weight_size[15:0] : 16'd0;
                param_count<=pending_reuse ? pending_co*16'd14 : 16'd0;
                load_ic<=0; load_oc<=0; load_pc<=0; load_ip<=0; load_wp<=0; load_pp<=0;
                load_ib<=0; load_wb<=0; load_pb<=0; state<=LOAD;
        end
        LOAD: begin
            if((write_accept && load_kind==0) || (vec_accept && vec_kind==0))
                input_count<=input_count+(banked_load ? input_vec_bytes : 5'd1);
            if((write_accept && load_kind==1) || (vec_accept && vec_kind==1))
                weight_count<=weight_count+(banked_load ? weight_vec_bytes : 5'd1);
            if((write_accept && load_kind==2) || (vec_accept && vec_kind==2))
                param_count<=param_count+(banked_load ? param_vec_bytes : 5'd1);
            if(load_valid && load_ready) begin
                if(!ordered) begin fault<=1; cache_valid<=0; end
                else case(load_kind)
                0: begin
                    if(load_ip==input_plane-1) begin
                        load_ip<=0; load_ic<=load_ic+1'b1;
                        if(load_ic[3:0]==15) load_ib<=load_ib+input_plane;
                    end else load_ip<=load_ip+1'b1;
                end
                1: begin
                    if(load_wp==weight_plane-1) begin
                        load_wp<=0; load_oc<=load_oc+1'b1;
                        if(load_oc[3:0]==15) load_wb<=load_wb+weight_plane;
                    end else load_wp<=load_wp+1'b1;
                end
                2: begin
                    if(load_pp==13) begin
                        load_pp<=0; load_pc<=load_pc+1'b1;
                        if(load_pc[3:0]==15) load_pb<=load_pb+7'd14;
                    end else load_pp<=load_pp+1'b1;
                end
                endcase
            end
            if(vec_valid && vec_ready) begin
                if(!vec_ordered) begin fault<=1; cache_valid<=0; end
                else case(vec_kind)
                0: begin
                    if(load_ip==input_plane-1) begin
                        load_ip<=0; load_ic<=load_ic+7'd16; load_ib<=load_ib+input_plane;
                        if(load_ic[6:4]+1'b1==input_last_group) begin
                            input_vec_bytes<=input_tail_bytes; input_vec_keep<=input_tail_keep;
                        end
                    end else load_ip<=load_ip+1'b1;
                end
                1: begin
                    if(load_wp==weight_plane-1) begin
                        load_wp<=0; load_oc<=load_oc+7'd16; load_wb<=load_wb+weight_plane;
                        if(load_oc[6:4]+1'b1==output_last_group) begin
                            weight_vec_bytes<=output_tail_bytes; weight_vec_keep<=output_tail_keep;
                        end
                    end else load_wp<=load_wp+1'b1;
                end
                2: begin
                    if(load_pp==13) begin
                        load_pp<=0; load_pc<=load_pc+7'd16; load_pb<=load_pb+7'd14;
                        if(load_pc[6:4]+1'b1==output_last_group) begin
                            param_vec_bytes<=output_tail_bytes; param_vec_keep<=output_tail_keep;
                        end
                    end else load_pp<=load_pp+1'b1;
                end
                endcase
            end
            if(start_valid && start_ready) begin
                cache_valid<=1;
                oc_base<=0; ox<=0; oy<=0; ic<=0; ky<=0; kx<=0;
                param_index<=0; state<=PARAM_READ;
            end
        end
        PARAM_READ: state<=PARAM_LATCH;
        PARAM_LATCH: begin
            if(param_index==13) begin state<=RUN; issuing<=1; end
            else begin param_index<=param_index+1'b1; state<=PARAM_READ; end
        end
        RUN: begin
            if(issuing) begin
                if(last_term) issuing<=0;
                if(kx==kernel-1) begin
                    kx<=0;
                    if(ky==kernel-1) begin ky<=0; ic<=ic+1'b1; end
                    else ky<=ky+1'b1;
                end else kx<=kx+1'b1;
            end
            if(valid_pipe[3] && last_pipe[3]) begin state<=EMIT; quant_lane<=0; end
        end
        EMIT: if(advance) begin
            // One shared wide quantizer; freeze every stage on output backpressure.
            // Register selection so synthesis cannot distribute the wide multiply across lanes.
            qvalid_select<=quant_lane<active_lanes;
            if(quant_lane<active_lanes) begin
                qacc_select<=accumulators[quant_lane[3:0]]; qgain_select<=gains[quant_lane[3:0]];
                qoffset_select<=offsets[quant_lane[3:0]];
                qindex_select<=(oc_base+quant_lane)*ow*oh + oy*ow + ox;
                qlast_select<=quant_lane==active_lanes-1; quant_lane<=quant_lane+1'b1;
            end
            qvalid0<=qvalid_select;
            if(qvalid_select) begin
                qproduct<=qacc_select*qgain_select;
                qoffset<=qoffset_select; qacc0<=qacc_select;
                qindex0<=qindex_select; qlast0<=qlast_select;
            end
            qvalid1<=qvalid0;
            if(qvalid0) begin
                qsum<={qproduct[79],qproduct}+{{17{qoffset[63]}},qoffset};
                qacc1<=qacc0; qindex1<=qindex0; qlast1<=qlast0;
            end
            out_valid<=qvalid1;
            if(qvalid1) begin out_data<=quantized; out_acc<=qacc1; out_index<=qindex1; out_last<=qlast1; end
            if(emit_last) begin
                qvalid_select<=0; qvalid0<=0; qvalid1<=0; out_valid<=0; ic<=0; ky<=0; kx<=0;
                if(ox==ow-1) begin
                    ox<=0;
                    if(oy==oh-1) begin
                        oy<=0;
                        if(oc_base+16>=co) begin state<=CONFIG; done<=1; end
                        else begin oc_base<=oc_base+7'd16; param_index<=0; state<=PARAM_READ; end
                    end else begin oy<=oy+1'b1; state<=RUN; issuing<=1; end
                end else begin ox<=ox+1'b1; state<=RUN; issuing<=1; end
            end
        end
        default: begin state<=CONFIG; fault<=1; out_valid<=0; cache_valid<=0; end
        endcase
    end
end
endmodule
