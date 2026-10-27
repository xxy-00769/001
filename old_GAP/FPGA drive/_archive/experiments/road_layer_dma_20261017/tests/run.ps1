param([switch]$SkipGenerate)
$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$python=Join-Path $root '.venv-road-model/Scripts/python.exe'
$vivado='D:/Xilinx/Vivado/2018.3/bin'
Push-Location $PSScriptRoot
try {
    if(!$SkipGenerate) {
        & $python -X utf8 prepare.py
        if($LASTEXITCODE -ne 0) { throw 'Vector preparation failed' }
    }
    $inputs=@{}
    foreach($file in @('../../road_tile_stream_20261017/source/conv_cached.v',
        '../source/conv_layer_dma.v','../source/layer_probe.v','layer_tb.v','prepare.py',
        'output/cases.vh','output/cases.json','output/initial.hex','output/golden.hex',
        'output/transactions.hex','output/descriptors.hex','output/jobs.txt','output/previous_inputs.json')) {
        $inputs[$file]=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash
    }
    & "$vivado/xvlog.bat" --sv ../../road_tile_stream_20261017/source/conv_cached.v ../source/conv_layer_dma.v ../source/layer_probe.v layer_tb.v
    if($LASTEXITCODE -ne 0) { throw 'RTL compile failed' }
    & "$vivado/xelab.bat" layer_tb --O3 -s road_layer_dma
    if($LASTEXITCODE -ne 0) { throw 'Elaboration failed' }
    & "$vivado/xsim.bat" road_layer_dma -runall -log layer.log
    if($LASTEXITCODE -ne 0) { throw 'Simulation failed' }
    $log=Get-Content -Raw -LiteralPath layer.log
    if($log -notmatch 'PASS: layer_dma ' -or $log -match 'Fatal:|\$fatal|ERROR:') { throw 'Missing clean pass' }
    foreach($file in $inputs.Keys) {
        if((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $inputs[$file]) { throw "Input changed: $file" }
    }
    $inputs | ConvertTo-Json | Set-Content -Encoding utf8 -LiteralPath output/rtl_build_inputs.json
} finally { Pop-Location }
