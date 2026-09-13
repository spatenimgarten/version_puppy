# Version_Puppy

PowerShell-basiertes Hintergrund-Versionierungstool fuer TIA Portal (Siemens
Automation) und perspektivisch weitere Engineering-Tools.

## Status

Manager Stufe 1 (lokale Versionierung) plus Server-Sofortkopie: jede Version
wird direkt beim Erstellen zusaetzlich auf den Serverpfad kopiert, wenn der
gerade erreichbar ist - inklusive SHA256-Hash je Version, Namenskonflikt-
Erkennung (`_KONFLIKT_<Zeitstempel>`) und Zeitlimit gegen haengende
Netzwerkfreigaben (siehe "Funktionsweise"). Eine vollwertige Stufe 2
(Hintergrund-Sync fuer bereits in `sync.json` wartende Versionen, HTML-
Historie) ist konzeptionell vorbereitet, aber noch nicht implementiert.

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
   Laedt `Version_Puppy.ps1` (inkl. `allowed_signers`) automatisch von
   GitHub nach (main-Branch), richtet den Autostart ein und bietet an,
   gleich zu starten.
3. Beim ersten Start von Version_Puppy werden `config.json` und
   `werkzeuge.json` automatisch mit Standardwerten angelegt. `kuerzel` in
   `config.json` danach von Hand nachtragen, in `werkzeuge.json` bei Bedarf
   weitere Tool-Eintraege (siehe naechster Abschnitt).

Danach prueft Version_Puppy selbst stuendlich auf ein neues, signiertes
Release (siehe Abschnitt "Update") - kein separater Task, kein erneutes
manuelles Kopieren noetig.

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

Kein separater Task mehr - der ohnehin laufende Watcher in
`Version_Puppy.ps1` prueft alle 3 Sekunden mit, ob seit der letzten Stunde
ein neues Release faellig ist (`Get-UpdateManifest`). Ablauf:

1. `releases/latest/checksums.txt` + `.sig` werden von GitHub geladen
   (roher Dateiinhalt, kein Git noetig).
2. Die Signatur wird per `ssh-keygen -Y verify` gegen die mitgelieferte
   `allowed_signers`-Datei geprueft. Nur bei gueltiger Signatur wird der
   Inhalt ueberhaupt geparst - ohne `ssh-keygen.exe` (Windows-Bordmittel,
   Teil des optionalen OpenSSH-Client-Features) oder ohne passende
   `allowed_signers` wird der Check uebersprungen, nicht ungeprueft
   akzeptiert.
3. Ist die im Manifest genannte Version neuer als `$AktuelleVersion` im
   laufenden Skript, erscheint im naechsten Versions-Popup ein Hinweis samt
   Button "Jetzt aktualisieren".
4. Erst der explizite Klick darauf laedt das im Manifest verlinkte ZIP,
   prueft dessen SHA-256 gegen den im (bereits signaturgeprueften)
   Manifest hinterlegten Wert, ersetzt die Programmdateien (`config.json`,
   `werkzeuge.json`, `sync.json` bleiben unberuehrt) und startet
   Version_Puppy neu.

Damit ist das automatische Laufen auf reines Lesen+Verifizieren begrenzt -
Code wird nur nach bewusstem Klick ausgetauscht, nie unbeaufsichtigt. Wer
nur Schreibzugriff aufs Repo hat (aber nicht den privaten Signier-Key
"Laptop EF" aus `allowed_signers`), kann kein gefaelschtes Manifest in
Umlauf bringen - hoechstens ein aelteres, echtes wiederverwenden
(Rollback), da keine monotone Versionshistorie erzwungen wird.

### Release signieren (manueller Schritt, nur auf der Maschine mit dem privaten Key)

Der private Signier-Key existiert nur auf einer Maschine ("Laptop EF") und
wird nie automatisiert eingebunden. Neues Release veroeffentlichen:

1. Version in `Version_Puppy.ps1` (`$AktuelleVersion`) erhoehen, commiten,
   taggen (`git tag vX.Y.Z`), pushen (inkl. `--tags`).
2. GitHubs automatisch generiertes Tag-Archiv abwarten/laden:
   `https://github.com/spatenimgarten/version_puppy/archive/refs/tags/vX.Y.Z.zip`
3. SHA-256 davon berechnen (`Get-FileHash -Algorithm SHA256`) und
   `checksums.txt` bauen:
   ```
   version=X.Y.Z
   sha256=<HASH>
   zipurl=https://github.com/spatenimgarten/version_puppy/archive/refs/tags/vX.Y.Z.zip
   ```
4. Signieren: `ssh-keygen -Y sign -f <privater-key> -n file checksums.txt`
   erzeugt `checksums.txt.sig`.
5. Beide Dateien nach `releases/latest/checksums.txt(.sig)` kopieren,
   committen und auf `main` pushen.

Schritt 4 ist der einzige, der zwingend auf "Laptop EF" laufen muss - alles
andere (inkl. dieser Implementierung) ist normaler Code, den jede Maschine
mit Push-Zugriff beitragen kann.

## Logging

`install.ps1` und `Version_Puppy.ps1` schreiben wichtige Ereignisse (Start,
Fehler, erstellte Versionen, Update-Checks) in eine gemeinsame
`version_puppy.log` im Installationsordner - nicht versioniert, rein lokal.
Wichtig vor allem fuer den automatischen Update-Check: der laeuft
unsichtbar im Watcher mit, ohne die Log-Datei waere ein fehlgeschlagener
oder verworfener Check (Download-Fehler, ungueltige Signatur) von aussen
nicht erkennbar. Popups (Fehlermeldungen, Versionierung) bleiben
zusaetzlich bestehen, wo sie Sinn ergeben - das Log ist der Kanal fuer
alles, was auch unbeaufsichtigt nachvollziehbar sein soll.

Einfache Ein-Generationen-Rotation: ueberschreitet `version_puppy.log` 2 MB,
wird sie nach `version_puppy.log.old` verschoben und neu begonnen - damit
waechst sie bei einem dauerhaft laufenden Hintergrunddienst nicht
unbegrenzt.

## Funktionsweise (Kurzfassung)

- Ueberwacht konfigurierte Tool-Prozesse (aktuell: TIA Portal) per Polling.
- Bei Prozessende: Popup mit Projektauswahl (Dropdown, letzte Auswahl
  vorbelegt), optionalem Kommentarfeld und den Optionen Zwischenversion /
  Version / Beenden.
- Versionen werden als ZIP im projekteigenen Zielpfad abgelegt (frei
  aenderbar, Vorschlag beim Registrieren: `<Elternordner>\Versionen`, eine
  Ebene ueber dem Projektpfad), Benennung nach konfigurierbarem Schema.
  Mehrere Projekte koennen sich denselben Zielpfad teilen - Dateiname
  (Projektnummer+Werkzeug-Praefix) und die laufende Versionsnummer je
  Projekt sind darauf ausgelegt, dass sich nichts vermischt.
- Die naechste Versionsnummer wird als Maximum aus lokalem Zielpfad **und**
  (falls gerade erreichbar) Serverpfad ermittelt (`Get-NaechsteVersions-
  nummer`) - sichert mehrere Maschinen ab, die dasselbe Projekt an denselben
  Server sichern: ohne diesen Abgleich koennten zwei Maschinen unabhaengig
  voneinander dieselbe naechste Nummer vergeben und sich beim Server-
  Kopieren gegenseitig ueberschreiben.
- Neue Projekte werden ueber den "Neu..."-Button im Popup registriert
  (Ordnerauswahl, Kandidaten-Liste der erkannten Projektdateien, manuelle
  Bestaetigung - keine automatische Vorauswahl). Dabei werden zusaetzlich
  Zielpfad und Serverpfad erfasst (beides Pflichtfelder).
- Nach dem lokalen ZIP wird sofort versucht, dieselbe Datei zusaetzlich auf
  den Serverpfad zu kopieren (`Copy-VersionZumServer`). Jede Netzwerk-
  operation dabei laeuft mit Zeitlimit (`$ServerTimeoutSekunden`, Standard
  60s, ueber `Invoke-MitNetzwerkTimeout`) - eine haengende/tote Freigabe
  blockiert das Popup nicht auf unbestimmte Zeit, ein Timeout zaehlt wie
  jeder andere Kopierfehler.
  - Serverpfad erreichbar, Zielname frei oder inhaltsgleich (SHA256-
    Vergleich) vorhanden: Kopie unter eindeutigem Zwischennamen (Kuerzel +
    Zeitstempel), danach atomar auf den echten Namen umbenannt - nie eine
    halbfertige Datei unter dem echten Namen.
  - Zielname existiert bereits mit ANDEREM Inhalt (Namenskonflikt, z.B.
    zwei Maschinen im selben Moment): wird NICHT ueberschrieben. Die eigene
    Version landet zusaetzlich unter `..._KONFLIKT_<Zeitstempel>.zip`, ein
    Historie-Eintrag (Typ "Konflikt") und eine Meldung markieren das fuer
    die manuelle Aufloesung.
  - Serverpfad nicht erreichbar oder jeder andere Fehler (inkl. Timeout):
    Version landet in der `sync.json`-Warteliste zum spaeteren Nachholen.
- Die lokale Versionshistorie (siehe unten) wird bei jeder erfolgreichen
  Sofortkopie mit der Server-Historie **vereinigt** (`Sync-Versionshistorie-
  ZumServer`, nach `dateiname`) und auf beiden Seiten zurueckgeschrieben -
  sonst wuerde eine zweite Maschine die Historie-Eintraege der ersten beim
  naechsten Speichern unbemerkt ueberschreiben, weil es dafuer (anders als
  bei den Versions-Zips) nur einen festen Dateinamen je Projekt gibt.
- Verwaiste Projekteintraege (Pfad existiert nicht mehr) werden beim Start
  still bereinigt.
- Jede erstellte Version (auch Zwischenversionen) landet zusaetzlich zum
  ZIP als Eintrag (Dateiname, Typ, Zeitstempel, Kommentar, SHA256-Hash) in
  einer Versionshistorie `{Praefix}historie.json` - eine Datei je Projekt,
  ueber den Praefix von anderen Projekten getrennt, lokal im Zielpfad UND
  (bei erreichbarem Server) auf dem Serverpfad gespiegelt. Der Hash dient
  sowohl als Beleg als auch der Namenskonflikt-Erkennung beim Server-
  Kopieren. Der Kommentar wird auch in den `sync.json`-Eintrag
  uebernommen. Vorstufe fuer die geplante HTML-Historie aus Stufe 2, die
  diese Daten aufbereiten soll - aktuell nur Rohdaten.

## Konfiguration

Drei getrennte Dateien, alle nicht versioniert (siehe `.gitignore`) und
rein lokal - Aenderungen wirken ohne Neustart, da nichts dauerhaft im
Speicher gehalten wird: `config.json`/`werkzeuge.json` laedt der Watcher
alle 3 Sekunden neu, `sync.json` wird direkt bei jedem Zugriff (neue
Version, Popup-Anzeige) frisch gelesen bzw. geschrieben. Geschrieben wird
immer atomar (Temp-Datei + `[System.IO.File]::Replace()`) - eine kaputte/
abgeschnittene JSON-Datei durch einen Prozessabbruch mitten im Schreiben
(z.B. der Selbst-Neustart nach einem eingespielten Update) ist damit
ausgeschlossen.

- **`config.json`** - maschinenspezifischer Laufzeitstand: Kuerzel,
  Trennzeichen, bekannte Projekte. Aendert sich staendig, bleibt pro
  Maschine.
- **`sync.json`** - Warteliste der Versionen, bei denen die Server-
  Sofortkopie beim Erstellen nicht geklappt hat (Server nicht erreichbar,
  Kopierfehler) - Dateiname, Kommentar, Zeitstempel, Status. Bewusst von
  `config.json` getrennt, damit eine kuenftige Stufe 2 sie als eigen-
  staendige Abarbeitungs-Warteschlange lesen und leeren kann, ohne mit dem
  Live-Projektstand zu kollidieren. Wird nur bei fehlgeschlagener
  Sofortkopie befuellt, aktuell von nichts automatisch wieder abgearbeitet
  (das ist die eigentliche, noch fehlende Stufe 2).
- **`werkzeuge.json`** - Tool-Definitionen (Name, Prozessname, Datei-
  Erweiterungsmuster). Aendert sich selten und laesst sich bei Bedarf
  einfach auf andere Maschinen kopieren, ohne Projektdaten mitzuschleppen:
  ```json
  [
      {
          "name": "TIA",
          "prozessName": "Siemens.Automation.Portal.exe",
          "erweiterungsMuster": "^ap(\\d+)$"
      },
      {
          "name": "LOGO!Soft",
          "prozessName": "javaw.exe",
          "erweiterungsMuster": "^lsc$",
          "kommandozeilenMuster": "LOGOComfort"
      }
  ]
  ```
  Ein Eintrag fuer ein auf der jeweiligen Maschine nicht installiertes
  Werkzeug ist unproblematisch - `Get-Process` liefert dafuer einfach nie
  einen Treffer, kein Fehler, kein spuerbarer Overhead. Eine gemeinsame
  Werkzeugliste ueber mehrere Maschinen hinweg ist also unbedenklich, auch
  wenn nicht jede Maschine jedes Tool installiert hat.

  Das optionale Feld `kommandozeilenMuster` grenzt Werkzeuge ein, die
  unter einem generischen Wirtsprozess laufen (z.B. LOGO!Soft Comfort als
  `javaw.exe` ueber einen InstallAnywhere-Launcher) - ohne dieses Feld
  wuerde jeder Prozess mit passendem Namen als Treffer zaehlen, mit dem
  Feld nur einer, dessen Kommandozeile (per Regex, hier via
  `Get-CimInstance Win32_Process`) zusaetzlich passt. Fehlt das Feld,
  bleibt es beim reinen Namensabgleich per `Get-Process` (wie bisher,
  z.B. bei TIA).

  [`werkzeuge.example.json`](werkzeuge.example.json) ist Teil des Repos
  (im Gegensatz zu `werkzeuge.json` selbst) und dient als Vorlage mit
  echten Beispiel-Eintraegen. `install.ps1` kopiert sie bei der
  Erstinstallation automatisch nach `werkzeuge.json`, falls dort noch
  keine existiert - eine bereits vorhandene, angepasste `werkzeuge.json`
  wird dabei nie ueberschrieben.

## Bekannte PowerShell-5.1-Fallstricke in diesem Code

Zwei Bugs, die sich nicht aus dem Code selbst erschliessen und beim
Weiterentwickeln leicht wieder eingebaut werden - beide reproduzierbar
und unabhaengig vom konkreten Aufrufkontext:

- **`[System.IO.File]::Replace($tmp, $ziel, $null)`** wirft auf diesem
  PowerShell-5.1/.NET-Stand zuverlaessig `"Der Pfad hat ein ungueltiges
  Format"`, sobald der dritte Parameter (Backup-Pfad) `$null` ist - selbst
  mit ansonsten komplett validen Pfaden. Betraf urspruenglich jede zweite
  und weitere Speicherung von `config.json`/`sync.json`/`werkzeuge.json`/
  `historie.json` (die erste Speicherung nimmt den `Move-Item`-Zweig, weil
  die Datei noch nicht existiert, und faellt dadurch nicht auf). Fix: immer
  einen echten (danach geloeschten) Backup-Pfad uebergeben, nie `$null`
  (siehe `Set-JsonAtomar`).
- **`@(Get-Content ... | ConvertFrom-Json)`** als EIN zusammengesetzter
  Ausdruck verschachtelt ein Ergebnis mit 2+ Elementen faelschlich in ein
  1-Element-Array (`.Count` luegt dann), obwohl genau dieses `@()` eigent-
  lich das bekannte "1 JSON-Element wird zum Skalar statt Array"-Problem
  loesen soll. Betraf `Load-Werkzeuge` und `Load-Sync`, sobald dort ein
  zweiter Eintrag dazukam (z.B. ein zweites Werkzeug wie LOGO!Soft Comfort
  neben TIA) - das zweite Werkzeug/der zweite Sync-Eintrag wurde dadurch
  unbemerkt "unsichtbar". Fix: IMMER erst in eine Zwischenvariable parsen,
  danach in einem eigenen Schritt mit `@()` absichern - nie
  `@(Pipeline | ConvertFrom-Json)` als ein Ausdruck.

## Naechste Schritte

- Manager Stufe 2: automatisches Nachholen der `sync.json`-Warteliste,
  sobald der Server wieder erreichbar ist; HTML-Historie.
- Auto-Erkennung, welche Dateien innerhalb einer TIA-Session konkret
  geaendert wurden (noch nicht spezifiziert).
