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
$LogPfad     = Join-Path $InstallDir "version_puppy.log"
$RepoZipUrl  = "https://github.com/spatenimgarten/version_puppy/archive/refs/heads/main.zip"
$TempZip     = Join-Path $env:TEMP "version_puppy_update.zip"
$TempExtract = Join-Path $env:TEMP "version_puppy_update_extract"

function Write-Log {
    param([string]$Nachricht)
    try {
        # Einfache Ein-Generationen-Rotation, damit das Log nicht unbegrenzt waechst.
        if ((Test-Path $LogPfad) -and (Get-Item $LogPfad).Length -gt 2MB) {
            Move-Item -Path $LogPfad -Destination "$LogPfad.old" -Force
        }
        "$(Get-Date -Format 's') [update.ps1] $Nachricht" | Add-Content -Path $LogPfad -Encoding UTF8
    } catch { }
}

if ($PSVersionTable.PSVersion -lt [Version]"5.1") {
    # Laeuft per Scheduled Task ohne sichtbare Konsole - Log statt Popup,
    # damit ein zu altes PowerShell nicht einfach still nichts tut.
    $Nachricht = "PowerShell $($PSVersionTable.PSVersion) erkannt - Version_Puppy-Update braucht mindestens 5.1. WMF 5.1: https://www.microsoft.com/en-us/download/details.aspx?id=54616"
    Write-Host $Nachricht
    Write-Log $Nachricht
    exit 1
}

try {
    Invoke-WebRequest -Uri $RepoZipUrl -OutFile $TempZip -UseBasicParsing
} catch {
    Write-Host "Update fehlgeschlagen (Download): $($_.Exception.Message)" -ForegroundColor Red
    Write-Log "Update fehlgeschlagen (Download): $($_.Exception.Message)"
    exit 1
}

if (Test-Path $TempExtract) { Remove-Item $TempExtract -Recurse -Force }
Expand-Archive -Path $TempZip -DestinationPath $TempExtract -Force
Remove-Item $TempZip -Force

$QuellOrdner = Get-ChildItem -Path $TempExtract -Directory | Select-Object -First 1

$geaendert = $false
$geaenderteDateien = @()
Get-ChildItem -Path $QuellOrdner.FullName -File | Where-Object { $_.Name -ne "config.json" } | ForEach-Object {
    $ziel = Join-Path $InstallDir $_.Name
    $neu  = (-not (Test-Path $ziel)) -or ((Get-FileHash $_.FullName).Hash -ne (Get-FileHash $ziel).Hash)
    if ($neu) {
        Copy-Item -Path $_.FullName -Destination $ziel -Force
        $geaendert = $true
        $geaenderteDateien += $_.Name
    }
}

Remove-Item $TempExtract -Recurse -Force

if (-not $geaendert) {
    Write-Host "Bereits aktuell."
    Write-Log "Bereits aktuell, keine Aenderung."
    exit 0
}

Write-Host "Update eingespielt, starte Version_Puppy neu..."
Write-Log "Update eingespielt ($($geaenderteDateien -join ', ')), starte Version_Puppy neu..."

Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like "*Version_Puppy.ps1*" } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-ExecutionPolicy Bypass -File `"$SkriptPfad`""
Write-Host "Neu gestartet."
Write-Log "Neu gestartet."
