@echo off
setlocal
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0AstroHybrid VR Launcher.ps1"
if errorlevel 1 pause
