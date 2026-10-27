# Validate existing evidence and probe JTAG; never program the board.
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$archive = Join-Path $root 'experiments/v8_adas_camera_20261017'
$tool = 'D:/PDS/PDS_2022.2-SP6.1/bin/cdt_cfg_shell.exe'
$run = Join-Path $PSScriptRoot ('runs/' + (Get-Date -Format 'yyyyMMdd_HHmmss_fff'))
$null = New-Item -ItemType Directory -Path $run
$probe = Join-Path $run 'probe.tcl'
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'probe.tcl') -Destination $probe
$result = [ordered]@{
    started_at = (Get-Date -Format o)
    goal = 'Existing v8 single-camera on-board acceptance'
    archive_files_verified = 0
    shared_ip_files_verified = 0
    named_artifacts_verified = $false
    jtag_probe_attempted = $false
    jtag_probe_passed = $false
    configuration_done = $null
    configuration_error_flags_clear = $null
    running_bitstream_identified = $false
    camera_display_observed = $false
    five_minute_stability_passed = $null
    camera_scene_acceptance_passed = $null
    stage_acceptance_passed = $false
    new_bitstream = $false
    board_programmed = $false
    flash_written = $false
    errors = @()
}
try {
    foreach ($entry in @(
        @{ Directory = $archive; Manifest = 'SHA256SUMS.csv'; Field = 'archive_files_verified' },
        @{ Directory = $root; Manifest = 'IP_SHA256SUMS.csv'; Field = 'shared_ip_files_verified' }
    )) {
        foreach ($row in (Import-Csv -LiteralPath (Join-Path $archive $entry.Manifest))) {
            $path = Join-Path $entry.Directory $row.Path
            if (!(Test-Path -LiteralPath $path -PathType Leaf)) {
                throw "Manifest file missing: $($row.Path)"
            }
            if ((Get-Item -LiteralPath $path).Length -ne [long]$row.Bytes -or
                (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $row.SHA256) {
                throw "Manifest mismatch: $($row.Path)"
            }
            $result[$entry.Field]++
        }
    }
    $artifacts = @(
        @{ Name = '8_adas_lane_status_cmos1.sbit'; Hash = '4714B2F26E2E71DE27627A709C23DAF98818421613F850F97BBE73C8A8772573' },
        @{ Name = '4_road_markings_filtered_cmos1.sbit'; Hash = 'ED53C960F810528BEC0A641565A00B1A6FED9C2E6FCFAEDAC1AF64F32D613467' }
    )
    $artifactEvidence = foreach ($item in $artifacts) {
        $path = Join-Path $root ('bitstreams/' + $item.Name)
        $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        if ($hash -ne $item.Hash) { throw "Named artifact mismatch: $($item.Name)" }
        [ordered]@{ path = $path; bytes = (Get-Item -LiteralPath $path).Length; sha256 = $hash }
    }
    $result['artifacts'] = @($artifactEvidence)
    $result.named_artifacts_verified = $true
    if (!(Test-Path -LiteralPath $tool -PathType Leaf)) { throw 'Configuration tool missing.' }
    $result.jtag_probe_attempted = $true
    $log = Join-Path $run 'probe.log'
    $stderr = Join-Path $run 'probe.stderr.log'
    $process = Start-Process -FilePath $tool -WorkingDirectory $run `
        -ArgumentList '-file', 'probe.tcl' -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput $log -RedirectStandardError $stderr
    if (!$process.WaitForExit(60000)) {
        $process.Kill()
        $process.WaitForExit()
        throw 'Read-only probe timed out; no automatic retry.'
    }
    $text = Get-Content -Raw -LiteralPath $log
    $errorText = Get-Content -Raw -LiteralPath $stderr
    if ($process.ExitCode -ne 0 -or $errorText -or $text -match '(?m)^\s*E:' -or
        !$text.Contains('V8_ACCEPTANCE_PROBE_FINISHED') -or
        $text -notmatch 'The ID value is: 0x00521899\b' -or
        ([regex]::Matches($text, '(?m)^PGL50H\s*$')).Count -ne 1) {
        throw 'Read-only probe did not confirm one PGL50H; inspect retained logs.'
    }
    $result.jtag_probe_passed = $true
    $result.configuration_done = [bool]($text -match '(?m)^Bit\s+\d+:\s+1\s+done\s*$')
    $clear = $true
    foreach ($bit in @('over_temp', 'overflow', 'timeout', 'rbcrc_err', 'crc_err', 'id_err')) {
        if ($text -notmatch ('(?m)^Bit\s+\d+:\s+0\s+' + $bit + '\s*$')) { $clear = $false }
    }
    $result.configuration_error_flags_clear = $clear
    # ID/DONE cannot identify a bitstream or establish a camera/display verdict.
} catch {
    $result.errors += $_.Exception.Message
} finally {
    $result['completed_at'] = Get-Date -Format o
    $result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $run 'result.json') -Encoding utf8
}
$result | ConvertTo-Json -Depth 6
Write-Output "EVIDENCE_DIRECTORY: $run"
if ($result.errors.Count -gt 0) { exit 1 }
