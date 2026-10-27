param(
    [string]$ReuseVideoEvidence,
    [string]$OutputParent='E:\FPGA drive\tmp\video_modes',
    [string]$ModelSim='D:\PDS\Modelsim\win64',
    [string]$PrimitiveLibrary='D:\PDS\PDS_2022.2-SP6.1\arch\vendor\pango\verilog\simulation'
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$run=[IO.Path]::GetFullPath((Join-Path $OutputParent (
    (Get-Date -Format 'yyyyMMdd_HHmmss_fff')+'_'+[Guid]::NewGuid().ToString('N').Substring(0,8))))
$allowed=[IO.Path]::GetFullPath((Join-Path (Split-Path $repo -Parent) 'tmp'))
if(-not $run.StartsWith($allowed+'\',[StringComparison]::OrdinalIgnoreCase) -or
    (Test-Path -LiteralPath $run)) {throw 'Unique workspace tmp output required.'}
$sources=@('video_mode_key.v','video_capture_status.v','img_proc.v','lane_detect.v','zebra_detect.v',
    'zebra_overlay.v','lane_geometry.v','adas_overlay.v','frame_buffer_owner.v',
    'fram_buf.v','wr_buf.v','rd_buf.v','wr_rd_ctrl_top.v','wr_cmd_trans.v','wr_ctrl.v','rd_ctrl.v',
    'wr_fram_buf/wr_fram_buf.v','wr_fram_buf/rtl/ipml_sdpram_v1_6_wr_fram_buf.v',
    'rd_fram_buf/rd_fram_buf.v','rd_fram_buf/rtl/ipml_sdpram_v1_6_rd_fram_buf.v') |
    ForEach-Object {Join-Path $repo "source\rtl\$_"}
$sources+=@('key_tb.sv','video_tb.sv') | ForEach-Object {Join-Path $PSScriptRoot $_}
$sources+=Join-Path $repo 'tools/frame_ownership/full_frame_tb.sv'
$inputs=@($sources)+@($PSCommandPath,
    (Join-Path $PrimitiveLibrary 'GTP_GRS.v'),(Join-Path $PrimitiveLibrary 'GTP_DRM18K.v'),
    (Join-Path $repo 'source/rtl/hdmi_ddr_ov5640_top.v'),
    (Join-Path $repo 'hdmi_ddr_ov5640_top.fdc'),
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
    PhysicalDDRPHY=$false;BoardTest=$false}
$commands=[Collections.Generic.List[object]]::new()
$cases=[Collections.Generic.List[object]]::new()
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
    if($ReuseVideoEvidence) {
        $prior=Get-Content -LiteralPath $ReuseVideoEvidence -Raw | ConvertFrom-Json
        if($prior.Verdict -ne 'PASS' -or -not $prior.InputsUnchanged) {
            throw 'Reusable video/DDR run must have completed PASS with stable inputs.'
        }
        $priorDir=Split-Path ([IO.Path]::GetFullPath($ReuseVideoEvidence)) -Parent
        $priorInputs=@(Get-Content -LiteralPath (Join-Path $priorDir 'inputs_after.json') -Raw |
            ConvertFrom-Json)
        # Only the key module/driver may change. Neither image nor DDR bench
        # instantiates the key module; both still run on identical input hashes.
        foreach($entry in $before) {
            if($entry.Path -eq $PSCommandPath -or
                $entry.Path -eq (Join-Path $repo 'source/rtl/video_mode_key.v')) {continue}
            $match=@($priorInputs | Where-Object {$_.Path -eq $entry.Path -and $_.SHA256 -eq $entry.SHA256})
            if($match.Count -ne 1) {throw "Cannot reuse changed video/DDR dependency: $($entry.Path)"}
        }
        $result.ReusedVideoEvidence=[IO.Path]::GetFullPath($ReuseVideoEvidence)
    }
    $expected=[ordered]@{
        video_modes_key_tb='KEY_RESULT checks=\d+ errors=0'
        video_modes_frame_tb='VIDEO_MODES_RESULT frames=8 pixels=7372800 clean_pixels=7372800 errors=0'
        ownership_full_frame_tb='OWNERSHIP_FULL_RESULT frames=6 pixels=5529600 .*published=3 rejected=1 errors=0'
    }
    foreach($case in $expected.Keys) {
        if($ReuseVideoEvidence -and $case -ne 'video_modes_key_tb') {
            $oldCase=@($prior.Cases | Where-Object {$_.Name -eq $case -and $_.Verdict -eq 'PASS'})
            if($oldCase.Count -ne 1) {throw "Reusable case absent: $case"}
            $log=Join-Path $priorDir "$case.log"
            $text=Get-Content -LiteralPath $log -Raw
            if($text -match '\*\* (Error|Fatal):' -or $text -notmatch $expected[$case]) {
                throw "Reusable case log invalid: $case"
            }
            $cases.Add([pscustomobject]@{Name=$case;Verdict='PASS';Reused=$true;Log=$log
                LogSHA256=(Get-FileHash -LiteralPath $log -Algorithm SHA256).Hash})
            Save-Json 'cases.json' @($cases.ToArray())
            continue
        }
        $arguments=@('-c','-t','1ps','-lib','work',$case)
        if($case -eq 'ownership_full_frame_tb') { $arguments+='-gDISPLAY_PATH=1' }
        Invoke-Tool 'vsim.exe' ($arguments+@(
            '-do','onerror {quit -code 2}; run -all; quit -code 0',
            '-l',"$case.log")) "$case.console.log"
        $text=Get-Content -LiteralPath (Join-Path $run "$case.log") -Raw
        if($text -match '\*\* (Error|Fatal):' -or $text -notmatch $expected[$case]) {
            throw "Missing or failed acceptance: $case"
        }
        $cases.Add([pscustomobject]@{Name=$case;Verdict='PASS';Log="$case.log"})
        Save-Json 'cases.json' @($cases.ToArray())
    }
    $top=Get-Content -LiteralPath (Join-Path $repo 'source/rtl/hdmi_ddr_ov5640_top.v') -Raw
    foreach($connection in @('wr_fsync\s*\(\s*proc_vs\s*\)','wr_en\s*\(\s*proc_de\s*\)',
        'wr_data\s*\(\s*proc_rgb\s*\)','wr_frame_id\s*\(\s*display_frame_id\s*\)',
        'wr_frame_time\s*\(\s*display_frame_time\s*\)','key_n\s*\(\s*key8_n\s*\)')) {
        if($top -notmatch $connection) {throw "Top connection absent: $connection"}
    }
    $fdc=Get-Content -LiteralPath (Join-Path $repo 'hdmi_ddr_ov5640_top.fdc') -Raw
    if(([regex]::Matches($fdc,'\{PAP_IO_LOC\}\s*\{H17\}')).Count -ne 1 -or
        $fdc -notmatch '\{p:key8_n\}\s*\{PAP_IO_LOC\}\s*\{H17\}') {throw 'KEY8 pin binding conflict'}
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
$result|ConvertTo-Json -Depth 8
if($result.Verdict -ne 'PASS') {exit 1}
