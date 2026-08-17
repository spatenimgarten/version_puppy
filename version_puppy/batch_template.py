TEMPLATE = """@echo off
setlocal enabledelayedexpansion

REM Automatisch erstellt von "version_puppy setup" - Projekt: {prefix}

set PROJEKT_BASIS={basis}
set PROJEKT_PREFIX={prefix}
set DATENVERZEICHNIS=%~dp0_data_{prefix}
set SERVERVERZEICHNIS={server}
set BENUTZER_KUERZEL={kuerzel}
set TOOL=%~dp0version_puppy.exe

REM Aktuellen Projektordner automatisch finden (der Name aendert sich durch
REM das Umbenennen bei jeder neuen Version, z.B. ..._V001 -> ..._V002).
set QUELLVERZEICHNIS=
set GEFUNDEN=0
for /d %%D in ("%PROJEKT_BASIS%\\%PROJEKT_PREFIX%_V*") do (
    set QUELLVERZEICHNIS=%%D
    set /a GEFUNDEN+=1
)

if "%QUELLVERZEICHNIS%"=="" (
    echo FEHLER: Kein Verzeichnis "%PROJEKT_PREFIX%_V*" in "%PROJEKT_BASIS%" gefunden.
    pause
    exit /b 1
)
if %GEFUNDEN% GTR 1 (
    echo WARNUNG: Mehrere passende Verzeichnisse gefunden, verwende: %QUELLVERZEICHNIS%
)

REM Ausstehende Versionen im Hintergrund nachholen, blockiert das Oeffnen
REM der Software nicht.
if exist "%TOOL%" (
    start "" /min "%TOOL%" sync --data-dir "%DATENVERZEICHNIS%" --server-dir "%SERVERVERZEICHNIS%"
) else (
    start "" /min python -m version_puppy sync --data-dir "%DATENVERZEICHNIS%" --server-dir "%SERVERVERZEICHNIS%"
)

{software_line}

REM Oberflaeche mit drei Knoepfen (Version / Zwischenversion / Beenden).
if exist "%TOOL%" (
    "%TOOL%" gui --source-dir "%QUELLVERZEICHNIS%" --data-dir "%DATENVERZEICHNIS%" --user "%BENUTZER_KUERZEL%" --server-dir "%SERVERVERZEICHNIS%"
) else (
    python -m version_puppy gui --source-dir "%QUELLVERZEICHNIS%" --data-dir "%DATENVERZEICHNIS%" --user "%BENUTZER_KUERZEL%" --server-dir "%SERVERVERZEICHNIS%"
)
"""

SOFTWARE_TODO = (
    'REM TODO: Programmiersoftware oeffnen und warten bis sie geschlossen wird, z.B.:\n'
    'REM   start /wait "" "C:\\Program Files\\Siemens\\...\\TIA Portal.exe" "%QUELLVERZEICHNIS%\\Projekt.ap19"'
)


def render_batch(prefix, basis, server, kuerzel, software_kommando):
    if software_kommando:
        software_line = f'start /wait "" {software_kommando}'
    else:
        software_line = SOFTWARE_TODO
    return TEMPLATE.format(
        prefix=prefix, basis=basis, server=server, kuerzel=kuerzel, software_line=software_line
    )
