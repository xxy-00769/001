param([Parameter(Mandatory=$true)][string]$Port,[int]$Seconds=15,[string]$Output='net2_diag.txt')
$ErrorActionPreference='Stop'
# Built-in .NET SerialPort only. No driver installation or network changes.
$serial=[IO.Ports.SerialPort]::new($Port,115200,[IO.Ports.Parity]::None,8,[IO.Ports.StopBits]::One)
$serial.Handshake=[IO.Ports.Handshake]::None
$serial.DtrEnable=$false;$serial.RtsEnable=$false;$serial.ReadTimeout=1200
$lines=[Collections.Generic.List[string]]::new()
try {
 $serial.Open();$until=[DateTime]::UtcNow.AddSeconds($Seconds)
 while([DateTime]::UtcNow -lt $until){
  try {$line=$serial.ReadLine().Trim();if($line -match '^N2 35[12] '){$lines.Add($line);Write-Output $line}}
  catch [TimeoutException] {}
 }
} finally {if($serial.IsOpen){$serial.Close()};$serial.Dispose()}
if($lines.Count -eq 0){throw 'No N2 351/352 line. Check the selected board CP2102 COM port and USB UART cable; do not change Ethernet settings.'}
[IO.File]::WriteAllLines([IO.Path]::GetFullPath($Output),$lines,[Text.Encoding]::ASCII)
Write-Output "Saved $($lines.Count) lines to $([IO.Path]::GetFullPath($Output))"
& python -X utf8 (Join-Path $PSScriptRoot 'decode_net2_diag.py') $Output
