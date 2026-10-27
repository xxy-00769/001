`timescale 1ns/1ps
module display_joint_tb #(parameter HEIGHT=16,FRAMES=36,FIXED_FRONT=12,FIXED_REAR=8);
 reg clk=0,pc=0,vc0=0,vc1=0,rst=0,grs=0,fs=0,req=0,view_request=0;
 always #5 clk=~clk;
 always #16.923077 pc=~pc;
 always #11.9 vc0=~vc0;
 initial begin #3;forever #12.3 vc1=~vc1;end
 GTP_GRS GRS_INST(.GRS_N(grs));
 wire selected;
 m1_view_select selector(.clk(pc),.rst_n(rst),.frame_sync(fs),.view_request(view_request),.selected_view(selected));
 wire [55:0] saw,sar;wire [7:0] swlen,srlen;
 wire [1:0] swv,srv,swr,srr,sready,slast,svalid,srlast;
 wire [511:0] swdata;
 wire [27:0] aw,ar; wire [3:0] wl,rl; wire awv,arv;wire [255:0] wd;
 reg awr=0,arr=0,wr=0,last=0,rv=0,rlast=0;reg [255:0] rd=0;
 dual_ddr_arbiter arb(.clk(clk),.rst_n(rst),
 .s_awaddr(saw),.s_awlen(swlen),.s_awvalid(swv),.s_awready(swr),
 .s_wdata(swdata),.s_wstrb(64'hffffffffffffffff),.s_wready(sready),.s_wlast(slast),
 .s_araddr(sar),.s_arlen(srlen),.s_arvalid(srv),.s_arready(srr),.s_rvalid(svalid),.s_rlast(srlast),
 .awaddr(aw),.awlen(wl),.awvalid(awv),.awready(awr),.wdata(wd),.wstrb(),.wready(wr),.wlast(last),
 .araddr(ar),.arlen(rl),.arvalid(arv),.arready(arr),.rvalid(rv),.rlast(rlast));
 display_source #(.SOURCE(0),.HEIGHT(HEIGHT)) front(.core_clk(clk),.video_clk(vc0),.out_clk(pc),.rst_n(rst),
 .out_vs(fs),.out_de(req && !selected),.selected(!selected),
 .awaddr(saw[27:0]),.araddr(sar[27:0]),.awlen(swlen[3:0]),.arlen(srlen[3:0]),
 .awvalid(swv[0]),.arvalid(srv[0]),.wdata(swdata[255:0]),.awready(swr[0]),.wready(sready[0]),.wlast(slast[0]),
 .arready(srr[0]),.rvalid(svalid[0]),.rlast(srlast[0]),.rdata(rd),.stall_reads(),.finished(),.bad_capture());
 display_source #(.SOURCE(1),.HEIGHT(HEIGHT)) rear(.core_clk(clk),.video_clk(vc1),.out_clk(pc),.rst_n(rst),
 .out_vs(fs),.out_de(req && selected),.selected(selected),
 .awaddr(saw[55:28]),.araddr(sar[55:28]),.awlen(swlen[7:4]),.arlen(srlen[7:4]),
 .awvalid(swv[1]),.arvalid(srv[1]),.wdata(swdata[511:256]),.awready(swr[1]),.wready(sready[1]),.wlast(slast[1]),
 .arready(srr[1]),.rvalid(svalid[1]),.rlast(srlast[1]),.rdata(rd),.stall_reads(),.finished(),.bad_capture());
 // Same address meaning as configured HMIC_S: BANK[27:25], ROW[24:10], COL[9:0].
 // Do not index with an independently assumed source bit alone.
 reg [255:0] memory[0:230399];
 function integer idx(input [27:0] a);
  integer bank,row,col,word_address,source,slot,offset;
  begin
   bank=a[27:25];row=a[24:10];col=a[9:0];
   word_address=(bank*32768+row)*1024+col;
   source=(word_address>>23)&3;slot=(word_address>>22)&1;offset=word_address&4194303;
   if(bank!=0 || source>1 || offset>=640*HEIGHT || col%8!=0) $fatal(1,"Physical address invalid %h",a);
   idx=source*115200+slot*57600+offset/8;
  end
 endfunction
 function [15:0] pattern(input integer source,tag,row,col);
  pattern=(source<<15)|(((tag*16'h19d7)^(row*16'h031d)^(col*16'h9e37))&16'h7fff);
 endfunction
 integer wb=0,rb=0,wpixels=0,early_w=0,early_r=0;
 integer a,n,b,src,tag,y,x,lane;
 initial begin
  wait(rst);
  forever begin
   wait(awv);@(negedge clk);
   a=idx(aw);n=wl+1;src=aw[23];tag=src ? rear.dut.owner.active_id : front.dut.owner.active_id;
   y=aw[21:0]/640;x=(aw[21:0]%640)*2;awr=1;
   // Alternate address-coincident first beat and immediately adjacent first beat.
   if(wb%2) begin @(posedge clk);@(negedge clk);awr=0;end
   else early_w=early_w+1;
   for(b=0;b<n;b=b+1) begin
    if(b%5==3) repeat(3) @(negedge clk);
    wr=1;last=b==n-1;
    @(posedge clk);
    if(sready!==(src ? 2'b10 : 2'b01)) $fatal(1,"Write owner mismatch");
    memory[a+b]=wd;
    for(lane=0;lane<16;lane=lane+1) begin
     if(wd[lane*16+:16]!==pattern(src,tag,y,x+b*16+lane))
      $fatal(1,"Write oracle src=%0d tag=%0d y=%0d x=%0d got=%h exp=%h",src,tag,y,x+b*16+lane,wd[lane*16+:16],pattern(src,tag,y,x+b*16+lane));
     wpixels=wpixels+1;
    end
    @(negedge clk);awr=0;wr=0;last=0;
   end
   wb=wb+1;
  end
 end
 reg stall_read=0,late_phase=0;
 integer ra,rn,rr,rs;reg [27:0] held_address;
 initial begin
  wait(rst);
  forever begin
   wait(arv);@(negedge clk);ra=idx(ar);rn=rl+1;rs=ar[23];held_address=ar;arr=1;
   if(!late_phase && rs!==selected) $fatal(1,"Hidden source scheduled src=%0d selected=%0d",rs,selected);
   if(rb%2 || stall_read) begin
    @(posedge clk);@(negedge clk);arr=0;
    while(stall_read) @(negedge clk);
   end else early_r=early_r+1;
   for(rr=0;rr<rn;rr=rr+1) begin
    if(rr%5==2 || rr==rn-1) repeat(2+(rb%3)) @(negedge clk);
    rd=memory[ra+rr];rv=1;rlast=rr==rn-1;
    @(posedge clk);
    if(svalid!==(rs ? 2'b10 : 2'b01)) $fatal(1,"Return crossed source");
    @(negedge clk);arr=0;rv=0;rlast=0;
   end
   rb=rb+1;
  end
 end
 wire valid=selected ? rear.valid : front.valid;
 wire [15:0] pixel=selected ? rear.pixel : front.pixel;
 integer frame_tag,frame_source,columns=0,rows=0,pixels=0,frames=0,black_pixels=0;
 reg checking=0,black_checking=0,de_d=0;
 always @(posedge pc) begin
  #2;
  if(checking && selected!==frame_source) $fatal(1,"Source changed inside frame");
  if(valid && checking) begin
   if(pixel!==pattern(frame_source,frame_tag,rows*2,columns*2))
    $fatal(1,"Display oracle frame=%0d src=%0d tag=%0d y=%0d x=%0d got=%h exp=%h bad=%0d/%0d enabled=%b lines=%0d/%0d fault=%0d/%0d busy=%b ready=%b pending=%b reader=%b",frames,frame_source,frame_tag,rows,columns,pixel,pattern(frame_source,frame_tag,rows*2,columns*2),front.dut.output_bad,rear.dut.output_bad,{rear.dut.read_enabled,front.dut.read_enabled},front.dut.available_rows,rear.dut.available_rows,front.dut.read_fault_count,rear.dut.read_fault_count,{rear.dut.owner.read_busy,front.dut.owner.read_busy},{rear.dut.rd_cmd_ready,front.dut.rd_cmd_ready},{rear.dut.owner.pending,front.dut.owner.pending},{rear.dut.owner.have_reader,front.dut.owner.have_reader});
   columns=columns+1;pixels=pixels+1;
  end
  if(valid && black_checking) begin
   if(pixel!==0) $fatal(1,"Late-return fault leaked pixels");black_pixels=black_pixels+1;
  end
  if(!valid && de_d && checking) begin
   if(columns!=640) $fatal(1,"row width");columns=0;rows=rows+1;
  end
  de_d=valid;
 end
 task boundary;
  begin @(posedge pc);#0.1;fs=1;repeat(8) @(negedge pc);fs=0;end
 endtask
 task image;
  integer row;
  begin
   for(row=0;row<HEIGHT/2;row=row+1) begin
    req=1;repeat(640) @(negedge pc);req=0;repeat(352) @(negedge pc);
   end
   repeat(10) @(negedge pc);
  end
 endtask
 task frame;
  begin
   boundary;repeat(2000) @(negedge pc);
   frame_source=selected;frame_tag=selected ? rear.dut.display_id : front.dut.display_id;
   columns=0;rows=0;checking=1;image;checking=0;
   if(rows!=HEIGHT/2) $fatal(1,"missing last row");frames=frames+1;
   $display("JOINT_FRAME frame=%0d source=%0d tag=%0d pixels=%0d",frames,frame_source,frame_tag,pixels);$fflush();
  end
 endtask
 always @(posedge clk) if(rst && frames>=22) begin
  if(front.dut.output_sof || rear.dut.output_sof)
   $display("TRACE_SOF t=%0t sel=%b sync=%b enabled=%b request=%b ready=%b busy=%b pend=%b reader=%b",$time,selected,{rear.dut.selected_d[1],front.dut.selected_d[1]},{rear.dut.read_enabled,front.dut.read_enabled},{rear.dut.rd_cmd_en,front.dut.rd_cmd_en},{rear.dut.rd_cmd_ready,front.dut.rd_cmd_ready},{rear.dut.owner.read_busy,front.dut.owner.read_busy},{rear.dut.owner.pending,front.dut.owner.pending},{rear.dut.owner.have_reader,front.dut.owner.have_reader});
  if((front.dut.rd_cmd_en && front.dut.read_enabled) || (rear.dut.rd_cmd_en && rear.dut.read_enabled))
   $display("TRACE_LINE t=%0t sel=%b enabled=%b issue=%b busy=%b ready=%b",$time,selected,{rear.dut.read_enabled,front.dut.read_enabled},{rear.dut.read_issue,front.dut.read_issue},{rear.dut.owner.read_busy,front.dut.owner.read_busy},{rear.dut.rd_cmd_ready,front.dut.rd_cmd_ready});
 end
 always @(posedge clk) if(rst) begin
  if(front.dut.write_issue && ((front.dut.owner.have_reader && front.dut.write_bank==front.dut.read_bank) || (front.dut.owner.pending && front.dut.write_bank==front.dut.owner.pending_bank))) $fatal(1,"Front overwrote owned slot");
  if(rear.dut.write_issue && ((rear.dut.owner.have_reader && rear.dut.write_bank==rear.dut.read_bank) || (rear.dut.owner.pending && rear.dut.write_bank==rear.dut.owner.pending_bank))) $fatal(1,"Rear overwrote owned slot");
 end
 integer expected_front,expected_rear;
 always @(posedge clk) begin
  if(rst) begin
   expected_front=front.dut.owner.pending ? front.dut.owner.pending_id : front.dut.display_id;
   expected_rear=rear.dut.owner.pending ? rear.dut.owner.pending_id : rear.dut.display_id;
   if(front.dut.output_sof && front.dut.selected_d[1] && !front.dut.owner.read_busy && front.dut.rd_cmd_ready) begin
    #2;if(front.dut.display_id!=expected_front) $fatal(1,"Front not latest complete");
   end else if(rear.dut.output_sof && rear.dut.selected_d[1] && !rear.dut.owner.read_busy && rear.dut.rd_cmd_ready) begin
    #2;if(rear.dut.display_id!=expected_rear) $fatal(1,"Rear not latest complete");
   end
  end
 end
 integer f,old_front,old_rear,switches=0,held_source;reg [31:0] random_state=32'h1a23b451;
 initial begin
  #100;grs=1;#400;rst=1;
  wait(front.init_done && rear.init_done);
  old_rear=rear.dut.published_count;
  // Long no-key front observation while rear remains hidden and keeps publishing.
  repeat(FIXED_FRONT) frame;
  if(rear.dut.published_count<=old_rear+(HEIGHT>16 ? 0 : 2)) $fatal(1,"Hidden rear stopped capturing");
  view_request=1;frame;old_front=front.dut.published_count;
  repeat(FIXED_REAR) frame;
  if(front.dut.published_count<=old_front+(HEIGHT>16 ? 0 : 1)) $fatal(1,"Hidden front stopped capturing");
  for(f=FIXED_FRONT+FIXED_REAR+1;f<FRAMES;f=f+1) begin
   // Request at a pseudorandom pixel phase; commitment must wait for SOF.
   random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
   fork
    frame;
    begin
     repeat(17+(random_state%(2000+992*(HEIGHT/2)))) @(negedge pc);
     view_request=~view_request;switches=switches+1;
    end
   join
  end
  if(front.dut.read_fault_count!=0 || rear.dut.read_fault_count!=0) $fatal(1,"Unexpected normal read faults");
  // Hold a legal burst across a switch. Old reader stays pinned until all
  // return beats drain; the new source's separate reader must stay correct.
  late_phase=1;stall_read=1;boundary;
  wait(arb.rs==2);repeat(50) @(negedge pc);
  held_source=selected;old_front=front.dut.read_bank;old_rear=rear.dut.read_bank;
  view_request=~view_request;boundary;repeat(30) @(negedge pc);
  if((!held_source && front.dut.read_bank!=old_front) || (held_source && rear.dut.read_bank!=old_rear)) $fatal(1,"Released outstanding bank");
  stall_read=0;wait(arb.rs==0);repeat(1000) @(negedge pc);
  frame;view_request=~view_request;frame;
  // A deadline violation while staying on the same source must blank the
  // affected output and recover on the next safely prefetched frame.
  stall_read=1;boundary;wait(arb.rs==2);repeat(100) @(negedge pc);
  boundary;repeat(100) @(negedge pc);stall_read=0;
  wait(arb.rs==0);repeat(500) @(negedge pc);
  black_checking=1;image;black_checking=0;
  frame;
  if(black_pixels!=640*(HEIGHT/2)) $fatal(1,"Fault coverage incomplete");
  $display("DISPLAY_JOINT_PASS frames=%0d pixels=%0d switches=%0d write_pixels=%0d write_bursts=%0d read_bursts=%0d early_w=%0d early_r=%0d hidden_pub=%0d/%0d faults=%0d/%0d black_pixels=%0d last_row=%0d errors=0",frames,pixels,switches,wpixels,wb,rb,early_w,early_r,front.dut.published_count,rear.dut.published_count,front.dut.read_fault_count,rear.dut.read_fault_count,black_pixels,HEIGHT-2);
  $finish;
 end
 initial begin #1000000000;$fatal(1,"Joint timeout");end
endmodule
