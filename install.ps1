<#
.SYNOPSIS
    Version_Puppy - Installer
.DESCRIPTION
    Eigenstaendiger Installer - reicht als einzige Datei. Fehlt
    Version_Puppy.ps1 im selben Ordner, wird der aktuelle Stand zuerst von
    GitHub nachgeladen. Richtet danach den Autostart ein (Verknuepfung im
    Startup-Ordner des aktuellen Benutzers, kein Admin noetig), einen
    stuendlichen Update-Check (Scheduled Task, laedt update.ps1) und bietet
    an, das Tool gleich zu starten.
#>

if ($PSVersionTable.PSVersion -lt [Version]"5.1") {
    Write-Host "PowerShell $($PSVersionTable.PSVersion) erkannt - Version_Puppy braucht mindestens 5.1." -ForegroundColor Red
    Write-Host "Windows Management Framework 5.1 herunterladen und installieren, danach Rechner neu starten:" -ForegroundColor Yellow
    Write-Host "https://www.microsoft.com/en-us/download/details.aspx?id=54616" -ForegroundColor Yellow
    Write-Host "(nur fuer Windows 7 SP1/8.1/Server 2008 R2 SP1/2012/2012 R2 - Windows 10/11 und Server 2016+ haben 5.1 bereits eingebaut.)"
    exit 1
}

$InstallDir      = Split-Path -Parent $MyInvocation.MyCommand.Path
$SkriptPfad      = Join-Path $InstallDir "Version_Puppy.ps1"
$UpdatePfad      = Join-Path $InstallDir "update.ps1"
$WerkzeugePfad   = Join-Path $InstallDir "werkzeuge.json"
$BeispielPfad    = Join-Path $InstallDir "werkzeuge.example.json"
$LogPfad         = Join-Path $InstallDir "version_puppy.log"
$RepoZipUrl      = "https://github.com/spatenimgarten/version_puppy/archive/refs/heads/main.zip"

function Write-Log {
    param([string]$Nachricht)
    try {
        # Einfache Ein-Generationen-Rotation, damit das Log nicht unbegrenzt waechst.
        if ((Test-Path $LogPfad) -and (Get-Item $LogPfad).Length -gt 2MB) {
            Move-Item -Path $LogPfad -Destination "$LogPfad.old" -Force
        }
        "$(Get-Date -Format 's') [install.ps1] $Nachricht" | Add-Content -Path $LogPfad -Encoding UTF8
    } catch { }
}

if (-not (Test-Path $SkriptPfad)) {
    Write-Host "Version_Puppy.ps1 fehlt noch in $InstallDir - lade aktuellen Stand von GitHub..." -ForegroundColor Yellow
    $TempZip     = Join-Path $env:TEMP "version_puppy_install.zip"
    $TempExtract = Join-Path $env:TEMP "version_puppy_install_extract"
    try {
        Invoke-WebRequest -Uri $RepoZipUrl -OutFile $TempZip -UseBasicParsing
    } catch {
        Write-Host "Download fehlgeschlagen: $($_.Exception.Message)" -ForegroundColor Red
        Write-Log "Download fehlgeschlagen: $($_.Exception.Message)"
        exit 1
    }
    try {
        if (Test-Path $TempExtract) { Remove-Item $TempExtract -Recurse -Force }
        Expand-Archive -Path $TempZip -DestinationPath $TempExtract -Force
    } catch {
        # z.B. korruptes ZIP oder ein Eintrag, den Expand-Archive wegen
        # eines Pfad-Traversal-Versuchs (Zip Slip) ablehnt.
        Write-Host "Entpacken fehlgeschlagen: $($_.Exception.Message)" -ForegroundColor Red
        Write-Log "Entpacken fehlgeschlagen: $($_.Exception.Message)"
        Remove-Item $TempZip -Force -ErrorAction SilentlyContinue
        exit 1
    }
    Remove-Item $TempZip -Force
    $QuellOrdner = Get-ChildItem -Path $TempExtract -Directory | Select-Object -First 1
    Get-ChildItem -Path $QuellOrdner.FullName -File | Where-Object { $_.Name -ne "config.json" } | ForEach-Object {
        Copy-Item -Path $_.FullName -Destination (Join-Path $InstallDir $_.Name) -Force
    }
    Remove-Item $TempExtract -Recurse -Force
    Write-Host "Heruntergeladen nach $InstallDir." -ForegroundColor Green
    Write-Log "Erstinstallation: von GitHub nach $InstallDir heruntergeladen."
}

if ((-not (Test-Path $WerkzeugePfad)) -and (Test-Path $BeispielPfad)) {
    Copy-Item -Path $BeispielPfad -Destination $WerkzeugePfad
    Write-Host "werkzeuge.json aus werkzeuge.example.json angelegt - bei Bedarf anpassen." -ForegroundColor Green
}

$Verknuepfung = Join-Path ([Environment]::GetFolderPath("Startup")) "Version_Puppy.lnk"
$shell = New-Object -ComObject WScript.Shell
$lnk = $shell.CreateShortcut($Verknuepfung)
$lnk.TargetPath = "powershell.exe"
$lnk.Arguments = "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$SkriptPfad`""
$lnk.WorkingDirectory = $InstallDir
$lnk.Save()

Write-Host "Autostart eingerichtet: $Verknuepfung" -ForegroundColor Green
Write-Host "Version_Puppy startet ab der naechsten Anmeldung automatisch im Hintergrund."
Write-Log "Autostart-Verknuepfung eingerichtet: $Verknuepfung"

if (Test-Path $UpdatePfad) {
    try {
        $AufgabenName = "Version_Puppy_Update"
        $Aktion  = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$UpdatePfad`""
        $Trigger = New-ScheduledTaskTrigger -Once (Get-Date) -RepetitionInterval (New-TimeSpan -Hours 1) -RepetitionDuration ([TimeSpan]::MaxValue)
        Register-ScheduledTask -TaskName $AufgabenName -Action $Aktion -Trigger $Trigger -Description "Prueft stuendlich auf ein Version_Puppy-Update von GitHub." -Force | Out-Null
        Write-Host "Automatischer Update-Check eingerichtet (stuendlich, Task '$AufgabenName')." -ForegroundColor Green
        Write-Log "Scheduled Task '$AufgabenName' eingerichtet (stuendlich)."
    } catch {
        Write-Host "Automatischer Update-Check konnte nicht eingerichtet werden ($($_.Exception.Message)) - update.ps1 muss manuell oder per eigener Aufgabenplanung ausgefuehrt werden." -ForegroundColor Yellow
        Write-Log "Scheduled Task konnte nicht eingerichtet werden: $($_.Exception.Message)"
    }
} else {
    Write-Host "update.ps1 nicht gefunden - kein automatischer Update-Check eingerichtet." -ForegroundColor Yellow
}

# Verhindert einen zweiten parallelen Watcher, falls install.ps1 auf einer
# Maschine erneut ausgefuehrt wird, auf der Version_Puppy bereits laeuft
# (sonst Race Conditions auf config.json, doppelte Popups).
$LaeuftBereits = Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like "*Version_Puppy.ps1*" }

if ($LaeuftBereits) {
    Write-Host "Version_Puppy laeuft bereits (PID $(($LaeuftBereits | ForEach-Object ProcessId) -join ', ')) - kein zusaetzlicher Start noetig." -ForegroundColor Yellow
} else {
    $antwort = Read-Host "Jetzt sofort starten, statt bis zur naechsten Anmeldung zu warten? (j/n)"
    if ($antwort -eq "j") {
        Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-ExecutionPolicy Bypass -File `"$SkriptPfad`""
        Write-Host "Gestartet."
        Write-Log "Manuell gestartet ueber install.ps1."
    }
}
