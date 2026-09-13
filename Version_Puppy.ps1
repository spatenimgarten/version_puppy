<#
.SYNOPSIS
    Version_Puppy - Manager Stufe 1
.DESCRIPTION
    Ueberwacht konfigurierte Engineering-Tools (z.B. TIA Portal), zeigt beim
    Beenden ein Auswahlfenster fuer Versionierung und legt lokale ZIP-Versionen an.
    Stufe 1: nur lokale Versionierung, kein Server-Sync (folgt in Stufe 2 -
    Sync-Warteliste wird hier aber schon mitgefuehrt).
#>

# ============================================================
# region Grundeinrichtung
# ============================================================

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$MinPSVersion = [Version]"5.1"
if ($PSVersionTable.PSVersion -lt $MinPSVersion) {
    [System.Windows.Forms.MessageBox]::Show(
        "PowerShell $($PSVersionTable.PSVersion) erkannt.`nDer Version_Puppy benoetigt mindestens PowerShell 5.1.`n`nWindows Management Framework 5.1 herunterladen und installieren, danach Rechner neu starten:`nhttps://www.microsoft.com/en-us/download/details.aspx?id=54616`n(nur fuer Windows 7 SP1/8.1/Server 2008 R2 SP1/2012/2012 R2 - Windows 10/11 und Server 2016+ haben 5.1 bereits eingebaut.)",
        "Version zu alt",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    ) | Out-Null
    exit 1
}

$InstallVerzeichnis = Split-Path -Parent $MyInvocation.MyCommand.Path
$SkriptPfad = Join-Path $InstallVerzeichnis "Version_Puppy.ps1"
$ConfigPfad = Join-Path $InstallVerzeichnis "config.json"
$WerkzeugePfad = Join-Path $InstallVerzeichnis "werkzeuge.json"
$SyncPfad = Join-Path $InstallVerzeichnis "sync.json"
$LogPfad = Join-Path $InstallVerzeichnis "version_puppy.log"
$AllowedSignersPfad = Join-Path $InstallVerzeichnis "allowed_signers"

# Eigene Versionsnummer dieses Codestands - bei jedem signierten Release
# erhoehen (Format X.Y.Z), sonst haelt Get-UpdateManifest ein frisch
# verifiziertes Manifest faelschlich fuer "nicht neuer".
$AktuelleVersion = [Version]"1.0.0"

# Signiertes Text-Manifest im Repo (siehe README "Release signieren") -
# .sig ist dieselbe URL mit ".sig"-Suffix.
$UpdateManifestUrl    = "https://raw.githubusercontent.com/spatenimgarten/version_puppy/main/releases/latest/checksums.txt"
$UpdateManifestSigUrl = "$UpdateManifestUrl.sig"
$UpdatePrincipal      = "release"
$UpdatePruefIntervall = [TimeSpan]::FromHours(1)

# Zeitlimit je Netzwerkoperation gegen den Serverpfad (Copy-VersionZumServer,
# Sync-VersionshistorieZumServer) - eine haengende/tote Freigabe darf das
# Versions-Popup nicht auf unbestimmte Zeit blockieren.
$ServerTimeoutSekunden = 60

function Write-Log {
    param([string]$Nachricht)
    try {
        # Einfache Ein-Generationen-Rotation, damit das Log bei einem
        # dauerhaft laufenden Hintergrunddienst nicht unbegrenzt waechst.
        if ((Test-Path $LogPfad) -and (Get-Item $LogPfad).Length -gt 2MB) {
            Move-Item -Path $LogPfad -Destination "$LogPfad.old" -Force
        }
        "$(Get-Date -Format 's') [Version_Puppy.ps1] $Nachricht" | Add-Content -Path $LogPfad -Encoding UTF8
    } catch { }
}

function Set-JsonAtomar {
    # Schreibt zuerst in eine Temp-Datei und ersetzt das Ziel dann atomar -
    # verhindert eine abgeschnittene/kaputte JSON-Datei, falls der Prozess
    # exakt waehrend des Schreibens beendet wird (z.B. ein Selbst-Neustart
    # nach eingespieltem Update). [System.IO.File]::Replace() statt
    # Move-Item -Force, da Move-Item -Force bei existierendem Ziel unter
    # Windows PowerShell 5.1 nicht garantiert atomar ist.
    #
    # WICHTIG: als drittes Argument (Backup-Pfad) NIE $null uebergeben -
    # das wirft auf diesem PowerShell-5.1/.NET-Stand zuverlaessig
    # "Der Pfad hat ein ungueltiges Format" (reproduziert unabhaengig von
    # jeglichem Aufrufkontext). Ein echter Backup-Pfad funktioniert, wird
    # danach einfach wieder geloescht.
    param([string]$Pfad, $Objekt)
    $tempPfad   = "$Pfad.tmp"
    $backupPfad = "$Pfad.bak"
    $Objekt | ConvertTo-Json -Depth 10 | Set-Content -Path $tempPfad -Encoding UTF8
    if (Test-Path $Pfad) {
        [System.IO.File]::Replace($tempPfad, $Pfad, $backupPfad)
        Remove-Item -Path $backupPfad -Force -ErrorAction SilentlyContinue
    } else {
        Move-Item -Path $tempPfad -Destination $Pfad
    }
}

# endregion

# ============================================================
# region Konfiguration: Laden / Speichern / Standardwerte
#
#   Drei getrennte Dateien, bewusst alle nicht versioniert (siehe
#   .gitignore) und rein lokal:
#   - config.json     - Projekte, Kuerzel/Trennzeichen - maschinen-
#                        spezifischer Laufzeitstand.
#   - werkzeuge.json  - Tool-Definitionen (Prozessname, Dateimuster) -
#                        aendert sich selten, laesst sich bei Bedarf einfach
#                        auf andere Maschinen kopieren, ohne Projektdaten
#                        mitzuschleppen.
#   - sync.json       - Warteliste erstellter Versionen, die noch nicht
#                        auf den Serverpfad synchronisiert wurden. Bewusst
#                        von config.json getrennt, damit Stufe 2 sie als
#                        eigenstaendige Abarbeitungs-Warteschlange lesen/
#                        leeren kann, ohne mit dem Live-Projektstand zu
#                        kollidieren.
# ============================================================

function Get-StandardConfig {
    [PSCustomObject]@{
        global = [PSCustomObject]@{
            kuerzel       = ""
            trennzeichen  = "-"
            letzteAuswahl = ""
        }
        projekte = @()
    }
}

function Get-StandardWerkzeuge {
    @(
        [PSCustomObject]@{
            name               = "TIA"
            prozessName        = "Siemens.Automation.Portal.exe"
            erweiterungsMuster = "^ap(\d+)$"
        }
    )
}

function Load-Config {
    # Wirft bei kaputtem/nicht lesbarem JSON bewusst einen normalen Fehler
    # (statt hier selbst abzubrechen) - der Aufrufer entscheidet, ob das
    # fatal ist (Erststart) oder nur dieser Zyklus uebersprungen wird
    # (periodisches Neuladen im Watcher, z.B. waehrend config.json von
    # Hand gespeichert wird).
    if (-not (Test-Path $ConfigPfad)) {
        $config = Get-StandardConfig
        Save-Config -Config $config
        return $config
    }
    $inhalt = Get-Content -Path $ConfigPfad -Raw -Encoding UTF8
    $config = $inhalt | ConvertFrom-Json

    # Einzelne Objekte aus JSON koennen beim Parsen als Skalar statt
    # Array zurueckkommen (z.B. genau 1 Projekt) - hier absichern.
    $config.projekte = @($config.projekte)

    return $config
}

function Save-Config {
    param($Config)
    Set-JsonAtomar -Pfad $ConfigPfad -Objekt $Config
}

function Load-Werkzeuge {
    # Gleiches Prinzip wie Load-Config: wirft bei kaputtem JSON, Aufrufer
    # entscheidet ueber fatal vs. Zyklus ueberspringen.
    if (-not (Test-Path $WerkzeugePfad)) {
        $werkzeuge = Get-StandardWerkzeuge
        Save-Werkzeuge -Werkzeuge $werkzeuge
        return $werkzeuge
    }
    $inhalt = Get-Content -Path $WerkzeugePfad -Raw -Encoding UTF8
    # ZWINGEND erst in eine Variable parsen, DANACH mit @() absichern -
    # "@(... | ConvertFrom-Json)" als EIN Ausdruck verschachtelt auf diesem
    # PowerShell-5.1-Stand ein Ergebnis mit 2+ Elementen faelschlich in ein
    # 1-Element-Array (reproduzierbar, unabhaengig vom Inhalt). Erst danach
    # @() drauf ist der einzige Weg, der sowohl fuer 1 als auch fuer
    # mehrere Eintraege korrekt funktioniert.
    $geparst = $inhalt | ConvertFrom-Json
    @($geparst)
}

function Save-Werkzeuge {
    param($Werkzeuge)
    Set-JsonAtomar -Pfad $WerkzeugePfad -Objekt $Werkzeuge
}

function Load-Sync {
    # Gleiches Prinzip wie Load-Config/Load-Werkzeuge: wirft bei kaputtem
    # JSON, Aufrufer entscheidet ueber Fallback.
    if (-not (Test-Path $SyncPfad)) {
        Save-Sync -Sync @()
        return @()
    }
    $inhalt = Get-Content -Path $SyncPfad -Raw -Encoding UTF8
    # Siehe Kommentar in Load-Werkzeuge - Zwischenvariable ist hier Pflicht.
    $geparst = $inhalt | ConvertFrom-Json
    @($geparst)
}

function Save-Sync {
    param($Sync)
    Set-JsonAtomar -Pfad $SyncPfad -Objekt $Sync
}

# endregion

# ============================================================
# region Aufraeumfunktion: verwaiste Projektpfade entfernen (still, beim Start)
# ============================================================

function Remove-VerwaisteProjekte {
    param($Config)
    # "-and" kurzschliesst vor Test-Path - ein Projekt mit leerem/fehlendem
    # pfad (z.B. durch manuelle Config-Bearbeitung) wirft dadurch keinen
    # Fehler, sondern gilt konsequenterweise ebenfalls als verwaist.
    $Config.projekte = @($Config.projekte | Where-Object { $_.pfad -and (Test-Path $_.pfad) })
    return $Config
}

# endregion

# ============================================================
# region Projekt-Erkennung im Ordner (Projektnummer, Werkzeug-Kandidaten)
#
#   Liefert ALLE gefundenen Projektdateien als Kandidaten zurueck -
#   keine automatische Vorauswahl. Der Nutzer waehlt im Registrierungs-
#   fenster aktiv aus, auch wenn nur ein Kandidat gefunden wurde.
# ============================================================

function Get-ProjektnummerAusOrdner {
    param([string]$Ordnerpfad)
    $ordnerName = Split-Path -Leaf $Ordnerpfad
    if ($ordnerName -match '^(\d+)') { return $Matches[1] }
    return ""
}

function Get-ProjektKandidaten {
    param(
        [string]$Ordnerpfad,
        $Werkzeuge
    )

    $kandidaten = @()
    $dateien = Get-ChildItem -Path $Ordnerpfad -File -ErrorAction SilentlyContinue

    foreach ($datei in $dateien) {
        $erweiterung = $datei.Extension.TrimStart('.')
        foreach ($werkzeug in $Werkzeuge) {
            if ($erweiterung -match $werkzeug.erweiterungsMuster) {
                $kandidaten += [PSCustomObject]@{
                    dateiname       = $datei.Name
                    werkzeug        = $werkzeug.name
                    werkzeugVersion = $Matches[1]
                    geaendert       = $datei.LastWriteTime
                }
            }
        }
    }

    # Neueste zuerst - nur zur besseren Lesbarkeit, keine Vorauswahl
    return @($kandidaten | Sort-Object geaendert -Descending)
}

# endregion

# ============================================================
# region Namensschema: naechste Versionsnummer ermitteln, Dateinamen bauen
#
#   Version:         {NR}{tz}{WERKZEUG}-V{WVERSION}{tz}V{NNN}.zip
#   Zwischenversion:  ... {tz}V{NNN}{tz}{KUERZEL}{tz}{TIMESTAMP}.zip
#
#   Parsing (fuer naechste Nummer): nur Dateien mit dem eigenen
#   Projekt-Praefix zaehlen (Zielpfad kann sich mehrere Projekte teilen),
#   direkt danach steht V{NNN}.
# ============================================================

function Get-VersionsPraefix {
    # Zentrale Stelle fuer den Praefix - wird sowohl zum Dateinamen-Bauen
    # als auch zum Wiederfinden vorhandener Versionen (Get-NaechsteVersions-
    # nummer) und fuer den Historie-Dateinamen benutzt. Muss deshalb ueberall
    # exakt gleich aussehen: Werkzeuge ohne Versionszahl in der Dateiendung
    # (z.B. LOGO!Soft Comfort, ".lsc") lassen werkzeugVersion leer - das
    # "-V"-Segment faellt dann komplett weg, statt ein leeres "-V-"
    # (Konsistenz-Bug: Get-NaechsteVersionsnummer haette gegen ein "-V-"
    # geprueft, das im tatsaechlichen Dateinamen so nie vorkommt, und immer
    # V001 gefunden).
    param($Projekt, $GlobalConfig)
    $tz = $GlobalConfig.trennzeichen
    $versionsTeil = if ([string]::IsNullOrEmpty($Projekt.werkzeugVersion)) { "" } else { "-V$($Projekt.werkzeugVersion)" }
    "$($Projekt.projektnummer)$tz$($Projekt.werkzeug)$versionsTeil$tz"
}

function Get-HoechsteVorhandeneVersionsnummer {
    # Reine Ermittlung (kein +1) - wiederverwendbar sowohl fuers Zuweisen
    # der naechsten Nummer (Get-NaechsteVersionsnummer) als auch spaeter
    # fuer eine echte Stufe 2 (z.B. Abgleich/Konflikterkennung zwischen
    # mehreren Quellen).
    param([string]$Ordner, [string]$Praefix)
    if (-not (Test-Path $Ordner)) { return 0 }

    # Nur Dateien des eigenen Projekts zaehlen - der Ordner kann sich
    # mehrere Projekte teilen (Praefix aus Projektnummer+Werkzeug trennt sie).
    $dateien = Get-ChildItem -Path $Ordner -Filter "*.zip" -File -ErrorAction SilentlyContinue |
        Where-Object { $_.BaseName.StartsWith($Praefix) }
    $nummern = @(
        foreach ($datei in $dateien) {
            $rest = $datei.BaseName.Substring($Praefix.Length)
            if ($rest -match '^V(\d+)') {
                [int]$Matches[1]
            }
        }
    )
    if ($nummern.Count -eq 0) { return 0 }
    return ($nummern | Measure-Object -Maximum).Maximum
}

function Get-NaechsteVersionsnummer {
    # Nimmt das Maximum aus lokalem Zielpfad UND (falls gerade erreichbar)
    # Serverpfad - sonst koennten zwei Maschinen, die dasselbe Projekt auf
    # denselben Server sichern, unabhaengig voneinander dieselbe naechste
    # Nummer vergeben und sich beim Server-Kopieren gegenseitig
    # ueberschreiben (Copy-VersionZumServer kopiert mit -Force).
    param(
        [string]$VersionenOrdner,
        [string]$Serverpfad,
        [string]$Praefix
    )

    $hoechste = Get-HoechsteVorhandeneVersionsnummer -Ordner $VersionenOrdner -Praefix $Praefix

    if (-not [string]::IsNullOrWhiteSpace($Serverpfad) -and (Test-Path $Serverpfad)) {
        $hoechsteAufServer = Get-HoechsteVorhandeneVersionsnummer -Ordner $Serverpfad -Praefix $Praefix
        if ($hoechsteAufServer -gt $hoechste) { $hoechste = $hoechsteAufServer }
    }

    $hoechste + 1
}

function Build-Versionsdateiname {
    param(
        $Projekt,
        $GlobalConfig,
        [int]$Nummer,
        [ValidateSet("Version", "Zwischenversion")]
        [string]$Typ
    )
    $tz     = $GlobalConfig.trennzeichen
    $nnnStr = "V{0:D3}" -f $Nummer

    $kern = "$(Get-VersionsPraefix -Projekt $Projekt -GlobalConfig $GlobalConfig)$nnnStr"

    if ($Typ -eq "Zwischenversion") {
        $timestamp = Get-Date -Format "yyyyMMddHHmmss"
        $kern = "$kern$tz$($GlobalConfig.kuerzel)$tz$timestamp"
    }

    "$kern.zip"
}

# endregion

# ============================================================
# region Lokale Versionshistorie (Kommentar je Version, Vorstufe fuer die
# geplante HTML-Historie aus Stufe 2)
#
#   Eine Datei pro Projekt im Zielpfad, ueber den Praefix vom Zielpfad
#   anderer Projekte getrennt (gleiches Prinzip wie die Versionsnummern).
# ============================================================

function Get-VersionshistorieDatei {
    param($Projekt, $GlobalConfig)
    $praefix = Get-VersionsPraefix -Projekt $Projekt -GlobalConfig $GlobalConfig
    Join-Path $Projekt.zielpfad "${praefix}historie.json"
}

function Add-VersionshistorieEintrag {
    # $Hash ist optional (z.B. leer bei einem reinen Konflikt-Hinweiseintrag,
    # der keine eigene Datei referenziert) - SHA256 des Zip-Inhalts fuer
    # normale Versionen, dient der Konflikterkennung in
    # Copy-VersionZumServer als eindeutiger Inhaltsvergleich.
    param($Projekt, $GlobalConfig, [string]$Dateiname, [string]$Typ, [string]$Kommentar, [string]$Hash = "")

    $historieDatei = Get-VersionshistorieDatei -Projekt $Projekt -GlobalConfig $GlobalConfig
    # @(...) noetig: eine Funktion, die ein 1-Element-Array zurueckgibt,
    # liefert dem Aufrufer sonst ein entpacktes Einzelobjekt statt eines
    # Arrays (PowerShell-Eigenheit) - sonst wuerde .Count spaeter fehlen
    # bzw. "+=" ein zweites Objekt statt ein Array-Element anhaengen.
    $eintraege = @(Read-VersionshistorieDatei -Pfad $historieDatei)
    $eintraege += [PSCustomObject]@{
        dateiname  = $Dateiname
        typ        = $Typ
        erstelltAm = (Get-Date).ToString("s")
        kommentar  = $Kommentar
        hash       = $Hash
    }
    Set-JsonAtomar -Pfad $historieDatei -Objekt $eintraege
}

function Read-VersionshistorieDatei {
    # Ausgelagert aus Add-VersionshistorieEintrag, da Sync-Versionshistorie-
    # ZumServer (Server-Sofortkopie-Region) dieselbe robuste Lesart auch
    # fuer die serverseitige Historie-Datei braucht.
    param([string]$Pfad)
    if (-not (Test-Path $Pfad)) { return @() }
    try {
        # Siehe Kommentar in Load-Werkzeuge - Zwischenvariable ist hier
        # Pflicht, "@(... | ConvertFrom-Json)" als ein Ausdruck verschachtelt
        # sonst ein Ergebnis mit 2+ Elementen faelschlich.
        $geparst = Get-Content -Path $Pfad -Raw -Encoding UTF8 | ConvertFrom-Json
        return @($geparst)
    } catch {
        # Kaputte Historie nicht fortschreiben und damit staendig neue
        # Fehler produzieren - lieber mit leerer Liste neu beginnen als
        # den Watcher zu gefaehrden.
        Write-Log "Versionshistorie '$Pfad' nicht lesbar, beginne neu: $($_.Exception.Message)"
        return @()
    }
}

# endregion

# ============================================================
# region Signiertes Update: Manifest pruefen, Update einspielen
#
#   Bewusst kein Git auf der Zielmaschine noetig - stattdessen wird ein
#   winziges, signiertes Text-Manifest (releases/latest/checksums.txt +
#   .sig, gepflegt im Repo) per SSH-Signatur gegen eine mitgelieferte
#   allowed_signers-Datei geprueft, bevor irgendein Code heruntergeladen
#   oder ausgefuehrt wird. Wer Schreibzugriff aufs Repo hat, aber nicht den
#   privaten Signier-Key, kann das Manifest damit nicht faelschen - nur
#   auf eine aeltere, echte Version zuruecksetzen (Rollback), da hier keine
#   monotone Versionshistorie erzwungen wird. Fuer ein internes Tool
#   bewusst in Kauf genommen statt eines vollen TUF-artigen Schemas.
# ============================================================

function Get-UpdateManifest {
    # Laedt Manifest + Signatur, prueft die Signatur per "ssh-keygen -Y
    # verify" gegen allowed_signers. Gibt bei JEDEM Fehler (Download,
    # fehlendes ssh-keygen/allowed_signers, ungueltige Signatur,
    # unvollstaendiges Manifest) $null zurueck - ein fehlgeschlagener
    # Update-Check darf den Watcher nie stoeren oder ungeprueften Inhalt
    # durchlassen.
    $manifestPfad = Join-Path $env:TEMP "version_puppy_update_manifest.txt"
    $sigPfad      = Join-Path $env:TEMP "version_puppy_update_manifest.sig"
    try {
        if (-not (Get-Command ssh-keygen.exe -ErrorAction SilentlyContinue)) {
            Write-Log "Update-Check uebersprungen: ssh-keygen.exe nicht gefunden."
            return $null
        }
        if (-not (Test-Path $AllowedSignersPfad)) {
            Write-Log "Update-Check uebersprungen: allowed_signers fehlt."
            return $null
        }

        Invoke-WebRequest -Uri $UpdateManifestUrl -OutFile $manifestPfad -UseBasicParsing
        Invoke-WebRequest -Uri $UpdateManifestSigUrl -OutFile $sigPfad -UseBasicParsing

        # cmd.exe fuer die "<"-Stdin-Umleitung - PowerShell 5.1 reicht Text
        # ueber die Pipeline zeilenweise mit eigener Zeilenumbruch-
        # Behandlung durch, ssh-keygen -Y verify braucht aber exakt die
        # signierten Rohbytes.
        $pruefBefehl = "ssh-keygen.exe -Y verify -f `"$AllowedSignersPfad`" -I $UpdatePrincipal -n file -s `"$sigPfad`" < `"$manifestPfad`""
        $ausgabe = & cmd.exe /c $pruefBefehl 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Log "Update-Manifest-Signatur ungueltig, verworfen: $ausgabe"
            return $null
        }

        $werte = @{}
        Get-Content -Path $manifestPfad -Encoding UTF8 | ForEach-Object {
            if ($_ -match '^(\w+)=(.+)$') { $werte[$Matches[1]] = $Matches[2] }
        }
        if (-not $werte.version -or -not $werte.sha256 -or -not $werte.zipurl) {
            Write-Log "Update-Manifest signiert, aber unvollstaendig - verworfen."
            return $null
        }
        return [PSCustomObject]$werte
    } catch {
        Write-Log "Update-Check fehlgeschlagen: $($_.Exception.Message)"
        return $null
    } finally {
        Remove-Item -Path $manifestPfad, $sigPfad -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-UpdateEinspielen {
    # Laedt das ZIP aus dem (bereits signaturgeprueften) Manifest, prueft
    # den Hash zusaetzlich gegen den im Manifest hinterlegten Wert (schuetzt
    # gegen einen Download-/Mirror-Fehler, nicht gegen Faelschung - das
    # erledigt die Signatur schon vorher), ersetzt die Programmdateien und
    # startet neu.
    param($Manifest)

    $TempZip     = Join-Path $env:TEMP "version_puppy_update.zip"
    $TempExtract = Join-Path $env:TEMP "version_puppy_update_extract"
    try {
        Invoke-WebRequest -Uri $Manifest.zipurl -OutFile $TempZip -UseBasicParsing

        $istHash = (Get-FileHash -Path $TempZip -Algorithm SHA256).Hash
        if ($istHash -ne $Manifest.sha256.ToUpperInvariant()) {
            throw "Hash aus signiertem Manifest ($($Manifest.sha256)) passt nicht zum Download ($istHash)."
        }

        if (Test-Path $TempExtract) { Remove-Item $TempExtract -Recurse -Force }
        Expand-Archive -Path $TempZip -DestinationPath $TempExtract -Force

        $QuellOrdner = Get-ChildItem -Path $TempExtract -Directory | Select-Object -First 1
        Get-ChildItem -Path $QuellOrdner.FullName -File | Where-Object {
            $_.Name -notin @("config.json", "werkzeuge.json", "sync.json")
        } | ForEach-Object {
            Copy-Item -Path $_.FullName -Destination (Join-Path $InstallVerzeichnis $_.Name) -Force
        }

        Write-Log "Update $($Manifest.version) eingespielt, starte neu."
        Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-ExecutionPolicy Bypass -File `"$SkriptPfad`""
        exit 0
    } catch {
        Write-Log "Update $($Manifest.version) fehlgeschlagen: $($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show(
            "Update konnte nicht eingespielt werden:`n$($_.Exception.Message)",
            "Update fehlgeschlagen",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    } finally {
        Remove-Item -Path $TempZip, $TempExtract -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# endregion

# ============================================================
# region Server-Sofortkopie (Ersatz fuer die geplante Stufe-2-Warteschlange,
# solange der Server im Moment des Speicherns erreichbar ist)
# ============================================================

function Invoke-MitNetzwerkTimeout {
    # Fuehrt eine Datei-/Netzwerkoperation in einem Hintergrund-Job mit
    # Zeitlimit aus - eine haengende/tote Netzwerkfreigabe darf das
    # Versions-Popup nicht auf unbestimmte Zeit blockieren. Variablen von
    # aussen muessen im Scriptblock ueber $using: referenziert werden
    # (Start-Job laeuft in einem eigenen Prozess ohne Zugriff auf den
    # aufrufenden Scope). Wirft bei Zeitueberschreitung oder wenn die
    # Aktion selbst einen Fehler wirft - der Aufrufer faengt das wie jeden
    # anderen Kopierfehler ab.
    param([scriptblock]$Aktion, [int]$TimeoutSekunden)
    $job = Start-Job -ScriptBlock $Aktion
    try {
        if (-not (Wait-Job -Job $job -Timeout $TimeoutSekunden)) {
            throw "Zeitueberschreitung nach $TimeoutSekunden Sekunden."
        }
        Receive-Job -Job $job -ErrorAction Stop
    } finally {
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
    }
}

function Sync-VersionshistorieZumServer {
    # Vereinigt lokale und Server-Historie nach 'dateiname' und schreibt das
    # Ergebnis auf beide Seiten zurueck. Ein Vereinigen ist hier immer
    # verlustfrei moeglich - jeder Eintrag beschreibt eine tatsaechlich
    # erstellte, unveraenderliche Datei -, anders als bei den Versions-ZIPs
    # selbst, die einen echten Namenskonflikt erzeugen koennen. Ohne diese
    # Vereinigung wuerde eine zweite Maschine die Historie-Eintraege der
    # ersten beim naechsten Speichern unbemerkt ueberschreiben, weil es
    # (anders als bei den Versions-Zips) nur einen festen Dateinamen je
    # Projekt gibt.
    param($Projekt, $GlobalConfig, [string]$LokaleHistorieDatei, [int]$TimeoutSekunden)

    $praefix             = Get-VersionsPraefix -Projekt $Projekt -GlobalConfig $GlobalConfig
    $serverHistorieDatei = Join-Path $Projekt.serverpfad "${praefix}historie.json"

    $serverEintraege = @()
    try {
        $serverVorhanden = Invoke-MitNetzwerkTimeout -TimeoutSekunden $TimeoutSekunden -Aktion { Test-Path $using:serverHistorieDatei }
        if ($serverVorhanden) {
            $serverInhalt = Invoke-MitNetzwerkTimeout -TimeoutSekunden $TimeoutSekunden -Aktion { Get-Content -Path $using:serverHistorieDatei -Raw -Encoding UTF8 }
            # Siehe Kommentar in Load-Werkzeuge - Zwischenvariable Pflicht.
            $serverGeparst = $serverInhalt | ConvertFrom-Json
            $serverEintraege = @($serverGeparst)
        }
    } catch {
        Write-Log "Server-Historie '$serverHistorieDatei' konnte nicht gelesen werden, vereinige nur mit leerer Server-Seite: $($_.Exception.Message)"
    }

    # @(...) noetig - siehe Kommentar in Add-VersionshistorieEintrag.
    $lokaleEintraege = @(Read-VersionshistorieDatei -Pfad $LokaleHistorieDatei)

    $vereinigt = @{}
    foreach ($e in $serverEintraege) { $vereinigt[$e.dateiname] = $e }
    foreach ($e in $lokaleEintraege) { $vereinigt[$e.dateiname] = $e }
    $ergebnis = @($vereinigt.Values | Sort-Object erstelltAm)

    Set-JsonAtomar -Pfad $LokaleHistorieDatei -Objekt $ergebnis

    $json                = $ergebnis | ConvertTo-Json -Depth 10
    $tempName             = "historie.tmp-$($GlobalConfig.kuerzel)-$(Get-Date -Format 'yyyyMMddHHmmss').json"
    $serverTemp           = Join-Path $Projekt.serverpfad $tempName
    $serverHistorieBackup = "$serverHistorieDatei.bak"

    Invoke-MitNetzwerkTimeout -TimeoutSekunden $TimeoutSekunden -Aktion {
        $using:json | Set-Content -Path $using:serverTemp -Encoding UTF8
    } | Out-Null
    Invoke-MitNetzwerkTimeout -TimeoutSekunden $TimeoutSekunden -Aktion {
        if (Test-Path $using:serverHistorieDatei) {
            # Kein $null als Backup-Pfad - siehe Kommentar in Set-JsonAtomar,
            # derselbe Bug gilt hier genauso.
            [System.IO.File]::Replace($using:serverTemp, $using:serverHistorieDatei, $using:serverHistorieBackup)
            Remove-Item -Path $using:serverHistorieBackup -Force -ErrorAction SilentlyContinue
        } else {
            Move-Item -Path $using:serverTemp -Destination $using:serverHistorieDatei
        }
    } | Out-Null
}

function Copy-VersionZumServer {
    # Best-Effort-Sofortkopie direkt beim Erstellen der Version - kein
    # Hintergrundabgleich noetig, solange der Serverpfad gerade erreichbar
    # ist. Jede Netzwerkoperation laeuft ueber Invoke-MitNetzwerkTimeout,
    # damit eine haengende/tote Freigabe das Popup nicht auf unbestimmte
    # Zeit blockiert - ein Timeout wird wie jeder andere Kopierfehler
    # behandelt (Ruecksprung false -> Aufrufer traegt in sync.json ein).
    #
    # Schreibt das Zip zuerst unter einem eindeutigen Zwischennamen
    # (Kuerzel + Zeitstempel) und benennt danach auf den echten Dateinamen
    # um, damit bei einem Abbruch mitten im Kopieren nie eine halbfertige
    # Datei unter dem echten Namen auf dem Server liegt.
    #
    # Existiert der Zielname auf dem Server schon mit ANDEREM Inhalt
    # (Hash-Vergleich) - z.B. weil zwei Maschinen im selben Moment dieselbe
    # naechste Nummer vergeben haben (Restrisiko trotz Get-Naechste-
    # Versionsnummers Server-Check, siehe dort) -, wird NICHT
    # ueberschrieben: unser Stand landet unter einem "_KONFLIKT_"-Namen
    # daneben, ein Historie-Eintrag und eine Meldung markieren das fuer
    # die manuelle Aufloesung.
    param($Projekt, $GlobalConfig, [string]$QuellZip, [string]$Dateiname, [string]$ZipHash, [string]$LokaleHistorieDatei)

    if ([string]::IsNullOrWhiteSpace($Projekt.serverpfad)) { return $false }

    try {
        $serverErreichbar = Invoke-MitNetzwerkTimeout -TimeoutSekunden $ServerTimeoutSekunden -Aktion { Test-Path $using:Projekt.serverpfad }
    } catch {
        Write-Log "Erreichbarkeitspruefung fuer Serverpfad '$($Projekt.serverpfad)' fehlgeschlagen: $($_.Exception.Message)"
        $serverErreichbar = $false
    }
    if (-not $serverErreichbar) {
        Write-Log "Serverpfad '$($Projekt.serverpfad)' nicht erreichbar, '$Dateiname' bleibt in Sync-Warteliste."
        return $false
    }

    $zielDateiname  = $Dateiname
    $zielEndgueltig = Join-Path $Projekt.serverpfad $zielDateiname
    $zielTemp       = $null

    try {
        $vorhanden = Invoke-MitNetzwerkTimeout -TimeoutSekunden $ServerTimeoutSekunden -Aktion { Test-Path $using:zielEndgueltig }
        if ($vorhanden) {
            $vorhandenerHash = Invoke-MitNetzwerkTimeout -TimeoutSekunden $ServerTimeoutSekunden -Aktion { (Get-FileHash -Path $using:zielEndgueltig -Algorithm SHA256).Hash }
            if ($vorhandenerHash -eq $ZipHash) {
                Write-Log "Version '$Dateiname' liegt inhaltsgleich bereits auf dem Server, nichts zu tun."
                return $true
            }

            $zielDateiname  = $Dateiname -replace '\.zip$', "_KONFLIKT_$(Get-Date -Format 'yyyyMMdd-HHmmss').zip"
            $zielEndgueltig = Join-Path $Projekt.serverpfad $zielDateiname
            Write-Log "Konflikt fuer '$($Projekt.name)': Server hat unter '$Dateiname' bereits einen anderen Inhalt - lege unseren Stand als '$zielDateiname' ab, manuelle Aufloesung noetig."
            [System.Windows.Forms.MessageBox]::Show(
                "Auf dem Server liegt unter '$Dateiname' bereits eine andere Version (vermutlich zeitgleich von einer anderen Maschine erstellt).`n`nDeine Version wurde zusaetzlich als '$zielDateiname' abgelegt - bitte beide manuell vergleichen und den Konflikt aufloesen.",
                "Konflikt auf dem Server",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            ) | Out-Null
            Add-VersionshistorieEintrag -Projekt $Projekt -GlobalConfig $GlobalConfig -Dateiname $zielDateiname -Typ "Konflikt" -Kommentar "Kollidierte auf dem Server mit vorhandenem '$Dateiname' - manuell aufloesen." -Hash $ZipHash
        }

        $tempName = "$zielDateiname.tmp-$($GlobalConfig.kuerzel)-$(Get-Date -Format 'yyyyMMddHHmmss')"
        $zielTemp = Join-Path $Projekt.serverpfad $tempName

        # Vor dem Kopieren aufraeumen, falls von einem frueheren, mitten
        # abgebrochenen Versuch mit demselben Zwischennamen noch etwas
        # liegt - haelt das Serververzeichnis sauber statt Leichen
        # anzusammeln.
        Invoke-MitNetzwerkTimeout -TimeoutSekunden $ServerTimeoutSekunden -Aktion {
            Remove-Item -Path $using:zielTemp -Force -ErrorAction SilentlyContinue
        } | Out-Null

        Invoke-MitNetzwerkTimeout -TimeoutSekunden $ServerTimeoutSekunden -Aktion {
            Copy-Item -Path $using:QuellZip -Destination $using:zielTemp -Force
        } | Out-Null
        Invoke-MitNetzwerkTimeout -TimeoutSekunden $ServerTimeoutSekunden -Aktion {
            Move-Item -Path $using:zielTemp -Destination $using:zielEndgueltig -Force
        } | Out-Null
        Write-Log "Version '$zielDateiname' zusaetzlich auf Serverpfad kopiert."

        try {
            Sync-VersionshistorieZumServer -Projekt $Projekt -GlobalConfig $GlobalConfig -LokaleHistorieDatei $LokaleHistorieDatei -TimeoutSekunden $ServerTimeoutSekunden
        } catch {
            Write-Log "Historie konnte nicht mit dem Server abgeglichen werden: $($_.Exception.Message)"
        }

        return $true
    } catch {
        Write-Log "Kopieren von '$Dateiname' auf Serverpfad fehlgeschlagen, bleibt in Sync-Warteliste: $($_.Exception.Message)"
        if ($zielTemp) {
            try { Invoke-MitNetzwerkTimeout -TimeoutSekunden $ServerTimeoutSekunden -Aktion { Remove-Item -Path $using:zielTemp -Force -ErrorAction SilentlyContinue } | Out-Null } catch { }
        }
        return $false
    }
}

# endregion

# ============================================================
# region Version erstellen (ZIP, ohne Versionen-Unterordner selbst)
# ============================================================

function New-ProjektVersion {
    param(
        $Projekt,
        $Config,
        [ValidateSet("Version", "Zwischenversion")]
        [string]$Typ,
        [string]$Kommentar = ""
    )

    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    $zielPfad = $null
    try {
        $versionenOrdner = $Projekt.zielpfad
        if ([string]::IsNullOrWhiteSpace($versionenOrdner)) {
            # Kann bei Projekten aus einer aelteren Version ohne Zielpfad-Feld
            # vorkommen - lieber sauber melden als mit Test-Path abstuerzen.
            throw "Projekt '$($Projekt.name)' hat keinen Zielpfad hinterlegt."
        }
        if (-not (Test-Path $versionenOrdner)) {
            New-Item -ItemType Directory -Path $versionenOrdner -Force | Out-Null
        }

        $praefix   = Get-VersionsPraefix -Projekt $Projekt -GlobalConfig $Config.global
        $nummer    = Get-NaechsteVersionsnummer -VersionenOrdner $versionenOrdner -Serverpfad $Projekt.serverpfad -Praefix $praefix
        $dateiname = Build-Versionsdateiname -Projekt $Projekt -GlobalConfig $Config.global -Nummer $nummer -Typ $Typ
        $zielPfad  = Join-Path $versionenOrdner $dateiname

        $zip = [System.IO.Compression.ZipFile]::Open($zielPfad, [System.IO.Compression.ZipArchiveMode]::Create)
        try {
            $basisLaenge = $Projekt.pfad.TrimEnd('\').Length
            Get-ChildItem -Path $Projekt.pfad -Recurse -File | Where-Object {
                $_.FullName -notlike "$versionenOrdner*"
            } | ForEach-Object {
                $relativerPfad = $_.FullName.Substring($basisLaenge).TrimStart('\')
                [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $_.FullName, $relativerPfad) | Out-Null
            }
        } finally {
            $zip.Dispose()
        }
    } catch {
        # Zip evtl. nur teilweise geschrieben (z.B. Datei war noch gesperrt),
        # oder Fehler schon davor (z.B. fehlender Zielpfad) - verwaiste/
        # korrupte Zip nicht liegen lassen, Watcher darf nicht sterben.
        if ($zielPfad) {
            Remove-Item -Path $zielPfad -Force -ErrorAction SilentlyContinue
        }
        Write-Log "Version fuer '$($Projekt.name)' fehlgeschlagen: $($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show(
            "Version konnte nicht erstellt werden:`n$($_.Exception.Message)",
            "Fehler bei Versionierung",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
        return $null
    }

    $Projekt.letzteVersion   = $dateiname
    $Projekt.letzteAenderung = (Get-Date).ToString("s")
    Write-Log "Version '$dateiname' fuer '$($Projekt.name)' erstellt."

    # SHA256 des fertigen Zips - dient sowohl als Beleg in der Historie als
    # auch Copy-VersionZumServer als Inhaltsvergleich zur Konflikterkennung.
    try {
        $zipHash = (Get-FileHash -Path $zielPfad -Algorithm SHA256).Hash
    } catch {
        Write-Log "Hash fuer '$dateiname' konnte nicht berechnet werden: $($_.Exception.Message)"
        $zipHash = ""
    }

    $historieDatei = Get-VersionshistorieDatei -Projekt $Projekt -GlobalConfig $Config.global
    try {
        Add-VersionshistorieEintrag -Projekt $Projekt -GlobalConfig $Config.global -Dateiname $dateiname -Typ $Typ -Kommentar $Kommentar -Hash $zipHash
    } catch {
        # Historie ist eine Zugabe, kein Kriterium fuer Erfolg/Misserfolg der
        # Version selbst - Fehler hier loggen, aber die bereits erstellte
        # Version nicht als fehlgeschlagen melden.
        Write-Log "Versionshistorie fuer '$dateiname' konnte nicht geschrieben werden: $($_.Exception.Message)"
    }

    # Sofortkopie auf den Server versuchen - nur wenn die (Server gerade
    # nicht erreichbar/Kopierfehler) nicht klappt, landet die Version zum
    # spaeteren Nachholen in der sync.json-Warteliste. Beides eigener
    # try/catch wie bei der Historie: kein Kriterium fuer den Erfolg der
    # Version selbst.
    $aufServerKopiert = $false
    try {
        $aufServerKopiert = Copy-VersionZumServer -Projekt $Projekt -GlobalConfig $Config.global -QuellZip $zielPfad -Dateiname $dateiname -ZipHash $zipHash -LokaleHistorieDatei $historieDatei
    } catch {
        Write-Log "Server-Sofortkopie fuer '$dateiname' unerwartet fehlgeschlagen: $($_.Exception.Message)"
    }

    if (-not $aufServerKopiert) {
        try {
            $sync = Load-Sync
            $sync += [PSCustomObject]@{
                projektpfad = $Projekt.pfad
                zielpfad    = $Projekt.zielpfad
                serverpfad  = $Projekt.serverpfad
                dateiname   = $dateiname
                kommentar   = $Kommentar
                erstelltAm  = (Get-Date).ToString("s")
                status      = "wartend"
            }
            Save-Sync -Sync $sync
        } catch {
            Write-Log "Sync-Eintrag fuer '$dateiname' konnte nicht gespeichert werden: $($_.Exception.Message)"
        }
    }

    return $dateiname
}

# endregion

# ============================================================
# region GUI: Ordnerauswahl mit Adressleiste
#
#   Das klassische FolderBrowserDialog-Baumfenster hat unter .NET
#   Framework/WinForms 5.1 keine Adressleiste - ein Pfad (z.B. ein
#   UNC-Serverpfad) laesst sich nicht reinkopieren, nur durchklicken.
#   OpenFileDialog mit deaktivierter Datei-Existenzpruefung zeigt
#   stattdessen den modernen Explorer-Dialog samt Adressleiste; man
#   navigiert zum gewuenschten Ordner und bestaetigt (der eingetragene
#   Dateiname wird ignoriert, nur der Elternordner zaehlt).
# ============================================================

function Show-OrdnerAuswahlDialog {
    param([string]$Titel)
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title = $Titel
    $dlg.ValidateNames = $false
    $dlg.CheckFileExists = $false
    $dlg.CheckPathExists = $true
    $dlg.FileName = "Ordner auswaehlen"
    if ($dlg.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { return $null }
    Split-Path -Parent $dlg.FileName
}

# endregion

# ============================================================
# region GUI: Neues Projekt registrieren
# ============================================================

function Show-NeuesProjektFenster {
    param(
        [string]$Ordnerpfad,
        $Kandidaten
    )

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Neues Projekt registrieren"
    $form.Size = New-Object System.Drawing.Size(420, 460)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.TopMost = $true

    $y = 15
    $lblPfad = New-Object System.Windows.Forms.Label
    $lblPfad.Text = "Pfad: $Ordnerpfad"
    $lblPfad.AutoSize = $true
    $lblPfad.MaximumSize = New-Object System.Drawing.Size(380, 0)
    $lblPfad.Location = New-Object System.Drawing.Point(15, $y)
    $form.Controls.Add($lblPfad)
    $y += 35

    $lblListe = New-Object System.Windows.Forms.Label
    $lblListe.Text = "Gefundene Projektdatei(en) - bitte auswaehlen:"
    $lblListe.AutoSize = $true
    $lblListe.Location = New-Object System.Drawing.Point(15, $y)
    $form.Controls.Add($lblListe)
    $y += 20

    $liste = New-Object System.Windows.Forms.ListBox
    $liste.Location = New-Object System.Drawing.Point(15, $y)
    $liste.Size = New-Object System.Drawing.Size(385, 90)
    $liste.SelectionMode = "One"
    foreach ($k in $Kandidaten) {
        [void]$liste.Items.Add("$($k.werkzeug) V$($k.werkzeugVersion)  -  $($k.dateiname)  (geaendert: $($k.geaendert.ToString('dd.MM.yyyy HH:mm')))")
    }
    # bewusst KEINE Vorauswahl, auch bei nur einem Kandidaten
    $liste.ClearSelected()
    $form.Controls.Add($liste)
    $y += 100

    if ($Kandidaten.Count -eq 0) {
        $lblKeine = New-Object System.Windows.Forms.Label
        $lblKeine.Text = "Keine bekannte Projektdatei gefunden. Registrierung nicht moeglich."
        $lblKeine.ForeColor = [System.Drawing.Color]::DarkRed
        $lblKeine.AutoSize = $true
        $lblKeine.Location = New-Object System.Drawing.Point(15, $y)
        $form.Controls.Add($lblKeine)
        $y += 20
    }

    $lblNr = New-Object System.Windows.Forms.Label
    $lblNr.Text = "Projektnummer:"
    $lblNr.Location = New-Object System.Drawing.Point(15, $y)
    $lblNr.AutoSize = $true
    $form.Controls.Add($lblNr)
    $txtNr = New-Object System.Windows.Forms.TextBox
    $txtNr.Text = Get-ProjektnummerAusOrdner -Ordnerpfad $Ordnerpfad
    $txtNr.Location = New-Object System.Drawing.Point(150, ($y - 3))
    $txtNr.Width = 200
    $form.Controls.Add($txtNr)
    $y += 30

    $lblName = New-Object System.Windows.Forms.Label
    $lblName.Text = "Sprechender Name:"
    $lblName.Location = New-Object System.Drawing.Point(15, $y)
    $lblName.AutoSize = $true
    $form.Controls.Add($lblName)
    $txtName = New-Object System.Windows.Forms.TextBox
    $txtName.Text = ""
    $txtName.Location = New-Object System.Drawing.Point(150, ($y - 3))
    $txtName.Width = 200
    $form.Controls.Add($txtName)
    $y += 30

    $lblZiel = New-Object System.Windows.Forms.Label
    $lblZiel.Text = "Zielpfad (Versionen):"
    $lblZiel.Location = New-Object System.Drawing.Point(15, $y)
    $lblZiel.AutoSize = $true
    $form.Controls.Add($lblZiel)
    $txtZiel = New-Object System.Windows.Forms.TextBox
    $elternordner = Split-Path -Parent $Ordnerpfad
    $txtZiel.Text = Join-Path $elternordner "Versionen"
    $txtZiel.Location = New-Object System.Drawing.Point(150, ($y - 3))
    $txtZiel.Width = 170
    $form.Controls.Add($txtZiel)
    $btnZielDurchsuchen = New-Object System.Windows.Forms.Button
    $btnZielDurchsuchen.Text = "..."
    $btnZielDurchsuchen.Location = New-Object System.Drawing.Point(325, ($y - 4))
    $btnZielDurchsuchen.Width = 30
    $btnZielDurchsuchen.Add_Click({
        $gewaehlt = Show-OrdnerAuswahlDialog -Titel "Zielordner fuer Versionen auswaehlen"
        if ($gewaehlt) { $txtZiel.Text = $gewaehlt }
    })
    $form.Controls.Add($btnZielDurchsuchen)
    $y += 30

    $lblServer = New-Object System.Windows.Forms.Label
    $lblServer.Text = "Serverpfad:"
    $lblServer.Location = New-Object System.Drawing.Point(15, $y)
    $lblServer.AutoSize = $true
    $form.Controls.Add($lblServer)
    $txtServer = New-Object System.Windows.Forms.TextBox
    $txtServer.Text = ""
    $txtServer.Location = New-Object System.Drawing.Point(150, ($y - 3))
    $txtServer.Width = 170
    $form.Controls.Add($txtServer)
    $btnServerDurchsuchen = New-Object System.Windows.Forms.Button
    $btnServerDurchsuchen.Text = "..."
    $btnServerDurchsuchen.Location = New-Object System.Drawing.Point(325, ($y - 4))
    $btnServerDurchsuchen.Width = 30
    $btnServerDurchsuchen.Add_Click({
        # Der Dialog hat wie Explorer selbst einen "Neuer Ordner"-Button -
        # deckt das Anlegen eines noch nicht existierenden Serverordners
        # ab, ohne dass Version_Puppy selbst automatisiert Ordner auf
        # einer Netzwerkfreigabe anlegen muss.
        $gewaehlt = Show-OrdnerAuswahlDialog -Titel "Serverordner fuer diese Version auswaehlen"
        if ($gewaehlt) { $txtServer.Text = $gewaehlt }
    })
    $form.Controls.Add($btnServerDurchsuchen)
    $y += 40

    $script:neuesProjektErgebnis = $null

    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Text = "Registrieren"
    $btnOk.Location = New-Object System.Drawing.Point(150, $y)
    $btnOk.Add_Click({
        if ($liste.SelectedIndex -lt 0) {
            [System.Windows.Forms.MessageBox]::Show(
                "Bitte zuerst eine Projektdatei aus der Liste auswaehlen.",
                "Auswahl fehlt",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            ) | Out-Null
            return
        }
        if ([string]::IsNullOrWhiteSpace($txtZiel.Text)) {
            [System.Windows.Forms.MessageBox]::Show(
                "Bitte einen Zielpfad fuer die Versionen angeben.",
                "Zielpfad fehlt",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            ) | Out-Null
            return
        }
        if ([string]::IsNullOrWhiteSpace($txtServer.Text)) {
            [System.Windows.Forms.MessageBox]::Show(
                "Bitte einen Serverpfad angeben.",
                "Serverpfad fehlt",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            ) | Out-Null
            return
        }
        $gewaehlterKandidat = $Kandidaten[$liste.SelectedIndex]
        $script:neuesProjektErgebnis = [PSCustomObject]@{
            pfad            = $Ordnerpfad
            zielpfad        = $txtZiel.Text
            serverpfad      = $txtServer.Text
            projektnummer   = $txtNr.Text
            name            = $txtName.Text
            werkzeug        = $gewaehlterKandidat.werkzeug
            werkzeugVersion = $gewaehlterKandidat.werkzeugVersion
            letzteVersion   = ""
            letzteAenderung = ""
            erstelltAm      = (Get-Date).ToString("s")
        }
        $form.Close()
    })
    $form.Controls.Add($btnOk)

    $btnAbbrechen = New-Object System.Windows.Forms.Button
    $btnAbbrechen.Text = "Abbrechen"
    $btnAbbrechen.Location = New-Object System.Drawing.Point(260, $y)
    $btnAbbrechen.Add_Click({ $form.Close() })
    $form.Controls.Add($btnAbbrechen)

    [void]$form.ShowDialog()
    return $script:neuesProjektErgebnis
}

# endregion

# ============================================================
# region GUI: Versions-Popup nach Tool-Ende
# ============================================================

function Show-VersionPopup {
    param($Config, $Werkzeuge)

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Version_Puppy"
    $form.Size = New-Object System.Drawing.Size(420, 270)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.TopMost = $true

    $lblProjekt = New-Object System.Windows.Forms.Label
    $lblProjekt.Text = "Projekt:"
    $lblProjekt.Location = New-Object System.Drawing.Point(15, 15)
    $lblProjekt.AutoSize = $true
    $form.Controls.Add($lblProjekt)

    $combo = New-Object System.Windows.Forms.ComboBox
    $combo.Location = New-Object System.Drawing.Point(80, 12)
    $combo.Width = 240
    $combo.DropDownStyle = "DropDownList"
    foreach ($p in $Config.projekte) { [void]$combo.Items.Add($p.name) }
    if ($combo.Items.Count -gt 0) {
        $letzterIndex = 0
        for ($i = 0; $i -lt $Config.projekte.Count; $i++) {
            if ($Config.projekte[$i].pfad -eq $Config.global.letzteAuswahl) { $letzterIndex = $i }
        }
        $combo.SelectedIndex = $letzterIndex
    }
    $form.Controls.Add($combo)

    $btnNeu = New-Object System.Windows.Forms.Button
    $btnNeu.Text = "Neu..."
    $btnNeu.Location = New-Object System.Drawing.Point(330, 11)
    $btnNeu.Width = 60
    $form.Controls.Add($btnNeu)

    $lblPfad = New-Object System.Windows.Forms.Label
    $lblPfad.Text = ""
    $lblPfad.Location = New-Object System.Drawing.Point(15, 45)
    $lblPfad.AutoSize = $true
    $lblPfad.ForeColor = [System.Drawing.Color]::Gray
    $form.Controls.Add($lblPfad)

    $aktualisierePfad = {
        if ($combo.SelectedIndex -ge 0) {
            $lblPfad.Text = $Config.projekte[$combo.SelectedIndex].pfad
        }
    }
    $combo.Add_SelectedIndexChanged($aktualisierePfad)
    & $aktualisierePfad

    $btnNeu.Add_Click({
        $gewaehlterOrdner = Show-OrdnerAuswahlDialog -Titel "Projektordner auswaehlen"
        if ($gewaehlterOrdner) {
            $kandidaten = Get-ProjektKandidaten -Ordnerpfad $gewaehlterOrdner -Werkzeuge $Werkzeuge
            $neuesProjekt = Show-NeuesProjektFenster -Ordnerpfad $gewaehlterOrdner -Kandidaten $kandidaten
            if ($neuesProjekt) {
                $Config.projekte += $neuesProjekt
                Save-Config -Config $Config
                [void]$combo.Items.Add($neuesProjekt.name)
                $combo.SelectedIndex = $combo.Items.Count - 1
            }
        }
    })

    $lblKommentar = New-Object System.Windows.Forms.Label
    $lblKommentar.Text = "Kommentar (optional):"
    $lblKommentar.Location = New-Object System.Drawing.Point(15, 70)
    $lblKommentar.AutoSize = $true
    $form.Controls.Add($lblKommentar)

    $txtKommentar = New-Object System.Windows.Forms.TextBox
    $txtKommentar.Location = New-Object System.Drawing.Point(15, 88)
    $txtKommentar.Width = 385
    $form.Controls.Add($txtKommentar)

    $script:popupAktion = $null

    $btnZwischen = New-Object System.Windows.Forms.Button
    $btnZwischen.Text = "Zwischenversion"
    $btnZwischen.Size = New-Object System.Drawing.Size(120, 30)
    $btnZwischen.Location = New-Object System.Drawing.Point(15, 120)
    $btnZwischen.Add_Click({ $script:popupAktion = "Zwischenversion"; $form.Close() })
    $form.Controls.Add($btnZwischen)

    $btnVersion = New-Object System.Windows.Forms.Button
    $btnVersion.Text = "Version"
    $btnVersion.Size = New-Object System.Drawing.Size(120, 30)
    $btnVersion.Location = New-Object System.Drawing.Point(150, 120)
    $btnVersion.Add_Click({ $script:popupAktion = "Version"; $form.Close() })
    $form.Controls.Add($btnVersion)

    $btnBeenden = New-Object System.Windows.Forms.Button
    $btnBeenden.Text = "Beenden (keine Version)"
    $btnBeenden.Size = New-Object System.Drawing.Size(255, 30)
    $btnBeenden.Location = New-Object System.Drawing.Point(15, 160)
    $btnBeenden.Add_Click({ $script:popupAktion = "Beenden"; $form.Close() })
    $form.Controls.Add($btnBeenden)

    # Enter = sicherer Default (keine Version) - Zwischenversion/Version
    # bleiben bewusst nur per expliziten Klick erreichbar. Gilt auch aus
    # dem Kommentarfeld heraus (einzeiliges TextBox konsumiert Enter nicht).
    $form.AcceptButton = $btnBeenden

    try {
        $syncAnzahl = @(Load-Sync).Count
    } catch {
        $syncAnzahl = "?"
    }
    $lblSync = New-Object System.Windows.Forms.Label
    $lblSync.Text = "$syncAnzahl Version(en) warten auf Sync"
    $lblSync.Location = New-Object System.Drawing.Point(15, 205)
    $lblSync.AutoSize = $true
    $lblSync.ForeColor = [System.Drawing.Color]::Gray
    $form.Controls.Add($lblSync)

    if ($script:verfuegbaresUpdate) {
        $form.Height += 35

        $lblUpdate = New-Object System.Windows.Forms.Label
        $lblUpdate.Text = "Update $($script:verfuegbaresUpdate.version) verfuegbar (Signatur geprueft)"
        $lblUpdate.Location = New-Object System.Drawing.Point(15, 228)
        $lblUpdate.AutoSize = $true
        $form.Controls.Add($lblUpdate)

        $btnUpdate = New-Object System.Windows.Forms.Button
        $btnUpdate.Text = "Jetzt aktualisieren"
        $btnUpdate.Size = New-Object System.Drawing.Size(140, 25)
        $btnUpdate.Location = New-Object System.Drawing.Point(260, 223)
        # Schliesst das Popup und ersetzt danach sofort den laufenden Code -
        # bewusst nur per explizitem Klick erreichbar, nie automatisch.
        $btnUpdate.Add_Click({
            $form.Close()
            Invoke-UpdateEinspielen -Manifest $script:verfuegbaresUpdate
        })
        $form.Controls.Add($btnUpdate)
    }

    [void]$form.ShowDialog()

    if ($combo.SelectedIndex -lt 0 -or $null -eq $script:popupAktion) { return }

    $ausgewaehltesProjekt = $Config.projekte[$combo.SelectedIndex]
    $Config.global.letzteAuswahl = $ausgewaehltesProjekt.pfad

    switch ($script:popupAktion) {
        "Version"         { New-ProjektVersion -Projekt $ausgewaehltesProjekt -Config $Config -Typ "Version" -Kommentar $txtKommentar.Text | Out-Null }
        "Zwischenversion" { New-ProjektVersion -Projekt $ausgewaehltesProjekt -Config $Config -Typ "Zwischenversion" -Kommentar $txtKommentar.Text | Out-Null }
        "Beenden"         { } # bewusst keine Aktion
    }

    Save-Config -Config $Config
}

# endregion

# ============================================================
# region Watcher: Ueberwacht konfigurierte Tool-Prozesse (Polling)
#
#   Bewusst per Polling statt Win32_ProcessStopTrace (WMI-Trace-Events
#   brauchen i.d.R. Admin-Rechte) - so laeuft es auf allen VMs gleich,
#   ohne erhoehte Rechte vorauszusetzen.
# ============================================================

function Test-WerkzeugLaeuft {
    # Manche Werkzeuge laufen unter einem generischen Wirtsprozess (z.B.
    # LOGO!Soft Comfort als javaw.exe) - reiner Prozessname-Abgleich wuerde
    # dann jeden Prozess mit diesem Namen faelschlich als Treffer werten.
    # Optionales kommandozeilenMuster grenzt das per Regex auf die
    # tatsaechliche Kommandozeile ein; ohne das Feld bleibt das Verhalten
    # unveraendert (reiner Get-Process-Namensabgleich).
    param($Werkzeug)

    $prozessBasisname = $Werkzeug.prozessName -replace '\.exe$', ''

    if ($Werkzeug.kommandozeilenMuster) {
        $treffer = Get-CimInstance Win32_Process -Filter "Name='$($Werkzeug.prozessName)'" -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -match $Werkzeug.kommandozeilenMuster }
        return [bool]$treffer
    }

    return [bool](Get-Process -Name $prozessBasisname -ErrorAction SilentlyContinue)
}

function Start-Watcher {
    param($Config, $Werkzeuge)

    $laufendVorher = @{}
    foreach ($werkzeug in $Werkzeuge) {
        $laufendVorher[$werkzeug.name] = Test-WerkzeugLaeuft -Werkzeug $werkzeug
    }

    $script:letzteUpdatePruefung = [DateTime]::MinValue
    $script:verfuegbaresUpdate   = $null

    while ($true) {
        Start-Sleep -Seconds 3

        try {
            # Laeuft im selben 3s-Zyklus mit, prueft aber nur stuendlich -
            # ersetzt den frueheren eigenen Scheduled Task fuer update.ps1.
            # Reines Lesen+Verifizieren, kein Codeaustausch: der passiert
            # erst auf expliziten Klick im Popup (Invoke-UpdateEinspielen).
            if ((Get-Date) - $script:letzteUpdatePruefung -ge $UpdatePruefIntervall) {
                $script:letzteUpdatePruefung = Get-Date
                $manifest = Get-UpdateManifest
                if ($manifest -and [Version]$manifest.version -gt $AktuelleVersion) {
                    $script:verfuegbaresUpdate = $manifest
                    Write-Log "Verifiziertes Update verfuegbar: $($manifest.version)"
                }
            }

            try {
                $Config = Load-Config
            } catch {
                # Transienter Lesefehler (z.B. config.json wird gerade von
                # Hand gespeichert) - bisherigen Stand behalten, naechster
                # Zyklus in 3s versucht es erneut, statt den Watcher zu
                # beenden.
                Write-Log "config.json konnte nicht gelesen werden, behalte bisherigen Stand: $($_.Exception.Message)"
                continue
            }
            $Config = Remove-VerwaisteProjekte -Config $Config

            try {
                $Werkzeuge = Load-Werkzeuge
            } catch {
                # Gleiches Prinzip fuer werkzeuge.json (z.B. gerade von Hand
                # kopiert/bearbeitet) - bisherige Liste behalten.
                Write-Log "werkzeuge.json konnte nicht gelesen werden, behalte bisherige Liste: $($_.Exception.Message)"
            }

            foreach ($werkzeug in $Werkzeuge) {
                $laeuftJetzt = Test-WerkzeugLaeuft -Werkzeug $werkzeug

                if ($laufendVorher[$werkzeug.name] -eq $true -and $laeuftJetzt -eq $false) {
                    Show-VersionPopup -Config $Config -Werkzeuge $Werkzeuge
                    try {
                        $Config = Load-Config
                    } catch {
                        # Popup hat evtl. schon gespeichert - bei Lesefehler
                        # direkt danach einfach beim vorherigen $Config bleiben.
                        Write-Log "config.json nach Popup nicht lesbar, behalte bisherigen Stand: $($_.Exception.Message)"
                    }
                }

                $laufendVorher[$werkzeug.name] = $laeuftJetzt
            }
        } catch {
            # Letztes Sicherheitsnetz: irgendein unerwarteter Fehler in
            # diesem Zyklus (z.B. kaputter Regex in werkzeuge.json, ein
            # Projekt mit fehlendem Feld) darf den Watcher nicht toeten -
            # loggen und mit dem naechsten Zyklus in 3s weitermachen.
            Write-Log "Unerwarteter Fehler im Watcher-Zyklus, mache weiter: $($_.Exception.Message)"
        }
    }
}

# endregion

# ============================================================
# region Einstiegspunkt
# ============================================================

Write-Log "Gestartet."

try {
    $Config = Load-Config
} catch {
    Write-Log "Fataler Fehler beim Start - config.json nicht lesbar: $($_.Exception.Message)"
    [System.Windows.Forms.MessageBox]::Show(
        "Konfigurationsdatei konnte nicht gelesen werden:`n$ConfigPfad`n`n$($_.Exception.Message)",
        "Fehler",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
    exit 1
}
$Config = Remove-VerwaisteProjekte -Config $Config
Save-Config -Config $Config

try {
    $Werkzeuge = Load-Werkzeuge
} catch {
    Write-Log "Fataler Fehler beim Start - werkzeuge.json nicht lesbar: $($_.Exception.Message)"
    [System.Windows.Forms.MessageBox]::Show(
        "Werkzeugliste konnte nicht gelesen werden:`n$WerkzeugePfad`n`n$($_.Exception.Message)",
        "Fehler",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
    exit 1
}

Start-Watcher -Config $Config -Werkzeuge $Werkzeuge

# endregion
