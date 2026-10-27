`timescale 1ns/1ps
module arbiter_edge_tb;
 reg clk=0,rst=0; always #5 clk=~clk;
 reg [1:0] av=0,rv=0; reg awready=0,wready=0,wlast=0,arready=0,rvalid=0,rlast=0;
 wire [1:0] swr,swl,srv,srl; wire awvalid,arvalid;
 dual_ddr_arbiter dut(.clk(clk),.rst_n(rst),.s_awaddr(56'd0),.s_awlen(8'd0),.s_awvalid(av),
 .s_awready(),.s_wdata(512'd0),.s_wstrb(64'd0),.s_wready(swr),.s_wlast(swl),
 .s_araddr(56'd0),.s_arlen(8'd0),.s_arvalid(rv),.s_arready(),.s_rvalid(srv),.s_rlast(srl),
 .awaddr(),.awlen(),.awvalid(awvalid),.awready(awready),.wdata(),.wstrb(),.wready(wready),.wlast(wlast),
 .araddr(),.arlen(),.arvalid(arvalid),.arready(arready),.rvalid(rvalid),.rlast(rlast));
 integer i,k,checks=0;
 initial begin
  #20; rst=1;
  for(k=0;k<3;k=k+1) for(i=0;i<2;i=i+1) begin
   @(negedge clk); av=1<<i; rv=1<<i;
   wait(awvalid && arvalid);
   @(negedge clk); awready=1; arready=1;
   if(k==0) begin wready=1;wlast=1;rvalid=1;rlast=1;end
   @(posedge clk);
   if(k==0 && (swr!==(1<<i) || srv!==(1<<i)))
    $fatal(1,"EARLY_BEAT_LOST source=%0d write=%b read=%b",i,swr,srv);
   @(negedge clk);av=0;rv=0;awready=0;arready=0;
   if(k!=0) begin
    if(k==2) repeat(4) @(negedge clk);
    wready=1;wlast=1;rvalid=1;rlast=1;
    #1; if(swr!==(1<<i) || srv!==(1<<i) || swl!==(1<<i) || srl!==(1<<i)) $fatal(1,"Wrong owner");
    @(posedge clk);
   end
   @(negedge clk);wready=0;wlast=0;rvalid=0;rlast=0;
   repeat(3) @(negedge clk);checks=checks+1;
  end
  $display("ARBITER_EDGE_PASS transactions=%0d same_cycle_and_adjacent_and_gap=1",checks);$finish;
 end
 initial begin #20000;$fatal(1,"timeout");end
endmodule

