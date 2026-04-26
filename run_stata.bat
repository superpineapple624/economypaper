@echo off
setlocal enabledelayedexpansion

rem Always run from the project root, no matter where this file is launched.
pushd "%~dp0"

set "STATA_EXE=D:\StataMP-64.exe"
set "DEFAULT_DO=code\00_master.do"

if not exist "%STATA_EXE%" (
    echo Stata executable not found: %STATA_EXE%
    popd
    exit /b 1
)

if "%~1"=="" (
    set "TARGET_DO=%DEFAULT_DO%"
) else (
    set "TARGET_DO=%~1"
)

if not exist "%TARGET_DO%" (
    echo Do-file not found: %TARGET_DO%
    popd
    exit /b 1
)

echo Running Stata...
echo Executable: %STATA_EXE%
echo Do-file   : %TARGET_DO%
echo.

"%STATA_EXE%" /e do "%TARGET_DO%"
set "EXIT_CODE=%ERRORLEVEL%"

echo.
echo Stata finished with exit code %EXIT_CODE%.

popd
exit /b %EXIT_CODE%
