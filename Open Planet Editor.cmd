@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\open_editor.ps1" %*
if errorlevel 1 pause
