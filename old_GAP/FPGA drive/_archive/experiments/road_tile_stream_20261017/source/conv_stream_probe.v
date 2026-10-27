`timescale 1ns/1ps
// Resource-probe shell only. Configuration and data share pins because their
// accepted phases are disjoint. No board pinout, DDR or production bus implied.
module conv_stream_probe (
    input clk, rst_n,
    input [3:0] command,
    input [127:0] payload,
    input [15:0] address,
    input [1:0] kind,
    input [15:0] keep,
    input out_ready,
    output cfg_ready, load_ready, vec_ready, start_ready,
    output busy, fault, done, cache_valid, out_valid,
    output [31:0] cached_weights_id,
    output [15:0] out_index,
    output [7:0] out_data,
    output signed [31:0] out_acc
);
conv_cached core (
    .clk(clk), .rst_n(rst_n),
    .cfg_valid(command[0]), .cfg_ready(cfg_ready),
    .cfg_reuse(payload[0]), .cfg_banked_load(payload[1]), .cfg_weights_id(payload[33:2]),
    .cfg_depthwise(payload[34]), .cfg_ci(payload[41:35]), .cfg_co(payload[48:42]),
    .cfg_kernel(payload[50:49]), .cfg_stride(payload[52:51]), .cfg_dilation(payload[56:53]),
    .cfg_iw(payload[61:57]), .cfg_ih(payload[66:62]), .cfg_ow(payload[69:67]), .cfg_oh(payload[72:70]),
    .cache_valid(cache_valid), .cached_weights_id(cached_weights_id),
    .load_valid(command[1]), .load_ready(load_ready), .load_kind(kind),
    .load_addr(address), .load_data(payload[7:0]),
    .vec_valid(command[2]), .vec_ready(vec_ready), .vec_kind(kind),
    .vec_addr(address[11:0]), .vec_data(payload), .vec_keep(keep),
    .start_valid(command[3]), .start_ready(start_ready),
    .busy(busy), .fault(fault), .done(done), .out_valid(out_valid), .out_ready(out_ready),
    .out_index(out_index), .out_data(out_data), .out_acc(out_acc)
);
endmodule
