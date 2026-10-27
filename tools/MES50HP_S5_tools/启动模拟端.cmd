@echo off
setlocal
cd /d "%~dp0"
"%~dp0.venv\Scripts\python.exe" "%~dp0link.py" emulator --bind 127.0.0.1 %*
pause
