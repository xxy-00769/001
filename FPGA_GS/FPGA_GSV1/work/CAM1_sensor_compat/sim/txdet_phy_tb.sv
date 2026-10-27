`timescale 1ns/1ps
module txdet_phy_tb;
 reg clk=0,rx=0,rst=0,phy_rstn=0;
 always #10 clk=~clk;always #4 rx=~rx;
 tri1 mdio;wire mdc,ready,configured;wire [4:0] address;wire [15:0] status;wire [127:0] diag;
 reg corrupt_verify=1,bad_page=0,deny_ack=0;
 m36_phy2 #(.START_CYCLES(10),.POLL_CYCLES(30),.MDIO_HALF(2),
 .STRAP_ONLY(0),.TX_DELAY_ENABLE(1),.RX_DELAY_ENABLE(1)) dut(
 .clk(clk),.rst_n(rst),.phy_rstn(phy_rstn),.rx_clock(rx),.mdc(mdc),.mdio(mdio),
 .ready(ready),.configured(configured),.address(address),.status(status),.diagnostics(diag));
 reg slave_drive=0,slave_bit=1;assign mdio=slave_drive ? slave_bit:1'bz;
 integer bitno=0,transactions=0,writes=0;reg [63:0] wireword=0;
 reg [15:0] answer,delay_reg=16'h8575,phy_status=16'hac00;
 reg [15:0] page=0,ext=0;integer pa,ra;reg rdop;
 always @(posedge mdc) begin
  wireword={wireword[62:0],mdio};
  if(bitno==45) begin
   if(wireword[45:14]!==32'hffffffff || wireword[13:12]!==2'b01) $fatal(1,"MDIO framing");
   rdop=wireword[11:10]==2'b10;pa=wireword[9:5];ra=wireword[4:0];
   answer=16'hffff;
   if(pa==7) case(ra)
    2:answer=16'h001c;
    3:answer=16'hc915;
    28:answer=(page==7 && ext==16'ha4) ? ((corrupt_verify && dut.step==7) ? delay_reg^16'h0800:delay_reg):16'hffff;
    17:answer=phy_status;
    31:answer=(bad_page && dut.step==9) ? 1:page;
   endcase
   // A responding but incorrect PHY ID must not be configured.
   if(pa==3) answer=16'h1234;
  end
  if(bitno==63) begin
   transactions++;
   if(!rdop && pa==7) begin
    writes++;
    case(ra)
     31:page=wireword[15:0];
     30:ext=wireword[15:0];
     28:begin
      if(page!=7 || ext!=16'ha4 || (wireword[15:0]&16'hc7ff)!=16'h8575) $fatal(1,"MDIO reserved bits/page");
      delay_reg=wireword[15:0];
     end
    endcase
   end
   bitno=0;
  end else bitno++;
 end
 always @(negedge mdc) begin
  slave_drive=rdop && (pa==7 || pa==3) && bitno>=47;
  slave_bit=bitno==47 ? deny_ack:bitno>=48 ? answer[63-bitno]:1;
 end

 always @(posedge clk) if(ready) begin
  if(!dut.verified || !configured || page!=0 || (delay_reg & 16'h3800)!=16'h3800)
   $fatal(1,"ready before verified forced configuration/page restore");
 end
 integer prior_fail,prior_noack,prior_writes;
 initial begin
  #101;rst=1;phy_rstn=1;
  wait(dut.delay_fail!=0);#1;if(ready || configured) $fatal(1,"readback failure not gated");
  corrupt_verify=0;wait(ready);
  if(address!=7 || delay_reg!=16'hbd75 || page!=0 || dut.wrong_id==0) $fatal(1,"RMW/scan/normal page");
  prior_fail=dut.delay_fail;bad_page=1;
  // Re-run the configuration through hardware reset, retaining diagnostic counts.
  phy_rstn=0;#201;page=0;ext=0;delay_reg=16'h8575;phy_rstn=1;
  wait(dut.delay_fail>prior_fail);#1;if(ready || configured) $fatal(1,"page verify failure not gated");
  bad_page=0;wait(ready);
  prior_noack=dut.no_ack;deny_ack=1;wait(dut.no_ack>prior_noack);
  #1;if(ready || configured) $fatal(1,"MDIO failure not gated");
  deny_ack=0;wait(ready);
  prior_writes=writes;phy_rstn=0;#201;page=0;ext=0;delay_reg=16'h8575;phy_rstn=1;
  wait(ready);if(writes<=prior_writes || delay_reg!=16'hbd75 || page!=0) $fatal(1,"PHY reset not reconfigured");
  $display("TXDET_PHY_PASS ID_scan=1 RMW_reserved=1 TX_RX_force=1 readback_reject=1 page_reject=1 MDIO_recover=1 hardware_reset_reapply=1 ready_gated=1");$finish;
 end
 initial begin #2000000;$fatal(1,"PHY timeout step=%0d address=%0d",dut.step,address);end
endmodule
