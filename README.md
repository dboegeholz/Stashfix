# Stashfix

Eine macOS Menüleisten-App zum Scannen, Analysieren und Sortieren von Dokumenten mit lokaler KI.

## Features

- 📄 OCR-Texterkennung für gescannte Belege – auch reine Bild-PDFs (ocrmypdf + tesseract)
- 🤖 KI-Analyse via lokalem Ollama-Modell – keine Cloud, keine Datenweitergabe
- 📁 Automatische Sortierung in Kategorien (Einnahmen/Ausgaben)
- 🔢 Ordnungsnummern pro Kategorie und Jahr
- 📊 CSV-Export für den Steuerberater (Datum als TT.MM.JJJJ)
- 🏷️ Metadaten in PDFs einbetten (exiftool) + macOS Finder Tags – beides optional
- 🔍 Dubletten-Check via SHA-256 (erste 64 KB)
- ⚡ Auto-Modus: automatische Verarbeitung bei neuen Dateien
- 🖱️ Drag & Drop: mehrere PDFs gleichzeitig ins App-Fenster ziehen
- 🎯 Onboarding beim ersten Start
- 🔒 LLM-agnostisch: beliebiges Ollama-Modell konfigurierbar
- ✏️ Analyse-Prompt direkt in den Einstellungen editierbar
- 🐛 Developer Log: Live-Ansicht von OCR, Text und Ollama-Antworten
- 🔔 Dock-Badge zeigt Anzahl wartender Belege
- 🌀 Animiertes Menüleisten-Icon während der Verarbeitung

---

## Abgrenzung zu Paperless-ngx

[Paperless-ngx](https://github.com/paperless-ngx/paperless-ngx) ist ein hervorragendes, voll ausgestattetes Dokumentenmanagementsystem mit Web-Interface, automatischer Verschlagwortung, mächtiger Suchfunktion und über 37.000 GitHub-Sternen. Es ist die bessere Wahl wenn du ein vollständiges digitales Archiv für alle Dokumente aufbauen möchtest und bereit bist, einen Server oder Docker einzurichten.

Stashfix verfolgt einen anderen Ansatz:

| | Paperless-ngx | Stashfix |
|---|---|---|
| Einrichtung | Server, Docker, Datenbank | Homebrew + App starten |
| Oberfläche | Web-Interface | Native macOS App |
| Archiv | Datenbank (PostgreSQL) | Dateisystem / Finder |
| Suche | Eigene Suchmaschine | Spotlight |
| Metadaten | In Datenbank | In PDF-Datei (exiftool) + macOS Tags |
| Zielgruppe | Alle Dokumente, ganzjährig | Deutsche Steuerbelege |
| KI | Optional via Plugins | Lokal via Ollama, eingebaut |

Stashfix ist ideal für alle die ihre Steuerbelege einmal im Jahr schnell in Ordnung bringen wollen – ohne Nachmittag Einrichtungsarbeit, ohne Server und ohne den Finder zu verlassen.

---

## Installation

### Schritt 1: Abhängigkeiten installieren
```bash
brew install ocrmypdf poppler exiftool ollama
```

Alternativ Ollama als GUI-App: [ollama.com](https://ollama.com)

### Schritt 2: Ollama-Modell laden (einmalig, ~5 GB)
```bash
ollama pull qwen3:8b
```
Jedes andere Ollama-Modell funktioniert ebenfalls.

### Schritt 3: App bauen
```bash
cd ~/Downloads/Stashfix
swift build -c release && bash Scripts/build_app.sh
```
Dauert beim ersten Mal 3–5 Minuten. `steuer_confirm` wird automatisch mitkompiliert.

### Schritt 4: App starten
```bash
open ~/Applications/Stashfix.app
```

Beim ersten Start erscheint ein Einrichtungsassistent.

---

## Systemvoraussetzungen

- macOS 14 (Sonoma) oder neuer
- Apple Silicon (M1+) oder Intel Mac
- Homebrew: [brew.sh](https://brew.sh)
- `ocrmypdf` → `brew install ocrmypdf`
- `poppler` → `brew install poppler`
- `exiftool` → `brew install exiftool`
- `ollama` → `brew install ollama` oder [ollama.com](https://ollama.com)

---

## Projektstruktur

```
Stashfix/
├── Package.swift
├── README.md
├── Scripts/
│   └── build_app.sh               ← App-Bundle bauen + signieren
├── Resources/
│   └── AppIcon.icns               ← App-Icon (macOS Tahoe Stil)
├── Sources/Stashfix/
│   ├── Stashfix.swift             ← Einstiegspunkt, Menüleiste, AppDelegate
│   ├── MenuBarIcons.swift         ← Animierte Menüleisten-Icons
│   ├── Models/
│   │   ├── AppState.swift         ← Zentraler App-Zustand (@Observable)
│   │   └── Konfiguration.swift    ← Datenmodell & Einstellungen
│   ├── Views/
│   │   ├── ContentView.swift
│   │   ├── EinstellungenView.swift
│   │   ├── EinstellungenFenster.swift
│   │   ├── OnboardingView.swift
│   │   ├── DependencyCheck.swift
│   │   └── DevLogView.swift       ← Developer Log
│   └── Services/
│       ├── VerarbeitungsService.swift  ← OCR, KI, Sortierung
│       └── FolderWatcher.swift
└── Tools/
    └── steuer_confirm.swift       ← Bestätigungsfenster (wird automatisch gebaut)
```

---

## Workflow

1. PDF in `_Inbox` Ordner legen oder ins Fenster ziehen (auch mehrere gleichzeitig)
2. App erkennt die Datei automatisch (Auto-Modus) oder auf Knopfdruck
3. OCR + PDF/A Konvertierung (automatisch mit `--force-ocr` für reine Bild-PDFs)
4. KI analysiert Datum, Betrag, Kategorie, Person und Steuerrelevanz
5. Alle Bestätigungsfenster nacheinander abarbeiten (kein Fokus-Wechsel während der Analyse)
6. Datei wird umbenannt und sortiert
7. CSV wird aktualisiert

---

## Einstellungen

### KI-Modell Tab
- Ollama-Server URL und Modell konfigurieren
- Analyse-Prompt direkt editieren und auf Standard zurücksetzen
- Platzhalter: `{{personen}}`, `{{kategorien}}`, `{{jahr}}`, `{{text}}`

### Allgemein Tab
- Dock-Anzeige ein/ausschalten
- PDF-Metadaten einbetten (exiftool) ein/ausschalten
- macOS Finder Tags setzen ein/ausschalten
- Einrichtungsassistent erneut starten
- Konfigurationsdatei und Dublettenprotokoll im Finder zeigen
- Nur Dublettenprotokoll zurücksetzen
- Alle Einstellungen zurücksetzen

### Developer Log
Über Menüleiste → „Developer Log" erreichbar. Zeigt live OCR-Status, extrahierten Text, Ollama Request und Antwort sowie Fehlermeldungen.

---

## Technische Entscheidungen

### Metadaten & macOS Tags

Stashfix bettet nach der Verarbeitung strukturierte Metadaten in jede PDF-Datei ein (via exiftool) und setzt gleichzeitig macOS Finder-Tags. Beide sind immer deckungsgleich und können unabhängig voneinander im Onboarding und in den Einstellungen aktiviert werden.

**Immer gesetzt:**
- Kategorie (z.B. `Handwerkerleistungen`)
- Belegtyp (z.B. `Rechnung`)
- Typ (`Einnahme` oder `Ausgabe`)
- Ausstellungsjahr (z.B. `2025`)
- Aussteller (z.B. `Sanitär Meier GmbH`)
- Empfänger/Person (z.B. `Anna Müller` oder `Gemeinsam`)
- `Stashfix` als Marker

**Nur bei steuerrelevanten Belegen zusätzlich:**
- `Steuer`
- `Steuerjahr-2024` (kann vom Ausstellungsjahr abweichen)

**Hinweis zur Portabilität:** exiftool-Metadaten sind in der PDF-Datei selbst gespeichert und bleiben beim Weitergeben erhalten. macOS Finder-Tags sind im Dateisystem (extended attributes) gespeichert und gehen beim Weitergeben verloren – per E-Mail, ZIP, Cloud-Upload oder FAT32/ExFAT-Datenträger. Ausnahme: Kopieren auf APFS/HFS+ Laufwerke erhält die Tags. Das ist datenschutztechnisch ein Vorteil – ein Empfänger sieht keine internen Kategorisierungen.

### Dubletten-Check: SHA-256 über erste 64 KB

SHA-256 ist der aktuelle kryptographische Standard und in Apples CryptoKit enthalten. Die ersten 64 KB enthalten Header und Beginn des Inhalts – ausreichend für eindeutige Identifikation ohne große Dateien komplett einzulesen.

Format der `.verarbeitete_belege` Datei:
```
sha256hex<TAB>/absoluter/pfad/zur/archivierten/datei
```

### OCR-Strategie
Erst `--skip-text` (schnell), dann Textprüfung. Falls leer → `--force-ocr` (für Bild-PDFs wie Kassenbons). `tesseract` wird über expliziten Pfad aufgerufen um PATH-Probleme bei App-Start zu vermeiden.

### Ollama-Lifecycle
Ollama startet automatisch bei Verarbeitungsbeginn und beendet sich nach der KI-Analyse. Im Idle-Betrieb keine Ressourcennutzung. Läuft Ollama bereits, wird es nicht beendet.

### Datumsformate
- Intern und in Dateinamen: ISO `JJJJ-MM-TT`
- Anzeige und CSV: `TT.MM.JJJJ`

### Dateinamen
Umlaute nach DIN 5007: ä→ae, ö→oe, ü→ue, Ä→Ae, Ö→Oe, Ü→Ue, ß→ss.

---

## Datenschutz

Alle Daten bleiben lokal auf dem Mac. Das KI-Modell läuft via Ollama vollständig offline. Es werden keine Daten an externe Server übertragen.

Die App-Konfiguration wird lokal in `~/Library/Application Support/Stashfix/` gespeichert – nicht in iCloud.

**Hinweis:** Wenn du als Archivpfad einen iCloud Drive Ordner wählst, werden deine archivierten Belege über Apples iCloud synchronisiert. Das unterliegt dann Apples Datenschutzbestimmungen. Für maximalen Datenschutz empfehlen wir einen lokalen Ordner (Standard: `~/Documents/Stashfix`).

---

## Lizenzen der verwendeten Tools

| Tool | Lizenz | Kompatibilität |
|------|--------|----------------|
| ocrmypdf | MPL 2.0 | ✅ GPL 3.0 kompatibel |
| tesseract | Apache 2.0 | ✅ GPL 3.0 kompatibel |
| poppler/pdftotext | GPL 2.0 or later | ✅ GPL 3.0 kompatibel |
| exiftool | Perl Artistic License | ✅ GPL 3.0 kompatibel |
| ollama | MIT | ✅ GPL 3.0 kompatibel |

---

## Lizenz

Copyright (C) 2026 dboegeholz

Dieses Programm ist freie Software – lizenziert unter der **GNU General Public License v3.0 or later (GPL-3.0-or-later)**.

- Du darfst die Software frei nutzen, kopieren, verändern und weitergeben
- Weiterentwicklungen müssen ebenfalls unter der GPL veröffentlicht werden
- Niemand darf daraus ein proprietäres/closed-source Produkt machen

Den vollständigen Lizenztext findest du in der Datei [LICENSE](LICENSE) oder unter https://www.gnu.org/licenses/gpl-3.0.html

---

## Spenden

Stashfix ist kostenlos und bleibt es. Wenn dir das Projekt gefällt, freue ich mich über eine Spende:

☕ [Ko-fi](https://ko-fi.com/dboegeholz) · 💛 [GitHub Sponsors](https://github.com/sponsors/dboegeholz)
