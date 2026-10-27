param([Parameter(Mandatory)][string]$Build,
      [Parameter(Mandatory)][string]$Simulation,
      [Parameter(Mandatory)][string]$AddressEvidence)
$ErrorActionPreference='Stop'
$projectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$b=Get-Content "$Build/result.json" -Raw | ConvertFrom-Json
$s=Get-Content "$Simulation/result.json" -Raw | ConvertFrom-Json
$a=Get-Content -LiteralPath $AddressEvidence -Raw | ConvertFrom-Json
if($b.Version -ne 'M2-01 2.0' -or -not $b.BuildPass -or -not $b.ExistingConstraintsMet -or -not $b.InputsUnchanged){throw 'Passing current M2 build required'}
if($s.Case -ne 'm2_all' -or $s.Verdict -ne 'PASS' -or -not $s.InputsUnchanged){throw 'Passing complete M2 simulation evidence required'}
if($a.Verdict -ne 'PASS' -or $a.ProductionSources -ne 3){throw 'Three-source physical address evidence required'}
foreach($item in (Get-Content "$Build/inputs.json" -Raw | ConvertFrom-Json)) {
    if((Get-FileHash -LiteralPath $item.Source).Hash -ne $item.SHA256){throw "Build input changed: $($item.Source)"}
}
foreach($p in (Get-Content "$Simulation/inputs.json" -Raw | ConvertFrom-Json).PSObject.Properties){
    if((Get-FileHash -LiteralPath $p.Name).Hash -ne $p.Value){throw "Simulation input changed: $($p.Name)"}
}
foreach($p in $a.Inputs.PSObject.Properties){
    if((Get-FileHash -LiteralPath (Join-Path $projectRoot $p.Name)).Hash -ne $p.Value){throw "Address input changed: $($p.Name)"}
}
if((Get-FileHash -LiteralPath $b.Release).Hash -ne $b.SHA256){throw 'Bitstream hash mismatch'}
$dest=Join-Path $projectRoot 'release/FPGA_GSV1_M2_01_2_0'
if(Test-Path -LiteralPath $dest){throw 'Never replace an existing release'}
New-Item -ItemType Directory -Path $dest | Out-Null
$bit=Join-Path $dest 'FPGA_GSV1_M2_01_2_0_HDMI_PROCESSING.sbit'
Copy-Item -LiteralPath $b.Release -Destination $bit
Copy-Item "$Build/report_timing/fpga_gsv1_top.rtr" "$dest/timing.rtr"
Copy-Item "$Build/device_map/fpga_gsv1_top.dmr" "$dest/resources.dmr"
Copy-Item "$Build/place_route/fpga_gsv1_top.prr" "$dest/implementation.prr"
Copy-Item "$Build/inputs.json" "$dest/build_inputs.json"
Copy-Item "$Simulation/inputs.json" "$dest/simulation_inputs.json"
Copy-Item "$Simulation/result.json" "$dest/simulation_result.json"
Get-ChildItem -LiteralPath $Simulation -Filter '*_run.log' | Copy-Item -Destination $dest
Copy-Item -LiteralPath $AddressEvidence -Destination "$dest/address_check.json"
Copy-Item "$projectRoot/docs/M2_01_board_test.md" "$dest/USER_TEST.md"
Copy-Item "$projectRoot/docs/M2_01_architecture.md" "$dest/ARCHITECTURE.md"
Copy-Item "$projectRoot/reports/M2_01_delivery.md" "$dest/DELIVERY.md"
Copy-Item "$projectRoot/reports/M2_01_osd_rtl.png" "$dest/osd_rtl.png"
Copy-Item "$projectRoot/reports/M2_01_edid.bin" "$dest/edid.bin"
# Preserve a self-contained project snapshot, including exactly the built IPs.
$src=Join-Path $dest 'source'
New-Item -ItemType Directory -Path $src | Out-Null
foreach($folder in @('rtl','vendor','constraints')){Copy-Item "$Build/$folder" "$src/$folder" -Recurse}
Copy-Item "$Build/build.pds" "$src/FPGA_GSV1_M2_01.pds"
Copy-Item "$Build/flow.tcl" "$src/flow.tcl"
Copy-Item "$projectRoot/scripts" "$src/scripts" -Recurse
Copy-Item "$projectRoot/sim" "$src/sim" -Recurse
New-Item -ItemType Directory -Path "$src/reports","$src/docs" | Out-Null
Copy-Item "$projectRoot/reports/M2_01_edid.bin","$projectRoot/reports/M2_01_delivery.md" "$src/reports/"
Copy-Item "$projectRoot/docs/M2_01_board_test.md","$projectRoot/docs/M2_01_architecture.md" "$src/docs/"
Copy-Item "$Build/build.pds" "$projectRoot/FPGA_GSV1_M2_01.pds"
$instant=[DateTimeOffset]$b.GeneratedTime
$release=[ordered]@{Version=$b.Version;Bitstream=$bit;SHA256=$b.SHA256;
 GeneratedUtc=$instant.ToUniversalTime().ToString('o');
 GeneratedShanghai=[TimeZoneInfo]::ConvertTime($instant,[TimeZoneInfo]::FindSystemTimeZoneById('China Standard Time')).ToString('yyyy-MM-dd HH:mm:ss zzz');
 Build=$Build;Simulation=$Simulation;BuildPass=$true;SimulationPass=$true;
 Programmed=$false;BoardVerified=$false;ExternalIoTimingSignoff=$false}
$release | ConvertTo-Json -Depth 4 | Set-Content "$dest/release.json" -Encoding utf8
$release | ConvertTo-Json -Depth 4
