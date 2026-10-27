`timescale 1ns/1ps
module m2_joint_tb;
 localparam HEIGHT=32;
 reg clk=0,pc=0,v0=0,v1=0,v2=0,rst=0,fs=0;
 always #5 clk=~clk;
 always #16.923077 pc=~pc;
 always #11.9 v0=~v0;
 initial begin #3;forever #12.3 v1=~v1;end
 initial begin #1.7;forever #6.7340067 v2=~v2;end
 wire [2:0] vc={v2,v1,v0};reg [2:0] online=7,req=0;
 reg [1:0] view=0;
 wire quad=view==3;
 wire [2:0] selected=quad ? 7 : 1<<view;
 wire [83:0] saw,sar;wire [11:0] swlen,srlen;
 wire [2:0] swv,srv,swr,srr,sready,slast,svalid,srlast;
 wire [767:0] swdata;
 wire [27:0] aw,ar;wire [3:0] wl,rl;wire awv,arv;wire [255:0] wd;
 reg awr=0,arr=0,wr=0,last=0,rv=0,rlast=0;reg [255:0] rd=0;
 dual_ddr_arbiter #(.PORTS(3)) arb(.clk(clk),.rst_n(rst),
 .s_awaddr(saw),.s_awlen(swlen),.s_awvalid(swv),.s_awready(swr),
 .s_wdata(swdata),.s_wstrb({96{1'b1}}),.s_wready(sready),.s_wlast(slast),
 .s_araddr(sar),.s_arlen(srlen),.s_arvalid(srv),.s_arready(srr),.s_rvalid(svalid),.s_rlast(srlast),
 .awaddr(aw),.awlen(wl),.awvalid(awv),.awready(awr),.wdata(wd),.wstrb(),.wready(wr),.wlast(last),
 .araddr(ar),.arlen(rl),.arvalid(arv),.arready(arr),.rvalid(rv),.rlast(rlast));
 wire [2:0] valid,init;
 wire [47:0] pixel;
 wire [95:0] display_ids,pubs,faults;
 genvar s;
 generate for(s=0;s<3;s=s+1) begin: source
  m2_source #(.SOURCE(s),.HEIGHT(HEIGHT)) input_source(
   .core_clk(clk),.video_clk(vc[s]),.out_clk(pc),.rst_n(rst),.out_vs(fs),
   .out_de(req[s]),.selected(selected[s]),.quarter(quad),.online(online[s]),
   .awaddr(saw[s*28+:28]),.araddr(sar[s*28+:28]),.awlen(swlen[s*4+:4]),.arlen(srlen[s*4+:4]),
   .awvalid(swv[s]),.arvalid(srv[s]),.wdata(swdata[s*256+:256]),.awready(swr[s]),
   .wready(sready[s]),.wlast(slast[s]),.arready(srr[s]),.rvalid(svalid[s]),.rlast(srlast[s]),.rdata(rd));
  assign valid[s]=input_source.valid;
  assign pixel[s*16+:16]=input_source.pixel;
  assign init[s]=input_source.init_done;
  assign display_ids[s*32+:32]=input_source.dut.display_id;
  assign pubs[s*32+:32]=input_source.dut.published_count;
  assign faults[s*32+:32]=input_source.dut.read_fault_count;
  always @(posedge clk) if(rst) begin
   if(input_source.dut.write_issue &&
    ((input_source.dut.owner.have_reader && input_source.dut.write_bank==input_source.dut.read_bank) ||
     (input_source.dut.owner.pending && input_source.dut.write_bank==input_source.dut.owner.pending_bank)))
    $fatal(1,"write into reader/pending slot source=%0d",s);
  end
 end endgenerate
 reg [255:0] memory[0:15359]; // 3 sources x 2 slots x 2560 beats
 function integer idx(input [27:0] a);
  integer source,slot,offset;
  begin
   source=(a>>23)&3;slot=(a>>22)&1;offset=a&4194303;
   if(a[27:25]!=0 || source>2 || offset>=640*HEIGHT || a%8!=0)
    $fatal(1,"invalid physical native address %h",a);
   idx=(source*2+slot)*(80*HEIGHT)+offset/8;
  end
 endfunction
 function [15:0] pattern(input integer source,tag,row,col);
  pattern=(source<<14)|(((tag*16'h19d7)^(row*16'h031d)^(col*16'h9e37))&16'h3fff);
 endfunction
 integer wb=0,rb=0,wpixels=0,early_w=0,early_r=0;
 integer a,n,b,src,tag,wy,wx,lane;
 initial begin
  wait(rst);
  forever begin
   wait(awv);@(negedge clk);
   a=idx(aw);n=wl+1;src=aw[24:23];
   case(src)
    0:tag=source[0].input_source.dut.owner.active_id;
    1:tag=source[1].input_source.dut.owner.active_id;
    2:tag=source[2].input_source.dut.owner.active_id;
   endcase
   wy=aw[21:0]/640;wx=(aw[21:0]%640)*2;awr=1;
   if(wb%2) begin @(posedge clk);@(negedge clk);awr=0;end
   else early_w++;
   for(b=0;b<n;b++) begin
    if(b%5==3) repeat(3) @(negedge clk);
    wr=1;last=b==n-1;@(posedge clk);
    if(sready!==(1<<src)) $fatal(1,"write owner mismatch");
    memory[a+b]=wd;
    for(lane=0;lane<16;lane++) begin
     if(wd[lane*16+:16]!==pattern(src,tag,wy,wx+b*16+lane))
      $fatal(1,"write oracle src=%0d row=%0d col=%0d",src,wy,wx+b*16+lane);
     wpixels++;
    end
    @(negedge clk);awr=0;wr=0;last=0;
   end
   wb++;
  end
 end
 reg stall=0,allow_old_tail=0,old_bank=0;integer ra,rn,rr,rs;
 initial begin
  wait(rst);
  forever begin
   wait(arv);@(negedge clk);ra=idx(ar);rn=rl+1;rs=ar[24:23];arr=1;
   if(!selected[rs] && !(allow_old_tail && rs==0 && ar[22]==old_bank && ar[21:0]<640))
    $fatal(1,"hidden new line (old in-flight line tail is allowed)");
   if(rb%2 || stall) begin @(posedge clk);@(negedge clk);arr=0;while(stall) @(negedge clk);end
   else early_r++;
   for(rr=0;rr<rn;rr++) begin
    if(rr%5==2 || rr==rn-1) repeat(2+(rb%3)) @(negedge clk);
    rd=memory[ra+rr];rv=1;rlast=rr==rn-1;@(posedge clk);
    if(svalid!==(1<<rs)) $fatal(1,"return crossed source");
    @(negedge clk);arr=0;rv=0;rlast=0;
   end
   rb++;
  end
 end
 integer cols[0:2],rows[0:2],tags[0:2],pixels=0,frames=0;
 reg checking=0,fault_allowed=0;integer black_pixels=0;reg [2:0] vd=0;
 integer j;
 always @(posedge pc) begin
  #2;
  for(j=0;j<3;j++) begin
   if(checking && valid[j]) begin
    if(pixel[j*16+:16]!==pattern(j,tags[j],rows[j]*(quad ? 4 : 2),cols[j]*(quad ? 4 : 2)))
     if(fault_allowed && j==0 && rows[j]>=4 && pixel[j*16+:16]===0) black_pixels++;
     else $fatal(1,"display oracle frame=%0d view=%0d src=%0d tag=%0d y=%0d x=%0d got=%h expected=%h",frames,view,j,tags[j],rows[j],cols[j],pixel[j*16+:16],pattern(j,tags[j],rows[j]*(quad ? 4 : 2),cols[j]*(quad ? 4 : 2)));
    cols[j]++;pixels++;
   end
   if(checking && !valid[j] && vd[j]) begin
    if(cols[j]!=(quad ? 320 : 640)) $fatal(1,"wrong width");
    cols[j]=0;rows[j]++;
   end
  end
  vd=valid;
 end
 task boundary(input integer v);
  begin
   @(negedge pc);view=v;fs=1;repeat(8) @(negedge pc);fs=0;
   repeat(2000) @(negedge pc);
  end
 endtask
 task image;
  integer y;
  begin
   for(y=0;y<HEIGHT/2;y++) begin
    if(quad) begin
     req=y<HEIGHT/4 ? 1 : 4;repeat(320) @(negedge pc);
     req=y<HEIGHT/4 ? 2 : 0;repeat(320) @(negedge pc);
    end else begin req=1<<view;repeat(640) @(negedge pc);end
    req=0;repeat(352) @(negedge pc);
   end
   repeat(10) @(negedge pc);
  end
 endtask
 task frame(input integer v);
  begin
   boundary(v);
   for(integer k=0;k<3;k++) begin cols[k]=0;rows[k]=0;tags[k]=display_ids[k*32+:32];end
   checking=1;image;checking=0;
   for(integer k=0;k<3;k++) if(selected[k] && rows[k]!=(quad ? HEIGHT/4 : HEIGHT/2)) $fatal(1,"missing rows");
   frames++;
   $display("M2_FRAME frame=%0d view=%0d pubs=%0d/%0d/%0d",frames,view,pubs[31:0],pubs[63:32],pubs[95:64]);$fflush();
  end
 endtask
 integer f,old;reg [31:0] random_state=32'h1a23b451;
 initial begin
  #500;rst=1;wait(&init);
  old=pubs[95:64];repeat(8) frame(0);
  if(pubs[95:64]<=old) $fatal(1,"hidden HDMI stopped");
  frame(1);frame(2);repeat(4) frame(3);
  for(f=0;f<12;f++) begin
   random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
   frame(random_state%4);
  end
  // Disconnect/recover third input while front/rear keep publishing.
  online[2]=0;repeat(3) frame(0);online[2]=1;
  repeat(4) frame(0);frame(2);frame(3);
  if(faults!=0) $fatal(1,"unexpected read faults %h",faults);
  // A >two-line stall still fails closed; one late line cannot leak stale
  // circular RAM data, and the next frame must recover without a reset.
  boundary(0);
  for(integer k=0;k<3;k++) begin cols[k]=0;rows[k]=0;tags[k]=display_ids[k*32+:32];end
  checking=1;fault_allowed=1;
  fork
   image;
   begin wait(rows[0]==2);stall=1;#90000;stall=0;end
  join
  checking=0;fault_allowed=0;
  if(black_pixels!=640*(HEIGHT/2-4)) $fatal(1,"late frame guard coverage %0d",black_pixels);
  frame(0);
  // Keep a native return in flight across a source change; bank must stay pinned.
  stall=1;boundary(0);wait(arb.rs==2);repeat(40) @(negedge pc);
  old_bank=source[0].input_source.dut.read_bank;allow_old_tail=1;
  boundary(1);stall=0;repeat(1000) @(negedge pc);frame(1);frame(0);
  $display("M2_JOINT_PASS frames=%0d pixels=%0d write_pixels=%0d bursts=%0d/%0d coincident=%0d/%0d pubs=%0d/%0d/%0d guarded_black=%0d",frames,pixels,wpixels,wb,rb,early_w,early_r,pubs[31:0],pubs[63:32],pubs[95:64],black_pixels);
  $finish;
 end
 initial begin #100000000;$fatal(1,"timeout");end
endmodule
