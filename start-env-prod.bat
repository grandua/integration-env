@echo off
REM Runs the integration environment in Production mode.
REM This mode is non-destructive. It will not drop existing resources.
REM The -ForceRecreate flag is explicitly disabled.

cd "%~dp0"

powershell.exe -ExecutionPolicy Bypass -File ".\scripts\start-env.ps1" -Environment Production

pause
