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
    foreach($file in @('../source/conv_parallel.v','parallel_tb.v','prepare.py',
        'output/cases.vh','output/cases.json','output/inputs.hex','output/weights.hex',
        'output/coefficients.hex','output/expected.hex','output/descriptors.txt','output/baseline_inputs.json')) {
        $inputs[$file]=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash
    }
    & "$vivado/xvlog.bat" --sv ../source/conv_parallel.v parallel_tb.v
    if($LASTEXITCODE -ne 0) { throw 'RTL compile failed' }
    & "$vivado/xelab.bat" parallel_tb --O3 -s road_parallel
    if($LASTEXITCODE -ne 0) { throw 'Elaboration failed' }
    & "$vivado/xsim.bat" road_parallel -runall -log parallel.log
    if($LASTEXITCODE -ne 0) { throw 'Simulation failed' }
    $log=Get-Content -Raw -LiteralPath parallel.log
    if($log -notmatch 'PASS: parallel ' -or $log -match 'Fatal:|\$fatal|ERROR:') { throw 'Missing clean pass' }
    foreach($file in $inputs.Keys) {
        if((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $inputs[$file]) { throw "Input changed: $file" }
    }
    $inputs | ConvertTo-Json | Set-Content -Encoding utf8 -LiteralPath output/rtl_build_inputs.json
} finally { Pop-Location }
