`timescale 1ns/1ps
module cam_sensor_id_tb;
 reg clk=0;always #10 clk=~clk;
 reg rst_n=0,enable=0;
 tri1 scl,sda;
 reg slave_low=0,hold_clock=0;
 assign sda=slave_low ? 1'b0:1'bz;
 assign scl=hold_clock ? 1'b0:1'bz;
 wire finished,identified,timeout;
 wire [15:0] id,confirm,nacks;
 cam_sensor_id #(.CLOCK_HZ(50000000),.SCCB_HZ(100000),.WAIT_TICKS(12)) dut(
  .clk(clk),.rst_n(rst_n),.enable(enable),.scl(scl),.sda(sda),
  .finished(finished),.identified(identified),.sensor_id(id),
  .confirmation_id(confirm),.nack_masks(nacks),.timeout_error(timeout));
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

 task automatic reset_probe;
  begin
   enable=0;rst_n=0;slave_low=0;hold_clock=0;
   repeat(8) @(negedge clk);rst_n=1;
   repeat(30) @(negedge clk);
   if(scl!==1 || sda!==1 || finished) $fatal(1,"probe started before enable");
  end
 endtask
 task automatic identify(input [15:0] primary,secondary,input bit expected);
  begin
   reset_probe();
   fork
    begin
     sensor(16'h300a,primary[15:8],-1);
     sensor(16'h300b,primary[7:0],-1);
     sensor(16'h300a,secondary[15:8],-1);
     sensor(16'h300b,secondary[7:0],-1);
    end
    begin
     enable=1;wait(finished);#1;
     if(identified!==expected || id!==primary || confirm!==secondary || nacks!==0 || timeout)
      $fatal(1,"incorrect identification primary=%h confirmation=%h accept=%b nacks=%h",id,confirm,identified,nacks);
    end
   join
   repeat(100) @(negedge clk);
   if(scl!==1 || sda!==1) $fatal(1,"probe did not stop");
  end
 endtask
 integer i;
 initial begin
  identify(16'h3660,16'h3660,1);
  identify(16'h5640,16'h5640,0);
  identify(16'h3660,16'h3661,0);
  for(i=0;i<4;i=i+1) begin
   reset_probe();
   fork
    sensor(16'h300a,8'h36,i);
    begin
     enable=1;wait(finished);#1;
     if(identified || !nacks[i] || timeout) $fatal(1,"NACK accepted");
    end
   join
  end
  reset_probe();hold_clock=1;enable=1;wait(finished);#1;
  if(!timeout || identified) $fatal(1,"stuck bus accepted");
  hold_clock=0;
  identify(16'h3660,16'h3660,1);
  $display("PASS ID sequencer: waits enable, 2 independent ID reads, OV3660 matches, OV5640 rejected, unstable ID rejected, each NACK rejected, stuck bus rejected, reset/re-identification");
  $finish;
 end
 initial begin #50000000;$fatal(1,"test deadline");end
endmodule
