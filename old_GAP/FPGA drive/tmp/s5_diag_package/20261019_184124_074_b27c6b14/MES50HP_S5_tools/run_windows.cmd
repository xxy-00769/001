@echo off
setlocal
cd /d "%~dp0"
where py >nul 2>nul
if not errorlevel 1 (
    py -3 link.py client %*
) else (
    python link.py client %*
)
set "rc=%errorlevel%"
echo.
echo Diagnostics only. This tool does not receive video.
pause
exit /b %rc%
