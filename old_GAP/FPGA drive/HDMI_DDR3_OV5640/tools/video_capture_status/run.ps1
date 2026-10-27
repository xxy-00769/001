param(
    [string]$OutputParent = 'E:\FPGA drive\tmp\video_capture_status',
    [string]$ModelSim = 'D:\PDS\Modelsim\win64'
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$run=[IO.Path]::GetFullPath((Join-Path $OutputParent (
    (Get-Date -Format 'yyyyMMdd_HHmmss_fff')+'_'+[Guid]::NewGuid().ToString('N').Substring(0,8))))
$allowed=[IO.Path]::GetFullPath((Join-Path (Split-Path $repo -Parent) 'tmp'))
if (-not $run.StartsWith($allowed+'\',[StringComparison]::OrdinalIgnoreCase) -or
    (Test-Path -LiteralPath $run)) { throw 'Unique workspace tmp output required.' }
$sources=@('video_capture_status.v','img_proc.v','lane_detect.v','zebra_detect.v',
    'zebra_overlay.v','lane_geometry.v','adas_overlay.v') |
    ForEach-Object {Join-Path $repo "source\rtl\$_"}
$sources+=@('capture_status_tb.sv','full_color_tb.sv','recovery_color_tb.sv') |
    ForEach-Object {Join-Path $PSScriptRoot $_}
$inputs=@($sources)+@($PSCommandPath,(Join-Path $repo 'source\rtl\hdmi_ddr_ov5640_top.v'),
    (Join-Path $repo 'flow.tcl'),(Join-Path $repo 'HDMI_DDR3_OV5640.pds'))
function Hashes { @($inputs | ForEach-Object {
    [pscustomobject]@{Path=$_;SHA256=(Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash}
}) }
function Save-Json($Name,$Value) {
    ConvertTo-Json -InputObject $Value -Depth 8 |
        Set-Content -LiteralPath (Join-Path $run $Name) -Encoding utf8
}
foreach($name in @('vlib.exe','vlog.exe','vsim.exe','vmap.exe')) {
    if(-not(Test-Path -LiteralPath (Join-Path $ModelSim $name))) {throw "Missing $name"}
}
[IO.Directory]::CreateDirectory($run) | Out-Null
$before=Hashes
Save-Json 'inputs_before.json' $before
$commands=[Collections.Generic.List[object]]::new()
$cases=[Collections.Generic.List[object]]::new()
$result=[ordered]@{Verdict='ERROR';Error=$null;RunDirectory=$run;TestLevel='RTL simulation'
    FullDDRControllerPHY=$false;Synthesis=$false;BoardTest=$false}
function Invoke-Tool($Name,[string[]]$Arguments,$Log) {
    & (Join-Path $ModelSim $Name) @Arguments *> (Join-Path $run $Log)
    $code=$LASTEXITCODE
    $commands.Add([pscustomobject]@{Tool=$Name;Arguments=$Arguments;ExitCode=$code;Log=$Log})
    if($code -ne 0) {throw "$Name failed ($code), see $Log"}
}
Push-Location $run
try {
    Invoke-Tool 'vlog.exe' @('-version') 'version.log'
    Invoke-Tool 'vlib.exe' @('work') 'library.log'
    Invoke-Tool 'vlog.exe' (@('-sv','-work','work')+$sources) 'compile.log'
    foreach($case in @('capture_status_tb','capture_full_color_tb','capture_recovery_color_tb')) {
        $dir=Join-Path $run $case
        [IO.Directory]::CreateDirectory($dir) | Out-Null
        Push-Location $dir
        try {
            Invoke-Tool 'vmap.exe' @('-c') "$case.config.log"
            Invoke-Tool 'vmap.exe' @('work',(Join-Path $run 'work')) "$case.map.log"
            Invoke-Tool 'vsim.exe' @('-c','-t','1ps','-lib','work',$case,
                '-do','onerror {quit -code 2}; run -all; quit -code 0',
                '-l',(Join-Path $dir 'simulation.log')) "$case.console.log"
        } finally {Pop-Location}
        $text=Get-Content -LiteralPath (Join-Path $dir 'simulation.log') -Raw
        if($text -match '\*\* (Error|Fatal):') {throw "$case simulator assertion failed."}
        if($case -eq 'capture_status_tb') {
            $match=[regex]::Match($text,'CAPTURE_STATUS_RESULT checks=(\d+) reports=(\d+) errors=0')
            if(-not $match.Success -or [int]$match.Groups[1].Value -lt 150) {
                throw 'Missing or incomplete directed status results.'
            }
            $cases.Add([pscustomobject]@{Name=$case;Verdict='PASS';
                Checks=[int]$match.Groups[1].Value;Reports=[int]$match.Groups[2].Value})
        } elseif($case -eq 'capture_full_color_tb') {
            if($text -notmatch 'CAPTURE_COLOR_RESULT frames=3 reports=3 pixels=2764800 errors=0') {
                throw 'Missing full 720p color/metadata result.'
            }
            $cases.Add([pscustomobject]@{Name=$case;Verdict='PASS';Frames=3;Pixels=2764800})
        } else {
            $match=[regex]::Match($text,'CAPTURE_RECOVERY_RESULT frames=(\d+) pixels=(\d+) errors=0')
            if(-not $match.Success -or [int]$match.Groups[1].Value -lt 6) {
                throw 'Missing integrated recovery results.'
            }
            $cases.Add([pscustomobject]@{Name=$case;Verdict='PASS';Frames=[int]$match.Groups[1].Value;
                Pixels=[int]$match.Groups[2].Value;IncludesPreResetPartialPixels=$true})
        }
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
    $result.Cases=@($cases.ToArray())
    Save-Json 'commands.json' @($commands.ToArray())
    Save-Json 'result.json' $result
}
$result | ConvertTo-Json -Depth 8
if($result.Verdict -ne 'PASS') {exit 1}
