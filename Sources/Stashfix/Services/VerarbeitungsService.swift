import Foundation
import AppKit
import CryptoKit  // SHA256

// ============================================================
// VerarbeitungsService.swift
// Verarbeitet PDFs aus der Inbox:
// 1. Dubletten-Check (SHA-256, erste 64KB)
// 2. OCR + PDF/A (ocrmypdf)
// 3. Textextraktion (pdftotext)
// 4. KI-Analyse (Ollama)
// 5. Bestätigung (steuer_confirm)
// 6. Ordnungsnummer vergeben
// 7. Metadaten einbetten (exiftool)
// 8. Datei verschieben + umbenennen
// 9. CSV + Hash aktualisieren
// ============================================================

@MainActor
class VerarbeitungsService {

    private var appState: AppState
    private let fm = FileManager.default
    private var ollamaVonUnsGestartet = false
    private var ollamaProzess: Process? = nil  // Prozess-Handle für gezieltes Beenden

    init(appState: AppState) {
        self.appState = appState
    }

    // ------------------------------------------------------------
    // Datum-Formatierung
    // Intern immer JJJJ-MM-TT (ISO), Anzeige/CSV als TT.MM.JJJJ
    // ------------------------------------------------------------
    private func datumAnzeige(_ iso: String) -> String {
        // Erwartet JJJJ-MM-TT, gibt TT.MM.JJJJ zurück
        let teile = iso.split(separator: "-")
        guard teile.count == 3 else { return iso }
        return "\(teile[2]).\(teile[1]).\(teile[0])"
    }

    private func beschreibungFuerDateiname(_ text: String) -> String {
        // Umlaute nach internationaler Norm (DIN 5007)
        let result = text
            .replacingOccurrences(of: "ä", with: "ae")
            .replacingOccurrences(of: "ö", with: "oe")
            .replacingOccurrences(of: "ü", with: "ue")
            .replacingOccurrences(of: "Ä", with: "Ae")
            .replacingOccurrences(of: "Ö", with: "Oe")
            .replacingOccurrences(of: "Ü", with: "Ue")
            .replacingOccurrences(of: "ß", with: "ss")
        // Sonderzeichen und Leerzeichen durch Unterstrich ersetzen
        let erlaubt = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        return result
            .components(separatedBy: erlaubt.inverted)
            .joined(separator: "_")
            .replacingOccurrences(of: "__+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    // Callbacks für Menüleisten-Animation
    var onStart: (() -> Void)?
    var onStop:  (() -> Void)?

// Zwischenspeicher: analysierter Beleg vor Bestätigung
    private struct AnalyseErgebnis {
        let url:      URL
        let tmpURL:   URL
        let pdfURL:   URL
        let beleg:    Beleg
    }

    // Findet den Pfad eines Tools in allen bekannten Installationsorten
    nonisolated private func toolPfad(_ befehl: String) -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let pfade = [
            "/opt/homebrew/bin/\(befehl)",
            "/usr/local/bin/\(befehl)",
            "/usr/bin/\(befehl)",
            "\(home)/homebrew/bin/\(befehl)",
            "\(home)/.homebrew/bin/\(befehl)",
            "\(home)/bin/\(befehl)",
            "/opt/local/bin/\(befehl)",
        ]
        return pfade.first { FileManager.default.fileExists(atPath: $0) }
    }

    // ------------------------------------------------------------
    // Hauptmethode: alle PDFs in der Inbox verarbeiten
    // ------------------------------------------------------------
    func alleVerarbeiten() async {
        guard !appState.laeuft else { return }
        appState.laeuft      = true
        appState.verarbeitet = 0
        onStart?()
        DevLog.shared.aktiv = true
        DevLog.shared.log("▶ Verarbeitung gestartet – \(appState.inboxDateien.count) Datei(en)", typ: .info)
        appState.gesamt      = appState.inboxDateien.count

        // Ollama starten falls nicht aktiv
        appState.statusAktualisieren(datei: "", schritt: "Ollama wird gestartet...")
        await ollamaStarten()

        // Modell-Verfügbarkeit einmalig prüfen
        guard await modellVerfuegbar() else {
            ollamaBeenden()
            onStop?()
            appState.laeuft = false
            return
        }

        // Phase 1: Alle Dateien analysieren (OCR + KI) – kein Fokus-Wechsel
        var ergebnisse: [AnalyseErgebnis] = []
        for url in appState.inboxDateien {
            if let ergebnis = await analysieren(url: url) {
                ergebnisse.append(ergebnis)
            }
            appState.verarbeitet += 1
        }

        // Ollama nach KI-Phase beenden – nicht mehr gebraucht
        ollamaBeenden()

        // Phase 2: Alle Bestätigungsfenster nacheinander zeigen
        appState.gesamt      = ergebnisse.count
        appState.verarbeitet = 0
        for ergebnis in ergebnisse {
            await bestaetigenUndArchivieren(ergebnis: ergebnis)
            appState.verarbeitet += 1
        }

        onStop?()
        DevLog.shared.aktiv = false
        DevLog.shared.log("■ Verarbeitung abgeschlossen", typ: .erfolg)
        appState.laeuft = false
        appState.inboxLaden()
    }

    // ------------------------------------------------------------
    // Ollama starten und auf Bereitschaft warten
    // ------------------------------------------------------------
    private func ollamaStarten() async {
        if await ollamaLaeuft() { return }

        // ollama serve als Hintergrundprozess – kein Fenster
        guard let pfad = toolPfad("ollama") else {
            await zeigeInfo("Ollama nicht gefunden.\n\nBitte installiere Ollama:\nhttps://ollama.com")
            return
        }

        let process = Process()
        process.executableURL  = URL(fileURLWithPath: pfad)
        process.arguments      = ["serve"]
        process.standardOutput = Pipe()
        process.standardError  = Pipe()
        try? process.run()
        ollamaProzess = process  // Handle merken

        // Bis zu 10 Sekunden warten
        for _ in 0..<20 {
            try? await Task.sleep(nanoseconds: 500_000_000)
            if await ollamaLaeuft() {
                ollamaVonUnsGestartet = true
                appState.statusAktualisieren(datei: "", schritt: "Ollama bereit ✅")
                return
            }
        }
        await zeigeInfo("Ollama konnte nicht gestartet werden.\n\nBitte starte Ollama manuell.")
    }

    // Ollama beenden – nur wenn wir es selbst gestartet haben
    func ollamaBeenden() {
        guard ollamaVonUnsGestartet else { return }
        // Direkt über Prozess-Handle beenden
        ollamaProzess?.terminate()
        ollamaProzess = nil
    }

    private func ollamaLaeuft() async -> Bool {
        guard let serverURL = URL(string: appState.konfig.ollamaURL) else { return false }
        return (try? await URLSession.shared.data(from: serverURL)) != nil
    }

    private func modellVerfuegbar() async -> Bool {
        guard let tagsURL = URL(string: "\(appState.konfig.ollamaURL)/api/tags") else { return true }
        guard let (data, _) = try? await URLSession.shared.data(from: tagsURL) else { return true }

        struct TagsAntwort: Codable { struct Modell: Codable { let name: String }; let models: [Modell] }
        guard let antwort = try? JSONDecoder().decode(TagsAntwort.self, from: data) else { return true }

        let modellName = appState.konfig.ollamaModell
        let basisName  = modellName.components(separatedBy: ":").first ?? modellName
        let verfuegbar = antwort.models.contains {
            $0.name == modellName ||
            $0.name.hasPrefix(modellName) ||
            $0.name.hasPrefix(basisName)
        }
        if !verfuegbar {
            await zeigeInfo("Das Modell '\(modellName)' ist nicht in Ollama verfügbar.\n\nBitte lade es herunter:\n\nollama pull \(modellName)")
        }
        return verfuegbar
    }

    // ------------------------------------------------------------
    // Phase 1: OCR + KI-Analyse – kein Fokus-Wechsel
    // ------------------------------------------------------------
    private func analysieren(url: URL) async -> AnalyseErgebnis? {
        let dateiname = url.lastPathComponent
        appState.statusAktualisieren(datei: dateiname, schritt: "Vorbereitung...")
        DevLog.shared.log("── \(dateiname)", typ: .info)

        // 1. Dubletten-Check
        guard let hash = sha256Hash(url: url) else { return nil }
        if istDublette(hash: hash) {
            await zeigeInfo("Dublette übersprungen:\n\(dateiname)")
            return nil
        }

        // 2. OCR + PDF/A
        // Strategie: erst --skip-text (schnell, schont bereits textualisierte PDFs),
        // dann Text prüfen – falls leer, nochmal mit --force-ocr (für reine Scan-Bilder)
        appState.statusAktualisieren(datei: dateiname, schritt: "OCR + PDF/A wird erstellt...")
        let ocrmypdf = toolPfad("ocrmypdf") ?? "/opt/homebrew/bin/ocrmypdf"
        let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString + ".pdf")

        var ocrErfolg = await prozessAusfuehren(
            pfad: ocrmypdf,
            argumente: ["-l", "deu", "--pdfa-image-compression", "jpeg",
                       "--optimize", "1", "--skip-text", "--quiet",
                       url.path, tmpURL.path]
        )

        // Schnellcheck: hat OCR Text produziert?
        var pdfURL = ocrErfolg && fm.fileExists(atPath: tmpURL.path) ? tmpURL : url
        DevLog.shared.log("OCR (--skip-text): \(ocrErfolg ? "ok" : "fehlgeschlagen, nutze Original")", typ: .ocr)
        let probeText = await textExtrahieren(pdfURL: pdfURL)

        if probeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Kein Text – PDF ist reines Bild (z.B. Kassenbon-Scan)
            // Nochmal mit --force-ocr
            appState.statusAktualisieren(datei: dateiname, schritt: "OCR (Bild-PDF wird erkannt)...")
            let tmp2URL = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent(UUID().uuidString + ".pdf")
            let ocrErfolg2 = await prozessAusfuehren(
                pfad: ocrmypdf,
                argumente: ["-l", "deu", "--pdfa-image-compression", "jpeg",
                           "--optimize", "1", "--force-ocr", "--quiet",
                           url.path, tmp2URL.path]
            )
            if ocrErfolg2 && fm.fileExists(atPath: tmp2URL.path) {
                try? fm.removeItem(at: tmpURL)
                pdfURL = tmp2URL
                ocrErfolg = true
                DevLog.shared.log("OCR --force-ocr: erfolgreich", typ: .ocr)
            } else {
                DevLog.shared.log("OCR --force-ocr: fehlgeschlagen", typ: .fehler)
            }
        }

        // 3. Text extrahieren (ggf. bereits als probeText vorhanden)
        appState.statusAktualisieren(datei: dateiname, schritt: "Text wird extrahiert...")
        let text = probeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? await textExtrahieren(pdfURL: pdfURL)
            : probeText
        let textVorschau = String(text.prefix(800)).replacingOccurrences(of: "\n", with: " ↵ ")
        DevLog.shared.log("Text (\(text.count) Zeichen): \(textVorschau)", typ: .text)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            await zeigeInfo("Kein Text erkannt in:\n\(dateiname)\n\nBitte mit mind. 300 dpi scannen.")
            try? fm.removeItem(at: tmpURL)
            return nil
        }

        // 4. KI-Analyse
        appState.statusAktualisieren(datei: dateiname, schritt: "KI analysiert Dokument...")
        guard var beleg = await ollamaAnalysieren(text: text, dateiname: dateiname) else {
            await zeigeInfo("KI-Analyse fehlgeschlagen für:\n\(dateiname)")
            try? fm.removeItem(at: tmpURL)
            return nil
        }
        beleg.hash = hash

        return AnalyseErgebnis(url: url, tmpURL: tmpURL, pdfURL: pdfURL, beleg: beleg)
    }

    // ------------------------------------------------------------
    // Phase 2: Bestätigung + Archivierung eines Ergebnisses
    // ------------------------------------------------------------
    private func bestaetigenUndArchivieren(ergebnis: AnalyseErgebnis) async {
        let dateiname = ergebnis.url.lastPathComponent

        // 5. Bestätigung via steuer_confirm
        appState.statusAktualisieren(datei: dateiname, schritt: "Warte auf Bestätigung...")
        guard let bestaetigterBeleg = await bestaetigungAnzeigen(
            beleg:     ergebnis.beleg,
            pdfPfad:   ergebnis.pdfURL.path,
            dateiname: dateiname
        ) else {
            try? fm.removeItem(at: ergebnis.tmpURL)
            return
        }

        // 6. Ordnungsnummer
        appState.statusAktualisieren(datei: dateiname, schritt: "Ordnungsnummer wird vergeben...")
        let ordnungsNr = naechsteOrdnungsnummer(
            kategorie: bestaetigterBeleg.kategorie,
            typ:       bestaetigterBeleg.typ,
            jahr:      bestaetigterBeleg.steuerjahr
        )
        var finalerBeleg        = bestaetigterBeleg
        finalerBeleg.ordnungsNr = ordnungsNr
        finalerBeleg.hash       = ergebnis.beleg.hash  // Hash aus Analyse-Phase übernehmen

        // 7. Metadaten einbetten
        appState.statusAktualisieren(datei: dateiname, schritt: "Metadaten werden eingebettet...")
        await metadatenEinbetten(beleg: finalerBeleg, pdfURL: ergebnis.pdfURL)

        // 8. Datei verschieben
        appState.statusAktualisieren(datei: dateiname, schritt: "Datei wird sortiert...")
        let zielURL = dateiVerschieben(beleg: finalerBeleg, pdfURL: ergebnis.pdfURL)
        guard let zielURL = zielURL else { return }
        finalerBeleg.archivPfad = zielURL.path

        // Original aus Inbox löschen wenn OCR eine neue tmp-Datei erzeugt hat
        if ergebnis.pdfURL != ergebnis.url {
            try? fm.removeItem(at: ergebnis.url)
        }
        try? fm.removeItem(at: ergebnis.tmpURL)

        // 9. CSV + Hash aktualisieren
        appState.statusAktualisieren(datei: dateiname, schritt: "CSV wird aktualisiert...")
        csvAktualisieren(beleg: finalerBeleg)
        hashSpeichern(hash: finalerBeleg.hash, archivPfad: zielURL.path)
    }

    // ------------------------------------------------------------
    // Prozess ausführen (ocrmypdf, exiftool etc.)
    // Verwendet terminationHandler statt waitUntilExit(), um den
    // Thread-Pool nicht zu blockieren.
    // ------------------------------------------------------------
    nonisolated private func prozessAusfuehren(pfad: String, argumente: [String]) async -> Bool {
        let pfadZuNutzen = toolPfad(URL(fileURLWithPath: pfad).lastPathComponent) ?? pfad
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let process = Process()
            process.executableURL  = URL(fileURLWithPath: pfadZuNutzen)
            process.arguments      = argumente
            process.standardOutput = Pipe()
            let errPipe = Pipe()
            process.standardError  = errPipe
            process.terminationHandler = { p in
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                if p.terminationStatus != 0, let errStr = String(data: errData, encoding: .utf8), !errStr.isEmpty {
                    let msg = "\(URL(fileURLWithPath: pfadZuNutzen).lastPathComponent) exit(\(p.terminationStatus)): \(errStr.prefix(300))"
                    print("⚠️ \(msg)")
                    Task { DevLog.shared.log(msg, typ: .fehler) }
                }
                continuation.resume(returning: p.terminationStatus == 0)
            }
            do {
                try process.run()
            } catch {
                print("⚠️ Fehler beim Starten von \(pfadZuNutzen): \(error)")
                continuation.resume(returning: false)
            }
        }
    }

    // ------------------------------------------------------------
    // Text aus PDF extrahieren
    // ------------------------------------------------------------
    private func textExtrahieren(pdfURL: URL) async -> String {
        let pfad = toolPfad("pdftotext") ?? "/opt/homebrew/bin/pdftotext"
        return await withCheckedContinuation { (continuation: CheckedContinuation<String, Never>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: pfad)
            process.arguments     = [pdfURL.path, "-"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError  = Pipe()
            process.terminationHandler = { _ in
                let data     = pipe.fileHandleForReading.readDataToEndOfFile()
                let text     = String(data: data, encoding: .utf8) ?? ""
                continuation.resume(returning: String(text.prefix(3000)))
            }
            do { try process.run() } catch {
                continuation.resume(returning: "")
            }
        }
    }

    // ------------------------------------------------------------
    // Ollama KI-Analyse
    // ------------------------------------------------------------
    private func ollamaAnalysieren(text: String, dateiname: String) async -> Beleg? {
        let konfig       = appState.konfig
        let person1      = konfig.person1
        let person2      = konfig.person2
        let fallbackJahr = Calendar.current.component(.year, from: Date())
        let kategorien   = konfig.kategorien.map { $0.name }.joined(separator: " / ")
        let personen     = konfig.modus == .paar ? "\(person1), \(person2) oder Gemeinsam" : person1

        let prompt = """
        Du bist ein Assistent für deutsche Steuererklärungen.
        Steuererklärung für: \(personen).

        Analysiere den Dokumententext und antworte NUR mit einem JSON-Objekt, ohne Erklärung, ohne Backticks, ohne Markdown.
        Achte auf korrekte deutsche Umlaute (ä, ö, ü, Ä, Ö, Ü, ß) in allen Feldern.

        Format:
        {"datum":"JJJJ-MM-TT","steuerjahr":"JJJJ","person":"...","belegtyp":"...","beschreibung":"...","betrag":"...","kategorie":"...","typ":"...","gemeinsam":"...","notiz":"..."}

        Regeln:
        - datum: Belegdatum JJJJ-MM-TT. Alle Formate umwandeln: "07.01.22"→"2022-01-07", "07.01.2022"→"2022-01-07". Fallback: \(fallbackJahr)-01-01
        - steuerjahr: steuerlich relevantes Jahr. Bei Lohnsteuerbescheinigung/Jahresabrechnung/Kapitalertragsbescheinigung: das Abrechnungsjahr (steht meist groß auf dem Dokument). Sonst: Jahr aus datum.
        - person: \(personen)
        - belegtyp: Wähle den passendsten:
            Kassenbon | Rechnung | Quittung | Lohnsteuerbescheinigung | Kapitalertragssteuerbescheinigung | Steuerbescheid | Bescheinigung | Kontoauszug | Vertrag | Sonstiges
        - beschreibung: Name des Ausstellers, max 30 Zeichen, Umlaute korrekt schreiben. Beispiele: "Rossmann", "Ärztekammer Bayern", "Finanzamt München", "Deutsche Bank AG"
        - betrag: NUR der finale GESAMTBETRAG als Zahl mit Punkt.
            Kassenbon: neben "Total", "Gesamt", "SUMME" oder "EUR [Betrag]"
            Lohnsteuerbescheinigung: Bruttolohn (Zeile 3)
            Kapitalertragsbescheinigung: Gesamtbetrag der Erträge
            Steuerbescheid: festgesetzte Steuer oder Erstattungsbetrag
            Sonst: der wichtigste Betrag des Dokuments
        - kategorie: eine von: \(kategorien)
            Lohnsteuerbescheinigung → Arbeitslohn
            Kapitalertragsbescheinigung → Kapitalerträge
            Drogerie/Apotheke → Krankheitskosten oder Haushaltskosten
            Arzt/Krankenhaus → Krankheitskosten
            Supermarkt/Lebensmittel → Haushaltskosten
            Handwerker/Baumarkt → Handwerkerleistungen
            Versicherung → Vorsorgeaufwendungen
            Spende → Spenden
        - typ:
            Lohnsteuerbescheinigung → Einnahme
            Kapitalertragsbescheinigung → Einnahme
            Steuerbescheid mit Erstattung → Einnahme
            Alles andere → Ausgabe
        - gemeinsam: ja oder nein
        - notiz: Steuerlicher Hinweis, max 60 Zeichen. Beispiele:
            "Bruttolohn lt. Lohnsteuerbescheinigung"
            "Kapitalerträge abgeltungssteuerpflichtig"
            "FFP2-Masken, ggf. Krankheitskosten absetzbar"
            "leer" wenn kein Hinweis nötig

        Dokumenttext:
        \(text)
        /no_think
        """

        guard let url = URL(string: "\(konfig.ollamaURL)/api/generate") else { return nil }

        struct OllamaRequest: Codable {
            let model:  String
            let prompt: String
            let stream: Bool
        }
        struct OllamaResponse: Codable {
            let response: String
        }

        guard let body = try? JSONEncoder().encode(
            OllamaRequest(model: konfig.ollamaModell, prompt: prompt, stream: false)
        ) else { return nil }

        var request        = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody   = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 300

        let data: Data
        do {
            let (responseData, httpResponse) = try await URLSession.shared.data(for: request)
            data = responseData
            if let http = httpResponse as? HTTPURLResponse, http.statusCode != 200 {
                let body = String(data: data, encoding: .utf8) ?? "(leer)"
                await zeigeInfo("Ollama HTTP-Fehler \(http.statusCode):\n\(body.prefix(200))")
                return nil
            }
        } catch {
            await zeigeInfo("Ollama nicht erreichbar:\n\(error.localizedDescription)")
            return nil
        }

        guard let antwort = try? JSONDecoder().decode(OllamaResponse.self, from: data) else {
            let raw = String(data: data, encoding: .utf8) ?? "(leer)"
            await zeigeInfo("Ollama Antwort konnte nicht gelesen werden:\n\(raw.prefix(300))")
            return nil
        }

        return jsonZuBeleg(json: antwort.response, dateiname: dateiname)
    }

    // ------------------------------------------------------------
    // JSON-Antwort in Beleg umwandeln
    // ------------------------------------------------------------
    private func jsonZuBeleg(json: String, dateiname: String) -> Beleg? {
        var bereinigt = json.trimmingCharacters(in: .whitespacesAndNewlines)

        // qwen3 gibt manchmal <think>...</think> vor dem JSON aus
        if let thinkEnd = bereinigt.range(of: "</think>") {
            bereinigt = String(bereinigt[thinkEnd.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        bereinigt = bereinigt.trimmingCharacters(in: CharacterSet(charactersIn: "`"))
        if bereinigt.hasPrefix("json") { bereinigt = String(bereinigt.dropFirst(4)) }

        // Nur JSON-Block extrahieren falls noch anderer Text vorhanden
        if let start = bereinigt.firstIndex(of: "{"),
           let end   = bereinigt.lastIndex(of: "}") {
            bereinigt = String(bereinigt[start...end])
        }

        guard let data = bereinigt.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        var beleg           = Beleg()
        beleg.datum         = dict["datum"]        as? String ?? ""
        beleg.steuerjahr    = dict["steuerjahr"]   as? String ?? String(beleg.datum.prefix(4))
        // Fallback: wenn steuerjahr leer, aus Datum ableiten
        if beleg.steuerjahr.isEmpty || beleg.steuerjahr.count != 4 {
            beleg.steuerjahr = String(beleg.datum.prefix(4))
        }
        beleg.person        = dict["person"]       as? String ?? "Gemeinsam"
        beleg.belegtyp      = dict["belegtyp"]     as? String ?? "Sonstiges"
        beleg.beschreibung  = dict["beschreibung"] as? String ?? "Unbekannt"
        // Betrag: Ollama gibt manchmal String ("9.95"), manchmal Zahl (9.95) zurück
        // Betrag: Komma→Punkt, €/EUR/Leerzeichen entfernen, dann parsen
        func parseBetrag(_ str: String) -> Double {
            let clean = str
                .replacingOccurrences(of: "€", with: "")
                .replacingOccurrences(of: "EUR", with: "")
                .replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: ",", with: ".")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return Double(clean) ?? 0.0
        }
        if let betragStr = dict["betrag"] as? String {
            beleg.betrag = parseBetrag(betragStr)
        } else if let betragNum = dict["betrag"] as? Double {
            beleg.betrag = betragNum
        } else if let betragInt = dict["betrag"] as? Int {
            beleg.betrag = Double(betragInt)
        }
        beleg.kategorie     = dict["kategorie"]    as? String ?? "Sonstiges"
        beleg.typ           = dict["typ"]          as? String ?? "Ausgabe"
        beleg.gemeinsam     = dict["gemeinsam"]    as? String ?? "nein"
        beleg.notiz         = dict["notiz"]        as? String ?? "leer"
        beleg.dateiname     = dateiname
        return beleg
    }

    // ------------------------------------------------------------
    // steuer_confirm aufrufen für Bestätigung
    // ------------------------------------------------------------
    private func bestaetigungAnzeigen(beleg: Beleg, pdfPfad: String, dateiname: String) async -> Beleg? {
        let konfig = appState.konfig

        // steuer_confirm aus dem App-Bundle laden
        // Falls nicht im Bundle, Fallback auf Home-Verzeichnis
        // steuer_confirm: erst im App-Bundle suchen (für verteilte App),
        // dann neben der App-Binary, dann im Home-Verzeichnis
        let confirmPfad: String
        let bundleDir = Bundle.main.bundlePath + "/Contents/MacOS/steuer_confirm"
        let nebenApp  = Bundle.main.bundlePath + "/../steuer_confirm"
        let homePfad  = NSHomeDirectory() + "/steuer_confirm"
        if FileManager.default.fileExists(atPath: bundleDir) {
            confirmPfad = bundleDir
        } else if FileManager.default.fileExists(atPath: nebenApp) {
            confirmPfad = nebenApp
        } else {
            confirmPfad = homePfad
        }
        let kategorienEinnahmen = konfig.kategorien
            .filter { $0.typ == .einnahme }
            .map { $0.name }
        let kategorienAusgaben = konfig.kategorien
            .filter { $0.typ == .ausgabe }
            .map { $0.name }
        let kategorienBeides = konfig.kategorien
            .filter { $0.typ == .beides }
            .map { $0.name }

        let dict: [String: Any] = [
            "datum":               beleg.datum,
            "steuerjahr":          beleg.steuerjahr,
            "person":              beleg.person,
            "belegtyp":            beleg.belegtyp,
            "beschreibung":        beleg.beschreibung,
            "betrag":              String(format: "%.2f", beleg.betrag),
            "kategorie":           beleg.kategorie,
            "typ":                 beleg.typ,
            "gemeinsam":           beleg.gemeinsam,
            "notiz":               beleg.notiz,
            "dateiname":           dateiname,
            "modus":               konfig.modus.rawValue,
            "person1":             konfig.person1,
            "person2":             konfig.person2,
            "pdfpfad":             pdfPfad,
            "kategorienEinnahmen": kategorienEinnahmen,
            "kategorienAusgaben":  kategorienAusgaben,
            "kategorienBeides":    kategorienBeides,
        ]

        guard let jsonData   = try? JSONSerialization.data(withJSONObject: dict),
              let jsonString = String(data: jsonData, encoding: .utf8)
        else { return nil }

        return await withCheckedContinuation { (continuation: CheckedContinuation<Beleg?, Never>) in
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: confirmPfad)
                process.arguments     = [jsonString]
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError  = Pipe()

                process.terminationHandler = { p in
                    if p.terminationStatus == 2 {
                        continuation.resume(returning: nil)
                        return
                    }
                    let data    = pipe.fileHandleForReading.readDataToEndOfFile()
                    let jsonStr = String(data: data, encoding: .utf8) ?? ""
                    Task { @MainActor in
                        var result = self.jsonZuBeleg(json: jsonStr, dateiname: dateiname)
                        // steuerjahr aus JSON-Antwort direkt lesen
                        if let data = jsonStr.data(using: .utf8),
                           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let sj = dict["steuerjahr"] as? String, !sj.isEmpty {
                            result?.steuerjahr = sj
                        }
                        continuation.resume(returning: result)
                    }
                }
                try? process.run()
            }
        }
    }

    // ------------------------------------------------------------
    // Ordnungsnummer aus CSV ableiten
    // Liest die Jahres-CSV und nimmt max(vorhandene Nummern) + 1
    // Die CSV ist die einzige Wahrheit – robust gegen gelöschte Dateien
    // ------------------------------------------------------------
    private func naechsteOrdnungsnummer(kategorie: String, typ: String, jahr: String) -> String {
        let kuerzel  = kuerzelFuerKategorie(kategorie: kategorie, typ: typ)
        let basis    = appState.konfig.archivPfad
        let csvPfad  = typ == "Einnahme"
            ? "\(basis)/\(jahr)/Einnahmen_\(jahr).csv"
            : "\(basis)/\(jahr)/Ausgaben_\(jahr).csv"
        let praefix  = "\(kuerzel)-"
        var maxNummer = 0

        if let inhalt = try? String(contentsOfFile: csvPfad) {
            for zeile in inhalt.components(separatedBy: "\n").dropFirst() {
                // Erste Spalte ist die Ordnungsnummer z.B. "HK-003"
                let ersteSpalte = zeile.components(separatedBy: ";").first ?? ""
                guard ersteSpalte.hasPrefix(praefix) else { continue }
                let numStr = String(ersteSpalte.dropFirst(praefix.count))
                if let num = Int(numStr), num > maxNummer {
                    maxNummer = num
                }
            }
        }

        return String(format: "%@-%03d", kuerzel, maxNummer + 1)
    }

    private func kuerzelFuerKategorie(kategorie: String, typ: String) -> String {
        return appState.konfig.kategorien
            .first { $0.name == kategorie }?.kuerzel ?? "SO"
    }

    // ------------------------------------------------------------
    // Metadaten einbetten (exiftool)
    // ------------------------------------------------------------
    private func metadatenEinbetten(beleg: Beleg, pdfURL: URL) async {
        let exiftoolPfad = toolPfad("exiftool") ?? "/opt/homebrew/bin/exiftool"

        _ = await prozessAusfuehren(pfad: exiftoolPfad, argumente: [
            "-Title=\(beleg.beschreibung)",
            "-Subject=\(beleg.kategorie)",
            "-Keywords=\(beleg.ordnungsNr), \(beleg.typ), \(String(beleg.datum.prefix(4))), \(beleg.person)",
            "-Author=\(beleg.person)",
            "-Comment=Nr: \(beleg.ordnungsNr) | \(String(format: "%.2f", beleg.betrag)) EUR | \(beleg.belegtyp) | \(beleg.notiz)",
            "-overwrite_original",
            pdfURL.path
        ])
    }

    // ------------------------------------------------------------
    // Datei verschieben und umbenennen
    // ------------------------------------------------------------
    private func dateiVerschieben(beleg: Beleg, pdfURL: URL) -> URL? {
        let basis = appState.konfig.archivPfad
        let jahr  = beleg.steuerjahr.isEmpty ? String(beleg.datum.prefix(4)) : beleg.steuerjahr
        let unterordner = beleg.typ == "Einnahme"
            ? "Einnahmen/\(beleg.kategorie)"
            : "Ausgaben/\(beleg.kategorie)"
        let zielOrdner = "\(basis)/\(jahr)/\(unterordner)"

        do {
            try fm.createDirectory(atPath: zielOrdner, withIntermediateDirectories: true)
        } catch {
            appState.fehler = "Ordner konnte nicht angelegt werden: \(zielOrdner)\n\(error.localizedDescription)"
            return nil
        }

        let beschreibungFuerName = beschreibungFuerDateiname(beleg.beschreibung)
        let neuerName = "\(beleg.ordnungsNr)_\(beleg.datum)_\(beschreibungFuerName)_\(String(format: "%.2f", beleg.betrag))EUR.pdf"
        let zielURL   = URL(fileURLWithPath: "\(zielOrdner)/\(neuerName)")

        do {
            try fm.moveItem(at: pdfURL, to: zielURL)
            return zielURL
        } catch {
            appState.fehler = "Datei konnte nicht verschoben werden:\n\(pdfURL.lastPathComponent)\n\(error.localizedDescription)"
            return nil
        }
    }

    // ------------------------------------------------------------
    // CSV aktualisieren
    // ------------------------------------------------------------
    private func csvAktualisieren(beleg: Beleg) {
        let basis  = appState.konfig.archivPfad
        let jahr   = beleg.steuerjahr.isEmpty ? String(beleg.datum.prefix(4)) : beleg.steuerjahr
        let betragFormatiert = String(format: "%.2f", beleg.betrag).replacingOccurrences(of: ".", with: ",")
        let csvPfad: String
        let header:  String
        let zeile:   String
        let datname = URL(fileURLWithPath: beleg.archivPfad).lastPathComponent

        if beleg.typ == "Einnahme" {
            csvPfad = "\(basis)/\(jahr)/Einnahmen_\(jahr).csv"
            header  = "Nr;Datum;Person;Belegtyp;Beschreibung;Betrag in EUR;Kategorie;Notiz;Dateiname"
            zeile   = "\(beleg.ordnungsNr);\(datumAnzeige(beleg.datum));\(beleg.person);\(beleg.belegtyp);\(beleg.beschreibung);\(betragFormatiert);\(beleg.kategorie);\(beleg.notiz);\(datname)"
        } else {
            csvPfad = "\(basis)/\(jahr)/Ausgaben_\(jahr).csv"
            header  = "Nr;Datum;Person;Belegtyp;Beschreibung;Betrag in EUR;Kategorie;Gemeinsam;Notiz;Dateiname"
            zeile   = "\(beleg.ordnungsNr);\(datumAnzeige(beleg.datum));\(beleg.person);\(beleg.belegtyp);\(beleg.beschreibung);\(betragFormatiert);\(beleg.kategorie);\(beleg.gemeinsam);\(beleg.notiz);\(datname)"
        }

        if !fm.fileExists(atPath: csvPfad) {
            do {
                try (header + "\n").write(toFile: csvPfad, atomically: true, encoding: .utf8)
            } catch {
                appState.fehler = "CSV konnte nicht erstellt werden:\n\(error.localizedDescription)"
                return
            }
        }
        if let handle = FileHandle(forWritingAtPath: csvPfad) {
            handle.seekToEndOfFile()
            if let data = (zeile + "\n").data(using: .utf8) { handle.write(data) }
            handle.closeFile()
        } else {
            appState.fehler = "CSV konnte nicht geöffnet werden:\n\(csvPfad)"
        }
    }

    // ------------------------------------------------------------
    // SHA-256-Hash berechnen (erste 64KB)
    //
    // Warum SHA-256 statt MD5?
    //   MD5 gilt als kollisionsanfällig – zwei verschiedene Dateien
    //   könnten theoretisch denselben Hash erzeugen. SHA-256 ist der
    //   aktuelle kryptographische Standard und in CryptoKit bereits
    //   enthalten, ohne zusätzliche Abhängigkeiten.
    //
    // Warum nur die ersten 64KB?
    //   Ein Scan-PDF kann leicht 20–100 MB groß sein. Den kompletten
    //   Dateiinhalt in den Speicher zu laden, nur um einen Hash zu
    //   berechnen, ist unnötig. Die ersten 64KB enthalten Header,
    //   Metadaten und den Beginn des ersten Inhalts – das reicht
    //   sicher aus um eine Datei eindeutig zu identifizieren.
    // ------------------------------------------------------------
    private func sha256Hash(url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let chunk  = handle.readData(ofLength: 65_536)  // 64 KB
        let digest = SHA256.hash(data: chunk)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func istDublette(hash: String) -> Bool {
        let pfad = appState.konfig.archivPfad + "/.verarbeitete_belege"
        guard fm.fileExists(atPath: pfad),
              let inhalt = try? String(contentsOfFile: pfad)
        else { return false }

        // Format pro Zeile: sha256hex<TAB>/absoluter/pfad/zur/datei
        // TAB als Trenner – sicher gegen Leerzeichen und Sonderzeichen im Pfad.
        // Nur als Dublette zählen wenn die archivierte Datei noch existiert.
        for zeile in inhalt.components(separatedBy: "\n") {
            let teile = zeile.components(separatedBy: "\t")
            guard teile.count >= 2 else { continue }
            let gespeicherterHash = teile[0]
            let archivPfad        = teile[1]
            if gespeicherterHash == hash && fm.fileExists(atPath: archivPfad) {
                return true
            }
        }
        return false
    }

    private func hashSpeichern(hash: String, archivPfad: String) {
        let pfad    = appState.konfig.archivPfad + "/.verarbeitete_belege"
        let eintrag = "\(hash)\t\(archivPfad)\n"  // TAB als Trenner
        if let handle = FileHandle(forWritingAtPath: pfad) {
            handle.seekToEndOfFile()
            if let data = eintrag.data(using: .utf8) { handle.write(data) }
            handle.closeFile()
        } else {
            try? eintrag.write(toFile: pfad, atomically: true, encoding: .utf8)
        }
    }

    // ------------------------------------------------------------
    // Info-Popup
    // ------------------------------------------------------------
    private func zeigeInfo(_ text: String) async {
        await MainActor.run {
            let alert             = NSAlert()
            alert.messageText     = "Stashfix"
            alert.informativeText = text
            alert.runModal()
        }
    }
}
