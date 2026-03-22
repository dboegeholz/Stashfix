import SwiftUI
import Observation

// ============================================================
// AppState.swift
// Zentraler App-Zustand – @Observable statt ObservableObject.
// Kein @Published mehr nötig, SwiftUI trackt Zugriffe automatisch.
// ============================================================

@MainActor
@Observable
class AppState {

    var konfig:             Konfiguration = Konfiguration.laden()
    var inboxDateien:       [URL]         = []
    var verarbeitet:        Int           = 0
    var gesamt:             Int           = 0
    var laeuft:             Bool          = false
    var aktuelleDatei:      String        = ""
    var aktuellerSchritt:   String        = ""
    var fehler:             String?       = nil
    var verfuegbareModelle: [String]      = []

    var zeigeOnboarding: Bool {
        konfig.person1.isEmpty
    }

    func konfigurationSpeichern() {
        konfig.speichern()
        dockDarstellungAktualisieren()
    }

    func dockDarstellungAktualisieren() {
        NSApp.setActivationPolicy(konfig.zeigeImDock ? .regular : .accessory)
    }

    func inboxLaden() {
        let inbox = konfig.archivPfad + "/_Inbox"
        let fm = FileManager.default
        guard let inhalt = try? fm.contentsOfDirectory(
            at: URL(fileURLWithPath: inbox),
            includingPropertiesForKeys: nil
        ) else {
            inboxDateien = []
            dockBadgeAktualisieren(anzahl: 0)
            return
        }
        inboxDateien = inhalt.filter {
            $0.pathExtension.lowercased() == "pdf"
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        dockBadgeAktualisieren(anzahl: inboxDateien.count)
    }

    func dockBadgeAktualisieren(anzahl: Int) {
        NSApp.dockTile.badgeLabel = anzahl > 0 ? "\(anzahl)" : nil
    }

    func ollamaFuerModelllisteStarten() async {
        // Ollama kurz starten damit der Modell-Picker befüllt werden kann.
        // Wird nur gestartet wenn es nicht bereits läuft.
        guard let url = URL(string: konfig.ollamaURL) else { return }
        if (try? await URLSession.shared.data(from: url)) != nil { return }

        // Pfad suchen – alle üblichen Installationsorte
        let pfade = [
            "/opt/homebrew/bin/ollama",
            "/usr/local/bin/ollama",
            "/usr/bin/ollama",
            FileManager.default.homeDirectoryForCurrentUser.path + "/homebrew/bin/ollama",
        ]
        guard let pfad = pfade.first(where: { FileManager.default.fileExists(atPath: $0) }) else { return }

        // Process auf Background-Thread starten um MainActor nicht zu blockieren
        await Task.detached(priority: .background) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: pfad)
            process.arguments     = ["serve"]
            process.standardOutput = Pipe()
            process.standardError  = Pipe()
            try? process.run()
        }.value

        // Bis zu 5 Sekunden auf Bereitschaft warten
        for _ in 0..<10 {
            try? await Task.sleep(for: .milliseconds(500))
            if (try? await URLSession.shared.data(from: url)) != nil { return }
        }
    }

    func ollamaModelleAktualisieren() async {
        guard let url = URL(string: "\(konfig.ollamaURL)/api/tags") else { return }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return }
        guard let antwort = try? JSONDecoder().decode(OllamaTagsAntwort.self, from: data) else { return }
        verfuegbareModelle = antwort.models.map { $0.name }
    }

    func statusAktualisieren(datei: String, schritt: String) {
        aktuelleDatei    = datei
        aktuellerSchritt = schritt
    }
}
