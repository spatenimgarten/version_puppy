@echo off
setlocal enabledelayedexpansion

REM ============================================================
REM  Beispiel-Startdatei fuer ein einzelnes Projekt.
REM  Diese Datei in das Projektverzeichnis kopieren (oder daneben
REM  ablegen) und die Variablen unten anpassen.
REM ============================================================

REM Verzeichnis, in dem der Projektordner liegt
set PROJEKT_BASIS=C:\Projekte

REM Fester Teil des Projektnamens OHNE die "_V<Nummer>"-Endung.
REM Die aktuelle Versionsnummer wird unten automatisch ermittelt,
REM da "version" den Ordner bei jeder neuen Version umbenennt
REM (..._V001 -> ..._V002), der Pfad darf hier also NICHT fest
REM verdrahtet werden.
set PROJEKT_PREFIX=123456_TIA19

REM Lokales Verzeichnis fuer Historie und Warteschlange dieses Projekts
set DATENVERZEICHNIS=%~dp0_data

REM Dein Benutzerkuerzel, wird in jeder Version als Ersteller eingetragen
set BENUTZER_KUERZEL=AF

REM Pfad zur version_puppy.exe (Fallback: python -m version_puppy, falls
REM noch keine exe gebaut wurde)
set TOOL=%~dp0version_puppy.exe

REM ------------------------------------------------------------
REM Aktuellen Projektordner automatisch finden.
REM ------------------------------------------------------------
set QUELLVERZEICHNIS=
set GEFUNDEN=0
for /d %%D in ("%PROJEKT_BASIS%\%PROJEKT_PREFIX%_V*") do (
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

REM ------------------------------------------------------------
REM TODO (kommt in einem spaeteren Schritt): Hier die Programmier-
REM software oeffnen und warten bis sie geschlossen wird, z.B.:
REM   start /wait "" "C:\Program Files\Siemens\...\TIA Portal.exe" "%QUELLVERZEICHNIS%\Projekt.ap19"
REM Fuer den ersten Test des version-Teils erstmal weggelassen.
REM ------------------------------------------------------------

REM Oberflaeche mit drei Knoepfen (Version / Zwischenversion / Beenden)
REM oeffnen. Kommentar-Eingabe und Ausfuehrung passieren dort, nicht mehr
REM in dieser Batchdatei.
if exist "%TOOL%" (
    "%TOOL%" gui --source-dir "%QUELLVERZEICHNIS%" --data-dir "%DATENVERZEICHNIS%" --user "%BENUTZER_KUERZEL%"
) else (
    python -m version_puppy gui --source-dir "%QUELLVERZEICHNIS%" --data-dir "%DATENVERZEICHNIS%" --user "%BENUTZER_KUERZEL%"
)
