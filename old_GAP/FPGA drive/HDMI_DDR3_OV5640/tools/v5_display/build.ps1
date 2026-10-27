param([string]$Pds='E:/XUEXI/FPGA_PDS/PDS_2022.2-SP6.4/bin/pds_shell.exe',
      [string]$Version='v5_1', [string]$ReleaseName='V5_1_MPI7001_DIAG_KEY8_cmos1')
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$run=Join-Path 'E:/zhoumian/FPGA/JF/builds' ($Version+'_'+(Get-Date -Format 'yyyyMMdd_HHmmss'))
New-Item -ItemType Directory -Path $run | Out-Null
$paths=@(Get-ChildItem "$repo/source" -Recurse -File | ForEach-Object FullName)
$paths+=@('flow.tcl','hdmi_ddr_ov5640_top.fdc','impl.pds') | ForEach-Object {Join-Path $repo $_}
$manifest=@($paths | ForEach-Object {
    $rel=[IO.Path]::GetRelativePath($repo,$_)
    $dest=Join-Path $run $rel
    New-Item -ItemType Directory -Path (Split-Path $dest -Parent) -Force | Out-Null
    Copy-Item -LiteralPath $_ -Destination $dest
    [pscustomobject]@{Source=$_;RelativePath=$rel;SHA256=(Get-FileHash $_).Hash}
})
$manifest | ConvertTo-Json -Depth 4 | Set-Content "$run/inputs.json" -Encoding utf8
Copy-Item "$run/flow.tcl" "$run/build.tcl"
Write-Output "BUILD_DIRECTORY=$run"
Push-Location $run
try { & $Pds -file build.tcl *> "$run/pds_console.log"; $code=$LASTEXITCODE } finally { Pop-Location }
$log=Get-Content "$run/pds_console.log" -Raw
$timing="$run/report_timing/hdmi_ddr_ov5640_top.rtr"
$bit="$run/generate_bitstream/hdmi_ddr_ov5640_top.sbit"
$unchanged=@($manifest | Where-Object {(Get-FileHash $_.Source).Hash -ne $_.SHA256}).Count -eq 0
$met=(Test-Path $timing) -and ((Get-Content $timing -Raw) -match 'Design Summary\s*:\s*All Constraints Met\.')
$ok=$code -eq 0 -and $log -notmatch '(?im)^\s*E:|Program Error' -and (Test-Path $bit) -and $met -and $unchanged
$result=[ordered]@{BuildPass=$ok;ExitCode=$code;ExistingConstraintsMet=$met;InputsUnchanged=$unchanged;Programmed=$false;BoardVerified=$false;RunDirectory=$run}
if($ok){
    $release="$run/$ReleaseName.sbit"
    Copy-Item $bit $release
    $result.Release=$release
    $result.SHA256=(Get-FileHash $release).Hash
}
$result | ConvertTo-Json | Set-Content "$run/result.json" -Encoding utf8
$result | ConvertTo-Json
if(-not $ok){Get-Content "$run/pds_console.log" -Tail 25; exit 1}
