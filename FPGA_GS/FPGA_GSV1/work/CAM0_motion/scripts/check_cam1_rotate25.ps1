param([string]$Tools='E:/zhoumian/FPGA/tmp/v5_tools/ucrt64/bin')
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$env:PATH="$Tools;$env:PATH"
Push-Location $root
try {
 $capture=@('rtl/capture/cam_ov3660_config.v','rtl/capture/cam_ov3660_table.v','rtl/capture/cam_sensor_id.v','rtl/capture/cam_sccb_read16.v','rtl/capture/cam_sccb_write16.v')
 foreach($rotation in @(1,0)) {
  $name="config_rotate$rotation"
  & iverilog -g2012 -s cam_ov3660_config_tb "-Pcam_ov3660_config_tb.ROTATE_180=$rotation" -o "reports/$name.vvp" sim/cam_ov3660_config_tb.sv @capture
  if($LASTEXITCODE){throw "$name compile"}
  & vvp "reports/$name.vvp" *> "reports/$name.log"
  if($LASTEXITCODE -or (Get-Content "reports/$name.log" -Raw) -notmatch 'PASS'){throw "$name failed"}
  Get-Content "reports/$name.log"
 }
 $pango='E:/XUEXI/FPGA_PDS/PDS_2022.2-SP6.4/arch/vendor/pango/verilog/simulation'
 $units=@('sim/cam1_rotate25_tb.sv','sim/line_ram_model.sv','rtl/capture/cam3660_dvp.v','rtl/capture/capture_pipe.v','rtl/reuse/video_capture_status.v','rtl/reuse/fram_buf.v','rtl/frame/m3_front_owner.v','rtl/reuse/frame_buffer_owner.v','rtl/reuse/wr_buf.v','rtl/reuse/wr_rd_ctrl_top.v','rtl/reuse/wr_cmd_trans.v','rtl/reuse/wr_ctrl.v','rtl/reuse/rd_ctrl.v','rtl/display/m31_rd_buf.v','rtl/display/m31_timing.v','rtl/network/m361_diag.v')
 & iverilog -g2012 -s GRS_INST -s cam1_rotate25_tb -o reports/cam1_rotate25.vvp @units "$pango/GTP_IOCLKBUF.v" "$pango/GTP_IOCLKDIV.v"
 if($LASTEXITCODE){throw 'CAM1 production path compile'}
 & vvp reports/cam1_rotate25.vvp *> reports/cam1_rotate25.log
 if($LASTEXITCODE -or (Get-Content reports/cam1_rotate25.log -Raw) -notmatch 'PASS'){Get-Content reports/cam1_rotate25.log;throw 'CAM1 production path failed'}
 Get-Content reports/cam1_rotate25.log
 & iverilog -g2012 -s cam1_rate_status_tb -o reports/cam1_rate_status.vvp sim/cam1_rate_status_tb.sv rtl/capture/cam1_rate_status.v rtl/network/m361_diag.v
 if($LASTEXITCODE){throw 'Rate status compile'}
 & vvp reports/cam1_rate_status.vvp *> reports/cam1_rate_status.log
 if($LASTEXITCODE){throw 'Rate status failed'}
 Get-Content reports/cam1_rate_status.log
 & iverilog -g2012 -s cam1_byte_verdict_tb -o reports/cam1_byte_verdict.vvp sim/cam1_byte_verdict_tb.sv rtl/reuse/video_capture_status.v
 if($LASTEXITCODE){throw 'Byte verdict compile'}
 & vvp reports/cam1_byte_verdict.vvp *> reports/cam1_byte_verdict.log
 if($LASTEXITCODE){throw 'Byte verdict failed'}
 Get-Content reports/cam1_byte_verdict.log
 & python -X utf8 scripts/check_cam1_decoder.py
 if($LASTEXITCODE){throw 'Rate decoder failed'}
 & python -X utf8 scripts/audit_cam1_rotate25.py
 if($LASTEXITCODE){throw 'Protected-source scope failed'}
} finally {Pop-Location}
