$ErrorActionPreference='Stop'
$tool='D:/PDS/PDS_2022.2-SP6.1/bin/pds_shell.exe'
$inputs=@{}
foreach($file in @('source/conv_tile.v','source/residual_requant.v','compute.fdc','flow.tcl','residual_build/flow.tcl')) {
    $inputs[$file]=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $file) -Algorithm SHA256).Hash
}
foreach($dir in @($PSScriptRoot, (Join-Path $PSScriptRoot 'residual_build'))) {
    Push-Location $dir
    try {
        Copy-Item -LiteralPath flow.tcl -Destination impl.tcl
        & $tool impl.tcl *> synthesis.log
        if($LASTEXITCODE -ne 0) { throw "PDS failed: $dir" }
        $log=Get-Content -Raw -LiteralPath synthesis.log
        if($log -match '(?m)^E:\s' -or !$log.Contains('Executing : dev_map successfully.')) { throw "PDS mapping incomplete: $dir" }
    } finally { Pop-Location }
}
foreach($file in $inputs.Keys) {
    if((Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $file) -Algorithm SHA256).Hash -ne $inputs[$file]) { throw "Source changed during build: $file" }
}
$null=New-Item -ItemType Directory -Path (Join-Path $PSScriptRoot 'tests/output') -Force
$inputs | ConvertTo-Json | Set-Content -Encoding utf8 -LiteralPath (Join-Path $PSScriptRoot 'tests/output/synthesis_inputs.json')
Write-Output 'PDS_MAPPING_COMPLETE: inspect synthesis timing and resource reports; no routed timing/bitstream.'
