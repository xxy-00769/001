`timescale 1ns/1ps
module cam_sccb_id_tb;
 reg clk=0;always #10 clk=~clk;
 reg rst_n=0,start=0;
 reg [15:0] regaddr=16'h300a;
 tri1 scl,sda;
 reg slave_low=0,hold_clock=0;
 assign sda=slave_low ? 1'b0:1'bz;
 assign scl=hold_clock ? 1'b0:1'bz;
 wire busy,done,timeout;
 wire [7:0] data;
 wire [3:0] nacks;
 cam_sccb_read16 #(.CLOCK_HZ(50000000),.SCCB_HZ(100000),.WAIT_TICKS(12)) dut(
   .clk(clk),.rst_n(rst_n),.start(start),.address(7'h3c),.register_address(regaddr),
   .scl(scl),.sda(sda),.busy(busy),.done(done),.data(data),
   .nack_mask(nacks),.bus_timeout(timeout));
 task automatic check_byte(input [7:0] expected);
   reg [7:0] actual;integer i;
   begin
     actual=0;
     for(i=7;i>=0;i=i-1) begin @(posedge scl);#1;actual[i]=sda;end
     if(actual!==expected) $fatal(1,"wire byte expected %h got %h",expected,actual);
   end
 endtask
 task automatic slave_ack(input bit reject);
   begin
     @(negedge scl);#1;slave_low=!reject;
     @(posedge scl);@(negedge scl);#1;slave_low=0;
   end
 endtask
 task automatic wait_start;
   begin do @(negedge sda);while(scl!==1);end
 endtask
 task automatic wait_stop;
   begin do @(posedge sda);while(scl!==1);end
 endtask
 task automatic sensor(input [15:0] address,input [7:0] value,input integer reject_index);
   integer i;
   begin:respond
     wait_start();check_byte(8'h78);slave_ack(reject_index==0);
     if(reject_index==0) begin wait_stop();disable respond;end
     check_byte(address[15:8]);slave_ack(reject_index==1);
     if(reject_index==1) begin wait_stop();disable respond;end
     check_byte(address[7:0]);slave_ack(reject_index==2);
     if(reject_index==2) begin wait_stop();disable respond;end
     wait_start();check_byte(8'h79);slave_ack(reject_index==3);
     if(reject_index==3) begin wait_stop();disable respond;end
     for(i=7;i>=0;i=i-1) begin
       // ACK task has already observed the first falling data edge.
       slave_low=!value[i];@(posedge scl);@(negedge scl);#1;
     end
     slave_low=0;@(posedge scl);#1;
     if(sda!==1) $fatal(1,"master must NACK final read byte");
     @(negedge scl);wait_stop();
   end
 endtask
 task automatic transact(input [15:0] address,input [7:0] value,input integer reject_index);
   begin
     regaddr=address;
     fork
       sensor(address,value,reject_index);
       begin
         @(negedge clk);start=1;@(negedge clk);start=0;
         wait(done);#1;
         if(timeout) $fatal(1,"unexpected timeout");
         if(reject_index<0 && (data!==value || nacks!==0))
           $fatal(1,"read result got %h nacks %h",data,nacks);
         if(reject_index>=0 && !nacks[reject_index]) $fatal(1,"missing NACK evidence");
       end
     join
     repeat(5) @(negedge clk);
   end
 endtask
 integer i;
 initial begin
   repeat(8) @(negedge clk);rst_n=1;
   // OV3660 and OV5640 ID byte patterns. These simulated values are not
   // hardware sensor identification evidence.
   transact(16'h300a,8'h36,-1);transact(16'h300b,8'h60,-1);
   transact(16'h300a,8'h56,-1);transact(16'h300b,8'h40,-1);
   for(i=0;i<4;i=i+1) transact(16'h300a,8'h36,i);
   hold_clock=1;@(negedge clk);start=1;@(negedge clk);start=0;
   wait(done);#1;if(!timeout || nacks==0) $fatal(1,"stuck SCL accepted");
   hold_clock=0;repeat(8) @(negedge clk);
   transact(16'h300a,8'h36,-1);
   // Asynchronous reset must release both lines during an active read.
   @(negedge clk);start=1;@(negedge clk);start=0;wait(busy);
   repeat(12) @(negedge clk);rst_n=0;#1;
   if(scl!==1 || sda!==1 || busy!==0) $fatal(1,"reset did not release bus");
   $display("PASS wire SCCB: 0x78/0x79, 16-bit MSB-first pointers, repeated START, both ID patterns, all four NACK phases, final NACK, timeout/recovery/reset");
   $finish;
 end
 initial begin #15000000;$fatal(1,"test deadline");end
endmodule
