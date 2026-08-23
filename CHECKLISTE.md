# Version_Puppy - Testcheckliste

Zum Abhaken beim manuellen Test auf der Windows-VM. Reihenfolge entspricht
dem Installationsablauf; danach nach Belieben.

## 1. Installation (Ein-Datei-Installer)

- [ ] Nur `install.ps1` in einen leeren Ordner kopieren (z.B. `C:\Tools\Version_Puppy\`).
- [ ] `powershell.exe -ExecutionPolicy Bypass -File install.ps1` ausfuehren.
- [ ] `Version_Puppy.ps1` und `update.ps1` wurden automatisch von GitHub nachgeladen.
- [ ] Meldung "Autostart eingerichtet" erscheint, Verknuepfung liegt in `shell:startup`.
- [ ] Meldung "Automatischer Update-Check eingerichtet" erscheint, Task `Version_Puppy_Update` existiert in der Aufgabenplanung (stuendlich wiederholend).
- [ ] Frage "Jetzt sofort starten?" mit `j` beantworten - Version_Puppy startet, kein sichtbares Konsolenfenster (nur ggf. Popups).
- [ ] `install.ps1` ein zweites Mal ausfuehren, waehrend Version_Puppy noch laeuft -> Meldung "Version_Puppy laeuft bereits", **keine** zweite Instanz wird gestartet, keine Frage "Jetzt sofort starten?" erscheint.
- [ ] `install.ps1` ein zweites Mal ausfuehren (idempotent) - keine Fehler, Verknuepfung/Task werden einfach neu angelegt.

## 2. Erststart / Konfigurationsdateien

- [ ] `config.json` wurde automatisch mit Standardwerten angelegt.
- [ ] `werkzeuge.json` wurde automatisch mit Standardwerten angelegt (Eintrag `TIA`).

## 3. Live-Bearbeitung waehrend Version_Puppy laeuft

- [ ] `werkzeuge.json` von Hand um einen zweiten Testeintrag erweitern (z.B. `prozessName: "notepad.exe"`, `erweiterungsMuster: "^txt$"`) - Aenderung wirkt ohne Neustart (innerhalb ~3s).
- [ ] `config.json`: `kuerzel` eintragen - wirkt ohne Neustart.
- [ ] Waehrend des Speicherns (oder mit absichtlich kurz kaputtem JSON testen, z.B. eine Klammer entfernen und Datei speichern) pruefen: Watcher stuerzt NICHT ab, laeuft nach Korrektur normal weiter.

## 4. Popup-Trigger (Prozess-Ende erkennen)

- [ ] Konfigurierten Prozess starten (TIA Portal, oder testweise den in Schritt 3 hinzugefuegten `notepad.exe`-Eintrag nutzen) und wieder schliessen.
- [ ] Versions-Popup erscheint innerhalb von ~3s nach Prozessende.
- [ ] Dropdown zeigt registrierte Projekte, vorbelegt mit der zuletzt genutzten Auswahl.
- [ ] **Enter druecken, ohne einen Button anzuklicken** -> Popup schliesst sich wie "Beenden (keine Version)", keine ZIP wird erstellt.
- [ ] Popup ueber das **X** schliessen -> gleiches Verhalten wie "Beenden".
- [ ] Per Tab zu "Version" oder "Zwischenversion" navigieren und dort Enter druecken -> loest genau diesen Button aus (bewusste Auswahl zaehlt).

## 5. Neues Projekt registrieren

- [ ] Im Popup "Neu..." klicken, Ordner mit passender Datei (z.B. `.ap17`-Datei fuer TIA) auswaehlen.
- [ ] Kandidatenliste zeigt die passende(n) Datei(en) - **keine Vorauswahl**, auch bei nur einem Treffer.
- [ ] "Registrieren" ohne Kandidatenauswahl klicken -> Warnung "Bitte zuerst eine Projektdatei auswaehlen".
- [ ] Projektnummer ist vorbelegt aus den fuehrenden Ziffern des Ordnernamens, aber editierbar.
- [ ] Zielpfad ist vorbelegt mit `<Elternordner>\Versionen`, per "..."-Button aenderbar.
- [ ] Zielpfad leeren und "Registrieren" klicken -> Warnung "Bitte einen Zielpfad angeben".
- [ ] Serverpfad leer lassen und "Registrieren" klicken -> Warnung "Bitte einen Serverpfad angeben".
- [ ] Alle Felder korrekt ausfuellen, "Registrieren" -> Projekt erscheint sofort im Dropdown und ist direkt ausgewaehlt.
- [ ] Ordner ohne passende Datei auswaehlen -> "Keine bekannte Projektdatei gefunden. Registrierung nicht moeglich." wird angezeigt.

## 6. Version erstellen

- [ ] "Version" klicken -> ZIP landet im Zielpfad, Name nach Schema `{Nr}-{Werkzeug}-V{WVersion}-V001.zip`.
- [ ] Nochmal "Version" fuer dasselbe Projekt -> Nummer zaehlt korrekt hoch (`V002`).
- [ ] "Zwischenversion" klicken -> Dateiname zusaetzlich mit `-{Kuerzel}-{Timestamp}` Suffix.
- [ ] ZIP-Inhalt pruefen: kompletter Projektordner drin, `Versionen`-Unterordner (falls Zielpfad zufaellig darunter liegt) ausgeschlossen.
- [ ] Ein zweites Projekt registrieren, dessen Zielpfad mit dem ersten identisch ist -> Versionsnummern beider Projekte zaehlen unabhaengig (kein gegenseitiges Hochzaehlen).
- [ ] Waehrend eine Projektdatei geoeffnet/gesperrt ist (z.B. in einem Editor offen halten), eine Version erstellen -> Fehlermeldung "Version konnte nicht erstellt werden", **kein Absturz**, keine kaputte ZIP bleibt liegen.
- [ ] Nach erfolgreicher Version: Sync-Zaehler im Popup ("X Version(en) warten auf Sync") erhoeht sich.
- [ ] In `config.json` bei einem Projekt das Feld `zielpfad` entfernen/leeren, dann "Version" klicken -> Fehlermeldung "Version konnte nicht erstellt werden: ...hat keinen Zielpfad hinterlegt", **kein Absturz**, Watcher laeuft danach normal weiter (naechster Popup-Trigger funktioniert noch).
- [ ] In `config.json` bei einem Projekt das Feld `pfad` leeren, Watcher neu starten -> Eintrag wird beim Start als verwaist entfernt statt eines Absturzes.

## 6b. Kommentar / lokale Versionshistorie

- [ ] Kommentarfeld im Popup ausfuellen, "Version" klicken -> im Zielpfad liegt `{Nr}-{Werkzeug}-V{WVersion}-historie.json` mit einem Eintrag (Dateiname, Typ, Zeitstempel, genau der eingegebene Kommentar).
- [ ] Kommentarfeld leer lassen, "Version" klicken -> funktioniert trotzdem (Pflichtfeld ist es nicht), Historie-Eintrag hat leeres `kommentar`-Feld.
- [ ] Noch eine Version erstellen -> zweiter Eintrag kommt zur selben Historie-Datei dazu, erster bleibt erhalten (Array waechst, wird nicht ueberschrieben).
- [ ] Zwischenversion mit Kommentar erstellen -> landet ebenfalls in der Historie, `typ` = "Zwischenversion".
- [ ] `ausstehendeSyncs` in `config.json` pruefen -> der jeweilige Kommentar taucht dort ebenfalls im entsprechenden Eintrag auf.
- [ ] Historie-Datei waehrend des Schreibens absichtlich mit kaputtem JSON ueberschreiben, dann eine weitere Version erstellen -> Historie beginnt sauber neu (kein Absturz, Log-Eintrag "nicht lesbar, beginne neu").

## 7. Verwaiste Projekte

- [ ] Projektordner eines registrierten Projekts umbenennen/loeschen -> beim naechsten Reload-Zyklus verschwindet der Eintrag automatisch aus `config.json` (kein Fehler, keine Meldung).

## 8. Update-Mechanismus

- [ ] `update.ps1` manuell ausfuehren, wenn kein neuer Commit vorliegt -> "Bereits aktuell.".
- [ ] Einen Testcommit auf GitHub pushen (z.B. Kommentar-Aenderung), dann `update.ps1` erneut ausfuehren -> laedt herunter, ersetzt geaenderte Datei(en), laufender Version_Puppy-Prozess wird beendet und neu gestartet.
- [ ] `config.json` und `werkzeuge.json` bleiben nach dem Update unveraendert.
- [ ] Scheduled Task `Version_Puppy_Update` in der Aufgabenplanung per Rechtsklick -> "Ausfuehren" manuell anstossen -> laeuft ohne sichtbares Fenster durch.

## 9. PowerShell-Versionscheck (nur falls relevant/testbare Umgebung vorhanden)

- [ ] Auf einer Maschine mit PowerShell < 5.1 (falls verfuegbar): `install.ps1` bricht mit Fehlermeldung + WMF-5.1-Downloadlink ab, statt stumm nichts zu tun.

## 10. Logging

- [ ] `version_puppy.log` existiert im Installationsordner nach dem ersten Start.
- [ ] Enthaelt Zeilen von `install.ps1`, `Version_Puppy.ps1` (mind. "Gestartet.") und nach einem Testlauf von `update.ps1`.
- [ ] Nach einer erstellten Version steht eine entsprechende Zeile im Log (`Version '...' fuer '...' erstellt.`).
- [ ] Download-Fehler in `update.ps1` erzwingen (z.B. kurz Netzwerk trennen) -> Fehlschlag steht im Log, nicht nur (nirgendwo sichtbar) in `Write-Host`.
- [ ] `config.json`/`werkzeuge.json` waehrend eines kaputten Zwischenzustands (siehe Punkt 3) -> entsprechende Log-Zeile ("konnte nicht gelesen werden, behalte bisherigen Stand") erscheint.
