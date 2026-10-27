param([string]$OutputParent = 'E:\FPGA drive\tmp\s5_diag_package')
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$stamp = (Get-Date -Format 'yyyyMMdd_HHmmss_fff') + '_' + [Guid]::NewGuid().ToString('N').Substring(0,8)
$run = [IO.Path]::GetFullPath((Join-Path $OutputParent $stamp))
$allowed = [IO.Path]::GetFullPath((Join-Path (Split-Path $repo -Parent) 'tmp'))
if (-not $run.StartsWith($allowed + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Output outside workspace tmp.' }
if (Test-Path -LiteralPath $run) { throw 'Output already exists.' }
$dest = Join-Path $run 'MES50HP_S5_tools'
[IO.Directory]::CreateDirectory($dest) | Out-Null
$files = @('link.py','run_windows.cmd','README.md')
$manifest = @($files | ForEach-Object {
    $original = Join-Path $repo "host\mes50hp_link\$_"
    $copy = Join-Path $dest $_
    Copy-Item -LiteralPath $original -Destination $copy
    $hash = (Get-FileHash -LiteralPath $original).Hash
    if ((Get-FileHash -LiteralPath $copy).Hash -ne $hash) { throw "Copy mismatch: $_" }
    [pscustomobject]@{RelativePath=$_; Size=(Get-Item -LiteralPath $copy).Length; SHA256=$hash}
})
$manifest | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $dest 'manifest.json') -Encoding utf8
$zip = Join-Path $run 'MES50HP_S5_tools.zip'
Compress-Archive -LiteralPath $dest -DestinationPath $zip
$restore = Join-Path $run 'restore_check'
Expand-Archive -LiteralPath $zip -DestinationPath $restore
foreach ($item in $manifest) {
    if ((Get-FileHash -LiteralPath (Join-Path $restore "MES50HP_S5_tools\$($item.RelativePath)")).Hash -ne $item.SHA256) {
        throw "ZIP extraction mismatch: $($item.RelativePath)"
    }
}
[ordered]@{Package=$zip; SHA256=(Get-FileHash -LiteralPath $zip).Hash; Files=$manifest;
    ExtractionHashCheck='PASS'; ReceivesVideo=$false; RequiresFPGAEthernetRelease=$true} |
    ConvertTo-Json -Depth 8 | Tee-Object -FilePath (Join-Path $run 'package.json')
