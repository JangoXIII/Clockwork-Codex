@echo off
rem Turns the OE proxy off by renaming it (run from the game directory; enable.bat reverses it). Nothing else is touched:
rem ObjectEditor.exe then loads the normal d3dx9_43.dll from System32 again. OpenWhe.exe keeps working on its own.
if exist "%~dp0d3dx9_43.dll" (ren "%~dp0d3dx9_43.dll" d3dx9_43.dll.off && echo OE proxy disabled) else echo OE proxy already disabled
