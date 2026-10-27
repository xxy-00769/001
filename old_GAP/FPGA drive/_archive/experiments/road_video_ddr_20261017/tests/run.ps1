param([int]$Scenario=0,[int]$Frames=3,[switch]$OriginalControl)
$ErrorActionPreference='Stop'
$project=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$experiment=Split-Path $PSScriptRoot
$modelsim='D:/PDS/Modelsim/win64'
$lib='D:/PDS/PDS_2022.2-SP6.1/arch/vendor/pango/verilog/simulation'
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss_fff'
$variant=if($OriginalControl){'original'}else{'candidate'}
$run=Join-Path $experiment "runs/${stamp}_s${Scenario}_$variant"
$null=New-Item -ItemType Directory -Path $run
& "$project/.venv-road-model/Scripts/python.exe" -X utf8 "$PSScriptRoot/audit.py" --capture $run
if($LASTEXITCODE -ne 0) { throw 'Input audit failed' }
$files=@('source/rtl/fram_buf.v','source/rtl/wr_buf.v','source/rtl/rd_buf.v',
 'source/rtl/wr_rd_ctrl_top.v','source/rtl/wr_cmd_trans.v','source/rtl/wr_ctrl.v','source/rtl/rd_ctrl.v',
 'source/rtl/wr_fram_buf/wr_fram_buf.v',
 'source/rtl/wr_fram_buf/rtl/ipml_sdpram_v1_6_wr_fram_buf.v',
 'source/rtl/rd_fram_buf/rd_fram_buf.v',
 'source/rtl/rd_fram_buf/rtl/ipml_sdpram_v1_6_rd_fram_buf.v',
 'experiments/road_ddr_bridge_20261017/source/road_ddr_bridge.v',
 'experiments/road_video_ddr_20261017/source/video_ddr_probe.v',
 'experiments/road_video_ddr_20261017/tests/video_memory.sv',
 'experiments/road_video_ddr_20261017/tests/video_tb.sv')
$argsFiles=$files | ForEach-Object { Join-Path $project $_ }
if(!$OriginalControl) {
    $argsFiles=$argsFiles | ForEach-Object {
        if($_ -in @('fram_buf.v','wr_buf.v','rd_buf.v','wr_cmd_trans.v' |
            ForEach-Object { Join-Path $project "source/rtl/$_" })) {
            Join-Path $experiment "source/$([IO.Path]::GetFileName($_))"
        } else { $_ }
    }
}
Push-Location $run
try {
    & "$modelsim/vlib.exe" work *> library.log
    if($LASTEXITCODE -ne 0) { throw 'vlib failed' }
    & "$modelsim/vlog.exe" -sv -work work $argsFiles -y $lib '+libext+.v' *> compile.log
    if($LASTEXITCODE -ne 0) { throw "Compilation failed: $run/compile.log" }
    & "$modelsim/vsim.exe" -c -novopt -t 1ps -suppress 12110 -lib work video_tb "+SCENARIO=$Scenario" "+FRAMES=$Frames" -do 'onerror {quit -code 2}; run -all; quit -code 0' -l simulation.log *> console.log
    if($LASTEXITCODE -ne 0) { throw "Simulation failed: $run/simulation.log" }
    & "$project/.venv-road-model/Scripts/python.exe" -X utf8 "$PSScriptRoot/audit.py" --verify $run
    if($LASTEXITCODE -ne 0) { throw "Evidence verification failed: $run" }
} finally { Pop-Location }
Write-Output "Evidence: $run"
