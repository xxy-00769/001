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

module m36_rgmii_probe(
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
    

    

 wire rx_io, rx_half_raw, rx_half;
 GTP_CLKBUFG gb(.CLKIN(rgmii_rxc),.CLKOUT(rgmii_clk));
 GTP_IOCLKBUF #(.GATE_EN("FALSE")) ib(.CLKIN(rgmii_rxc),.DI(1'b1),.CLKOUT(rx_io));
 GTP_IOCLKDIV #(.DIV_FACTOR("2")) div(.CLKIN(rx_io),.RST_N(!rst),.CLKDIVOUT(rx_half_raw));
 GTP_CLKBUFG hb(.CLKIN(rx_half_raw),.CLKOUT(rx_half));
 wire [4:0] pins={rgmii_rx_ctl,rgmii_rxd};
 wire [39:0] samples; wire [4:0] delayed;
 genvar j;
 generate for(j=0;j<5;j=j+1) begin: rx
 assign delayed[j]=pins[j];
 GTP_ISERDES #(.ISERDES_MODE("IDES4"),.GRS_EN("TRUE"),.LRS_EN("TRUE")) id(
 .DO(samples[j*8+:8]),.DI(delayed[j]),.DESCLK(rx_io),.RCLK(rx_half),.ICLK(1'b0),
 .RADDR(3'd0),.WADDR(3'd0),.RST(rst));
 end endgenerate
 reg [7:0] acc;
 always @(posedge rx_half) acc<=samples[39:32]^samples[31:24]^samples[23:16]^samples[15:8]^samples[7:0];
 always @(posedge rgmii_clk) begin mac_rx_data<=acc;mac_rx_data_valid<=acc[7];mac_rx_error<=acc[6];end
 endmodule

