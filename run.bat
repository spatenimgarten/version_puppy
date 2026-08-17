@echo off
REM Ziehe einen Projektordner auf diese Datei, um eine neue Version zu erstellen.
REM Der Ordnername muss dem Projektnamen in config.json entsprechen.
REM Alternativ direkt aufrufen als: run.bat <projektname> ["Kommentar"]

if "%~1"=="" (
    echo Bitte einen Projektordner auf run.bat ziehen, oder aufrufen als:
    echo   run.bat ^<projektname^> ["Kommentar"]
    pause
    exit /b 1
)

set PROJECT_NAME=%~1
if exist "%~1\" (
    for %%F in ("%~1") do set PROJECT_NAME=%%~nxF
)

cd /d "%~dp0"
if exist "version_puppy.exe" (
    version_puppy.exe create "%PROJECT_NAME%" --comment "%~2"
) else (
    python -m version_puppy create "%PROJECT_NAME%" --comment "%~2"
)
pause
