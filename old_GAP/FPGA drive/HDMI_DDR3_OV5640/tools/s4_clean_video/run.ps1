param(
    [string]$OutputParent = 'E:\FPGA drive\tmp\s4_clean_video',
    [string]$ModelSim = 'D:\PDS\Modelsim\win64'
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$stamp = (Get-Date -Format 'yyyyMMdd_HHmmss_fff') + '_' + [Guid]::NewGuid().ToString('N').Substring(0,8)
$run = [IO.Path]::GetFullPath((Join-Path $OutputParent $stamp))
$allowed = [IO.Path]::GetFullPath((Join-Path (Split-Path $repo -Parent) 'tmp'))
if (-not $run.StartsWith($allowed + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Outputs must remain under workspace tmp.'
}
if (Test-Path -LiteralPath $run) { throw 'Output directory already exists.' }
$sources = @('img_proc.v','lane_detect.v','zebra_detect.v','zebra_overlay.v','lane_geometry.v','adas_overlay.v') |
    ForEach-Object { Join-Path $repo "source\rtl\$_" }
$sources += (Join-Path $PSScriptRoot 'clean_video_tb.sv')
$sources += (Join-Path $repo 'tests\img_proc_frame_tb.v')
$inputs = @($sources) + @($PSCommandPath, (Join-Path $repo 'source\rtl\hdmi_ddr_ov5640_top.v'))
function Hashes {
    @($inputs | ForEach-Object { [pscustomobject]@{
        Path=$_; SHA256=(Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash
    } })
}
function Save-Json($Name,$Value) {
    ConvertTo-Json -InputObject $Value -Depth 8 | Set-Content -LiteralPath (Join-Path $run $Name) -Encoding utf8
}
foreach ($name in @('vlib.exe','vlog.exe','vsim.exe','vmap.exe')) {
    if (-not (Test-Path -LiteralPath (Join-Path $ModelSim $name))) { throw "Missing simulator: $name" }
}
[IO.Directory]::CreateDirectory($run) | Out-Null
$before = Hashes
Save-Json 'inputs_before.json' $before
$commands = [Collections.Generic.List[object]]::new()
$cases = [Collections.Generic.List[object]]::new()
$result = [ordered]@{ TestLevel='RTL simulation'; RunDirectory=$run; Verdict='ERROR'; Error=$null
    Synthesis=$false; BoardTest=$false; FullDDRControllerPHY=$false }
function Invoke-Tool([string]$Name,[string[]]$Arguments,[string]$Log) {
    $start = [DateTime]::UtcNow
    & (Join-Path $ModelSim $Name) @Arguments *> (Join-Path $run $Log)
    $code = $LASTEXITCODE
    $commands.Add([pscustomobject]@{ Tool=$Name; Arguments=$Arguments; WorkingDirectory=(Get-Location).Path
        StartedUtc=$start.ToString('o'); FinishedUtc=[DateTime]::UtcNow.ToString('o'); ExitCode=$code; Log=$Log })
    if ($code -ne 0) { throw "$Name exited $code; see $Log" }
}
Push-Location $run
try {
    Invoke-Tool 'vlog.exe' @('-version') 'version.log'
    Invoke-Tool 'vlib.exe' @('work') 'library.log'
    Invoke-Tool 'vlog.exe' (@('-sv','-work','work') + $sources) 'compile.log'
    foreach ($case in @('s4_clean_fullframe_tb','s4_clean_diagnostics_tb','img_proc_early_sync_tb')) {
        $dir = Join-Path $run $case
        [IO.Directory]::CreateDirectory($dir) | Out-Null
        Push-Location $dir
        try {
            Invoke-Tool 'vmap.exe' @('-c') "$case.library_config.log"
            Invoke-Tool 'vmap.exe' @('work',(Join-Path $run 'work')) "$case.library_map.log"
            Invoke-Tool 'vsim.exe' @('-c','-t','1ps','-lib','work',$case,
                '-do','onerror {quit -code 2}; run -all; quit -code 0',
                '-l',(Join-Path $dir 'simulation.log')) "$case.console.log"
        } finally { Pop-Location }
        $text = Get-Content -LiteralPath (Join-Path $dir 'simulation.log') -Raw
        if ($text -match '\*\* (Error|Fatal):') { throw "${case}: simulator Error/Fatal." }
        if ($case -eq 'img_proc_early_sync_tb') {
            if ($text -notmatch 'PASS: 49920 unchanged pixels across 3 frames') {
                throw 'Legacy early-sync smoke test did not complete.'
            }
            $cases.Add([pscustomobject]@{ Name=$case; Verdict='PASS'; Frames=3; Pixels=49920 })
        } else {
            $m = [regex]::Match($text,'S4_RESULT frames=(\d+) pixels=(\d+) errors=(\d+) reset_checks=(\d+) diagnostic_changes=(\d+)')
            if (-not $m.Success) { throw "Missing result: $case" }
            $frames=[int]$m.Groups[1].Value; $pixels=[int]$m.Groups[2].Value
            $expectedFrames=if ($case -eq 's4_clean_fullframe_tb') {6} else {2}
            $expectedPixels=if ($case -eq 's4_clean_fullframe_tb') {5529600} else {184320}
            if ($frames -ne $expectedFrames -or $pixels -ne $expectedPixels -or [int]$m.Groups[3].Value -ne 0) {
                throw "Unexpected totals: $case"
            }
            $cases.Add([pscustomobject]@{ Name=$case; Verdict='PASS'; Frames=$frames; Pixels=$pixels
                PixelErrors=[int]$m.Groups[3].Value; ResetChecks=[int]$m.Groups[4].Value
                DiagnosticChangedPixels=[int]$m.Groups[5].Value })
        }
        Save-Json 'cases.json' @($cases.ToArray())
    }
    $top = Get-Content -LiteralPath (Join-Path $repo 'source\rtl\hdmi_ddr_ov5640_top.v') -Raw
    foreach ($connection in @('wr_fsync\s*\(\s*clean_vs\s*\)','wr_en\s*\(\s*clean_de\s*\)','wr_data\s*\(\s*clean_rgb\s*\)')) {
        if ($top -notmatch $connection) { throw "Clean DDR binding missing: $connection" }
    }
    $result.Verdict='PASS'
} catch {
    $result.Error=$_.Exception.Message
} finally {
    Pop-Location
    $after = Hashes
    Save-Json 'inputs_after.json' $after
    $result.InputsUnchanged=@(Compare-Object $before $after -Property Path,SHA256).Count -eq 0
    if (-not $result.InputsUnchanged) { $result.Verdict='INVALID_INPUT_CHANGED' }
    $result.Cases=@($cases.ToArray())
    Save-Json 'commands.json' @($commands.ToArray())
    Save-Json 'result.json' $result
}
$result | ConvertTo-Json -Depth 8
if ($result.Verdict -ne 'PASS') { exit 1 }
