@echo off
setlocal
cd /d "%~dp0"

echo ========================================================
echo   PIXGATE MASTER FIXER
echo ========================================================
echo.

:: 1. CREATE THE LAUNCHER (The Bridge)
echo [1/2] Creating launcher.bat in this folder...
(
    echo @echo off
    echo cd /d "%%~dp0"
    echo echo [LAUNCHER] BRIDGE ACTIVE.
    echo echo [LAUNCHER] RAW ARGUMENT: %%1
    echo.
    echo "Pixgate.console.exe" -- %%1
    echo.
    echo if %%ERRORLEVEL%% NEQ 0 pause
) > launcher.bat

echo    - Launcher created successfully.
echo.

:: 2. UPDATE THE REGISTRY
echo [2/2] Updating Windows Registry...
set "TARGET_PATH=%~dp0launcher.bat"
:: Escape backslashes for Registry
set "TARGET_PATH=%TARGET_PATH:\=\\%"

reg delete "HKCR\pixgate" /f >nul 2>&1
reg add "HKCR\pixgate" /ve /t REG_SZ /d "URL:Pixgate Protocol" /f
reg add "HKCR\pixgate" /v "URL Protocol" /t REG_SZ /d "" /f
reg add "HKCR\pixgate\shell\open\command" /ve /t REG_SZ /d "\"%TARGET_PATH%\" \"%%1\"" /f

echo.
echo ========================================================
echo   SUCCESS!
echo   1. launcher.bat is now in the same folder as this script.
echo   2. Registry now points to: %TARGET_PATH%
echo ========================================================
pause