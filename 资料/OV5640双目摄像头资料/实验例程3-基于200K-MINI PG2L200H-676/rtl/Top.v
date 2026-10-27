`timescale 1ns / 1ps
module Top#(
	parameter MEM_ROW_ADDR_WIDTH   = 15         ,
	parameter MEM_COL_ADDR_WIDTH   = 10         ,
	parameter MEM_BADDR_WIDTH      = 3          ,
	parameter MEM_DQ_WIDTH         =  32        ,
	parameter MEM_DQS_WIDTH        =  32/8
)(
	input   wire                                sys_clk        ,//27Mhz
    input   wire                                clk_p          ,
    input   wire                                clk_n          ,
    input   wire                                rst_in         ,
    //DDR
    output  wire                                mem_rst_n      ,
    output  wire                                mem_ck         ,
    output  wire                                mem_ck_n       ,
    output  wire                                mem_cke        ,
    output  wire                                mem_cs_n       ,
    output  wire                                mem_ras_n      ,
    output  wire                                mem_cas_n      ,
    output  wire                                mem_we_n       ,
    output  wire                                mem_odt        ,
    output  wire    [MEM_ROW_ADDR_WIDTH-1:0]    mem_a          ,
    output  wire    [MEM_BADDR_WIDTH-1:0]       mem_ba         ,
    inout   wire    [MEM_DQ_WIDTH/8-1:0]        mem_dqs        ,
    inout   wire    [MEM_DQ_WIDTH/8-1:0]        mem_dqs_n      ,
    inout   wire    [MEM_DQ_WIDTH-1:0]          mem_dq         ,
    output  wire    [MEM_DQ_WIDTH/8-1:0]        mem_dm         ,
    output  reg                                 heart_beat_led ,
    //cam
    input   wire                                camera_clk_0   ,
    input   wire    [7:0]                       camera_data_0  ,
    input   wire                                camera_href_0  ,
    input   wire                                camera_vsync_0 ,
    output  wire                                SCL_0          ,
    output  wire                                SDA_0          ,
    output  wire                                cam_rst_0      ,
    //cam   
    input   wire                                camera_clk_1   ,
    input   wire    [7:0]                       camera_data_1  ,
    input   wire                                camera_href_1  ,
    input   wire                                camera_vsync_1 ,
    output  wire                                SCL_1          ,
    output  wire                                SDA_1          ,
    output  wire                                cam_rst_1      ,
    //hdmi                                                            
    output  wire    [2:0]                       tmds_data_p    ,
    output  wire    [2:0]                       tmds_data_n    ,
    output  wire                                tmds_clk_p     ,
    output  wire                                tmds_clk_n     ,

    output  reg                                 cam_led0       ,
    output  reg                                 cam_led1       
);
//=====================================================================================
//reg define
//=====================================================================================
// ENABLE_DDR
parameter CTRL_ADDR_WIDTH = MEM_ROW_ADDR_WIDTH + MEM_BADDR_WIDTH + MEM_COL_ADDR_WIDTH;//28
parameter TH_1S = 27'd33000000;
wire  ddr_init_done;
assign  LCD_EN   = 1'b1;
//=====================================================================================
//clk
//=====================================================================================
wire    pclk;
wire    pclkx5;
wire    locked0;
wire    rst_n;

clk_hdmi clk_hdmi_inst (
  .clkout0(pclk),    // output
  .clkout1(pclkx5 ),    // output
  .lock(locked0),          // output
  .clkin1(sys_clk)       // input
);

assign rst_n = locked0 & rst_in;

//===========================================================================
// camera
//===========================================================================
wire            cam_vsync_0;
wire            cam_href_0;
wire            cam_write_en_0;
wire    [15:0]  cam_data_0;

wire            cam_vsync_1;
wire            cam_href_1;
wire            cam_write_en_1;
wire    [15:0]  cam_data_1;

wire            cam_init_done_0;
wire            cam_init_done_1;

camera camera_inst0(
    /*input   wire            */.clk           ( sys_clk             )  ,
    /*input   wire            */.rst_n         ( rst_n               )  ,
    /*output  wire            */.SCL           ( SCL_0               )  ,  
    /*output  wire            */.SDA           ( SDA_0               )  ,  
    /*input   wire            */.camera_clk    ( camera_clk_0        )  ,
    /*input   wire    [7:0]   */.camera_data   ( camera_data_0       )  ,
    /*input   wire            */.camera_herf   ( camera_href_0       )  ,
    /*input   wire            */.camera_vsync  ( camera_vsync_0      )  ,
    /*input   wire            */.ddr_init      ( ddr_init_done       )  ,
    /*output  wire            */.camera_rstn   ( cam_rst_0           )  ,
    /*output  wire            */.camera_pwnd   ()  ,
    /*output  wire            */.init_done     ( cam_init_done_0     )  ,
    /*output  wire    [15:0]  */.wf_wr_data    ( cam_data_0          )  ,   //RGB565
    /*output  wire            */.wf_wr_en      ( cam_write_en_0      )  ,
    /*output  wire            */.vs            ( cam_vsync_0         )  ,
    /*output  wire            */.hs            ( cam_href_0          )  ,
    /*output  wire            */.sop           ()  ,
    /*output  wire            */.eop           ()  
);

camera camera_inst1(
    /*input   wire            */.clk           ( sys_clk             )  ,
    /*input   wire            */.rst_n         ( rst_n & cam_init_done_0 )  ,
    /*output  wire            */.SCL           ( SCL_1               )  ,  
    /*output  wire            */.SDA           ( SDA_1               )  ,  
    /*input   wire            */.camera_clk    ( camera_clk_1        )  ,
    /*input   wire    [7:0]   */.camera_data   ( camera_data_1       )  ,
    /*input   wire            */.camera_herf   ( camera_href_1       )  ,
    /*input   wire            */.camera_vsync  ( camera_vsync_1      )  ,
    /*input   wire            */.ddr_init      ( ddr_init_done       )  ,
    /*output  wire            */.camera_rstn   ( cam_rst_1           )  ,
    /*output  wire            */.camera_pwnd   ()  ,
    /*output  wire            */.init_done     ( cam_init_done_1     )  ,
    /*output  wire    [15:0]  */.wf_wr_data    ( cam_data_1          )  ,   //RGB565
    /*output  wire            */.wf_wr_en      ( cam_write_en_1      )  ,
    /*output  wire            */.vs            ( cam_vsync_1         )  ,
    /*output  wire            */.hs            ( cam_href_1          )  ,
    /*output  wire            */.sop           ()  ,
    /*output  wire            */.eop           ()  
);

//camera clk signal
reg  [27:0]     cam_cnt_0;
reg             cam_cnt_flag_0;

reg  [27:0]     cam_cnt_1;
reg             cam_cnt_flag_1;

always @(posedge camera_clk_0 or negedge rst_n) begin
    if (!rst_n) begin
        cam_cnt_0 <= 28'd0;
        cam_cnt_flag_0 <= 1'b0;
    end
    else if(cam_cnt_0 == 28'd24_000_000) begin
        cam_cnt_0 <= 28'd0;
        cam_cnt_flag_0 <= 1'b1;
    end
    else begin
        cam_cnt_0 <= cam_cnt_0 + 28'd1;
        cam_cnt_flag_0 <= 1'b0;
    end
end

always @(posedge camera_clk_1 or negedge rst_n) begin
    if (!rst_n) begin
        cam_cnt_1 <= 28'd0;
        cam_cnt_flag_1 <= 1'b0;
    end
    else if(cam_cnt_1 == 28'd24_000_000) begin
        cam_cnt_1 <= 28'd0;
        cam_cnt_flag_1 <= 1'b1;
    end
    else begin
        cam_cnt_1 <= cam_cnt_1 + 28'd1;
        cam_cnt_flag_1 <= 1'b0;
    end
end

always @(posedge camera_clk_0 or negedge rst_n) begin
    if (!rst_n)
        cam_led0 <= 1'b1;
    else if(cam_cnt_flag_0)
        cam_led0 <= ~cam_led0;
end

always @(posedge camera_clk_1 or negedge rst_n) begin
    if (!rst_n)
        cam_led1 <= 1'b1;
    else if(cam_cnt_flag_1)
        cam_led1 <= ~cam_led1;
end


//=====================================================================================
//video_scale
//=====================================================================================
wire    [15:0]    write_data_0;
wire              write_en_0;

wire    [15:0]    write_data_1;
wire              write_en_1;

video_scale_down#(
    .PIX_DATA_WIDTH       ( 16 )
)video_scale_down_inst0(
    .video_clk            ( camera_clk_0   ),
    .rst_n                ( rst_n          ),
    .frame_sync_n         ( ~cam_vsync_0   ),
    .video_data_in        ( cam_data_0     ),
    .video_data_valid     ( cam_write_en_0 ),
    .video_data_out       ( write_data_0   ),
    .video_data_out_valid ( write_en_0     ),
    .video_ready          ( 1'b1           ),
    .video_width_in       ( 1280           ),
    .video_height_in      ( 720            ),
    .video_width_out      ( 640            ),
    .video_height_out     ( 720            )
);

video_scale_down#(
    .PIX_DATA_WIDTH       ( 16 )
)video_scale_down_inst1(
    .video_clk            ( camera_clk_1   ),
    .rst_n                ( rst_n          ),
    .frame_sync_n         ( ~cam_vsync_1   ),
    .video_data_in        ( cam_data_1     ),
    .video_data_valid     ( cam_write_en_1 ),
    .video_data_out       ( write_data_1   ),
    .video_data_out_valid ( write_en_1     ),
    .video_ready          ( 1'b1           ),
    .video_width_in       ( 1280           ),
    .video_height_in      ( 720            ),
    .video_width_out      ( 640            ),
    .video_height_out     ( 720            )
);

wire                            write_req_0;
wire                            write_req_ack_0;
wire[1:0]                       write_addr_index_0;
wire[1:0]                       read_addr_index_0;

wire                            write_req_1;
wire                            write_req_ack_1;
wire[1:0]                       write_addr_index_1;
wire[1:0]                       read_addr_index_1;

cmos_write_req_gen cmos_write_req_gen_inst0(
	.rst                        ( ~rst_n             ),
	.pclk                       ( camera_clk_0       ),
	.cmos_vsync                 ( cam_vsync_0        ),
	.write_req                  ( write_req_0        ),
	.write_addr_index           ( write_addr_index_0 ),
	.read_addr_index            ( read_addr_index_0  ),
	.write_req_ack              ( write_req_ack_0    )
);

cmos_write_req_gen cmos_write_req_gen_inst1(
	.rst                        ( ~rst_n             ),
	.pclk                       ( camera_clk_1       ),
	.cmos_vsync                 ( cam_vsync_1        ),
	.write_req                  ( write_req_1        ),
	.write_addr_index           ( write_addr_index_1 ),
	.read_addr_index            ( read_addr_index_1  ),
	.write_req_ack              ( write_req_ack_1    )
);

//=====================================================================================
//产生visa时序 
//=====================================================================================
parameter X_WIDTH   = 4'd12;
parameter Y_WIDTH   = 4'd12; 
localparam  X_BITS   = 4'd13   ;
localparam  Y_BITS   = 4'd13   ;
localparam  V_TOTAL  = 12'd750 ;
localparam  V_FP     = 12'd5   ;
localparam  V_BP     = 12'd20  ;
localparam  V_SYNC   = 12'd5   ;
localparam  V_ACT    = 12'd720 ;
localparam  H_TOTAL  = 12'd1650;
localparam  H_FP     = 12'd110 ;
localparam  H_BP     = 12'd220 ;
localparam  H_SYNC   = 12'd40  ;
localparam  H_ACT    = 12'd1280;

wire            read_req_0;
wire            read_req_ack_0;
wire            read_en_0;
wire    [15:0]  read_data_0;
    
wire            read_req_1;
wire            read_req_ack_1;
wire            read_en_1;
wire    [15:0]  read_data_1;

wire            vs_out_sync;
wire            hs_out_sync;
wire            de_out_sync;

wire            vs_out_0;
wire            hs_out_0;
wire            de_out_0;

wire            vs_out_1;
wire            hs_out_1;
wire            de_out_1;

wire    [15:0]  vout_data_0;
wire    [15:0]  vout_data_1;

sync_vg #(
    .X_BITS               ( X_WIDTH ), 
    .Y_BITS               ( Y_WIDTH ),
    .V_TOTAL              ( V_TOTAL ),
    .V_FP                 ( V_FP    ),
    .V_BP                 ( V_BP    ),
    .V_SYNC               ( V_SYNC  ),
    .V_ACT                ( V_ACT   ),
    .H_TOTAL              ( H_TOTAL ),
    .H_FP                 ( H_FP    ),
    .H_BP                 ( H_BP    ),
    .H_SYNC               ( H_SYNC  ),
    .H_ACT                ( H_ACT   )
) sync_vg_inst (                                                 
    .clk                  ( pclk        ),
    .rstn                 ( rst_n       ),
    .vs_out               ( vs_out_sync ),
    .hs_out               ( hs_out_sync ),
    .de_out               ( de_out_sync ),
    .x_act                (),            
    .y_act                ()             
); 


video_rect_read_data video_rect_read_data_inst0(
	.video_clk                  ( pclk           ),
	.rst                        ( ~rst_n         ),
	.video_left_offset          ( 0              ),
	.video_top_offset           ( 0              ),
	.video_width                ( 640            ),
	.video_height	            ( 720            ),
	.read_req                   ( read_req_0     ),
	.read_req_ack               ( read_req_ack_0 ),
	.read_en                    ( read_en_0      ),
	.read_data                  ( read_data_0    ),
	.timing_hs                  ( hs_out_sync    ),
	.timing_vs                  ( vs_out_sync    ),
	.timing_de                  ( de_out_sync    ),
	.timing_data 	            ( 0              ),
	.hs                         ( hs_out_0       ),
	.vs                         ( vs_out_0       ),
	.de                         ( de_out_0       ),
	.vout_data                  ( vout_data_0    )
);

video_rect_read_data video_rect_read_data_inst1(
	.video_clk                  ( pclk           ),
	.rst                        ( ~rst_n         ),
	.video_left_offset          ( 640            ),
	.video_top_offset           ( 0              ),
	.video_width                ( 640            ),
	.video_height	            ( 720            ),
	.read_req                   ( read_req_1     ),
	.read_req_ack               ( read_req_ack_1 ),
	.read_en                    ( read_en_1      ),
	.read_data                  ( read_data_1    ),
	.timing_hs                  ( hs_out_0       ),
	.timing_vs                  ( vs_out_0       ),
	.timing_de                  ( de_out_0       ),
	.timing_data 	            ( vout_data_0    ),
	.hs                         ( hs_out_1       ),
	.vs                         ( vs_out_1       ),
	.de                         ( de_out_1       ),
	.vout_data                  ( vout_data_1    )
);

//===========================================================================
// 视频输出
//===========================================================================
wire            hs_out   ;
wire            vs_out   ;
wire            de_out   ;
wire    [23:0]  vout_data;

assign hs_out    =  hs_out_1    ;
assign vs_out    =  vs_out_1    ;
assign de_out    =  de_out_1    ;
assign vout_data = {vout_data_1[15:11], 3'b0, vout_data_1[10:5], 2'b0, vout_data_1[4:0], 3'b0};

rgb2tmds rgb2tmds_inst (
    /*output  wire            */.tmds_clk_p  ( tmds_clk_p   ) ,
    /*output  wire            */.tmds_clk_n  ( tmds_clk_n   ) ,
    /*output  wire    [2:0]   */.tmds_data_p ( tmds_data_p  ) ,
    /*output  wire    [2:0]   */.tmds_data_n ( tmds_data_n  ) ,

    /*input   wire            */.rstn        ( rst_n        ) ,

    /*input   wire    [23:0]  */.vid_pdata   ( vout_data    ) ,
    /*input   wire            */.vid_pvde    ( de_out       ) ,
    /*input   wire            */.vid_phsync  ( hs_out       ) ,
    /*input   wire            */.vid_pvsync  ( vs_out       ) ,
 
    /*input   wire            */.pixelclk    ( pclk         ) ,
    /*input   wire            */.serialclk   ( pclkx5       ) 
);

//=====================================================================================
//ddr读写模块
//=====================================================================================
parameter MEM_DATA_BITS          = 256;             //external memory user interface data width
parameter ADDR_BITS              = 25;             //external memory user interface address width
parameter BUSRT_BITS             = 10;             //external memory user interface burst width

wire                            wr_burst_req;
wire[BUSRT_BITS - 1:0]          wr_burst_len;
wire[ADDR_BITS - 1:0]           wr_burst_addr;
wire                            wr_burst_data_req;
wire[MEM_DATA_BITS - 1 : 0]     wr_burst_data;
wire                            wr_burst_finish;

wire                            rd_burst_req;
wire[BUSRT_BITS - 1:0]          rd_burst_len;
wire[ADDR_BITS - 1:0]           rd_burst_addr;
wire                            rd_burst_data_valid;
wire[MEM_DATA_BITS - 1 : 0]     rd_burst_data;
wire                            rd_burst_finish;


wire                            wr_burst_req_0;
wire[BUSRT_BITS - 1:0]          wr_burst_len_0;
wire[ADDR_BITS - 1:0]           wr_burst_addr_0;
wire                            wr_burst_data_req_0;
wire[MEM_DATA_BITS - 1 : 0]     wr_burst_data_0;
wire                            wr_burst_finish_0;

wire                            rd_burst_req_0;
wire[BUSRT_BITS - 1:0]          rd_burst_len_0;
wire[ADDR_BITS - 1:0]           rd_burst_addr_0;
wire                            rd_burst_data_valid_0;
wire[MEM_DATA_BITS - 1 : 0]     rd_burst_data_0;
wire                            rd_burst_finish_0;

wire                            wr_burst_req_1;
wire[BUSRT_BITS - 1:0]          wr_burst_len_1;
wire[ADDR_BITS - 1:0]           wr_burst_addr_1;
wire                            wr_burst_data_req_1;
wire[MEM_DATA_BITS - 1 : 0]     wr_burst_data_1;
wire                            wr_burst_finish_1;

wire                            rd_burst_req_1;
wire[BUSRT_BITS - 1:0]          rd_burst_len_1;
wire[ADDR_BITS - 1:0]           rd_burst_addr_1;
wire                            rd_burst_data_valid_1;
wire[MEM_DATA_BITS - 1 : 0]     rd_burst_data_1;
wire                            rd_burst_finish_1;

wire core_clk;

frame_read_write #(
	.MEM_DATA_BITS              (256                      ),
	.READ_DATA_BITS             (16                       ),
	.WRITE_DATA_BITS            (16                       ),
	.ADDR_BITS                  (25                       ),
	.BUSRT_BITS                 (10                       ),
	.BURST_SIZE                 (16                       ) //?
) frame_read_write_inst0(
	.rst                        (~ddr_init_done        ),
	.mem_clk                    (core_clk              ),
	.rd_burst_req               (rd_burst_req_0        ),
	.rd_burst_len               (rd_burst_len_0        ),
	.rd_burst_addr              (rd_burst_addr_0       ),
	.rd_burst_data_valid        (rd_burst_data_valid_0 ),
	.rd_burst_data              (rd_burst_data_0       ),
	.rd_burst_finish            (rd_burst_finish_0     ),
	.read_clk                   (pclk                  ),
	.read_req                   (read_req_0            ),
	.read_req_ack               (read_req_ack_0        ),
	.read_finish                (                      ),
	.read_addr_0                (25'd0                 ), //The first frame address is 0
	.read_addr_1                (25'd2073600           ), //The second frame address is 24'd2073600 ,large enough address space for one frame of video
	.read_addr_2                (25'd4147200           ),
	.read_addr_3                (25'd6220800           ),
	.read_addr_index            (read_addr_index_0     ),
	.read_len                   (25'd129600            ),//frame size 
	.read_en                    (read_en_0             ),
	.read_data                  (read_data_0           ),

	.wr_burst_req               (wr_burst_req_0        ),
	.wr_burst_len               (wr_burst_len_0        ),
	.wr_burst_addr              (wr_burst_addr_0       ),
	.wr_burst_data_req          (wr_burst_data_req_0   ),
	.wr_burst_data              (wr_burst_data_0       ),
	.wr_burst_finish            (wr_burst_finish_0     ),
	.write_clk                  (camera_clk_0          ),
	.write_req                  (write_req_0           ),
	.write_req_ack              (write_req_ack_0       ),
	.write_finish               (                      ),
	.write_addr_0               (25'd0                 ),
	.write_addr_1               (25'd2073600           ),
	.write_addr_2               (25'd4147200           ),
	.write_addr_3               (25'd6220800           ),
	.write_addr_index           (write_addr_index_0    ),
	.write_len                  (25'd129600            ), //frame size  
	.write_en                   (write_en_0            ),
	.write_data                 (write_data_0          )
);
frame_read_write #(
	.MEM_DATA_BITS              (256                   ),
	.READ_DATA_BITS             (16                    ),
	.WRITE_DATA_BITS            (16                    ),
	.ADDR_BITS                  (25                    ),
	.BUSRT_BITS                 (10                    ),
	.BURST_SIZE                 (16                    ) //?
) frame_read_write_inst1(
	.rst                        (~ddr_init_done        ),
	.mem_clk                    (core_clk              ),
	.rd_burst_req               (rd_burst_req_1        ),
	.rd_burst_len               (rd_burst_len_1        ),
	.rd_burst_addr              (rd_burst_addr_1       ),
	.rd_burst_data_valid        (rd_burst_data_valid_1 ),
	.rd_burst_data              (rd_burst_data_1       ),
	.rd_burst_finish            (rd_burst_finish_1     ),
	.read_clk                   (pclk                  ),
	.read_req                   (read_req_1            ),
	.read_req_ack               (read_req_ack_1        ),
	.read_finish                (                      ),
	.read_addr_0                (25'd8294400           ), //The first frame address is 0
	.read_addr_1                (25'd10368000          ), //The second frame address is 24'd2073600 ,large enough address space for one frame of video
	.read_addr_2                (25'd12441600          ),
	.read_addr_3                (25'd14515200          ),
	.read_addr_index            (read_addr_index_1     ),
	.read_len                   (25'd129600            ),//frame size 
	.read_en                    (read_en_1             ),
	.read_data                  (read_data_1           ),

	.wr_burst_req               (wr_burst_req_1        ),
	.wr_burst_len               (wr_burst_len_1        ),
	.wr_burst_addr              (wr_burst_addr_1       ),
	.wr_burst_data_req          (wr_burst_data_req_1   ),
	.wr_burst_data              (wr_burst_data_1       ),
	.wr_burst_finish            (wr_burst_finish_1     ),
	.write_clk                  (camera_clk_1          ),
	.write_req                  (write_req_1           ),
	.write_req_ack              (write_req_ack_1       ),
	.write_finish               (                      ),
	.write_addr_0               (25'd8294400           ),
	.write_addr_1               (25'd10368000          ),
	.write_addr_2               (25'd12441600          ),
	.write_addr_3               (25'd14515200          ),
	.write_addr_index           (write_addr_index_1    ),
	.write_len                  (25'd129600            ), //frame size  
	.write_en                   (write_en_1            ),
	.write_data                 (write_data_1          )
);    

/************************************************************
通道仲裁模块
************************************************************/ 
//读仲裁
mem_read_arbi #(
	.MEM_DATA_BITS               (MEM_DATA_BITS),
	.ADDR_BITS                   (ADDR_BITS    ),
	.BUSRT_BITS                  (BUSRT_BITS   )
)mem_read_arbi_inst(
	.rst_n                        (ddr_init_done),
	.mem_clk                      (core_clk),
	.ch0_rd_burst_req             (rd_burst_req_0),
	.ch0_rd_burst_len             (rd_burst_len_0),
	.ch0_rd_burst_addr            (rd_burst_addr_0),
	.ch0_rd_burst_data_valid      (rd_burst_data_valid_0),
	.ch0_rd_burst_data            (rd_burst_data_0),
	.ch0_rd_burst_finish          (rd_burst_finish_0),
	
	.ch1_rd_burst_req             (rd_burst_req_1),
	.ch1_rd_burst_len             (rd_burst_len_1),
	.ch1_rd_burst_addr            (rd_burst_addr_1),
	.ch1_rd_burst_data_valid      (rd_burst_data_valid_1),
	.ch1_rd_burst_data            (rd_burst_data_1),
	.ch1_rd_burst_finish          (rd_burst_finish_1),
	
	.rd_burst_req                 (rd_burst_req),
	.rd_burst_len                 (rd_burst_len),
	.rd_burst_addr                (rd_burst_addr),
	.rd_burst_data_valid          (rd_burst_data_valid),
	.rd_burst_data                (rd_burst_data),
	.rd_burst_finish              (rd_burst_finish)	
);
//写仲裁
mem_write_arbi #(
	.MEM_DATA_BITS               (MEM_DATA_BITS),
	.ADDR_BITS                   (ADDR_BITS    ),
	.BUSRT_BITS                  (BUSRT_BITS   )
)mem_write_arbi_inst(
	.rst_n                       (ddr_init_done),
	.mem_clk                     (core_clk),
	
	.ch0_wr_burst_req            (wr_burst_req_0),
	.ch0_wr_burst_len            (wr_burst_len_0),
	.ch0_wr_burst_addr           (wr_burst_addr_0),
	.ch0_wr_burst_data_req       (wr_burst_data_req_0),
	.ch0_wr_burst_data           (wr_burst_data_0),
	.ch0_wr_burst_finish         (wr_burst_finish_0),
	
	.ch1_wr_burst_req            (wr_burst_req_1),
	.ch1_wr_burst_len            (wr_burst_len_1),
	.ch1_wr_burst_addr           (wr_burst_addr_1),
	.ch1_wr_burst_data_req       (wr_burst_data_req_1),
	.ch1_wr_burst_data           (wr_burst_data_1),
	.ch1_wr_burst_finish         (wr_burst_finish_1),

	.wr_burst_req(wr_burst_req),
	.wr_burst_len(wr_burst_len),
	.wr_burst_addr(wr_burst_addr),
	.wr_burst_data_req(wr_burst_data_req),
	.wr_burst_data(wr_burst_data),
	.wr_burst_finish(wr_burst_finish)	
);


wire [CTRL_ADDR_WIDTH-1:0]  axi_awaddr      ;
wire [3:0]                  axi_awid        ;
wire [3:0]                  axi_awlen       ;
wire                        axi_awready     ;
wire                        axi_awvalid     ;

wire [MEM_DQ_WIDTH*8-1:0]   axi_wdata       ;
wire [MEM_DQ_WIDTH*8/8-1:0] axi_wstrb       ;
wire                        axi_wready      ;

wire [CTRL_ADDR_WIDTH-1:0]  axi_araddr      ;
wire [3:0]                  axi_arid        ;
wire [3:0]                  axi_arlen       ;
wire                        axi_arready     ;
wire                        axi_arvalid     ;

wire [MEM_DQ_WIDTH*8-1:0]   axi_rdata       ;
wire                        axi_rid         ;
wire [3:0]                  axi_rlast       ;
wire                        axi_rvalid      ;

wire axi_bvalid;
assign axi_bvalid =1'b1; 
aq_axi_master_256	u_aq_axi_master (
	  .ARESETN                     (ddr_init_done         ),
	  .ACLK                        (core_clk              ),
	  .M_AXI_AWID                  (axi_awid          ),
	  .M_AXI_AWADDR                (axi_awaddr        ),
	  .M_AXI_AWLEN                 (axi_awlen         ),
	  .M_AXI_AWSIZE                (),
	  .M_AXI_AWBURST               (),
	  .M_AXI_AWLOCK                (),
	  .M_AXI_AWCACHE               (),
	  .M_AXI_AWPROT                (),
	  .M_AXI_AWQOS                 (),
	  .M_AXI_AWUSER                (),
	  .M_AXI_AWVALID               (axi_awvalid       ),
	  .M_AXI_AWREADY               (axi_awready       ),

	  .M_AXI_WDATA                 (axi_wdata         ),
	  .M_AXI_WSTRB                 (axi_wstrb         ),
	  .M_AXI_WLAST                 (),
	  .M_AXI_WUSER                 (),
	  .M_AXI_WVALID                (),
	  .M_AXI_WREADY                (axi_wready        ),

	  .M_AXI_BID                   (),
	  .M_AXI_BRESP                 (),
	  .M_AXI_BUSER                 (),
      .M_AXI_BVALID                (axi_bvalid        ),
	  .M_AXI_BREADY                (),

	  .M_AXI_ARID                  (axi_arid          ),
	  .M_AXI_ARADDR                (axi_araddr        ),
	  .M_AXI_ARLEN                 (axi_arlen         ),
	  .M_AXI_ARSIZE                (),
	  .M_AXI_ARBURST               (),
	  .M_AXI_ARLOCK                (),
	  .M_AXI_ARCACHE               (),
	  .M_AXI_ARPROT                (),
	  .M_AXI_ARQOS                 (),
	  .M_AXI_ARUSER                (),
	  .M_AXI_ARVALID               (axi_arvalid       ),
	  .M_AXI_ARREADY               (axi_arready       ),

	  .M_AXI_RID                   (axi_rid           ),
	  .M_AXI_RDATA                 (axi_rdata         ),
	  .M_AXI_RRESP                 (),
	  .M_AXI_RLAST                 (axi_rlast         ),
	  .M_AXI_RUSER                 (),
	  .M_AXI_RVALID                (axi_rvalid        ),
	  .M_AXI_RREADY                (),

	  .MASTER_RST                  (1'b0                  ),
	  .WR_START                    (wr_burst_req          ),
	  .WR_ADRS                     ({wr_burst_addr,5'd0}  ),
	  .WR_LEN                      ({wr_burst_len, 5'd0}  ),
	  .WR_READY                    (                      ),
	  .WR_FIFO_RE                  (wr_burst_data_req     ),
	  .WR_FIFO_EMPTY               (1'b0                  ),
	  .WR_FIFO_AEMPTY              (1'b0                  ),
	  .WR_FIFO_DATA                (wr_burst_data         ),
	  .WR_DONE                     (wr_burst_finish       ),
	  .RD_START                    (rd_burst_req          ),
	  .RD_ADRS                     ({rd_burst_addr,5'd0}  ),
	  .RD_LEN                      ({rd_burst_len, 5'd0}   ),
	  .RD_READY                    (                      ),
	  .RD_FIFO_WE                  (rd_burst_data_valid   ),
	  .RD_FIFO_FULL                (1'b0                  ),
	  .RD_FIFO_AFULL               (1'b0                  ),
	  .RD_FIFO_DATA                (rd_burst_data         ),
	  .RD_DONE                     (rd_burst_finish       ),
	  .DEBUG                       (                      )
);
//=====================================================================================
//ddr
//=====================================================================================
wire clk_125Mhz ;

GTP_INBUFGDS #(
    .IOSTANDARD("DEFAULT"),
    .TERM_DIFF("ON")
) u_gtp (
    .O(clk_125Mhz), // OUTPUT  
    .I(clk_p), // INPUT  
    .IB(clk_n) // INPUT  
);

//ddr    
DDR_200H DDR_200H_inst (
    .ref_clk                   (clk_125Mhz            ),
    .resetn                    (rst_n               ),// input
    .ddr_init_done             (ddr_init_done      ),// outpu
    .pll_lock                  (pll_lock           ),// outpu
    .core_clk                  (core_clk),                                  // outpu
    .phy_pll_lock              (phy_pll_lock),                          // output
    .gpll_lock                 (gpll_lock),                                // output
    .rst_gpll_lock             (rst_gpll_lock),                        // output
    .ddrphy_cpd_lock           (ddrphy_cpd_lock),                    // output
    //.ddr_init_done             (ddr_init_done),                        // outpu
    .axi_awaddr                (axi_awaddr         ),// input [27:0]
    .axi_awuser_ap             (1'b0               ),// input
    .axi_awuser_id             (axi_awid           ),// input [3:0]
    .axi_awlen                 (axi_awlen          ),// input [3:0]
    .axi_awready               (axi_awready        ),// output
    .axi_awvalid               (axi_awvalid        ),// input

    .axi_wdata                 (axi_wdata          ),
    .axi_wstrb                 (axi_wstrb          ),// input [31:0]
    .axi_wready                (axi_wready         ),// output
    .axi_wusero_id             (                   ),// output [3:0]
    .axi_wusero_last           (),// output

    .axi_araddr                (axi_araddr         ),// input [27:0]
    .axi_aruser_ap             (1'b0               ),// input
    .axi_aruser_id             (axi_arid           ),// input [3:0]
    .axi_arlen                 (axi_arlen          ),// input [3:0]
    .axi_arready               (axi_arready        ),// output
    .axi_arvalid               (axi_arvalid        ),// input

    .axi_rdata                 (axi_rdata          ),// output [255:0]
    .axi_rid                   (axi_rid            ),// output [3:0]
    .axi_rlast                 (axi_rlast          ),// output
    .axi_rvalid                (axi_rvalid         ),// outpu

    .apb_clk                   (1'b0               ),// input
    .apb_rst_n                 (1'b1               ),// input
    .apb_sel                   (1'b0               ),// input
    .apb_enable                (1'b0               ),// input
    .apb_addr                  (8'b0               ),// input [7:0]
    .apb_write                 (1'b0               ),// input
    .apb_ready                 (                   ), // output
    .apb_wdata                 (16'b0              ),// input [15:0]
    .apb_rdata                 (                   ),// output [15:0]
//          .apb_int                   (                   ),// outpu
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

    .dbg_gate_start(1'b0),                      // input
    .dbg_cpd_start(1'b0),                        // input
    .dbg_ddrphy_rst_n(1'b1),                  // input
    .dbg_gpll_scan_rst(1'b0),                // input
    .samp_position_dyn_adj(1'b0),        // input
    .init_samp_position_even(32'd0),    // input [31:0]
    .init_samp_position_odd(32'd0),      // input [31:0]
    .wrcal_position_dyn_adj(1'b0),      // input
    .init_wrcal_position(32'd0),            // input [31:0]
    .force_read_clk_ctrl(1'b0),            // input
    .init_slip_step(16'd0),                      // input [15:0]
    .init_read_clk_ctrl(12'd0),              // input [11:0]
    .debug_calib_ctrl(),                  // output [33:0]
    .dbg_slice_status(),                  // output [67:0]
    .dbg_slice_state(),                    // output [87:0]
    .debug_data(),                              // output [275:0]
    .dbg_dll_upd_state(),                // output [1:0]
    .debug_gpll_dps_phase(),          // output [8:0]
    .dbg_rst_dps_state(),                // output [2:0]
    .dbg_tran_err_rst_cnt(),          // output [5:0]
    .dbg_ddrphy_init_fail(),          // output
    .debug_cpd_offset_adj(1'b0),          // input
    .debug_cpd_offset_dir(1'b0),          // input
    .debug_cpd_offset(10'd0),                  // input [9:0]
    .debug_dps_cnt_dir0(),              // output [9:0]
    .debug_dps_cnt_dir1(),              // output [9:0]
    .ck_dly_en(1'b0),                                // input
    .init_ck_dly_step(8'h0),                  // input [7:0]
    .ck_dly_set_bin(),                      // output [7:0]
    .align_error(),                            // output
    .debug_rst_state(),                    // output [3:0]
    .debug_cpd_state()                     // output [3:0]
);

//=====================================================================================
//心跳信号
//=====================================================================================
reg [26:0] cnt;
always@(posedge core_clk) begin
    if (!ddr_init_done)
        cnt <= 27'd0;
    else if ( cnt >= TH_1S )
        cnt <= 27'd0;
    else
        cnt <= cnt + 27'd1;
end

always @(posedge core_clk) begin
    if (!ddr_init_done)
        heart_beat_led <= 1'd1;
    else if ( cnt >= TH_1S )
        heart_beat_led <= ~heart_beat_led;
end

endmodule
