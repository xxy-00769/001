$ErrorActionPreference='Stop'
Push-Location $PSScriptRoot
try {
    $inputs=@{}
    foreach($file in @('source/conv_cached.v','source/conv_layer_dma.v','source/layer_probe.v','flow.tcl','compute.fdc')) {
        $inputs[$file]=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash
    }
    Copy-Item -LiteralPath flow.tcl -Destination impl.tcl
    & 'D:/PDS/PDS_2022.2-SP6.1/bin/pds_shell.exe' impl.tcl *> synthesis.log
    if($LASTEXITCODE -ne 0) { throw 'PDS failed' }
    $log=Get-Content -Raw synthesis.log
    if($log -match '(?m)^E:\s' -or !$log.Contains('Executing : dev_map successfully.')) { throw 'Mapping incomplete' }
    foreach($file in $inputs.Keys) {
        if((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $inputs[$file]) { throw "Input changed: $file" }
    }
    $null=New-Item -ItemType Directory -Path tests/output -Force
    $inputs | ConvertTo-Json | Set-Content -Encoding utf8 -LiteralPath tests/output/synthesis_inputs.json
    Write-Output 'PDS_MAPPING_COMPLETE: no routing or bitstream.'
    $snr=Get-Content -Raw -LiteralPath synthesize/layer_probe.snr
    $timing=[regex]::Match($snr,'compute_clk\s+100\.0000 MHz\s+[\d.]+ MHz\s+10\.0000\s+([\d.]+)\s+([\d.-]+)')
    if(!$timing.Success) { throw 'Missing synthesis timing summary' }
    $slack=[double]::Parse($timing.Groups[2].Value,[Globalization.CultureInfo]::InvariantCulture)
    if($slack -lt 0) {
        Write-Warning "TIMING_TARGET_NOT_MET: period $($timing.Groups[1].Value) ns, slack $slack ns. Mapping is not deployment approval."
    } else {
        Write-Output "SYNTHESIS_TIMING_ONLY: slack $slack ns; still not routed."
    }
} finally { Pop-Location }
