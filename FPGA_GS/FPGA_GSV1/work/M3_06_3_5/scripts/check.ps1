param([string]$Python='python',[string]$Case='m1_02')
$ErrorActionPreference='Stop'
& $Python (Join-Path $PSScriptRoot 'check.py') --case $Case
if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}
