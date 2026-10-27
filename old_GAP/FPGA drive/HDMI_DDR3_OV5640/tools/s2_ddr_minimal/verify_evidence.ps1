param(
    [Parameter(Mandatory=$true)][string]$ControlRun,
    [Parameter(Mandatory=$true)][string]$ReadRun,
    [string]$S1Metadata = 'D:\MES50HP_Snapshots\S1_20261019T082916Z_d8742ddd\metadata'
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$control = Get-Content -LiteralPath (Join-Path $ControlRun 'result.json') -Raw | ConvertFrom-Json
$read = Get-Content -LiteralPath (Join-Path $ReadRun 'result.json') -Raw | ConvertFrom-Json
$checks = [Collections.Generic.List[object]]::new()
foreach ($run in @($ControlRun, $ReadRun)) {
    $evidence = Get-Content -LiteralPath (Join-Path $run 'evidence_manifest.json') -Raw | ConvertFrom-Json
    foreach ($file in $evidence) {
        $current = (Get-FileHash -LiteralPath $file.Path -Algorithm SHA256).Hash
        $checks.Add([pscustomobject]@{
            Path = $file.Path; ExpectedSHA256 = $file.SHA256; SHA256 = $current
            Unchanged = $current -eq $file.SHA256
        })
    }
}

# Decode only the four scalar signals in this known simulator-generated VCD.
# This is an evidence cross-check, not a software replacement of the RTL test.
$definitions = @{}
$values = @{}
$samples = [Collections.Generic.List[object]]::new()
$timePs = [long]0
$rising = $false
foreach ($line in (Get-Content -LiteralPath (Join-Path $ControlRun 'control.vcd'))) {
    if ($line -match '^\$var\s+\w+\s+1\s+(\S+)\s+(clk|rstn|read_en|rd_cmd_done)\s+\$end$') {
        if (-not $definitions.ContainsKey($Matches[2])) { $definitions[$Matches[2]] = $Matches[1] }
    } elseif ($line.StartsWith('#')) {
        if ($rising) {
            $samples.Add([pscustomobject]@{
                TimePs = $timePs; ResetN = $values[$definitions['rstn']]
                ReadEn = $values[$definitions['read_en']]
                Done = $values[$definitions['rd_cmd_done']]
            })
        }
        $timePs = [long]$line.Substring(1)
        $rising = $false
    } elseif ($line -match '^([01xz])(.+)$') {
        $value = $Matches[1]
        $id = $Matches[2]
        if ($definitions.Count -eq 4 -and $id -in $definitions.Values) {
            if ($id -eq $definitions['clk'] -and $value -eq '1' -and $values[$id] -eq '0') { $rising = $true }
            $values[$id] = $value
        }
    }
}
if ($rising) {
    $samples.Add([pscustomobject]@{
        TimePs = $timePs; ResetN = $values[$definitions['rstn']]
        ReadEn = $values[$definitions['read_en']]; Done = $values[$definitions['rd_cmd_done']]
    })
}
if ($definitions.Count -ne 4) { throw 'Missing scalar signal definitions in control VCD.' }
$active = @($samples | Where-Object ResetN -eq '1')
$accepted = @($active | Where-Object ReadEn -eq '1')
$done = @($active | Where-Object Done -eq '1')
$premature = @($done | Where-Object ReadEn -ne '1')
$rows = @(Import-Csv -LiteralPath (Join-Path $ReadRun 'rows.csv'))
$requests = @(Import-Csv -LiteralPath (Join-Path $ReadRun 'requests.csv'))
$requestErrors = 0
for ($i = 0; $i -lt $requests.Count; $i++) {
    if ([int]$requests[$i].index -ne $i -or [int]$requests[$i].row -ne $i -or
        [Convert]::ToInt32($requests[$i].address,16) -ne 0x400000 + $i * 640 -or
        [int]$requests[$i].length -ne 80) { $requestErrors++ }
}
$rowErrors = 0
for ($i = 0; $i -lt $rows.Count; $i++) {
    if ([int]$rows[$i].row -ne $i -or [int]$rows[$i].pixels -ne 1280 -or
        [int]$rows[$i].errors -ne $(if ($i -eq 719) {1280} else {0}) -or
        [int]$rows[$i].requests -ne $(if ($i -eq 719) {0} else {1})) { $rowErrors++ }
}
$protected = Get-Content -LiteralPath (Join-Path $S1Metadata 'protected_files.json') -Raw | ConvertFrom-Json
$mainChecks = @($protected | ForEach-Object {
    $hash = (Get-FileHash -LiteralPath $_.SourcePath -Algorithm SHA256).Hash
    [pscustomobject]@{Path=$_.SourcePath; Unchanged=$hash -eq $_.SHA256}
})
$s1Docs = @(Get-Content -LiteralPath (Join-Path $S1Metadata 's1_supplement_manifest.jsonl') |
    ForEach-Object { $_ | ConvertFrom-Json } | ForEach-Object {
        $hash = (Get-FileHash -LiteralPath $_.SourcePath -Algorithm SHA256).Hash
        [pscustomobject]@{Path=$_.SourcePath; Unchanged=$hash -eq $_.SourceSHA256}
    })
$verified = @($checks | Where-Object { -not $_.Unchanged }).Count -eq 0 -and
    @($mainChecks | Where-Object { -not $_.Unchanged }).Count -eq 0 -and
    @($s1Docs | Where-Object { -not $_.Unchanged }).Count -eq 0 -and
    $accepted.Count -eq 80 -and $done.Count -eq 20 -and $premature.Count -eq 19 -and
    $control.PrematureCompletionCycles -eq $premature.Count -and
    $control.CompletionCycles -eq $done.Count -and
    $rows.Count -eq 720 -and $requests.Count -eq 719 -and
    $requestErrors -eq 0 -and $rowErrors -eq 0 -and
    $read.PixelErrors -eq 1280 -and $read.LastRowErrors -eq 1280 -and
    $control.ToolExecutionSucceeded -and $read.ToolExecutionSucceeded -and
    $control.InputsUnchanged -and $read.InputsUnchanged
$result = [ordered]@{
    CapturedUtc = [DateTime]::UtcNow.ToString('o')
    Kind = 'Post-simulation waveform/CSV/hash cross-check, not a new RTL simulation'
    EvidenceConsistent = $verified; DUTPassed = $false
    ControlRun = $ControlRun; ReadRun = $ReadRun
    ControlWaveform = [ordered]@{
        AcceptedReturns = $accepted.Count; CompletionCycles = $done.Count
        PrematureCompletionCycles = $premature.Count
        FinalReturnTimePs = $accepted[-1].TimePs
        FirstPrematureTimePs = $premature[0].TimePs
        PrematureSamples = $premature
    }
    ReadCSV = [ordered]@{
        Rows = $rows.Count; Requests = $requests.Count; LastRequestedRow = $requests[-1].row
        MissingRow = 719; RowEvidenceErrors = $rowErrors; RequestEvidenceErrors = $requestErrors
        FirstRow = $rows[0]; LastRow = $rows[-1]
    }
    EvidenceHashes = @($checks.ToArray()); S1ProtectedFiles = $mainChecks; S1Documents = $s1Docs
}
$parent = Split-Path $ControlRun -Parent
$path = Join-Path $parent ('evidence_review_' + (Get-Date -Format 'yyyyMMdd_HHmmss_fff') + '.json')
if (Test-Path -LiteralPath $path) { throw 'Review destination exists.' }
$result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $path -Encoding utf8
[pscustomobject]@{
    EvidenceConsistent = $verified; ControlAcceptedReturns = $accepted.Count
    ControlCompletionCycles = $done.Count; ControlPrematureCycles = $premature.Count
    ReadRows = $rows.Count; ReadRequests = $requests.Count
    LastRequestedRow = $requests[-1].row; LastRowErrors = $rows[-1].errors
    S1ProtectedCount = $mainChecks.Count; ReviewPath = $path
} | ConvertTo-Json
if (-not $verified) { exit 1 }
