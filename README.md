# Stashfix

Eine macOS Menüleisten-App zum Scannen, Analysieren und Sortieren von Dokumenten mit lokaler KI.

## Features

- 📄 OCR-Texterkennung für gescannte Belege (ocrmypdf)
- 🤖 KI-Analyse via lokalem Ollama-Modell – keine Cloud, keine Datenweitergabe
- 📁 Automatische Sortierung in Kategorien (Einnahmen/Ausgaben)
- 🔢 Ordnungsnummern pro Kategorie und Jahr
- 📊 CSV-Export für den Steuerberater
- 🏷️ Metadaten in PDFs einbetten (Spotlight-durchsuchbar)
- 🔍 Dubletten-Check via SHA-256 (erste 64 KB)
- ⚡ Auto-Modus: automatische Verarbeitung bei neuen Dateien
- 🖱️ Drag & Drop: PDFs direkt ins App-Fenster ziehen
- 🎯 Onboarding beim ersten Start
- 🔒 LLM-agnostisch: beliebiges Ollama-Modell konfigurierbar

---

## Installation

### Schritt 1: Abhängigkeiten installieren
```bash
brew install ocrmypdf poppler exiftool
brew install ollama
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
│   └── build_app.sh            ← App-Bundle bauen + signieren
├── Sources/Stashfix/
│   ├── Stashfix.swift          ← Einstiegspunkt, Menüleiste, AppDelegate
│   ├── Models/
│   │   ├── AppState.swift      ← Zentraler App-Zustand
│   │   └── Konfiguration.swift ← Datenmodell & Einstellungen
│   ├── Views/
│   │   ├── ContentView.swift
│   │   ├── EinstellungenView.swift
│   │   ├── EinstellungenFenster.swift
│   │   ├── OnboardingView.swift
│   │   └── DependencyCheck.swift
│   └── Services/
│       ├── VerarbeitungsService.swift  ← OCR, KI, Sortierung
│       └── FolderWatcher.swift
└── Tools/
    └── steuer_confirm.swift    ← Bestätigungsfenster (wird automatisch gebaut)
```

---

## Workflow

1. PDF in `_Inbox` Ordner legen oder ins Fenster ziehen
2. App erkennt die Datei automatisch (Auto-Modus) oder auf Knopfdruck
3. OCR + PDF/A Konvertierung
4. KI analysiert Datum, Betrag, Kategorie, Person
5. Alle Bestätigungsfenster nacheinander abarbeiten (kein Fokus-Wechsel während der Analyse)
6. Datei wird umbenannt und sortiert
7. CSV wird aktualisiert

---

## Technische Entscheidungen

### Dubletten-Check: SHA-256 über erste 64 KB

Stashfix erkennt bereits verarbeitete Belege anhand eines Fingerabdrucks der Datei.

**Warum SHA-256 statt MD5?**
MD5 gilt als kollisionsanfällig – zwei verschiedene Dateien könnten theoretisch denselben Hash erzeugen. SHA-256 ist der aktuelle kryptographische Standard und in Apples CryptoKit bereits enthalten, ohne zusätzliche Abhängigkeiten.

**Warum nur die ersten 64 KB?**
Ein Scan-PDF kann 20–100 MB groß sein. Den kompletten Dateiinhalt in den Speicher zu laden, nur um einen Hash zu berechnen, ist unnötig. Die ersten 64 KB enthalten Header, Metadaten und den Beginn des ersten Inhalts – das reicht aus, um eine Datei eindeutig zu identifizieren.

**Dateiformat `.verarbeitete_belege`**
Eine Textdatei im Archivordner, eine Zeile pro Beleg:
```
sha256hex<TAB>/absoluter/pfad/zur/archivierten/datei
```
TAB als Trenner – sicher gegen Leerzeichen und Sonderzeichen in Pfaden. Ein Beleg gilt nur dann als Dublette, wenn der Hash übereinstimmt **und** die archivierte Datei noch existiert. Gelöschte Archivdateien werden nicht als Duplikate gezählt.

### Ollama-Lifecycle

Ollama wird automatisch gestartet wenn eine Verarbeitung beginnt, und automatisch beendet wenn alle Belege abgearbeitet sind. Im Idle-Betrieb verbraucht die App damit keine nennenswerten Ressourcen. Ollama wird nur beendet wenn Stashfix es selbst gestartet hat – läuft Ollama bereits, wird es in Ruhe gelassen.

---

## Datenschutz

Alle Daten bleiben lokal auf dem Mac. Das KI-Modell läuft via Ollama vollständig offline. Es werden keine Daten an externe Server übertragen.

## Lizenz

MIT
