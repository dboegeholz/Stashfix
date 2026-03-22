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

    private let appState: AppState
    private let fm = FileManager.default

    // FIX Warn#1: Ollama-Lifecycle-Zustand über Enum absichern – verhindert Doppelstart
    private enum OllamaStatus { case unbekannt, gestartetVonUns, externLaufend }
    private var ollamaStatus: OllamaStatus = .unbekannt
    private var ollamaProzess: Process? = nil

    // FIX Arch#1: gecachte Tool-Pfade – Dateisystem nur einmal pro Session traversieren
    private var toolPfadCache: [String: String] = [:]

    init(appState: AppState) {
        self.appState = appState
    }

    // ------------------------------------------------------------
    // Datum-Formatierung
    // Intern immer JJJJ-MM-TT (ISO), Anzeige/CSV als TT.MM.JJJJ
    // ------------------------------------------------------------
    private func datumAnzeige(_ iso: String) -> String {
        let teile = iso.split(separator: "-")
        guard teile.count == 3 else { return iso }
        return "\(teile[2]).\(teile[1]).\(teile[0])"
    }

    private func beschreibungFuerDateiname(_ text: String) -> String {
        let result = text
            .replacingOccurrences(of: "ä", with: "ae")
            .replacingOccurrences(of: "ö", with: "oe")
            .replacingOccurrences(of: "ü", with: "ue")
            .replacingOccurrences(of: "Ä", with: "Ae")
            .replacingOccurrences(of: "Ö", with: "Oe")
            .replacingOccurrences(of: "Ü", with: "Ue")
            .replacingOccurrences(of: "ß", with: "ss")
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
        let url:    URL
        let tmpURL: URL
        let pdfURL: URL
        let beleg:  Beleg
    }

    // FIX Bug#1: nonisolated-Variante für Prozessaufruf-Kontext
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

    // FIX Bug#1 + Arch#1: Gecachte Variante auf MainActor – löst Pfad einmalig auf
    private func toolPfadCached(_ befehl: String) -> String? {
        if let cached = toolPfadCache[befehl] { return cached }
        if let pfad = toolPfad(befehl) {
            toolPfadCache[befehl] = pfad
            return pfad
        }
        return nil
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

        appState.statusAktualisieren(datei: "", schritt: "Ollama wird gestartet...")
        await ollamaStarten()

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
    // FIX Warn#1: ollamaStatus-Enum verhindert Race Condition / Doppelstart
    // ------------------------------------------------------------
    private func ollamaStarten() async {
        if await ollamaLaeuft() {
            ollamaStatus = .externLaufend
            return
        }
        // Status sofort setzen – verhindert Doppelstart bei erneutem Aufruf
        guard ollamaStatus == .unbekannt else { return }
        ollamaStatus = .gestartetVonUns

        guard let pfad = toolPfadCached("ollama") else {
            await zeigeInfo("Ollama nicht gefunden.\n\nBitte installiere Ollama:\nhttps://ollama.com")
            ollamaStatus = .unbekannt
            return
        }

        let process = Process()
        process.executableURL  = URL(fileURLWithPath: pfad)
        process.arguments      = ["serve"]
        process.standardOutput = Pipe()
        process.standardError  = Pipe()
        try? process.run()
        ollamaProzess = process

        // Bis zu 10 Sekunden warten
        for _ in 0..<20 {
            try? await Task.sleep(nanoseconds: 500_000_000)
            if await ollamaLaeuft() {
                appState.statusAktualisieren(datei: "", schritt: "Ollama bereit ✅")
                return
            }
        }
        await zeigeInfo("Ollama konnte nicht gestartet werden.\n\nBitte starte Ollama manuell.")
    }

    // Ollama beenden – nur wenn wir es selbst gestartet haben
    func ollamaBeenden() {
        guard ollamaStatus == .gestartetVonUns else { return }
        ollamaProzess?.terminate()
        ollamaProzess = nil
        ollamaStatus  = .unbekannt
    }

    private func ollamaLaeuft() async -> Bool {
        guard let serverURL = URL(string: appState.konfig.ollamaURL) else { return false }
        return (try? await URLSession.shared.data(from: serverURL)) != nil
    }

    private func modellVerfuegbar() async -> Bool {
        guard let tagsURL = URL(string: "\(appState.konfig.ollamaURL)/api/tags") else { return true }
        guard let (data, _) = try? await URLSession.shared.data(from: tagsURL) else { return true }
        guard let antwort = try? JSONDecoder().decode(OllamaTagsAntwort.self, from: data) else { return true }

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
    // Phase 1: OCR + KI-Analyse
    // FIX Bug#2: probeText wird direkt weiterverwendet – kein zweiter pdftotext-Aufruf
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
        appState.statusAktualisieren(datei: dateiname, schritt: "OCR + PDF/A wird erstellt...")

        // FIX Bug#1: Pfad einmalig auflösen, direkt übergeben
        let ocrmypdf = toolPfadCached("ocrmypdf") ?? "/opt/homebrew/bin/ocrmypdf"
        let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString + ".pdf")

        let ocrErfolg = await prozessAusfuehren(
            pfad: ocrmypdf,
            argumente: ["-l", "deu", "--pdfa-image-compression", "jpeg",
                       "--optimize", "1", "--skip-text", "--quiet",
                       url.path, tmpURL.path]
        )

        var pdfURL = ocrErfolg && fm.fileExists(atPath: tmpURL.path) ? tmpURL : url
        DevLog.shared.log("OCR (--skip-text): \(ocrErfolg ? "ok" : "fehlgeschlagen, nutze Original")", typ: .ocr)

        // FIX Bug#2: Text EINMAL extrahieren und für alle weiteren Schritte nutzen
        appState.statusAktualisieren(datei: dateiname, schritt: "Text wird extrahiert...")
        var extrahierterText = await textExtrahieren(pdfURL: pdfURL)

        if extrahierterText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Kein Text – PDF ist reines Bild → --force-ocr
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
                DevLog.shared.log("OCR --force-ocr: erfolgreich", typ: .ocr)
                // Nach force-ocr Text neu extrahieren (einmalig)
                extrahierterText = await textExtrahieren(pdfURL: pdfURL)
            } else {
                DevLog.shared.log("OCR --force-ocr: fehlgeschlagen", typ: .fehler)
            }
        }

        let textVorschau = extrahierterText.replacingOccurrences(of: "\n", with: " ↵ ")
        DevLog.shared.log("Text (\(extrahierterText.count) Zeichen): \(textVorschau)", typ: .text)

        guard !extrahierterText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            await zeigeInfo("Kein Text erkannt in:\n\(dateiname)\n\nBitte mit mind. 300 dpi scannen.")
            try? fm.removeItem(at: tmpURL)
            return nil
        }

        // 4. KI-Analyse
        appState.statusAktualisieren(datei: dateiname, schritt: "KI analysiert Dokument...")
        var beleg: Beleg
        if let analysierterBeleg = await ollamaAnalysieren(text: extrahierterText, dateiname: dateiname) {
            beleg = analysierterBeleg
        } else {
            // KI-Analyse fehlgeschlagen – leeren Beleg zur manuellen Bearbeitung anbieten
            DevLog.shared.log("KI-Analyse fehlgeschlagen – öffne Bestätigungsfenster zur manuellen Eingabe", typ: .fehler)
            let heute = ISO8601DateFormatter().string(from: Date()).prefix(10)
            let fallbackJahr = String(Calendar.current.component(.year, from: Date()))
            var leerBeleg = Beleg()
            leerBeleg.datum        = String(heute)
            leerBeleg.steuerjahr   = fallbackJahr
            leerBeleg.person       = appState.konfig.person1
            leerBeleg.belegtyp     = "Sonstiges"
            leerBeleg.beschreibung = "Manuell prüfen"
            leerBeleg.betrag       = 0.0
            leerBeleg.kategorie    = appState.konfig.kategorien.first?.name ?? "Sonstiges"
            leerBeleg.typ          = "Ausgabe"
            leerBeleg.gemeinsam    = "nein"
            leerBeleg.notiz        = "KI-Analyse fehlgeschlagen – bitte alle Felder prüfen"
            leerBeleg.steuerrelevant = true
            beleg = leerBeleg
        }
        beleg.hash = hash
        return AnalyseErgebnis(url: url, tmpURL: tmpURL, pdfURL: pdfURL, beleg: beleg)
    }

    // ------------------------------------------------------------
    // Phase 2: Bestätigung + Archivierung eines Ergebnisses
    // ------------------------------------------------------------
    private func bestaetigenUndArchivieren(ergebnis: AnalyseErgebnis) async {
        let dateiname = ergebnis.url.lastPathComponent

        appState.statusAktualisieren(datei: dateiname, schritt: "Warte auf Bestätigung...")
        guard let bestaetigterBeleg = await bestaetigungAnzeigen(
            beleg:     ergebnis.beleg,
            pdfPfad:   ergebnis.pdfURL.path,
            dateiname: dateiname
        ) else {
            try? fm.removeItem(at: ergebnis.tmpURL)
            return
        }

        appState.statusAktualisieren(datei: dateiname, schritt: "Ordnungsnummer wird vergeben...")
        let archivJahr = bestaetigterBeleg.steuerrelevant && !bestaetigterBeleg.steuerjahr.isEmpty
            ? bestaetigterBeleg.steuerjahr
            : String(bestaetigterBeleg.datum.prefix(4))
        let ordnungsNr = naechsteOrdnungsnummer(
            kategorie:      bestaetigterBeleg.kategorie,
            typ:            bestaetigterBeleg.typ,
            jahr:           archivJahr,
            steuerrelevant: bestaetigterBeleg.steuerrelevant
        )
        var finalerBeleg        = bestaetigterBeleg
        finalerBeleg.ordnungsNr = ordnungsNr
        finalerBeleg.hash       = ergebnis.beleg.hash

        appState.statusAktualisieren(datei: dateiname, schritt: "Metadaten werden eingebettet...")
        await metadatenEinbetten(beleg: finalerBeleg, pdfURL: ergebnis.pdfURL)

        appState.statusAktualisieren(datei: dateiname, schritt: "Datei wird sortiert...")
        let zielURL = dateiVerschieben(beleg: finalerBeleg, pdfURL: ergebnis.pdfURL)
        guard let zielURL = zielURL else { return }
        finalerBeleg.archivPfad = zielURL.path

        if ergebnis.pdfURL != ergebnis.url {
            try? fm.removeItem(at: ergebnis.url)
        }
        try? fm.removeItem(at: ergebnis.tmpURL)

        appState.statusAktualisieren(datei: dateiname, schritt: "CSV wird aktualisiert...")
        csvAktualisieren(beleg: finalerBeleg)
        hashSpeichern(hash: finalerBeleg.hash, archivPfad: zielURL.path)
    }

    // ------------------------------------------------------------
    // Prozess ausführen (ocrmypdf, exiftool etc.)
    // FIX Bug#1: Übergebenen Pfad direkt nutzen – kein zweites toolPfad() intern
    // ------------------------------------------------------------
    nonisolated private func prozessAusfuehren(pfad: String, argumente: [String]) async -> Bool {
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let process = Process()
            process.executableURL  = URL(fileURLWithPath: pfad)
            process.arguments      = argumente
            var env = ProcessInfo.processInfo.environment
            let extraPfade = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
            env["PATH"] = extraPfade + ":" + (env["PATH"] ?? "")
            process.environment    = env
            process.standardOutput = Pipe()
            let errPipe = Pipe()
            process.standardError  = errPipe
            process.terminationHandler = { p in
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                if p.terminationStatus != 0,
                   let errStr = String(data: errData, encoding: .utf8),
                   !errStr.isEmpty {
                    let msg = "\(URL(fileURLWithPath: pfad).lastPathComponent) exit(\(p.terminationStatus)): \(errStr.prefix(300))"
                    print("⚠️ \(msg)")
                    Task { await DevLog.shared.log(msg, typ: .fehler) }
                }
                continuation.resume(returning: p.terminationStatus == 0)
            }
            do {
                try process.run()
            } catch {
                print("⚠️ Fehler beim Starten von \(pfad): \(error)")
                continuation.resume(returning: false)
            }
        }
    }

    // ------------------------------------------------------------
    // Text aus PDF extrahieren
    // FIX Bug#1: Gecachten Pfad nutzen
    // FIX Encoding: -enc UTF-8 erzwingt UTF-8-Ausgabe von pdftotext.
    //   Fallback: wenn Swift das Ergebnis nicht als UTF-8 parsen kann
    //   (z.B. ältere PDFs mit Latin-1-Encoding), nochmal ohne Flag
    //   und dann mit isoLatin1 dekodieren – verhindert MÃ¼nsterland-Artefakte.
    // ------------------------------------------------------------
    private func textExtrahieren(pdfURL: URL) async -> String {
        guard let pfad = toolPfadCached("pdftotext") else { return "" }

        // Erster Versuch: mit -enc UTF-8
        // Limit 8000 Zeichen – mehrseitige Bankbescheinigungen brauchen mehr als 3000
        let rohdaten = await pdftotextAusfuehren(pfad: pfad, pdfURL: pdfURL, argumente: ["-enc", "UTF-8", pdfURL.path, "-"])
        if let text = String(data: rohdaten, encoding: .utf8), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return String(text.prefix(8000))
        }

        // Fallback: ohne Encoding-Flag, Latin-1 dekodieren
        let rohdatenFallback = await pdftotextAusfuehren(pfad: pfad, pdfURL: pdfURL, argumente: [pdfURL.path, "-"])
        let text = String(data: rohdatenFallback, encoding: .isoLatin1)
            ?? String(data: rohdatenFallback, encoding: .utf8)
            ?? ""
        return String(text.prefix(8000))
    }

    nonisolated private func pdftotextAusfuehren(pfad: String, pdfURL: URL, argumente: [String]) async -> Data {
        return await withCheckedContinuation { (continuation: CheckedContinuation<Data, Never>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: pfad)
            process.arguments     = argumente
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError  = Pipe()
            process.terminationHandler = { _ in
                continuation.resume(returning: pipe.fileHandleForReading.readDataToEndOfFile())
            }
            do { try process.run() } catch {
                continuation.resume(returning: Data())
            }
        }
    }

    // ------------------------------------------------------------
    // Smart-Extrakt für lange Dokumente (> 1500 Zeichen)
    // Statt blind die ersten N Zeichen zu nehmen: Briefkopf +
    // Umgebung relevanter Schlüsselwörter extrahieren.
    // So landen Beträge auf der letzten Seite trotzdem im Kontext.
    // ------------------------------------------------------------
    private func textFuerKI(_ volltext: String) -> String {
        // Ab 800 Zeichen Smart-Extrakt – greift auch bei kürzeren mehrseitigen Dokumenten
        guard volltext.count > 800 else { return volltext }

        let schluesselwoerter = [
            "Gesamtbetrag", "Nachzahlung", "Guthaben", "Rechnungsbetrag",
            "Endbetrag", "Summe", "Total", "fällig", "zahlbar",
            "Betrag", "EUR", "€", "Brutto", "Netto",
            "Datum", "Rechnungsdatum", "Abrechnungszeitraum", "vom",
            "Zeile 3", "Zeile 7", "Zeile 9", "Bruttoarbeitslohn", "Kapitalertrag",
            "Kapitalertragsteuer", "Solidaritätszuschlag", "Kirchensteuer",
            "Jahressteuerbescheinigung", "Steuerbescheinigung",
            "Kalenderjahr", "Abrechnungsjahr", "Veranlagungsjahr",
            // Empfänger-Erkennung
            "Kontoinhaber", "Depot", "Kundennummer", "Kunde", "Auftraggeber",
            "Vertragspartner", "Versicherungsnehmer", "Antragsteller",
            "GmbH", "AG", "Bank", "Versicherung", "Institut"
        ]

        let zeilen = volltext.components(separatedBy: "\n")
        var trefferIndizes = IndexSet()

        for (i, zeile) in zeilen.enumerated() {
            let hatSchluessel = schluesselwoerter.contains {
                zeile.localizedCaseInsensitiveContains($0)
            }
            if hatSchluessel {
                let von = max(0, i - 2)
                let bis = min(zeilen.count - 1, i + 2)
                (von...bis).forEach { trefferIndizes.insert($0) }
            }
        }

        // Erste 10 Zeilen (Briefkopf) + letzte 15 Zeilen (Footer mit Institutsname)
        (0..<min(10, zeilen.count)).forEach { trefferIndizes.insert($0) }
        let footerStart = max(0, zeilen.count - 15)
        (footerStart..<zeilen.count).forEach { trefferIndizes.insert($0) }

        let extrakt = trefferIndizes.sorted()
            .map { zeilen[$0] }
            .joined(separator: "\n")

        let ergebnis = extrakt.isEmpty ? String(volltext.prefix(4000)) : String(extrakt.prefix(4000))
        DevLog.shared.log("Smart-Extrakt: \(volltext.count) → \(ergebnis.count) Zeichen", typ: .info)
        return ergebnis
    }

    // ------------------------------------------------------------
    // Ollama KI-Analyse
    // FIX Perf#1: stream:true – Tokens inkrementell lesen
    // FIX Perf#2: Erst 800-Zeichen-Kontext; Fallback auf Smart-Extrakt
    // FIX Perf#3: Timeout auf 90 Sekunden reduziert
    // FIX Arch#3: /no_think nur bei Qwen-Modellen
    // FIX Arch#1: Retry bei Netzwerkfehler (1 Wiederholung)
    // ------------------------------------------------------------
    private func ollamaAnalysieren(text: String, dateiname: String) async -> Beleg? {
        // Kurze Dokumente: erst 800-Zeichen-Kontext versuchen
        if text.count <= 1500 {
            let kurztext = String(text.prefix(800))
            if let beleg = await ollamaRequest(text: kurztext, dateiname: dateiname) {
                let fallbackJahr = "\(Calendar.current.component(.year, from: Date()))-01-01"
                if beleg.betrag > 0 && !beleg.datum.isEmpty && beleg.datum != fallbackJahr {
                    return beleg
                }
                DevLog.shared.log("Kurzkontext unzureichend (\(kurztext.count) Z.), versuche Smart-Extrakt…", typ: .info)
            }
        } else {
            DevLog.shared.log("Langes Dokument (\(text.count) Z.) – überspringe Kurzkontext, direkt Smart-Extrakt", typ: .info)
        }
        // Fallback / lange Dokumente: Smart-Extrakt
        let extrakt = textFuerKI(text)
        return await ollamaRequest(text: extrakt, dateiname: dateiname)
    }

    private func ollamaRequest(text: String, dateiname: String, versuch: Int = 1) async -> Beleg? {
        let konfig       = appState.konfig
        let fallbackJahr = Calendar.current.component(.year, from: Date())
        let kategorien   = konfig.kategorien.map { $0.name }.joined(separator: " / ")
        let personen     = konfig.modus == .paar
            ? "\(konfig.person1), \(konfig.person2) oder Gemeinsam"
            : konfig.person1

        // FIX Arch#3: /no_think nur bei Qwen-Modellen anhängen
        let istQwen = konfig.ollamaModell.lowercased().hasPrefix("qwen")
        var prompt = konfig.ollamaPrompt
            .replacingOccurrences(of: "{{personen}}",   with: personen)
            .replacingOccurrences(of: "{{kategorien}}", with: kategorien)
            .replacingOccurrences(of: "{{jahr}}",       with: String(fallbackJahr))
            .replacingOccurrences(of: "{{text}}",       with: text)
        if !istQwen {
            prompt = prompt
                .replacingOccurrences(of: "\n/no_think", with: "")
                .replacingOccurrences(of: "/no_think",   with: "")
        }

        DevLog.shared.log("Ollama → Modell: \(konfig.ollamaModell), \(text.count) Z. (Versuch \(versuch))", typ: .ollama)
        guard let url = URL(string: "\(konfig.ollamaURL)/api/generate") else { return nil }

        // Adaptiver Thinking-Modus (nur Qwen3):
        // Kurze Dokumente (≤ 1500 Z.): think:false – schnell, ausreichend für einfache Belege
        // Lange Dokumente (> 1500 Z.):  Thinking an  – zuverlässiger bei komplexen Dokumenten
        // Nicht-Qwen-Modelle: think-Parameter wird nicht gesendet
        let brauchtThinking = istQwen && text.count > 1500
        DevLog.shared.log("Thinking-Modus: \(brauchtThinking ? "an" : "aus") (\(text.count) Z.)", typ: .info)

        struct OllamaRequestMitThinking: Codable {
            let model: String; let prompt: String; let stream: Bool
            let think: Bool
            let options: Options
            struct Options: Codable { let num_predict: Int }
        }
        struct OllamaRequestOhneThinking: Codable {
            let model: String; let prompt: String; let stream: Bool
            let options: Options
            struct Options: Codable { let num_predict: Int }
        }
        let maxTokens = brauchtThinking ? 4096 : 600
        let body: Data?
        if istQwen {
            body = try? JSONEncoder().encode(
                OllamaRequestMitThinking(model: konfig.ollamaModell, prompt: prompt, stream: true,
                                         think: brauchtThinking,
                                         options: .init(num_predict: maxTokens))
            )
        } else {
            body = try? JSONEncoder().encode(
                OllamaRequestOhneThinking(model: konfig.ollamaModell, prompt: prompt, stream: true,
                                          options: .init(num_predict: maxTokens))
            )
        }
        guard let body = body else { return nil }

        var request        = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody   = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Timeout adaptiv: mit Thinking mehr Zeit einplanen
        request.timeoutInterval = brauchtThinking ? 120 : 60

        do {
            // FIX Perf#1: Streaming-Leser
            let vollstaendig = try await ollamaStreamLesen(request: request)
            DevLog.shared.log("Ollama ← (\(vollstaendig.count) Zeichen): \(vollstaendig.prefix(500))", typ: .ollama)
            DevLog.shared.log("Ollama ← Ende: …\(vollstaendig.suffix(200))", typ: .ollama)
            if vollstaendig.isEmpty {
                DevLog.shared.log("⚠️ Ollama Antwort leer – stream hat keine Chunks geliefert", typ: .fehler)
                return nil
            }
            if let beleg = jsonZuBeleg(json: vollstaendig, dateiname: dateiname) {
                return beleg
            } else {
                DevLog.shared.log("⚠️ JSON-Parsing fehlgeschlagen. Rohtext: \(vollstaendig.prefix(300))", typ: .fehler)
                return nil
            }
        } catch let error as URLError where versuch < 2 {
            // FIX Arch#1: Ein Retry bei Netzwerkfehler
            DevLog.shared.log("Netzwerkfehler (V\(versuch)): \(error.localizedDescription) – retry…", typ: .fehler)
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            return await ollamaRequest(text: text, dateiname: dateiname, versuch: versuch + 1)
        } catch {
            await zeigeInfo("Ollama nicht erreichbar:\n\(error.localizedDescription)")
            return nil
        }
    }

    // FIX Perf#1: NDJSON-Streaming – sammelt alle response-Chunks
    // FIX Encoding: Bytes als Data puffern, nicht als einzelne UnicodeScalars lesen –
    //   verhindert dass multi-byte UTF-8-Zeichen (ü = 0xC3 0xBC) zerrissen werden.
    private func ollamaStreamLesen(request: URLRequest) async throws -> String {
        // thinking: Qwen3 liefert im Thinking-Modus Chunks mit leerem response
        // und befülltem thinking-Feld – diese ignorieren, aber zählen
        struct OllamaChunk: Decodable {
            let response: String
            let thinking: String?
            let done: Bool
        }

        let (asyncBytes, httpResponse) = try await URLSession.shared.bytes(for: request)

        if let http = httpResponse as? HTTPURLResponse, http.statusCode != 200 {
            var fehlerText = ""
            for try await byte in asyncBytes {
                fehlerText.append(Character(UnicodeScalar(byte)))
                if fehlerText.count > 300 { break }
            }
            await zeigeInfo("Ollama HTTP-Fehler \(http.statusCode):\n\(fehlerText)")
            throw URLError(.badServerResponse)
        }

        var vollstaendig = ""
        var zeilenPuffer = Data()
        var chunkAnzahl  = 0

        for try await byte in asyncBytes {
            if byte == UInt8(ascii: "\n") {
                // Direkt aus Data dekodieren – kein String-Roundtrip, kein Encoding-Verlust
                if !zeilenPuffer.isEmpty,
                   let chunk = try? JSONDecoder().decode(OllamaChunk.self, from: zeilenPuffer) {
                    vollstaendig += chunk.response
                    chunkAnzahl  += 1
                    if chunk.done {
                        Task { DevLog.shared.log("Stream beendet nach \(chunkAnzahl) Chunks", typ: .info) }
                        break
                    }
                }
                zeilenPuffer = Data()
            } else {
                zeilenPuffer.append(byte)
            }
        }
        if chunkAnzahl == 0 {
            Task { DevLog.shared.log("⚠️ Stream: 0 Chunks empfangen – Ollama hat nichts gesendet", typ: .fehler) }
        }
        return vollstaendig
    }

    // ------------------------------------------------------------
    // Person-Zuordnung: token-basierter Abgleich mit konfigurierten Namen
    // Fängt Varianten wie zweite Vornamen, Tippfehler im Dokument ab.
    // Gibt Person1, Person2 oder "Gemeinsam" zurück.
    // ------------------------------------------------------------
    private func personZuordnen(_ name: String) -> String {
        let konfig = appState.konfig
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return "Gemeinsam" }

        let nameLower  = name.lowercased()
        let p1Token    = konfig.person1.lowercased().components(separatedBy: " ").filter { !$0.isEmpty }
        let p2Token    = konfig.modus == .paar
            ? konfig.person2.lowercased().components(separatedBy: " ").filter { !$0.isEmpty }
            : []
        let nameToken  = nameLower.components(separatedBy: " ").filter { !$0.isEmpty }

        let p1Treffer  = nameToken.filter { p1Token.contains($0) }.count
        let p2Treffer  = nameToken.filter { p2Token.contains($0) }.count

        DevLog.shared.log("Person-Zuordnung: '\(name)' → P1:\(p1Treffer) P2:\(p2Treffer)", typ: .info)

        if p1Treffer > 0 && p1Treffer >= p2Treffer { return konfig.person1 }
        if p2Treffer > 0 { return konfig.person2 }
        return "Gemeinsam"
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

        if let start = bereinigt.firstIndex(of: "{"),
           let end   = bereinigt.lastIndex(of: "}") {
            bereinigt = String(bereinigt[start...end])
        }

        guard let data = bereinigt.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        var beleg           = Beleg()
        beleg.datum         = dict["datum"]        as? String ?? ""

        // FIX: steuerjahr kann als String ("2024") oder Int (2024) kommen
        if let jahrStr = dict["steuerjahr"] as? String, jahrStr.count == 4 {
            beleg.steuerjahr = jahrStr
        } else if let jahrInt = dict["steuerjahr"] as? Int {
            beleg.steuerjahr = String(jahrInt)
        } else {
            beleg.steuerjahr = String(beleg.datum.prefix(4))
        }
        if beleg.steuerjahr.isEmpty || beleg.steuerjahr.count != 4 {
            beleg.steuerjahr = String(beleg.datum.prefix(4))
        }

        // FIX: person – Ollama nutzt manchmal "steuerpflichtiger" oder "empfaenger"
        // Token-basierter Abgleich mit konfigurierten Personen
        let personRoh = dict["person"]             as? String
            ?? dict["steuerpflichtiger"]           as? String
            ?? dict["empfaenger"]                  as? String
            ?? dict["kontoinhaber"]                as? String
            ?? ""
        beleg.person        = personZuordnen(personRoh)

        // Belegtyp auf erlaubte Frontend-Werte beschränken
        let erlaubteBelegtypen = ["Rechnung", "Quittung", "Lohnsteuerbescheinigung",
                                  "Bescheinigung", "Kontoauszug", "Vertrag", "Sonstiges"]
        let belegtypRoh = dict["belegtyp"] as? String ?? "Sonstiges"
        if erlaubteBelegtypen.contains(belegtypRoh) {
            beleg.belegtyp = belegtypRoh
        } else if belegtypRoh.lowercased().contains("bescheinigung") {
            beleg.belegtyp = "Bescheinigung"
        } else if belegtypRoh.lowercased().contains("rechnung") {
            beleg.belegtyp = "Rechnung"
        } else if belegtypRoh.lowercased().contains("quittung") || belegtypRoh.lowercased().contains("kassenbon") {
            beleg.belegtyp = "Quittung"
        } else if belegtypRoh.lowercased().contains("lohnsteuer") {
            beleg.belegtyp = "Lohnsteuerbescheinigung"
        } else if belegtypRoh.lowercased().contains("steuer") {
            beleg.belegtyp = "Bescheinigung"
        } else if belegtypRoh.lowercased().contains("kontoauszug") {
            beleg.belegtyp = "Kontoauszug"
        } else if belegtypRoh.lowercased().contains("vertrag") {
            beleg.belegtyp = "Vertrag"
        } else {
            beleg.belegtyp = "Sonstiges"
        }
        beleg.beschreibung  = dict["beschreibung"] as? String ?? "Unbekannt"

        func parseBetrag(_ str: String) -> Double {
            var clean = str
                .replacingOccurrences(of: "€",   with: "")
                .replacingOccurrences(of: "EUR", with: "")
                .replacingOccurrences(of: " ",   with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let hatPunkt = clean.contains(".")
            let hatKomma = clean.contains(",")
            if hatPunkt && hatKomma {
                if clean.range(of: ",")!.lowerBound < clean.range(of: ".")!.lowerBound {
                    clean = clean.replacingOccurrences(of: ",", with: "")
                } else {
                    clean = clean.replacingOccurrences(of: ".", with: "")
                    clean = clean.replacingOccurrences(of: ",", with: ".")
                }
            } else if hatKomma {
                clean = clean.replacingOccurrences(of: ",", with: ".")
            }
            return Double(clean) ?? 0.0
        }

        if let betragStr = dict["betrag"] as? String {
            beleg.betrag = parseBetrag(betragStr)
        } else if let betragNum = dict["betrag"] as? Double {
            beleg.betrag = betragNum
        } else if let betragInt = dict["betrag"] as? Int {
            beleg.betrag = Double(betragInt)
        }

        beleg.kategorie      = dict["kategorie"]      as? String ?? "Sonstiges"
        beleg.typ            = dict["typ"]            as? String ?? "Ausgabe"
        beleg.gemeinsam      = dict["gemeinsam"]      as? String ?? "nein"
        beleg.notiz          = dict["notiz"]          as? String ?? "leer"
        beleg.steuerrelevant = dict["steuerrelevant"] as? Bool   ?? true

        // Sicherheitsnetz: Typ aus Kategorie ableiten wenn Modell falsch liegt
        // Kapitalerträge, Arbeitslohn, Rente etc. sind immer Einnahmen
        let einnahmeKategorien = ["kapitalertrag", "arbeitslohn", "rente", "pension",
                                  "vermietung", "verpachtung", "freiberuflich", "einnahme"]
        let kategorieLower = beleg.kategorie.lowercased()
        if einnahmeKategorien.contains(where: { kategorieLower.contains($0) }) {
            if beleg.typ == "Ausgabe" {
                DevLog.shared.log("Typ korrigiert: Ausgabe → Einnahme (Kategorie: \(beleg.kategorie))", typ: .info)
                beleg.typ = "Einnahme"
            }
        }

        beleg.dateiname      = dateiname
        return beleg
    }

    // ------------------------------------------------------------
    // steuer_confirm aufrufen für Bestätigung
    // ------------------------------------------------------------
    private func bestaetigungAnzeigen(beleg: Beleg, pdfPfad: String, dateiname: String) async -> Beleg? {
        let konfig = appState.konfig
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

        let kategorienEinnahmen = konfig.kategorien.filter { $0.typ == .einnahme }.map { $0.name }
        let kategorienAusgaben  = konfig.kategorien.filter { $0.typ == .ausgabe  }.map { $0.name }
        let kategorienBeides    = konfig.kategorien.filter { $0.typ == .beides   }.map { $0.name }

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
            "steuerrelevant":      beleg.steuerrelevant,
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
                    if let data = jsonStr.data(using: .utf8),
                       let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        if let sj = dict["steuerjahr"] as? String, !sj.isEmpty {
                            result?.steuerjahr = sj
                        }
                        result?.steuerrelevant = dict["steuerrelevant"] as? Bool ?? true
                    }
                    continuation.resume(returning: result)
                }
            }
            try? process.run()
        }
    }

    // ------------------------------------------------------------
    // Ordnungsnummer aus CSV ableiten
    // ------------------------------------------------------------
    private func naechsteOrdnungsnummer(kategorie: String, typ: String, jahr: String, steuerrelevant: Bool = true) -> String {
        let kuerzel  = kuerzelFuerKategorie(kategorie: kategorie, typ: typ)
        let basis    = appState.konfig.archivPfad
        let csvPfad: String
        if !steuerrelevant {
            csvPfad = "\(basis)/\(jahr)/Unterlagen_\(jahr).csv"
        } else if typ == "Einnahme" {
            csvPfad = "\(basis)/\(jahr)/Einnahmen_\(jahr).csv"
        } else {
            csvPfad = "\(basis)/\(jahr)/Ausgaben_\(jahr).csv"
        }
        let praefix   = "\(kuerzel)-"
        var maxNummer = 0

        if let inhalt = try? String(contentsOfFile: csvPfad) {
            for zeile in inhalt.components(separatedBy: "\n").dropFirst() {
                let ersteSpalte = zeile.components(separatedBy: ";").first ?? ""
                guard ersteSpalte.hasPrefix(praefix) else { continue }
                let numStr = String(ersteSpalte.dropFirst(praefix.count))
                if let num = Int(numStr), num > maxNummer { maxNummer = num }
            }
        }
        return String(format: "%@-%03d", kuerzel, maxNummer + 1)
    }

    private func kuerzelFuerKategorie(kategorie: String, typ: String) -> String {
        return appState.konfig.kategorien.first { $0.name == kategorie }?.kuerzel ?? "SO"
    }

    // ------------------------------------------------------------
    // Metadaten einbetten (exiftool) + macOS Tags setzen
    // ------------------------------------------------------------
    private func metadatenEinbetten(beleg: Beleg, pdfURL: URL) async {
        let konfig           = appState.konfig
        let ausstellungsjahr = String(beleg.datum.prefix(4))

        var tags = [beleg.kategorie, beleg.belegtyp, beleg.typ, ausstellungsjahr, "Stashfix"]
        if !beleg.beschreibung.isEmpty { tags.append(beleg.beschreibung) }
        if !beleg.person.isEmpty       { tags.append(beleg.person) }
        if beleg.steuerrelevant {
            tags += ["Steuer", "Steuerjahr-\(beleg.steuerjahr.isEmpty ? ausstellungsjahr : beleg.steuerjahr)"]
        }

        if konfig.exifMetadatenAktiv, let exiftoolPfad = toolPfadCached("exiftool") {
            _ = await prozessAusfuehren(pfad: exiftoolPfad, argumente: [
                "-Title=\(beleg.beschreibung)",
                "-Subject=\(beleg.kategorie)",
                "-Keywords=\(tags.joined(separator: ", "))",
                "-Author=\(beleg.person)",
                "-Comment=Nr: \(beleg.ordnungsNr) | \(String(format: "%.2f", beleg.betrag)) EUR | \(beleg.belegtyp) | \(beleg.notiz)",
                "-overwrite_original",
                pdfURL.path
            ])
            DevLog.shared.log("exiftool Metadaten eingebettet", typ: .info)
        }

        if konfig.macOSTagsAktiv {
            macOSTagsSetzen(url: pdfURL, tags: tags)
        }
    }

    private func macOSTagsSetzen(url: URL, tags: [String]) {
        do {
            try (url as NSURL).setResourceValue(tags as NSArray, forKey: .tagNamesKey)
            DevLog.shared.log("macOS Tags gesetzt: \(tags.joined(separator: ", "))", typ: .info)
        } catch {
            DevLog.shared.log("macOS Tags konnten nicht gesetzt werden: \(error.localizedDescription)", typ: .fehler)
        }
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
    // FIX Warn#2: Atomares Schreiben via replaceItemAt – kein korrupter State bei Absturz
    // ------------------------------------------------------------
    private func csvAktualisieren(beleg: Beleg) {
        let basis    = appState.konfig.archivPfad
        let datname  = URL(fileURLWithPath: beleg.archivPfad).lastPathComponent
        let betragFormatiert = String(format: "%.2f", beleg.betrag).replacingOccurrences(of: ".", with: ",")

        if beleg.steuerrelevant {
            let jahr = beleg.steuerjahr.isEmpty ? String(beleg.datum.prefix(4)) : beleg.steuerjahr
            let csvPfad: String; let header: String; let zeile: String
            if beleg.typ == "Einnahme" {
                csvPfad = "\(basis)/\(jahr)/Einnahmen_\(jahr).csv"
                header  = "Nr;Datum;Person;Belegtyp;Beschreibung;Betrag in EUR;Kategorie;Notiz;Dateiname"
                zeile   = "\(beleg.ordnungsNr);\(datumAnzeige(beleg.datum));\(beleg.person);\(beleg.belegtyp);\(beleg.beschreibung);\(betragFormatiert);\(beleg.kategorie);\(beleg.notiz);\(datname)"
            } else {
                csvPfad = "\(basis)/\(jahr)/Ausgaben_\(jahr).csv"
                header  = "Nr;Datum;Person;Belegtyp;Beschreibung;Betrag in EUR;Kategorie;Gemeinsam;Notiz;Dateiname"
                zeile   = "\(beleg.ordnungsNr);\(datumAnzeige(beleg.datum));\(beleg.person);\(beleg.belegtyp);\(beleg.beschreibung);\(betragFormatiert);\(beleg.kategorie);\(beleg.gemeinsam);\(beleg.notiz);\(datname)"
            }
            csvZeileSchreiben(pfad: csvPfad, header: header, zeile: zeile)
        } else {
            let jahr    = String(beleg.datum.prefix(4))
            let csvPfad = "\(basis)/\(jahr)/Unterlagen_\(jahr).csv"
            let header  = "Nr;Datum;Belegtyp;Beschreibung;Betrag in EUR;Kategorie;Notiz;Dateiname"
            let zeile   = "\(beleg.ordnungsNr);\(datumAnzeige(beleg.datum));\(beleg.belegtyp);\(beleg.beschreibung);\(betragFormatiert);\(beleg.kategorie);\(beleg.notiz);\(datname)"
            csvZeileSchreiben(pfad: csvPfad, header: header, zeile: zeile)
        }
    }

    // FIX Warn#2: Atomares Schreiben – kein Datenverlust bei Absturz
    private func csvZeileSchreiben(pfad: String, header: String, zeile: String) {
        let csvURL = URL(fileURLWithPath: pfad)

        // Bestehenden Inhalt lesen oder neu mit Header beginnen
        var inhalt: String
        if fm.fileExists(atPath: pfad),
           let vorhandener = try? String(contentsOf: csvURL, encoding: .utf8) {
            inhalt = vorhandener
        } else {
            inhalt = header + "\n"
        }
        inhalt += zeile + "\n"

        // Atomar schreiben: erst in tmp-Datei, dann atomic replace
        let tmpURL = csvURL.deletingLastPathComponent()
            .appendingPathComponent(".\(csvURL.lastPathComponent).tmp")
        do {
            try inhalt.write(to: tmpURL, atomically: false, encoding: .utf8)
            _ = try fm.replaceItemAt(csvURL, withItemAt: tmpURL,
                                     backupItemName: nil,
                                     options: .usingNewMetadataOnly)
        } catch {
            // Fallback: direktes atomares Schreiben
            try? inhalt.write(to: csvURL, atomically: true, encoding: .utf8)
            appState.fehler = "CSV-Schreiben (Fallback): \(error.localizedDescription)"
        }
    }

    // ------------------------------------------------------------
    // SHA-256-Hash berechnen (erste 64KB)
    // ------------------------------------------------------------
    private func sha256Hash(url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let chunk  = handle.readData(ofLength: 65_536)
        let digest = SHA256.hash(data: chunk)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func istDublette(hash: String) -> Bool {
        let pfad = appState.konfig.archivPfad + "/.verarbeitete_belege"
        guard fm.fileExists(atPath: pfad),
              let inhalt = try? String(contentsOfFile: pfad)
        else { return false }
        for zeile in inhalt.components(separatedBy: "\n") {
            let teile = zeile.components(separatedBy: "\t")
            guard teile.count >= 2 else { continue }
            if teile[0] == hash && fm.fileExists(atPath: teile[1]) { return true }
        }
        return false
    }

    private func hashSpeichern(hash: String, archivPfad: String) {
        let pfad    = appState.konfig.archivPfad + "/.verarbeitete_belege"
        let eintrag = "\(hash)\t\(archivPfad)\n"
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
