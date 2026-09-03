@echo off
setlocal EnableExtensions
chcp 65001 >nul 2>&1
cd /d "%~dp0"

title OP Kiosk OS 2.0 - сборка ISO

echo ========================================================================
echo   OP Kiosk OS 2.0 - сборка ISO из малых частей
echo ========================================================================
echo.

echo Все файлы комплекта должны находиться в этой папке:
echo   %CD%
echo.

where powershell.exe >nul 2>&1
if errorlevel 1 (
    echo ОШИБКА: powershell.exe не найден.
    echo Для сборки требуется Windows PowerShell 5.1.
    echo.
    pause
    exit /b 1
)

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass ^
    -File "%~dp0MERGE-OP-Kiosk-OS-2.0.ps1" ^
    -Directory "%~dp0"

set "RESULT=%ERRORLEVEL%"
echo.
if "%RESULT%"=="0" (
    echo Готово. ISO собран и проверен по SHA-256.
) else (
    echo Сборка завершилась с ошибкой. Код: %RESULT%
)
echo.
pause
exit /b %RESULT%
