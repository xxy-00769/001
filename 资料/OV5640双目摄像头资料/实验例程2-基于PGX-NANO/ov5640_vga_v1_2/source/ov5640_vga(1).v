`timescale 1ns / 1ps
`define UD #1

//cmos1、cmos2二选一，作为视频源输入
`define CMOS_1      //cmos1作为视频输入；
//`define CMOS_2      //cmos2作为视频输入；

module ov5640_vga(
	input                                sys_clk              ,//50Mhz
    input                                rst_n                ,
//OV5647
    output  [1:0]                        cmos_init_done       ,//OV5640寄存器初始化完成
    //coms1	
    inout                                cmos1_scl           ,//cmos1 i2c 
    inout                                cmos1_sda           ,//cmos1 i2c 
    input                                cmos1_vsync         /*synthesis PAP_MARK_DEBUG="1"*/,//cmos1 vsync
    input                                cmos1_href          /*synthesis PAP_MARK_DEBUG="1"*/,//cmos1 hsync refrence,data valid
    input                                cmos1_pclk          /*synthesis PAP_MARK_DEBUG="1"*/,//cmos1 pxiel clock
    input   [7:0]                        cmos1_data          /*synthesis PAP_MARK_DEBUG="1"*/,//cmos1 data
    output                               cmos1_reset         ,//cmos1 reset
    //coms2
    inout                                cmos2_scl           ,//cmos2 i2c 
    inout                                cmos2_sda           ,//cmos2 i2c 
    input                                cmos2_vsync         ,//cmos2 vsync
    input                                cmos2_href          ,//cmos2 hsync refrence,data valid
    input                                cmos2_pclk          ,//cmos2 pxiel clock
    input   [7:0]                        cmos2_data          ,//cmos2 data
    output                               cmos2_reset         ,//cmos2 reset

//vga_out                                                   
    output                            vs_out               /* synthesis PAP_MARK_DEBUG="true" */, 
    output                            hs_out               /* synthesis PAP_MARK_DEBUG="true" */, 
   
    output     [3:0]                  r_out                /* synthesis PAP_MARK_DEBUG="true" */, 
    output     [3:0]                  g_out                /* synthesis PAP_MARK_DEBUG="true" */, 
    output     [3:0]                  b_out             /* synthesis PAP_MARK_DEBUG="true" */
);


wire  pix_clk              ;//pixclk   
wire   de_out               ;
reg cmos1_hreg ;
wire cmos1_hr ;
wire cmos1_hf /*synthesis PAP_MARK_DEBUG="1"*/;
reg cmos1_vreg ;
wire cmos1_vr /*synthesis PAP_MARK_DEBUG="1"*/;
reg [26:0]cnt_time ;
reg time_flag/*synthesis PAP_MARK_DEBUG="1"*/ ; 

always @(posedge cmos1_pclk)begin
    if (~rst_n) begin
        cmos1_hreg <= 1'b0 ;
        cmos1_vreg <= 1'b0 ;
    end 
    else begin 
        cmos1_hreg <= cmos1_href ;
        cmos1_vreg <= cmos1_vsync;
    end 
end 

assign cmos1_hr = ((~cmos1_hreg)&&(cmos1_href))? 1'b1 : 1'b0  ;
assign cmos1_hf = ((cmos1_hreg)&&(~cmos1_href))? 1'b1 : 1'b0  ;

assign cmos1_vr = ((~cmos1_vreg)&&(cmos1_vsync))? 1'b1 : 1'b0  ;



/////////////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////////////
    wire                        initial_en          ;
    wire[15:0]                  cmos1_d_16bit       /*synthesis PAP_MARK_DEBUG="1"*/;
    wire                        cmos1_href_16bit    /*synthesis PAP_MARK_DEBUG="1"*/;
    reg [7:0]                   cmos1_d_d0          ;
    reg                         cmos1_href_d0       ;
    reg                         cmos1_vsync_d0      ;
    wire                        cmos1_pclk_16bit    /*synthesis PAP_MARK_DEBUG="1"*/;
    wire[15:0]                  cmos2_d_16bit       ;
    wire                        cmos2_href_16bit    ;
    reg [7:0]                   cmos2_d_d0          ;
    reg                         cmos2_href_d0       ;
    reg                         cmos2_vsync_d0      ;
    wire                        cmos2_pclk_16bit    ;
    wire[15:0]                  o_rgb565            ; //gbgb8,rgb16
    wire                        pclk_in_test        ;    
    wire                        vs_in_test          ;
    wire                        de_in_test          ;
    wire[15:0]                  i_rgb565            ; /////////GBGB:8,RGB:16
    wire                        de_re               ;
    wire                        pix_clk/*synthesis PAP_MARK_DEBUG="1"*/ ;
/////////////////////////////////////////////////////////////////////////////////////
//PLL
    pll u_pll (
        .clkin1   (  sys_clk    ),//50MHz
        .clkout0  (  clk_25M    ),
        .clkout1  (  pix_clk    ),
        .lock (  locked     )
    );
//配置CMOS///////////////////////////////////////////////////////////////////////////////////
//OV5640 register configure enable    
    power_on_delay	power_on_delay_inst(
    	.clk_50M                 (sys_clk        ),//input
    	.reset_n                 (1'b1           ),//input	
    	.camera1_rstn            (cmos1_reset    ),//output
    	.camera2_rstn            (cmos2_reset    ),//output	
    	.camera_pwnd             (               ),//output
    	.initial_en              (initial_en     ) //output		
    );
//CMOS1 Camera 
    reg_config	coms1_reg_config(
    	.clk_25M                 (clk_25M            ),//input
    	.camera_rstn             (cmos1_reset        ),//input
    	.initial_en              (initial_en         ),//input		
    	.i2c_sclk                (cmos1_scl          ),//output
    	.i2c_sdat                (cmos1_sda          ),//inout
    	.reg_conf_done           (cmos_init_done[0]  ),//output config_finished
    	.reg_index               (                   ),//output reg [8:0]
    	.clock_20k               (                   ) //output reg
    );

//CMOS2 Camera 
    reg_config	coms2_reg_config(
    	.clk_25M                 (clk_25M            ),//input
    	.camera_rstn             (cmos2_reset        ),//input
    	.initial_en              (initial_en         ),//input		
    	.i2c_sclk                (cmos2_scl          ),//output
    	.i2c_sdat                (cmos2_sda          ),//inout
    	.reg_conf_done           (cmos_init_done[1]  ),//output config_finished
    	.reg_index               (                   ),//output reg [8:0]
    	.clock_20k               (                   ) //output reg
    );
//CMOS 8bit转16bit///////////////////////////////////////////////////////////////////////////////////
//CMOS1
    always@(posedge cmos1_pclk)
        begin
            cmos1_d_d0        <= cmos1_data    ;
            cmos1_href_d0     <= cmos1_href    ;
            cmos1_vsync_d0    <= cmos1_vsync   ;
        end

    cmos_8_16bit cmos1_8_16bit(
    	.pclk           (cmos1_pclk       ),//input
    	.rst_n          (cmos_init_done[0]),//input
    	.pdata_i        (cmos1_d_d0       ),//input[7:0]
    	.de_i           (cmos1_href_d0    ),//input
    	.vs_i           (cmos1_vsync_d0    ),//input
    	
    	.pixel_clk      (cmos1_pclk_16bit ),//output
    	.pdata_o        (cmos1_d_16bit    ),//output[15:0]
    	.de_o           (cmos1_href_16bit ) //output
    );


//CMOS2
    always@(posedge cmos2_pclk)
        begin
            cmos2_d_d0        <= cmos2_data    ;
            cmos2_href_d0     <= cmos2_href    ;
            cmos2_vsync_d0    <= cmos2_vsync   ;
        end

    cmos_8_16bit cmos2_8_16bit(
    	.pclk           (cmos2_pclk       ),//input
    	.rst_n          (cmos_init_done[1]),//input
    	.pdata_i        (cmos2_d_d0       ),//input[7:0]
    	.de_i           (cmos2_href_d0    ),//input
    	.vs_i           (cmos2_vsync_d0    ),//input
    	
    	.pixel_clk      (cmos2_pclk_16bit ),//output
    	.pdata_o        (cmos2_d_16bit    ),//output[15:0]
    	.de_o           (cmos2_href_16bit ) //output
    );
 wire [15:0]rgb_out /*synthesis PAP_MARK_DEBUG="1"*/;
wire vs_1 /*synthesis PAP_MARK_DEBUG="1"*/;
wire hs_1 /*synthesis PAP_MARK_DEBUG="1"*/;
wire de_1 /*synthesis PAP_MARK_DEBUG="1"*/;


//输入视频源选择//////////////////////////////////////////////////////////////////////////////////////////
`ifdef CMOS_1
assign     pclk_in_test    =    cmos1_pclk_16bit    ;
assign     vs_in_test      =    cmos1_vsync_d0      ;
assign     de_in_test      =    cmos1_href_16bit    ;
assign     i_rgb565        =    {cmos1_d_16bit[15:11],cmos1_d_16bit[10:5],cmos1_d_16bit[4:0]} ;
`elsif CMOS_2
assign     pclk_in_test    =    cmos2_pclk_16bit    ;
assign     vs_in_test      =    cmos2_vsync_d0      ;
assign     de_in_test      =    cmos2_href_16bit    ;
assign     i_rgb565        =    {cmos2_d_16bit[15:11],cmos2_d_16bit[10:5],cmos2_d_16bit[4:0]};//{r,g,b}

`endif
wire rstn_sync;
wire rd_en_fifo;
wire r;
wire [1:0]g;
wire b;

wr_ctrl wr_ctrl
    (
    .rstn(rstn),
    .cmos_pclk(cmos1_pclk),    // input
    .cmos_de(cmos1_href_16bit),        // input
    .cmos_data(cmos1_d_16bit),    // input[15:0]
    .cmos_vsync(cmos1_vsync),  // input
    .rstn_sync(rstn_sync),    // output
    .vga_clk(pix_clk),        // input
    .rd_en_fifo(rd_en_fifo),  // input
    .vga_vs(vs_out),
    .vga_data({r_out,r,g_out,g,b_out,b})       // output[15:0]
);
vga_test vga_test1(
   .pix_clk (pix_clk),
   .rstn (rstn_sync),
   .de(rd_en_fifo),                // output
   .vs_out (vs_out),
   .hs_out (hs_out),
   //.de_out (de_out),
    .r_out(),          // output
    .g_out(),          // output
    .b_out()           // output
   );

endmodule
