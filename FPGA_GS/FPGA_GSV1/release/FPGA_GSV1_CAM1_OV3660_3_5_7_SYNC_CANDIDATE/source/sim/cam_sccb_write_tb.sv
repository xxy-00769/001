`timescale 1ns/1ps
module cam_sccb_write_tb;
 reg clk=0;always #10 clk=~clk;
 reg rst_n=0,start=0,slave_low=0,hold_clock=0;
 tri1 scl,sda;
 assign sda=slave_low ? 1'b0:1'bz;
 assign scl=hold_clock ? 1'b0:1'bz;
 wire busy,done,timeout;wire [3:0] nacks;
 cam_sccb_write16 #(.WAIT_TICKS(12)) dut(.clk(clk),.rst_n(rst_n),.start(start),
  .address(7'h3c),.register_address(16'h3808),.value(8'h05),.scl(scl),.sda(sda),
  .busy(busy),.done(done),.nack_mask(nacks),.bus_timeout(timeout));
 task automatic receive(input [7:0] expected,input bit reject);
  reg [7:0] got;integer j;
  begin
   for(j=7;j>=0;j=j-1) begin @(posedge scl);#1;got[j]=sda;end
   if(got!==expected) $fatal(1,"write wire %h expected %h",got,expected);
   @(negedge scl);#1;slave_low=!reject;
   @(posedge scl);@(negedge scl);#1;slave_low=0;
  end
 endtask
 task automatic respond(input integer rejection);
  integer j;reg [7:0] octet;
  begin
   do @(negedge sda);while(scl!==1);
   for(j=0;j<4 && (rejection<0 || j<=rejection);j=j+1) begin
    case(j) 0:octet=8'h78;1:octet=8'h38;2:octet=8'h08;3:octet=8'h05;endcase
    receive(octet,j==rejection);
   end
   do @(posedge sda);while(scl!==1);
  end
 endtask
 integer i;
 initial begin
  repeat(8) @(negedge clk);rst_n=1;
  for(i=-1;i<4;i=i+1) begin
   fork
    respond(i);
    begin @(negedge clk);start=1;@(negedge clk);start=0;wait(done);#1;
     if(timeout || (i<0 && nacks!=0) || (i>=0 && !nacks[i])) $fatal(1,"ACK failure accepted");
    end
   join
   repeat(8) @(negedge clk);
  end
  hold_clock=1;@(negedge clk);start=1;@(negedge clk);start=0;wait(done);#1;
  if(!timeout || nacks==0) $fatal(1,"stuck bus accepted");
  hold_clock=0;rst_n=0;#1;if(scl!==1 || sda!==1 || busy!==0) $fatal(1,"bus reset release");
  $display("PASS production SCCB write divider: 0x78/16-bit address/data, all 4 ACK phases, STOP, stuck SCL timeout, reset release");
  $finish;
 end
 initial begin #12000000;$fatal(1,"write deadline");end
endmodule
