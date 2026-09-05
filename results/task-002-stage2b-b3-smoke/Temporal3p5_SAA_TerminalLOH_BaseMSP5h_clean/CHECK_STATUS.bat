@echo off
setlocal
echo PACKAGE_ID=BASE_STAGE89Q_REFERENCE
echo PMAX_KW=300,200,120,150
echo TERMINAL_MODE=DIRECT_GAP
echo TERMINAL_GAP_PENALTY=1000
echo STAGE90_ENABLED=0
if exist "%~dp0status\BASE_STATUS.txt" type "%~dp0status\BASE_STATUS.txt"
echo.
echo Run directories:
if exist "%~dp0results" dir /b /ad "%~dp0results"
