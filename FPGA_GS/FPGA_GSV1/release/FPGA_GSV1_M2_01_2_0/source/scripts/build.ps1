param([string]$Pds='E:/XUEXI/FPGA_PDS/PDS_2022.2-SP6.4/bin/pds_shell.exe')
$ErrorActionPreference='Stop'
$projectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$run=Join-Path $projectRoot ('build/M2_01_2_0_'+(Get-Date -Format 'yyyyMMdd_HHmmss_fff'))
New-Item -ItemType Directory -Path $run | Out-Null
$files=@(Get-ChildItem "$projectRoot/rtl","$projectRoot/vendor","$projectRoot/constraints" -Recurse -File)
$files+=Get-Item "$projectRoot/flow.tcl"
$manifest=@($files | ForEach-Object {
    $rel=[IO.Path]::GetRelativePath($projectRoot,$_.FullName)
    $dest=Join-Path $run $rel
    New-Item -ItemType Directory -Path (Split-Path $dest -Parent) -Force | Out-Null
    Copy-Item -LiteralPath $_.FullName -Destination $dest
    [pscustomobject]@{Source=$_.FullName;RelativePath=$rel;SHA256=(Get-FileHash $_.FullName).Hash}
})
$manifest | ConvertTo-Json -Depth 4 | Set-Content "$run/inputs.json" -Encoding utf8
Copy-Item "$run/flow.tcl" "$run/build.tcl"
Write-Output "BUILD_DIRECTORY=$run"
Push-Location $run
try { & $Pds -file build.tcl *> "$run/pds_console.log"; $code=$LASTEXITCODE } finally { Pop-Location }
$log=Get-Content "$run/pds_console.log" -Raw
$timing="$run/report_timing/fpga_gsv1_top.rtr"
$bit="$run/generate_bitstream/fpga_gsv1_top.sbit"
$unchanged=@($manifest | Where-Object {(Get-FileHash $_.Source).Hash -ne $_.SHA256}).Count -eq 0
$met=(Test-Path $timing) -and ((Get-Content $timing -Raw) -match 'Design Summary\s*:\s*All Constraints Met\.')
$ok=$code -eq 0 -and $log -notmatch '(?im)^\s*E:|Program Error' -and (Test-Path $bit) -and $met -and $unchanged
$result=[ordered]@{Version='M2-01 2.0';BuildPass=$ok;ExitCode=$code;ExistingConstraintsMet=$met;InputsUnchanged=$unchanged;Programmed=$false;BoardVerified=$false;RunDirectory=$run}
if($ok){
    $release="$run/FPGA_GSV1_M2_01_2_0_HDMI_PROCESSING.sbit"
    Copy-Item $bit $release
    $result.Release=$release
    $result.SHA256=(Get-FileHash $release).Hash
    $result.GeneratedTime=(Get-Item $release).LastWriteTimeUtc.ToString('o')
}
$result | ConvertTo-Json | Set-Content "$run/result.json" -Encoding utf8
$result | ConvertTo-Json
if(-not $ok){Get-Content "$run/pds_console.log" -Tail 35; exit 1}
