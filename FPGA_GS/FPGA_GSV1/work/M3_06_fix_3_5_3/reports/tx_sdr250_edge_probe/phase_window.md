|Pin|Corner|Capture edge|Lower delta ns|Upper delta ns|Width ns|Setup line|Hold line|
|---|---|---|---:|---:|---:|---:|---:|
|rgmii2_tx_ctl|slow|rising edge|0.109|-0.219|-0.328|1141|1220|
|rgmii2_tx_ctl|slow|falling edge|0.134|-0.188|-0.322|983|1378|
|rgmii2_tx_ctl|fast|rising edge|-0.122|-0.019|0.103|5702|5781|
|rgmii2_tx_ctl|fast|falling edge|-0.053|0.057|0.11|5307|6176|
|rgmii2_txd[0]|slow|rising edge|0.145|-0.183|-0.328|667|1615|
|rgmii2_txd[0]|slow|falling edge|0.17|-0.152|-0.322|430|1931|
|rgmii2_txd[0]|fast|rising edge|-0.086|0.017|0.103|5386|6097|
|rgmii2_txd[0]|fast|falling edge|-0.017|0.093|0.11|4991|6492|
|rgmii2_txd[1]|slow|rising edge|0.144|-0.184|-0.328|746|1536|
|rgmii2_txd[1]|slow|falling edge|0.169|-0.153|-0.322|509|1852|
|rgmii2_txd[1]|fast|rising edge|-0.087|0.016|0.103|5465|6018|
|rgmii2_txd[1]|fast|falling edge|-0.018|0.092|0.11|5070|6413|
|rgmii2_txd[2]|slow|rising edge|0.14|-0.188|-0.328|904|1457|
|rgmii2_txd[2]|slow|falling edge|0.165|-0.157|-0.322|588|1773|
|rgmii2_txd[2]|fast|rising edge|-0.091|0.012|0.103|5544|5939|
|rgmii2_txd[2]|fast|falling edge|-0.022|0.088|0.11|5149|6334|
|rgmii2_txd[3]|slow|rising edge|0.118|-0.21|-0.328|1062|1299|
|rgmii2_txd[3]|slow|falling edge|0.143|-0.179|-0.322|825|1694|
|rgmii2_txd[3]|fast|rising edge|-0.113|-0.01|0.103|5623|5860|
|rgmii2_txd[3]|fast|falling edge|-0.044|0.066|0.11|5228|6255|

Common: {"lower_ns": 0.17, "upper_ns": -0.219, "width_ns": -0.389, "feasible": false, "lower_path": {"line": 430, "startpoint": "pins[0].pad/opit_1_OQ/SYSCLK", "endpoint": "rgmii2_txd[0]", "type": "max (slow corner)", "launch_edge": "sys_clk|u_cfg_pll/u_pll_e3/CLKOUT3_Inferred (rising edge)", "capture_edge": "falling edge", "launch_clock_ns": 5.088, "capture_clock_ns": 8.131, "cpr_ns": 0.17, "data_arrival_ns": 13.121, "data_required_ns": 12.951, "slack_ns": -0.17}, "upper_path": {"line": 1220, "startpoint": "ctl_pad/opit_1_OQ/SYSCLK", "endpoint": "rgmii2_tx_ctl", "type": "min (slow corner)", "launch_edge": "sys_clk|u_cfg_pll/u_pll_e3/CLKOUT3_Inferred (rising edge)", "capture_edge": "rising edge", "launch_clock_ns": 4.743, "capture_clock_ns": 9.119, "cpr_ns": -0.264, "data_arrival_ns": 11.986, "data_required_ns": 12.205, "slack_ns": -0.219}}

Sensitivity only: {"removed_uncertainty_ns": 0.3, "signoff": false, "lower_ns": -0.13, "upper_ns": 0.081, "width_ns": 0.211, "feasible": true, "lower_path": {"line": 430, "startpoint": "pins[0].pad/opit_1_OQ/SYSCLK", "endpoint": "rgmii2_txd[0]", "type": "max (slow corner)", "launch_edge": "sys_clk|u_cfg_pll/u_pll_e3/CLKOUT3_Inferred (rising edge)", "capture_edge": "falling edge", "launch_clock_ns": 5.088, "capture_clock_ns": 8.131, "cpr_ns": 0.17, "data_arrival_ns": 13.121, "data_required_ns": 12.951, "slack_ns": -0.17}, "upper_path": {"line": 1220, "startpoint": "ctl_pad/opit_1_OQ/SYSCLK", "endpoint": "rgmii2_tx_ctl", "type": "min (slow corner)", "launch_edge": "sys_clk|u_cfg_pll/u_pll_e3/CLKOUT3_Inferred (rising edge)", "capture_edge": "rising edge", "launch_clock_ns": 4.743, "capture_clock_ns": 9.119, "cpr_ns": -0.264, "data_arrival_ns": 11.986, "data_required_ns": 12.205, "slack_ns": -0.219}}

Datasheet duty sensitivity: {"duty_percent": [45, 55], "already_covered_in_input": false, "additional_half_cycle_shortening_ns": 0.4, "new_sta_run": false, "signoff": false, "original_budget": {"lower_ns": 0.17, "upper_ns": -0.619, "width_ns": -0.789, "feasible": false, "lower_path": {"line": 430, "startpoint": "pins[0].pad/opit_1_OQ/SYSCLK", "endpoint": "rgmii2_txd[0]", "type": "max (slow corner)", "launch_edge": "sys_clk|u_cfg_pll/u_pll_e3/CLKOUT3_Inferred (rising edge)", "capture_edge": "falling edge", "launch_clock_ns": 5.088, "capture_clock_ns": 8.131, "cpr_ns": 0.17, "data_arrival_ns": 13.121, "data_required_ns": 12.951, "slack_ns": -0.17}, "upper_path": {"line": 1220, "startpoint": "ctl_pad/opit_1_OQ/SYSCLK", "endpoint": "rgmii2_tx_ctl", "type": "min (slow corner)", "launch_edge": "sys_clk|u_cfg_pll/u_pll_e3/CLKOUT3_Inferred (rising edge)", "capture_edge": "rising edge", "launch_clock_ns": 4.743, "capture_clock_ns": 9.119, "cpr_ns": -0.264, "data_arrival_ns": 11.986, "data_required_ns": 12.205, "slack_ns": -0.619}}, "arbitrary_budget_removed": {"lower_ns": -0.13, "upper_ns": -0.319, "width_ns": -0.189, "feasible": false, "lower_path": {"line": 430, "startpoint": "pins[0].pad/opit_1_OQ/SYSCLK", "endpoint": "rgmii2_txd[0]", "type": "max (slow corner)", "launch_edge": "sys_clk|u_cfg_pll/u_pll_e3/CLKOUT3_Inferred (rising edge)", "capture_edge": "falling edge", "launch_clock_ns": 5.088, "capture_clock_ns": 8.131, "cpr_ns": 0.17, "data_arrival_ns": 13.121, "data_required_ns": 12.951, "slack_ns": -0.17}, "upper_path": {"line": 1220, "startpoint": "ctl_pad/opit_1_OQ/SYSCLK", "endpoint": "rgmii2_tx_ctl", "type": "min (slow corner)", "launch_edge": "sys_clk|u_cfg_pll/u_pll_e3/CLKOUT3_Inferred (rising edge)", "capture_edge": "rising edge", "launch_clock_ns": 4.743, "capture_clock_ns": 9.119, "cpr_ns": -0.264, "data_arrival_ns": 11.986, "data_required_ns": 12.205, "slack_ns": -0.619}}}
