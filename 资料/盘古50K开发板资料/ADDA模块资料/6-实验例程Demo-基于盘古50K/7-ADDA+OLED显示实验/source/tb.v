`timescale   1ns / 1ps
module tb(

   );
reg clk;
reg rst_n;
wire rs;
wire reset;
wire scl;
wire sda;

initial
begin
    rst_n    <=    0;
    clk      <=    0;
    #2000
    rst_n    <=    1;

end

always#10 clk = ~clk;//20ns  50MHZ

GTP_GRS GRS_INST(
    .GRS_N(1'b1)
    ) ;
oled_test oled_test
    (
    .sys_clk(clk),          // input
    .rst_n(rst_n),              // input
    .rs(rs),                    // output
    .reset(reset),              // output
    .scl(scl),                  // output
    .sda(sda)                   // output
);



endmodule