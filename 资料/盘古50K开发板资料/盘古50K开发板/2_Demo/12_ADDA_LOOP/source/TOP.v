module TOP(
   input  wire clk_50M ,
   input  wire rst_n ,
   output wire ad_clk /* synthesis PAP_MARK_DEBUG="true" */,
   input  wire [7:0]ad_data /* synthesis PAP_MARK_DEBUG="true" */,
   output wire [7:0]da_data /* synthesis PAP_MARK_DEBUG="true" */,
   output wire da_clk/* synthesis PAP_MARK_DEBUG="true" */

   );

wire lock ;
wire clk_125M ;
wire clk_35M ;
reg  [7:0]cnt ;
wire clk_10M ;

assign da_clk = clk_35M  ;
assign da_data = cnt  ;
assign ad_clk = clk_35M ;

ad_clock_125m u_pll (
  .clkin1(clk_50M),          // input
  .pll_lock(lock),          // output
  .clkout0(clk_125M) ,        // output
  .clkout1(clk_35M),      // output
  .clkout2(clk_10M)       // output       // output
);

always @(negedge clk_10M or negedge rst_n) begin
   if (~rst_n)
      cnt <= 8'd0 ;
//   else if (cnt == 8'd127)
//      cnt <= 8'd0 ;
   else 
      cnt <= cnt - 1'b1 ; 
end



endmodule