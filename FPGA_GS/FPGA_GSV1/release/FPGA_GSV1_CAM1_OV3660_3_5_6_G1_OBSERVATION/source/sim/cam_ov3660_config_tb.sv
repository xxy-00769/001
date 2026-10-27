`timescale 1ns/1ps
module cam_ov3660_config_tb;
 reg clk=0;always #500 clk=~clk; // actual 1MHz test clock; waits remain in ms
 reg rst_n=0,enable=0,slave_low=0;
 tri1 scl,sda;assign sda=slave_low ? 1'b0:1'bz;
 wire finished,identified,idtimeout,configured,failed;
 wire [15:0] id,confirm,nacks,lastreg;wire [7:0] errorcode;
 cam_ov3660_config #(.CLOCK_HZ(1000000),.SCCB_HZ(100000),.WAIT_TICKS(12)) dut(
  .clk(clk),.rst_n(rst_n),.enable(enable),.scl(scl),.sda(sda),
  .id_finished(finished),.identified(identified),.sensor_id(id),.confirmation_id(confirm),
  .nack_masks(nacks),.id_timeout(idtimeout),.configured(configured),.failed(failed),
  .last_register(lastreg),.error_code(errorcode));
 reg [7:0] memory[0:65535];reg [23:0] expected_entries[0:234];
 integer writes=0,reads=0;realtime reset_stop,enable_stop;
 task automatic wait_start;
  begin do @(negedge sda);while(scl!==1);end
 endtask
 task automatic wait_stop;
  begin do @(posedge sda);while(scl!==1);end
 endtask
 task automatic byte_in(output [7:0] value);
  integer j;
  begin
   for(j=7;j>=0;j=j-1) begin @(posedge scl);#1;value[j]=sda;end
  end
 endtask
 task automatic ack(input bit rejected);
  begin
   @(negedge scl);#1;slave_low=!rejected;
   @(posedge scl);@(negedge scl);#1;slave_low=0;
  end
 endtask
 task automatic check_byte(input [7:0] value);
  reg [7:0] got;
  begin byte_in(got);if(got!==value) $fatal(1,"wire header %h expected %h",got,value);end
 endtask
 task automatic read_transaction(input [15:0] pointer,input [7:0] value);
  integer j;
  begin
   wait_start();check_byte(8'h78);ack(0);check_byte(pointer[15:8]);ack(0);
   check_byte(pointer[7:0]);ack(0);wait_start();check_byte(8'h79);ack(0);
   for(j=7;j>=0;j=j-1) begin slave_low=!value[j];@(posedge scl);@(negedge scl);#1;end
   slave_low=0;@(posedge scl);#1;if(sda!==1) $fatal(1,"read must end in NACK");
   @(negedge scl);wait_stop();reads=reads+1;
  end
 endtask
 task automatic identify(input [15:0] chip);
  begin
   read_transaction(16'h300a,chip[15:8]);read_transaction(16'h300b,chip[7:0]);
   read_transaction(16'h300a,chip[15:8]);read_transaction(16'h300b,chip[7:0]);
  end
 endtask
 task automatic write_transaction(input [23:0] expected,input bit reject_data);
  reg [7:0] h,l,data;
  begin
   wait_start();
   if(writes==1 && $realtime-reset_stop<100000000) $fatal(1,"reset wait shorter than 100ms");
   check_byte(8'h78);ack(0);byte_in(h);ack(0);byte_in(l);ack(0);byte_in(data);ack(reject_data);
   if({h,l,data}!==expected) $fatal(1,"configuration stream mismatch %h expected %h",{h,l,data},expected);
   if(!reject_data) memory[{h,l}]=data;
   wait_stop();writes=writes+1;
   if({h,l,data}==24'h300882) reset_stop=$realtime;
   if({h,l,data}==24'h300802) enable_stop=$realtime;
  end
 endtask
 function automatic [15:0] verify_addr(input integer i);
  case(i)
   0:verify_addr=16'h3808;1:verify_addr=16'h3809;2:verify_addr=16'h380a;3:verify_addr=16'h380b;
   4:verify_addr=16'h501f;5:verify_addr=16'h4300;6:verify_addr=16'h4740;
   7:verify_addr=16'h303a;8:verify_addr=16'h303b;9:verify_addr=16'h303c;10:verify_addr=16'h303d;
   11:verify_addr=16'h3824;12:verify_addr=16'h460c;13:verify_addr=16'h3820;14:verify_addr=16'h3821;
   15:verify_addr=16'h3814;16:verify_addr=16'h3815;17:verify_addr=16'h5001;default:verify_addr=16'h3008;
  endcase
 endfunction
 task automatic reset_controller;
  begin
   enable=0;rst_n=0;slave_low=0;writes=0;reads=0;
   repeat(8) @(negedge clk);rst_n=1;
   repeat(30) @(negedge clk);
   if(scl!==1 || sda!==1 || configured) $fatal(1,"started without enable");
  end
 endtask
 task automatic valid_sensor(input bit mismatch);
  integer i;reg [15:0] ptr;reg [7:0] value;
  begin
   identify(16'h3660);
   for(i=0;i<235;i=i+1)
    if(expected_entries[i][23:8]!=16'hffff) write_transaction(expected_entries[i],0);
   if(configured) $fatal(1,"ready before readback");
   for(i=0;i<(mismatch ? 1:19);i=i+1) begin
    ptr=verify_addr(i);value=memory[ptr];
    if(mismatch && i==0) value=value^8'h01;
    // First read START occurs inside the task after the mandated settle.
    read_transaction(ptr,value);
    if(i==0 && $realtime-enable_stop<100000000) $fatal(1,"output settle shorter than 100ms");
   end
  end
 endtask
 integer j;
 initial begin
  $readmemh("sim/ov3660_expected.hex",expected_entries);
  reset_controller();
  fork valid_sensor(0);begin enable=1;wait(configured||failed);#1;
   if(!configured||failed||errorcode!=0) $fatal(1,"good table/readback rejected %h %h",lastreg,errorcode);end
  join
  if(writes!=233 || reads!=23 || memory[16'h3808]!=5 || memory[16'h380b]!=8'hd0)
   $fatal(1,"wrong table/transaction count %0d %0d",writes,reads);
  reset_controller();
  fork identify(16'h5640);begin enable=1;wait(failed);#1;
   if(configured||errorcode!=1) $fatal(1,"wrong sensor not blocked");end
  join
  repeat(30) @(negedge clk);if(writes!=0||scl!==1||sda!==1) $fatal(1,"writes after wrong ID");
  reset_controller();
  fork begin identify(16'h3660);write_transaction(24'h300882,1);end
   begin enable=1;wait(failed);#1;if(configured||errorcode!=2||lastreg!=16'h3008) $fatal(1,"write failure accepted");end
  join
  reset_controller();
  fork valid_sensor(1);begin enable=1;wait(failed);#1;
   if(configured||errorcode!=5||lastreg!=16'h3808) $fatal(1,"geometry readback failure accepted");end
  join
  // A new hardware reset discards sticky failure and re-identifies/configures.
  reset_controller();
  fork valid_sensor(0);begin enable=1;wait(configured||failed);#1;
   if(!configured||failed) $fatal(1,"reset recovery failed");end
  join
  $display("PASS OV3660 production wire sequence: two IDs, 233 ACK-checked writes, 100ms reset/settle, 19 critical readbacks, wrong ID/write NACK/readback mismatch refuse ready, reset reconfiguration");
  $finish;
 end
 initial begin #1500000000;$fatal(1,"configuration deadline");end
endmodule
