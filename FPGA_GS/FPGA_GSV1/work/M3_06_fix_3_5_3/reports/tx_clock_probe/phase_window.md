|Pin|Corner|Capture edge|Lower delta ns|Upper delta ns|Width ns|Setup line|Hold line|
|---|---|---|---:|---:|---:|---:|---:|
|rgmii2_tx_ctl|slow|rising edge|0.256|-0.121|-0.377|852|1721|
|rgmii2_tx_ctl|slow|falling edge|0.343|-0.036|-0.379|457|2116|
|rgmii2_tx_ctl|fast|rising edge|0.028|0.094|0.066|10309|11178|
|rgmii2_tx_ctl|fast|falling edge|0.112|0.193|0.081|9914|11573|
|rgmii2_txd[0]|slow|rising edge|0.292|-0.085|-0.377|536|2037|
|rgmii2_txd[0]|slow|falling edge|0.379|0.0|-0.379|141|2432|
|rgmii2_txd[0]|fast|rising edge|0.064|0.13|0.066|9993|11494|
|rgmii2_txd[0]|fast|falling edge|0.148|0.229|0.081|9598|11889|
|rgmii2_txd[1]|slow|rising edge|0.291|-0.086|-0.377|615|1958|
|rgmii2_txd[1]|slow|falling edge|0.378|-0.001|-0.379|220|2353|
|rgmii2_txd[1]|fast|rising edge|0.063|0.129|0.066|10072|11415|
|rgmii2_txd[1]|fast|falling edge|0.147|0.228|0.081|9677|11810|
|rgmii2_txd[2]|slow|rising edge|0.287|-0.09|-0.377|694|1879|
|rgmii2_txd[2]|slow|falling edge|0.374|-0.005|-0.379|299|2274|
|rgmii2_txd[2]|fast|rising edge|0.059|0.125|0.066|10151|11336|
|rgmii2_txd[2]|fast|falling edge|0.143|0.224|0.081|9756|11731|
|rgmii2_txd[3]|slow|rising edge|0.265|-0.112|-0.377|773|1800|
|rgmii2_txd[3]|slow|falling edge|0.352|-0.027|-0.379|378|2195|
|rgmii2_txd[3]|fast|rising edge|0.037|0.103|0.066|10230|11257|
|rgmii2_txd[3]|fast|falling edge|0.121|0.202|0.081|9835|11652|

Common: {"lower_ns": 0.379, "upper_ns": -0.121, "width_ns": -0.5, "feasible": false, "lower_path": {"line": 141, "startpoint": "pins[0].genblk1.pad/opit_1_IOL/SYSCLK", "endpoint": "rgmii2_txd[0]", "type": "max (slow corner)", "launch_edge": "sys_clk|u_cfg_pll/u_pll_e3/CLKOUT3_Inferred (falling edge)", "capture_edge": "falling edge", "launch_clock_ns": 5.218, "capture_clock_ns": 8.169, "cpr_ns": 0.282, "data_arrival_ns": 13.48, "data_required_ns": 13.101, "slack_ns": -0.379}, "upper_path": {"line": 1721, "startpoint": "pins[4].genblk1.pad/opit_1_IOL/SYSCLK", "endpoint": "rgmii2_tx_ctl", "type": "min (slow corner)", "launch_edge": "sys_clk|u_cfg_pll/u_pll_e3/CLKOUT3_Inferred (falling edge)", "capture_edge": "rising edge", "launch_clock_ns": 4.854, "capture_clock_ns": 9.195, "cpr_ns": -0.17, "data_arrival_ns": 12.254, "data_required_ns": 12.375, "slack_ns": -0.121}}

Sensitivity only: {"removed_uncertainty_ns": 0.3, "signoff": false, "lower_ns": 0.079, "upper_ns": 0.179, "width_ns": 0.1, "feasible": true, "lower_path": {"line": 141, "startpoint": "pins[0].genblk1.pad/opit_1_IOL/SYSCLK", "endpoint": "rgmii2_txd[0]", "type": "max (slow corner)", "launch_edge": "sys_clk|u_cfg_pll/u_pll_e3/CLKOUT3_Inferred (falling edge)", "capture_edge": "falling edge", "launch_clock_ns": 5.218, "capture_clock_ns": 8.169, "cpr_ns": 0.282, "data_arrival_ns": 13.48, "data_required_ns": 13.101, "slack_ns": -0.379}, "upper_path": {"line": 1721, "startpoint": "pins[4].genblk1.pad/opit_1_IOL/SYSCLK", "endpoint": "rgmii2_tx_ctl", "type": "min (slow corner)", "launch_edge": "sys_clk|u_cfg_pll/u_pll_e3/CLKOUT3_Inferred (falling edge)", "capture_edge": "rising edge", "launch_clock_ns": 4.854, "capture_clock_ns": 9.195, "cpr_ns": -0.17, "data_arrival_ns": 12.254, "data_required_ns": 12.375, "slack_ns": -0.121}}
