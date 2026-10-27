param(
    [Parameter(Mandatory=$true)][string]$Run,
    [string]$ResumeHoldFrom
)
$ErrorActionPreference = 'Stop'
$python = 'C:/Users/19511/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe'
$pds = 'D:/PDS/PDS_2022.2-SP6.1/bin/pds_shell.exe'
$helper = Join-Path $PSScriptRoot 'continue.py'
if ($ResumeHoldFrom) {
    & $python -X utf8 $helper prepare-hold --run $Run --previous $ResumeHoldFrom
} else {
    & $python -X utf8 $helper prepare --run $Run
}
if ($LASTEXITCODE -ne 0) { throw 'Preparation failed' }
Push-Location $Run
try {
    if ($ResumeHoldFrom) {
        & $pds -file resume_hold.tcl *> place_route.log
    } else {
        & $pds -file map.tcl -continue *> map.log
        if ($LASTEXITCODE -ne 0) { throw 'Mapping failed' }
        & $pds -action place_route -project_file map.pds *> place_route.log
    }
    if ($LASTEXITCODE -ne 0) { throw 'Place/route failed' }
    & $python -X utf8 $helper collect --run $Run
    if ($LASTEXITCODE -ne 0) { throw 'PNR collection failed' }
    & $pds -file timing_only.tcl *> timing_only.log
    if ($LASTEXITCODE -ne 0) { throw 'Timing command failed' }
    & $python -X utf8 $helper check --run $Run
    if ($LASTEXITCODE -ne 0) { throw 'Timing gate failed; stop automatic retries' }
    & $pds -file bitstream_only.tcl *> bitstream_only.log
    if ($LASTEXITCODE -ne 0) { throw 'Bitstream generation failed' }
    & $python -X utf8 $helper release --run $Run
    if ($LASTEXITCODE -ne 0) { throw 'Release audit failed' }
} finally {
    Pop-Location
}
Write-Output "Candidate build complete, not programmed: $Run"
