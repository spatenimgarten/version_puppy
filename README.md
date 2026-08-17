# version_puppy

Automatisierte Versionsverwaltung für TIA Portal / SIMATIC Manager Projekte.

## Problem

Nach dem Exportieren eines Projekts aus TIA Portal oder SIMATIC Manager wird
das komplette Verzeichnis gezippt und als Version bzw. Zwischenversion in
einem Serververzeichnis abgelegt. Besteht gerade kein Serverzugriff (z.B.
Anlage ohne Netzwerkverbindung), muss das Archiv später von Hand
nachkopiert werden — das wird manchmal vergessen. Zusätzlich gibt es keine
durchsuchbare Historie der Versionen.

## Stand

Aktuell umgesetzt ist der **lokale Versionierungs-Teil** (`version`-Befehl).
Der Server-Sync-Teil (`sync`) mit Konflikterkennung, Server-Historie
(JSON + HTML) und automatischem Aufräumen alter Zwischenversionen folgt als
nächster Schritt.

## Funktionsweise

Das Projektverzeichnis folgt der Namenskonvention `<...>_V<Nummer>`, z.B.
`123456_TIA19_V001`. `version_puppy version` kennt zwei Typen:

- **`--typ version`** — zippt den Ordner in seinem aktuellen Namen
  (`123456_TIA19_V001.zip`) und benennt das Quellverzeichnis danach auf die
  nächste Nummer um (`123456_TIA19_V002`), damit die nächste Bearbeitung
  direkt Richtung V002 läuft.
- **`--typ zwischenversion`** — zippt den Ordner als rollendes Backup
  (`123456_TIA19_V001_AF_2026-08-17_143205.zip`, Kürzel + Datum + Uhrzeit),
  ohne den Ordner umzubenennen. Gedacht als Zwischenstand, der beim
  nächsten `sync` wieder aufgeräumt wird, sobald die zugehörige echte
  Version existiert (Teil des noch ausstehenden `sync`-Schritts).

Jeder Aufruf zippt lokal, berechnet eine SHA256-Prüfsumme des Archivs und
schreibt einen Eintrag in eine lokale `history.json` im Datenverzeichnis
(Zeitstempel, Typ, Dateiname, Kommentar, Ersteller-Kürzel, Hash,
Status `pending`). Es findet **kein Netzwerkzugriff** statt — das ist
bewusst dem separaten `sync`-Befehl vorbehalten.

## Benutzung

Interaktiv über eine kleine Oberfläche mit drei Knöpfen (Version /
Zwischenversion / Beenden), Kommentar wird dort abgefragt:

```
version_puppy gui --source-dir <Pfad zum Projektordner> \
                   --data-dir <Pfad für Historie/Warteschlange> \
                   --user <Kürzel>
```

Oder direkt über die Kommandozeile (z.B. für Skripte/Tests, ohne
Oberfläche):

```
version_puppy version --source-dir <Pfad zum Projektordner> \
                       --data-dir <Pfad für Historie/Warteschlange> \
                       --user <Kürzel> \
                       --typ version|zwischenversion \
                       [--comment "Notiz"]
```

Als eigenständige `.exe` bauen (keine externen Python-Abhängigkeiten
nötig — nur Standardbibliothek):

```
build.bat
```

Ergebnis liegt danach unter `dist/version_puppy.exe`.

## Beispiel-Batchdatei

[`beispiel_start.bat`](beispiel_start.bat) zeigt den geplanten Alltags-
Workflow: pro Projekt eine eigene, angepasste Kopie dieser Datei. Sie
ermittelt den aktuellen `_V<Nummer>`-Ordner automatisch (wichtig, da
`version` ihn umbenennt) und öffnet dann die Oberfläche (`gui`-Befehl).
Das Öffnen der Programmiersoftware (mit Warten bis zum Schließen) sowie
der Aufruf von `sync` im Hintergrund sind als TODO markiert und folgen mit
dem `sync`-Schritt.

## Lizenz

MIT, siehe [LICENSE](LICENSE).
