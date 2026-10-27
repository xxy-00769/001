from pathlib import Path
root=Path(__file__).parent.parent
p=root/'oneclick/demo_launcher.ps1';s=p.read_text(encoding='utf-8-sig')
s=s.replace("'m405/demo_ops.py'))", "'m405/demo_ops.py','m405r2/demo_ops.py'))")
s=s.replace("else{'M4-04-r1'}", "elseif($cfg.demo_ops -eq 'm405r2/demo_ops.py'){'M4-05-r2'}else{'M4-04-r1'}")
p.write_text(s,encoding='utf-8-sig')
p=root/'oneclick/set_demo_version.ps1';s=p.read_text(encoding='utf-8-sig')
s=s.replace("'m403','m404','m405'", "'m403','m404','m405','m405r2'")
s=s.replace('[string]$Version)', '[string]$Version,[switch]$NoPause,[switch]$NoBrowser)')
s=s.replace(" & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'demo_launcher.ps1') -Action Start -NoPause", " $launchArgs=@('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $PSScriptRoot 'demo_launcher.ps1'),'-Action','Start','-NoPause')\n if($NoBrowser){$launchArgs+='-NoBrowser'}\n & powershell.exe @launchArgs")
s=s.replace("Read-Host '按回车关闭' | Out-Null", "if(!$NoPause){Read-Host '按回车关闭' | Out-Null}")
p.write_text(s,encoding='utf-8-sig')
for name,version in [('切回M4-05-r2车道结构.cmd','m405r2'),('回退M4-05-r1道路车道.cmd','m405')]:
 (root/'oneclick'/name).write_text('@echo off\nchcp 65001 >nul\npowershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0set_demo_version.ps1" -Version '+version+'\n',encoding='utf-8')
