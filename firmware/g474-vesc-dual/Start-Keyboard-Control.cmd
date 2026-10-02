@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0keyboard_controller.ps1"
if errorlevel 1 pause
