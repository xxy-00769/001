`timescale 1ns/1ps
module cam0_readback_tb;
 reg clk=0;always #500 clk=~clk;
 reg rst_n=0,enable=0;
 tri1 scl,sda;
 reg slave_low=0,hold_clock=0;
 assign sda=slave_low?1'b0:1'bz;
 assign scl=hold_clock?1'b0:1'bz;
 // The legacy push-pull SCL is high in idle, and must be isolated on enable.
 wire legacy_scl=1;
 assign scl=enable ? 1'bz:legacy_scl;
 wire [351:0] registers;
 wire valid,timeout;wire [7:0] seq,errors;wire [3:0] nacks;
 cam0_readback #(.CLOCK_HZ(1000000),.SCCB_HZ(100000)) dut(
  .clk(clk),.rst_n(rst_n),.enable(enable),.scl(scl),.sda(sda),
  .registers(registers),.valid(valid),.sequence_number(seq),.errors(errors),
  .last_nack(nacks),.last_timeout(timeout));
 reg [15:0] expected[0:43];
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

 integer j;
 reg [351:0] committed;
 initial begin
  expected[0]=16'h300a;
  expected[1]=16'h300b;
  expected[2]=16'h3034;
  expected[3]=16'h3035;
  expected[4]=16'h3036;
  expected[5]=16'h3037;
  expected[6]=16'h3108;
  expected[7]=16'h3039;
  expected[8]=16'h3500;
  expected[9]=16'h3501;
  expected[10]=16'h3502;
  expected[11]=16'h3500;
  expected[12]=16'h3501;
  expected[13]=16'h3503;
  expected[14]=16'h350a;
  expected[15]=16'h350b;
  expected[16]=16'h350c;
  expected[17]=16'h350d;
  expected[18]=16'h380c;
  expected[19]=16'h380d;
  expected[20]=16'h380e;
  expected[21]=16'h380f;
  expected[22]=16'h3a00;
  expected[23]=16'h3a02;
  expected[24]=16'h3a03;
  expected[25]=16'h3a14;
  expected[26]=16'h3a15;
  expected[27]=16'h3a18;
  expected[28]=16'h3a19;
  expected[29]=16'h3a08;
  expected[30]=16'h3a09;
  expected[31]=16'h3a0a;
  expected[32]=16'h3a0b;
  expected[33]=16'h3a0d;
  expected[34]=16'h3a0e;
  expected[35]=16'h3c00;
  expected[36]=16'h3c01;
  expected[37]=16'h3c0c;
  expected[38]=16'h3824;
  expected[39]=16'h460c;
  expected[40]=16'h5000;
  expected[41]=16'h5001;
  expected[42]=16'h5308;
  expected[43]=16'h5306;
  repeat(8) @(negedge clk);rst_n=1;
  repeat(100) @(negedge clk);
  if(scl!==1 || sda!==1 || valid || seq) $fatal(1,"read before init");
  enable=1;
  fork
   begin for(j=0;j<44;j=j+1) begin
    sensor(expected[j],8'h40+j,-1);
    if(seq!=0 || valid) $fatal(1,"partial sweep was published");
   end end
   begin wait(seq==1);#1;
    if(!valid || errors || nacks || timeout) $fatal(1,"successful sweep failed");
    for(integer k=0;k<44;k=k+1)
     if(registers[351-k*8 -: 8] !== 8'h40+k) $fatal(1,"wrong byte packing %d",k);
    committed=registers;
   end
  join
  // One address NACK must reject the new sweep, keep prior bytes and mark invalid.
  for(j=0;j<6;j=j+1) sensor(expected[j],8'h80+j,j==5?2:-1);
  wait(errors==1);#1;
  if(valid || seq!=1 || registers!==committed || nacks!=4'b1100)
   $fatal(1,"NACK did not reject sweep");
  hold_clock=1;wait(errors==2);#1;
  if(valid || !timeout || seq!=1) $fatal(1,"timeout accepted");
  hold_clock=0;
  fork
   begin for(j=0;j<44;j=j+1) sensor(expected[j],8'ha0+j,-1);end
   begin wait(seq==2);#1;if(!valid || nacks || timeout) $fatal(1,"recovery failed");end
  join
  @(negedge clk);rst_n=0;#1;
  if(scl!==1 || sda!==1 || valid || seq) $fatal(1,"reset release failed");
  $display("PASS CAM0 production readback: legacy SCL handoff, all44 actual SCCB addresses, 0x78/79, atomic byte packing, NACK/timeout/no-stale-valid, recovery/reset");$finish;
 end
 initial begin #6000000000;$fatal(1,"deadline");end
endmodule
