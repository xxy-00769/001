open_project E:/zhoumian/FPGA/FPGA_GS/FPGA_GSV1/work/M3_06_front15_txdet1/build/M3_06_3_5_5_TXDET1_20261023_141332_459/build.pds
set_dir -impl_directory E:/zhoumian/FPGA/FPGA_GS/FPGA_GSV1/work/M3_06_front15_txdet1/reports/full_output_paths
report_timing -force_to_run -input_db_file E:/zhoumian/FPGA/FPGA_GS/FPGA_GSV1/work/M3_06_front15_txdet1/build/M3_06_3_5_5_TXDET1_20261023_141332_459/place_route/fpga_gsv1_top_pnr.adf -to {rgmii2_txd* rgmii2_tx_ctl} -max_path 1000 -nworst 32 -input_pins TRUE
exit
