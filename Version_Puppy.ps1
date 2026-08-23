#requires -Version 5.1
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
        "PowerShell $($PSVersionTable.PSVersion) erkannt.`nDer Version_Puppy benoetigt mindestens PowerShell 5.1.`n`nBitte WMF 5.1 installieren (Windows Management Framework) und Rechner neu starten.",
        "Version zu alt",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    ) | Out-Null
    exit 1
}

$InstallVerzeichnis = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigPfad = Join-Path $InstallVerzeichnis "config.json"

# endregion

# ============================================================
# region Konfiguration: Laden / Speichern / Standardwerte
# ============================================================

function Get-StandardConfig {
    [PSCustomObject]@{
        global = [PSCustomObject]@{
            kuerzel       = ""
            trennzeichen  = "-"
            letzteAuswahl = ""
            werkzeuge     = @(
                [PSCustomObject]@{
                    name               = "TIA"
                    prozessName        = "Siemens.Automation.Portal.exe"
                    erweiterungsMuster = "^ap(\d+)$"
                }
            )
        }
        projekte         = @()
        ausstehendeSyncs = @()
    }
}

function Load-Config {
    if (-not (Test-Path $ConfigPfad)) {
        $config = Get-StandardConfig
        Save-Config -Config $config
        return $config
    }
    try {
        $inhalt = Get-Content -Path $ConfigPfad -Raw -Encoding UTF8
        $config = $inhalt | ConvertFrom-Json

        # Einzelne Objekte aus JSON koennen beim Parsen als Skalar statt
        # Array zurueckkommen (z.B. genau 1 Projekt) - hier absichern.
        $config.projekte         = @($config.projekte)
        $config.ausstehendeSyncs = @($config.ausstehendeSyncs)
        $config.global.werkzeuge = @($config.global.werkzeuge)

        return $config
    } catch {
        [System.Windows.Forms.MessageBox]::Show(
            "Konfigurationsdatei konnte nicht gelesen werden:`n$ConfigPfad`n`n$($_.Exception.Message)",
            "Fehler",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
        exit 1
    }
}

function Save-Config {
    param($Config)
    $Config | ConvertTo-Json -Depth 10 | Set-Content -Path $ConfigPfad -Encoding UTF8
}

# endregion

# ============================================================
# region Aufraeumfunktion: verwaiste Projektpfade entfernen (still, beim Start)
# ============================================================

function Remove-VerwaisteProjekte {
    param($Config)
    $Config.projekte = @($Config.projekte | Where-Object { Test-Path $_.pfad })
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
        $Config
    )

    $kandidaten = @()
    $dateien = Get-ChildItem -Path $Ordnerpfad -File -ErrorAction SilentlyContinue

    foreach ($datei in $dateien) {
        $erweiterung = $datei.Extension.TrimStart('.')
        foreach ($werkzeug in $Config.global.werkzeuge) {
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
#   Parsing (fuer naechste Nummer): Dateiname am Trennzeichen splitten,
#   letztes Segment das exakt ^V\d+$ entspricht = laufende Nummer.
# ============================================================

function Get-VersionenOrdner {
    param([string]$Projektpfad)
    Join-Path $Projektpfad "Versionen"
}

function Get-NaechsteVersionsnummer {
    param(
        [string]$Projektpfad,
        [string]$Trennzeichen
    )
    $versionenOrdner = Get-VersionenOrdner -Projektpfad $Projektpfad
    if (-not (Test-Path $versionenOrdner)) { return 1 }

    $dateien = Get-ChildItem -Path $versionenOrdner -Filter "*.zip" -File -ErrorAction SilentlyContinue
    $nummern = @(
        foreach ($datei in $dateien) {
            $teile = $datei.BaseName -split [regex]::Escape($Trennzeichen)
            $versionsSegment = $teile | Where-Object { $_ -match '^V\d+$' } | Select-Object -Last 1
            if ($versionsSegment) {
                [int]($versionsSegment -replace '^V0*', '')
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

    $kern = "$($Projekt.projektnummer)$tz$($Projekt.werkzeug)-V$($Projekt.werkzeugVersion)$tz$nnnStr"

    if ($Typ -eq "Zwischenversion") {
        $timestamp = Get-Date -Format "yyyyMMddHHmmss"
        $kern = "$kern$tz$($GlobalConfig.kuerzel)$tz$timestamp"
    }

    "$kern.zip"
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
        [string]$Typ
    )

    $versionenOrdner = Get-VersionenOrdner -Projektpfad $Projekt.pfad
    if (-not (Test-Path $versionenOrdner)) {
        New-Item -ItemType Directory -Path $versionenOrdner | Out-Null
    }

    $nummer    = Get-NaechsteVersionsnummer -Projektpfad $Projekt.pfad -Trennzeichen $Config.global.trennzeichen
    $dateiname = Build-Versionsdateiname -Projekt $Projekt -GlobalConfig $Config.global -Nummer $nummer -Typ $Typ
    $zielPfad  = Join-Path $versionenOrdner $dateiname

    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem

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

    $Projekt.letzteVersion   = $dateiname
    $Projekt.letzteAenderung = (Get-Date).ToString("s")

    # In Sync-Warteliste eintragen (Stufe 2 arbeitet diese ab)
    $Config.ausstehendeSyncs += [PSCustomObject]@{
        projektpfad = $Projekt.pfad
        dateiname   = $dateiname
        erstelltAm  = (Get-Date).ToString("s")
        status      = "wartend"
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
    $form.Size = New-Object System.Drawing.Size(420, 380)
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
        $gewaehlterKandidat = $Kandidaten[$liste.SelectedIndex]
        $script:neuesProjektErgebnis = [PSCustomObject]@{
            pfad            = $Ordnerpfad
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
    param($Config)

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Version_Puppy"
    $form.Size = New-Object System.Drawing.Size(420, 240)
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
            $kandidaten = Get-ProjektKandidaten -Ordnerpfad $dialog.SelectedPath -Config $Config
            $neuesProjekt = Show-NeuesProjektFenster -Ordnerpfad $dialog.SelectedPath -Kandidaten $kandidaten
            if ($neuesProjekt) {
                $Config.projekte += $neuesProjekt
                Save-Config -Config $Config
                [void]$combo.Items.Add($neuesProjekt.name)
                $combo.SelectedIndex = $combo.Items.Count - 1
            }
        }
    })

    $script:popupAktion = $null

    $btnZwischen = New-Object System.Windows.Forms.Button
    $btnZwischen.Text = "Zwischenversion"
    $btnZwischen.Size = New-Object System.Drawing.Size(120, 30)
    $btnZwischen.Location = New-Object System.Drawing.Point(15, 90)
    $btnZwischen.Add_Click({ $script:popupAktion = "Zwischenversion"; $form.Close() })
    $form.Controls.Add($btnZwischen)

    $btnVersion = New-Object System.Windows.Forms.Button
    $btnVersion.Text = "Version"
    $btnVersion.Size = New-Object System.Drawing.Size(120, 30)
    $btnVersion.Location = New-Object System.Drawing.Point(150, 90)
    $btnVersion.Add_Click({ $script:popupAktion = "Version"; $form.Close() })
    $form.Controls.Add($btnVersion)

    $btnBeenden = New-Object System.Windows.Forms.Button
    $btnBeenden.Text = "Beenden (keine Version)"
    $btnBeenden.Size = New-Object System.Drawing.Size(255, 30)
    $btnBeenden.Location = New-Object System.Drawing.Point(15, 130)
    $btnBeenden.Add_Click({ $script:popupAktion = "Beenden"; $form.Close() })
    $form.Controls.Add($btnBeenden)

    $syncAnzahl = @($Config.ausstehendeSyncs).Count
    $lblSync = New-Object System.Windows.Forms.Label
    $lblSync.Text = "$syncAnzahl Version(en) warten auf Sync"
    $lblSync.Location = New-Object System.Drawing.Point(15, 175)
    $lblSync.AutoSize = $true
    $lblSync.ForeColor = [System.Drawing.Color]::Gray
    $form.Controls.Add($lblSync)

    [void]$form.ShowDialog()

    if ($combo.SelectedIndex -lt 0 -or $null -eq $script:popupAktion) { return }

    $ausgewaehltesProjekt = $Config.projekte[$combo.SelectedIndex]
    $Config.global.letzteAuswahl = $ausgewaehltesProjekt.pfad

    switch ($script:popupAktion) {
        "Version"         { New-ProjektVersion -Projekt $ausgewaehltesProjekt -Config $Config -Typ "Version" | Out-Null }
        "Zwischenversion" { New-ProjektVersion -Projekt $ausgewaehltesProjekt -Config $Config -Typ "Zwischenversion" | Out-Null }
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
    param($Config)

    $laufendVorher = @{}
    foreach ($werkzeug in $Config.global.werkzeuge) {
        $prozessBasisname = $werkzeug.prozessName -replace '\.exe$', ''
        $laufendVorher[$werkzeug.name] = [bool](Get-Process -Name $prozessBasisname -ErrorAction SilentlyContinue)
    }

    while ($true) {
        Start-Sleep -Seconds 3

        $Config = Load-Config
        $Config = Remove-VerwaisteProjekte -Config $Config

        foreach ($werkzeug in $Config.global.werkzeuge) {
            $prozessBasisname = $werkzeug.prozessName -replace '\.exe$', ''
            $laeuftJetzt = [bool](Get-Process -Name $prozessBasisname -ErrorAction SilentlyContinue)

            if ($laufendVorher[$werkzeug.name] -eq $true -and $laeuftJetzt -eq $false) {
                Show-VersionPopup -Config $Config
                $Config = Load-Config
            }

            $laufendVorher[$werkzeug.name] = $laeuftJetzt
        }
    }
}

# endregion

# ============================================================
# region Einstiegspunkt
# ============================================================

$Config = Load-Config
$Config = Remove-VerwaisteProjekte -Config $Config
Save-Config -Config $Config

Start-Watcher -Config $Config

# endregion
