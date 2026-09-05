@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0START_TRAINING.ps1" %*
exit /b %ERRORLEVEL%
