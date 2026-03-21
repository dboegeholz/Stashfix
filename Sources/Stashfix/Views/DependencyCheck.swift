import SwiftUI
import AppKit

// ============================================================
// DependencyCheck.swift
// Prüft beim Start ob alle externen Tools installiert sind.
// Zeigt ein Fenster mit Installationsanleitung wenn nicht.
// ============================================================

struct Dependency: Identifiable {
    let id:          String
    let name:        String
    let befehl:      String   // z.B. "ocrmypdf"
    let zweck:       String
    let installBefehl: String
    let infoURL:     String
    var installiert: Bool = false

    static let alle: [Dependency] = [
        Dependency(
            id:            "ocrmypdf",
            name:          "ocrmypdf",
            befehl:        "ocrmypdf",
            zweck:         "OCR und PDF/A-Konvertierung",
            installBefehl: "brew install ocrmypdf",
            infoURL:       "https://ocrmypdf.readthedocs.io"
        ),
        Dependency(
            id:            "ollama",
            name:          "Ollama",
            befehl:        "ollama",
            zweck:         "Lokales KI-Modell (wird automatisch gestartet)",
            installBefehl: "brew install ollama",
            infoURL:       "https://ollama.com"
        ),
        Dependency(
            id:            "pdftotext",
            name:          "pdftotext",
            befehl:        "pdftotext",
            zweck:         "Textextraktion aus PDFs",
            installBefehl: "brew install poppler",
            infoURL:       "https://poppler.freedesktop.org"
        ),
        Dependency(
            id:            "exiftool",
            name:          "exiftool",
            befehl:        "exiftool",
            zweck:         "Metadaten in PDFs einbetten",
            installBefehl: "brew install exiftool",
            infoURL:       "https://exiftool.org"
        ),
    ]
}

// ------------------------------------------------------------
// Check-Service
// ------------------------------------------------------------
class DependencyChecker: ObservableObject {
    @Published var dependencies: [Dependency] = Dependency.alle
    @Published var allInstalled: Bool = false
    @Published var checked:      Bool = false

    func pruefen() {
        for i in dependencies.indices {
            dependencies[i].installiert = istInstalliert(dependencies[i].befehl)
        }
        allInstalled = dependencies.allSatisfy { $0.installiert }
        checked      = true
    }

    private func istInstalliert(_ befehl: String) -> Bool {
        // Alle bekannten Homebrew- und System-Pfade prüfen
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let pfade = [
            "/opt/homebrew/bin/\(befehl)",          // Apple Silicon (Standard)
            "/usr/local/bin/\(befehl)",              // Intel Mac (Standard)
            "/usr/bin/\(befehl)",                    // macOS System
            "\(home)/homebrew/bin/\(befehl)",        // Homebrew ohne Admin
            "\(home)/.homebrew/bin/\(befehl)",       // Homebrew ohne Admin (alt)
            "\(home)/bin/\(befehl)",                 // Lokale Installation
            "/opt/local/bin/\(befehl)",              // MacPorts
        ]
        if pfade.contains(where: { FileManager.default.fileExists(atPath: $0) }) {
            return true
        }
        // Fallback: which aufrufen (funktioniert wenn PATH gesetzt ist)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [befehl]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// ------------------------------------------------------------
// Dependency-Check View
// ------------------------------------------------------------
struct DependencyCheckView: View {
    @StateObject private var checker = DependencyChecker()
    @EnvironmentObject var appState:  AppState
    @State private var kopiert:       String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Header
            HStack(spacing: 12) {
                Image(systemName: checker.allInstalled
                      ? "checkmark.shield.fill"
                      : "exclamationmark.shield.fill")
                    .font(.system(size: 32))
                    .foregroundColor(checker.allInstalled ? .green : .orange)

                VStack(alignment: .leading, spacing: 4) {
                    Text(checker.allInstalled
                         ? "Alle Tools installiert"
                         : "Fehlende Tools")
                        .font(.headline)
                    Text(checker.allInstalled
                         ? "Stashfix ist einsatzbereit."
                         : "Bitte installiere die fehlenden Tools um fortzufahren.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Tool-Liste
            ScrollView {
                VStack(spacing: 0) {
                    ForEach($checker.dependencies) { $dep in
                        DependencyZeile(
                            dep:     $dep,
                            kopiert: $kopiert
                        )
                        Divider().padding(.leading, 48)
                    }
                }
            }

            Divider()

            // Footer
            HStack {
                Button("Beenden") {
                    NSApp.terminate(nil)
                }
                .foregroundColor(.secondary)

                Button("Erneut prüfen") {
                    checker.pruefen()
                }
                .keyboardShortcut("r")

                Spacer()

                if checker.allInstalled {
                    Button("Weiter") {
                        NSApp.keyWindow?.close()
                    }
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
        .frame(width: 520)
        .onAppear {
            checker.pruefen()
        }
    }
}

// ------------------------------------------------------------
// Einzelne Tool-Zeile
// ------------------------------------------------------------
struct DependencyZeile: View {
    @Binding var dep:     Dependency
    @Binding var kopiert: String?

    var body: some View {
        HStack(spacing: 12) {

            // Status-Icon
            Image(systemName: dep.installiert
                  ? "checkmark.circle.fill"
                  : "xmark.circle.fill")
                .font(.title2)
                .foregroundColor(dep.installiert ? .green : .red)
                .frame(width: 28)

            // Info
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(dep.name)
                        .font(.callout)
                        .bold()
                    Text("–")
                        .foregroundColor(.secondary)
                    Text(dep.zweck)
                        .font(.callout)
                        .foregroundColor(.secondary)
                }

                if !dep.installiert {
                    // Install-Befehl
                    HStack(spacing: 6) {
                        Text(dep.installBefehl)
                            .font(.system(.caption, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(4)

                        // Kopieren
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(dep.installBefehl, forType: .string)
                            kopiert = dep.id
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                if kopiert == dep.id { kopiert = nil }
                            }
                        } label: {
                            Image(systemName: kopiert == dep.id
                                  ? "checkmark"
                                  : "doc.on.doc")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .foregroundColor(kopiert == dep.id ? .green : .accentColor)
                        .help("Befehl kopieren")

                        // Info-Link
                        Button {
                            if let url = URL(string: dep.infoURL) {
                                NSWorkspace.shared.open(url)
                            }
                        } label: {
                            Image(systemName: "arrow.up.right.square")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .foregroundColor(.accentColor)
                        .help("Dokumentation öffnen")
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(dep.installiert
                    ? Color.clear
                    : Color.red.opacity(0.04))
    }
}

// ------------------------------------------------------------
// Modifier: zeigt DependencyCheck beim Start
// ------------------------------------------------------------
struct DependencyCheckModifier: ViewModifier {
    @StateObject private var checker = DependencyChecker()
    @State private var fensterOffen  = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                checker.pruefen()
                if !checker.allInstalled {
                    fensterOffen = true
                }
            }
            .sheet(isPresented: $fensterOffen) {
                DependencyCheckView()
            }
    }
}

extension View {
    func dependencyCheck() -> some View {
        modifier(DependencyCheckModifier())
    }
}
