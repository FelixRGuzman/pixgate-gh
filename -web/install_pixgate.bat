@echo off
echo Force-installing Pixgate Protocol with Argument Separator...

:: Clean old entries
reg delete "HKCR\pixgate" /f >nul 2>&1

:: Add Protocol Base
reg add "HKCR\pixgate" /ve /t REG_SZ /d "URL:Pixgate Protocol" /f
reg add "HKCR\pixgate" /v "URL Protocol" /t REG_SZ /d "" /f

:: Add the Command with the -- Separator
:: This tells Godot to pass the %1 link directly to your script's OS.get_cmdline_args()
reg add "HKCR\pixgate\shell\open\command" /ve /t REG_SZ /d "\"C:\Users\vaeli\OneDrive\Documents\pixgate-gh\Pixgate.exe\" --path \"C:\Users\vaeli\OneDrive\Documents\pixgate-gh\" -- \"%%1\"" /f

echo.
echo Registry Updated Successfully. 
echo Godot will now see the web links.
pause