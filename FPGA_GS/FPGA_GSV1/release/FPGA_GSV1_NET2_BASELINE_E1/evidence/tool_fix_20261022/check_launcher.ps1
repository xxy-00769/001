$ErrorActionPreference='Stop'
$root=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$tool=Join-Path $root 'tools/sample.ps1'
$src=[IO.File]::ReadAllText($tool)
$tokens=$null; $errors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile($tool,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Parser errors'}
foreach($f in $ast.FindAll({param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst]},$false)) { Invoke-Expression $f.Extent.Text }
$start=$src.IndexOf('    $raw = Get-Content')
$finish=$src.IndexOf("    Write-SampleLog '采样已完成",$start)
$validate=[scriptblock]::Create($src.Substring($start,$finish-$start))
$psExe='C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe'
foreach($case in @('complete','missing','python_error')) {
    $script:report=Join-Path $PSScriptRoot ("check_"+$case+'.txt')
    [IO.File]::WriteAllText($report,'')
    $failed=$false
    try {
        Invoke-SampleCommand $psExe @('-NoProfile','-File',(Join-Path $PSScriptRoot 'fixture.ps1'),$case) 'FIXTURE_NOT_HARDWARE'
        . $validate
    } catch { $failed=$true; Write-Host "Failure: $($_.Exception.Message)" }
    if(($case -eq 'complete') -eq $failed){throw "Wrong result for $case"}
    if($case -eq 'complete') {
        $saved=Get-Content -LiteralPath $report -Raw -Encoding UTF8
        $payload=[regex]::Match($saved,'(?s)=== E1_SAMPLE_JSON_BEGIN ===\s*(.*?)\s*=== E1_SAMPLE_JSON_END ===').Groups[1].Value
        if($payload.Contains('Connection to fixture')){throw 'stderr spliced into JSON'}
        if(($payload|ConvertFrom-Json).padding -ne ('X'*20000)){throw 'stdout payload changed'}
    }
    Write-Host "CHECK PASS: $case"
}
