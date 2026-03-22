# Stashfix

Eine macOS Menüleisten-App zum Scannen, Analysieren und Sortieren von Dokumenten mit lokaler KI.

## Features

- 📄 OCR-Texterkennung für gescannte Belege – auch reine Bild-PDFs (ocrmypdf + tesseract)
- 🤖 KI-Analyse via lokalem Ollama-Modell – keine Cloud, keine Datenweitergabe
- 📁 Automatische Sortierung in Kategorien (Einnahmen/Ausgaben)
- 🔢 Ordnungsnummern pro Kategorie und Jahr
- 📊 CSV-Export für den Steuerberater (Datum als TT.MM.JJJJ)
- 🏷️ Metadaten in PDFs einbetten (Spotlight-durchsuchbar)
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
4. KI analysiert Datum, Betrag, Kategorie, Person
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
- Einrichtungsassistent erneut starten
- Konfigurationsdatei und Dublettenprotokoll im Finder zeigen
- Nur Dublettenprotokoll zurücksetzen (Belege bleiben erhalten)
- Alle Einstellungen zurücksetzen (inkl. Prompt, Kategorien, Namen)

### Developer Log
Über Menüleiste → „Developer Log" erreichbar. Zeigt live:
- OCR-Status und Fehlermeldungen
- Extrahierten Text (erste 800 Zeichen)
- Ollama Request (Modell, Prompt-Länge) und vollständige Antwort
- Alle Fehlermeldungen der externen Tools

---

## Technische Entscheidungen

### Dubletten-Check: SHA-256 über erste 64 KB

**Warum SHA-256 statt MD5?**
MD5 gilt als kollisionsanfällig. SHA-256 ist der aktuelle Standard und in Apples CryptoKit enthalten.

**Warum nur die ersten 64 KB?**
Scan-PDFs können 20–100 MB groß sein. Die ersten 64 KB enthalten Header und Beginn des Inhalts – ausreichend für eindeutige Identifikation.

**Dateiformat `.verarbeitete_belege`**
```
sha256hex<TAB>/absoluter/pfad/zur/archivierten/datei
```
TAB als Trenner – sicher gegen Sonderzeichen in Pfaden. Dubletten zählen nur wenn die archivierte Datei noch existiert.

### Metadaten & macOS Tags

Stashfix bettet nach der Verarbeitung strukturierte Metadaten in jede PDF-Datei ein (via exiftool) und setzt gleichzeitig macOS Finder-Tags. Beide sind immer deckungsgleich.

**Immer gesetzt:**
- Kategorie (z.B. `Krankheitskosten`)
- Belegtyp (z.B. `Kassenbon`)
- Typ (`Einnahme` oder `Ausgabe`)
- Ausstellungsjahr (z.B. `2025`)
- Aussteller (z.B. `Rossmann`)
- Empfänger/Person (z.B. `Max` oder `Gemeinsam`)
- `Stashfix` als Marker

**Nur bei steuerrelevanten Belegen zusätzlich:**
- `Steuer`
- `Steuerjahr-2024` (kann vom Ausstellungsjahr abweichen)

Durch die macOS Finder-Tags sind alle Belege direkt im Finder filterbar und über Spotlight durchsuchbar – ohne zusätzliche App oder Datenbank.

**Hinweis zur Portabilität:** exiftool-Metadaten sind in der PDF-Datei selbst gespeichert und bleiben beim Weitergeben erhalten. macOS Finder-Tags sind dagegen im Dateisystem (extended attributes) gespeichert und gehen beim Weitergeben verloren – etwa per E-Mail, ZIP, Upload zu Cloud-Diensten oder Kopieren auf FAT32/ExFAT-Datenträger. Das ist datenschutztechnisch ein Vorteil: ein Empfänger sieht keine internen Kategorisierungen. Beide Optionen lassen sich unabhängig im Onboarding und in den Einstellungen aktivieren oder deaktivieren.

### OCR-Strategie
Erst `--skip-text` (schnell, schont textualisierte PDFs), dann Textprüfung. Falls leer → `--force-ocr` (erzwingt OCR auch bei Bild-PDFs wie Kassenbons). `tesseract` wird über expliziten Pfad aufgerufen um PATH-Probleme bei App-Start zu vermeiden.

### Ollama-Lifecycle
Ollama startet automatisch bei Verarbeitungsbeginn und beendet sich nach der KI-Analyse – vor den Bestätigungsfenstern. Im Idle-Betrieb keine Ressourcennutzung. Läuft Ollama bereits, wird es nicht beendet.

### Datumsformate
- Intern und in Dateinamen: ISO `JJJJ-MM-TT` (korrekte alphabetische Sortierung)
- Anzeige und CSV: `TT.MM.JJJJ` (deutsches Format)

### Dateinamen
Umlaute werden nach DIN 5007 umgeschrieben: ä→ae, ö→oe, ü→ue, Ä→Ae, Ö→Oe, Ü→Ue, ß→ss.

---

## Datenschutz

Alle Daten bleiben lokal auf dem Mac. Das KI-Modell läuft via Ollama vollständig offline. Es werden keine Daten an externe Server übertragen.

Die App-Konfiguration (Namen, Einstellungen) wird lokal in `~/Library/Application Support/Stashfix/` gespeichert – nicht in iCloud.

**Hinweis:** Wenn du als Archivpfad einen iCloud Drive Ordner wählst, werden deine archivierten Belege über Apples iCloud synchronisiert. Das unterliegt dann Apples Datenschutzbestimmungen. Für maximalen Datenschutz empfehlen wir einen lokalen Ordner (Standard: `~/Documents/Stashfix`).

## Lizenz

Stashfix ist freie Software – lizenziert unter der **GNU General Public License v3.0 or later (GPL-3.0-or-later)**.

Das bedeutet:
- Du darfst die Software frei nutzen, kopieren, verändern und weitergeben
- Weiterentwicklungen müssen ebenfalls unter der GPL veröffentlicht werden
- Niemand darf daraus ein proprietäres/closed-source Produkt machen
- Kommerzielle Nutzung ist erlaubt, aber der Quellcode muss offen bleiben

```
This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU General Public License for more details.
```

Den vollständigen Lizenztext findest du in der Datei [LICENSE](LICENSE) oder unter https://www.gnu.org/licenses/gpl-3.0.html

### Lizenzen der verwendeten Tools

| Tool | Lizenz | Kompatibilität |
|------|--------|----------------|
| ocrmypdf | MPL 2.0 | ✅ GPL 3.0 kompatibel |
| tesseract | Apache 2.0 | ✅ GPL 3.0 kompatibel |
| poppler/pdftotext | GPL 2.0 or later | ✅ GPL 3.0 kompatibel |
| exiftool | Perl Artistic License | ✅ GPL 3.0 kompatibel |
| ollama | MIT | ✅ GPL 3.0 kompatibel |

### Lizenztext

```
This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program. If not, see <https://www.gnu.org/licenses/>.
```

### Spenden

Stashfix ist kostenlos und bleibt es. Wenn du das Projekt unterstützen möchtest, freue ich mich über eine Spende – das motiviert zur Weiterentwicklung.

---

## Lizenz

Copyright (C) 2026 Stashfix

Dieses Programm ist freie Software: Du kannst es unter den Bedingungen der GNU General Public License, wie von der Free Software Foundation veröffentlicht, weitergeben und/oder modifizieren, entweder gemäß Version 3 der Lizenz oder (nach deiner Wahl) jeder späteren Version.

Dieses Programm wird in der Hoffnung bereitgestellt, dass es nützlich ist, aber OHNE JEDE GEWÄHRLEISTUNG. Siehe die GNU General Public License für weitere Details.

[GNU General Public License v3.0](https://www.gnu.org/licenses/gpl-3.0.html)

---

## Spenden

Stashfix ist kostenlos und quelloffen. Wenn dir das Projekt gefällt, freue ich mich über eine Spende:

☕ [Ko-fi](https://ko-fi.com/dboegeholz) · 💛 [GitHub Sponsors](https://github.com/sponsors/dboegeholz)
