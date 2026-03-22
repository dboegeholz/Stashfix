import Foundation

// ============================================================
// Konfiguration.swift
// Zentrale Einstellungen der App.
// Werden lokal in ~/Library/Application Support/Stashfix/ gespeichert.
// Das Archiv kann optional in iCloud abgelegt werden (Nutzerentscheidung).
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

    // Metadaten & Tags
    var exifMetadatenAktiv: Bool = true  // exiftool Keywords in PDF einbetten
    var macOSTagsAktiv:     Bool = true  // macOS Finder Tags setzen

    // Prompt-Version – wird bei jeder inhaltlichen Prompt-Änderung erhöht.
    // Beim Laden: wenn gespeicherte Version < aktuelle, wird Prompt automatisch migriert.
    var promptVersion: Int = 0
    static let aktuellePromptVersion = 12

    // Ollama Prompt – anpassbar, Platzhalter werden zur Laufzeit ersetzt
    // {{personen}}   → Namen der Steuerpflichtigen
    // {{kategorien}} → Liste aller Kategorien
    // {{jahr}}       → Aktuelles Jahr als Fallback
    // {{text}}       → Extrahierter PDF-Text (wird immer ans Ende gesetzt)
    //
    // Hinweis: /no_think am Promptende deaktiviert den Reasoning-Modus bei
    // Qwen3-Modellen und halbiert die Latenz. Der VerarbeitungsService
    // entfernt /no_think automatisch wenn ein anderes Modell konfiguriert ist.
    var ollamaPrompt: String = Konfiguration.standardPrompt

    // Backup des alten Prompts nach automatischer Migration – nil wenn kein Backup vorhanden
    var ollamaPromptBackup: String? = nil

    // true wenn der Nutzer den Prompt manuell bearbeitet hat – steuert ob Backup erstellt wird
    var promptManuellBearbeitet: Bool = false

    static let standardPrompt = """
        Du bist Experte für deutsches Steuerrecht. Analysiere den Dokumenttext und befülle das JSON mit deinem Fachwissen.

        Antworte NUR mit kompaktem JSON in EINER Zeile, ohne Umbrüche, Backticks oder Erklärungen.
        Verwende EXAKT diese deutschen Feldnamen:

        {"datum":"JJJJ-MM-TT","steuerjahr":"JJJJ","person":"...","belegtyp":"...","beschreibung":"...","aussteller":"...","betrag":0.00,"kategorie":"...","typ":"...","gemeinsam":"...","notiz":"...","steuerrelevant":true}

        Strikte Vorgaben (keine Abweichung):

        person – NUR einer dieser Werte:
        {{person_regel}}

        belegtyp – NUR einer dieser Werte:
        Rechnung | Quittung | Lohnsteuerbescheinigung | Bescheinigung | Kontoauszug | Vertrag | Sonstiges

        steuerjahr – das steuerlich relevante Jahr, NICHT das Ausstellungsdatum.
        Ein Dokument vom März 2025 über Kalenderjahr 2024 → steuerjahr "2024".

        typ – "Einnahme" oder "Ausgabe":
        WICHTIG: Wenn eine Rechnung oder Quittung an {{personen}} adressiert ist → IMMER "Ausgabe".
        Einnahme nur bei: Lohnbescheinigung, Kapitalertragsbescheinigung, Steuererstattung, Mieteinnahmen, selbst gestellte Rechnungen.

        betrag – Achtung bei diesen Dokumenttypen:
        Lohnsteuerbescheinigung: Bruttoarbeitslohn Zeile 3. Euro- und Cent-Spalte zusammensetzen (z.B. "42.350" + "00" = 42350.00). Punkt = Tausendertrennzeichen, KEIN Dezimalzeichen.
        Kapitalertragsbescheinigung: NUR Zeile 7 Anlage KAP. Mehrzeiliges Layout: erst "Zeile 7", dann "EUR", dann Betrag (kann mehrere Zeilen weiter unten stehen). NICHT Zeile 37/38. Komma = Dezimaltrennzeichen: "209,11" = 209.11, NICHT 20911.
        Sonst: wichtigster steuerrelevanter Betrag. Nicht erkennbar → 0

        Freie Felder (nutze dein Fachwissen):
        beschreibung – präziser Dokumenttitel wie ein Steuerberater ihn verwenden würde (max 40 Zeichen)
        aussteller – ausstellende Institution oder Person (max 40 Zeichen, "Unbekannt" falls nicht erkennbar)
        kategorie – passendste aus: {{kategorien}}
        typ – "Einnahme" oder "Ausgabe" nach wirtschaftlichem Gehalt
        gemeinsam – "ja" oder "nein"
        steuerrelevant – true oder false
        notiz – fachlicher Hinweis für den Steuerberater (max 60 Zeichen, "leer" wenn nicht nötig)

        Dokumenttext:
        {{text}}
        /no_think
        """


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
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.path else {
            return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".stashfix").path
        }
        let dir = "\(appSupport)/Stashfix"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return "\(dir)/konfiguration.json"
    }

    // Laden
    static func laden() -> Konfiguration {
        let pfad = speicherPfad
        guard let data = FileManager.default.contents(atPath: pfad) else {
            // Erster Start – frische Konfiguration mit aktuellem Prompt
            var standard = Konfiguration()
            standard.archivPfad    = documentsPfad
            standard.promptVersion = aktuellePromptVersion
            let inbox = documentsPfad + "/_Inbox"
            try? FileManager.default.createDirectory(
                atPath: inbox,
                withIntermediateDirectories: true
            )
            return standard
        }

        // Bestehende Konfiguration laden – fehlende neue Felder bekommen Defaultwerte
        if var konfig = try? JSONDecoder().decode(Konfiguration.self, from: data) {
            // Auto-Migration: Prompt auf neue Version aktualisieren
            // Backup nur wenn der Nutzer den Prompt manuell bearbeitet hatte
            if konfig.promptVersion < aktuellePromptVersion {
                if konfig.promptManuellBearbeitet {
                    konfig.ollamaPromptBackup = konfig.ollamaPrompt
                }
                konfig.ollamaPrompt           = standardPrompt
                konfig.promptVersion          = aktuellePromptVersion
                konfig.promptManuellBearbeitet = false
                konfig.speichern()
            }
            return konfig
        }

        // Fallback: JSON vorhanden aber nicht vollständig dekodierbar
        // Alle vorhandenen Werte retten – KEINE stillen Änderungen
        if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            var gerettet = Konfiguration()
            gerettet.archivPfad    = dict["archivPfad"]    as? String ?? documentsPfad
            gerettet.person1       = dict["person1"]       as? String ?? ""
            gerettet.person2       = dict["person2"]       as? String ?? ""
            gerettet.modus         = (dict["modus"] as? String).flatMap(Konfiguration.Modus.init) ?? .einzel
            gerettet.ollamaModell  = dict["ollamaModell"]  as? String ?? "qwen3:8b"
            gerettet.ollamaURL     = dict["ollamaURL"]     as? String ?? "http://localhost:11434"
            gerettet.ollamaPrompt  = dict["ollamaPrompt"]  as? String ?? standardPrompt
            gerettet.promptVersion = dict["promptVersion"] as? Int    ?? 0
            return gerettet
        }

        // Letzter Fallback
        var standard = Konfiguration()
        standard.archivPfad = documentsPfad
        return standard
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
// Ollama API – geteilte Response-Typen
// ============================================================

struct OllamaTagsAntwort: Codable {
    struct Modell: Codable { let name: String }
    let models: [Modell]
}

// ============================================================
// Beleg
// Ein einzelner Beleg mit allen relevanten Feldern.
// ============================================================

struct Beleg: Codable {
    var ordnungsNr:      String = ""
    var datum:           String = ""
    var steuerjahr:      String = ""
    var person:          String = ""
    var belegtyp:        String = ""
    var beschreibung:    String = ""
    var aussteller:      String = ""
    var betrag:          Double = 0.0
    var kategorie:       String = ""
    var typ:             String = ""
    var gemeinsam:       String = "nein"
    var notiz:           String = ""
    var dateiname:       String = ""
    var archivPfad:      String = ""
    var hash:            String = ""
    var steuerrelevant:  Bool   = true  // Steuerbezug – steuert macOS Tags und exiftool Keywords
}
