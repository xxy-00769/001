param([string]$Port='COM23',[int]$Seconds=12)
$ErrorActionPreference='Stop'
$prefix=Join-Path $PSScriptRoot ('reports/CAM0_MOTION_'+(Get-Date -Format 'yyyyMMdd_HHmmss_fff'))
New-Item -ItemType Directory -Force (Join-Path $PSScriptRoot 'reports') | Out-Null
try {
 Write-Output 'Keep FRONT visible in single or quad view; keep the existing lighting and camera position.'
 & (Join-Path $PSScriptRoot 'read_net2_diag.ps1') -Port $Port -Seconds $Seconds -Output ($prefix+'.txt') | Out-Null
 & python -X utf8 (Join-Path $PSScriptRoot 'decode_cam0.py') ($prefix+'.txt') --output ($prefix+'.json') > ($prefix+'_decode.txt')
 $code=$LASTEXITCODE
 $r=Get-Content -LiteralPath ($prefix+'.json') -Raw -Encoding UTF8 | ConvertFrom-Json
 if($code -ne 0 -or -not $r.completed){throw 'CAM0 sample incomplete. See saved raw/JSON for ID, ACK and timing.'}
 $z=$r.snapshots[-1]
 if($z.tag -ne 'C0M9'){throw 'Expected motion candidate C0M9; C0O9 is the old read-only baseline.'}
 Write-Output "Tag=$($z.tag) ReadValid=$($z.read_valid) ReadSequence=$($z.read_sequence) ReadErrorsDelta=$($r.read_errors_delta)"
 Write-Output ("CAM0 capture {0:F3}fps / DDR {1:F3}fps / visible NEW {2:F3}fps" -f $r.capture_fps,$r.ddr_publish_fps,$r.display_new_fps)
 Write-Output "ID=$($z.sensor_id) Rows=$($z.rows) Pixels=$($z.pixels) BadDelta=$($r.capture_bad_delta)"
 $exposure=if($null -eq $z.exposure_ms){'UNKNOWN (AEC changed during read)'}else{('{0:F3}ms' -f $z.exposure_ms)}
 Write-Output ("Exposure={0} Gain={1:F2}x Row={2:F6}ms HTS={3} VTS={4} ExtraVTS={5}" -f $exposure,$z.gain_x,$z.row_period_ms,$z.hts,$z.vts,$z.extra_vts)
 Write-Output "ExposureRangeMs=$($r.exposure_ms_range) Night=$($z.night_mode) AE=$($z.aec_auto) AGC=$($z.agc_auto)"
 Write-Output "GainCeiling=$($z.gain_ceiling_x)x Band50=$($z.band_50_ms)ms Band60=$($z.band_60_ms)ms PCLK=$($z.byte_pclk_hz)Hz"
 Write-Output "AEProfileVerified=$($r.motion_profile_verified) MotionMetricsOK=$($r.motion_metrics_ok) ProfileFailed=$($z.profile_failed); physical motion improvement awaits same-scene comparison."
 Write-Output "Saved: $prefix.json"
} catch {
 ('SAMPLE INCOMPLETE: '+$_.Exception.Message) | Tee-Object -FilePath ($prefix+'_error.txt')
 exit 1
}
