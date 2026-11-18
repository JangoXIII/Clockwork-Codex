@echo off
rem Installs the optional OE proxy into a Dawn of War: Definitive Edition directory (next to ObjectEditor.exe).
rem   install.bat "C:\Program Files (x86)\Steam\steamapps\common\Dawn of War Definitive Edition"
rem Files placed there: d3dx9_43.dll (the proxy), d3dx9_43_real.dll (copy of %SystemRoot%\System32\d3dx9_43.dll),
rem enable.bat / disable.bat, and OpenWhe.exe if it sits next to this script. Nothing of the game's is modified.
setlocal
set "SRC=%~dp0"
set "DST=%~1"
if "%DST%"=="" set "DST=%CD%"
if not exist "%DST%\ObjectEditor.exe" echo ObjectEditor.exe not found in "%DST%" & exit /b 1
if exist "%DST%\d3dx9_43.dll" (
    findstr /m /c:"oeproxy" "%DST%\d3dx9_43.dll" >nul || (echo "%DST%\d3dx9_43.dll" already exists and is not the OE proxy - not touching it & exit /b 1)
)
if not exist "%SystemRoot%\System32\d3dx9_43.dll" echo %SystemRoot%\System32\d3dx9_43.dll missing - install the DirectX 9 runtime first & exit /b 1
copy /y "%SystemRoot%\System32\d3dx9_43.dll" "%DST%\d3dx9_43_real.dll" >nul || exit /b 1
copy /y "%SRC%d3dx9_43.dll" "%DST%\d3dx9_43.dll" >nul || exit /b 1
copy /y "%SRC%enable.bat" "%DST%\" >nul
copy /y "%SRC%disable.bat" "%DST%\" >nul
if exist "%SRC%OpenWhe.exe" copy /y "%SRC%OpenWhe.exe" "%DST%\" >nul
if not exist "%DST%\OpenWhe.exe" echo WARNING: OpenWhe.exe is not in "%DST%" - copy it there or .whe files cannot be converted
echo OE proxy installed in "%DST%". Log: %APPDATA%\Relic Entertainment\Dawn of War\Mods\WheBridge\proxy.log
endlocal

if exist "%DST%\OpenWhe.exe" (
    rem create/refresh the bridge mod now, with absolute game paths in its pipeline.ini, so the Object Editor can burn
    rem even when the Mod Assistant starts it with only -wkdir (no -appdir)
    "%DST%\OpenWhe.exe" --init --game "%DST%" || echo WARNING: could not create the bridge mod
)