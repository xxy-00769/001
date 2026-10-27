`timescale 1ns/1ps
module cam0_ae_profile_tb;
 reg clk=0;always #500 clk=~clk;
 reg rst_n=0,enable=0;
 tri1 scl,sda;
 reg slave_low=0,hold_clock=0;
 assign sda=slave_low?1'b0:1'bz;
 assign scl=hold_clock?1'b0:1'bz;
 assign scl=enable?1'bz:1'b1;
 wire configured,failed;wire[15:0] last;wire[3:0] err;
 cam0_ae_profile #(.CLOCK_HZ(1000000),.SCCB_HZ(100000)) dut(
 .clk(clk),.rst_n(rst_n),.enable(enable),.scl(scl),.sda(sda),
 .configured(configured),.failed(failed),.last_register(last),.error_code(err));
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

 task automatic write_sensor(input[15:0] address,input[7:0] value,input bit reject);
 begin:respond_write
  wait_start();check_byte(8'h78);slave_ack(reject);
  if(reject) begin wait_stop();disable respond_write;end
  check_byte(address[15:8]);slave_ack(0);
  check_byte(address[7:0]);slave_ack(0);
  check_byte(value);slave_ack(0);wait_stop();
 end endtask
 task automatic reset_dut;
 begin
  @(negedge clk);rst_n=0;enable=0;slave_low=0;hold_clock=0;
  repeat(8) @(negedge clk);
  if(configured || failed || scl!==1 || sda!==1) $fatal(1,"reset state");
  rst_n=1;repeat(20) @(negedge clk);
  if(configured || failed || dut.rs || dut.ws) $fatal(1,"started before legacy done");
  enable=1;
 end endtask
 reg [15:0] a[0:17];reg[7:0] initial_value[0:17],wanted[0:17];integer j;
 initial begin
  // Independent expected datasheet addresses and explicit nonzero reserved bits.
  a[0]=16'h300a;a[1]=16'h300b;a[2]=16'h3503;a[3]=16'h3a00;
  a[4]=16'h3a02;a[5]=16'h3a03;a[6]=16'h3a14;a[7]=16'h3a15;
  a[8]=16'h3a18;a[9]=16'h3a19;a[10]=16'h3a08;a[11]=16'h3a09;
  a[12]=16'h3a0a;a[13]=16'h3a0b;a[14]=16'h3a0d;a[15]=16'h3a0e;
  a[16]=16'h3c00;a[17]=16'h3c01;
  initial_value[0]=8'h56;wanted[0]=8'h56;initial_value[1]=8'h40;wanted[1]=8'h40;
  initial_value[2]=8'haf;wanted[2]=8'hac;
  initial_value[3]=8'h7c;wanted[3]=8'h78;
  initial_value[4]=8'h02;wanted[4]=0;initial_value[5]=8'he0;wanted[5]=8'hde;
  initial_value[6]=8'ha2;wanted[6]=8'ha0;initial_value[7]=8'he0;wanted[7]=8'hde;
  initial_value[8]=8'hf3;wanted[8]=8'hf0;initial_value[9]=8'hf8;wanted[9]=8'h80;
  initial_value[10]=8'hac;wanted[10]=8'hac;initial_value[11]=8'h6f;wanted[11]=8'hde;
  initial_value[12]=8'hfc;wanted[12]=8'hfc;initial_value[13]=8'h5c;wanted[13]=8'hb9;
  initial_value[14]=8'hc8;wanted[14]=8'hc1;initial_value[15]=8'h86;wanted[15]=8'h81;
  initial_value[16]=8'hd0;wanted[16]=8'hd4;initial_value[17]=8'h34;wanted[17]=8'hb4;
  reset_dut();
  for(j=0;j<18;j=j+1) begin
   sensor(a[j],initial_value[j],-1);
   if(j>=2) begin write_sensor(a[j],wanted[j],0);sensor(a[j],wanted[j],-1);end
   if(configured) $fatal(1,"premature ready");
  end
  wait(configured);#1;if(failed || err) $fatal(1,"success failed");
  repeat(200) @(negedge clk);
  if(dut.rs || dut.ws) $fatal(1,"unexpected continuing writes");
  reset_dut();sensor(a[0],8'h36,-1);wait(failed);#1;
  if(configured || err!=3) $fatal(1,"wrong sensor accepted");
  reset_dut();sensor(a[0],8'h56,2);wait(failed);#1;
  if(configured || err!=1) $fatal(1,"read nack ignored");
  reset_dut();hold_clock=1;wait(failed);#1;
  if(configured || err!=2) $fatal(1,"read timeout ignored");hold_clock=0;
  reset_dut();sensor(a[0],8'h56,-1);sensor(a[1],8'h40,-1);
  sensor(a[2],initial_value[2],-1);write_sensor(a[2],wanted[2],1);wait(failed);#1;
  if(configured || err!=4) $fatal(1,"write nack ignored");
  reset_dut();sensor(a[0],8'h56,-1);sensor(a[1],8'h40,-1);
  sensor(a[2],initial_value[2],-1);write_sensor(a[2],wanted[2],0);
  sensor(a[2],wanted[2]^8'h80,-1);wait(failed);#1;
  if(configured || err!=6) $fatal(1,"preserved-bit mismatch ignored");
  reset_dut();sensor(a[0],8'h56,-1);sensor(a[1],8'h40,-1);
  sensor(a[2],initial_value[2],-1);
  wait(dut.ws);hold_clock=1;wait(failed);#1;
  if(configured || err!=5) $fatal(1,"write timeout ignored");hold_clock=0;
  reset_dut();
  for(j=0;j<18;j=j+1) begin
   sensor(a[j],initial_value[j],-1);
   if(j>=2) begin write_sensor(a[j],wanted[j],0);sensor(a[j],wanted[j],-1);end
  end
  wait(configured);#1;if(failed) $fatal(1,"reinit failed");
  $display("PASS CAM0 AE profile: production SCCB ID5640, RMW/reserved bits, cap222 gain128 bands222/185 manual50Hz, all ACKs, mismatch, timeouts, reset/reconfigure; no early-ready");$finish;
 end
 initial begin #200000000;$fatal(1,"deadline");end
endmodule
