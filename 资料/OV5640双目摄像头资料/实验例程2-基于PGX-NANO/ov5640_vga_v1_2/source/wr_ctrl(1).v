module wr_ctrl(

    input    rstn,

    input    cmos_pclk,
    input    cmos_de,
    input    [15:0]cmos_data,
    input    cmos_vsync,

    output   reg rstn_sync,
    input    vga_clk,
    input    rd_en_fifo,
    input    vga_vs,
    output    [15:0]vga_data/*synthesis PAP_MARK_DEBUG="1"*/

   );
reg vga_vs_1d;
always @(posedge vga_clk)
begin
    vga_vs_1d <= vga_vs;
end

parameter NUM=16'd640;
reg cmos_vsync_1d;
reg cmos_vsync_2d;
reg cmos_vsync_3d;
reg [31:0]vsync_cnt;
reg fifo_rstn;
always @(posedge cmos_pclk)
begin
    cmos_vsync_1d <= cmos_vsync;
    cmos_vsync_2d <= cmos_vsync_1d;
    cmos_vsync_3d <= cmos_vsync_2d;
end
always @(posedge cmos_pclk)
begin
    if(!cmos_vsync_3d && cmos_vsync_2d )
        vsync_cnt <= 31'd0;
    else if(vsync_cnt < 50*NUM)
        vsync_cnt <= vsync_cnt + 1'd1;
    else
        vsync_cnt <= vsync_cnt;
end

always @(posedge cmos_pclk)
begin
    if((vsync_cnt < 50*NUM)&&(vsync_cnt>50*NUM-8'd10))
        fifo_rstn <= 1'b0;
    else
        fifo_rstn <= 1'b1;
end
wire wr_full/*synthesis PAP_MARK_DEBUG="1"*/;
wire rd_empty;
wire [16:0]wr_water_level/*synthesis PAP_MARK_DEBUG="1"*/;
wire [16:0]rd_water_level;
wr_fifo wr_fifo (
  .wr_clk(cmos_pclk),                    // input
  .wr_rst(!cmos_vsync_3d && cmos_vsync_2d),                    // input
  .wr_en(cmos_de),                      // input
  .wr_data(cmos_data),                  // input [15:0]
  .wr_full(wr_full),                  // output
  .wr_water_level(wr_water_level),    // output [14:0]
  .almost_full(almost_full),          // output
  .rd_clk(vga_clk),                    // input
  .rd_rst(!vga_vs_1d && vga_vs),                    // input
  .rd_en(rd_en_fifo),                      // input
  .rd_data(vga_data),                  // output [15:0]
  .rd_empty(rd_empty),                // output
  .rd_water_level(rd_water_level),    // output [14:0]
  .almost_empty(almost_empty)         // output
);

always @(posedge cmos_pclk)
begin
    if(!fifo_rstn)
        rstn_sync <= 1'b0;
//    else if(wr_water_level > 20*NUM)
//        rstn_sync <= 1'b1;
    else
        rstn_sync <= 1'b1;
end





endmodule