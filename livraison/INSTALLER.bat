@echo off
title Installation - Controle Qualite
echo.
echo ============================================================
echo     INSTALLATION - Application Controle Qualite
echo ============================================================
echo.
echo Lancement de l'installation...
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0installer.ps1"
pause
