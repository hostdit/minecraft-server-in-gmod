@echo off
setlocal
cd /d "%~dp0"

where cl >nul 2>&1
if errorlevel 1 (
  echo Run this from a "x64 Native Tools Command Prompt for VS".
  echo Install Build Tools for Visual Studio with the C++ workload if you have not.
  exit /b 1
)

cl /nologo /LD /EHsc /O2 /std:c++17 /Imodule\include module\mcsock.cpp ^
   /link /OUT:gmsv_mcsock_win64.dll ws2_32.lib
if errorlevel 1 exit /b 1

echo.
echo Built gmsv_mcsock_win64.dll
