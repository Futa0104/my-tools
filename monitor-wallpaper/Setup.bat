@echo off
setlocal DisableDelayedExpansion
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File "%~dp0internal\Wallpaper.ps1" -Action Setup
set "result=%ERRORLEVEL%"
pause
exit /b %result%
