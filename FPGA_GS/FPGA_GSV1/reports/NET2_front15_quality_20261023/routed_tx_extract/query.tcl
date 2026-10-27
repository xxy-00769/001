open_project E:/zhoumian/FPGA/FPGA_GS/FPGA_GSV1/work/M3_06_E1_integrated_3_5_4/build/M3_06_3_5_4_20261022_185404_116/build.pds
set_dir -impl_directory E:/zhoumian/FPGA/FPGA_GS/FPGA_GSV1/reports/NET2_front15_quality_20261023/routed_tx_extract
report_timing -force_to_run -input_db_file E:/zhoumian/FPGA/FPGA_GS/FPGA_GSV1/work/M3_06_E1_integrated_3_5_4/build/M3_06_3_5_4_20261022_185404_116/place_route/fpga_gsv1_top_pnr.adf -report_io_datasheet -to {rgmii2_txc rgmii2_txd* rgmii2_tx_ctl} -max_path 100 -nworst 8 -input_pins TRUE
exit

