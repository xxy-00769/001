|Pin|Corner|Capture edge|Lower delta ns|Upper delta ns|Width ns|Setup line|Hold line|
|---|---|---|---:|---:|---:|---:|---:|
|rgmii2_tx_ctl|slow|rising edge|0.08|-0.215|-0.295|843|1635|
|rgmii2_tx_ctl|slow|falling edge|0.143|-0.153|-0.296|483|1995|
|rgmii2_tx_ctl|fast|rising edge|-0.139|-0.02|0.119|5728|6520|
|rgmii2_tx_ctl|fast|falling edge|-0.054|0.072|0.126|5368|6880|
|rgmii2_txd[0]|slow|rising edge|0.116|-0.179|-0.295|555|1923|
|rgmii2_txd[0]|slow|falling edge|0.179|-0.117|-0.296|195|2283|
|rgmii2_txd[0]|fast|rising edge|-0.103|0.016|0.119|5440|6808|
|rgmii2_txd[0]|fast|falling edge|-0.018|0.108|0.126|5080|7168|
|rgmii2_txd[1]|slow|rising edge|0.115|-0.18|-0.295|627|1851|
|rgmii2_txd[1]|slow|falling edge|0.178|-0.118|-0.296|267|2211|
|rgmii2_txd[1]|fast|rising edge|-0.104|0.015|0.119|5512|6736|
|rgmii2_txd[1]|fast|falling edge|-0.019|0.107|0.126|5152|7096|
|rgmii2_txd[2]|slow|rising edge|0.111|-0.184|-0.295|699|1779|
|rgmii2_txd[2]|slow|falling edge|0.174|-0.122|-0.296|339|2139|
|rgmii2_txd[2]|fast|rising edge|-0.108|0.011|0.119|5584|6664|
|rgmii2_txd[2]|fast|falling edge|-0.023|0.103|0.126|5224|7024|
|rgmii2_txd[3]|slow|rising edge|0.089|-0.206|-0.295|771|1707|
|rgmii2_txd[3]|slow|falling edge|0.152|-0.144|-0.296|411|2067|
|rgmii2_txd[3]|fast|rising edge|-0.13|-0.011|0.119|5656|6592|
|rgmii2_txd[3]|fast|falling edge|-0.045|0.081|0.126|5296|6952|

Common: {"lower_ns": 0.179, "upper_ns": -0.215, "width_ns": -0.394, "feasible": false, "lower_path": {"line": 195, "startpoint": "network2/port2_io.phy/tx_data_pad[0].pad/opit_1_IOL/SERCLK", "endpoint": "rgmii2_txd[0]", "type": "max (slow corner)", "launch_edge": "eth2_rxc (falling edge)", "capture_edge": "falling edge", "launch_clock_ns": 2.814, "capture_clock_ns": 5.781, "cpr_ns": 0.365, "data_arrival_ns": 10.975, "data_required_ns": 10.796, "slack_ns": -0.179}, "upper_path": {"line": 1635, "startpoint": "network2/port2_io.phy/tx_control_pad/opit_1_IOL/SERCLK", "endpoint": "rgmii2_tx_ctl", "type": "min (slow corner)", "launch_edge": "eth2_rxc (falling edge)", "capture_edge": "rising edge", "launch_clock_ns": 2.426, "capture_clock_ns": 6.862, "cpr_ns": -0.254, "data_arrival_ns": 9.743, "data_required_ns": 9.958, "slack_ns": -0.215}}

Sensitivity only: {"removed_uncertainty_ns": 0.3, "signoff": false, "lower_ns": -0.121, "upper_ns": 0.085, "width_ns": 0.206, "feasible": true, "lower_path": {"line": 195, "startpoint": "network2/port2_io.phy/tx_data_pad[0].pad/opit_1_IOL/SERCLK", "endpoint": "rgmii2_txd[0]", "type": "max (slow corner)", "launch_edge": "eth2_rxc (falling edge)", "capture_edge": "falling edge", "launch_clock_ns": 2.814, "capture_clock_ns": 5.781, "cpr_ns": 0.365, "data_arrival_ns": 10.975, "data_required_ns": 10.796, "slack_ns": -0.179}, "upper_path": {"line": 1635, "startpoint": "network2/port2_io.phy/tx_control_pad/opit_1_IOL/SERCLK", "endpoint": "rgmii2_tx_ctl", "type": "min (slow corner)", "launch_edge": "eth2_rxc (falling edge)", "capture_edge": "rising edge", "launch_clock_ns": 2.426, "capture_clock_ns": 6.862, "cpr_ns": -0.254, "data_arrival_ns": 9.743, "data_required_ns": 9.958, "slack_ns": -0.215}}

Datasheet duty sensitivity: {"duty_percent": [45, 55], "half_cycle_shortening_ns": 0.4, "new_sta_run": false, "signoff": false, "original_budget": {"lower_ns": 0.179, "upper_ns": -0.615, "width_ns": -0.794, "feasible": false, "lower_path": {"line": 195, "startpoint": "network2/port2_io.phy/tx_data_pad[0].pad/opit_1_IOL/SERCLK", "endpoint": "rgmii2_txd[0]", "type": "max (slow corner)", "launch_edge": "eth2_rxc (falling edge)", "capture_edge": "falling edge", "launch_clock_ns": 2.814, "capture_clock_ns": 5.781, "cpr_ns": 0.365, "data_arrival_ns": 10.975, "data_required_ns": 10.796, "slack_ns": -0.179}, "upper_path": {"line": 1635, "startpoint": "network2/port2_io.phy/tx_control_pad/opit_1_IOL/SERCLK", "endpoint": "rgmii2_tx_ctl", "type": "min (slow corner)", "launch_edge": "eth2_rxc (falling edge)", "capture_edge": "rising edge", "launch_clock_ns": 2.426, "capture_clock_ns": 6.862, "cpr_ns": -0.254, "data_arrival_ns": 9.743, "data_required_ns": 9.958, "slack_ns": -0.615}}, "arbitrary_budget_removed": {"lower_ns": -0.121, "upper_ns": -0.315, "width_ns": -0.194, "feasible": false, "lower_path": {"line": 195, "startpoint": "network2/port2_io.phy/tx_data_pad[0].pad/opit_1_IOL/SERCLK", "endpoint": "rgmii2_txd[0]", "type": "max (slow corner)", "launch_edge": "eth2_rxc (falling edge)", "capture_edge": "falling edge", "launch_clock_ns": 2.814, "capture_clock_ns": 5.781, "cpr_ns": 0.365, "data_arrival_ns": 10.975, "data_required_ns": 10.796, "slack_ns": -0.179}, "upper_path": {"line": 1635, "startpoint": "network2/port2_io.phy/tx_control_pad/opit_1_IOL/SERCLK", "endpoint": "rgmii2_tx_ctl", "type": "min (slow corner)", "launch_edge": "eth2_rxc (falling edge)", "capture_edge": "rising edge", "launch_clock_ns": 2.426, "capture_clock_ns": 6.862, "cpr_ns": -0.254, "data_arrival_ns": 9.743, "data_required_ns": 9.958, "slack_ns": -0.615}}}
