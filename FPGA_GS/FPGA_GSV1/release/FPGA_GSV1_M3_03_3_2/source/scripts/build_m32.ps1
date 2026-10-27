param([string]$Pds='E:/XUEXI/FPGA_PDS/PDS_2022.2-SP6.4/bin/pds_shell.exe', [switch]$ProcessingBypass)
$ErrorActionPreference='Stop'
$projectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$defaultMatch=[regex]::Match((Get-Content (Join-Path $projectRoot 'rtl/board/fpga_gsv1_top.v') -Raw),'parameter PROCESSING_ENABLE\s*=\s*([01])')
if(-not $defaultMatch.Success){throw 'PROCESSING_ENABLE parameter missing'}
if($defaultMatch.Groups[1].Value -eq '0'){$ProcessingBypass=$true}
$variant=if($ProcessingBypass){'M3_03_3_2B'}else{'M3_03_3_2'}
$version=if($ProcessingBypass){'M3-03 3.2B'}else{'M3-03 3.2'}
$run=Join-Path $projectRoot ('build/'+$variant+'_'+(Get-Date -Format 'yyyyMMdd_HHmmss_fff'))
New-Item -ItemType Directory -Path $run | Out-Null
& python -X utf8 (Join-Path $projectRoot 'scripts/configure_m31_endpoints.py')
if($LASTEXITCODE -ne 0){throw 'Endpoint configuration failed'}
$files=@(Get-ChildItem "$projectRoot/rtl","$projectRoot/vendor","$projectRoot/constraints" -Recurse -File)
$files+=Get-Item "$projectRoot/flow.tcl","$projectRoot/config/m3_endpoints.json"
$manifest=@($files | ForEach-Object {
    $rel=[IO.Path]::GetRelativePath($projectRoot,$_.FullName)
    $dest=Join-Path $run $rel
    New-Item -ItemType Directory -Path (Split-Path $dest -Parent) -Force | Out-Null
    Copy-Item -LiteralPath $_.FullName -Destination $dest
    [pscustomobject]@{Source=$_.FullName;RelativePath=$rel;SHA256=(Get-FileHash $_.FullName).Hash}
})
# The diagnostic variant differs by this single default elaboration parameter.
if($ProcessingBypass){
    $topFile=Join-Path $run 'rtl/board/fpga_gsv1_top.v'
    $topText=Get-Content -LiteralPath $topFile -Raw
    if($topText -notmatch 'parameter PROCESSING_ENABLE = [01]'){throw 'Bypass parameter missing'}
    [IO.File]::WriteAllText($topFile,[regex]::Replace($topText,'parameter PROCESSING_ENABLE = [01]','parameter PROCESSING_ENABLE = 0'))
}
foreach($item in $manifest){$item | Add-Member -NotePropertyName SnapshotSHA256 -NotePropertyValue (Get-FileHash -LiteralPath (Join-Path $run $item.RelativePath)).Hash}
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
$result=[ordered]@{Version=$version;ProcessingEnable=(-not $ProcessingBypass);BuildPass=$ok;ExitCode=$code;ExistingConstraintsMet=$met;InputsUnchanged=$unchanged;Programmed=$false;BoardVerified=$false;RunDirectory=$run}
if($ok){
    $release="$run/FPGA_GSV1_${variant}_HDMI_1080P60.sbit"
    Copy-Item $bit $release
    $result.Release=$release
    $result.SHA256=(Get-FileHash $release).Hash
    $result.GeneratedTime=(Get-Item $release).LastWriteTimeUtc.ToString('o')
}
$result | ConvertTo-Json | Set-Content "$run/result.json" -Encoding utf8
$result | ConvertTo-Json
if(-not $ok){Get-Content "$run/pds_console.log" -Tail 35; exit 1}
