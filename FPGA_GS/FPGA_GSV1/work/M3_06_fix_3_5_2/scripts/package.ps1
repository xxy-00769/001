param([Parameter(Mandatory)][string]$Build,[Parameter(Mandatory)][string]$Simulation,
      [Parameter(Mandatory)][string]$ControlSimulation,
      [Parameter(Mandatory)][string]$FullSimulation,
      [Parameter(Mandatory)][string]$AddressEvidence)
$ErrorActionPreference='Stop'
$projectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$b=Get-Content "$Build/result.json" -Raw | ConvertFrom-Json
$s=Get-Content "$Simulation/result.json" -Raw | ConvertFrom-Json
$c=Get-Content "$ControlSimulation/result.json" -Raw | ConvertFrom-Json
$f=Get-Content "$FullSimulation/result.json" -Raw | ConvertFrom-Json
$a=Get-Content -LiteralPath $AddressEvidence -Raw | ConvertFrom-Json
if($f.Case -ne 'joint_full' -or $f.Verdict -ne 'PASS' -or -not $f.InputsUnchanged){throw 'Full-height multi-frame simulation required'}
if($a.Verdict -ne 'PASS'){throw 'Configured physical address mapping check required'}
foreach($p in $a.Inputs.PSObject.Properties){
    if((Get-FileHash -LiteralPath (Join-Path $projectRoot $p.Name)).Hash -ne $p.Value){throw "Address check source changed: $($p.Name)"}
}
if(-not $b.BuildPass -or -not $b.ExistingConstraintsMet -or -not $b.InputsUnchanged){throw 'A passing implemented build is required'}
if($s.Verdict -ne 'PASS' -or -not $s.InputsUnchanged){throw 'Passing simulation with unchanged inputs is required'}
if($s.Case -ne 'm1_02' -or $c.Case -ne 'smoke' -or $c.Verdict -ne 'PASS' -or -not $c.InputsUnchanged){throw 'M1-02 joint/controls and fault-control simulation evidence required'}
foreach($item in (Get-Content "$Build/inputs.json" -Raw | ConvertFrom-Json)) {
    if((Get-FileHash -LiteralPath $item.Source).Hash -ne $item.SHA256){throw "Build source changed: $($item.Source)"}
}
$simInputs=Get-Content "$Simulation/inputs.json" -Raw | ConvertFrom-Json
foreach($p in $simInputs.PSObject.Properties){
    if((Get-FileHash -LiteralPath $p.Name).Hash -ne $p.Value){throw "Simulation source changed: $($p.Name)"}
}
$controlInputs=Get-Content "$ControlSimulation/inputs.json" -Raw | ConvertFrom-Json
foreach($p in $controlInputs.PSObject.Properties){
    if((Get-FileHash -LiteralPath $p.Name).Hash -ne $p.Value){throw "Control simulation source changed: $($p.Name)"}
}
$fullInputs=Get-Content "$FullSimulation/inputs.json" -Raw | ConvertFrom-Json
foreach($p in $fullInputs.PSObject.Properties){
    if((Get-FileHash -LiteralPath $p.Name).Hash -ne $p.Value){throw "Full simulation source changed: $($p.Name)"}
}
if((Get-FileHash -LiteralPath $b.Release).Hash -ne $b.SHA256){throw 'Release hash mismatch'}
$dest=Join-Path $projectRoot 'release/FPGA_GSV1_M1_02_1_1'
if(Test-Path -LiteralPath $dest){throw 'Release already exists; never replace an earlier delivery'}
New-Item -ItemType Directory -Path $dest | Out-Null
$bit=Join-Path $dest 'FPGA_GSV1_M1_02_1_1_DISPLAY_FIX.sbit'
Copy-Item -LiteralPath $b.Release -Destination $bit
Copy-Item "$Build/report_timing/fpga_gsv1_top.rtr" "$dest/timing.rtr"
Copy-Item "$Build/device_map/fpga_gsv1_top.dmr" "$dest/resources.dmr"
Copy-Item "$Build/place_route/fpga_gsv1_top.prr" "$dest/implementation.prr"
Copy-Item "$Build/inputs.json" "$dest/build_inputs.json"
Copy-Item "$Simulation/inputs.json" "$dest/simulation_inputs.json"
Copy-Item "$Simulation/result.json" "$dest/simulation_result.json"
Copy-Item "$ControlSimulation/result.json" "$dest/control_simulation_result.json"
Copy-Item "$ControlSimulation/inputs.json" "$dest/control_simulation_inputs.json"
Copy-Item "$FullSimulation/inputs.json" "$dest/full_simulation_inputs.json"
Copy-Item "$FullSimulation/result.json" "$dest/full_simulation_result.json"
Copy-Item "$FullSimulation/display_joint_720_run.log" "$dest/full_height_run.log"
Copy-Item -LiteralPath $AddressEvidence -Destination "$dest/address_check.json"
Get-ChildItem -LiteralPath $Simulation -Filter '*_run.log' | Copy-Item -Destination $dest
Copy-Item "$ControlSimulation/dual_run.log" "$dest/control_run.log"
Copy-Item "$projectRoot/reports/M1_02_diagnosis.md" "$dest/diagnosis.md"
Copy-Item "$projectRoot/docs/M1_02_board_test.md" "$dest/USER_TEST.md"
Copy-Item "$projectRoot/docs/M1_02_display_ownership.md" "$dest/OWNERSHIP.md"
Copy-Item "$projectRoot/reports/M1_02_hint_rtl.png" "$dest/key_hint_preview.png"
Copy-Item "$Build/build.pds" "$projectRoot/FPGA_GSV1_M1_02.pds"
$generatedInstant=[DateTimeOffset]$b.GeneratedTime
$release=[ordered]@{Version=$b.Version;Bitstream=$bit;SHA256=$b.SHA256;
    GeneratedUtc=$generatedInstant.ToUniversalTime().ToString('o');GeneratedShanghai=[TimeZoneInfo]::ConvertTime($generatedInstant,[TimeZoneInfo]::FindSystemTimeZoneById('China Standard Time')).ToString('yyyy-MM-dd HH:mm:ss zzz');
    Build=$Build;Simulation=$Simulation;ControlSimulation=$ControlSimulation;FullSimulation=$FullSimulation;BuildPass=$true;SimulationPass=$true;
    Programmed=$false;BoardVerified=$false;ExternalIoTimingSignoff=$false}
$release | ConvertTo-Json -Depth 4 | Set-Content "$dest/release.json" -Encoding utf8
$release | ConvertTo-Json -Depth 4
