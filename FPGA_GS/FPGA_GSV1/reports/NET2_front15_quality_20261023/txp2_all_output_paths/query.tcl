open_project E:/zhoumian/FPGA/FPGA_GS/FPGA_GSV1/work/M3_06_front15_txp2/build/M3_06_3_5_4_TXP2_20261023_123336_837/build.pds
set_dir -impl_directory E:/zhoumian/FPGA/FPGA_GS/FPGA_GSV1/reports/NET2_front15_quality_20261023/txp2_all_output_paths
report_timing -force_to_run -input_db_file E:/zhoumian/FPGA/FPGA_GS/FPGA_GSV1/work/M3_06_front15_txp2/build/M3_06_3_5_4_TXP2_20261023_123336_837/place_route/fpga_gsv1_top_pnr.adf -to {rgmii2_txd* rgmii2_tx_ctl} -max_path 1000 -nworst 32 -input_pins TRUE
exit
