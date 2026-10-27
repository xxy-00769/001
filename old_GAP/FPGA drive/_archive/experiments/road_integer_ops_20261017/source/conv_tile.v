`timescale 1ns/1ps
// Reconfigurable serial INT8 convolution tile; CHW input/output, OIHW weights.
// Padding is supplied by the caller. This module has no DDR or camera interface.
module conv_tile (
    input clk, rst_n,
    input cfg_valid, output cfg_ready,
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
    input start_valid, output start_ready,
    output busy, output reg fault, output reg done,
    output reg out_valid, input out_ready,
    output reg [15:0] out_index,
    output reg [7:0] out_data,
    output reg signed [31:0] out_acc
);
localparam CONFIG=0, LOAD=1, PARAM_READ=2, PARAM_LATCH=3,
           READ=4, MAC=5, SCALE=6, BIAS=7, QUANT=8, HOLD=9, ADDRESS_ROW=10, ADDRESS_FINAL=11, MULTIPLY=12;
reg [3:0] state;
reg depthwise;
reg [6:0] ci, co, ic, oc;
reg [1:0] kernel, stride, ky, kx;
reg [3:0] dilation, param_index;
reg [4:0] iw, ih;
reg [2:0] ow, oh, oy, ox;
reg [15:0] input_count, weight_count, param_count;
reg [15:0] input_size, weight_size, param_size;
reg [7:0] pixels [0:32767];
reg signed [7:0] weights [0:8191];
reg [7:0] coefficients [0:1119];
reg [7:0] pixel_reg, param_byte;
reg signed [7:0] weight_reg;
reg signed [47:0] gain;
reg signed [63:0] offset;
reg signed [31:0] accumulator;
reg signed [16:0] product_reg;
reg signed [79:0] scaled_product;
reg signed [80:0] scaled;
reg [11:0] pixel_row;
reg [5:0] pixel_column;
reg [14:0] weight_row;
reg [15:0] pixel_addr, weight_addr;

wire [31:0] new_input_size = cfg_ci * cfg_iw * cfg_ih;
wire [31:0] new_weight_size = cfg_co * (cfg_depthwise ? 32'd1 : cfg_ci) * cfg_kernel * cfg_kernel;
wire [31:0] required_w = (cfg_ow-32'd1)*cfg_stride + (cfg_kernel-32'd1)*cfg_dilation + 1;
wire [31:0] required_h = (cfg_oh-32'd1)*cfg_stride + (cfg_kernel-32'd1)*cfg_dilation + 1;
wire config_ok = cfg_ci>0 && cfg_ci<=80 && cfg_co>0 && cfg_co<=80 &&
                 cfg_kernel>0 && cfg_kernel<=3 && cfg_stride>0 && cfg_stride<=2 &&
                 cfg_dilation>0 && cfg_dilation<=8 && cfg_ow>0 && cfg_ow<=4 && cfg_oh>0 && cfg_oh<=4 &&
                 cfg_iw==required_w && cfg_ih==required_h &&
                 new_input_size<=32768 && new_weight_size<=8192 &&
                 (!cfg_depthwise || cfg_ci==cfg_co);
wire [15:0] expected_addr = load_kind==0 ? input_count : load_kind==1 ? weight_count : param_count;
wire ordered = load_addr==expected_addr && load_kind!=3;
assign cfg_ready = rst_n && state==CONFIG && !fault;
assign load_ready = rst_n && state==LOAD && !fault &&
                    (load_kind==0 ? input_count<input_size : load_kind==1 ? weight_count<weight_size :
                     load_kind==2 ? param_count<param_size : 1'b1);
assign start_ready = rst_n && state==LOAD && !fault && input_count==input_size &&
                     weight_count==weight_size && param_count==param_size &&
                     !(load_valid && load_ready && !ordered);
assign busy = state!=CONFIG;

wire [10:0] coefficient_addr = oc*11'd14 + param_index;
wire signed [8:0] unsigned_pixel = $signed({1'b0,pixel_reg});
wire signed [16:0] product = unsigned_pixel * weight_reg;
wire signed [31:0] extended_product = {{15{product_reg[16]}},product_reg};
wire signed [80:0] rounded = scaled + (81'sd1 <<< 35);
wire [7:0] quantized = scaled<=0 ? 8'd0 : scaled>=(81'sd255 <<< 36) ? 8'd255 : rounded[43:36];

// Unreset synchronous RAMs are inaccessible until all three banks are loaded.
always @(posedge clk) begin
    if (load_valid && load_ready && ordered) begin
        case (load_kind)
            0: pixels[load_addr[14:0]] <= load_data;
            1: weights[load_addr[12:0]] <= load_data;
            2: coefficients[load_addr[10:0]] <= load_data;
        endcase
    end
    if (rst_n && state==READ) begin
        pixel_reg <= pixels[pixel_addr[14:0]];
        weight_reg <= weights[weight_addr[12:0]];
    end
    if (rst_n && state==PARAM_READ) param_byte <= coefficients[coefficient_addr];
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state<=CONFIG; fault<=0; done<=0; out_valid<=0; out_index<=0; out_data<=0; out_acc<=0;
        depthwise<=0; ci<=0; co<=0; kernel<=0; stride<=0; dilation<=0;
        iw<=0; ih<=0; ow<=0; oh<=0; ic<=0; oc<=0; kx<=0; ky<=0; ox<=0; oy<=0;
        input_size<=0; weight_size<=0; param_size<=0; input_count<=0; weight_count<=0; param_count<=0;
        param_index<=0; gain<=0; offset<=0; accumulator<=0; scaled_product<=0; scaled<=0; product_reg<=0;
        pixel_row<=0; pixel_column<=0; weight_row<=0; pixel_addr<=0; weight_addr<=0;
    end else begin
        done<=0;
        case (state)
        CONFIG: if (cfg_valid && cfg_ready) begin
            if (!config_ok) fault<=1;
            else begin
                depthwise<=cfg_depthwise; ci<=cfg_ci; co<=cfg_co; kernel<=cfg_kernel;
                stride<=cfg_stride; dilation<=cfg_dilation; iw<=cfg_iw; ih<=cfg_ih; ow<=cfg_ow; oh<=cfg_oh;
                input_size<=new_input_size[15:0]; weight_size<=new_weight_size[15:0]; param_size<=cfg_co*16'd14;
                input_count<=0; weight_count<=0; param_count<=0; state<=LOAD;
            end
        end
        LOAD: begin
            if (load_valid && load_ready) begin
                if (!ordered) fault<=1;
                else case (load_kind)
                    0: input_count<=input_count+1'b1;
                    1: weight_count<=weight_count+1'b1;
                    2: param_count<=param_count+1'b1;
                endcase
            end
            if (start_valid && start_ready) begin
                oc<=0; ox<=0; oy<=0; ic<=0; ky<=0; kx<=0;
                out_index<=0; accumulator<=0; param_index<=0; state<=PARAM_READ;
            end
        end
        PARAM_READ: state<=PARAM_LATCH;
        PARAM_LATCH: begin
            if (param_index<6) gain<={param_byte,gain[47:8]};
            else offset<={param_byte,offset[63:8]};
            if (param_index==13) state<=ADDRESS_ROW;
            else begin param_index<=param_index+1'b1; state<=PARAM_READ; end
        end
        ADDRESS_ROW: begin
            pixel_row<=(depthwise ? oc : ic)*ih + oy*stride + ky*dilation;
            pixel_column<=ox*stride + kx*dilation;
            weight_row<=(depthwise ? oc : oc*ci+ic)*kernel + ky;
            state<=ADDRESS_FINAL;
        end
        ADDRESS_FINAL: begin
            pixel_addr<=pixel_row*iw + pixel_column;
            weight_addr<=weight_row*kernel + kx;
            state<=READ;
        end
        READ: state<=MULTIPLY;
        MULTIPLY: begin product_reg<=product; state<=MAC; end
        MAC: begin
            accumulator<=accumulator+extended_product;
            if (kx==kernel-1) begin
                kx<=0;
                if (ky==kernel-1) begin
                    ky<=0;
                    if (depthwise || ic==ci-1) begin ic<=0; state<=SCALE; end
                    else begin ic<=ic+1'b1; state<=ADDRESS_ROW; end
                end else begin ky<=ky+1'b1; state<=ADDRESS_ROW; end
            end else begin kx<=kx+1'b1; state<=ADDRESS_ROW; end
        end
        SCALE: begin scaled_product<=accumulator*gain; state<=BIAS; end
        BIAS: begin scaled<={scaled_product[79],scaled_product}+{{17{offset[63]}},offset}; state<=QUANT; end
        QUANT: begin
            out_acc<=accumulator; out_data<=quantized; out_valid<=1; state<=HOLD;
        end
        HOLD: if (out_ready) begin
            out_valid<=0; accumulator<=0;
            if (ox==ow-1) begin
                ox<=0;
                if (oy==oh-1) begin
                    oy<=0;
                    if (oc==co-1) begin state<=CONFIG; done<=1; end
                    else begin oc<=oc+1'b1; param_index<=0; state<=PARAM_READ; end
                end else begin oy<=oy+1'b1; state<=ADDRESS_ROW; end
            end else begin ox<=ox+1'b1; state<=ADDRESS_ROW; end
            if (!(ox==ow-1 && oy==oh-1 && oc==co-1)) out_index<=out_index+1'b1;
        end
        default: begin state<=CONFIG; fault<=1; out_valid<=0; end
        endcase
    end
end
endmodule
