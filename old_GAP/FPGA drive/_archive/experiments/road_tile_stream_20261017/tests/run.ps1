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
    foreach($file in @('../source/conv_cached.v','../source/conv_stream_probe.v','stream_tb.v','prepare.py',
        'output/cases.vh','output/cases.json','output/inputs.hex','output/weights.hex',
        'output/coefficients.hex','output/expected.hex','output/descriptors.txt',
        'output/vectors.hex','output/vector_cases.vh','output/vector_cases.json',
        'output/vector_descriptors.txt','output/previous_inputs.json')) {
        $inputs[$file]=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash
    }
    & "$vivado/xvlog.bat" --sv ../source/conv_cached.v ../source/conv_stream_probe.v stream_tb.v
    if($LASTEXITCODE -ne 0) { throw 'RTL compile failed' }
    & "$vivado/xelab.bat" stream_tb --O3 -s road_tile_stream
    if($LASTEXITCODE -ne 0) { throw 'Elaboration failed' }
    & "$vivado/xsim.bat" road_tile_stream -runall -log stream.log
    if($LASTEXITCODE -ne 0) { throw 'Simulation failed' }
    $log=Get-Content -Raw -LiteralPath stream.log
    if($log -notmatch 'PASS: stream ' -or $log -match 'Fatal:|\$fatal|ERROR:') { throw 'Missing clean pass' }
    foreach($file in $inputs.Keys) {
        if((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $inputs[$file]) { throw "Input changed: $file" }
    }
    $inputs | ConvertTo-Json | Set-Content -Encoding utf8 -LiteralPath output/rtl_build_inputs.json
} finally { Pop-Location }
