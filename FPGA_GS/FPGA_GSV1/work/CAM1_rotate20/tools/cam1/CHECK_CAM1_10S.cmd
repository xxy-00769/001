@echo off
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0check_cam1.ps1" -Port COM23 -Seconds 10
pause
