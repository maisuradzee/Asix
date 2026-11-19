@echo off
setlocal
cd /d "%~dp0\.."
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0export_casino_handover.ps1"
if errorlevel 1 (
  echo.
  echo Export failed. Check the error above, npx.cmd login, and Docker Desktop.
  pause
  exit /b 1
)
echo.
echo Export completed.
pause
