@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0START_OOS.ps1" %*
exit /b %ERRORLEVEL%
