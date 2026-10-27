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
    

    

    // Independent PHY2 RX: pin-local 4:1 sampling and /2 word clock.
    // No sixth PLL; no port1 clock is used. Each word holds two GMII bytes.
    wire rx_ioclk,rx_half_raw,rx_half;
    GTP_CLKBUFG GTP_CLKBUFG_RXSHFT(.CLKIN(rgmii_rxc),.CLKOUT(rgmii_clk));
    GTP_IOCLKBUF #(.GATE_EN("FALSE")) rx_iobuf(.CLKIN(rgmii_rxc),.DI(1'b1),.CLKOUT(rx_ioclk));
    GTP_IOCLKDIV #(.DIV_FACTOR("2")) rx_div(.CLKIN(rx_ioclk),.RST_N(!rst),.CLKDIVOUT(rx_half_raw));
    GTP_CLKBUFG half_buf(.CLKIN(rx_half_raw),.CLKOUT(rx_half));
    wire [4:0] pins={rgmii_rx_ctl,rgmii_rxd}; wire [4:0] delayed;
    wire [39:0] samples;
    genvar j;
    generate for(j=0;j<5;j=j+1) begin: rx
      // Physical PAP_IO_IN_DELAY=15 is specified on PHY2 data/control pads.
      assign delayed[j]=pins[j];
      GTP_ISERDES #(.ISERDES_MODE("IDES4"),.GRS_EN("TRUE"),.LRS_EN("TRUE")) sample_input(
        .DO(samples[j*8+:8]),.DI(delayed[j]),.DESCLK(rx_ioclk),.RCLK(rx_half),
        .ICLK(1'b0),.RADDR(3'd0),.WADDR(3'd0),.RST(rst));
    end endgenerate
    // DO[5:4] is the earlier byte, DO[7:6] the following byte.
    wire [7:0] byte0={samples[29],samples[21],samples[13],samples[5],samples[28],samples[20],samples[12],samples[4]};
    wire [7:0] byte1={samples[31],samples[23],samples[15],samples[7],samples[30],samples[22],samples[14],samples[6]};
    wire [19:0] pair_data={samples[38]^samples[39],samples[38],byte1,samples[36]^samples[37],samples[36],byte0};
    reg [19:0] pairs[0:7];
    reg [2:0] wp,wg;
    always @(posedge rx_half or posedge rst) if(rst) begin wp<=0;wg<=0;end
    else begin pairs[wp]<=pair_data;wp<=wp+1'b1;wg<=((wp+3'd1)^((wp+3'd1)>>1));end
    reg [2:0] wg1,wg2,rp;reg streaming,second;
    wire [2:0] published={wg2[2],wg2[2]^wg2[1],wg2[2]^wg2[1]^wg2[0]};
    wire [2:0] available=published-rp;
    wire [9:0] next_byte=second ? pairs[rp][19:10]:pairs[rp][9:0];
    always @(posedge rgmii_clk or posedge rst) if(rst) begin
      wg1<=0;wg2<=0;rp<=0;streaming<=0;second<=0;
      mac_rx_data<=0;mac_rx_data_valid<=0;mac_rx_error<=0;
    end else begin
      wg1<=wg;wg2<=wg1;mac_rx_data_valid<=0;mac_rx_error<=0;
      if(!streaming) begin if(available>=3) streaming<=1;end
      else begin
        mac_rx_data<=next_byte[7:0];mac_rx_data_valid<=next_byte[8];mac_rx_error<=next_byte[9];
        second<=!second;if(second) rp<=rp+1'b1;
      end
    end
endmodule
