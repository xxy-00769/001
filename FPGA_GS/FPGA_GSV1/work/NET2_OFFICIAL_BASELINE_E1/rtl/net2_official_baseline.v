`timescale 1ns/1ps
// E1 controlled physical baseline. Official ARP/MAC and RGMII/PLL modules;
// no DDR, video, UDP application, PHY MDIO writes, or new TX architecture.
module net2_official_baseline #(
    parameter RESET_CYCLES=1000000,
    parameter ARP_PERIOD=12500000
)(input clk_50m, output reg phy_rstn=0,
  input rgmii_rxc,rgmii_rx_ctl,input [3:0] rgmii_rxd,
  output rgmii_txc,rgmii_tx_ctl,output [3:0] rgmii_txd);
    wire ref200,ref125,ref_lock;
    ref_clock reference_clock(.clkin1(clk_50m),.clkout0(ref200),
        .clkout1(ref125),.pll_lock(ref_lock));
    reg [19:0] power_count=0;
    always @(posedge clk_50m or negedge ref_lock)
        if(!ref_lock) begin power_count<=0;phy_rstn<=0;end
        else if(!phy_rstn) begin
            if(power_count==RESET_CYCLES-1) phy_rstn<=1;
            else power_count<=power_count+1'b1;
        end
    wire phase0,phase1,phase_lock,mac_clk;
    // Byte-for-byte original IP: nominal RXC-relative phases 4ns and 5ns.
    pll_phase rx_phase_clock(.clkin1(rgmii_rxc),.clkout0(phase0),
        .clkout1(phase1),.pll_lock(phase_lock));
    wire reset_async= !ref_lock || !phy_rstn || !phase_lock;
    reg [2:0] release_sync=0;
    always @(posedge mac_clk or posedge reset_async)
        if(reset_async) release_sync<=0;
        else release_sync<={release_sync[1:0],1'b1};
    wire rstn=release_sync[2];
    wire [7:0] rx_data;wire rx_valid,rx_error;
    wire [7:0] core_tx_data;wire core_tx_valid;
    reg [7:0] tx_data,rx_data_d;reg tx_valid,rx_valid_d;
    // Same GMII register stages as the original eth_udp_test wrapper.
    always @(posedge mac_clk) begin
        if(!rstn) begin tx_data<=0;tx_valid<=0;rx_data_d<=0;rx_valid_d<=0;end
        else begin
            tx_data<=core_tx_data;tx_valid<=core_tx_valid;
            rx_data_d<=rx_data;rx_valid_d<=rx_valid;
        end
    end
    rgmii_interface physical(.rst(!rstn),.rgmii_clk(mac_clk),
        .rgmii_clk_90p(1'b0),.rgmii_rxc_phase_d(phase1),
        .mac_tx_data_valid(tx_valid),.mac_tx_data(tx_data),
        .mac_rx_data_valid(rx_valid),.mac_rx_data(rx_data),.mac_rx_error(rx_error),
        .rgmii_rxc(phase0),.rgmii_rx_ctl(rgmii_rx_ctl),.rgmii_rxd(rgmii_rxd),
        .rgmii_txc(rgmii_txc),.rgmii_tx_ctl(rgmii_tx_ctl),.rgmii_txd(rgmii_txd));
    reg [23:0] probe_count;reg arp_probe;
    always @(posedge mac_clk) begin
        if(!rstn) begin probe_count<=0;arp_probe<=0;end
        else begin
            arp_probe<=0;
            if(probe_count==ARP_PERIOD-1) begin probe_count<=0;arp_probe<=1;end
            else probe_count<=probe_count+1'b1;
        end
    end
    wire ip_request;
    arp_mac_top #(.LOCAL_MAC_ADDR(48'h020047535632),
        .LOCAL_IP_ADDR(32'hc0a83c02)) arp_mac(
        .clk(mac_clk),.rstn(rstn),.checksum_err(1'b0),
        .ip_tx_req(1'b0),.ip_tx_ready(1'b0),.ip_tx_data(8'd0),.ip_tx_end(1'b0),
        .ip_tx_ack(),.mac_data_req(),.mac_send_end(),
        .ip_rx_end(ip_request),.ip_rx_req(ip_request),
        .mac_rx_dataout(),.mac_rx_dest_mac_addr(),.mac_rx_sour_mac_addr(),
        .arp_request_req(arp_probe),.arp_found(),.mac_not_exist(),.arp_dest_mac_addr(),
        .dest_ip_addr(32'hc0a83c01),.mac_rec_error(),
        .mac_tx_data(core_tx_data),.mac_data_valid(core_tx_valid),
        .rx_en(rx_valid_d),.mac_rx_datain(rx_data_d));
endmodule
