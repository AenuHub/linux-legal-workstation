@echo off
rem Legal Workstation Windows CLI launcher wrapper
set SCRIPT_DIR=%~dp0
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%legal-workstation.ps1" %*
