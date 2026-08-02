@echo off
REM Doppelklick: druckt das Bild aus der Zwischenablage.
REM Bild auf diese Datei ziehen: druckt diese Datei.
REM
REM -STA ist noetig, sonst liefert die Zwischenablage kein Bild.
REM Bewusst powershell.exe (5.1) statt pwsh: dort ist System.Drawing sicher da.

setlocal
set SKRIPT=%~dp0Drucke-Tassenbogen.ps1

if "%~1"=="" (
  powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%SKRIPT%"
) else (
  powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%SKRIPT%" -Bild "%~1"
)

echo.
pause
