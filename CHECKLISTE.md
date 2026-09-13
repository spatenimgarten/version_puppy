# Version_Puppy - Testcheckliste

Zum Abhaken beim manuellen Test auf der Windows-VM. Reihenfolge entspricht
dem Installationsablauf; danach nach Belieben.

## 1. Installation (Ein-Datei-Installer)

- [ ] Nur `install.ps1` in einen leeren Ordner kopieren (z.B. `C:\Tools\Version_Puppy\`).
- [ ] `powershell.exe -ExecutionPolicy Bypass -File install.ps1` ausfuehren.
- [ ] `Version_Puppy.ps1` (inkl. `allowed_signers`) wurde automatisch von GitHub nachgeladen. Kein `update.ps1` mehr (entfaellt als eigenstaendiges Skript).
- [ ] Meldung "Autostart eingerichtet" erscheint, Verknuepfung liegt in `shell:startup`.
- [ ] **Kein** Scheduled Task mehr in der Aufgabenplanung (`Version_Puppy_Update` gibt es nicht mehr - der Update-Check laeuft direkt im Watcher mit).
- [ ] Frage "Jetzt sofort starten?" mit `j` beantworten - Version_Puppy startet, kein sichtbares Konsolenfenster (nur ggf. Popups).
- [ ] `install.ps1` ein zweites Mal ausfuehren, waehrend Version_Puppy noch laeuft -> Meldung "Version_Puppy laeuft bereits", **keine** zweite Instanz wird gestartet, keine Frage "Jetzt sofort starten?" erscheint.
- [ ] `install.ps1` ein zweites Mal ausfuehren (idempotent) - keine Fehler, Verknuepfung wird einfach neu angelegt.

## 2. Erststart / Konfigurationsdateien

- [ ] `config.json` wurde automatisch mit Standardwerten angelegt.
- [ ] `werkzeuge.json` wurde automatisch mit Standardwerten angelegt (Eintrag `TIA`).
- [ ] `sync.json` existiert **nicht** direkt nach dem Erststart (wird erst beim ersten Oeffnen des Versions-Popups angelegt, da der Sync-Zaehler sie liest), dann mit leerem Array `[]`.

## 3. Live-Bearbeitung waehrend Version_Puppy laeuft

- [ ] `werkzeuge.json` von Hand um einen **zweiten** Eintrag erweitern (z.B. LOGO!Soft Comfort, siehe Abschnitt 6a) - Aenderung wirkt ohne Neustart (innerhalb ~3s).
- [ ] **Wichtig (Regressionstest):** nach dem zweiten Eintrag pruefen, dass **beide** Werkzeuge weiterhin erkannt werden - z.B. beide Prozesse nacheinander starten/beenden und pruefen, dass fuer beide das Popup erscheint. (War ein echter Bug: `Load-Werkzeuge` hat vor dem Fix ab dem zweiten Eintrag nur noch einen verschachtelten Rest geliefert, das erste/zweite Werkzeug ist dann "verschwunden" - siehe README "Bekannte PowerShell-5.1-Fallstricke".)
- [ ] `config.json`: `kuerzel` eintragen - wirkt ohne Neustart.
- [ ] Waehrend des Speicherns (oder mit absichtlich kurz kaputtem JSON testen, z.B. eine Klammer entfernen und Datei speichern) pruefen: Watcher stuerzt NICHT ab, laeuft nach Korrektur normal weiter.

## 4. Popup-Trigger (Prozess-Ende erkennen)

- [ ] Konfigurierten Prozess starten (TIA Portal, oder testweise LOGO!Soft Comfort) und wieder schliessen.
- [ ] Versions-Popup erscheint innerhalb von ~3s nach Prozessende.
- [ ] Dropdown zeigt registrierte Projekte, vorbelegt mit der zuletzt genutzten Auswahl.
- [ ] **Enter druecken, ohne einen Button anzuklicken** -> Popup schliesst sich wie "Beenden (keine Version)", keine ZIP wird erstellt.
- [ ] Popup ueber das **X** schliessen -> gleiches Verhalten wie "Beenden".
- [ ] Per Tab zu "Version" oder "Zwischenversion" navigieren und dort Enter druecken -> loest genau diesen Button aus (bewusste Auswahl zaehlt).

## 5. Neues Projekt registrieren

- [ ] Im Popup "Neu..." klicken -> oeffnet den modernen Ordnerdialog mit Adressleiste (nicht mehr das alte Baumfenster). Einen Pfad direkt in die Adressleiste einfuegen/tippen und bestaetigen funktioniert.
- [ ] Ordner mit passender Datei auswaehlen (z.B. `.ap17`-Datei fuer TIA, `.lsc` fuer LOGO!).
- [ ] Kandidatenliste zeigt die passende(n) Datei(en) - **keine Vorauswahl**, auch bei nur einem Treffer.
- [ ] "Registrieren" ohne Kandidatenauswahl klicken -> Warnung "Bitte zuerst eine Projektdatei auswaehlen".
- [ ] Projektnummer ist vorbelegt aus den fuehrenden Ziffern des Ordnernamens, aber editierbar.
- [ ] Zielpfad ist vorbelegt mit `<Elternordner>\Versionen`, per "..."-Button (Adressleisten-Dialog) aenderbar.
- [ ] Zielpfad leeren und "Registrieren" klicken -> Warnung "Bitte einen Zielpfad angeben".
- [ ] **Serverpfad hat jetzt ebenfalls einen "..."-Button** (Adressleisten-Dialog, Pfad direkt einfuegbar) - vorher nur Freitextfeld.
- [ ] Serverpfad leer lassen und "Registrieren" klicken -> Warnung "Bitte einen Serverpfad angeben".
- [ ] Alle Felder korrekt ausfuellen, "Registrieren" -> Projekt erscheint sofort im Dropdown und ist direkt ausgewaehlt.
- [ ] Ordner ohne passende Datei auswaehlen -> "Keine bekannte Projektdatei gefunden. Registrierung nicht moeglich." wird angezeigt.

## 6. Version erstellen (lokal)

- [ ] "Version" klicken -> ZIP landet im Zielpfad, Name nach Schema `{Nr}-{Werkzeug}-V{WVersion}-V001.zip`.
- [ ] Nochmal "Version" fuer dasselbe Projekt -> Nummer zaehlt korrekt hoch (`V002`).
- [ ] "Zwischenversion" klicken -> Dateiname zusaetzlich mit `-{Kuerzel}-{Timestamp}` Suffix.
- [ ] ZIP-Inhalt pruefen: kompletter Projektordner drin, `Versionen`-Unterordner (falls Zielpfad zufaellig darunter liegt) ausgeschlossen.
- [ ] Ein zweites Projekt registrieren, dessen Zielpfad mit dem ersten identisch ist -> Versionsnummern beider Projekte zaehlen unabhaengig (kein gegenseitiges Hochzaehlen).
- [ ] Waehrend eine Projektdatei geoeffnet/gesperrt ist (z.B. in einem Editor offen halten), eine Version erstellen -> Fehlermeldung "Version konnte nicht erstellt werden", **kein Absturz**, keine kaputte ZIP bleibt liegen.
- [ ] Nach erfolgreicher Version: Sync-Zaehler im Popup ("X Version(en) warten auf Sync") **bleibt bei 0**, wenn der Serverpfad erreichbar ist (siehe Abschnitt 6c - die Version wird sofort auf den Server kopiert statt in die Warteliste zu wandern).
- [ ] In `config.json` bei einem Projekt das Feld `zielpfad` entfernen/leeren, dann "Version" klicken -> Fehlermeldung "Version konnte nicht erstellt werden: ...hat keinen Zielpfad hinterlegt", **kein Absturz**, Watcher laeuft danach normal weiter (naechster Popup-Trigger funktioniert noch).
- [ ] In `config.json` bei einem Projekt das Feld `pfad` leeren, Watcher neu starten -> Eintrag wird beim Start als verwaist entfernt statt eines Absturzes.

## 6a. Werkzeug ohne Versionszahl in der Dateiendung (z.B. LOGO!Soft Comfort)

- [ ] Werkzeug-Eintrag mit `erweiterungsMuster` **ohne** Zahlengruppe anlegen (z.B. `"^lsc$"` fuer LOGO!Soft Comfort, Name z.B. "LOGO9").
- [ ] Version erstellen -> Dateiname hat **kein** doppeltes `-V-` (z.B. `10023-LOGO9-V001.zip`, nicht `10023-LOGO9-V-V001.zip`).
- [ ] Zweite Version desselben Projekts -> Nummer zaehlt korrekt zu `V002` hoch (war ein echter Folgebug: der urspruengliche Fix hat nur den fertigen Dateinamen bereinigt, nicht den Praefix, den `Get-NaechsteVersionsnummer` zum Wiederfinden benutzt - haette sonst immer wieder `V001` geliefert und die vorige Version ueberschrieben).
- [ ] Historie-Dateiname passt zum selben, bereinigten Schema (`10023-LOGO9-historie.json`, kein `-V-`).

## 6b. Kommentar / lokale Versionshistorie

- [ ] Kommentarfeld im Popup ausfuellen, "Version" klicken -> im Zielpfad liegt `{Nr}-{Werkzeug}-V{WVersion}-historie.json` mit einem Eintrag (Dateiname, Typ, Zeitstempel, Kommentar, SHA256-Hash).
- [ ] Kommentarfeld leer lassen, "Version" klicken -> funktioniert trotzdem (Pflichtfeld ist es nicht), Historie-Eintrag hat leeres `kommentar`-Feld.
- [ ] Noch eine Version erstellen -> zweiter Eintrag kommt zur selben Historie-Datei dazu, erster bleibt erhalten (Array waechst, wird nicht ueberschrieben).
- [ ] Zwischenversion mit Kommentar erstellen -> landet ebenfalls in der Historie, `typ` = "Zwischenversion".
- [ ] Historie-Datei waehrend des Schreibens absichtlich mit kaputtem JSON ueberschreiben, dann eine weitere Version erstellen -> Historie beginnt sauber neu (kein Absturz, Log-Eintrag "nicht lesbar, beginne neu").

## 6c. Server-Sofortkopie (neu)

- [ ] Serverpfad **erreichbar**: "Version" klicken -> ZIP erscheint **sofort** zusaetzlich im Serverpfad (gleicher Dateiname), `sync.json` bekommt **keinen** neuen Eintrag.
- [ ] `{Nr}-{Werkzeug}-V{WVersion}-historie.json` liegt nach der Sofortkopie **auch** im Serverpfad, mit demselben Eintrag wie lokal.
- [ ] Serverpfad **nicht erreichbar** (z.B. Netzlaufwerk kurz trennen oder nicht-existierenden Pfad eintragen): "Version" klicken -> ZIP landet nur lokal, **ein** neuer Eintrag in `sync.json` mit `status: "wartend"`, Sync-Zaehler im Popup erhoeht sich.
- [ ] **Zweite Maschine / Nummernkonflikt simulieren**: manuell eine Datei mit dem naechsten erwarteten Namen (z.B. `..V003.zip`) direkt in den Serverpfad legen, dann lokal eine neue Version erstellen -> `Get-NaechsteVersionsnummer` erkennt die hoehere Server-Nummer und ueberspringt sie (naechste lokale Nummer ist `V004`, nicht wieder `V003`).
- [ ] **Echten Namenskonflikt erzwingen**: eine Datei mit dem naechsten erwarteten Namen, aber **anderem Inhalt**, manuell in den Serverpfad legen; danach WEITERHIN denselben Namen lokal erzeugen (z.B. indem man die soeben gelegte Server-Datei vor dem `Get-NaechsteVersionsnummer`-Aufruf nicht beruecksichtigt, oder einfach zeitgleich testet) -> eigene Version landet zusaetzlich als `..._KONFLIKT_<Zeitstempel>.zip` auf dem Server, **nicht** ueberschrieben, ein Historie-Eintrag mit `typ: "Konflikt"` erscheint (lokal und auf dem Server), eine Meldung informiert darueber.
- [ ] Serverpfad auf einen extrem langsamen/haengenden Pfad zeigen lassen (falls simulierbar, z.B. eine bereits getrennte Netzwerkfreigabe, die erst nach langer Zeit einen Fehler wirft) -> Popup haengt **nicht** unbegrenzt (Zeitlimit `$ServerTimeoutSekunden`, Standard 60s), Version landet danach in `sync.json`.
- [ ] Dieselbe Version ein zweites Mal auf den Server kopieren lassen (z.B. `Copy-VersionZumServer` erneut mit identischem Hash aufrufen) -> kein doppelter Eintrag, keine erneute Datei.

## 7. Verwaiste Projekte

- [ ] Projektordner eines registrierten Projekts umbenennen/loeschen -> beim naechsten Reload-Zyklus verschwindet der Eintrag automatisch aus `config.json` (kein Fehler, keine Meldung).

## 8. Update-Mechanismus (signiert, laeuft im Watcher mit)

Voraussetzung fuer die ersten drei Punkte: es existiert bereits ein
signiertes Release (`releases/latest/checksums.txt` + `.sig` im Repo,
siehe README "Release signieren"). Ohne das findet der Check einfach
nichts und bleibt unauffaellig - das ist ebenfalls ein gueltiges
Testergebnis (kein Fehler, kein Absturz, kein Hinweis im Popup).

- [ ] Ohne signiertes Release im Repo: Watcher laeuft normal weiter, kein Update-Hinweis im Popup, `version_puppy.log` zeigt hoechstens "Update-Check uebersprungen" oder "Manifest nicht gefunden" - kein Fehler-Popup, kein Absturz.
- [ ] Mit signiertem Release (hoehere Version als `$AktuelleVersion` im laufenden Skript): innerhalb einer Stunde (oder `$UpdatePruefIntervall` fuer den Test kurz herabsetzen) erscheint im naechsten Versions-Popup der Hinweis "Update X.Y.Z verfuegbar (Signatur geprueft)" samt Button "Jetzt aktualisieren".
- [ ] Manifest mit **ungueltiger** Signatur (z.B. `checksums.txt` nach dem Signieren nochmal von Hand aendern) -> wird verworfen, kein Update-Hinweis, Log-Eintrag "Signatur ungueltig, verworfen".
- [ ] "Jetzt aktualisieren" klicken -> laedt das ZIP, prueft SHA256 gegen den (bereits signaturgeprueften) Manifest-Wert, ersetzt die Programmdateien, `config.json`/`werkzeuge.json`/`sync.json` bleiben unveraendert, Version_Puppy startet automatisch neu.
- [ ] Manifest mit falschem SHA256 (Downloadfehler simulieren) -> Update wird abgebrochen, Fehlermeldung "Update konnte nicht eingespielt werden", alte Version laeuft unveraendert weiter.
- [ ] **Kein** Scheduled Task mehr vorhanden, der das uebernimmt (siehe Abschnitt 1) - der Check ist Teil des normalen 3s-Watcher-Zyklus.

## 9. PowerShell-Versionscheck (nur falls relevant/testbare Umgebung vorhanden)

- [ ] Auf einer Maschine mit PowerShell < 5.1 (falls verfuegbar): `install.ps1` bricht mit Fehlermeldung + WMF-5.1-Downloadlink ab, statt stumm nichts zu tun.

## 10. Logging

- [ ] `version_puppy.log` existiert im Installationsordner nach dem ersten Start.
- [ ] Enthaelt Zeilen von `install.ps1` und `Version_Puppy.ps1` (mind. "Gestartet.").
- [ ] Nach einer erstellten Version steht eine entsprechende Zeile im Log (`Version '...' fuer '...' erstellt.`), bei Server-Sofortkopie zusaetzlich `... zusaetzlich auf Serverpfad kopiert.` oder der jeweilige Fehler-/Konflikt-Hinweis.
- [ ] `config.json`/`werkzeuge.json` waehrend eines kaputten Zwischenzustands (siehe Abschnitt 3) -> entsprechende Log-Zeile ("konnte nicht gelesen werden, behalte bisherigen Stand") erscheint.

## 11. Regressionstests fuer gefundene PowerShell-5.1-Bugs

Siehe README "Bekannte PowerShell-5.1-Fallstricke" fuer den Hintergrund -
beide Bugs waren vorher im Code, unabhaengig von den Server-Sync-Aenderungen,
und haetten sich erst bei mehrfacher Nutzung gezeigt.

- [ ] `config.json`/`sync.json`/`werkzeuge.json`/eine Historie-Datei **mindestens zweimal** speichern lassen (z.B. zwei Versionen erstellen, zwei Projekte registrieren) -> **kein** Absturz mit "Der Pfad hat ein ungueltiges Format" (war `[System.IO.File]::Replace(..., $null)`-Bug, betraf jede zweite Speicherung).
- [ ] `werkzeuge.json` mit **zwei** Eintraegen (siehe Abschnitt 3) und `sync.json` mit **zwei** wartenden Eintraegen (zwei Versionen bei nicht erreichbarem Server erstellen) -> in beiden Faellen werden **beide** Eintraege korrekt geladen/gezaehlt, keiner "verschwindet" (war der `@(Pipeline | ConvertFrom-Json)`-Bug).
