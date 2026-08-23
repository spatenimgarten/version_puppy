# Version_Puppy

PowerShell-basiertes Hintergrund-Versionierungstool fuer TIA Portal (Siemens
Automation) und perspektivisch weitere Engineering-Tools.

## Status

Manager Stufe 1 (lokale Versionierung, kein Server-Sync). Stufe 2 (Server-Sync,
Konflikterkennung) ist konzeptionell vorbereitet (Sync-Warteliste wird bereits
lokal mitgefuehrt), aber noch nicht implementiert.

## Installation

`install.ps1` ist ein eigenstaendiger Installer - es reicht, nur diese eine
Datei auf die Zielmaschine zu kopieren:

1. `install.ps1` z.B. nach `C:\Tools\Version_Puppy\install.ps1` kopieren.
2. Ausfuehren (mind. PowerShell 5.1 erforderlich - Windows 10/11 und
   Server 2016+ haben das bereits eingebaut; auf Windows 7 SP1/8.1/
   Server 2008 R2 SP1/2012/2012 R2 vorher [Windows Management Framework
   5.1](https://www.microsoft.com/en-us/download/details.aspx?id=54616)
   installieren, sonst meldet sich `install.ps1` mit dem Downloadlink und
   bricht ab):
   ```
   powershell.exe -ExecutionPolicy Bypass -File "C:\Tools\Version_Puppy\install.ps1"
   ```
   Laedt `Version_Puppy.ps1` und `update.ps1` automatisch von GitHub nach
   (main-Branch), richtet Autostart und stuendlichen Update-Check ein
   (siehe naechster Abschnitt) und bietet an, gleich zu starten.
3. Beim ersten Start von Version_Puppy werden `config.json` und
   `werkzeuge.json` automatisch mit Standardwerten angelegt. `kuerzel` in
   `config.json` danach von Hand nachtragen, in `werkzeuge.json` bei Bedarf
   weitere Tool-Eintraege (siehe naechster Abschnitt).

Danach sorgt der Update-Task dafuer, dass neue Versionen automatisch
ankommen - kein erneutes manuelles Kopieren noetig.

## Autostart mit Windows

Richtet `install.ps1` automatisch mit ein (siehe oben). Legt eine
Verknuepfung im Autostart-Ordner des aktuellen Benutzers an (kein Admin
noetig). Erneutes Ausfuehren von `install.ps1` ueberschreibt die
Verknuepfung einfach neu (z.B. nach Verschieben des Installationsordners).

Ganz manuell geht es genauso - im Autostart-Ordner selbst eine Verknuepfung
anlegen (kein Admin noetig, gilt nur fuer den aktuell angemeldeten
Benutzer), falls man `install.ps1` lieber nicht ausfuehren moechte:

1. `Win+R` -> `shell:startup` -> Enter (oeffnet den Autostart-Ordner).
2. Darin eine neue Verknuepfung anlegen mit folgendem Ziel (Installationspfad
   anpassen):
   ```
   powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File "C:\Tools\Version_Puppy\Version_Puppy.ps1"
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

## Update

`install.ps1` richtet neben dem Autostart auch einen stuendlichen Scheduled
Task (`Version_Puppy_Update`) ein, der `update.ps1` ausfuehrt. Der laedt
den aktuellen `main`-Branch als ZIP von GitHub (kein Git auf der
Zielmaschine noetig), vergleicht die Dateien per Hash und ersetzt nur, was
sich geaendert hat. `config.json` und `werkzeuge.json` sind nicht Teil des
Repos und bleiben unberuehrt. Gab es eine Aenderung, wird der laufende Version_Puppy-Prozess
beendet und mit dem neuen Stand neu gestartet - laufende Ueberwachung geht
dabei kurz aus, ein evtl. offenes Versions-Popup wuerde mitbeendet.

Manuell anstossen: `powershell.exe -ExecutionPolicy Bypass -File
"C:\Tools\Version_Puppy\update.ps1"`. Falls `Register-ScheduledTask` in
`install.ps1` fehlschlaegt (z.B. durch Gruppenrichtlinien auf gesperrten
Engineering-PCs), muss der Task manuell in der Aufgabenplanung angelegt
werden (Trigger: taeglich wiederholen alle 1 Stunde, Aktion wie oben).

## Logging

`install.ps1`, `update.ps1` und `Version_Puppy.ps1` schreiben wichtige
Ereignisse (Start, Fehler, erstellte Versionen, Updates) in eine gemeinsame
`version_puppy.log` im Installationsordner - nicht versioniert, rein lokal.
Wichtig vor allem fuer `update.ps1`: der laeuft per Scheduled Task komplett
unsichtbar im Hintergrund, ohne die Log-Datei waere ein fehlgeschlagener
Update-Check (z.B. Download-Fehler) von aussen nicht erkennbar. Popups
(Fehlermeldungen, Versionierung) bleiben zusaetzlich bestehen, wo sie
Sinn ergeben - das Log ist der Kanal fuer alles, was auch unbeaufsichtigt
nachvollziehbar sein soll.

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

## Konfiguration

Zwei getrennte Dateien, beide nicht versioniert (siehe `.gitignore`) und
rein lokal - der Watcher laedt beide alle 3 Sekunden neu, Aenderungen
wirken also ohne Neustart:

- **`config.json`** - maschinenspezifischer Laufzeitstand: Kuerzel,
  Trennzeichen, bekannte Projekte, ausstehende Syncs. Aendert sich staendig,
  bleibt pro Maschine.
- **`werkzeuge.json`** - Tool-Definitionen (Name, Prozessname, Datei-
  Erweiterungsmuster). Aendert sich selten und laesst sich bei Bedarf
  einfach auf andere Maschinen kopieren, ohne Projektdaten mitzuschleppen:
  ```json
  [
      {
          "name": "TIA",
          "prozessName": "Siemens.Automation.Portal.exe",
          "erweiterungsMuster": "^ap(\\d+)$"
      }
  ]
  ```
  Ein Eintrag fuer ein auf der jeweiligen Maschine nicht installiertes
  Werkzeug ist unproblematisch - `Get-Process` liefert dafuer einfach nie
  einen Treffer, kein Fehler, kein spuerbarer Overhead. Eine gemeinsame
  Werkzeugliste ueber mehrere Maschinen hinweg ist also unbedenklich, auch
  wenn nicht jede Maschine jedes Tool installiert hat.

  [`werkzeuge.example.json`](werkzeuge.example.json) ist Teil des Repos
  (im Gegensatz zu `werkzeuge.json` selbst) und dient als Vorlage mit
  echten Beispiel-Eintraegen. `install.ps1` kopiert sie bei der
  Erstinstallation automatisch nach `werkzeuge.json`, falls dort noch
  keine existiert - eine bereits vorhandene, angepasste `werkzeuge.json`
  wird dabei nie ueberschrieben.

## Naechste Schritte

- Manager Stufe 2: Server-Sync (SHA256-Vergleich, alle 10 Min.), Konflikt-
  handling (`_KONFLIKT_<datum>`-Suffix), HTML-Historie.
- Auto-Erkennung, welche Dateien innerhalb einer TIA-Session konkret
  geaendert wurden (noch nicht spezifiziert).
