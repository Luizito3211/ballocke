@echo off
REM Script portátil para iniciar o HaxBall Local sem instalação ou permissões de administrador

if "%1"=="--test" (
    "%~dp0bin\love\lovec.exe" "%~dp0." --test
) else (
    start "" "%~dp0bin\love\love.exe" "%~dp0." %*
)
