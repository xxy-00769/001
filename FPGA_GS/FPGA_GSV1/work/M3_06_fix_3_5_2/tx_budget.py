from pathlib import Path
p=Path('constraints/mes50hp.fdc');s=p.read_text();s=s[:s.index('# Port2 TX: constrain')]+'''# Port2 TX capture model: propagated forwarded clock, followed by the
# RTL8211E internal TXC delay (datasheet TXDLY = 2ns). Table65 receiver
# integrated-delay setup/hold = 1.0ns. 0.2ns uncertainty reserves link skew;
# PCB and PHY delay variation still require hardware validation.
create_generated_clock -name eth2_phy_tx_capture -source [get_ports {rgmii2_rxc}] -master_clock [get_clocks {eth2_rxc}] -edges {1 2 3} -edge_shift {2.000 2.000 2.000} [get_ports {rgmii2_txc}]
set_clock_uncertainty 0.200 [get_clocks {eth2_phy_tx_capture}] -setup -hold
set_output_delay -clock [get_clocks {eth2_phy_tx_capture}] -max 1.000 [get_ports {rgmii2_txd[*] rgmii2_tx_ctl}]
set_output_delay -clock [get_clocks {eth2_phy_tx_capture}] -min -1.000 [get_ports {rgmii2_txd[*] rgmii2_tx_ctl}]
set_output_delay -clock [get_clocks {eth2_phy_tx_capture}] -clock_fall -add_delay -max 1.000 [get_ports {rgmii2_txd[*] rgmii2_tx_ctl}]
set_output_delay -clock [get_clocks {eth2_phy_tx_capture}] -clock_fall -add_delay -min -1.000 [get_ports {rgmii2_txd[*] rgmii2_tx_ctl}]
'''
# Exactly the six port2 TX pads; preserve every other IO setting.
import re
s,n=re.subn(r'(define_attribute \{p:rgmii2_tx(?:c|_ctl|d\[[0-3]\])\} \{PAP_IO_DRIVE\} )\{4\}',r'\g<1>{12}',s)
assert n==6,n
p.write_text(s)
p=Path('flow.tcl');s=p.read_text().replace('-route_constraint_iterate_times 3','-route_constraint_iterate_times 1');p.write_text(s)
