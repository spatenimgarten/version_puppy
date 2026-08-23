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

# endregion

# ============================================================
# region Konfiguration: Laden / Speichern / Standardwerte
#
#   Zwei getrennte Dateien, bewusst beide nicht versioniert (siehe
#   .gitignore) und rein lokal:
#   - config.json     - Projekte, Sync-Warteliste, Kuerzel/Trennzeichen -
#                        maschinenspezifischer Laufzeitstand.
#   - werkzeuge.json  - Tool-Definitionen (Prozessname, Dateimuster) -
#                        aendert sich selten, laesst sich bei Bedarf einfach
#                        auf andere Maschinen kopieren, ohne Projektdaten
#                        mitzuschleppen.
# ============================================================

function Get-StandardConfig {
    [PSCustomObject]@{
        global = [PSCustomObject]@{
            kuerzel       = ""
            trennzeichen  = "-"
            letzteAuswahl = ""
        }
        projekte         = @()
        ausstehendeSyncs = @()
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
    $config.projekte         = @($config.projekte)
    $config.ausstehendeSyncs = @($config.ausstehendeSyncs)

    return $config
}

function Save-Config {
    param($Config)
    $Config | ConvertTo-Json -Depth 10 | Set-Content -Path $ConfigPfad -Encoding UTF8
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
    $Werkzeuge | ConvertTo-Json -Depth 10 | Set-Content -Path $WerkzeugePfad -Encoding UTF8
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
# region Version erstellen (ZIP, ohne Versionen-Unterordner selbst)
# ============================================================

function New-ProjektVersion {
    param(
        $Projekt,
        $Config,
        [ValidateSet("Version", "Zwischenversion")]
        [string]$Typ
    )

    $versionenOrdner = $Projekt.zielpfad
    if (-not (Test-Path $versionenOrdner)) {
        New-Item -ItemType Directory -Path $versionenOrdner -Force | Out-Null
    }

    $praefix   = Get-VersionsPraefix -Projekt $Projekt -GlobalConfig $Config.global
    $nummer    = Get-NaechsteVersionsnummer -VersionenOrdner $versionenOrdner -Praefix $praefix
    $dateiname = Build-Versionsdateiname -Projekt $Projekt -GlobalConfig $Config.global -Nummer $nummer -Typ $Typ
    $zielPfad  = Join-Path $versionenOrdner $dateiname

    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    try {
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
        # Zip evtl. nur teilweise geschrieben (z.B. Datei war noch gesperrt) -
        # verwaiste/korrupte Zip nicht liegen lassen, Watcher darf nicht sterben.
        Remove-Item -Path $zielPfad -Force -ErrorAction SilentlyContinue
        [System.Windows.Forms.MessageBox]::Show(
            "Version konnte nicht erstellt werden (Datei evtl. noch gesperrt):`n$($_.Exception.Message)",
            "Fehler bei Versionierung",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
        return $null
    }

    $Projekt.letzteVersion   = $dateiname
    $Projekt.letzteAenderung = (Get-Date).ToString("s")

    # In Sync-Warteliste eintragen (Stufe 2 arbeitet diese ab)
    $Config.ausstehendeSyncs += [PSCustomObject]@{
        projektpfad = $Projekt.pfad
        zielpfad    = $Projekt.zielpfad
        serverpfad  = $Projekt.serverpfad
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

    # Enter = sicherer Default (keine Version) - Zwischenversion/Version
    # bleiben bewusst nur per expliziten Klick erreichbar.
    $form.AcceptButton = $btnBeenden

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
    param($Config, $Werkzeuge)

    $laufendVorher = @{}
    foreach ($werkzeug in $Werkzeuge) {
        $prozessBasisname = $werkzeug.prozessName -replace '\.exe$', ''
        $laufendVorher[$werkzeug.name] = [bool](Get-Process -Name $prozessBasisname -ErrorAction SilentlyContinue)
    }

    while ($true) {
        Start-Sleep -Seconds 3

        try {
            $Config = Load-Config
        } catch {
            # Transienter Lesefehler (z.B. config.json wird gerade von Hand
            # gespeichert) - bisherigen Stand behalten, naechster Zyklus in
            # 3s versucht es erneut, statt den Watcher zu beenden.
            continue
        }
        $Config = Remove-VerwaisteProjekte -Config $Config

        try {
            $Werkzeuge = Load-Werkzeuge
        } catch {
            # Gleiches Prinzip fuer werkzeuge.json (z.B. gerade von Hand
            # kopiert/bearbeitet) - bisherige Liste behalten.
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
                }
            }

            $laufendVorher[$werkzeug.name] = $laeuftJetzt
        }
    }
}

# endregion

# ============================================================
# region Einstiegspunkt
# ============================================================

try {
    $Config = Load-Config
} catch {
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
