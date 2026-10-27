"""Prepare one E1-based integration from the published 3.5.2 source snapshot."""
from pathlib import Path
import re,hashlib,json
R=Path(__file__).resolve().parents[1]
P=R.parents[1]
E=P/'release/FPGA_GSV1_NET2_BASELINE_E1'
def edit(p,old,new):
    f=R/p;s=f.read_text(encoding='utf-8-sig');assert old in s,(p,old[:80]);f.write_text(s.replace(old,new),encoding='utf-8')
# The E1 IO implementation is unchanged except for its module name.
io=(E/'source/rtl/rgmii_interface.v').read_text(encoding='utf-8-sig')
(R/'rtl/network/m364_e1_rgmii.v').write_text(io.replace('module rgmii_interface(', 'module m364_e1_rgmii('),encoding='utf-8')
edit('rtl/board/fpga_gsv1_top.v', '''    pll_mpi7001 u_pll (
        .clkin1   (  sys_clk    ),//50MHz
        .clkout0  (             ),//old pixel output unused; cfg/camera clocks retained
        .clkout1  (  cfg_clk    ),//10MHz
        .clkout2  (  clk_25M    ),//25M
        .pll_lock (  cfg_locked )
    );''', '''    m364_ref_dividers u_ref_div(.clkin1(sys_clk),.cfg_clk(cfg_clk),
        .camera_clk(clk_25M),.ready(cfg_locked));''')
edit('rtl/board/fpga_gsv1_top.v','.ENABLE_VIDEO(0),.PHY_INTERNAL_DELAY(1)', '.ENABLE_VIDEO(0),.PHY_INTERNAL_DELAY(1),.E1_PHY(1)')
edit('rtl/network/m3_network.v','PHY_INTERNAL_DELAY=0,','PHY_INTERNAL_DELAY=0,E1_PHY=0,')
edit('rtl/network/m3_network.v','end else begin: managed_phy\n assign phase=rgmii_rxc;', '''end else if(E1_PHY) begin: e1_phy
 // Own RXC, same PLL parameters and IO structure as accepted E1.
 m3_eth_pll pll(.clkin1(rgmii_rxc),.clkout0(phase),.clkout1(phase_d),.pll_lock(pll_lock));
 wire manager_ready;
 m36_phy2 #(.STRAP_ONLY(1)) manager(.clk(sys_clk),.rst_n(phy_reset_n),.phy_rstn(phy_rstn),.rx_clock(nc),
 .mdc(phy_mdc),.mdio(phy_mdio),.ready(manager_ready),.configured(),.address(),.status(),.diagnostics(phy_diagnostics));
 assign phy_ready=manager_ready && pll_lock;
 assign diagnostic_tx=1'b1;
 end else begin: managed_phy
 assign phase=rgmii_rxc;''')
edit('rtl/network/m3_network.v',"if(!reset_count[22]) reset_count<=reset_count+1'b1;\n assign phy_rstn=reset_count[22];", "if(!phy_rstn) reset_count<=reset_count+1'b1;\n assign phy_rstn=E1_PHY ? reset_count>=1000000:reset_count[22];")
edit('rtl/network/m3_network.v','end else begin: port2_io\n m36_rgmii_interface', '''end else if(E1_PHY) begin: e1_io
 // MAC already registers txd/txv. E1 adds this GMII boundary register.
 reg [7:0] tx_data;reg tx_valid;
 always @(posedge nc) if(!nr[2]) begin tx_data<=0;tx_valid<=0;end
 else begin tx_data<=txd;tx_valid<=txv;end
 m364_e1_rgmii phy(.rst(!nr[2]),.rgmii_rxc_phase_d(phase_d),.rgmii_clk(nc),.rgmii_clk_90p(phase_d),
 .mac_tx_data_valid(tx_valid),.mac_tx_data(tx_data),.mac_rx_error(rxe),.mac_rx_data_valid(rxv),.mac_rx_data(rxd),
 .rgmii_rxc(phase),.rgmii_rx_ctl(rgmii_rx_ctl),.rgmii_rxd(rgmii_rxd),
 .rgmii_txc(rgmii_txc),.rgmii_tx_ctl(rgmii_tx_ctl),.rgmii_txd(rgmii_txd));
 end else begin: port2_io
 m36_rgmii_interface''')
edit('rtl/network/m3_network.v','if(PHY_INTERNAL_DELAY) begin: passive_diagnostics','if(PHY_INTERNAL_DELAY && !E1_PHY) begin: passive_diagnostics')
edit('rtl/network/m36_phy2.v','parameter MDIO_HALF=25)', 'parameter MDIO_HALF=25, STRAP_ONLY=0)')
edit('rtl/network/m36_phy2.v',"if(rd[13:11]!=3'b111) delay_fail", "if(!STRAP_ONLY && rd[13:11]!=3'b111) delay_fail")
edit('rtl/network/m36_phy2.v',"5:begin regaddr<=28;read_op<=0;wd<=delay_value|16'h3800;end", "5:begin regaddr<=28;read_op<=STRAP_ONLY;wd<=delay_value|16'h3800;end")
edit('rtl/network/m36_phy2.v',"6:if(rd[13:11]==3'b111)", "6:if(STRAP_ONLY || rd[13:11]==3'b111)")
# No TX/RX delay bits are written in STRAP_ONLY mode. Page writes only select
# readback banks. Successful E1 strap RX relationship is migrated as a whole.
f=R/'constraints/mes50hp.fdc';s=f.read_text(encoding='utf-8-sig')
s=s.replace('[get_nets {u_pll.clkout1}]','[get_nets {u_ref_div.cfg_clk}]').replace('-multiply_by {1} -divide_by {5}','-edges {1 5 11}')
s=s.replace('[get_nets {u_pll.clkout2}]','[get_nets {u_ref_div.camera_clk}]')
start=s.index('# RTL8211E table65:')
end=s.index('# Passive diagnostic UART:',start)
s=s[:start]+'''# E1 strap-mode IDDR/PLL sampling replaces the old RGMII-ID/IDES4 path.
# Therefore the old delayed-RXC [1.2,2.8] input model and pad IN_DELAY=15
# are inapplicable. Strap delay/PCB PVT are not guaranteed by vendor data:
# RX external eye remains unqualified, exactly as declared for accepted E1.
\n'''+s[end:]
start=s.index('# Port2 TX capture model:')
s=s[:start]+'''# E1 TX: forwarded phase1 is +1ns relative to data phase0. Strap PHY
# TX delay was NOT measured; no old +2ns internal-delay model is combined
# with this clock. Known external timing requirements are documented in
# reports/e1_integration_analysis.md; no board-level signoff is claimed.
'''
s=s.replace('# Port2 has its own clock. PHY internal RX/TX delay configured by MDIO.', '# Port2 has its own E1 PLL. PHY delay straps retained; MDIO only reads them.')
f.write_text(s,encoding='utf-8')
edit('flow.tcl','add_design "rtl/network/m3_network.v"','add_design "rtl/network/m364_e1_rgmii.v"\nadd_design "rtl/board/m364_ref_dividers.v"\nadd_design "rtl/network/m3_network.v"')
# Confirm E1 PLL parameters match the production network PLL exactly.
a=(E/'source/rtl/pll_phase.v').read_text().replace('module pll_phase','module m3_eth_pll')
b=(R/'rtl/network/m3_eth_pll.v').read_text()
assert a.replace('\r','')==b.replace('\r',''),'PLL must match accepted E1'
print('E1 PLL byte-equivalent after module rename; independent RXC; strap-only monitor')
