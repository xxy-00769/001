`timescale 1ns/1ps
module cam0_row_tb;
 reg clk=0;always #10 clk=~clk;
 reg rst_n=0,href=0,vs=0;
 wire [15:0] ticks;
 cam0_row_period dut(.clk(clk),.rst_n(rst_n),.href(href),.vs(vs),.ticks(ticks));
 task frame(input integer spacing);
  begin
   @(negedge clk);vs=1;repeat(50) @(negedge clk);
   vs=0;repeat(3000) @(negedge clk);
   // Full720 active rows. VS blanking must never pollute the mean row period.
   for(integer j=0;j<720;j=j+1) begin
    href=1;repeat(30) @(negedge clk);href=0;
    repeat(spacing-30) @(negedge clk);
   end
  end
 endtask
 initial begin
  repeat(8) @(negedge clk);rst_n=1;
  frame(2252);if(ticks!=2252) $fatal(1,"row ticks %d expected2252",ticks);
  frame(2500);if(ticks!=2500) $fatal(1,"row ticks %d expected2500",ticks);
  frame(2252);if(ticks!=2252) $fatal(1,"VS reset of averaging failed");
  rst_n=0;#1;if(ticks!=0) $fatal(1,"reset");
  $display("PASS CAM0 physical row period: full720 rows,256 interval average, changed cadence, VS gap exclusion, reset");
  $finish;
 end
endmodule
