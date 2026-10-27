@echo off
setlocal
cd /d "%~dp0"
echo Start the emulator first using the emulator launcher.
"%~dp0.venv\Scripts\python.exe" "%~dp0link.py" client --board 127.0.0.1 --bind 127.0.0.2 --count 10 --led 1 --lease-ms 2000
set "rc=%errorlevel%"
pause
exit /b %rc%
