`timescale 1ns/1ps
module cam_ov3660_config_tb #(parameter ROTATE_180=1);
 reg clk=0;always #500 clk=~clk; // actual 1MHz test clock; waits remain in ms
 reg rst_n=0,enable=0,slave_low=0;
 tri1 scl,sda;assign sda=slave_low ? 1'b0:1'bz;
 wire finished,identified,idtimeout,configured,failed;
 wire [15:0] id,confirm,nacks,lastreg;wire [7:0] errorcode;
 cam_ov3660_config #(.ROTATE_180(ROTATE_180),.CLOCK_HZ(1000000),.SCCB_HZ(100000),.WAIT_TICKS(12)) dut(
  .clk(clk),.rst_n(rst_n),.enable(enable),.scl(scl),.sda(sda),
  .id_finished(finished),.identified(identified),.sensor_id(id),.confirmation_id(confirm),
  .nack_masks(nacks),.id_timeout(idtimeout),.configured(configured),.failed(failed),
  .last_register(lastreg),.error_code(errorcode));
 reg [7:0] memory[0:65535];reg [23:0] expected_entries[0:247];
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
   15:verify_addr=16'h3814;16:verify_addr=16'h3815;17:verify_addr=16'h5001;
   18:verify_addr=16'h4514;19:verify_addr=16'h380c;20:verify_addr=16'h380d;
   21:verify_addr=16'h380e;22:verify_addr=16'h380f;23:verify_addr=16'h3a00;
   24:verify_addr=16'h3a05;25:verify_addr=16'h3a02;26:verify_addr=16'h3a03;
   27:verify_addr=16'h3a14;28:verify_addr=16'h3a15;29:verify_addr=16'h3a08;
   30:verify_addr=16'h3a09;31:verify_addr=16'h3a0a;32:verify_addr=16'h3a0b;
   33:verify_addr=16'h3a0e;34:verify_addr=16'h3a0d;35:verify_addr=16'h3503;
   36:verify_addr=16'h3800;37:verify_addr=16'h3801;38:verify_addr=16'h3802;
   39:verify_addr=16'h3803;40:verify_addr=16'h3804;41:verify_addr=16'h3805;
   42:verify_addr=16'h3806;43:verify_addr=16'h3807;default:verify_addr=16'h3008;
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
 task automatic valid_sensor(input integer mismatch);
  integer i;reg [15:0] ptr;reg [7:0] value;
  begin
   identify(16'h3660);
   for(i=0;i<248;i=i+1)
    if(expected_entries[i][23:8]!=16'hffff) write_transaction(expected_entries[i],0);
   if(configured) $fatal(1,"ready before readback");
   for(i=0;i<(mismatch==1 ? 1:(mismatch==2 ? 7:(mismatch==3 ? 19:(mismatch==4 ? 24:45))));i=i+1) begin
    ptr=verify_addr(i);value=memory[ptr];
    if(mismatch==1 && i==0) value=value^8'h01;
    if(mismatch==2 && i==6) value=8'h23; // old, electrically wrong profile
    if(mismatch==3 && i==18) value=value^8'h33;
    if(mismatch==4 && i==23) value=value^8'h04; // night mode must stay disabled
    // First read START occurs inside the task after the mandated settle.
    read_transaction(ptr,value);
    if(i==0 && $realtime-enable_stop<100000000) $fatal(1,"output settle shorter than 100ms");
   end
  end
 endtask
 integer j;
 initial begin
  $readmemh("sim/ov3660_expected.hex",expected_entries);
  if(!ROTATE_180) for(j=218;j<=220;j=j+1)
   case(j) 218:expected_entries[j]=24'h382040;219:expected_entries[j]=24'h382100;
    220:expected_entries[j]=24'h451488;endcase
  reset_controller();
  fork valid_sensor(0);begin enable=1;wait(configured||failed);#1;
   if(!configured||failed||errorcode!=0) $fatal(1,"good table/readback rejected %h %h",lastreg,errorcode);end
  join
  if(writes!=246 || reads!=49 || memory[16'h3808]!=5 || memory[16'h380b]!=8'hd0
      || memory[16'h4740]!=8'h20 || {memory[16'h380c],memory[16'h380d]}!=1800
      || {memory[16'h380e],memory[16'h380f]}!=800
      || memory[16'h3820]!=(ROTATE_180?8'h46:8'h40)
      || memory[16'h3821]!=(ROTATE_180?8'h06:8'h00)
      || memory[16'h4514]!=(ROTATE_180?8'hbb:8'h88)
      || memory[16'h5001]!=8'h83 || {memory[16'h3a14],memory[16'h3a15]}!=796)
   $fatal(1,"wrong table/transaction count %0d %0d",writes,reads);
  if(!ROTATE_180) begin $display("PASS normal mounting parameter: full SCCB writes/readbacks, bits preserved");$finish;end
  reset_controller();
  fork valid_sensor(3);begin enable=1;wait(failed);#1;
   if(configured||errorcode!=5||lastreg!=16'h4514) $fatal(1,"mirror/flip companion mismatch accepted");end
  join
  reset_controller();
  fork valid_sensor(4);begin enable=1;wait(failed);#1;
   if(configured||errorcode!=5||lastreg!=16'h3a00) $fatal(1,"night-mode readback mismatch accepted");end
  join
  reset_controller();
  fork identify(16'h5640);begin enable=1;wait(failed);#1;
   if(configured||errorcode!=1) $fatal(1,"wrong sensor not blocked");end
  join
  repeat(30) @(negedge clk);if(writes!=0||scl!==1||sda!==1) $fatal(1,"writes after wrong ID");
  reset_controller();
  fork valid_sensor(2);begin enable=1;wait(failed);#1;
   if(configured||errorcode!=5||lastreg!=16'h4740)
    $fatal(1,"stale 4740=23 profile accepted instead of 20");end
  join
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
  $display("PASS OV3660 production wire sequence: two IDs,246 ACK writes,45 readbacks; rotate46/06/BB;1800x800 native720; exposure796 night-off checked; stale rotation/night/geometry and write NACK refuse ready; reset recovery");
  $finish;
 end
 initial begin #2500000000;$fatal(1,"configuration deadline");end
endmodule
