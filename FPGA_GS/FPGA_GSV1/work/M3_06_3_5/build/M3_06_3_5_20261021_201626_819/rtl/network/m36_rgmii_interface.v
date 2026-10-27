`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Meyesemi
// Engineer: Nill
// 
// Create Date: 21/02/23 11:03:00
// Design Name: 
// Module Name: rgmii_interface
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
`define UD #1

module m36_rgmii_interface(
    input        rst,
    input        rst90,
    input        rgmii_rxc_phase_d,
    output       rgmii_clk/*synthesis PAP_MARK_DEBUG="1"*/,
    input        rgmii_clk_90p,
    
    input        mac_tx_data_valid/*synthesis PAP_MARK_DEBUG="1"*/,
    input [7:0]  mac_tx_data/*synthesis PAP_MARK_DEBUG="1"*/,
    
    output reg       mac_rx_error,
    output reg       mac_rx_data_valid/*synthesis PAP_MARK_DEBUG="1"*/,
    output reg [7:0] mac_rx_data/*synthesis PAP_MARK_DEBUG="1"*/,
    
    input        rgmii_rxc,
    input        rgmii_rx_ctl/*synthesis PAP_MARK_DEBUG="1"*/,
    input [3:0]  rgmii_rxd/*synthesis PAP_MARK_DEBUG="1"*/,
                 
    output       rgmii_txc,
    output       rgmii_tx_ctl/*synthesis PAP_MARK_DEBUG="1"*/,
    output [3:0] rgmii_txd/*synthesis PAP_MARK_DEBUG="1"*/ 
);

    //=============================================================
    //  RGMII TX 
    //=============================================================
    wire       rgmii_txc_obuf;
    wire       rgmii_txc_tbuf;
    wire       rgmii_tx_ctl_obuf;
    wire       rgmii_tx_ctl_tbuf;
    wire [3:0] rgmii_txd_obuf;
    wire [3:0] rgmii_txd_tbuf;

    generate 
        genvar i;
        for (i=0; i<4; i=i+1) 
        begin : rgmii_tx_data            
            GTP_OSERDES #(
                .OSERDES_MODE("ODDR"),  //"ODDR","OMDDR","OGSER4","OMSER4","OGSER7","OGSER8",OMSER8"
                .WL_EXTEND   ("FALSE"),     //"TRUE"; "FALSE"
                .GRS_EN      ("TRUE"),         //"TRUE"; "FALSE"
                .LRS_EN      ("TRUE"),          //"TRUE"; "FALSE"
                .TSDDR_INIT  (1'b0)         //1'b0;1'b1
            ) tx_data_oddr(
                .DO    (rgmii_txd_obuf[i]),
                .TQ    (rgmii_txd_tbuf[i]),
                .DI    ({6'd0,mac_tx_data[i+4],mac_tx_data[i]}),
                .TI    (4'd0),
                .RCLK  (rgmii_clk),
                .SERCLK(rgmii_clk),
                .OCLK  (1'd0),
                .RST   (1'b0)
            );                                         
            
            GTP_OUTBUFT  gtp_outbuft1(
                .I(rgmii_txd_obuf[i]),     
                .T(rgmii_txd_tbuf[i])  ,
                .O(rgmii_txd[i])        
            );
        end
    endgenerate

    GTP_OSERDES #(
        .OSERDES_MODE("ODDR"),  //"ODDR","OMDDR","OGSER4","OMSER4","OGSER7","OGSER8",OMSER8"
        .WL_EXTEND   ("FALSE"),     //"TRUE"; "FALSE"
        .GRS_EN      ("TRUE"),         //"TRUE"; "FALSE"
        .LRS_EN      ("TRUE"),          //"TRUE"; "FALSE"
        .TSDDR_INIT  (1'b0)         //1'b0;1'b1
    ) tx_ctl_oddr(
        .DO    (rgmii_tx_ctl_obuf),
        .TQ    (rgmii_tx_ctl_tbuf),
        .DI    ({6'd0,mac_tx_data_valid ^ 1'b0,mac_tx_data_valid}),
        .TI    (4'd0),
        .RCLK  (rgmii_clk),
        .SERCLK(rgmii_clk),
        .OCLK  (1'd0),
        .RST   (rst)
    );                                         
    
    GTP_OUTBUFT  gtp_outbuft1(
        .I(rgmii_tx_ctl_obuf),     
        .T(rgmii_tx_ctl_tbuf)  ,
        .O(rgmii_tx_ctl)        
    );

 
    GTP_OSERDES #(
     .OSERDES_MODE("ODDR"),  //"ODDR","OMDDR","OGSER4","OMSER4","OGSER7","OGSER8",OMSER8"
     .WL_EXTEND   ("FALSE"),     //"TRUE"; "FALSE"
     .GRS_EN      ("TRUE"),         //"TRUE"; "FALSE"
     .LRS_EN      ("TRUE"),          //"TRUE"; "FALSE"
     .TSDDR_INIT  (1'b0)         //1'b0;1'b1
    ) tx_clk_oddr(
       .DO    (rgmii_txc_obuf),
       .TQ    (rgmii_txc_tbuf),
       .DI    ({7'd0,1'b1}),
       .TI    (4'd0),
       .RCLK  (rgmii_rxc_phase_d),
       .SERCLK(rgmii_rxc_phase_d),
       .OCLK  (1'd0),
       .RST   (rst90)
    ); 
    GTP_OUTBUFT  gtp_outbuft6
    (
        
        .I(rgmii_txc_obuf),     
        .T(rgmii_txc_tbuf)  ,
        .O(rgmii_txc)        
    );                                                                                                            
    

    
    //=============================================================
    //  RGMII RX 
    //=============================================================
    wire        rgmii_rxc_ibuf;
    wire        rgmii_rxc_bufio;
    wire        rgmii_rx_ctl_ibuf;
    wire [3:0]  rgmii_rxd_ibuf;

    wire [7:0] delay_step_b ;
    wire [7:0] delay_step_gray ;
    
    assign delay_step_b = 8'hA0;   // 0~247 , 10ps/step

    wire lock;
/*
    GTP_DLL #(
        .GRS_EN("TRUE"),
        .FAST_LOCK("TRUE"),
        .DELAY_STEP_OFFSET(0) 
    ) clk_dll (
        .DELAY_STEP(delay_step_gray),// OUTPUT[7:0]  
        .LOCK      (lock),      // OUTPUT  
        .CLKIN     (rgmii_rxc),     // INPUT  
        .PWD       (1'b0),       // INPUT  
        .RST       (1'b0),       // INPUT  
        .UPDATE_N  (1'b1)   // INPUT  
    );
    GTP_IOCLKDELAY #(
        .DELAY_STEP_VALUE   (  'd127           ),
        .DELAY_STEP_SEL     (  "PARAMETER"     ),
        .SIM_DEVICE         (  "LOGOS"         ) 
    ) rgmii_clk_delay (
        .DELAY_STEP         (  delay_step_gray ),// INPUT[7:0]     
        .CLKOUT             (  rgmii_rxc_ibuf  ),// OUTPUT         
        .DELAY_OB           (                  ),// OUTPUT         
        .CLKIN              (  rgmii_rxc       ),// INPUT          
        .DIRECTION          (  1'b0            ),// INPUT          
        .LOAD               (  1'b0            ),// INPUT          
        .MOVE               (  1'b0            ) // INPUT          
    );
*/
    // Sample pins on the dedicated IO clock, not on the delayed global tree.
    // IMDDR's eight-word memory bridges the related IO/global clocks with
    // three-byte startup cushion. Address generation remains in the related
    // global clock domain; no fabric flip-flop is driven by an IO clock net.
    wire rx_ioclk;
    GTP_IOCLKBUF #(.GATE_EN("FALSE")) rx_iobuf(.CLKIN(rgmii_rxc),.DI(1'b1),.CLKOUT(rx_ioclk));
    reg [2:0] wp;
    // IO clock nets may drive IO cells only on PGL50H. The write
    // address counter uses the related global falling edge; STA checks
    // that address setup/hold at the IMDDR local falling edge is met.
    always @(negedge rgmii_clk or posedge rst) if(rst) wp<=0;else wp<=wp+1'b1;
    wire [2:0] wg=wp^(wp>>1);
    reg [2:0] wg1,wg2,rp;reg streaming,stream_d;
    wire [2:0] published={wg2[2],wg2[2]^wg2[1],wg2[2]^wg2[1]^wg2[0]};
    wire [2:0] available=published-rp;
    always @(posedge rgmii_clk or posedge rst) if(rst) begin
      wg1<=0;wg2<=0;rp<=0;streaming<=0;stream_d<=0;
    end else begin
      wg1<=wg;wg2<=wg1;stream_d<=streaming;
      if(!streaming) begin if(available>=3) streaming<=1;end
      else rp<=rp+1'b1;
    end
    GTP_CLKBUFG GTP_CLKBUFG_RXSHFT(
        .CLKIN     (rgmii_rxc),
        .CLKOUT    (rgmii_clk)
    );


    GTP_INBUF #(
        .IOSTANDARD("DEFAULT"),
        .TERM_DDR("ON")
    ) u_rgmii_rx_ctl_ibuf (
        .O(rgmii_rx_ctl_ibuf),// OUTPUT  
        .I(rgmii_rx_ctl) // INPUT  
    );
    
    wire  rgmii_rx_ctl_delay;
    parameter DELAY_STEP = 8'h0F;

    wire [5:0] rx_ctl_nc;
    wire       gmii_ctl;
    wire       rgmii_rx_valid_xor_error;
    GTP_ISERDES #(
        .ISERDES_MODE("IMDDR"),
        .GRS_EN("TRUE"),
        .LRS_EN("TRUE") 
    ) gmii_ctl_in (
        .DO   ({rgmii_rx_valid_xor_error,gmii_ctl,rx_ctl_nc[5: 0]}),    // OUTPUT[7:0]  
        .RADDR(rp), // INPUT[2:0]  
        .WADDR(wp), // INPUT[2:0]  
        .DESCLK(rgmii_clk),// INPUT  
        .DI(rgmii_rx_ctl_ibuf),    // INPUT  
        .ICLK(rx_ioclk),  // INPUT  
        .RCLK(rgmii_clk),  // INPUT  
        .RST(rst)    // INPUT  
    );

    wire [3:0] rgmii_rxd_delay;
    wire [23:0] rxd_nc;
    wire [7:0]  gmii_rxd;
    always @(posedge rgmii_clk)
    begin
        mac_rx_data <= gmii_rxd;
        mac_rx_data_valid <= stream_d && gmii_ctl;
        mac_rx_error <= stream_d && (gmii_ctl ^ rgmii_rx_valid_xor_error);
    end

    generate 
        genvar j;
        for (j=0; j<4; j=j+1)
        begin : rgmii_rx_data

            GTP_INBUF #(
                .IOSTANDARD("DEFAULT"),
                .TERM_DDR("ON")
            ) u_rgmii_rxd_ibuf (
                .O(rgmii_rxd_ibuf[j]),// OUTPUT  
                .I(rgmii_rxd[j]) // INPUT  
            );
            
            GTP_ISERDES #(
                .ISERDES_MODE("IMDDR"),
                .GRS_EN("TRUE"),
                .LRS_EN("TRUE") 
            ) gmii_rxd_in (
                .DO   ({gmii_rxd[j+4],gmii_rxd[j],rxd_nc[j*6 +: 6]}),    // OUTPUT[7:0]  
                .RADDR(rp), // INPUT[2:0]  
                .WADDR(wp), // INPUT[2:0]  
                .DESCLK(rgmii_clk),// INPUT  
                .DI(rgmii_rxd_ibuf[j]),    // INPUT  
                .ICLK(rx_ioclk),  // INPUT  
                .RCLK(rgmii_clk),  // INPUT  
                .RST(rst)    // INPUT  
            );

        end
    endgenerate
    
endmodule
