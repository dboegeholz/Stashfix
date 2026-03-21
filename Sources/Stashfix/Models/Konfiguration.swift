import Foundation

// ============================================================
// Konfiguration.swift
// Zentrale Einstellungen der App – werden in der iCloud
// gespeichert und sind auf allen Macs verfügbar.
// ============================================================

struct Konfiguration: Codable {

    // Modus: Einzelperson oder Paar
    enum Modus: String, Codable, CaseIterable {
        case einzel = "einzel"
        case paar   = "paar"

        var bezeichnung: String {
            switch self {
            case .einzel: return "Einzelperson"
            case .paar:   return "Ehepaar / Paar"
            }
        }
    }

    // Personen
    var modus:   Modus  = .einzel
    var person1: String = ""
    var person2: String = ""

    // Archivpfad
    var archivPfad: String = ""

    // Ollama
    var ollamaModell: String = "qwen3:8b"
    var ollamaURL:    String = "http://localhost:11434"

    // Auto-Modus (Folder Watcher)
    var autoModus: Bool = false

    // App-Darstellung
    var zeigeImDock: Bool = true

    // Kategorien (anpassbar)
    var kategorien: [Kategorie] = Kategorie.standard

    // Computed: Documents-Standardpfad
    static var documentsPfad: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Documents/Stashfix"
    }

    // iCloud-Pfad als Alternative
    static var iCloudPfad: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/Mobile Documents/com~apple~CloudDocs/Stashfix"
    }

    // Konfigurationsdatei in Application Support – getrennt vom Archiv
    static var speicherPfad: String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.path
        let dir = "\(appSupport)/Stashfix"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return "\(dir)/konfiguration.json"
    }

    // Laden
    static func laden() -> Konfiguration {
        let pfad = speicherPfad
        guard let data = FileManager.default.contents(atPath: pfad),
              let konfig = try? JSONDecoder().decode(Konfiguration.self, from: data)
        else {
            var standard = Konfiguration()
            standard.archivPfad = documentsPfad
            // _Inbox beim ersten Start anlegen
            let inbox = documentsPfad + "/_Inbox"
            try? FileManager.default.createDirectory(
                atPath: inbox,
                withIntermediateDirectories: true
            )
            return standard
        }
        return konfig
    }

    // Speichern in Documents
    func speichern() {
        // Sicherstellen dass der Ordner existiert
        try? FileManager.default.createDirectory(
            atPath: Konfiguration.documentsPfad,
            withIntermediateDirectories: true
        )
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: URL(fileURLWithPath: Konfiguration.speicherPfad))
    }
}

// ============================================================
// Kategorie
// Jede Kategorie hat einen Namen, ein Kürzel für die
// Ordnungsnummer und einen Typ (Einnahme/Ausgabe/Beides).
// ============================================================

struct Kategorie: Codable, Identifiable, Hashable {
    var id:      String  // z.B. "haushaltskosten"
    var name:    String  // z.B. "Haushaltskosten"
    var kuerzel: String  // z.B. "HK"
    var typ:     TypFilter

    enum TypFilter: String, Codable, CaseIterable {
        case einnahme = "Einnahme"
        case ausgabe  = "Ausgabe"
        case beides   = "Beides"
    }

    // Standardkategorien
    static let standard: [Kategorie] = [
        // Einnahmen
        Kategorie(id: "arbeitslohn",        name: "Arbeitslohn",           kuerzel: "AL", typ: .einnahme),
        Kategorie(id: "kapitalertraege",    name: "Kapitalerträge",        kuerzel: "KE", typ: .einnahme),
        Kategorie(id: "vermietung",         name: "Vermietung & Verpachtung", kuerzel: "VV", typ: .einnahme),
        Kategorie(id: "rente",              name: "Rente / Pension",       kuerzel: "RE", typ: .einnahme),
        Kategorie(id: "freiberuflich",      name: "Freiberufliche Eink.",  kuerzel: "FB", typ: .einnahme),
        Kategorie(id: "sonstige_einnahmen", name: "Sonstige Einnahmen",    kuerzel: "SE", typ: .einnahme),

        // Ausgaben
        Kategorie(id: "werbungskosten",     name: "Werbungskosten",        kuerzel: "WK", typ: .ausgabe),
        Kategorie(id: "sonderausgaben",     name: "Sonderausgaben",        kuerzel: "SA", typ: .ausgabe),
        Kategorie(id: "haushaltskosten",    name: "Haushaltskosten",       kuerzel: "HK", typ: .ausgabe),
        Kategorie(id: "handwerker",         name: "Handwerkerleistungen",  kuerzel: "HW", typ: .ausgabe),
        Kategorie(id: "haushaltsnahe",      name: "Haushaltsnahe DL",      kuerzel: "HD", typ: .ausgabe),
        Kategorie(id: "krankheitskosten",   name: "Krankheitskosten",      kuerzel: "KK", typ: .ausgabe),
        Kategorie(id: "spenden",            name: "Spenden",               kuerzel: "SP", typ: .ausgabe),
        Kategorie(id: "vorsorge",           name: "Vorsorgeaufwendungen",  kuerzel: "VO", typ: .ausgabe),
        Kategorie(id: "kinderbetreuung",    name: "Kinderbetreuung",       kuerzel: "KB", typ: .ausgabe),
        Kategorie(id: "aussergewoehnlich",  name: "Außergew. Belastungen", kuerzel: "AB", typ: .ausgabe),
        Kategorie(id: "sonstige_ausgaben",  name: "Sonstige Ausgaben",     kuerzel: "SO", typ: .ausgabe),
    ]
}

// ============================================================
// Beleg
// Ein einzelner Beleg mit allen relevanten Feldern.
// ============================================================

struct Beleg: Codable {
    var ordnungsNr:   String = ""
    var datum:        String = ""
    var steuerjahr:   String = ""
    var person:       String = ""
    var belegtyp:     String = ""
    var beschreibung: String = ""
    var betrag:       Double = 0.0
    var kategorie:    String = ""
    var typ:          String = ""
    var gemeinsam:    String = "nein"
    var notiz:        String = ""
    var dateiname:    String = ""
    var archivPfad:   String = ""
    var hash:         String = ""
}
