# Explicit v4 restoration, not a semantic-model release/build command.
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$scriptRoot = $PSScriptRoot
$tool = 'D:/PDS/PDS_2022.2-SP6.1/bin/cdt_cfg_shell.exe'
$bitstream = Join-Path $root 'bitstreams/4_road_markings_filtered_cmos1.sbit'
$expected = 'ED53C960F810528BEC0A641565A00B1A6FED9C2E6FCFAEDAC1AF64F32D613467'
$hash = (Get-FileHash -LiteralPath $bitstream -Algorithm SHA256).Hash
if ($hash -ne $expected) { throw 'Named baseline hash mismatch; refusing to program.' }
if (!(Test-Path -LiteralPath $tool -PathType Leaf)) { throw 'Missing PDS configuration tool.' }
$run = Join-Path $scriptRoot ('runs/' + (Get-Date -Format 'yyyyMMdd_HHmmss_fff'))
$null = New-Item -ItemType Directory -Path $run

function Invoke-Configuration([string]$Script, [string]$Log, [string]$Marker) {
    # PDS does not safely quote an absolute -file path containing spaces.
    # Set the native working directory explicitly and pass only the filename.
    $stderr = $Log + '.stderr'
    $process = Start-Process -FilePath $tool -WorkingDirectory $scriptRoot `
        -ArgumentList '-file', $Script -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput $Log -RedirectStandardError $stderr
    if (!$process.WaitForExit(180000)) {
        $process.Kill()
        $process.WaitForExit()
        throw "Configuration tool timed out; inspect board before retrying: $Log"
    }
    $exitCode = $process.ExitCode
    $text = Get-Content -Raw -LiteralPath $Log
    $errors = Get-Content -Raw -LiteralPath $stderr
    Write-Host $text
    if ($errors) { Write-Host $errors }
    # This tool can exit 0 on Tcl/vendor failures, so require affirmative evidence.
    if ($exitCode -ne 0 -or $errors -or $text -match '(?m)^\s*E:' -or !$text.Contains($Marker)) {
        throw "Configuration command failed or incomplete; see $Log"
    }
    if ($text -notmatch 'The ID value is: 0x00521899\b' -or
        ([regex]::Matches($text, '(?m)^PGL50H\s*$')).Count -ne 1) {
        throw 'Expected PGL50H scan/ID evidence missing.'
    }
    return $text
}

Push-Location $run
try {
    $before = Invoke-Configuration 'probe.tcl' (Join-Path $run 'before.log') 'PREFLIGHT_COMMANDS_FINISHED'
    # Recheck the approved artifact immediately before the write operation.
    if ((Get-FileHash -LiteralPath $bitstream -Algorithm SHA256).Hash -ne $expected) {
        throw 'Baseline changed during preflight; refusing to program.'
    }
    $program = Invoke-Configuration 'program_v4.tcl' (Join-Path $run 'program.log') 'V4_PROGRAM_COMMANDS_FINISHED'
    if (!$program.Contains('Executing : cfg_program -device_index 0 successfully.')) {
        throw 'No successful cfg_program completion.'
    }
    $after = Invoke-Configuration 'probe.tcl' (Join-Path $run 'after.log') 'PREFLIGHT_COMMANDS_FINISHED'
    foreach ($status in @($program, $after)) {
        foreach ($bit in @('done_i', 'done', 'init_b', 'init_complete', 'wakeup_over')) {
            if ($status -notmatch ('(?m)^Bit\s+\d+:\s+1\s+' + $bit + '\s*$')) {
                throw "Required configuration status not set: $bit"
            }
        }
        foreach ($bit in @('over_temp', 'overflow', 'timeout', 'rbcrc_err', 'crc_err', 'id_err')) {
            if ($status -notmatch ('(?m)^Bit\s+\d+:\s+0\s+' + $bit + '\s*$')) {
                throw "Configuration error status set or missing: $bit"
            }
        }
    }
    $afterHash = (Get-FileHash -LiteralPath $bitstream -Algorithm SHA256).Hash
    if ($afterHash -ne $expected) { throw 'Baseline file changed; investigate provenance.' }
    [ordered]@{
        completed_at = (Get-Date -Format o)
        artifact = $bitstream
        sha256 = $hash.ToLowerInvariant()
        device = 'PGL50H'
        device_id = '0x00521899'
        cable_index = 0
        jtag_frequency = '1MHz'
        programmed = $true
        configuration_status_checked_in_new_session = $true
        flash_programmed = $false
        readback_verify_performed = $false
        readback_verify_reason = 'Matching archived v4 .smsk is unavailable; do not use another build mask.'
        semantic_road_model_deployed = $false
        camera_display_observed = $false
    } | ConvertTo-Json | Set-Content -Encoding utf8 -LiteralPath (Join-Path $run 'result.json')
    Write-Output "V4_RESTORE_STATUS_PASS: $run"
} finally {
    Pop-Location
}
