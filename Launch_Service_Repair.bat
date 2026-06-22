@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "Unblock-File -LiteralPath '%~dp0Windows_Service_Repair_Toolkit.ps1' -ErrorAction SilentlyContinue"

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

if "%CHOICE%"=="1" goto diagnose
if "%CHOICE%"=="2" goto safe
if "%CHOICE%"=="3" goto start
if "%CHOICE%"=="4" goto restart
if "%CHOICE%"=="5" goto stop
if "%CHOICE%"=="6" goto deps
if "%CHOICE%"=="7" goto startup
if "%CHOICE%"=="8" goto terminate
if "%CHOICE%"=="0" goto end
goto menu

:diagnose
set /p SERVICE=Service name to inspect (leave blank for inventory only): 
if "%SERVICE%"=="" powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Windows_Service_Repair_Toolkit.ps1"
if not "%SERVICE%"=="" powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Windows_Service_Repair_Toolkit.ps1" -ServiceName "%SERVICE%"
goto complete

:safe
set /p SERVICE=Service name: 
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Windows_Service_Repair_Toolkit.ps1" -ServiceName "%SERVICE%" -RepairAllSafe
goto complete

:start
set /p SERVICE=Service name: 
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Windows_Service_Repair_Toolkit.ps1" -ServiceName "%SERVICE%" -StartService
goto complete

:restart
set /p SERVICE=Service name: 
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Windows_Service_Repair_Toolkit.ps1" -ServiceName "%SERVICE%" -RestartService
goto complete

:stop
set /p SERVICE=Service name: 
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Windows_Service_Repair_Toolkit.ps1" -ServiceName "%SERVICE%" -StopService
goto complete

:deps
set /p SERVICE=Service name: 
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Windows_Service_Repair_Toolkit.ps1" -ServiceName "%SERVICE%" -StartDependencies
goto complete

:startup
set /p SERVICE=Service name: 
set /p STARTTYPE=Startup type [Automatic, AutomaticDelayedStart, Manual, Disabled]: 
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Windows_Service_Repair_Toolkit.ps1" -ServiceName "%SERVICE%" -SetStartupType "%STARTTYPE%"
goto complete

:terminate
set /p SERVICE=Service name: 
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Windows_Service_Repair_Toolkit.ps1" -ServiceName "%SERVICE%" -TerminateStuckProcess
goto complete

:complete
echo.
pause
goto menu

:end
endlocal
