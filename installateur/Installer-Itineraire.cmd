@echo off
rem Itineraire : installe / met a jour Itineraire, Questie et Shortest Path Forever pour WoW Forever.
rem (lit et execute Installer-Itineraire.ps1, place a cote de ce fichier)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Installer-Itineraire.ps1" %*
echo.
pause
