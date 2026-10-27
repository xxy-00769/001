$ErrorActionPreference='Stop'
$project=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$ip=Join-Path $project 'source/rtl/DDR3_50H'
$lib='D:/PDS/PDS_2022.2-SP6.1/arch/vendor/pango/verilog/simulation'
$modelsim='D:/PDS/Modelsim/win64'
$inputs=@{}
$files=@()
foreach($line in Get-Content -LiteralPath (Join-Path $ip 'sim/modelsim/sim_file_list.f')) {
    $line=$line.Trim()
    if(!$line -or $line.StartsWith('+')) { continue }
    if($line.StartsWith('C:/pango/')) {
        $file=Join-Path $lib ([IO.Path]::GetFileName($line))
    } else {
        $file=[IO.Path]::GetFullPath((Join-Path (Join-Path $ip 'sim/modelsim') $line))
        if($file.Contains('example_design') -and !$file.Contains('bench\mem')) { continue }
    }
    if(!(Test-Path -LiteralPath $file)) { throw "Missing vendor source: $file" }
    $files+=$file.Replace('\','/')
}
$files+=(Join-Path $PSScriptRoot '../source/road_ddr_bridge.v')
$files+=(Join-Path $PSScriptRoot 'vendor_tb.v')
$files+=(Join-Path $PSScriptRoot 'harness.vh')
foreach($file in $files) { $inputs[$file]=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash }
$run=Join-Path $PSScriptRoot 'vendor_run'
$null=New-Item -ItemType Directory -Path $run -Force
$files | Where-Object { !($_.EndsWith('.vh')) } | ForEach-Object {
    '"' + $_.Replace('\','/') + '"'
} | Set-Content -Encoding ascii -LiteralPath (Join-Path $run 'sources.f')
Push-Location $run
try {
    if(!(Test-Path -LiteralPath work)) {
        & "$modelsim/vlib.exe" work
        if($LASTEXITCODE -ne 0) { throw 'ModelSim library creation failed' }
    }
    & "$modelsim/vlog.exe" -sv -work work -mfcu -f sources.f -y $lib '+libext+.v' '+incdir+..' "+incdir+$ip/sim/modelsim" '+define+SIMULATION' '+define+den4096Mb' '+define+sg25E' '+define+x16' *> compile.log
    if($LASTEXITCODE -ne 0) { throw 'Vendor model compilation failed; see vendor_run/compile.log' }
    if((Test-Path -LiteralPath console.log) -and !(Test-Path -LiteralPath previous_attempt.log)) {
        Copy-Item -LiteralPath console.log -Destination previous_attempt.log
    }
    & "$modelsim/vsim.exe" -c -novopt -t 1ps -suppress 3486,3680,3781,12110 -lib work vendor_tb -do ../vendor.do -l vendor.log *> console.log
    if($LASTEXITCODE -ne 0) { throw 'Vendor model simulation failed; see vendor_run/vendor.log' }
    $log=Get-Content -Raw vendor.log
    if(!$log.Contains('PASS: vendor DDR') -or $log -match '\*\* (Error|Fatal):') { throw 'Vendor model missing clean pass' }
    foreach($file in $inputs.Keys) {
        if((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $inputs[$file]) { throw "Vendor input changed: $file" }
    }
    $inputs | ConvertTo-Json | Set-Content -Encoding utf8 -LiteralPath ../output/vendor_inputs.json
    Write-Output ($log -split "`n" | Where-Object { $_ -match 'PASS: vendor|VENDOR_INITIALIZED' })
} finally { Pop-Location }
