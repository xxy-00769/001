|Pin|Corner|Capture edge|Lower delta ns|Upper delta ns|Width ns|Setup line|Hold line|
|---|---|---|---:|---:|---:|---:|---:|
|rgmii2_tx_ctl|slow|rising edge|0.321|-0.19|-0.511|483|3075|
|rgmii2_tx_ctl|slow|falling edge|0.173|-0.449|-0.622|1203|2355|
|rgmii2_tx_ctl|fast|rising edge|-0.031|0.068|0.099|6808|9400|
|rgmii2_tx_ctl|fast|falling edge|-0.108|-0.086|0.022|7528|8680|
|rgmii2_txd[0]|slow|rising edge|0.357|-0.154|-0.511|195|3363|
|rgmii2_txd[0]|slow|falling edge|0.209|-0.413|-0.622|915|2715|
|rgmii2_txd[0]|fast|rising edge|0.005|0.104|0.099|6520|9688|
|rgmii2_txd[0]|fast|falling edge|-0.072|-0.05|0.022|7168|9040|
|rgmii2_txd[1]|slow|rising edge|0.356|-0.155|-0.511|267|3291|
|rgmii2_txd[1]|slow|falling edge|0.208|-0.414|-0.622|987|2643|
|rgmii2_txd[1]|fast|rising edge|0.004|0.103|0.099|6592|9616|
|rgmii2_txd[1]|fast|falling edge|-0.073|-0.051|0.022|7240|8968|
|rgmii2_txd[2]|slow|rising edge|0.352|-0.159|-0.511|339|3219|
|rgmii2_txd[2]|slow|falling edge|0.204|-0.418|-0.622|1059|2499|
|rgmii2_txd[2]|fast|rising edge|-0.0|0.099|0.099|6664|9544|
|rgmii2_txd[2]|fast|falling edge|-0.077|-0.055|0.022|7384|8896|
|rgmii2_txd[3]|slow|rising edge|0.33|-0.181|-0.511|411|3147|
|rgmii2_txd[3]|slow|falling edge|0.182|-0.44|-0.622|1131|2427|
|rgmii2_txd[3]|fast|rising edge|-0.022|0.077|0.099|6736|9472|
|rgmii2_txd[3]|fast|falling edge|-0.099|-0.077|0.022|7456|8752|

Common: {"lower_ns": 0.357, "upper_ns": -0.449, "width_ns": -0.806, "feasible": false, "lower_path": {"line": 195, "startpoint": "network2/port2_io.phy/rgmii_tx_data[0].gtp_outbuft1/opit_1_IOL/SYSCLK", "endpoint": "rgmii2_txd[0]", "type": "max (slow corner)", "launch_edge": "eth2_rxc (rising edge)", "capture_edge": "rising edge", "launch_clock_ns": 5.56, "capture_clock_ns": 9.186, "cpr_ns": 0.305, "data_arrival_ns": 10.598, "data_required_ns": 10.241, "slack_ns": -0.357}, "upper_path": {"line": 2355, "startpoint": "network2/port2_io.phy/gtp_outbuft1/opit_1_IOL/SYSCLK", "endpoint": "rgmii2_tx_ctl", "type": "min (slow corner)", "launch_edge": "eth2_rxc (rising edge)", "capture_edge": "falling edge", "launch_clock_ns": 5.226, "capture_clock_ns": 10.733, "cpr_ns": -0.42, "data_arrival_ns": 17.114, "data_required_ns": 17.563, "slack_ns": -0.449}}

Sensitivity only: {"removed_uncertainty_ns": 0.2, "signoff": false, "lower_ns": 0.157, "upper_ns": -0.249, "width_ns": -0.406, "feasible": false, "lower_path": {"line": 195, "startpoint": "network2/port2_io.phy/rgmii_tx_data[0].gtp_outbuft1/opit_1_IOL/SYSCLK", "endpoint": "rgmii2_txd[0]", "type": "max (slow corner)", "launch_edge": "eth2_rxc (rising edge)", "capture_edge": "rising edge", "launch_clock_ns": 5.56, "capture_clock_ns": 9.186, "cpr_ns": 0.305, "data_arrival_ns": 10.598, "data_required_ns": 10.241, "slack_ns": -0.357}, "upper_path": {"line": 2355, "startpoint": "network2/port2_io.phy/gtp_outbuft1/opit_1_IOL/SYSCLK", "endpoint": "rgmii2_tx_ctl", "type": "min (slow corner)", "launch_edge": "eth2_rxc (rising edge)", "capture_edge": "falling edge", "launch_clock_ns": 5.226, "capture_clock_ns": 10.733, "cpr_ns": -0.42, "data_arrival_ns": 17.114, "data_required_ns": 17.563, "slack_ns": -0.449}}

Datasheet duty sensitivity: {"duty_percent": [45, 55], "half_cycle_shortening_ns": 0.4, "new_sta_run": false, "signoff": false, "original_budget": {"lower_ns": 0.357, "upper_ns": -0.849, "width_ns": -1.206, "feasible": false, "lower_path": {"line": 195, "startpoint": "network2/port2_io.phy/rgmii_tx_data[0].gtp_outbuft1/opit_1_IOL/SYSCLK", "endpoint": "rgmii2_txd[0]", "type": "max (slow corner)", "launch_edge": "eth2_rxc (rising edge)", "capture_edge": "rising edge", "launch_clock_ns": 5.56, "capture_clock_ns": 9.186, "cpr_ns": 0.305, "data_arrival_ns": 10.598, "data_required_ns": 10.241, "slack_ns": -0.357}, "upper_path": {"line": 2355, "startpoint": "network2/port2_io.phy/gtp_outbuft1/opit_1_IOL/SYSCLK", "endpoint": "rgmii2_tx_ctl", "type": "min (slow corner)", "launch_edge": "eth2_rxc (rising edge)", "capture_edge": "falling edge", "launch_clock_ns": 5.226, "capture_clock_ns": 10.733, "cpr_ns": -0.42, "data_arrival_ns": 17.114, "data_required_ns": 17.563, "slack_ns": -0.849}}, "arbitrary_budget_removed": {"lower_ns": 0.157, "upper_ns": -0.649, "width_ns": -0.806, "feasible": false, "lower_path": {"line": 195, "startpoint": "network2/port2_io.phy/rgmii_tx_data[0].gtp_outbuft1/opit_1_IOL/SYSCLK", "endpoint": "rgmii2_txd[0]", "type": "max (slow corner)", "launch_edge": "eth2_rxc (rising edge)", "capture_edge": "rising edge", "launch_clock_ns": 5.56, "capture_clock_ns": 9.186, "cpr_ns": 0.305, "data_arrival_ns": 10.598, "data_required_ns": 10.241, "slack_ns": -0.357}, "upper_path": {"line": 2355, "startpoint": "network2/port2_io.phy/gtp_outbuft1/opit_1_IOL/SYSCLK", "endpoint": "rgmii2_tx_ctl", "type": "min (slow corner)", "launch_edge": "eth2_rxc (rising edge)", "capture_edge": "falling edge", "launch_clock_ns": 5.226, "capture_clock_ns": 10.733, "cpr_ns": -0.42, "data_arrival_ns": 17.114, "data_required_ns": 17.563, "slack_ns": -0.849}}}
