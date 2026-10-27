param([switch]$SkipPrepare,[ValidateSet('all','tile','layer')][string]$Suite='all')
$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$python=Join-Path $root '.venv-road-model/Scripts/python.exe'
$vivado='D:/Xilinx/Vivado/2018.3/bin'
Push-Location $PSScriptRoot
try {
    if(!$SkipPrepare) {
        & $python -X utf8 prepare.py
        if($LASTEXITCODE -ne 0) { throw 'Pinned vector preparation failed' }
    }
    $suites=if($Suite -eq 'all') { @('tile','layer') } else { @($Suite) }
    foreach($kind in $suites) {
        $tb=if($kind -eq 'tile') { 'stream_tb' } else { 'layer_tb' }
        $inputs=@{}
        $files=@('../source/conv_cached.v','../source/conv_stream_probe.v','../source/conv_layer_dma.v',
            '../source/layer_probe.v',"$kind/$tb.v",'prepare.py','output/previous_inputs.json')
        $files+=Get-ChildItem -LiteralPath "$kind/output" -File | Where-Object {
            $_.Name -notmatch '^(rtl_|recovery_)'
        } | ForEach-Object { "$kind/output/$($_.Name)" }
        foreach($file in $files) { $inputs[$file]=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash }
        Push-Location $kind
        try {
            & "$vivado/xvlog.bat" --sv ../../source/conv_cached.v ../../source/conv_stream_probe.v ../../source/conv_layer_dma.v ../../source/layer_probe.v "$tb.v"
            if($LASTEXITCODE -ne 0) { throw "$kind RTL compile failed" }
            & "$vivado/xelab.bat" $tb --O3 -s "config_pipe_$kind"
            if($LASTEXITCODE -ne 0) { throw "$kind elaboration failed" }
            & "$vivado/xsim.bat" "config_pipe_$kind" -runall -log "$kind.log"
            if($LASTEXITCODE -ne 0) { throw "$kind simulation failed" }
            $log=Get-Content -Raw -LiteralPath "$kind.log"
            $pass=if($kind -eq 'tile') { 'PASS: stream ' } else { 'PASS: layer_dma ' }
            if(!$log.Contains($pass) -or $log -match 'Fatal:|\$fatal|ERROR:') { throw "$kind missing clean pass" }
        } finally { Pop-Location }
        foreach($file in $inputs.Keys) {
            if((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $inputs[$file]) { throw "Input changed: $file" }
        }
        $inputs | ConvertTo-Json | Set-Content -Encoding utf8 -LiteralPath "output/${kind}_build_inputs.json"
    }
} finally { Pop-Location }
