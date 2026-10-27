param(
    [string]$OutputParent = 'E:\FPGA drive\tmp\frame_ownership',
    [string]$ModelSim = 'D:\PDS\Modelsim\win64',
    [string]$PrimitiveLibrary = 'D:\PDS\PDS_2022.2-SP6.1\arch\vendor\pango\verilog\simulation'
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$run=[IO.Path]::GetFullPath((Join-Path $OutputParent (
    (Get-Date -Format 'yyyyMMdd_HHmmss_fff')+'_'+[Guid]::NewGuid().ToString('N').Substring(0,8))))
$allowed=[IO.Path]::GetFullPath((Join-Path (Split-Path $repo -Parent) 'tmp'))
if(-not $run.StartsWith($allowed+'\',[StringComparison]::OrdinalIgnoreCase) -or
    (Test-Path -LiteralPath $run)) {throw 'Unique workspace tmp output required.'}
$sources=@('video_capture_status.v','img_proc.v','lane_detect.v','zebra_detect.v',
    'zebra_overlay.v','lane_geometry.v','adas_overlay.v','frame_buffer_owner.v',
    'fram_buf.v','wr_buf.v','rd_buf.v','wr_rd_ctrl_top.v','wr_cmd_trans.v','wr_ctrl.v','rd_ctrl.v',
    'wr_fram_buf/wr_fram_buf.v','wr_fram_buf/rtl/ipml_sdpram_v1_6_wr_fram_buf.v',
    'rd_fram_buf/rd_fram_buf.v','rd_fram_buf/rtl/ipml_sdpram_v1_6_rd_fram_buf.v') |
    ForEach-Object {Join-Path $repo "source\rtl\$_"}
$sources+=@('full_frame_tb.sv','owner_tb.sv') | ForEach-Object {Join-Path $PSScriptRoot $_}
$inputs=@($sources)+@($PSCommandPath,
    (Join-Path $PrimitiveLibrary 'GTP_GRS.v'),(Join-Path $PrimitiveLibrary 'GTP_DRM18K.v'),
    (Join-Path $repo 'source/rtl/hdmi_ddr_ov5640_top.v'),
    (Join-Path $repo 'flow.tcl'),(Join-Path $repo 'HDMI_DDR3_OV5640.pds'))
function Hashes { @($inputs | ForEach-Object {
    [pscustomobject]@{Path=$_;SHA256=(Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash}
}) }
function Save-Json($Name,$Value) {
    ConvertTo-Json -InputObject $Value -Depth 8 |
        Set-Content -LiteralPath (Join-Path $run $Name) -Encoding utf8
}
[IO.Directory]::CreateDirectory($run)|Out-Null
$before=Hashes
Save-Json 'inputs_before.json' $before
$result=[ordered]@{Verdict='ERROR';Error=$null;RunDirectory=$run;TestLevel='RTL simulation'
    ProductionNativeControllers=$true;ProductionLineRAM=$true;PhysicalDDRPHY=$false;BoardTest=$false}
$commands=[Collections.Generic.List[object]]::new()
function Invoke-Tool($Name,[string[]]$Arguments,$Log) {
    & (Join-Path $ModelSim $Name) @Arguments *> (Join-Path $run $Log)
    $code=$LASTEXITCODE
    $commands.Add([pscustomobject]@{Tool=$Name;Arguments=$Arguments;ExitCode=$code;Log=$Log})
    if($code -ne 0) {throw "$Name failed ($code), see $Log"}
}
Write-Output "RTL run directory: $run"
Push-Location $run
try {
    Invoke-Tool 'vlog.exe' @('-version') 'version.log'
    Invoke-Tool 'vlib.exe' @('work') 'library.log'
    Invoke-Tool 'vlog.exe' (@('-sv','-work','work')+$sources+
        @('-y',$PrimitiveLibrary,'+libext+.v')) 'compile.log'
    Invoke-Tool 'vsim.exe' @('-c','-t','1ps','-lib','work','ownership_owner_tb',
        '-do','onerror {quit -code 2}; run -all; quit -code 0','-l','unit.log') 'unit.console.log'
    $unit=Get-Content -LiteralPath (Join-Path $run 'unit.log') -Raw
    if($unit -match '\*\* (Error|Fatal):' -or $unit -notmatch 'OWNERSHIP_UNIT_RESULT checks=\d+ errors=0') {
        throw 'Owner directed regression failed.'
    }
    Invoke-Tool 'vsim.exe' @('-c','-t','1ps','-lib','work','ownership_full_frame_tb',
        '-do','onerror {quit -code 2}; run -all; quit -code 0','-l','simulation.log') 'console.log'
    $text=Get-Content -LiteralPath (Join-Path $run 'simulation.log') -Raw
    if($text -match '\*\* (Error|Fatal):') {throw 'Simulation assertion failed.'}
    if($text -notmatch 'OWNERSHIP_FULL_RESULT frames=6 pixels=5529600 .*published=3 rejected=1 errors=0') {
        throw 'Missing full-raster acceptance totals.'
    }
    $result.Verdict='PASS'
} catch {
    $result.Error=$_.Exception.Message
} finally {
    Pop-Location
    $after=Hashes
    Save-Json 'inputs_after.json' $after
    $result.InputsUnchanged=@(Compare-Object $before $after -Property Path,SHA256).Count -eq 0
    if(-not $result.InputsUnchanged) {$result.Verdict='INVALID_INPUT_CHANGED'}
    Save-Json 'commands.json' @($commands.ToArray())
    Save-Json 'result.json' $result
}
$result|ConvertTo-Json -Depth 8
if($result.Verdict -ne 'PASS') {exit 1}
