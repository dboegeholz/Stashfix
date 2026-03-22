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

    static let standardPrompt = """
        Du bist ein Assistent für deutsche Steuererklärungen.
        Steuererklärung für: {{personen}}.

        Antworte NUR mit kompaktem JSON in EINER einzigen Zeile – absolut keine Zeilenumbrüche, keine Einrückung, kein Pretty-Print. Beispiel: {"datum":"2024-01-01","steuerjahr":"2024",...}
        Ohne Erklärung, ohne Backticks, ohne Markdown.
        WICHTIG: Verwende EXAKT diese deutschen Feldnamen – keine englischen Übersetzungen, keine Abweichungen.

        Format (eine Zeile, keine Umbrüche):
        {"datum":"JJJJ-MM-TT","steuerjahr":"JJJJ","person":"...","belegtyp":"...","beschreibung":"...","betrag":"...","kategorie":"...","typ":"...","gemeinsam":"...","notiz":"...","steuerrelevant":true}

        Regeln:
        - datum: Belegdatum JJJJ-MM-TT. Alle Formate umwandeln: "07.01.22"→"2022-01-07", "07.01.2022"→"2022-01-07". Fallback: {{jahr}}-01-01
        - steuerjahr: Das steuerlich relevante Abrechnungsjahr – NICHT das Ausstellungsdatum des Dokuments.
            Bei Kapitalertragsbescheinigung/Jahressteuerbescheinigung: das Kalenderjahr das bescheinigt wird (steht explizit im Dokument, z.B. "für das Kalenderjahr 2024" → "2024").
            Bei Lohnsteuerbescheinigung: das Abrechnungsjahr (steht groß auf dem Dokument).
            Bei allen anderen: Jahr aus datum.
            WICHTIG: Ein Dokument vom März 2025 über das Kalenderjahr 2024 hat steuerjahr "2024", nicht "2025".
        - person: Wem gehört dieser Beleg? Nur einen der folgenden Werte verwenden: {{personen}}
            Prüfe ob ein Name im Dokument vorkommt der zu einer der Personen passt (auch Teilübereinstimmung, z.B. zweiter Vorname). Falls eindeutig einer Person zuzuordnen: diesen Namen verwenden. Falls unklar oder beide betroffen: "Gemeinsam". Feldname ist immer "person", nicht "steuerpflichtiger" oder "empfaenger".
        - belegtyp: Wähle den passendsten aus diesen Werten (exakt so schreiben):
            Rechnung | Quittung | Lohnsteuerbescheinigung | Bescheinigung | Kontoauszug | Vertrag | Sonstiges
        - beschreibung: Kurzes Schlagwort für den Dokumentinhalt, max 30 Zeichen. Beispiele: "Kapitalertragssteuerbescheinigung", "Lohnsteuerbescheinigung", "Rechnung Strom", "Arztrechnung". NICHT der Name des Ausstellers.
        - betrag: NUR der finale GESAMTBETRAG als Zahl mit Punkt. Falls kein Betrag im Text erkennbar: 0
            Kassenbon: neben "Total", "Gesamt", "SUMME" oder "EUR [Betrag]"
            Lohnsteuerbescheinigung: Bruttoarbeitslohn (Zeile 3). WICHTIG: Der Betrag steht in zwei Spalten – Euro-Betrag links (z.B. "42.350") und Cent rechts (z.B. "00"). Kombiniere beide: "42.350" + "00" = 42350.00. Der Punkt ist Tausendertrennzeichen, KEIN Dezimalzeichen. Niemals "42.350" als 42,35 interpretieren.
            Kapitalertragsbescheinigung: NUR der Betrag aus Zeile 7 Anlage KAP ("Höhe der Kapitalerträge"). WICHTIG: Das Layout ist mehrzeilig – "Zeile 7 Anlage KAP" steht auf einer Zeile, dann folgt "EUR" auf einer eigenen Zeile, dann der Betrag auf der nächsten Zeile (z.B. "209,11"). Suche die Zeile mit "Zeile 7" und nimm den ersten Zahlenwert der danach erscheint, auch wenn er mehrere Zeilen weiter unten steht. NICHT Zeile 37 (Kapitalertragsteuer), NICHT Zeile 38 (Solidaritätszuschlag). Komma ist Dezimaltrennzeichen: "209,11" = 209.11, NICHT 20911.
            Steuerbescheid: festgesetzte Steuer oder Erstattungsbetrag
            Sonst: der wichtigste Betrag des Dokuments. Falls kein Betrag erkennbar: 0
        - kategorie: Wähle die am besten passende Kategorie aus dieser Liste: {{kategorien}}
            Ordne den Dokumentinhalt inhaltlich zu – nicht nach Kategorienamen sondern nach Bedeutung.
            Kapitalerträge, Zinsen, Dividenden, Wertpapiere → wähle die Kategorie die am ehesten "Kapitalerträge" bedeutet
            Lohn, Gehalt, Arbeitslohn → wähle die Kategorie die am ehesten "Arbeitslohn" bedeutet
            Arzt, Krankenhaus, Medikamente → wähle die Kategorie die am ehesten "Krankheitskosten" bedeutet
            Handwerker, Reparatur, Baumarkt → wähle die Kategorie die am ehesten "Handwerkerleistungen" bedeutet
            Versicherung → wähle die Kategorie die am ehesten "Vorsorgeaufwendungen" bedeutet
            Spende → wähle die Kategorie die am ehesten "Spenden" bedeutet
            Falls keine Kategorie passt: wähle die inhaltlich nächste aus der Liste.
        - typ: "Einnahme" oder "Ausgabe" – leite dies aus dem Dokumentinhalt ab, NICHT aus dem Kategorienamen:
            Einnahme: Kapitalerträge, Zinsen, Dividenden, Lohn/Gehalt, Steuererstattung, Mieteinnahmen – alles was Geldeingang bescheinigt
            Ausgabe: Rechnungen, Kassenbons, Quittungen, gezahlte Beiträge – alles was Geldausgang belegt
            WICHTIG: Ein Dokument über Kapitalerträge ist IMMER eine Einnahme, auch wenn darauf Steuern ausgewiesen sind.
        - gemeinsam: ja oder nein
        - steuerrelevant: true wenn steuerlich relevant (Lohnsteuerbescheinigung, Rechnung mit Steuerbezug, Krankheitskosten, Spenden etc.). false für rein private Unterlagen ohne Steuerbezug.
        - notiz: Steuerlicher Hinweis, max 60 Zeichen. Beispiele:
            "Bruttolohn lt. Lohnsteuerbescheinigung"
            "Kapitalerträge abgeltungssteuerpflichtig"
            "FFP2-Masken, ggf. Krankheitskosten absetzbar"
            "leer" wenn kein Hinweis nötig

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
