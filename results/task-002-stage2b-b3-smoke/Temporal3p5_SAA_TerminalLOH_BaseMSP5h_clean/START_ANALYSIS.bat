@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0START_ANALYSIS.ps1" %*
exit /b %ERRORLEVEL%
