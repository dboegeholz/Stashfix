import SwiftUI
import AppKit

// ============================================================
// DevLogView.swift
// Developer-Fenster: zeigt Live-Log aller Verarbeitungsschritte
// Erreichbar über Menüleiste → "Developer Log"
// ============================================================

// Globaler Log-Sink – thread-safe, wird von VerarbeitungsService befüllt
@MainActor
@Observable
class DevLog {
    static let shared = DevLog()

    struct Eintrag: Identifiable {
        let id    = UUID()
        let zeit  = Date()
        let typ:  Typ
        let text: String

        enum Typ {
            case info, ocr, text, ollama, fehler, erfolg
            var farbe: Color {
                switch self {
                case .info:    return .secondary
                case .ocr:     return .blue
                case .text:    return .purple
                case .ollama:  return .orange
                case .fehler:  return .red
                case .erfolg:  return .green
                }
            }
            var symbol: String {
                switch self {
                case .info:    return "ℹ"
                case .ocr:     return "🔍"
                case .text:    return "📄"
                case .ollama:  return "🤖"
                case .fehler:  return "⚠️"
                case .erfolg:  return "✅"
                }
            }
        }
    }

    var eintraege: [Eintrag] = []
    var aktiv = false

    func log(_ text: String, typ: Eintrag.Typ = .info) {
        eintraege.append(Eintrag(typ: typ, text: text))
        // Max 500 Einträge behalten
        if eintraege.count > 500 {
            eintraege.removeFirst(eintraege.count - 500)
        }
    }

    func leeren() {
        eintraege = []
    }
}

// ============================================================
// Fensterverwaltung
// ============================================================
@MainActor
class DevLogFenster {
    static let shared = DevLogFenster()
    private var fenster: NSWindow?

    func oeffnen() {
        if let f = fenster, f.isVisible {
            f.makeKeyAndOrderFront(nil)
            return
        }
        let view    = DevLogView()
        let hosting = NSHostingController(rootView: view)
        let window  = NSWindow(contentViewController: hosting)
        window.title                = "Developer Log – Stashfix"
        window.styleMask            = [.titled, .closable, .resizable, .miniaturizable]
        window.setContentSize(NSSize(width: 800, height: 500))
        window.minSize              = NSSize(width: 500, height: 300)
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        fenster = window
    }
}

// ============================================================
// DevLogView
// ============================================================
struct DevLogView: View {
    @State private var log = DevLog.shared
    @State private var autoscroll = true
    @State private var filter: DevLog.Eintrag.Typ? = nil

    private let zeitFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    var gefilterteEintraege: [DevLog.Eintrag] {
        guard let f = filter else { return log.eintraege }
        return log.eintraege.filter { $0.typ == f }
    }

    var body: some View {
        VStack(spacing: 0) {

            // Toolbar
            HStack(spacing: 10) {
                Text("Developer Log")
                    .font(.headline)

                Spacer()

                // Filter
                HStack(spacing: 4) {
                    filterButton(nil, label: "Alle")
                    filterButton(.ocr,    label: "OCR")
                    filterButton(.text,   label: "Text")
                    filterButton(.ollama, label: "Ollama")
                    filterButton(.fehler, label: "Fehler")
                }

                Divider().frame(height: 20)

                Toggle("Auto-Scroll", isOn: $autoscroll)
                    .toggleStyle(.switch)
                    .scaleEffect(0.8)

                Button(action: { log.leeren() }) {
                    Label("Leeren", systemImage: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Log-Liste
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(gefilterteEintraege) { eintrag in
                            LogZeile(eintrag: eintrag, zeitFormatter: zeitFormatter)
                                .id(eintrag.id)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onChange(of: log.eintraege.count) {
                    if autoscroll, let last = gefilterteEintraege.last {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            // Statuszeile
            HStack {
                Circle()
                    .fill(log.aktiv ? Color.green : Color.secondary)
                    .frame(width: 8, height: 8)
                Text(log.aktiv ? "Verarbeitung läuft..." : "Bereit")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(gefilterteEintraege.count) Einträge")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    @ViewBuilder
    func filterButton(_ typ: DevLog.Eintrag.Typ?, label: String) -> some View {
        Button(label) { filter = typ }
            .buttonStyle(.borderless)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(filter == typ ? Color.accentColor.opacity(0.15) : Color.clear)
            .cornerRadius(6)
            .font(.caption)
    }
}

struct LogZeile: View {
    let eintrag: DevLog.Eintrag
    let zeitFormatter: DateFormatter

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(zeitFormatter.string(from: eintrag.zeit))
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 90, alignment: .leading)

            Text(eintrag.typ.symbol)
                .font(.caption2)
                .frame(width: 20)

            Text(eintrag.text)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(eintrag.typ.farbe)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
        .background(eintrag.typ == .fehler ? Color.red.opacity(0.05) : Color.clear)
    }
}
