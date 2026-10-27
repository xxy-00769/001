`timescale 1ns/1ps
// One channel/segment per configuration. Inputs are unsigned codes whose
// different real scales/zero offsets are folded into the three Q36 coefficients.
module residual_requant (
    input clk, rst_n,
    input cfg_valid, output cfg_ready,
    input [16:0] cfg_count,
    input signed [47:0] cfg_gain_a, cfg_gain_b,
    input signed [63:0] cfg_offset,
    input in_valid, output in_ready,
    input [7:0] in_a, in_b,
    output reg out_valid, input out_ready,
    output reg [7:0] out_data,
    output reg out_last,
    output busy, output reg done, output reg fault
);
reg active;
reg [16:0] remaining;
reg signed [47:0] gain_a, gain_b;
reg signed [63:0] offset;
reg product_valid, sum_valid, product_last, sum_last;
reg signed [56:0] pa, pb;
reg signed [65:0] sum;
wire signed [8:0] a=$signed({1'b0,in_a}), b=$signed({1'b0,in_b});
wire signed [65:0] rounded=sum+(66'sd1 <<< 35);
wire [7:0] quantized=sum<=0 ? 8'd0 : sum>=(66'sd255 <<< 36) ? 8'd255 : rounded[43:36];
wire advance=!out_valid || out_ready;
assign cfg_ready=rst_n && !busy && !fault;
assign in_ready=rst_n && active && remaining!=0 && advance && !fault;
assign busy=active || out_valid || product_valid || sum_valid;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        active<=0; remaining<=0; gain_a<=0; gain_b<=0; offset<=0;
        out_valid<=0; out_data<=0; out_last<=0; done<=0; fault<=0;
        product_valid<=0; sum_valid<=0; product_last<=0; sum_last<=0; pa<=0; pb<=0; sum<=0;
    end else begin
        done<=0;
        if (cfg_valid && cfg_ready) begin
            if (cfg_count==0 || cfg_count>65536) fault<=1;
            else begin
                active<=1; remaining<=cfg_count;
                gain_a<=cfg_gain_a; gain_b<=cfg_gain_b; offset<=cfg_offset;
            end
        end
        if (out_valid && out_ready) begin
            if (out_last) begin active<=0; done<=1; end
        end
        // A stalled output freezes all stages and their last-element tags.
        if (advance) begin
            out_valid<=sum_valid;
            if (sum_valid) begin out_data<=quantized; out_last<=sum_last; end
            sum_valid<=product_valid;
            if (product_valid) begin
                sum<={{9{pa[56]}},pa}+{{9{pb[56]}},pb}+{{2{offset[63]}},offset};
                sum_last<=product_last;
            end
            product_valid<=in_valid && in_ready;
            if (in_valid && in_ready) begin
                pa<=a*gain_a; pb<=b*gain_b; product_last<=remaining==1;
                remaining<=remaining-1'b1;
            end
        end
    end
end
endmodule
