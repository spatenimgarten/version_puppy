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

## Funktionsweise (Kurzfassung)

- Ueberwacht konfigurierte Tool-Prozesse (aktuell: TIA Portal) per Polling.
- Bei Prozessende: Popup mit Projektauswahl (Dropdown, letzte Auswahl
  vorbelegt) und den Optionen Zwischenversion / Version / Beenden.
- Versionen werden als ZIP im `Versionen`-Unterordner des jeweiligen
  Projekts abgelegt, Benennung nach konfigurierbarem Schema.
- Neue Projekte werden ueber den "Neu..."-Button im Popup registriert
  (Ordnerauswahl, Kandidaten-Liste der erkannten Projektdateien, manuelle
  Bestaetigung - keine automatische Vorauswahl).
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
