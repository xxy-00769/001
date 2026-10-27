param(
    [string]$Archive = 'D:\BaiduNetdiskDownload\盘古50K开发板\2_Demo\11_ethernet_test.rar',
    [string]$OutputParent = 'E:\FPGA drive\tmp\s5_vendor_inspection'
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$run = [IO.Path]::GetFullPath((Join-Path $OutputParent (
    (Get-Date -Format 'yyyyMMdd_HHmmss_fff') + '_' + [Guid]::NewGuid().ToString('N').Substring(0,8))))
$allowed = [IO.Path]::GetFullPath((Join-Path (Split-Path $repo -Parent) 'tmp'))
if (-not $run.StartsWith($allowed + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Output outside workspace tmp.' }
if (Test-Path -LiteralPath $run) { throw 'Output already exists.' }
$before = (Get-FileHash -LiteralPath $Archive).Hash
[IO.Directory]::CreateDirectory($run) | Out-Null
$members = @('ethernet_test.fdc','source/ethernet_test.v','source/eth_udp_test.v',
    'source/rgmii_interface.v','source/udp_rx.v','source/mac_rx.v',
    'source/udp_ip_mac_top.v','ipcore/pll_phase/pll_phase.idf')
$manifest = @($members | ForEach-Object {
    $member = "11_ethernet_test/11_ethernet_test/$_"
    $dest = Join-Path $run ($_.Replace('/','__') + '.txt')
    $text = & tar -xOf $Archive $member
    if ($LASTEXITCODE -ne 0) { throw "Cannot inspect $member" }
    $text | Set-Content -LiteralPath $dest -Encoding utf8
    [pscustomobject]@{Member=$member; ExtractedText=$dest; SHA256=(Get-FileHash -LiteralPath $dest).Hash}
})
$after = (Get-FileHash -LiteralPath $Archive).Hash
[ordered]@{Archive=$Archive; BeforeSHA256=$before; AfterSHA256=$after;
    ArchiveUnchanged=($before -eq $after); ImportIntoProject=$false; TextEvidence=$manifest} |
    ConvertTo-Json -Depth 8 | Tee-Object -FilePath (Join-Path $run 'inspection.json')
if ($before -ne $after) { throw 'Archive changed during inspection.' }
