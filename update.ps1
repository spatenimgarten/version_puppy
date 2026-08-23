#requires -Version 5.1
<#
.SYNOPSIS
    Version_Puppy - Update
.DESCRIPTION
    Laedt den aktuellen main-Branch von GitHub herunter, ersetzt geaenderte
    Programmdateien im Installationsordner und startet Version_Puppy bei
    Aenderungen neu. config.json ist nicht Teil des Downloads und bleibt
    unberuehrt. Kein Git auf der Zielmaschine noetig.
#>

$InstallDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$SkriptPfad  = Join-Path $InstallDir "Version_Puppy.ps1"
$RepoZipUrl  = "https://github.com/spatenimgarten/version_puppy/archive/refs/heads/main.zip"
$TempZip     = Join-Path $env:TEMP "version_puppy_update.zip"
$TempExtract = Join-Path $env:TEMP "version_puppy_update_extract"

try {
    Invoke-WebRequest -Uri $RepoZipUrl -OutFile $TempZip -UseBasicParsing
} catch {
    Write-Host "Update fehlgeschlagen (Download): $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

if (Test-Path $TempExtract) { Remove-Item $TempExtract -Recurse -Force }
Expand-Archive -Path $TempZip -DestinationPath $TempExtract -Force
Remove-Item $TempZip -Force

$QuellOrdner = Get-ChildItem -Path $TempExtract -Directory | Select-Object -First 1

$geaendert = $false
Get-ChildItem -Path $QuellOrdner.FullName -File | Where-Object { $_.Name -ne "config.json" } | ForEach-Object {
    $ziel = Join-Path $InstallDir $_.Name
    $neu  = (-not (Test-Path $ziel)) -or ((Get-FileHash $_.FullName).Hash -ne (Get-FileHash $ziel).Hash)
    if ($neu) {
        Copy-Item -Path $_.FullName -Destination $ziel -Force
        $geaendert = $true
    }
}

Remove-Item $TempExtract -Recurse -Force

if (-not $geaendert) {
    Write-Host "Bereits aktuell."
    exit 0
}

Write-Host "Update eingespielt, starte Version_Puppy neu..."

Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like "*Version_Puppy.ps1*" } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-ExecutionPolicy Bypass -File `"$SkriptPfad`""
Write-Host "Neu gestartet."
