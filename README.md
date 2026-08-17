# version_puppy

Automatisierte Versionsverwaltung für TIA Portal / SIMATIC Manager Projekte.

## Problem

Nach dem Exportieren eines Projekts aus TIA Portal oder SIMATIC Manager wird
das komplette Verzeichnis gezippt und als Version bzw. Zwischenversion in
einem Serververzeichnis abgelegt. Besteht gerade kein Serverzugriff (z.B.
Anlage ohne Netzwerkverbindung), muss das Archiv später von Hand
nachkopiert werden — das wird manchmal vergessen. Zusätzlich gibt es keine
durchsuchbare Historie der Versionen.

## Lösung

`version_puppy` automatisiert genau das:

1. **`create`** — zippt ein Projektverzeichnis, vergibt automatisch eine
   fortlaufende Versionsnummer + Zeitstempel, kopiert das Archiv auf den
   Server. Ist der Server gerade nicht erreichbar, landet das Archiv in
   einer lokalen Warteschlange (`data/pending/<projekt>/`) statt verloren
   zu gehen.
2. **`sync`** — holt alle in der Warteschlange wartenden Archive nach,
   sobald der Server wieder erreichbar ist. Gedacht für einen
   wiederkehrenden Aufruf (z.B. Windows-Taskplaner beim Login oder alle
   15 Minuten), damit nichts vergessen wird.
3. **`history`** — zeigt die Versionshistorie eines Projekts an
   (Versionsnummer, Zeitstempel, Kommentar, Sync-Status, Dateiname).

Die Historie wird lokal als JSON geführt (`data/history/<projekt>.json`)
und bei jedem erfolgreichen Sync zusätzlich als Kopie ins
Serververzeichnis geschrieben (`_history_<projekt>.json`), damit sie auch
ohne dieses Tool auf dem Server einsehbar ist.

## Installation / Setup

1. `config.example.json` nach `config.json` kopieren und die eigenen
   Projekte eintragen:

   ```json
   {
     "projects": {
       "BeispielAnlage": {
         "source_dir": "C:/TIA_Projects/BeispielAnlage",
         "server_dir": "//fileserver/Versionen/BeispielAnlage"
       }
     }
   }
   ```

2. Für den Alltagsgebrauch als eigenständige `.exe` bauen (keine externen
   Python-Abhängigkeiten nötig — nur Standardbibliothek):

   ```
   build.bat
   ```

   Ergebnis liegt danach unter `dist/version_puppy.exe`. Diese Datei
   zusammen mit `config.json`, `run.bat` und `sync_task.bat` an einen
   festen Ort kopieren (z.B. neben die TIA-Portal-Exporte).

## Benutzung

```
version_puppy create <projekt> [--comment "Notiz"]
version_puppy sync
version_puppy history <projekt>
```

Oder bequem per Doppelklick/Drag&Drop:

- **`run.bat`** — Projektordner draufziehen (Ordnername muss dem
  Projektnamen in `config.json` entsprechen), erstellt sofort eine neue
  Version.
- **`sync_task.bat`** — für den Windows-Taskplaner gedacht, holt
  ausstehende Kopien nach. Läuft ohne Nutzerinteraktion durch.

## Bekannte Einschränkungen (v1)

- Die Erreichbarkeitsprüfung des Servers nutzt einen 3-Sekunden-Timeout
  per Hintergrund-Thread, damit ein totes Netzlaufwerk das Tool nicht
  dauerhaft blockiert — bei sehr langsamen Verbindungen kann das
  fälschlich als "nicht erreichbar" gewertet werden.
- Kein automatisches Erkennen neuer Exporte (kein Ordner-Watcher) — das
  Auslösen von `create` bleibt bewusst manuell, nur das Nachholen der
  Server-Kopie (`sync`) läuft automatisiert im Hintergrund.

## Lizenz

MIT, siehe [LICENSE](LICENSE).
