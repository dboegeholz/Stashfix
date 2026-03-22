import SwiftUI

// ============================================================
// EinstellungenView.swift
// Einstellungsfenster der App mit vier Bereichen:
// - Personen (Einzelperson oder Paar)
// - Archivpfad
// - Ollama-Modell
// - Kategorien
// ============================================================

struct EinstellungenView: View {
    @Environment(AppState.self) var appState

    var body: some View {
        @Bindable var appState = appState
        TabView {
            PersonenTab()
                .tabItem {
                    Label("Personen", systemImage: "person.2")
                }

            ArchivTab()
                .tabItem {
                    Label("Archiv", systemImage: "folder")
                }

            OllamaTab()
                .tabItem {
                    Label("KI-Modell", systemImage: "brain")
                }

            KategorienTab()
                .tabItem {
                    Label("Kategorien", systemImage: "tag")
                }


            AllgemeinTab()
                .tabItem {
                    Label("Allgemein", systemImage: "gear")
                }
        }
        .padding(20)
        .environment(appState)
    }
}


// ------------------------------------------------------------
// Tab 1: Personen
// ------------------------------------------------------------
struct PersonenTab: View {
    @Environment(AppState.self) var appState

    var body: some View {
        @Bindable var appState = appState
        Form {
            Section {
                Picker("Steuererklärung für:", selection: $appState.konfig.modus) {
                    ForEach(Konfiguration.Modus.allCases, id: \.self) { modus in
                        Text(modus.bezeichnung).tag(modus)
                    }
                }
                .pickerStyle(.radioGroup)
            }

            Section {
                TextField("Name Person 1", text: $appState.konfig.person1)
                    .textFieldStyle(.roundedBorder)

                if appState.konfig.modus == .paar {
                    TextField("Name Person 2", text: $appState.konfig.person2)
                        .textFieldStyle(.roundedBorder)
                }
            } header: {
                Text("Namen")
                    .font(.headline)
            }
        }
        .formStyle(.grouped)
        .onChange(of: appState.konfig.modus)   { appState.konfigurationSpeichern() }
        .onChange(of: appState.konfig.person1) { appState.konfigurationSpeichern() }
        .onChange(of: appState.konfig.person2) { appState.konfigurationSpeichern() }
    }
}


// ------------------------------------------------------------
// Tab 2: Archiv
// ------------------------------------------------------------
struct ArchivTab: View {
    @Environment(AppState.self) var appState
    @State private var zeigeOrdnerAuswahl = false

    var body: some View {
        @Bindable var appState = appState
        Form {
            Section {
                HStack {
                    TextField("Pfad", text: $appState.konfig.archivPfad)
                        .textFieldStyle(.roundedBorder)
                    Button("Auswählen...") {
                        zeigeOrdnerAuswahl = true
                    }
                }
                Text("Standard: ~/Documents/Stashfix")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Button("Standardpfad wiederherstellen") {
                    appState.konfig.archivPfad = Konfiguration.documentsPfad
                    appState.konfigurationSpeichern()
                }
                .buttonStyle(.borderless)
                .foregroundColor(.accentColor)
            } header: {
                Text("Archivordner")
                    .font(.headline)
            }

            Section {
                Text("Im Archivordner werden folgende Unterordner erwartet:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("_Inbox  /  [Jahr]  /  Einnahmen  /  Ausgaben")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                Button("Ordnerstruktur jetzt anlegen") {
                    ordnerstrukturAnlegen()
                }
            } header: {
                Text("Ordnerstruktur")
                    .font(.headline)
            }
        }
        .formStyle(.grouped)
        .fileImporter(
            isPresented: $zeigeOrdnerAuswahl,
            allowedContentTypes: [.folder]
        ) { result in
            if case .success(let url) = result {
                appState.konfig.archivPfad = url.path
                appState.konfigurationSpeichern()
            }
        }
        .onChange(of: appState.konfig.archivPfad) { appState.konfigurationSpeichern() }
    }

    func ordnerstrukturAnlegen() {
        // Nur _Inbox anlegen – Jahresordner werden automatisch
        // beim ersten verarbeiteten Beleg erstellt
        try? FileManager.default.createDirectory(
            atPath: "\(appState.konfig.archivPfad)/_Inbox",
            withIntermediateDirectories: true
        )
    }
}


// ------------------------------------------------------------
// Tab 3: Ollama
// ------------------------------------------------------------
struct OllamaTab: View {
    @Environment(AppState.self) var appState
    @State private var zeigePromptReset = false

    var body: some View {
        @Bindable var appState = appState
        Form {
            Section {
                TextField("URL", text: $appState.konfig.ollamaURL)
                    .textFieldStyle(.roundedBorder)
                Text("Standard: http://localhost:11434")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } header: {
                Text("Ollama-Server")
                    .font(.headline)
            }

            Section {
                HStack {
                    if appState.verfuegbareModelle.isEmpty {
                        Text("Keine Modelle gefunden – läuft Ollama?")
                            .foregroundColor(.secondary)
                            .font(.callout)
                    } else {
                        Picker("Modell:", selection: $appState.konfig.ollamaModell) {
                            ForEach(appState.verfuegbareModelle, id: \.self) { modell in
                                Text(modell).tag(modell)
                            }
                        }
                    }
                    Spacer()
                    Button("Aktualisieren") {
                        Task { await appState.ollamaModelleAktualisieren() }
                    }
                }
            } header: {
                Text("Modell")
                    .font(.headline)
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Platzhalter: {{personen}}, {{kategorien}}, {{jahr}}, {{text}}")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("Zurücksetzen") {
                            zeigePromptReset = true
                        }
                        .foregroundColor(.orange)
                        .buttonStyle(.borderless)
                        .font(.caption)
                    }
                    TextEditor(text: $appState.konfig.ollamaPrompt)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 180)
                        .scrollContentBackground(.hidden)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(6)
                        .onChange(of: appState.konfig.ollamaPrompt) {
                            appState.konfigurationSpeichern()
                        }
                }
            } header: {
                Text("Analyse-Prompt")
                    .font(.headline)
            }
        }
        .formStyle(.grouped)
        .task {
            // Ollama kurz starten um Modelle zu laden, dann wieder beenden
            await appState.ollamaFuerModelllisteStarten()
            await appState.ollamaModelleAktualisieren()
        }
        .onChange(of: appState.konfig.ollamaURL)     { appState.konfigurationSpeichern() }
        .onChange(of: appState.konfig.ollamaModell)  { appState.konfigurationSpeichern() }
        .alert("Prompt zurücksetzen?", isPresented: $zeigePromptReset) {
            Button("Abbrechen", role: .cancel) {}
            Button("Zurücksetzen", role: .destructive) {
                appState.konfig.ollamaPrompt = Konfiguration.standardPrompt
                appState.konfigurationSpeichern()
            }
        } message: {
            Text("Der Prompt wird auf den Standardwert zurückgesetzt.")
        }
    }
}


// ------------------------------------------------------------
// Tab 4: Kategorien
// ------------------------------------------------------------
struct KategorienTab: View {
    @Environment(AppState.self) var appState
    @State private var neuerName:    String = ""
    @State private var neuesKuerzel: String = ""
    @State private var neuerTyp:     Kategorie.TypFilter = .ausgabe

    var body: some View {
        @Bindable var appState = appState
        VStack(alignment: .leading, spacing: 12) {

            Text("Kategorien")
                .font(.headline)
                .padding(.horizontal)
                .padding(.top, 8)

            List {
                ForEach($appState.konfig.kategorien) { $kat in
                    HStack(spacing: 12) {
                        // Farbkreis
                        Circle()
                            .fill(kategoriefarbe(kat.name))
                            .frame(width: 12, height: 12)

                        // Name (editierbar)
                        TextField("Name", text: $kat.name)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 160)

                        // Kürzel (editierbar)
                        TextField("Kürzel", text: $kat.kuerzel)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)

                        // Typ
                        Picker("", selection: $kat.typ) {
                            ForEach(Kategorie.TypFilter.allCases, id: \.self) { t in
                                Text(t.rawValue).tag(t)
                            }
                        }
                        .frame(width: 110)

                        Spacer()

                        // Löschen
                        Button {
                            appState.konfig.kategorien.removeAll { $0.id == kat.id }
                            appState.konfigurationSpeichern()
                        } label: {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 2)
                }
            }
            .frame(minHeight: 200)

            Divider()

            // Neue Kategorie hinzufügen
            HStack(spacing: 8) {
                TextField("Name", text: $neuerName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
                TextField("Kürzel", text: $neuesKuerzel)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                Picker("", selection: $neuerTyp) {
                    ForEach(Kategorie.TypFilter.allCases, id: \.self) { t in
                        Text(t.rawValue).tag(t)
                    }
                }
                .frame(width: 110)
                Button("Hinzufügen") {
                    guard !neuerName.isEmpty, !neuesKuerzel.isEmpty else { return }
                    let neu = Kategorie(
                        id:      neuerName.lowercased().replacingOccurrences(of: " ", with: "_"),
                        name:    neuerName,
                        kuerzel: neuesKuerzel.uppercased(),
                        typ:     neuerTyp
                    )
                    appState.konfig.kategorien.append(neu)
                    appState.konfigurationSpeichern()
                    neuerName    = ""
                    neuesKuerzel = ""
                }
                .buttonStyle(.borderedProminent)
                .disabled(neuerName.isEmpty || neuesKuerzel.isEmpty)
            }
            .padding(.horizontal)
            .padding(.bottom, 12)
        }
        .onChange(of: appState.konfig.kategorien) { appState.konfigurationSpeichern() }
    }
}

// Farbfunktion (gleich wie in steuer_confirm)
func kategoriefarbe(_ name: String) -> Color {
    switch name {
    case "Haushaltskosten":  return Color(red:1.0,  green:0.87, blue:0.7)
    case "Werbungskosten":   return Color(red:0.7,  green:0.9,  blue:1.0)
    case "Sonderausgaben":   return Color(red:0.85, green:0.7,  blue:1.0)
    case "Gehalt":           return Color(red:0.7,  green:1.0,  blue:0.75)
    default:                 return Color(red:0.9,  green:0.9,  blue:0.9)
    }
}

// ------------------------------------------------------------
// Tab 5: Allgemein
// ------------------------------------------------------------
struct AllgemeinTab: View {
    @Environment(AppState.self) var appState
    @State private var zeigeResetBestaetigung = false
    @State private var zeigeDublettenReset = false

    var body: some View {
        @Bindable var appState = appState
        Form {
            Section {
                Toggle(isOn: $appState.konfig.zeigeImDock) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("App im Dock anzeigen")
                        Text("Andernfalls erscheint die App nur in der Menüleiste oben rechts.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .onChange(of: appState.konfig.zeigeImDock) {
                    appState.konfigurationSpeichern()
                }
            } header: {
                Text("Darstellung")
                    .font(.headline)
            }

            Section {
                Toggle(isOn: $appState.konfig.exifMetadatenAktiv) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("PDF-Metadaten einbetten (exiftool)")
                        Text("Kategorie, Aussteller und weitere Infos werden in die PDF-Datei geschrieben und sind portabel.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .onChange(of: appState.konfig.exifMetadatenAktiv) { appState.konfigurationSpeichern() }

                Toggle(isOn: $appState.konfig.macOSTagsAktiv) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("macOS Finder Tags setzen")
                        Text("Tags ermöglichen schnelle Filterung im Finder und Spotlight-Suche. Werden nicht mit der Datei übertragen.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .onChange(of: appState.konfig.macOSTagsAktiv) { appState.konfigurationSpeichern() }
            } header: {
                Text("Metadaten & Tags")
                    .font(.headline)
            }

            Section {
                Button("Einrichtungsassistent erneut starten") {
                    OnboardingFenster.shared.oeffnen(appState: appState, beimAbschluss: {}, abbrechenErlaubt: true)
                }
                .foregroundColor(.accentColor)
                .buttonStyle(.borderless)
            } header: {
                Text("Einrichtung")
                    .font(.headline)
            }

            Section {
                // Konfigurationsdatei im Finder zeigen
                Button("Konfigurationsdatei im Finder zeigen") {
                    let pfad = Konfiguration.speicherPfad
                    NSWorkspace.shared.selectFile(pfad, inFileViewerRootedAtPath: (pfad as NSString).deletingLastPathComponent)
                }
                .foregroundColor(.accentColor)
                .buttonStyle(.borderless)

                // Dubletten-Datei im Finder zeigen
                Button("Dublettenprotokoll im Finder zeigen") {
                    let pfad = appState.konfig.archivPfad + "/.verarbeitete_belege"
                    NSWorkspace.shared.selectFile(pfad, inFileViewerRootedAtPath: appState.konfig.archivPfad)
                }
                .foregroundColor(.accentColor)
                .buttonStyle(.borderless)
            } header: {
                Text("Datenpfade")
                    .font(.headline)
            }

            Section {
                Button("Nur Dublettenprotokoll zurücksetzen…") {
                    zeigeDublettenReset = true
                }
                .foregroundColor(.orange)
                .buttonStyle(.borderless)

                Button("Alle Einstellungen zurücksetzen…") {
                    zeigeResetBestaetigung = true
                }
                .foregroundColor(.red)
                .buttonStyle(.borderless)
            } header: {
                Text("Zurücksetzen")
                    .font(.headline)
            }
        }
        .formStyle(.grouped)
        .alert("Dublettenprotokoll zurücksetzen?", isPresented: $zeigeDublettenReset) {
            Button("Abbrechen", role: .cancel) {}
            Button("Zurücksetzen", role: .destructive) {
                let pfad = appState.konfig.archivPfad + "/.verarbeitete_belege"
                // Datei existiert möglicherweise noch nicht – kein Fehler
                if FileManager.default.fileExists(atPath: pfad) {
                    try? FileManager.default.removeItem(atPath: pfad)
                }
            }
        } message: {
            Text("Alle gespeicherten Datei-Hashes werden gelöscht. Bereits archivierte Belege bleiben erhalten, können aber erneut verarbeitet werden.")
        }
        .alert("Alle Einstellungen zurücksetzen?", isPresented: $zeigeResetBestaetigung) {
            Button("Abbrechen", role: .cancel) {}
            Button("Zurücksetzen", role: .destructive) {
                // Konfigurationsdatei löschen (inkl. Prompt, Kategorien, Namen)
                try? FileManager.default.removeItem(atPath: Konfiguration.speicherPfad)
                // Dublettenprotokoll löschen
                let dublettenPfad = appState.konfig.archivPfad + "/.verarbeitete_belege"
                try? FileManager.default.removeItem(atPath: dublettenPfad)
                // App neu starten
                let url = URL(fileURLWithPath: Bundle.main.bundlePath)
                let config = NSWorkspace.OpenConfiguration()
                NSWorkspace.shared.openApplication(at: url, configuration: config)
                NSApp.terminate(nil)
            }
        } message: {
            Text("Folgendes wird gelöscht:\n• Personennamen und Modus\n• Kategorien\n• Analyse-Prompt (wird auf Standard zurückgesetzt)\n• Archivpfad\n• Ollama-Einstellungen\n• Dublettenprotokoll\n\nDas Archiv selbst bleibt erhalten. Die App wird danach neu gestartet.")
        }
    }
}
