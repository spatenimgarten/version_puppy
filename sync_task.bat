@echo off
REM Fuer den Windows-Taskplaner gedacht: holt ausstehende Server-Kopien nach.
REM Laeuft ohne Nutzerinteraktion durch (kein "pause").
cd /d "%~dp0"
if exist "version_puppy.exe" (
    version_puppy.exe sync
) else (
    python -m version_puppy sync
)
