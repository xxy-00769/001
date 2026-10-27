module oled_test(
   input          sys_clk   /* synthesis PAP_MARK_DEBUG="true" */,//50MHz
   input          rst_n      ,
   output         rs       ,//地址数据切换信号
   output         reset    ,
   output         scl      ,
   output         sda      /* synthesis PAP_MARK_DEBUG="true" */
   );
wire cs ;
 
parameter time_delay1 = 32'd499_999 ;
parameter time_delay2 = 32'd499_999   ;

///////////////////////////////////////////////////////////////////////
wire clk_5 ;                    //5MHz
wire clk ;
wire rst_n ;
reg key_reg  ;
reg rst_reg = 1'b0;
reg [7:0]cnt_clk ;

wire delay_end_0 /* synthesis PAP_MARK_DEBUG="true" */;
wire delay_end_1 /* synthesis PAP_MARK_DEBUG="true" */;
wire delay_start_0 /* synthesis PAP_MARK_DEBUG="true" */;
wire delay_start_1 /* synthesis PAP_MARK_DEBUG="true" */;
wire sda_start_init /* synthesis PAP_MARK_DEBUG="true" */;
wire [8:0]data_out_init /* synthesis PAP_MARK_DEBUG="true" */ ;
wire sda_end_init /* synthesis PAP_MARK_DEBUG="true" */;
wire initial_end /* synthesis PAP_MARK_DEBUG="true" */;

wire sda_end     /* synthesis PAP_MARK_DEBUG="true" */;
wire sda_start   /* synthesis PAP_MARK_DEBUG="true" */;
wire [8:0]sda_data   /* synthesis PAP_MARK_DEBUG="true" */;
wire start     /* synthesis PAP_MARK_DEBUG="true" */;
wire send_end  /* synthesis PAP_MARK_DEBUG="true" */;
wire [8:0]data_send /* synthesis PAP_MARK_DEBUG="true" */;

////////////////////////CLK_GEN//////////////////////////////////////////

PLL u_pll (
  .clkin1(sys_clk),        // input
  .pll_lock(),    // output
  .clkout0(clk)       // output
);

///////////////////////delay/////////////////////////////////////////////

time_delay time_delay_first(
   .clk              (clk            )   ,       //5MHz                             
   .rst_n            (rst_n          )   ,                                      
   .delay_start      (delay_start_0  )   ,                                            
   .delay_parameter  (time_delay1     )   ,                                                
   .delay_end        (delay_end_0    )                                    
);

time_delay time_delay_second(
   .clk              (clk            )   ,       //5MHz                             
   .rst_n            (rst_n          )   ,                                      
   .delay_start      (delay_start_1  )   ,                                            
   .delay_parameter  (time_delay2     )   ,                                                
   .delay_end        (delay_end_1    )                                    
);

/////////////////////////////////////////////////////////////////////////

command_data_send command_data_send(
   .clk              (clk           )   ,
   .rst_n            (rst_n         )   ,
   .start            (start         )   ,//input
   .rs_ctrl          (data_send[8]  )   ,//input 
   .data_in          (data_send[7:0])   ,//input 
   .send_end         (send_end      )   ,//input 
   .cs               (cs            )   ,//output
   .rs               (rs            )   ,//output
   .scl              (scl           )   ,//output
   .sda              (sda           )    //output
);

///////////////////////////初始化////////////////////////////////////////

display_initial display_initial(
    .clk            (clk          )     ,
    .rst_n          (rst_n        )     ,
    .delay_end_0    (delay_end_0  )     ,
    .delay_end_1    (delay_end_1  )     ,
    .sda_end        (sda_end_init )     ,
    .delay_start_0  (delay_start_0)     ,
    .delay_start_1  (delay_start_1)     ,
    .sda_start      (sda_start_init)     ,
    .data_out       (data_out_init )     ,//[8:0]
    .reset          (reset        )     ,
    .initial_end    (initial_end  )
); 

///////////////////////////图像信息/////////////////////////////////////

image_send image_send(
    .clk                (clk        ) ,
    .rst_n              (rst_n      ) ,
    .initial_end        (initial_end) ,
    .sda_end            (sda_end    ) ,
    .sda_start          (sda_start  ) ,
    .sda_data           (sda_data   )                       //[8:0]
);

assign start      = (initial_end)?  sda_start  :  sda_start_init ;
assign sda_end   = (initial_end)? send_end  :  1'b0   ;
assign sda_end_init   = (initial_end)? 1'b0  :  send_end   ;
assign data_send  = (initial_end)? sda_data : data_out_init  ;


endmodule