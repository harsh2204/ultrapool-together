@echo off
setlocal
cd /d "%~dp0"
if not exist "%~dp0ultrapool-together-install.json" (
    echo Run Install.cmd first, then use Launch.cmd inside the installed UltrapoolTogether folder.
    pause
    exit /b 1
)
start "Ultrapool Together" "%~dp0game.exe"
