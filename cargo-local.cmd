@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\setup-windows-vscode-rust.ps1" cargo %*
exit /b %ERRORLEVEL%