`timescale 1ns/1ps
// 2048x8 per explicit DRM. One-clock synchronous read; independent clocks.
module m3_byte_ram #(parameter BANKS=1,AW=11+$clog2(BANKS))(
 input wc,we,input [AW-1:0] wa,input [7:0] wd,
 input rc,input [AW-1:0] ra,output [7:0] rd);
 wire [7:0] q[0:BANKS-1];reg [$clog2(BANKS+1)-1:0] sel;
 always @(posedge rc) sel<=ra>>11;
 genvar i;generate for(i=0;i<BANKS;i=i+1) begin: bank
 wire [17:0] unused_q,out_q;
 GTP_DRM18K #(.GRS_EN("FALSE"),.DATA_WIDTH_A(9),.DATA_WIDTH_B(9),
 .WRITE_MODE_A("NORMAL_WRITE"),.DOA_REG(0),.DOB_REG(0),
 .RST_TYPE("ASYNC"),.RAM_MODE("TRUE_DUAL_PORT"),.SIM_DEVICE("LOGOS")) ram(
 .CLKA(wc),.CEA(we && (wa>>11)==i),.WEA(1'b1),
 .ADDRA({wa[10:0],1'b0,2'b11}),.ADDRA_HOLD(1'b0),.DIA({10'd0,wd}),
 .CSA(3'd0),.DOA(unused_q),.ORCEA(1'b0),.RSTA(1'b0),
 .CLKB(rc),.CEB(1'b1),.WEB(1'b0),.ADDRB({ra[10:0],1'b0,2'b11}),.ADDRB_HOLD(1'b0),
 .DIB(18'd0),.CSB(3'd0),.DOB(out_q),.ORCEB(1'b0),.RSTB(1'b0),.WWCONF());
 assign q[i]=out_q[7:0];
 end endgenerate
 assign rd=q[sel];
endmodule
