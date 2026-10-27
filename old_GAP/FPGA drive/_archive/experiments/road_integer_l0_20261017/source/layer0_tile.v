`timescale 1ns/1ps
// First-layer tile only: 17x17x3 uint8 BGR -> 16x8x8 quantized features.
// Loading and computing are mutually exclusive; no board DDR interface here.
module layer0_tile (
    input wire clk, input wire rst_n,
    input wire load_valid, output wire load_ready,
    input wire [9:0] load_addr, input wire [7:0] load_data,
    input wire start_valid, output wire start_ready,
    output wire busy, output reg fault, output reg done,
    output reg out_valid, input wire out_ready,
    output wire [9:0] out_index,
    output reg [7:0] out_data, output reg signed [31:0] out_acc
);
localparam IDLE=3'd0, READ=3'd1, MAC=3'd2, QUANT=3'd3, HOLD=3'd4;
reg [2:0] state;
reg [7:0] pixels [0:866];
reg [9:0] loaded;
reg [9:0] index;
reg [1:0] ci, ky, kx;
reg [7:0] pixel_reg;
reg signed [7:0] weight_reg;
reg signed [23:0] accumulator;
wire [3:0] channel = index[9:6];
wire [4:0] iy = {1'b0, index[5:3], 1'b0} + {3'd0, ky};
wire [4:0] ix = {1'b0, index[2:0], 1'b0} + {3'd0, kx};
wire [9:0] pixel_addr = iy * 10'd51 + ix * 10'd3 + ci;
wire [8:0] weight_addr = channel * 9'd27 + ci * 9'd9 + ky * 9'd3 + kx;
wire [7:0] input_code;
wire signed [7:0] weight_value;
wire signed [31:0] gain;
wire signed [47:0] offset;
wire signed [8:0] unsigned_pixel = $signed({1'b0, pixel_reg});
wire signed [16:0] product = unsigned_pixel * weight_reg;
wire signed [23:0] extended_product = {{7{product[16]}}, product};
wire signed [55:0] scaled_product = accumulator * gain;
wire signed [56:0] scaled = {scaled_product[55], scaled_product} + {{9{offset[47]}}, offset};
wire signed [56:0] rounded = scaled + (57'sd1 <<< 35);
wire [7:0] quantized = (scaled <= 0) ? 8'd0 :
                       (scaled >= (57'sd255 <<< 36)) ? 8'd255 : rounded[43:36];

assign load_ready = rst_n && state == IDLE && loaded < 867 && !fault;
assign start_ready = rst_n && state == IDLE && loaded == 867 && !fault;
assign busy = state != IDLE;
assign out_index = index;

layer0_params params(.raw_pixel(load_data), .weight_addr(weight_addr), .channel(channel),
                     .input_code(input_code), .weight(weight_value), .gain(gain), .offset(offset));

// Synchronous tile read. RAM is not reset; exactly 867 ordered writes are required.
always @(posedge clk) begin
    if (load_valid && load_ready && load_addr == loaded)
        pixels[load_addr] <= input_code;
    if (state == READ) begin
        pixel_reg <= pixels[pixel_addr];
        weight_reg <= weight_value;
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= IDLE;
        loaded <= 0;
        index <= 0;
        ci <= 0;
        ky <= 0;
        kx <= 0;
        accumulator <= 0;
        fault <= 0;
        done <= 0;
        out_valid <= 0;
        out_data <= 0;
        out_acc <= 0;
    end else begin
        done <= 0;
        case (state)
        IDLE: begin
            if (load_valid && load_ready) begin
                if (load_addr == loaded) loaded <= loaded + 1'b1;
                else fault <= 1;
            end
            if (start_valid && start_ready) begin
                index <= 0;
                ci <= 0;
                ky <= 0;
                kx <= 0;
                accumulator <= 0;
                state <= READ;
            end
        end
        READ: state <= MAC;
        MAC: begin
            accumulator <= accumulator + extended_product;
            if (kx == 2) begin
                kx <= 0;
                if (ky == 2) begin
                    ky <= 0;
                    if (ci == 2) begin
                        ci <= 0;
                        state <= QUANT;
                    end else begin
                        ci <= ci + 1'b1;
                        state <= READ;
                    end
                end else begin
                    ky <= ky + 1'b1;
                    state <= READ;
                end
            end else begin
                kx <= kx + 1'b1;
                state <= READ;
            end
        end
        QUANT: begin
            out_acc <= {{8{accumulator[23]}}, accumulator};
            out_data <= quantized;
            out_valid <= 1;
            state <= HOLD;
        end
        HOLD: begin
            if (out_ready) begin
                out_valid <= 0;
                if (index == 1023) begin
                    loaded <= 0;
                    done <= 1;
                    state <= IDLE;
                end else begin
                    index <= index + 1'b1;
                    accumulator <= 0;
                    state <= READ;
                end
            end
        end
        default: begin
            state <= IDLE;
            out_valid <= 0;
            loaded <= 0;
            fault <= 1;
        end
        endcase
    end
end
endmodule
