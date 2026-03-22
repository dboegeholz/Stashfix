import SwiftUI
import AppKit
import PDFKit
import Foundation

// ============================================================
// steuer_confirm.swift – mit PDF-Vorschau, Fokus, breitem Layout
// ============================================================

func datumAnzeige(_ iso: String) -> String {
    let t = iso.split(separator: "-")
    guard t.count == 3 else { return iso }
    return "\(t[2]).\(t[1]).\(t[0])"
}

func datumISO(_ anzeige: String) -> String {
    let t = anzeige.split(separator: ".")
    guard t.count == 3 else { return anzeige }
    return "\(t[2])-\(t[1])-\(t[0])"
}

struct Beleg: Codable {
    var datum:               String
    var steuerjahr:          String
    var person:              String
    var belegtyp:            String
    var beschreibung:        String
    var aussteller:          String = ""
    var betrag:              String
    var kategorie:           String
    var typ:                 String
    var gemeinsam:           String
    var notiz:               String
    var dateiname:           String
    var modus:               String
    var person1:             String
    var person2:             String
    var pdfpfad:             String
    var steuerrelevant:      Bool?
    var kategorienEinnahmen: [String]
    var kategorienAusgaben:  [String]
    var kategorienBeides:    [String]

    // Alle passenden Kategorien je nach Typ
    func kategorienFuer(typ: String) -> [String] {
        if typ == "Einnahme" {
            return kategorienEinnahmen + kategorienBeides
        } else {
            return kategorienAusgaben + kategorienBeides
        }
    }

    var verfuegbareKategorien: [String] {
        kategorienFuer(typ: typ)
    }
}

// ------------------------------------------------------------
// Farben
// ------------------------------------------------------------
func kategoriefarbe(_ k: String) -> Color {
    switch k {
    case "Haushaltskosten":  return Color(red:1.0,  green:0.87, blue:0.7)
    case "Werbungskosten":   return Color(red:0.7,  green:0.9,  blue:1.0)
    case "Sonderausgaben":   return Color(red:0.85, green:0.7,  blue:1.0)
    case "Gehalt":           return Color(red:0.7,  green:1.0,  blue:0.75)
    default:                 return Color(red:0.9,  green:0.9,  blue:0.9)
    }
}

func typfarbe(_ t: String) -> Color {
    t == "Einnahme"
        ? Color(red:0.7,  green:1.0,  blue:0.75)
        : Color(red:1.0,  green:0.75, blue:0.75)
}

// ------------------------------------------------------------
// PDF-Vorschau (PDFKit)
// ------------------------------------------------------------
struct PDFVorschau: NSViewRepresentable {
    let pfad: String

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales         = true
        view.displayMode        = .singlePage
        view.displaysPageBreaks = false
        view.isInMarkupMode     = false
        if let url = URL(string: "file://\(pfad.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? pfad)"),
           let doc = PDFDocument(url: url) {
            view.document = doc
        }
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        nsView.isInMarkupMode = false
    }
}

// ------------------------------------------------------------
// Hauptfenster
// ------------------------------------------------------------
struct BestaetigungView: View {
    @State var beleg: Beleg
    var onBestaetigen: (Beleg) -> Void
    var onAbbrechen:   ()      -> Void

    let belegtypen = ["Rechnung","Quittung","Lohnsteuerbescheinigung",
                      "Bescheinigung","Kontoauszug","Vertrag","Sonstiges"]
    let typen      = ["Einnahme","Ausgabe"]
    let jaNein     = ["ja","nein"]

    var body: some View {
        HStack(spacing: 0) {

            // ------------------------------------------------
            // LINKS: PDF-Vorschau
            // ------------------------------------------------
            VStack(spacing: 0) {
                Text("Dokument")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 6)
                Divider()
                if !beleg.pdfpfad.isEmpty {
                    PDFVorschau(pfad: beleg.pdfpfad)
                } else {
                    VStack {
                        Spacer()
                        Image(systemName: "doc.text")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text("Keine Vorschau")
                            .foregroundColor(.secondary)
                            .font(.caption)
                        Spacer()
                    }
                }
            }
            .frame(minWidth: 400, maxWidth: .infinity)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // ------------------------------------------------
            // RECHTS: Formular
            // ------------------------------------------------
            VStack(alignment: .leading, spacing: 0) {

                // Header
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Beleg bestätigen")
                            .font(.headline)
                        Text(beleg.dateiname)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(kategoriefarbe(beleg.kategorie))
                            .frame(width: 120, height: 28)
                            .overlay(
                                Text(beleg.kategorie)
                                    .font(.caption)
                                    .bold()
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.6)
                                    .padding(.horizontal, 4)
                            )
                        RoundedRectangle(cornerRadius: 8)
                            .fill(typfarbe(beleg.typ))
                            .frame(width: 120, height: 24)
                            .overlay(
                                Text(beleg.typ)
                                    .font(.caption)
                                    .bold()
                            )
                    }
                }
                .padding()
                .background(Color(NSColor.windowBackgroundColor))

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {

                        // Datum
                        Feld(label: "Datum") {
                            TextField("TT.MM.JJJJ", text: Binding(
                                get: { datumAnzeige(beleg.datum) },
                                set: { beleg.datum = datumISO($0) }
                            ))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 160)
                        }

                        // Steuerjahr – kann vom Belegdatum abweichen
                        Feld(label: "Steuerjahr") {
                            HStack(spacing: 8) {
                                TextField("JJJJ", text: $beleg.steuerjahr)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 80)
                                if !beleg.steuerjahr.isEmpty &&
                                   beleg.steuerjahr != String(beleg.datum.prefix(4)) {
                                    Text("⚠️ weicht vom Belegdatum ab")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                }
                            }
                        }
                        if beleg.modus == "paar" {
                            Feld(label: "Person") {
                                Picker("", selection: $beleg.person) {
                                    Text(beleg.person1).tag(beleg.person1)
                                    Text(beleg.person2).tag(beleg.person2)
                                    Text("Gemeinsam").tag("Gemeinsam")
                                }
                                .pickerStyle(.segmented)
                                .frame(minWidth: 280)
                            }
                        }

                        // Belegtyp
                        Feld(label: "Belegtyp") {
                            Picker("", selection: $beleg.belegtyp) {
                                ForEach(belegtypen, id: \.self) { Text($0).tag($0) }
                            }
                            .frame(minWidth: 240)
                        }

                        // Beschreibung
                        Feld(label: "Beschreibung") {
                            TextField("Dokumenttyp / Schlagwort", text: $beleg.beschreibung)
                                .textFieldStyle(.roundedBorder)
                                .frame(minWidth: 280)
                        }

                        // Aussteller
                        Feld(label: "Aussteller") {
                            TextField("Name der ausstellenden Institution", text: $beleg.aussteller)
                                .textFieldStyle(.roundedBorder)
                                .frame(minWidth: 280)
                        }

                        // Betrag
                        Feld(label: "Betrag (EUR)") {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    TextField("0.00", text: $beleg.betrag)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 120)
                                    Text("EUR")
                                        .foregroundColor(.secondary)
                                }
                                // Warnung wenn Betrag verdächtig niedrig für Lohnsteuerbescheinigung
                                if beleg.belegtyp == "Lohnsteuerbescheinigung",
                                   let b = Double(beleg.betrag.replacingOccurrences(of: ",", with: ".")),
                                   b < 1000 {
                                    HStack(spacing: 4) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundColor(.orange)
                                            .font(.caption)
                                        Text("Betrag erscheint zu niedrig – bitte prüfen (Tausenderpunkt?)")
                                            .font(.caption)
                                            .foregroundColor(.orange)
                                    }
                                }
                            }
                        }

                        // Typ
                        Feld(label: "Typ") {
                            Picker("", selection: $beleg.typ) {
                                ForEach(typen, id: \.self) { Text($0).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 180)
                            .onChange(of: beleg.typ) {
                                // Kategorie zurücksetzen wenn sie nicht mehr passt
                                if !beleg.verfuegbareKategorien.contains(beleg.kategorie) {
                                    beleg.kategorie = beleg.verfuegbareKategorien.first ?? ""
                                }
                            }
                        }

                        // Kategorie mit Live-Farbvorschau
                        // Kategorien werden dynamisch aus der Konfiguration geladen
                        Feld(label: "Kategorie") {
                            HStack(spacing: 10) {
                                Picker("", selection: $beleg.kategorie) {
                                    ForEach(beleg.verfuegbareKategorien, id: \.self) { kat in
                                        Text(kat).tag(kat)
                                    }
                                }
                                .frame(minWidth: 220)
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(kategoriefarbe(beleg.kategorie))
                                    .frame(width: 22, height: 22)
                                    .animation(.easeInOut(duration: 0.2), value: beleg.kategorie)
                            }
                        }

                        // "gemeinsam" wird automatisch aus dem Person-Feld abgeleitet:
                        // Person == "Gemeinsam" → gemeinsam = "ja", sonst "nein"

                        // Notiz
                        Feld(label: "Notiz") {
                            TextField("Hinweis", text: $beleg.notiz)
                                .textFieldStyle(.roundedBorder)
                                .frame(minWidth: 280)
                        }

                        // Steuerrelevanz
                        Feld(label: "Steuerrelevant") {
                            HStack(spacing: 10) {
                                Toggle("Relevant für Steuererklärung", isOn: Binding(
                                    get: { beleg.steuerrelevant ?? true },
                                    set: { beleg.steuerrelevant = $0 }
                                ))
                                    .toggleStyle(.switch)
                            }
                        }

                    }
                    .padding()
                }

                Divider()

                // Buttons
                HStack {
                    Button("Abbrechen") { onAbbrechen() }
                        .keyboardShortcut(.escape)
                    Spacer()
                    Button("Akzeptieren") { onBestaetigen(beleg) }
                        .keyboardShortcut(.return)
                        .buttonStyle(.borderedProminent)
                }
                .padding()
            }
            .frame(minWidth: 500, maxWidth: .infinity)
        }
        .frame(minWidth: 900, maxWidth: .infinity, minHeight: 600, maxHeight: .infinity)
    }
}

struct Feld<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(label)
                .frame(width: 150, alignment: .trailing)
                .foregroundColor(.secondary)
                .font(.callout)
            content()
        }
    }
}

// ------------------------------------------------------------
// App-Einstiegspunkt
// ------------------------------------------------------------
class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        guard args.count > 1,
              let data = args[1].data(using: .utf8),
              var beleg = try? JSONDecoder().decode(Beleg.self, from: data)
        else {
            fputs("Fehler: Kein gültiges JSON\n", stderr)
            exit(1)
        }

        // Punkt zu Komma für deutsche Darstellung
        beleg.betrag = beleg.betrag.replacingOccurrences(of: ".", with: ",")

        // Belegtyp auf erlaubte Werte normalisieren
        let erlaubt = ["Rechnung","Quittung","Lohnsteuerbescheinigung",
                       "Bescheinigung","Kontoauszug","Vertrag","Sonstiges"]
        if !erlaubt.contains(beleg.belegtyp) {
            let b = beleg.belegtyp.lowercased()
            if b.contains("lohnsteuer")       { beleg.belegtyp = "Lohnsteuerbescheinigung" }
            else if b.contains("bescheinigung") { beleg.belegtyp = "Bescheinigung" }
            else if b.contains("rechnung")    { beleg.belegtyp = "Rechnung" }
            else if b.contains("quittung") || b.contains("kassenbon") { beleg.belegtyp = "Quittung" }
            else if b.contains("steuer")      { beleg.belegtyp = "Bescheinigung" }
            else if b.contains("kontoauszug") { beleg.belegtyp = "Kontoauszug" }
            else if b.contains("vertrag")     { beleg.belegtyp = "Vertrag" }
            else                              { beleg.belegtyp = "Sonstiges" }
        }

        let view = BestaetigungView(
            beleg: beleg,
            onBestaetigen: { korrigiert in
                var ausgabe = korrigiert
                // Komma zurück zu Punkt für interne Verarbeitung
                ausgabe.betrag = ausgabe.betrag.replacingOccurrences(of: ",", with: ".")
                // "gemeinsam" aus Person-Feld ableiten
                ausgabe.gemeinsam = (ausgabe.person == "Gemeinsam") ? "ja" : "nein"
                if let json = try? JSONEncoder().encode(ausgabe),
                   let str  = String(data: json, encoding: .utf8) {
                    print(str)
                }
                exit(0)
            },
            onAbbrechen: {
                fputs("abgebrochen\n", stderr)
                exit(2)
            }
        )

        // Volle Bildschirmbreite
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x:0, y:0, width:1440, height:900)
        let winWidth  = screen.width
        let winHeight = min(screen.height, 700.0)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: winWidth, height: winHeight),
            styleMask:   [.titled, .closable, .resizable],
            backing:     .buffered,
            defer:       false
        )
        window.title           = "Beleg bestätigen"
        window.contentView     = NSHostingView(rootView: view)
        window.center()
        window.makeKeyAndOrderFront(nil)

        // Fokus erzwingen
        NSApp.activate(ignoringOtherApps: true)
        window.level = .floating
        window.level = .normal

        self.window = window
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }
}


let app      = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)

// Menüleiste mit Bearbeiten-Menü (Kopieren, Einfügen etc.)
let mainMenu = NSMenu()

let appMenuItem = NSMenuItem()
mainMenu.addItem(appMenuItem)
let appMenu = NSMenu()
appMenu.addItem(withTitle: "Beenden", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
appMenuItem.submenu = appMenu

let editMenuItem = NSMenuItem()
mainMenu.addItem(editMenuItem)
let editMenu = NSMenu(title: "Bearbeiten")
editMenu.addItem(withTitle: "Ausschneiden",    action: #selector(NSText.cut(_:)),       keyEquivalent: "x")
editMenu.addItem(withTitle: "Kopieren",        action: #selector(NSText.copy(_:)),      keyEquivalent: "c")
editMenu.addItem(withTitle: "Einsetzen",       action: #selector(NSText.paste(_:)),     keyEquivalent: "v")
editMenu.addItem(withTitle: "Alles auswählen", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
editMenuItem.submenu = editMenu

app.mainMenu = mainMenu

app.run()
