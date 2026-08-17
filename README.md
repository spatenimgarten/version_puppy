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

Zwei Use Cases:

- **Projekt bearbeiten** — Lokale Versionierung (`version`) und Server-Sync
  (`sync`) sind umgesetzt und in die Oberfläche (`gui`) eingebunden.
- **Neues Projekt anlegen** — das eigentliche Anlegen des Projekts (in TIA
  Portal/SIMATIC Manager) bleibt Handarbeit; der `setup`-Assistent fragt
  nur die nötigen Angaben ab und erzeugt daraus die passende
  Projekt-Batchdatei.

Offen ist noch das automatische Öffnen der Programmiersoftware (mit Warten
bis zum Schließen) — aktuell ein TODO-Platzhalter in der generierten
Batchdatei.

## Funktionsweise

Das Projektverzeichnis folgt der Namenskonvention `<...>_V<Nummer>`, z.B.
`123456_TIA19_V001`. `version_puppy version` kennt zwei Typen:

- **`--typ version`** — zippt den Ordner in seinem aktuellen Namen
  (`123456_TIA19_V001.zip`) und benennt das Quellverzeichnis danach auf die
  nächste Nummer um (`123456_TIA19_V002`), damit die nächste Bearbeitung
  direkt Richtung V002 läuft.
- **`--typ zwischenversion`** — zippt den Ordner als rollendes Backup
  (`123456_TIA19_V001_AF_2026-08-17_143205.zip`, Kürzel + Datum + Uhrzeit),
  ohne den Ordner umzubenennen. Dient als Zwischenstand, der beim nächsten
  `sync` automatisch aufgeräumt wird, sobald die zugehörige echte Version
  synchronisiert ist.

Jeder Aufruf zippt lokal, berechnet eine SHA256-Prüfsumme des Archivs und
schreibt einen Eintrag in eine lokale `history.json` im Datenverzeichnis
(Zeitstempel, Typ, Dateiname, Kommentar, Ersteller-Kürzel, Hash,
Status `pending`). `version` selbst greift **nicht** auf das Netzwerk zu —
das erledigt ausschließlich `sync`.

`version_puppy sync`:

- Prüft die Erreichbarkeit des Serververzeichnisses (Hintergrund-Thread mit
  3-Sekunden-Timeout, damit ein totes Netzlaufwerk nicht dauerhaft blockiert).
- Kopiert jede lokal wartende Datei, deren Name auf dem Server noch nicht
  existiert, dorthin und trägt sie in eine kanonische `history.json` +
  `history.html` im Serververzeichnis ein (auch ohne das Tool einsehbar).
- Existiert der Dateiname auf dem Server bereits mit **anderem** Hash
  (z.B. zwei Rechner haben unabhängig voneinander dieselbe Versionsnummer
  vergeben), wird **nichts überschrieben** — der lokale Eintrag wird als
  `conflict` markiert. Die Klärung passiert bewusst außerhalb des Tools.
- Sobald eine echte Version erfolgreich synchronisiert ist, werden alle
  zugehörigen Zwischenversionen (gleicher Ordnername als Präfix) lokal und
  auf dem Server automatisch entfernt.

## Benutzung

### Neues Projekt anlegen

Projekt zuerst wie gewohnt in TIA Portal/SIMATIC Manager anlegen, das
Verzeichnis muss auf `_V001` enden (z.B. `123456_TIA19_V001`). Danach:

```
version_puppy setup
```

Öffnet einen kleinen Assistenten (Projektverzeichnis, Serververzeichnis,
Benutzerkürzel, optional Startkommando der Programmiersoftware) und
erzeugt daraus `start_<Präfix>.bat` im übergeordneten Verzeichnis —
danach reicht Doppelklick auf diese Batchdatei für den Alltag.

### Projekt bearbeiten

Interaktiv über eine kleine Oberfläche mit drei Knöpfen (Version /
Zwischenversion / Beenden):

```
version_puppy gui --source-dir <Pfad zum Projektordner> \
                   --data-dir <Pfad für Historie/Warteschlange> \
                   --user <Kürzel> \
                   --server-dir <Pfad zum Serververzeichnis>
```

Die Oberfläche prüft beim Start die Servererreichbarkeit (Ampel: grün/rot
in der Statuszeile) und synchronisiert bei Erreichbarkeit sofort alles
Ausstehende. Nach jedem "Version"/"Zwischenversion"-Klick wird ebenfalls
sofort versucht zu synchronisieren. Der Kommentar wird per Dialog
abgefragt. Enter/Return schließt das Fenster (sicherer Default, falls
versehentlich gedrückt — im Normalfall soll nichts passieren).

Für Skripte/Hintergrund-Aufrufe ohne Oberfläche:

```
version_puppy version --source-dir <Pfad zum Projektordner> \
                       --data-dir <Pfad für Historie/Warteschlange> \
                       --user <Kürzel> \
                       --typ version|zwischenversion \
                       [--comment "Notiz"]

version_puppy sync --data-dir <Pfad für Historie/Warteschlange> \
                    --server-dir <Pfad zum Serververzeichnis>
```

Als eigenständige `.exe` bauen (keine externen Python-Abhängigkeiten
nötig — nur Standardbibliothek):

```
build.bat
```

Ergebnis liegt danach unter `dist/version_puppy.exe`.

## Beispiel-Batchdatei

[`beispiel_start.bat`](beispiel_start.bat) zeigt zur Referenz, wie eine
Projekt-Batchdatei aussieht (inhaltlich dasselbe, was `setup` automatisch
erzeugt): ermittelt den aktuellen `_V<Nummer>`-Ordner automatisch (wichtig,
da `version` ihn umbenennt), stößt `sync` im Hintergrund an (nicht
blockierend) und öffnet danach die Oberfläche (`gui`-Befehl). Das Öffnen
der Programmiersoftware (mit Warten bis zum Schließen) ist als TODO
markiert.

## Lizenz

MIT, siehe [LICENSE](LICENSE).
