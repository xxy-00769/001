param(
    [Parameter(Mandatory=$true)][string]$SimulationResult,
    [string]$VerifyCompletedRun,
    [ValidatePattern('^[A-Za-z0-9_]+$')][string]$ReleaseName = 'V1_clean_color_cmos1',
    [string]$OutputParent = 'E:\FPGA drive\tmp\s4_clean_video_build',
    [string]$Pds = 'D:\PDS\PDS_2022.2-SP6.1\bin\pds_shell.exe'
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$sim = Get-Content -LiteralPath $SimulationResult -Raw | ConvertFrom-Json
if ($sim.Verdict -ne 'PASS' -or -not $sim.InputsUnchanged) { throw 'Completed RTL PASS evidence required.' }
$simInputs = Get-Content -LiteralPath (Join-Path (Split-Path $SimulationResult -Parent) 'inputs_after.json') -Raw | ConvertFrom-Json
foreach ($input in $simInputs) {
    if ((Get-FileHash -LiteralPath $input.Path -Algorithm SHA256).Hash -ne $input.SHA256) {
        throw "Simulation input changed: $($input.Path)"
    }
}
if (-not (Test-Path -LiteralPath $Pds)) { throw 'PDS executable unavailable.' }
function Save-Json($Name,$Value) {
    ConvertTo-Json -InputObject $Value -Depth 10 | Set-Content -LiteralPath (Join-Path $run $Name) -Encoding utf8
}
if ($VerifyCompletedRun) {
    $run = [IO.Path]::GetFullPath($VerifyCompletedRun)
    $allowed = [IO.Path]::GetFullPath((Join-Path (Split-Path $repo -Parent) 'tmp'))
    if (-not $run.StartsWith($allowed + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Completed build must remain under workspace tmp.'
    }
    $recipe = Get-Content -LiteralPath (Join-Path $run 'recipe.json') -Raw | ConvertFrom-Json
    $manifest = @(Get-Content -LiteralPath (Join-Path $run 'inputs.json') -Raw | ConvertFrom-Json)
    $previous = Get-Content -LiteralPath (Join-Path $run 'result.json') -Raw | ConvertFrom-Json
    $simEvidence = Get-Content -LiteralPath (Join-Path $run 'simulation_evidence.json') -Raw | ConvertFrom-Json
    if ($previous.ProcessExitCode -ne 0 -or $recipe.Project -ne $repo -or
        $simEvidence.SHA256 -ne (Get-FileHash -LiteralPath $SimulationResult -Algorithm SHA256).Hash) {
        throw 'Completed-run identity or successful PDS process evidence does not match.'
    }
    $verifyStamp = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
    $previousResult = Join-Path $run "result_before_verification_$verifyStamp.json"
    if (Test-Path -LiteralPath $previousResult) { throw 'Verification evidence already exists.' }
    Copy-Item -LiteralPath (Join-Path $run 'result.json') -Destination $previousResult
    [ordered]@{ Mode='Verify completed build only'; PdsRerun=$false
        PreviousResult=$previousResult; VerifiedUtc=[DateTime]::UtcNow.ToString('o')
        VerificationScriptSHA256=(Get-FileHash -LiteralPath $PSCommandPath -Algorithm SHA256).Hash } |
        ConvertTo-Json | Set-Content -LiteralPath (Join-Path $run 'verification.json') -Encoding utf8
} else {
$source = Join-Path $repo 'source'
if (@(Get-ChildItem -LiteralPath $source -Recurse -Force |
    Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }).Count -ne 0) {
    throw 'Source tree contains a directory link; refuse unbounded copy.'
}
$stamp = (Get-Date -Format 'yyyyMMdd_HHmmss_fff') + '_' + [Guid]::NewGuid().ToString('N').Substring(0,8)
$run = [IO.Path]::GetFullPath((Join-Path $OutputParent $stamp))
$allowed = [IO.Path]::GetFullPath((Join-Path (Split-Path $repo -Parent) 'tmp'))
if (-not $run.StartsWith($allowed + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Build outputs must remain under workspace tmp.'
}
if (Test-Path -LiteralPath $run) { throw 'Build directory already exists.' }
[IO.Directory]::CreateDirectory($run) | Out-Null
$paths = @(Get-ChildItem -LiteralPath $source -Recurse -File | Select-Object -ExpandProperty FullName)
$paths += @('flow.tcl','hdmi_ddr_ov5640_top.fdc','HDMI_DDR3_OV5640.pds') |
    ForEach-Object { Join-Path $repo $_ }
$manifest = @($paths | ForEach-Object {
    $item = Get-Item -LiteralPath $_
    [pscustomobject]@{ Source=$item.FullName; RelativePath=[IO.Path]::GetRelativePath($repo,$item.FullName)
        Size=$item.Length; SHA256=(Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash }
})
$bytes = ($manifest | Measure-Object Size -Sum).Sum
$drive = Get-PSDrive -Name ([IO.Path]::GetPathRoot($run).TrimEnd('\',':'))
if ($drive.Free -lt ($bytes + 2GB)) { throw 'Less than 2 GB free beyond input copy size.' }
foreach ($item in $manifest) {
    $dest = Join-Path $run $item.RelativePath
    [IO.Directory]::CreateDirectory((Split-Path $dest -Parent)) | Out-Null
    Copy-Item -LiteralPath $item.Source -Destination $dest
    if ((Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash -ne $item.SHA256) {
        throw "Input copy mismatch: $($item.RelativePath)"
    }
}
Save-Json 'inputs.json' $manifest
Save-Json 'simulation_evidence.json' ([ordered]@{
    Path=[IO.Path]::GetFullPath($SimulationResult)
    SHA256=(Get-FileHash -LiteralPath $SimulationResult -Algorithm SHA256).Hash; Result=$sim
})
Copy-Item -LiteralPath (Join-Path $repo 'flow.tcl') -Destination (Join-Path $run 'build.tcl')
$recipe = [ordered]@{
    Project=$repo; RunDirectory=$run; Top='hdmi_ddr_ov5640_top'; SourceCopyBytes=$bytes
    HEAD=(& git --no-optional-locks -C $repo rev-parse HEAD)
    Tool=$Pds; Arguments=@('-file','build.tcl','-continue')
    FlowTemplateSHA256=(Get-FileHash -LiteralPath (Join-Path $run 'flow.tcl') -Algorithm SHA256).Hash
    BuildScriptInitialSHA256=(Get-FileHash -LiteralPath (Join-Path $run 'build.tcl') -Algorithm SHA256).Hash
    StartedUtc=[DateTime]::UtcNow.ToString('o'); Programmed=$false; FlashWritten=$false
}
Save-Json 'recipe.json' $recipe
& git --no-optional-locks -C $repo diff --binary --no-ext-diff |
    Set-Content -LiteralPath (Join-Path $run 'worktree.patch') -Encoding utf8
}
$result = [ordered]@{
    RunDirectory=$run; Verdict='ERROR'; Error=$null; ProcessExitCode=$null
    Compile=$false; Synthesis=$false; Mapping=$false; PlaceRoute=$false
    TimingReport=$false; ExistingConstraintsMet=$false; FullIOSignoff=$false
    Bitstream=$false; Programmed=$false; FlashWritten=$false
}
Write-Output "PDS build / verification directory: $run"
Push-Location $run
try {
    if ($VerifyCompletedRun) {
        $result.ProcessExitCode=$previous.ProcessExitCode
    } else {
        & $Pds -file build.tcl -continue *> (Join-Path $run 'pds_console.log')
        $result.ProcessExitCode=$LASTEXITCODE
    }
    if ($result.ProcessExitCode -ne 0) { throw "PDS exited $($result.ProcessExitCode)." }
    $console=Get-Content -LiteralPath (Join-Path $run 'pds_console.log') -Raw
    if ($console -match '(?im)^\s*(?:E:|\*\* (?:Error|Fatal):)|Program Error') {
        throw 'PDS console contains an error despite its process exit status.'
    }
    $required=[ordered]@{
        Compile='compile\hdmi_ddr_ov5640_top_comp.adf'
        Synthesis='synthesize\hdmi_ddr_ov5640_top_syn.adf'
        Mapping='device_map\hdmi_ddr_ov5640_top_map.adf'
        PlaceRoute='place_route\hdmi_ddr_ov5640_top_pnr.adf'
        TimingReport='report_timing\hdmi_ddr_ov5640_top.rtr'
        Bitstream='generate_bitstream\hdmi_ddr_ov5640_top.sbit'
    }
    foreach ($key in $required.Keys) {
        $path=Join-Path $run $required[$key]
        $result[$key]=(Test-Path -LiteralPath $path) -and (Get-Item -LiteralPath $path).Length -gt 0
        if (-not $result[$key]) { throw "Missing completed stage artifact: $key" }
    }
    $timing=Get-Content -LiteralPath (Join-Path $run $required.TimingReport) -Raw
    $result.ExistingConstraintsMet=$timing -match 'Design Summary\s*:\s*All Constraints Met\.'
    if (-not $result.ExistingConstraintsMet) { throw 'Current routed timing report does not meet existing constraints.' }
    $bit=Get-Item -LiteralPath (Join-Path $run $required.Bitstream)
    if ($bit.LastWriteTimeUtc -lt [DateTimeOffset]::Parse($recipe.StartedUtc).UtcDateTime) {
        throw 'Bitstream predates this build.'
    }
    $result.Verdict='PASS'
} catch {
    $result.Error=$_.Exception.Message
} finally {
    Pop-Location
    $sourceChanges=@($manifest | Where-Object {
        (Get-FileHash -LiteralPath $_.Source -Algorithm SHA256).Hash -ne $_.SHA256
    } | Select-Object -ExpandProperty RelativePath)
    $copyChanges=@($manifest | Where-Object {
        (Get-FileHash -LiteralPath (Join-Path $run $_.RelativePath) -Algorithm SHA256).Hash -ne $_.SHA256
    } | Select-Object -ExpandProperty RelativePath)
    # PDS may update its copied project metadata; source, IP, constraints and
    # the original flow template must remain bit-for-bit identical.
    $designChanges=@($copyChanges | Where-Object { $_ -ne 'HDMI_DDR3_OV5640.pds' })
    $result.OriginalInputsUnchanged=$sourceChanges.Count -eq 0
    $result.CopiedDesignInputsUnchanged=$designChanges.Count -eq 0
    Save-Json 'input_changes.json' ([ordered]@{Original=$sourceChanges;Copied=$copyChanges})
    if (-not $result.OriginalInputsUnchanged -or -not $result.CopiedDesignInputsUnchanged) {
        $result.Verdict='INVALID_INPUT_CHANGED'
    }
    $result.FinishedUtc=[DateTime]::UtcNow.ToString('o')
    if ($result.Verdict -eq 'PASS') {
        $release=Join-Path $run "$ReleaseName.sbit"
        Copy-Item -LiteralPath (Join-Path $run 'generate_bitstream\hdmi_ddr_ov5640_top.sbit') -Destination $release
        Save-Json 'release.json' ([ordered]@{
            Name=$ReleaseName; Path=$release; Size=(Get-Item -LiteralPath $release).Length
            SHA256=(Get-FileHash -LiteralPath $release -Algorithm SHA256).Hash
            SourceManifest='inputs.json'; Recipe='recipe.json'; Simulation='simulation_evidence.json'
            Timing='report_timing/hdmi_ddr_ov5640_top.rtr'; BoardTest=$false
            FullIOSignoff=$false; Programmed=$false; FlashWritten=$false
        })
    }
    Save-Json 'result.json' $result
}
$result | ConvertTo-Json -Depth 8
if ($result.Verdict -ne 'PASS') { exit 1 }
