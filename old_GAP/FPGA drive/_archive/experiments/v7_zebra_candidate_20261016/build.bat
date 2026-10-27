@echo off
REM ===========================================================================
REM  HDMI_DDR3_OV5640 - one-click build script
REM  Target : PGL50H-6FBG484   Tool : PDS 2022.2-SP6.1
REM
REM  Just double-click this file. The finished bitstream will be at:
REM      generate_bitstream\hdmi_ddr_ov5640_top.sbit
REM
REM  NOTE: pds_shell APPENDS its own absolute-path flow to the script file it
REM        is given, so we always regenerate impl.tcl from flow.tcl first.
REM        Edit flow.tcl, never impl.tcl.
REM ===========================================================================

setlocal
cd /d "%~dp0"

set "PDS_BIN=D:\PDS\PDS_2022.2-SP6.1\bin"

if not exist "%PDS_BIN%\pds_shell.exe" (
    echo [ERROR] pds_shell.exe not found at:
    echo         %PDS_BIN%
    echo         Edit PDS_BIN in this file to match your installation.
    pause
    exit /b 1
)

if not exist "flow.tcl" (
    echo [ERROR] flow.tcl not found - it is the build template.
    pause
    exit /b 1
)

echo ============================================================
echo  Building HDMI_DDR3_OV5640 ...
echo  Working dir : %CD%
echo  Toolchain   : %PDS_BIN%
echo ============================================================
echo.

REM Regenerate the run script so PDS appends to a clean copy every time.
del /q impl.tcl 2>nul
copy /y flow.tcl impl.tcl >nul
if not exist "impl.tcl" (
    echo [ERROR] could not create impl.tcl from flow.tcl
    pause
    exit /b 1
)

REM Remove previous bitstream so a stale one cannot be mistaken for success.
if exist "generate_bitstream\hdmi_ddr_ov5640_top.sbit" del /q "generate_bitstream\hdmi_ddr_ov5640_top.sbit"

"%PDS_BIN%\pds_shell.exe" -file impl.tcl -continue

echo.
echo ============================================================
if exist "generate_bitstream\hdmi_ddr_ov5640_top.sbit" (
    echo  [OK] Bitstream generated:
    echo       generate_bitstream\hdmi_ddr_ov5640_top.sbit
) else (
    echo  [FAILED] No bitstream produced. Check the log above
    echo           and pds.log in this folder.
)
echo ============================================================
pause
