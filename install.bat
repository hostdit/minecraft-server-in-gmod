@echo off
setlocal
cd /d "%~dp0"

if "%GMOD_DIR%"=="" set "GMOD_DIR=%ProgramFiles(x86)%\Steam\steamapps\common\GarrysMod\garrysmod"

if not exist "%GMOD_DIR%" (
  echo GMod not at: %GMOD_DIR%
  echo set GMOD_DIR to your garrysmod folder and rerun
  exit /b 1
)
if not exist gmsv_mcsock_win64.dll (
  echo run build.bat first
  exit /b 1
)

mkdir "%GMOD_DIR%\lua\bin" 2>nul
mkdir "%GMOD_DIR%\lua\mcserver" 2>nul
mkdir "%GMOD_DIR%\lua\autorun\server" 2>nul
mkdir "%GMOD_DIR%\data" 2>nul

copy /y gmsv_mcsock_win64.dll "%GMOD_DIR%\lua\bin\" >nul
copy /y garrysmod\lua\mcserver\proto.lua "%GMOD_DIR%\lua\mcserver\" >nul
copy /y garrysmod\lua\autorun\server\mcserver.lua "%GMOD_DIR%\lua\autorun\server\" >nul
if exist mc_favicon.png copy /y mc_favicon.png "%GMOD_DIR%\data\" >nul

echo Installed into %GMOD_DIR%
