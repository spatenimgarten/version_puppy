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
$ConfigPfad = Join-Path $InstallVerzeichnis "config.json"
$WerkzeugePfad = Join-Path $InstallVerzeichnis "werkzeuge.json"
$SyncPfad = Join-Path $InstallVerzeichnis "sync.json"
$LogPfad = Join-Path $InstallVerzeichnis "version_puppy.log"

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
    # exakt waehrend des Schreibens beendet wird (z.B. update.ps1s
    # Stop-Process -Force). [System.IO.File]::Replace() statt Move-Item
    # -Force, da Move-Item -Force bei existierendem Ziel unter Windows
    # PowerShell 5.1 nicht garantiert atomar ist.
    param([string]$Pfad, $Objekt)
    $tempPfad = "$Pfad.tmp"
    $Objekt | ConvertTo-Json -Depth 10 | Set-Content -Path $tempPfad -Encoding UTF8
    if (Test-Path $Pfad) {
        [System.IO.File]::Replace($tempPfad, $Pfad, $null)
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
    @($inhalt | ConvertFrom-Json)
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
    @($inhalt | ConvertFrom-Json)
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
    param($Projekt, $GlobalConfig)
    $tz = $GlobalConfig.trennzeichen
    "$($Projekt.projektnummer)$tz$($Projekt.werkzeug)-V$($Projekt.werkzeugVersion)$tz"
}

function Get-NaechsteVersionsnummer {
    param(
        [string]$VersionenOrdner,
        [string]$Praefix
    )
    if (-not (Test-Path $VersionenOrdner)) { return 1 }

    # Nur Dateien des eigenen Projekts zaehlen - der Zielordner kann sich
    # mehrere Projekte teilen (Praefix aus Projektnummer+Werkzeug trennt sie).
    $dateien = Get-ChildItem -Path $VersionenOrdner -Filter "*.zip" -File -ErrorAction SilentlyContinue |
        Where-Object { $_.BaseName.StartsWith($Praefix) }
    $nummern = @(
        foreach ($datei in $dateien) {
            $rest = $datei.BaseName.Substring($Praefix.Length)
            if ($rest -match '^V(\d+)') {
                [int]$Matches[1]
            }
        }
    )
    if ($nummern.Count -eq 0) { return 1 }
    return (($nummern | Measure-Object -Maximum).Maximum) + 1
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
    param($Projekt, $GlobalConfig, [string]$Dateiname, [string]$Typ, [string]$Kommentar)

    $historieDatei = Get-VersionshistorieDatei -Projekt $Projekt -GlobalConfig $GlobalConfig
    $eintraege = @()
    if (Test-Path $historieDatei) {
        try {
            $eintraege = @(Get-Content -Path $historieDatei -Raw -Encoding UTF8 | ConvertFrom-Json)
        } catch {
            # Kaputte Historie nicht fortschreiben und damit staendig neue
            # Fehler produzieren - lieber mit leerer Liste neu beginnen als
            # den Watcher zu gefaehrden.
            Write-Log "Versionshistorie '$historieDatei' nicht lesbar, beginne neu: $($_.Exception.Message)"
            $eintraege = @()
        }
    }
    $eintraege += [PSCustomObject]@{
        dateiname  = $Dateiname
        typ        = $Typ
        erstelltAm = (Get-Date).ToString("s")
        kommentar  = $Kommentar
    }
    Set-JsonAtomar -Pfad $historieDatei -Objekt $eintraege
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
        $nummer    = Get-NaechsteVersionsnummer -VersionenOrdner $versionenOrdner -Praefix $praefix
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

    try {
        Add-VersionshistorieEintrag -Projekt $Projekt -GlobalConfig $Config.global -Dateiname $dateiname -Typ $Typ -Kommentar $Kommentar
    } catch {
        # Historie ist eine Zugabe, kein Kriterium fuer Erfolg/Misserfolg der
        # Version selbst - Fehler hier loggen, aber die bereits erstellte
        # Version nicht als fehlgeschlagen melden.
        Write-Log "Versionshistorie fuer '$dateiname' konnte nicht geschrieben werden: $($_.Exception.Message)"
    }

    # In sync.json eintragen (Stufe 2 arbeitet diese eigenstaendige
    # Warteschlange ab) - eigener try/catch wie bei der Historie, ein
    # Sync-Eintrag ist kein Kriterium fuer den Erfolg der Version selbst.
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

    return $dateiname
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
        $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
        $dlg.Description = "Zielordner fuer Versionen auswaehlen"
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $txtZiel.Text = $dlg.SelectedPath
        }
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
    $txtServer.Width = 235
    $form.Controls.Add($txtServer)
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
        $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $dialog.Description = "Projektordner auswaehlen"
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $kandidaten = Get-ProjektKandidaten -Ordnerpfad $dialog.SelectedPath -Werkzeuge $Werkzeuge
            $neuesProjekt = Show-NeuesProjektFenster -Ordnerpfad $dialog.SelectedPath -Kandidaten $kandidaten
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

function Start-Watcher {
    param($Config, $Werkzeuge)

    $laufendVorher = @{}
    foreach ($werkzeug in $Werkzeuge) {
        $prozessBasisname = $werkzeug.prozessName -replace '\.exe$', ''
        $laufendVorher[$werkzeug.name] = [bool](Get-Process -Name $prozessBasisname -ErrorAction SilentlyContinue)
    }

    while ($true) {
        Start-Sleep -Seconds 3

        try {
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
                $prozessBasisname = $werkzeug.prozessName -replace '\.exe$', ''
                $laeuftJetzt = [bool](Get-Process -Name $prozessBasisname -ErrorAction SilentlyContinue)

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
