@echo off
setlocal

where powershell.exe >nul 2>nul
if errorlevel 1 (
  echo [ERROR] Windows PowerShell could not be found.
  pause
  exit /b 1
)

start "PetFeeder Backend" powershell.exe -NoProfile -ExecutionPolicy Bypass -NoExit -File "%~dp0start_backend.ps1"
exit /b 0
