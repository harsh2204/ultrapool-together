@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Capture-Screens.ps1" %*
if errorlevel 1 exit /b 1
