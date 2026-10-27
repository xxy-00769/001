`timescale 1ns/1ps
module fpga_gsv1_top#(
	parameter MEM_ROW_ADDR_WIDTH   = 15         ,
	parameter MEM_COL_ADDR_WIDTH   = 10         ,
	parameter MEM_BADDR_WIDTH      = 3          ,
	parameter MEM_DQ_WIDTH         =  32        ,
	parameter MEM_DQS_WIDTH        =  32/8,
    parameter SELF_TEST           = 0
)(
	input                                sys_clk              ,//50Mhz
    input [4:0] key_n,
    output [3:0] intent_led,
//OV5647
    //OV5640寄存器初始化完成
    //coms1	
    inout                                cmos1_scl            ,//cmos1 i2c 
    inout                                cmos1_sda            ,//cmos1 i2c 
    input                                cmos1_vsync          ,//cmos1 vsync
    input                                cmos1_href           ,//cmos1 hsync refrence,data valid
    input                                cmos1_pclk           ,//cmos1 pxiel clock
    input   [7:0]                        cmos1_data           ,//cmos1 data
    output                               cmos1_reset          ,//cmos1 reset
    //coms2
    inout                                cmos2_scl            ,//cmos2 i2c 
    inout                                cmos2_sda            ,//cmos2 i2c 
    input                                cmos2_vsync          ,//cmos2 vsync
    input                                cmos2_href           ,//cmos2 hsync refrence,data valid
    input                                cmos2_pclk           ,//cmos2 pxiel clock
    input   [7:0]                        cmos2_data           ,//cmos2 data
    output                               cmos2_reset          ,//cmos2 reset
//DDR
    output                               mem_rst_n                 ,
    output                               mem_ck                    ,
    output                               mem_ck_n                  ,
    output                               mem_cke                   ,
    output                               mem_cs_n                  ,
    output                               mem_ras_n                 ,
    output                               mem_cas_n                 ,
    output                               mem_we_n                  ,
    output                               mem_odt                   ,
    output      [MEM_ROW_ADDR_WIDTH-1:0] mem_a                     ,
    output      [MEM_BADDR_WIDTH-1:0]    mem_ba                    ,
    inout       [MEM_DQ_WIDTH/8-1:0]     mem_dqs                   ,
    inout       [MEM_DQ_WIDTH/8-1:0]     mem_dqs_n                 ,
    inout       [MEM_DQ_WIDTH-1:0]       mem_dq                    ,
    output      [MEM_DQ_WIDTH/8-1:0]     mem_dm                    ,


//MS72xx       
    output                               rstn_out                  ,
    output                               iic_tx_scl                ,
    inout                                iic_tx_sda                ,
//HDMI_OUT初始化完成
//HDMI_OUT
    output                               pix_clk                   ,//pixclk                           
    output     reg                       vs_out                    , 
    output     reg                       hs_out                    , 
    output     reg                       de_out                    ,
    output     reg[7:0]                  r_out                     , 
    output     reg[7:0]                  g_out                     , 
    output     reg[7:0]                  b_out         
);
wire [1:0] cmos_init_done;
wire ddr_init_done, hdmi_int_led;
wire cfg_clk, clk_25M, locked, core_clk, pll_lock;
wire init_over_tx;
/////////////////////////////////////////////////////////////////////////////////////
// ENABLE_DDR
    parameter CTRL_ADDR_WIDTH = MEM_ROW_ADDR_WIDTH + MEM_BADDR_WIDTH + MEM_COL_ADDR_WIDTH;//28
    parameter TH_1S = 27'd33000000;
/////////////////////////////////////////////////////////////////////////////////////
    reg  [15:0]                 rstn_1ms            ;
    wire                        cmos_scl            ;//cmos i2c clock
    wire                        cmos_sda            ;//cmos i2c data
    wire                        cmos_vsync          ;//cmos vsync
    wire                        cmos_href           ;//cmos hsync refrence,data valid
    wire                        cmos_pclk           ;//cmos pxiel clock
    wire   [7:0]                cmos_data           ;//cmos data
    wire                        cmos_reset          ;//cmos reset
    wire                        initial_en          ;
    wire[15:0]                  cmos1_d_16bit       ;
    wire                        cmos1_href_16bit    ;
    reg [7:0]                   cmos1_d_d0          ;
    reg                         cmos1_href_d0       ;
    reg                         cmos1_vsync_d0      ;
    wire                        cmos1_pclk_16bit    ;
    wire[15:0]                  cmos2_d_16bit       /*synthesis PAP_MARK_DEBUG="1"*/;
    wire                        cmos2_href_16bit    /*synthesis PAP_MARK_DEBUG="1"*/;
    reg [7:0]                   cmos2_d_d0          /*synthesis PAP_MARK_DEBUG="1"*/;
    reg                         cmos2_href_d0       /*synthesis PAP_MARK_DEBUG="1"*/;
    reg                         cmos2_vsync_d0      /*synthesis PAP_MARK_DEBUG="1"*/;
    wire                        cmos2_pclk_16bit    /*synthesis PAP_MARK_DEBUG="1"*/;
    wire[15:0]                  o_rgb565            ;
    wire                        pclk_in_test        ;    
    wire                        vs_in_test          ;
    wire                        de_in_test          ;
    wire[15:0]                  i_rgb565            ;
    wire                        de_re               ;
//axi bus   
    wire [CTRL_ADDR_WIDTH-1:0]  axi_awaddr                 ;
    wire                        axi_awuser_ap              ;
    wire [3:0]                  axi_awuser_id              ;
    wire [3:0]                  axi_awlen                  ;
    wire                        axi_awready                ;/*synthesis PAP_MARK_DEBUG="1"*/
    wire                        axi_awvalid                ;/*synthesis PAP_MARK_DEBUG="1"*/
    wire [MEM_DQ_WIDTH*8-1:0]   axi_wdata                  ;
    wire [MEM_DQ_WIDTH*8/8-1:0] axi_wstrb                  ;
    wire                        axi_wready                 ;/*synthesis PAP_MARK_DEBUG="1"*/
    wire [3:0]                  axi_wusero_id              ;
    wire                        axi_wusero_last            ;
    wire [CTRL_ADDR_WIDTH-1:0]  axi_araddr                 ;
    wire                        axi_aruser_ap              ;
    wire [3:0]                  axi_aruser_id              ;
    wire [3:0]                  axi_arlen                  ;
    wire                        axi_arready                ;/*synthesis PAP_MARK_DEBUG="1"*/
    wire                        axi_arvalid                ;/*synthesis PAP_MARK_DEBUG="1"*/
    wire [MEM_DQ_WIDTH*8-1:0]   axi_rdata                   /* synthesis syn_keep = 1 */;
    wire                        axi_rvalid                  /* synthesis syn_keep = 1 */;
    wire [3:0]                  axi_rid                    ;
    wire                        axi_rlast                  ;
    reg  [26:0]                 cnt                        ;
    reg  [15:0]                 cnt_1                      ;
/////////////////////////////////////////////////////////////////////////////////////
//PLL
    pll_mpi7001 u_pll (
        .clkin1   (  sys_clk    ),//50MHz
        .clkout0  (  pix_clk    ),//29.545454 MHz MPI7001 800x480
        .clkout1  (  cfg_clk    ),//10MHz
        .clkout2  (  clk_25M    ),//25M
        .pll_lock (  locked     )
    );

//配置7210
    hdmi_tx_config tx_config(.clk(cfg_clk), .rst_n(rstn_out),
        .done(init_over_tx), .scl(iic_tx_scl), .sda(iic_tx_sda));
   assign    hdmi_int_led    =    init_over_tx; 
    
    always @(posedge cfg_clk)
    begin
    	if(!locked)
    	    rstn_1ms <= 16'd0;
    	else
    	begin
    		if(rstn_1ms == 16'h2710)
    		    rstn_1ms <= rstn_1ms;
    		else
    		    rstn_1ms <= rstn_1ms + 1'b1;
    	end
    end
    
    assign rstn_out = (rstn_1ms == 16'h2710);

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


    wire [4:0] key_pressed;
    wire view_request;
    m1_keys keys(.clk(sys_clk),.rst_n(rstn_out),.key_n(key_n),
        .intent_led(intent_led),.view_request(view_request),.pressed(key_pressed));
    wire frame_sync, read_request, panel_hs, panel_vs, panel_de, panel_image;
    wire [9:0] panel_x; wire [8:0] panel_y;
    mpi7001_timing timing_panel(.clk(pix_clk),.rst_n(rstn_out && ddr_init_done),
        .frame_sync(frame_sync),.read_request(read_request),.hs(panel_hs),
        .vs(panel_vs),.de(panel_de),.image_area(panel_image),
        .diagnostic_rgb(),.active_x(panel_x),.active_y(panel_y));
    reg [1:0] view_sync;
    reg selected_view, fs_d;
    always @(posedge pix_clk or negedge rstn_out) begin
        if(!rstn_out) begin view_sync<=0; selected_view<=0; fs_d<=0; end
        else begin
            view_sync<={view_sync[0],view_request}; fs_d<=frame_sync;
            if(frame_sync && !fs_d) selected_view<=view_sync[1];
        end
    end
    wire [55:0] s_awaddr, s_araddr;
    wire [7:0] s_awlen, s_arlen;
    wire [1:0] s_awvalid,s_awready,s_wready,s_wlast,s_arvalid,s_arready,s_rvalid,s_rlast;
    wire [511:0] s_wdata;
    wire [63:0] s_wstrb;
    wire [1:0] source_de, source_ready, source_healthy;
    wire [31:0] source_rgb;

    wire pipe_rst0, verdict_valid0;
    wire [31:0] open_id0,open_time0,verdict_id0;
    wire [7:0] verdict_errors0;
    wire cap_vs0,cap_de0; wire [15:0] cap_rgb0;
    wire [31:0] cap_id0,cap_time0;
    wire [255:0] status0 /* synthesis syn_keep = 1 */;
    video_capture_status #(.SOURCE_ID(0)) monitor0(
        .ref_clk(sys_clk),.video_clk(cmos1_pclk_16bit),.rst_n(rstn_out),
        .source_ready(cmos_init_done[0]),.video_vs(cmos1_vsync_d0),
        .video_de(cmos1_href_16bit),.pipeline_rst_n(pipe_rst0),
        .healthy(source_healthy[0]),.timed_out(),.timeout_count(),
        .snapshot_valid(),.snapshot(status0),.frame_open_id(open_id0),
        .frame_open_time(open_time0),.frame_result_valid(verdict_valid0),
        .frame_result_id(verdict_id0),.frame_result_errors(verdict_errors0));
    capture_pipe pipe0(.clk(cmos1_pclk_16bit),.rst_n(pipe_rst0),
        .vs(cmos1_vsync_d0),.de(cmos1_href_16bit),
        .rgb({cmos1_d_16bit[4:0],cmos1_d_16bit[10:5],cmos1_d_16bit[15:11]}),
        .frame_id(open_id0),.frame_time(open_time0),
        .out_vs(cap_vs0),.out_de(cap_de0),.out_rgb(cap_rgb0),
        .out_id(cap_id0),.out_time(cap_time0));
    fram_buf #(.DISPLAY_HALF(1),.SOURCE_ID(0)) buffer0(
        .ddr_clk(core_clk),.ddr_rstn(ddr_init_done),
        .vin_clk(cmos1_pclk_16bit),.wr_fsync(cap_vs0),.wr_en(cap_de0),
        .wr_data(cap_rgb0),.pipeline_running(pipe_rst0),
        .wr_frame_id(cap_id0),.wr_frame_time(cap_time0),
        .source_result_valid(verdict_valid0),.source_result_id(verdict_id0),
        .source_result_errors(verdict_errors0),
        .vout_clk(pix_clk),.rd_fsync(frame_sync),.rd_en(read_request),
        .vout_de(source_de[0]),.vout_data(source_rgb[0+:16]),
        .init_done(source_ready[0]),
        .axi_awaddr(s_awaddr[0+:28]),.axi_awid(),.axi_awlen(s_awlen[0+:4]),
        .axi_awsize(),.axi_awburst(),.axi_awready(s_awready[0]),.axi_awvalid(s_awvalid[0]),
        .axi_wdata(s_wdata[0+:256]),.axi_wstrb(s_wstrb[0+:32]),
        .axi_wlast(s_wlast[0]),.axi_wvalid(),.axi_wready(s_wready[0]),.axi_bid(4'd0),
        .axi_araddr(s_araddr[0+:28]),.axi_arid(),.axi_arlen(s_arlen[0+:4]),
        .axi_arsize(),.axi_arburst(),.axi_arvalid(s_arvalid[0]),.axi_arready(s_arready[0]),
        .axi_rready(),.axi_rdata(axi_rdata),.axi_rvalid(s_rvalid[0]),
        .axi_rlast(s_rlast[0]),.axi_rid(4'd0));

    wire pipe_rst1, verdict_valid1;
    wire [31:0] open_id1,open_time1,verdict_id1;
    wire [7:0] verdict_errors1;
    wire cap_vs1,cap_de1; wire [15:0] cap_rgb1;
    wire [31:0] cap_id1,cap_time1;
    wire [255:0] status1 /* synthesis syn_keep = 1 */;
    video_capture_status #(.SOURCE_ID(1)) monitor1(
        .ref_clk(sys_clk),.video_clk(cmos2_pclk_16bit),.rst_n(rstn_out),
        .source_ready(cmos_init_done[1]),.video_vs(cmos2_vsync_d0),
        .video_de(cmos2_href_16bit),.pipeline_rst_n(pipe_rst1),
        .healthy(source_healthy[1]),.timed_out(),.timeout_count(),
        .snapshot_valid(),.snapshot(status1),.frame_open_id(open_id1),
        .frame_open_time(open_time1),.frame_result_valid(verdict_valid1),
        .frame_result_id(verdict_id1),.frame_result_errors(verdict_errors1));
    capture_pipe pipe1(.clk(cmos2_pclk_16bit),.rst_n(pipe_rst1),
        .vs(cmos2_vsync_d0),.de(cmos2_href_16bit),
        .rgb({cmos2_d_16bit[4:0],cmos2_d_16bit[10:5],cmos2_d_16bit[15:11]}),
        .frame_id(open_id1),.frame_time(open_time1),
        .out_vs(cap_vs1),.out_de(cap_de1),.out_rgb(cap_rgb1),
        .out_id(cap_id1),.out_time(cap_time1));
    fram_buf #(.DISPLAY_HALF(1),.SOURCE_ID(1)) buffer1(
        .ddr_clk(core_clk),.ddr_rstn(ddr_init_done),
        .vin_clk(cmos2_pclk_16bit),.wr_fsync(cap_vs1),.wr_en(cap_de1),
        .wr_data(cap_rgb1),.pipeline_running(pipe_rst1),
        .wr_frame_id(cap_id1),.wr_frame_time(cap_time1),
        .source_result_valid(verdict_valid1),.source_result_id(verdict_id1),
        .source_result_errors(verdict_errors1),
        .vout_clk(pix_clk),.rd_fsync(frame_sync),.rd_en(read_request),
        .vout_de(source_de[1]),.vout_data(source_rgb[16+:16]),
        .init_done(source_ready[1]),
        .axi_awaddr(s_awaddr[28+:28]),.axi_awid(),.axi_awlen(s_awlen[4+:4]),
        .axi_awsize(),.axi_awburst(),.axi_awready(s_awready[1]),.axi_awvalid(s_awvalid[1]),
        .axi_wdata(s_wdata[256+:256]),.axi_wstrb(s_wstrb[32+:32]),
        .axi_wlast(s_wlast[1]),.axi_wvalid(),.axi_wready(s_wready[1]),.axi_bid(4'd0),
        .axi_araddr(s_araddr[28+:28]),.axi_arid(),.axi_arlen(s_arlen[4+:4]),
        .axi_arsize(),.axi_arburst(),.axi_arvalid(s_arvalid[1]),.axi_arready(s_arready[1]),
        .axi_rready(),.axi_rdata(axi_rdata),.axi_rvalid(s_rvalid[1]),
        .axi_rlast(s_rlast[1]),.axi_rid(4'd0));

    assign axi_awuser_id=0; assign axi_aruser_id=0;
    dual_ddr_arbiter arbiter(.clk(core_clk),.rst_n(ddr_init_done),
        .s_awaddr(s_awaddr),.s_awlen(s_awlen),.s_awvalid(s_awvalid),.s_awready(s_awready),
        .s_wdata(s_wdata),.s_wstrb(s_wstrb),.s_wready(s_wready),.s_wlast(s_wlast),
        .s_araddr(s_araddr),.s_arlen(s_arlen),.s_arvalid(s_arvalid),.s_arready(s_arready),
        .s_rvalid(s_rvalid),.s_rlast(s_rlast),
        .awaddr(axi_awaddr),.awlen(axi_awlen),.awvalid(axi_awvalid),.awready(axi_awready),
        .wdata(axi_wdata),.wstrb(axi_wstrb),.wready(axi_wready),.wlast(axi_wusero_last),
        .araddr(axi_araddr),.arlen(axi_arlen),.arvalid(axi_arvalid),.arready(axi_arready),
        .rvalid(axi_rvalid),.rlast(axi_rlast));
    wire [15:0] selected_rgb=selected_view ? source_rgb[31:16] : source_rgb[15:0];
    wire selected_de=selected_view ? source_de[1] : source_de[0];
    wire selected_health=selected_view ? source_healthy[1] : source_healthy[0];
    wire show_video;
    video_present_guard guard_display(.clk(pix_clk),.rst_n(rstn_out),
        .healthy(selected_health),.vs(frame_sync),.show_video(show_video));
    wire label_area,label_pixel;
    m1_osd osd(.x(panel_x),.y(panel_y),.rear(selected_view),
        .area(label_area),.pixel(label_pixel));
    always @(posedge pix_clk) begin
        vs_out<=panel_vs; hs_out<=panel_hs; de_out<=panel_de;
        if(panel_de && label_area) begin
            r_out<=label_pixel ? 8'hff : 0;
            g_out<=label_pixel ? 8'hff : 0;
            b_out<=0;
        end else if(panel_image && selected_de && show_video) begin
            r_out<={selected_rgb[15:11],selected_rgb[15:13]};
            g_out<={selected_rgb[10:5],selected_rgb[10:9]};
            b_out<={selected_rgb[4:0],selected_rgb[4:2]};
        end else begin r_out<=0; g_out<=0; b_out<=0; end
    end

//ddr    
        DDR3_50H u_DDR3_50H (
             .ref_clk                   (sys_clk            ),
             .resetn                    (rstn_out           ),// input
             .ddr_init_done             (ddr_init_done      ),// output
             .ddrphy_clkin              (core_clk           ),// output
             .pll_lock                  (pll_lock           ),// output

             .axi_awaddr                (axi_awaddr         ),// input [27:0]
             .axi_awuser_ap             (1'b0               ),// input
             .axi_awuser_id             (axi_awuser_id      ),// input [3:0]
             .axi_awlen                 (axi_awlen          ),// input [3:0]
             .axi_awready               (axi_awready        ),// output
             .axi_awvalid               (axi_awvalid        ),// input
             .axi_wdata                 (axi_wdata          ),
             .axi_wstrb                 (axi_wstrb          ),// input [31:0]
             .axi_wready                (axi_wready         ),// output
             .axi_wusero_id             (                   ),// output [3:0]
             .axi_wusero_last           (axi_wusero_last    ),// output
             .axi_araddr                (axi_araddr         ),// input [27:0]
             .axi_aruser_ap             (1'b0               ),// input
             .axi_aruser_id             (axi_aruser_id      ),// input [3:0]
             .axi_arlen                 (axi_arlen          ),// input [3:0]
             .axi_arready               (axi_arready        ),// output
             .axi_arvalid               (axi_arvalid        ),// input
             .axi_rdata                 (axi_rdata          ),// output [255:0]
             .axi_rid                   (axi_rid            ),// output [3:0]
             .axi_rlast                 (axi_rlast          ),// output
             .axi_rvalid                (axi_rvalid         ),// output

             .apb_clk                   (1'b0               ),// input
             .apb_rst_n                 (1'b1               ),// input
             .apb_sel                   (1'b0               ),// input
             .apb_enable                (1'b0               ),// input
             .apb_addr                  (8'b0               ),// input [7:0]
             .apb_write                 (1'b0               ),// input
             .apb_ready                 (                   ), // output
             .apb_wdata                 (16'b0              ),// input [15:0]
             .apb_rdata                 (                   ),// output [15:0]
             .apb_int                   (                   ),// output

             .mem_rst_n                 (mem_rst_n          ),// output
             .mem_ck                    (mem_ck             ),// output
             .mem_ck_n                  (mem_ck_n           ),// output
             .mem_cke                   (mem_cke            ),// output
             .mem_cs_n                  (mem_cs_n           ),// output
             .mem_ras_n                 (mem_ras_n          ),// output
             .mem_cas_n                 (mem_cas_n          ),// output
             .mem_we_n                  (mem_we_n           ),// output
             .mem_odt                   (mem_odt            ),// output
             .mem_a                     (mem_a              ),// output [14:0]
             .mem_ba                    (mem_ba             ),// output [2:0]
             .mem_dqs                   (mem_dqs            ),// inout [3:0]
             .mem_dqs_n                 (mem_dqs_n          ),// inout [3:0]
             .mem_dq                    (mem_dq             ),// inout [31:0]
             .mem_dm                    (mem_dm             ),// output [3:0]
             //debug
             .debug_data                (                   ),// output [135:0]
             .debug_slice_state         (                   ),// output [51:0]
             .debug_calib_ctrl          (                   ),// output [21:0]
             .ck_dly_set_bin            (                   ),// output [7:0]
             .force_ck_dly_en           (1'b0               ),// input
             .force_ck_dly_set_bin      (8'h05              ),// input [7:0]
             .dll_step                  (                   ),// output [7:0]
             .dll_lock                  (                   ),// output
             .init_read_clk_ctrl        (2'b0               ),// input [1:0]
             .init_slip_step            (4'b0               ),// input [3:0]
             .force_read_clk_ctrl       (1'b0               ),// input
             .ddrphy_gate_update_en     (1'b0               ),// input
             .update_com_val_err_flag   (                   ),// output [3:0]
             .rd_fake_stop              (1'b0               ) // input
       );


endmodule
