<#
.SYNOPSIS
    Version_Puppy - Installer
.DESCRIPTION
    Eigenstaendiger Installer - reicht als einzige Datei. Fehlt
    Version_Puppy.ps1 im selben Ordner, wird das zuletzt signierte Release
    von GitHub nachgeladen (signaturgeprueft, siehe unten - kein Download
    von main.zip mehr). Richtet danach den Autostart ein (Verknuepfung im
    Startup-Ordner des aktuellen Benutzers, kein Admin noetig) und bietet
    an, das Tool gleich zu starten. Der laufende Update-Check danach lebt
    direkt im Watcher von Version_Puppy.ps1 (stuendlich, ebenfalls
    signaturgeprueft) - kein eigener Scheduled Task mehr noetig.
#>

if ($PSVersionTable.PSVersion -lt [Version]"5.1") {
    Write-Host "PowerShell $($PSVersionTable.PSVersion) erkannt - Version_Puppy braucht mindestens 5.1." -ForegroundColor Red
    Write-Host "Windows Management Framework 5.1 herunterladen und installieren, danach Rechner neu starten:" -ForegroundColor Yellow
    Write-Host "https://www.microsoft.com/en-us/download/details.aspx?id=54616" -ForegroundColor Yellow
    Write-Host "(nur fuer Windows 7 SP1/8.1/Server 2008 R2 SP1/2012/2012 R2 - Windows 10/11 und Server 2016+ haben 5.1 bereits eingebaut.)"
    exit 1
}

$InstallDir          = Split-Path -Parent $MyInvocation.MyCommand.Path
$SkriptPfad          = Join-Path $InstallDir "Version_Puppy.ps1"
$WerkzeugePfad       = Join-Path $InstallDir "werkzeuge.json"
$BeispielPfad        = Join-Path $InstallDir "werkzeuge.example.json"
$LogPfad             = Join-Path $InstallDir "version_puppy.log"
$AllowedSignersPfad  = Join-Path $InstallDir "allowed_signers"
$UpdateManifestUrl    = "https://raw.githubusercontent.com/spatenimgarten/version_puppy/main/releases/latest/checksums.txt"
$UpdateManifestSigUrl = "$UpdateManifestUrl.sig"
$UpdatePrincipal      = "release"

# Fest eingebauter Vertrauensanker fuer die Erstinstallation - bewusst NICHT
# von GitHub nachgeladen (sonst koennte, wer nur Schreibzugriff aufs Repo hat,
# aber nicht den privaten Signier-Key "Laptop EF", bei einer Neuinstallation
# einfach seinen eigenen Key als allowed_signers unterschieben und damit die
# gesamte Signaturpruefung aushebeln). install.ps1 selbst muss deshalb weiter
# ueber einen vertrauenswuerdigen Weg auf die Zielmaschine kommen (siehe
# README) - das ist hier die Vertrauensbasis, genau wie bei jedem anderen
# Bootstrap-Installer.
#
# WICHTIG: muss inhaltlich exakt zum "release"-Eintrag in allowed_signers
# im Repo passen. Aendert sich der Key dort (Rotation), MUSS diese Zeile
# hier synchron aktualisiert werden - sonst schlaegt jede Neuinstallation
# fehl.
$AllowedSignersInhalt = "release ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDR1umaOFIBkIsTiunQF3wZGikE1zgGvtRUYT+4Lf3wf"

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
    Write-Host "Version_Puppy.ps1 fehlt noch in $InstallDir - lade letztes signiertes Release von GitHub..." -ForegroundColor Yellow

    if (-not (Get-Command ssh-keygen.exe -ErrorAction SilentlyContinue)) {
        Write-Host "ssh-keygen.exe nicht gefunden - kann das Release nicht signaturgeprueft installieren." -ForegroundColor Red
        Write-Host "Windows-Feature 'OpenSSH-Client' aktivieren (Einstellungen -> Apps -> Optionale Features), danach install.ps1 erneut ausfuehren." -ForegroundColor Yellow
        Write-Log "Erstinstallation abgebrochen: ssh-keygen.exe fehlt."
        exit 1
    }

    # Vertrauensanker liegt fest in diesem Skript (siehe Kommentar oben) -
    # wird als allowed_signers direkt an den finalen Zielort geschrieben,
    # danach von Version_Puppy.ps1 selbst fuer alle weiteren Updates
    # wiederverwendet.
    Set-Content -Path $AllowedSignersPfad -Value $AllowedSignersInhalt -Encoding UTF8 -NoNewline

    $ManifestPfad = Join-Path $env:TEMP "version_puppy_install_manifest.txt"
    $SigPfad      = Join-Path $env:TEMP "version_puppy_install_manifest.sig"
    $TempZip      = Join-Path $env:TEMP "version_puppy_install.zip"
    $TempExtract  = Join-Path $env:TEMP "version_puppy_install_extract"

    try {
        try {
            Invoke-WebRequest -Uri $UpdateManifestUrl -OutFile $ManifestPfad -UseBasicParsing
            Invoke-WebRequest -Uri $UpdateManifestSigUrl -OutFile $SigPfad -UseBasicParsing
        } catch {
            throw "Manifest-Download fehlgeschlagen: $($_.Exception.Message)"
        }

        # cmd.exe fuer die "<"-Stdin-Umleitung - siehe gleiche Stelle in
        # Version_Puppy.ps1 (Get-UpdateManifest): ssh-keygen -Y verify
        # braucht exakt die signierten Rohbytes.
        $pruefBefehl = "ssh-keygen.exe -Y verify -f `"$AllowedSignersPfad`" -I $UpdatePrincipal -n file -s `"$SigPfad`" < `"$ManifestPfad`""
        $ausgabe = & cmd.exe /c $pruefBefehl 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Manifest-Signatur ungueltig: $ausgabe"
        }

        $werte = @{}
        Get-Content -Path $ManifestPfad -Encoding UTF8 | ForEach-Object {
            if ($_ -match '^(\w+)=(.+)$') { $werte[$Matches[1]] = $Matches[2] }
        }
        if (-not $werte.version -or -not $werte.sha256 -or -not $werte.zipurl) {
            throw "Manifest signiert, aber unvollstaendig."
        }

        try {
            Invoke-WebRequest -Uri $werte.zipurl -OutFile $TempZip -UseBasicParsing
        } catch {
            throw "Release-Download fehlgeschlagen: $($_.Exception.Message)"
        }

        $istHash = (Get-FileHash -Path $TempZip -Algorithm SHA256).Hash
        if ($istHash -ne $werte.sha256.ToUpperInvariant()) {
            throw "Hash aus signiertem Manifest ($($werte.sha256)) passt nicht zum Download ($istHash)."
        }

        try {
            if (Test-Path $TempExtract) { Remove-Item $TempExtract -Recurse -Force }
            Expand-Archive -Path $TempZip -DestinationPath $TempExtract -Force
        } catch {
            # z.B. korruptes ZIP oder ein Eintrag, den Expand-Archive wegen
            # eines Pfad-Traversal-Versuchs (Zip Slip) ablehnt.
            throw "Entpacken fehlgeschlagen: $($_.Exception.Message)"
        }

        $QuellOrdner = Get-ChildItem -Path $TempExtract -Directory | Select-Object -First 1
        Get-ChildItem -Path $QuellOrdner.FullName -File | Where-Object {
            $_.Name -notin @("config.json", "werkzeuge.json", "sync.json")
        } | ForEach-Object {
            Copy-Item -Path $_.FullName -Destination (Join-Path $InstallDir $_.Name) -Force
        }

        Write-Host "Release $($werte.version) signaturgeprueft heruntergeladen nach $InstallDir." -ForegroundColor Green
        Write-Log "Erstinstallation: Release $($werte.version) signaturgeprueft nach $InstallDir heruntergeladen."
    } catch {
        Write-Host "Installation abgebrochen: $($_.Exception.Message)" -ForegroundColor Red
        Write-Log "Erstinstallation abgebrochen: $($_.Exception.Message)"
        Remove-Item -Path $AllowedSignersPfad -Force -ErrorAction SilentlyContinue
        exit 1
    } finally {
        Remove-Item -Path $ManifestPfad, $SigPfad, $TempZip -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $TempExtract -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ((-not (Test-Path $WerkzeugePfad)) -and (Test-Path $BeispielPfad)) {
    Copy-Item -Path $BeispielPfad -Destination $WerkzeugePfad
    Write-Host "werkzeuge.json aus werkzeuge.example.json angelegt - bei Bedarf anpassen." -ForegroundColor Green
}

$Verknuepfung = Join-Path ([Environment]::GetFolderPath("Startup")) "Version_Puppy.lnk"
$shell = New-Object -ComObject WScript.Shell
$lnk = $shell.CreateShortcut($Verknuepfung)
$lnk.TargetPath = "powershell.exe"
$lnk.Arguments = "-WindowStyle Minimized -ExecutionPolicy Bypass -File `"$SkriptPfad`""
$lnk.WorkingDirectory = $InstallDir
$lnk.Save()

Write-Host "Autostart eingerichtet: $Verknuepfung" -ForegroundColor Green
Write-Host "Version_Puppy startet ab der naechsten Anmeldung automatisch im Hintergrund."
Write-Log "Autostart-Verknuepfung eingerichtet: $Verknuepfung"

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
        Start-Process powershell.exe -WindowStyle Minimized -ArgumentList "-ExecutionPolicy Bypass -File `"$SkriptPfad`""
        Write-Host "Gestartet."
        Write-Log "Manuell gestartet ueber install.ps1."
    }
}
