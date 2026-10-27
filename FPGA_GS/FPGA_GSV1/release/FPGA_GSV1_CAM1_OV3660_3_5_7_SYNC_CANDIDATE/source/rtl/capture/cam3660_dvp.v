`timescale 1ns/1ps
// CAM1-only RGB565 byte gearbox. Both byte phases and all sync boundaries are
// transferred as tuples through an eight-entry FIFO to the existing /2 clock.
// This removes the legacy dependence on HREF starting at a fixed divide phase.
// Odd trailing bytes/overflow mark the closing frame invalid; no padding/crop.
module cam3660_dvp(input pclk,rst_n,de_i,vs_i,input [7:0] pdata_i,
  output pixel_clk,output reg de_o,vs_o,frame_bad,output reg [15:0] pdata_o);
  wire io_clock;
  GTP_IOCLKBUF #(.GATE_EN("FALSE")) u_GTP_IOCLKBUF(
    .CLKIN(pclk),.DI(1'b1),.CLKOUT(io_clock));
  reg [1:0] source_reset;
  always @(posedge pclk or negedge rst_n)
    if(!rst_n) source_reset<=0;else source_reset<={source_reset[0],1'b1};
  GTP_IOCLKDIV #(.GRS_EN("TRUE"),.DIV_FACTOR("2")) u_GTP_IOCLKDIV(
    .CLKIN(io_clock),.RST_N(source_reset[1]),.CLKDIVOUT(pixel_clk));
  reg [1:0] sink_reset;
  always @(posedge pixel_clk or negedge rst_n)
    if(!rst_n) sink_reset<=0;else sink_reset<={sink_reset[0],1'b1};
  reg [18:0] tuples[0:7];
  reg [3:0] wr_binary,wr_gray,rd_binary,rd_gray;
  (* ASYNC_REG="TRUE" *) reg [3:0] rg1,rg2,wg1,wg2;
  wire full=wr_gray=={~rg2[3:2],rg2[1:0]};
  wire empty=rd_gray==wg2;
  wire [3:0] next_wr=wr_binary+1'b1,next_rd=rd_binary+1'b1;
  reg vs_d,href_d,half_byte,opened,bad;
  reg [7:0] high_byte;
  // Pixel writes are at most one per two pclk cycles; boundary markers may
  // arrive on the adjacent cycle. FIFO depth includes pointer sync latency.
  wire boundary=opened && (vs_i!=vs_d || (!de_i && href_d));
  wire opening=vs_i && !vs_d;
  wire pixel=opened && !vs_i && de_i && half_byte && !boundary;
  wire push=boundary || opening || pixel;
  wire [18:0] tuple_in=(boundary || opening)
    ? {vs_i && !vs_d && (bad || half_byte),vs_i,1'b0,16'd0}
    : {1'b0,1'b0,1'b1,high_byte,pdata_i};
  always @(posedge pclk or negedge rst_n) begin
    if(!rst_n) begin
      wr_binary<=0;wr_gray<=0;rg1<=0;rg2<=0;
      vs_d<=0;href_d<=0;half_byte<=0;high_byte<=0;opened<=0;bad<=0;
    end else if(!source_reset[1]) begin
      wr_binary<=0;wr_gray<=0;rg1<=0;rg2<=0;
      vs_d<=0;href_d<=0;half_byte<=0;high_byte<=0;opened<=0;bad<=0;
    end else begin
      rg1<=rd_gray;rg2<=rg1;
      vs_d<=vs_i;href_d<=de_i && !vs_i;
      if(opening) begin opened<=1;half_byte<=0;bad<=0;end
      else if(vs_i || !de_i) begin
        if(half_byte) bad<=1;
        half_byte<=0;
      end else if(opened) begin
        half_byte<=!half_byte;
        if(!half_byte) high_byte<=pdata_i;
      end
      if(push) begin
        if(full) bad<=1;
        else begin
          tuples[wr_binary[2:0]]<=tuple_in;
          wr_binary<=next_wr;wr_gray<=(next_wr>>1)^next_wr;
        end
      end
    end
  end
  always @(posedge pixel_clk or negedge rst_n) begin
    if(!rst_n) begin
      rd_binary<=0;rd_gray<=0;wg1<=0;wg2<=0;
      de_o<=0;vs_o<=0;frame_bad<=0;pdata_o<=0;
    end else if(!sink_reset[1]) begin
      rd_binary<=0;rd_gray<=0;wg1<=0;wg2<=0;
      de_o<=0;vs_o<=0;frame_bad<=0;pdata_o<=0;
    end else begin
      wg1<=wr_gray;wg2<=wg1;
      if(!empty) begin
        {frame_bad,vs_o,de_o,pdata_o}<=tuples[rd_binary[2:0]];
        rd_binary<=next_rd;rd_gray<=(next_rd>>1)^next_rd;
      end else de_o<=0;
    end
  end
endmodule
