param([ValidateSet('all','bridge','layer','partition')][string]$Suite='all')
$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$python=Join-Path $root '.venv-road-model/Scripts/python.exe'
$vivado='D:/Xilinx/Vivado/2018.3/bin'
Push-Location $PSScriptRoot
try {
    & $python -X utf8 prepare.py
    if($LASTEXITCODE -ne 0) { throw 'Preparation failed' }
    $suites=if($Suite -eq 'all') { @('bridge','layer','partition') } else { @($Suite) }
    foreach($kind in $suites) {
        $tb="${kind}_tb"
        $files=@('../source/road_ddr_bridge.v','native_bfm.v','harness.vh',"$tb.v",'prepare.py',
            '../../road_config_pipe_20261017/source/conv_cached.v',
            '../../road_config_pipe_20261017/source/conv_layer_dma.v')
        $inputs=@{}
        foreach($file in $files) { $inputs[$file]=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash }
        & "$vivado/xvlog.bat" --sv ../source/road_ddr_bridge.v native_bfm.v ../../road_config_pipe_20261017/source/conv_cached.v ../../road_config_pipe_20261017/source/conv_layer_dma.v "$tb.v"
        if($LASTEXITCODE -ne 0) { throw "$kind compile failed" }
        & "$vivado/xelab.bat" $tb --O3 -s "ddr_$kind"
        if($LASTEXITCODE -ne 0) { throw "$kind elaboration failed" }
        & "$vivado/xsim.bat" "ddr_$kind" -runall -log "$kind.log"
        if($LASTEXITCODE -ne 0) { throw "$kind simulation failed" }
        $log=Get-Content -Raw -LiteralPath "$kind.log"
        if(!$log.Contains("PASS: native $kind") -or $log -match 'Fatal:|\$fatal|ERROR:') { throw "$kind missing clean pass" }
        foreach($file in $inputs.Keys) {
            if((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $inputs[$file]) { throw "Input changed: $file" }
        }
        $inputs | ConvertTo-Json | Set-Content -Encoding utf8 -LiteralPath "output/${kind}_inputs.json"
    }
} finally { Pop-Location }
