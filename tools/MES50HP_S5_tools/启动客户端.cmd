@echo off
setlocal
cd /d "%~dp0"
"%~dp0.venv\Scripts\python.exe" "%~dp0link.py" client %*
set "rc=%errorlevel%"
echo.
echo Diagnostics only. This tool does not receive video.
pause
exit /b %rc%
