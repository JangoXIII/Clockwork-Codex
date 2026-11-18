@echo off
rem Turns the OE proxy back on after disable.bat (run from the game directory).
if exist "%~dp0d3dx9_43.dll.off" (ren "%~dp0d3dx9_43.dll.off" d3dx9_43.dll && echo OE proxy enabled) else echo OE proxy already enabled (or not installed)
