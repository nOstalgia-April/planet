@echo off
cd /d "%~dp0"
python "%~dp0serve.py"
if errorlevel 1 pause
