param([string]$Port='COM23',[ValidateSet(10,60)][int]$Seconds=10)
$ErrorActionPreference='Stop'
$dir=$PSScriptRoot
$prefix=Join-Path $dir ('reports/CAM1_'+$Seconds+'s_'+(Get-Date -Format 'yyyyMMdd_HHmmss_fff'))
New-Item -ItemType Directory -Force (Join-Path $dir 'reports') | Out-Null
try {
 Write-Output "Keep CAM1 visible (single view or quad) for this entire sample. Port=$Port"
 # Capture62 seconds for >=60 seconds between atomic one-second UART records.
 $duration=if($Seconds -eq 60){62}else{10}
 & (Join-Path $dir 'read_net2_diag.ps1') -Port $Port -Seconds $duration -Output ($prefix+'.txt') | Out-Null
 $minimum=if($Seconds -eq 60){60}else{7}
 & python -X utf8 (Join-Path $dir 'decode_cam1_rate.py') ($prefix+'.txt') --output ($prefix+'.json') --minimum-window $minimum > ($prefix+'_decode.txt')
 $exitCode=$LASTEXITCODE
 $r=Get-Content -LiteralPath ($prefix+'.json') -Raw -Encoding UTF8 | ConvertFrom-Json
 if($exitCode -ne 0 -or -not $r.completed){throw 'SAMPLE INCOMPLETE: missing C1R8 or insufficient time window. See saved report.'}
 Write-Output "Tag=C1R8  GeometryOK=$($r.geometry_ok)  Rows=$($r.snapshots[-1].rows)  Pixels=$($r.snapshots[-1].pixels)"
 Write-Output ("Capture {0:F3}fps / DDR publish {1:F3}fps / displayed NEW {2:F3}fps" -f $r.capture_fps,$r.ddr_publish_fps,$r.display_new_fps)
 Write-Output "CaptureBadDelta=$($r.capture_bad_delta)  Window=$($r.reference_window_seconds)s  ActualBytePCLK=$($r.snapshots[-1].actual_byte_pclk_hz)Hz"
 Write-Output "RateQualityPass=$($r.rate_quality_pass) (requires all three >=20fps, zero new bad frames, correct geometry)"
 Write-Output "Saved: $prefix.json"
} catch {
 $message='SAMPLE INCOMPLETE: '+$_.Exception.Message
 $message | Tee-Object -FilePath ($prefix+'_error.txt')
 exit 1
}
