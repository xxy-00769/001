open_project E:/zhoumian/FPGA/FPGA_GS/FPGA_GSV1/work/M3_06_front15_txobs1/build/M3_06_3_5_4_TXOBS1_20261023_120634_068/build.pds
set_dir -impl_directory E:/zhoumian/FPGA/FPGA_GS/FPGA_GSV1/reports/NET2_front15_quality_20261023/txobs1_routed_tx_extract
report_timing -force_to_run -input_db_file E:/zhoumian/FPGA/FPGA_GS/FPGA_GSV1/work/M3_06_front15_txobs1/build/M3_06_3_5_4_TXOBS1_20261023_120634_068/place_route/fpga_gsv1_top_pnr.adf -report_io_datasheet -to {rgmii2_txc rgmii2_txd* rgmii2_tx_ctl} -max_path 100 -nworst 8 -input_pins TRUE
exit
