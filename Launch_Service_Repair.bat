@echo off
setlocal
cd /d "%~dp0"

:menu
cls
echo ============================================================
echo   WINDOWS SERVICE REPAIR TOOLKIT
echo ============================================================
echo   1. Diagnose only
echo   2. Run safe repair for one service
echo   3. Start one service
echo   4. Restart one service
echo   5. Stop one service
echo   6. Start required dependencies
echo   7. Change startup type
echo   8. Terminate a stuck dedicated service process
echo   0. Exit
echo ============================================================
set /p CHOICE=Select an option: 

if "%CHOICE%"=="1" set ARGS=&goto run
if "%CHOICE%"=="2" goto safe
if "%CHOICE%"=="3" goto start
if "%CHOICE%"=="4" goto restart
if "%CHOICE%"=="5" goto stop
if "%CHOICE%"=="6" goto deps
if "%CHOICE%"=="7" goto startup
if "%CHOICE%"=="8" goto terminate
if "%CHOICE%"=="0" goto end
goto menu

:safe
set /p SERVICE=Service name: 
set ARGS=-ServiceName "%SERVICE%" -RepairAllSafe
goto run

:start
set /p SERVICE=Service name: 
set ARGS=-ServiceName "%SERVICE%" -StartService
goto run

:restart
set /p SERVICE=Service name: 
set ARGS=-ServiceName "%SERVICE%" -RestartService
goto run

:stop
set /p SERVICE=Service name: 
set ARGS=-ServiceName "%SERVICE%" -StopService
goto run

:deps
set /p SERVICE=Service name: 
set ARGS=-ServiceName "%SERVICE%" -StartDependencies
goto run

:startup
set /p SERVICE=Service name: 
set /p STARTTYPE=Startup type [Automatic, AutomaticDelayedStart, Manual, Disabled]: 
set ARGS=-ServiceName "%SERVICE%" -SetStartupType "%STARTTYPE%"
goto run

:terminate
set /p SERVICE=Service name: 
set ARGS=-ServiceName "%SERVICE%" -TerminateStuckProcess
goto run

:run
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "Unblock-File -LiteralPath '%~dp0Windows_Service_Repair_Toolkit.ps1' -ErrorAction SilentlyContinue"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Windows_Service_Repair_Toolkit.ps1" %ARGS%
echo.
pause
goto menu

:end
endlocal
