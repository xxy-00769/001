`timescale 1ns/1ps
// At most three resident lines in the existing 8192-pixel circular RAM.
// Two lines ahead of line START is safe: 3*1280=3840 <8192 pixels,
// including the still-scanning line. No slot is reused within that aperture.
// Requests wait for the real line-command completion; no timer is a verdict.
module m2_rd_buf #(parameter H_NUM=1280,V_NUM=720,ADDR_WIDTH=28)(
 input ddr_clk,ddr_rstn,vout_clk,rd_fsync,rd_en,quarter,selected,enabled,
 output vout_de,output reg [15:0] vout_data,
 output ddr_rreq,output [ADDR_WIDTH-1:0] ddr_raddr,
 output [31:0] ddr_rd_len,input ddr_rrdy,ddr_rdone,
 input [255:0] ddr_rdata,input ddr_rdata_en,output frame_start_event);
 reg [8:0] fs_sync;
 reg [2:0] en_sync;
 reg [1:0] q_sync;
 reg q;
 reg [11:0] consumed,issued;
 reg busy;
 reg discard_line;
 reg [21:0] address;
 wire line_start=en_sync[1] && !en_sync[2];
 wire [11:0] limit=q ? V_NUM/4 : V_NUM/2;
 wire start=selected && enabled && !busy && !discard_line && ddr_rrdy &&
            issued<limit && issued<consumed+12'd2 && !frame_start_event;
 assign ddr_rreq=start;
 assign ddr_raddr={{(ADDR_WIDTH-22){1'b0}},address};
 assign ddr_rd_len=H_NUM/16;
 assign frame_start_event=fs_sync[7] && !fs_sync[8];
 always @(posedge ddr_clk or negedge ddr_rstn) begin
  if(!ddr_rstn) begin
   fs_sync<=0;en_sync<=0;q_sync<=0;q<=0;consumed<=0;issued<=0;busy<=0;discard_line<=0;address<=0;
  end else begin
   fs_sync<={fs_sync[7:0],rd_fsync};en_sync<={en_sync[1:0],rd_en};
   q_sync<={q_sync[0],quarter};
   if(ddr_rdone) begin
    busy<=0;discard_line<=0;
    // A tail belonging to the previous SOF must not advance this epoch.
    address<=discard_line ? 22'd0 : address+(q ? H_NUM*2 : H_NUM);
   end
   if(frame_start_event) begin
    consumed<=0;issued<=0;address<=0;q<=q_sync[1];
    discard_line<=busy && !ddr_rdone;
   end
   else begin
    if(line_start) consumed<=consumed+1'b1;
    if(start) begin
     busy<=1;issued<=issued+1'b1;
    end
   end
  end
 end
 wire ram_write=ddr_rdata_en && !discard_line && !frame_start_event;
 reg [8:0] wr_addr;
 always @(posedge ddr_clk or negedge ddr_rstn)
  if(!ddr_rstn) wr_addr<=0;
  else if(frame_start_event) wr_addr<=0;
  else if(ddr_rdone && discard_line) wr_addr<=0;
  else if(ram_write) wr_addr<=wr_addr+1'b1;
 reg fs_d;
 reg [1:0] en_d;
 reg [11:0] rd_addr;
 wire [31:0] ram_data;
 always @(posedge vout_clk or negedge ddr_rstn) begin
  if(!ddr_rstn) begin fs_d<=0;en_d<=0;rd_addr<=0;vout_data<=0;end
  else begin
   fs_d<=rd_fsync;en_d<={en_d[0],rd_en};
   if(rd_fsync && !fs_d) rd_addr<=0;
   else if(rd_en) rd_addr<=rd_addr+(quarter ? 12'd2 : 12'd1);
   vout_data<=en_d[0] ? ram_data[15:0] : 16'd0;
  end
 end
 assign vout_de=en_d[1];
 rd_fram_buf line_ram(.wr_clk(ddr_clk),.wr_rst(!ddr_rstn),.wr_en(ram_write),
  .wr_addr(wr_addr),.wr_data(ddr_rdata),.rd_clk(vout_clk),.rd_rst(!ddr_rstn),
  .rd_addr(rd_addr),.rd_data(ram_data));
endmodule
