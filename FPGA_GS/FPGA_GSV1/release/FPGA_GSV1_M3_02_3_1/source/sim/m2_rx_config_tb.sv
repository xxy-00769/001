`timescale 1ns/1ps
// Register-transaction BFM; validates control/EDID sequence, not physical I2C.
module m2_rx_config_tb;
 reg clk=0,rst=0;always #50 clk=~clk;
 wire done,trigger,write_read;wire [7:0] device,data;wire [15:0] address;
 reg busy=0,byte_done=0;reg [7:0] read_data=0;
 ms7200_ctl dut(.clk(clk),.rstn(rst),.init_over(done),.device_id(device),.iic_trig(trigger),
  .w_r(write_read),.addr(address),.data_in(data),.busy(busy),.data_out(read_data),.byte_over(byte_done));
 reg [7:0] edid[0:255],expected[0:255];integer writes=0,polls=0,transactions=0;
 reg released=0;
 initial begin
  $readmemh("edid_expected.hex",expected);
  #500;rst=1;
  forever begin
   @(negedge clk);
   if(trigger && !busy) begin
    busy=1;transactions++;
    // iic_dri detects pluse through three registers before using address.
    repeat(3) @(negedge clk);
    if(device!==8'h56) $fatal(1,"wrong receiver address");
    if(write_read) begin
     if(address>=16'h0d00 && address<=16'h0dff) begin edid[address-16'h0d00]=data;writes++;end
     if(address==16'h000a && data==4) begin
      for(integer i=0;i<256;i++) if(edid[i]!==expected[i]) $fatal(1,"EDID byte %0d mismatch",i);
      if(writes<256) $fatal(1,"EDID incomplete");released=1;
     end
    end else begin
     if(address==16'h0003) read_data=8'h5a;
     else if(address==16'h209e) begin read_data=polls==0 ? 0 : 2;polls++;end
     else read_data=0;
    end
    repeat(5) @(negedge clk);byte_done=1;
    @(negedge clk);byte_done=0;
    repeat(5) @(negedge clk);busy=0;
    if(done) begin
     if(!released || polls<2) $fatal(1,"configuration ordering");
     $display("M2_RX_CONFIG_PASS transactions=%0d edid_writes=%0d checksums=valid release_after_program=1 calibration_polls=%0d",transactions,writes,polls);$finish;
    end
   end
  end
 end
 initial begin #20000000;$fatal(1,"configuration timeout state=%b count=%0d polls=%0d",dut.state,dut.dri_cnt,polls);end
endmodule
