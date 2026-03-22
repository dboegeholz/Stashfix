import SwiftUI
import AppKit

// ============================================================
// OnboardingView.swift
// Erstkonfiguration beim ersten App-Start.
// Ordner werden erst am Ende angelegt – nach Nutzerbestätigung.
// ============================================================

enum OnboardingSchritt: Int, CaseIterable {
    case willkommen   = 0
    case personen     = 1
    case speicherort  = 2
    case tools        = 3
    case metadaten    = 4
    case fertig       = 5
}

@MainActor
class OnboardingFenster {
    static let shared = OnboardingFenster()
    private var fenster: NSWindow?

    func oeffnen(appState: AppState, beimAbschluss: @escaping () -> Void, abbrechenErlaubt: Bool = false, ersterStart: Bool = false) {
        let view = OnboardingView(appState: appState, beimAbschluss: beimAbschluss, abbrechenErlaubt: abbrechenErlaubt, ersterStart: ersterStart)
        let hosting = NSHostingController(rootView: view)
        let window  = NSWindow(contentViewController: hosting)
        window.title                = "Stashfix einrichten"
        window.styleMask            = [.titled]
        window.setContentSize(NSSize(width: 700, height: 560))
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        fenster = window
    }

    func schliessen() {
        fenster?.close()
        fenster = nil
    }
}

// ------------------------------------------------------------
// Haupt-Onboarding-View
// ------------------------------------------------------------
struct OnboardingView: View {
    var appState: AppState
    var beimAbschluss: () -> Void
    var abbrechenErlaubt: Bool = false
    var ersterStart: Bool = false

    @State private var schritt: OnboardingSchritt = .willkommen
    @State private var person1:  String
    @State private var person2:  String
    @State private var modus:    Konfiguration.Modus
    @State private var pfadWahl: PfadWahl
    @State private var eigenerPfad: String = ""
    @State private var zeigePfadAuswahl = false
    @State private var exifAktiv: Bool = true
    @State private var macOSTagsAktiv: Bool = true

    init(appState: AppState, beimAbschluss: @escaping () -> Void, abbrechenErlaubt: Bool = false, ersterStart: Bool = false) {
        self.appState        = appState
        self.beimAbschluss   = beimAbschluss
        self.abbrechenErlaubt = abbrechenErlaubt
        self.ersterStart     = ersterStart
        _person1    = State(initialValue: appState.konfig.person1)
        _person2    = State(initialValue: appState.konfig.person2)
        _modus      = State(initialValue: appState.konfig.modus)
        let pfad    = appState.konfig.archivPfad
        if pfad == Konfiguration.documentsPfad {
            _pfadWahl = State(initialValue: .documents)
        } else if pfad == Konfiguration.iCloudPfad {
            _pfadWahl = State(initialValue: .icloud)
        } else {
            _pfadWahl   = State(initialValue: .eigener)
        }
    }

    enum PfadWahl {
        case documents, icloud, eigener
    }

    var ausgewaehlterPfad: String {
        switch pfadWahl {
        case .documents: return Konfiguration.documentsPfad
        case .icloud:    return Konfiguration.iCloudPfad
        case .eigener:   return eigenerPfad
        }
    }

    var body: some View {
        VStack(spacing: 0) {

            // Fortschrittsbalken
            FortschrittsLeiste(aktuell: schritt.rawValue, gesamt: OnboardingSchritt.allCases.count - 1)
                .padding(.horizontal, 40)
                .padding(.top, 30)

            // Schrittinhalt
            Group {
                switch schritt {
                case .willkommen:  WillkommenSchritt()
                case .personen:    PersonenSchritt(modus: $modus, person1: $person1, person2: $person2)
                case .speicherort: SpeicherortSchritt(pfadWahl: $pfadWahl, eigenerPfad: $eigenerPfad, zeigePfadAuswahl: $zeigePfadAuswahl)
                case .tools:       ToolsSchritt()
                case .metadaten:   MetadatenSchritt(exifAktiv: $exifAktiv, macOSTagsAktiv: $macOSTagsAktiv)
                case .fertig:      FertigSchritt(pfad: ausgewaehlterPfad, person: person1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Navigation
            HStack {
                if schritt != .willkommen {
                    Button("Zurück") {
                        withAnimation {
                            schritt = OnboardingSchritt(rawValue: schritt.rawValue - 1) ?? .willkommen
                        }
                    }
                } else if abbrechenErlaubt {
                    Button(ersterStart ? "Beenden" : "Abbrechen") {
                        if ersterStart {
                            NSApp.terminate(nil)
                        } else {
                            OnboardingFenster.shared.schliessen()
                        }
                    }
                    .keyboardShortcut(.escape)
                }

                Spacer()

                if schritt == .fertig {
                    Button("App starten") {
                        abschliessen()
                    }
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else {
                    Button(schritt == .tools ? "Weiter" : "Weiter") {
                        withAnimation {
                            schritt = OnboardingSchritt(rawValue: schritt.rawValue + 1) ?? .fertig
                        }
                    }
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
                    .disabled(schritt == .personen && person1.isEmpty)
                }
            }
            .padding(24)
        }
        .frame(width: 700, height: 560)
        .fileImporter(
            isPresented: $zeigePfadAuswahl,
            allowedContentTypes: [.folder]
        ) { result in
            if case .success(let url) = result {
                eigenerPfad = url.path
                pfadWahl    = .eigener
            }
        }
    }

    private func abschliessen() {
        // Konfiguration speichern
        appState.konfig.modus              = modus
        appState.konfig.person1            = person1
        appState.konfig.person2            = modus == .paar ? person2 : ""
        appState.konfig.archivPfad         = ausgewaehlterPfad
        appState.konfig.exifMetadatenAktiv = exifAktiv
        appState.konfig.macOSTagsAktiv     = macOSTagsAktiv

        // Jetzt erst _Inbox anlegen – Jahresordner werden automatisch
        // beim ersten verarbeiteten Beleg angelegt
        let fm = FileManager.default
        let inbox = ausgewaehlterPfad + "/_Inbox"
        try? fm.createDirectory(
            atPath: inbox,
            withIntermediateDirectories: true
        )

        appState.konfig.speichern()
        OnboardingFenster.shared.schliessen()
        beimAbschluss()
    }
}


// ------------------------------------------------------------
// Schritt 1: Willkommen
// ------------------------------------------------------------
struct WillkommenSchritt: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)

            Text("Willkommen bei Stashfix")
                .font(.largeTitle)
                .bold()

            Text("Stashfix hilft dir dabei, Dokumente zu scannen, zu analysieren und an der richtigen Stelle abzulegen.\n\nAlle Daten bleiben auf deinem Mac – nichts wird in die Cloud hochgeladen.")
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 500)

            VStack(alignment: .leading, spacing: 8) {
                InfoZeile(icon: "doc.viewfinder",       text: "OCR-Texterkennung für gescannte Belege")
                InfoZeile(icon: "brain",                text: "KI-Analyse via lokalem Ollama-Modell")
                InfoZeile(icon: "folder",                text: "Automatische Sortierung in Kategorien")
                InfoZeile(icon: "tablecells",           text: "CSV-Übersicht für den Steuerberater")
            }
            Spacer()
        }
        .padding(40)
    }
}

struct InfoZeile: View {
    let icon: String
    let text: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(.accentColor)
                .frame(width: 20)
            Text(text)
                .font(.callout)
        }
    }
}


// ------------------------------------------------------------
// Schritt 2: Personen
// ------------------------------------------------------------
struct PersonenSchritt: View {
    @Binding var modus:   Konfiguration.Modus
    @Binding var person1: String
    @Binding var person2: String

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            VStack(spacing: 6) {
                Text("Für wen ist die Steuererklärung?")
                    .font(.title2).bold()
                Text("Du kannst das später in den Einstellungen ändern.")
                    .font(.callout).foregroundColor(.secondary)
            }

            Picker("", selection: $modus) {
                ForEach(Konfiguration.Modus.allCases, id: \.self) { m in
                    Text(m.bezeichnung).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 300)

            VStack(spacing: 12) {
                HStack {
                    Text(modus == .paar ? "Person 1:" : "Dein Name:")
                        .frame(width: 100, alignment: .trailing)
                        .foregroundColor(.secondary)
                    TextField("z.B. Max Mustermann", text: $person1)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 260)
                }

                if modus == .paar {
                    HStack {
                        Text("Person 2:")
                            .frame(width: 100, alignment: .trailing)
                            .foregroundColor(.secondary)
                        TextField("z.B. Erika Mustermann", text: $person2)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 260)
                    }
                }
            }

            Spacer()
        }
        .padding(40)
    }
}


// ------------------------------------------------------------
// Schritt 3: Speicherort
// ------------------------------------------------------------
struct SpeicherortSchritt: View {
    @Binding var pfadWahl:        SpeicherortWahl
    @Binding var eigenerPfad:     String
    @Binding var zeigePfadAuswahl: Bool

    // Typealias damit der Compiler nicht meckert
    typealias SpeicherortWahl = OnboardingView.PfadWahl

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            VStack(spacing: 6) {
                Text("Wo sollen die Belege gespeichert werden?")
                    .font(.title2).bold()
                Text("Die Ordnerstruktur wird erst im letzten Schritt angelegt.")
                    .font(.callout).foregroundColor(.secondary)
            }

            VStack(spacing: 12) {
                PfadOption(
                    titel:       "Dokumente",
                    untertitel:  "~/Documents/Stashfix",
                    icon:        "folder",
                    ausgewaehlt: pfadWahl == .documents
                ) { pfadWahl = .documents }

                PfadOption(
                    titel:       "iCloud Drive",
                    untertitel:  "~/iCloud Drive/Stashfix",
                    icon:        "icloud",
                    ausgewaehlt: pfadWahl == .icloud
                ) { pfadWahl = .icloud }

                PfadOption(
                    titel:       "Eigener Ordner",
                    untertitel:  eigenerPfad.isEmpty ? "Ordner auswählen..." : eigenerPfad,
                    icon:        "folder.badge.gear",
                    ausgewaehlt: pfadWahl == .eigener
                ) {
                    pfadWahl = .eigener
                    zeigePfadAuswahl = true
                }
            }
            .frame(maxWidth: 460)

            Spacer()
        }
        .padding(40)
    }
}

struct PfadOption: View {
    let titel:       String
    let untertitel:  String
    let icon:        String
    let ausgewaehlt: Bool
    let aktion:      () -> Void

    var body: some View {
        Button(action: aktion) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(ausgewaehlt ? .white : .accentColor)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(titel)
                        .font(.callout).bold()
                        .foregroundColor(ausgewaehlt ? .white : .primary)
                    Text(untertitel)
                        .font(.caption)
                        .foregroundColor(ausgewaehlt ? .white.opacity(0.8) : .secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                if ausgewaehlt {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.white)
                }
            }
            .padding(14)
            .background(ausgewaehlt ? Color.accentColor : Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }
}


// ------------------------------------------------------------
// Schritt 4: Tools
// ------------------------------------------------------------
struct ToolsSchritt: View {
    @State private var checker = DependencyChecker()

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            VStack(spacing: 6) {
                Text("Erforderliche Tools")
                    .font(.title2).bold()
                Text("Diese Tools müssen installiert sein. Du kannst die App auch ohne sie einrichten und die Tools später installieren.")
                    .font(.callout).foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 500)
            }

            VStack(spacing: 0) {
                ForEach($checker.dependencies) { $dep in
                    DependencyZeile(dep: $dep, kopiert: .constant(nil))
                    if dep.id != checker.dependencies.last?.id {
                        Divider().padding(.leading, 48)
                    }
                }
            }
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)
            .frame(maxWidth: 460)

            Button("Erneut prüfen") { checker.pruefen() }
                .buttonStyle(.borderless)
                .foregroundColor(.accentColor)

            Spacer()
        }
        .padding(40)
        .onAppear { checker.pruefen() }
    }
}


// ------------------------------------------------------------
// Schritt 5: Metadaten & Tags
// ------------------------------------------------------------
struct MetadatenSchritt: View {
    @Binding var exifAktiv:      Bool
    @Binding var macOSTagsAktiv: Bool

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "tag.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.accentColor)

            Text("Metadaten & Tags")
                .font(.title).bold()

            Text("Stashfix kann strukturierte Informationen in deine Belege einbetten. Du kannst das jederzeit in den Einstellungen ändern.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .frame(maxWidth: 460)

            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    Toggle("", isOn: $exifAktiv)
                        .toggleStyle(.switch)
                        .labelsHidden()
                    VStack(alignment: .leading, spacing: 3) {
                        Text("PDF-Metadaten einbetten")
                            .fontWeight(.medium)
                        Text("Kategorie, Aussteller und weitere Infos werden direkt in die PDF-Datei geschrieben. Die Metadaten bleiben erhalten wenn du die Datei weitergibst.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                HStack(alignment: .top, spacing: 12) {
                    Toggle("", isOn: $macOSTagsAktiv)
                        .toggleStyle(.switch)
                        .labelsHidden()
                    VStack(alignment: .leading, spacing: 3) {
                        Text("macOS Finder Tags setzen")
                            .fontWeight(.medium)
                        Text("Tags erscheinen direkt im Finder und ermöglichen schnelle Filterung und Spotlight-Suche. Sie sind nicht in der Datei selbst gespeichert und gehen beim Weitergeben verloren (E-Mail, ZIP, Cloud, FAT32-Datenträger). Ausnahme: Kopieren auf APFS/HFS+ Laufwerke erhält die Tags.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)
            .frame(maxWidth: 500)

            Spacer()
        }
        .padding()
    }
}

// ------------------------------------------------------------
// Schritt 6: Fertig
// ------------------------------------------------------------
struct FertigSchritt: View {
    let pfad:   String
    let person: String

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.green)

            Text("Alles bereit!")
                .font(.largeTitle).bold()

            Text("Beim Klick auf 'App starten' werden folgende Ordner angelegt:")
                .font(.callout).foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                OrdnerZeile(pfad: pfad + "/_Inbox")
                OrdnerZeile(pfad: pfad + "/Einnahmen/...")
                OrdnerZeile(pfad: pfad + "/Ausgaben/...")
            }
            .padding(16)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(10)

            Text("Lege gescannte Belege in den _Inbox Ordner.\nDie App erkennt sie automatisch.")
                .font(.callout).foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding(40)
    }
}

struct OrdnerZeile: View {
    let pfad: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder.fill")
                .foregroundColor(.accentColor)
                .font(.caption)
            Text(pfad.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
        }
    }
}


// ------------------------------------------------------------
// Fortschrittsleiste
// ------------------------------------------------------------
struct FortschrittsLeiste: View {
    let aktuell: Int
    let gesamt:  Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0...gesamt, id: \.self) { i in
                Capsule()
                    .fill(i <= aktuell ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(height: 4)
                    .animation(.easeInOut, value: aktuell)
            }
        }
    }
}
