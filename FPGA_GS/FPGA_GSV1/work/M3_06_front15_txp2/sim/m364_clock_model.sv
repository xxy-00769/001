`timescale 1ns/1ps
// Logical PLL waveforms from the accepted E1 routed Clock Summary.
// No claim about physical jitter, PCB skew or PLL behavior from simulation.
module m3_eth_pll #(parameter integer TX_PHASE=41)(input clkin1,output reg clkout0=0,clkout1=0,output reg pll_lock=0);
 always @(clkin1) begin clkout0<=#4 clkin1;clkout1<=#((TX_PHASE-16)*0.2) clkin1;end
 always @(posedge clkin1) if($time>1001) pll_lock<=1;
endmodule
