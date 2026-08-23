# Version_Puppy

PowerShell-basiertes Hintergrund-Versionierungstool fuer TIA Portal (Siemens
Automation) und perspektivisch weitere Engineering-Tools.

## Status

Manager Stufe 1 (lokale Versionierung, kein Server-Sync). Stufe 2 (Server-Sync,
Konflikterkennung) ist konzeptionell vorbereitet (Sync-Warteliste wird bereits
lokal mitgefuehrt), aber noch nicht implementiert.

## Installation

1. Ordner z.B. nach `C:\Tools\Version_Puppy` kopieren.
2. `Version_Puppy.ps1` ausfuehren (mind. PowerShell 5.1 erforderlich, das
   Skript prueft das selbst und gibt bei Bedarf einen Hinweis).
3. Beim ersten Start wird `config.json` automatisch mit Standardwerten
   angelegt. `kuerzel` und ggf. weitere `werkzeuge`-Eintraege danach von
   Hand nachtragen.

## Autostart mit Windows

Damit Version_Puppy nicht jedes Mal manuell gestartet werden muss, im
Autostart-Ordner eine Verknuepfung anlegen (kein Admin noetig, gilt nur fuer
den aktuell angemeldeten Benutzer):

1. `Win+R` -> `shell:startup` -> Enter (oeffnet den Autostart-Ordner).
2. Darin eine neue Verknuepfung anlegen mit folgendem Ziel (Installationspfad
   anpassen):
   ```
   powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File "C:\Tools\Version_Puppy\Version_Puppy.ps1"
   ```

Alternativ per PowerShell einmalig automatisch erzeugen (Installationspfad
in `$Ziel` anpassen):
```powershell
$Ziel = "C:\Tools\Version_Puppy\Version_Puppy.ps1"
$Verknuepfung = Join-Path ([Environment]::GetFolderPath("Startup")) "Version_Puppy.lnk"
$shell = New-Object -ComObject WScript.Shell
$lnk = $shell.CreateShortcut($Verknuepfung)
$lnk.TargetPath = "powershell.exe"
$lnk.Arguments  = "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$Ziel`""
$lnk.WorkingDirectory = Split-Path $Ziel
$lnk.Save()
```

`-WindowStyle Hidden` unterdrueckt nur das PowerShell-Konsolenfenster - die
WinForms-Popups (Versionierung, neues Projekt registrieren) erscheinen
weiterhin normal. `-ExecutionPolicy Bypass` gilt ausschliesslich fuer diesen
einen Aufruf und aendert nichts an der systemweiten Execution Policy.

Robustere Alternative (z.B. wenn der Start auch bei Remote-/RDP-Anmeldung
zuverlaessig klappen soll): Aufgabenplanung -> Aufgabe erstellen -> Trigger
"Bei Anmeldung", Aktion wie oben. Dabei "Nur ausfuehren, wenn Benutzer
angemeldet ist" waehlen - die GUI-Popups brauchen eine interaktive Sitzung,
"Unabhaengig von der Benutzeranmeldung ausfuehren" wuerde sie unsichtbar
im Hintergrund laufen lassen.

## Funktionsweise (Kurzfassung)

- Ueberwacht konfigurierte Tool-Prozesse (aktuell: TIA Portal) per Polling.
- Bei Prozessende: Popup mit Projektauswahl (Dropdown, letzte Auswahl
  vorbelegt) und den Optionen Zwischenversion / Version / Beenden.
- Versionen werden als ZIP im projekteigenen Zielpfad abgelegt (frei
  aenderbar, Vorschlag beim Registrieren: `<Elternordner>\Versionen`, eine
  Ebene ueber dem Projektpfad), Benennung nach konfigurierbarem Schema.
  Mehrere Projekte koennen sich denselben Zielpfad teilen - Dateiname
  (Projektnummer+Werkzeug-Praefix) und die laufende Versionsnummer je
  Projekt sind darauf ausgelegt, dass sich nichts vermischt.
- Neue Projekte werden ueber den "Neu..."-Button im Popup registriert
  (Ordnerauswahl, Kandidaten-Liste der erkannten Projektdateien, manuelle
  Bestaetigung - keine automatische Vorauswahl). Dabei werden zusaetzlich
  Zielpfad und Serverpfad erfasst (beides Pflichtfelder) - der Serverpfad
  wird gespeichert und in die Sync-Warteliste uebernommen, aber in Stufe 1
  noch nicht verwendet (Sync folgt erst in Stufe 2).
- Verwaiste Projekteintraege (Pfad existiert nicht mehr) werden beim Start
  still bereinigt.

## Konfiguration (`config.json`)

Wird nicht versioniert (siehe `.gitignore`), da rechner-/nutzerspezifisch
(Kuerzel, Trennzeichen, bekannte Projekte, ausstehende Syncs).

## Naechste Schritte

- Manager Stufe 2: Server-Sync (SHA256-Vergleich, alle 10 Min.), Konflikt-
  handling (`_KONFLIKT_<datum>`-Suffix), HTML-Historie.
- Auto-Erkennung, welche Dateien innerhalb einer TIA-Session konkret
  geaendert wurden (noch nicht spezifiziert).
