@echo off
setlocal

set "ROOT=%~dp0"
set "DIST=%ROOT%dist"
set "STAGE=%DIST%\HaxBallLocal"
set "GAME=%DIST%\game.love"
set "LOVE_DIR=%ROOT%tools\love-11.5-win64"

echo [1/4] Preparando L??VE portatil e game.love...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%ROOT%build.ps1" -Action Prepare
if errorlevel 1 exit /b 1

echo [2/4] Fundindo love.exe com game.love...
copy /b "%LOVE_DIR%\love.exe"+"%GAME%" "%STAGE%\HaxBallLocal.exe" >nul
if errorlevel 1 exit /b 1

echo [3/4] Montando o ZIP de distribuicao...
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%ROOT%build.ps1" -Action Package
if errorlevel 1 exit /b 1

echo Build concluido: %DIST%\HaxBallLocal.zip
endlocal
