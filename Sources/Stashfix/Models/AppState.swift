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

    func ollamaModelleAktualisieren() async {
        guard let url = URL(string: "\(konfig.ollamaURL)/api/tags") else { return }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return }
        struct OllamaAntwort: Codable {
            struct Modell: Codable { let name: String }
            let models: [Modell]
        }
        guard let antwort = try? JSONDecoder().decode(OllamaAntwort.self, from: data) else { return }
        verfuegbareModelle = antwort.models.map { $0.name }
    }

    func statusAktualisieren(datei: String, schritt: String) {
        aktuelleDatei    = datei
        aktuellerSchritt = schritt
    }
}
