|Pin|Corner|Capture edge|Lower delta ns|Upper delta ns|Width ns|Setup line|Hold line|
|---|---|---|---:|---:|---:|---:|---:|
|rgmii2_tx_ctl|slow|rising edge|-0.22|-0.315|-0.095|773|1565|
|rgmii2_tx_ctl|slow|falling edge|-0.157|-0.253|-0.096|413|1925|
|rgmii2_tx_ctl|fast|rising edge|-0.439|-0.12|0.319|4092|4884|
|rgmii2_tx_ctl|fast|falling edge|-0.354|-0.028|0.326|3732|5244|
|rgmii2_txd[0]|slow|rising edge|-0.184|-0.279|-0.095|485|1853|
|rgmii2_txd[0]|slow|falling edge|-0.121|-0.217|-0.096|125|2213|
|rgmii2_txd[0]|fast|rising edge|-0.403|-0.084|0.319|3804|5172|
|rgmii2_txd[0]|fast|falling edge|-0.318|0.008|0.326|3444|5532|
|rgmii2_txd[1]|slow|rising edge|-0.185|-0.28|-0.095|557|1781|
|rgmii2_txd[1]|slow|falling edge|-0.122|-0.218|-0.096|197|2141|
|rgmii2_txd[1]|fast|rising edge|-0.404|-0.085|0.319|3876|5100|
|rgmii2_txd[1]|fast|falling edge|-0.319|0.007|0.326|3516|5460|
|rgmii2_txd[2]|slow|rising edge|-0.189|-0.284|-0.095|629|1709|
|rgmii2_txd[2]|slow|falling edge|-0.126|-0.222|-0.096|269|2069|
|rgmii2_txd[2]|fast|rising edge|-0.408|-0.089|0.319|3948|5028|
|rgmii2_txd[2]|fast|falling edge|-0.323|0.003|0.326|3588|5388|
|rgmii2_txd[3]|slow|rising edge|-0.211|-0.306|-0.095|701|1637|
|rgmii2_txd[3]|slow|falling edge|-0.148|-0.244|-0.096|341|1997|
|rgmii2_txd[3]|fast|rising edge|-0.43|-0.111|0.319|4020|4956|
|rgmii2_txd[3]|fast|falling edge|-0.345|-0.019|0.326|3660|5316|

Common: {"lower_ns": -0.121, "upper_ns": -0.315, "width_ns": -0.194, "feasible": false, "lower_path": {"line": 125, "startpoint": "phy/tx_data_pad[0].pad/opit_1_IOL/SERCLK", "endpoint": "rgmii2_txd[0]", "type": "max (slow corner)", "launch_edge": "eth2_rxc (falling edge)", "capture_edge": "falling edge", "launch_clock_ns": 2.814, "capture_clock_ns": 5.781, "cpr_ns": 0.365, "data_arrival_ns": 10.975, "data_required_ns": 11.096, "slack_ns": 0.121}, "upper_path": {"line": 1565, "startpoint": "phy/tx_control_pad/opit_1_IOL/SERCLK", "endpoint": "rgmii2_tx_ctl", "type": "min (slow corner)", "launch_edge": "eth2_rxc (falling edge)", "capture_edge": "rising edge", "launch_clock_ns": 2.426, "capture_clock_ns": 6.862, "cpr_ns": -0.254, "data_arrival_ns": 9.743, "data_required_ns": 10.058, "slack_ns": -0.315}}

Sensitivity only: {"removed_uncertainty_ns": 0.0, "signoff": false, "lower_ns": -0.121, "upper_ns": -0.315, "width_ns": -0.194, "feasible": false, "lower_path": {"line": 125, "startpoint": "phy/tx_data_pad[0].pad/opit_1_IOL/SERCLK", "endpoint": "rgmii2_txd[0]", "type": "max (slow corner)", "launch_edge": "eth2_rxc (falling edge)", "capture_edge": "falling edge", "launch_clock_ns": 2.814, "capture_clock_ns": 5.781, "cpr_ns": 0.365, "data_arrival_ns": 10.975, "data_required_ns": 11.096, "slack_ns": 0.121}, "upper_path": {"line": 1565, "startpoint": "phy/tx_control_pad/opit_1_IOL/SERCLK", "endpoint": "rgmii2_tx_ctl", "type": "min (slow corner)", "launch_edge": "eth2_rxc (falling edge)", "capture_edge": "rising edge", "launch_clock_ns": 2.426, "capture_clock_ns": 6.862, "cpr_ns": -0.254, "data_arrival_ns": 9.743, "data_required_ns": 10.058, "slack_ns": -0.315}}

Datasheet duty sensitivity: {"duty_percent": [45, 55], "already_covered_in_input": true, "additional_half_cycle_shortening_ns": 0, "new_sta_run": false, "signoff": false, "original_budget": {"lower_ns": -0.121, "upper_ns": -0.315, "width_ns": -0.194, "feasible": false, "lower_path": {"line": 125, "startpoint": "phy/tx_data_pad[0].pad/opit_1_IOL/SERCLK", "endpoint": "rgmii2_txd[0]", "type": "max (slow corner)", "launch_edge": "eth2_rxc (falling edge)", "capture_edge": "falling edge", "launch_clock_ns": 2.814, "capture_clock_ns": 5.781, "cpr_ns": 0.365, "data_arrival_ns": 10.975, "data_required_ns": 11.096, "slack_ns": 0.121}, "upper_path": {"line": 1565, "startpoint": "phy/tx_control_pad/opit_1_IOL/SERCLK", "endpoint": "rgmii2_tx_ctl", "type": "min (slow corner)", "launch_edge": "eth2_rxc (falling edge)", "capture_edge": "rising edge", "launch_clock_ns": 2.426, "capture_clock_ns": 6.862, "cpr_ns": -0.254, "data_arrival_ns": 9.743, "data_required_ns": 10.058, "slack_ns": -0.315}}, "arbitrary_budget_removed": {"lower_ns": -0.121, "upper_ns": -0.315, "width_ns": -0.194, "feasible": false, "lower_path": {"line": 125, "startpoint": "phy/tx_data_pad[0].pad/opit_1_IOL/SERCLK", "endpoint": "rgmii2_txd[0]", "type": "max (slow corner)", "launch_edge": "eth2_rxc (falling edge)", "capture_edge": "falling edge", "launch_clock_ns": 2.814, "capture_clock_ns": 5.781, "cpr_ns": 0.365, "data_arrival_ns": 10.975, "data_required_ns": 11.096, "slack_ns": 0.121}, "upper_path": {"line": 1565, "startpoint": "phy/tx_control_pad/opit_1_IOL/SERCLK", "endpoint": "rgmii2_tx_ctl", "type": "min (slow corner)", "launch_edge": "eth2_rxc (falling edge)", "capture_edge": "rising edge", "launch_clock_ns": 2.426, "capture_clock_ns": 6.862, "cpr_ns": -0.254, "data_arrival_ns": 9.743, "data_required_ns": 10.058, "slack_ns": -0.315}}}
