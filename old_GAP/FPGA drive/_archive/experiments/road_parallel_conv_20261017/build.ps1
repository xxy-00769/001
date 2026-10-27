$ErrorActionPreference='Stop'
$tool='D:/PDS/PDS_2022.2-SP6.1/bin/pds_shell.exe'
Push-Location $PSScriptRoot
try {
    $inputs=@{}
    foreach($file in @('source/conv_parallel.v','compute.fdc','flow.tcl')) {
        $inputs[$file]=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash
    }
    Copy-Item -LiteralPath flow.tcl -Destination impl.tcl
    & $tool impl.tcl *> synthesis.log
    if($LASTEXITCODE -ne 0) { throw 'PDS failed' }
    $log=Get-Content -Raw -LiteralPath synthesis.log
    if($log -match '(?m)^E:\s' -or !$log.Contains('Executing : dev_map successfully.')) { throw 'PDS mapping incomplete' }
    foreach($file in $inputs.Keys) {
        if((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $inputs[$file]) { throw "Source changed: $file" }
    }
    $null=New-Item -ItemType Directory -Path tests/output -Force
    $inputs | ConvertTo-Json | Set-Content -Encoding utf8 -LiteralPath tests/output/synthesis_inputs.json
    Write-Output 'PDS_MAPPING_COMPLETE: not routed, no bitstream.'
} finally { Pop-Location }
