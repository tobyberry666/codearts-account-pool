@echo off
chcp 65001 >nul
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0windows\install.ps1"
if errorlevel 1 echo Installation failed. Please read the message above.
pause
