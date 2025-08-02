@echo off
REM Runs the integration environment in Development mode.
REM The -ForceRecreate flag ensures MindsDB agents and skills are dropped and recreated from scratch.

cd "%~dp0"

powershell.exe -ExecutionPolicy Bypass -File ".\scripts\start-env.ps1" -Environment Development -ForceRecreate

pause
