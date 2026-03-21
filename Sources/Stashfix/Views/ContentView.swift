import SwiftUI
import AppKit

// ============================================================
// ContentView.swift – Hauptfenster
// ============================================================

struct ContentView: View {
    @Environment(AppState.self) var appState

    var body: some View {
        @Bindable var appState = appState
        NavigationSplitView {
            InboxSidebar()
                .environment(appState)
        } detail: {
            StatusView()
                .environment(appState)
        }
        .navigationTitle("Stashfix")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {

                Button {
                    appState.inboxLaden()
                } label: {
                    Label("Aktualisieren", systemImage: "arrow.clockwise")
                }
                .help("Inbox neu laden")

                Button {
                    NotificationCenter.default.post(name: .verarbeitenStarten, object: nil)
                } label: {
                    Label("Verarbeiten", systemImage: "play.circle.fill")
                }
                .disabled(appState.inboxDateien.isEmpty || appState.laeuft)
                .help("Alle Belege in der Inbox verarbeiten")

                Button {
                    EinstellungenFenster.shared.oeffnen(appState: appState)
                } label: {
                    Label("Einstellungen", systemImage: "gear")
                }
                .help("Einstellungen öffnen")
            }
        }
        .onAppear {
            appState.inboxLaden()
        }
        .onReceive(NotificationCenter.default.publisher(for: .fensterOeffnen)) { _ in
            appState.inboxLaden()
        }
        .dependencyCheck()
    }
}


// ------------------------------------------------------------
// Sidebar: Inbox-Liste
// ------------------------------------------------------------
struct InboxSidebar: View {
    @Environment(AppState.self) var appState

    var body: some View {
        @Bindable var appState = appState
        VStack(alignment: .leading, spacing: 0) {

            // Header
            HStack {
                Text("Inbox")
                    .font(.headline)
                Spacer()
                if !appState.inboxDateien.isEmpty {
                    Text("\(appState.inboxDateien.count)")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if appState.inboxDateien.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "tray")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary)
                    Text("Inbox ist leer")
                        .font(.callout)
                        .foregroundColor(.secondary)
                    Text("Lege PDFs in den Inbox-Ordner\noder ziehe sie ins Fenster")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding()
            } else {
                List(appState.inboxDateien, id: \.self) { url in
                    InboxDateiZeile(url: url)
                        .environment(appState)
                }
                .listStyle(.sidebar)
            }

            Divider()

            // Auto-Modus Toggle
            HStack {
                Image(systemName: appState.konfig.autoModus ? "bolt.fill" : "bolt.slash")
                    .foregroundColor(appState.konfig.autoModus ? .yellow : .secondary)
                    .font(.caption)
                Text("Auto-Modus")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Toggle("", isOn: $appState.konfig.autoModus)
                    .toggleStyle(.switch)
                    .scaleEffect(0.8)
                    .onChange(of: appState.konfig.autoModus) {
                        appState.konfigurationSpeichern()
                    }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(minWidth: 220, maxWidth: 280)
    }
}


// ------------------------------------------------------------
// Einzelne Datei in der Inbox-Liste
// ------------------------------------------------------------
struct InboxDateiZeile: View {
    @Environment(AppState.self) var appState
    let url: URL

    var body: some View {
        @Bindable var appState = appState
        HStack(spacing: 10) {
            Image(systemName: "doc.fill")
                .foregroundColor(.accentColor)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(url.lastPathComponent)
                    .font(.callout)
                    .lineLimit(2)
                    .truncationMode(.middle)

                if let attr = try? FileManager.default.attributesOfItem(atPath: url.path),
                   let groesse = attr[.size] as? Int {
                    Text(ByteCountFormatter.string(fromByteCount: Int64(groesse), countStyle: .file))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("In Finder zeigen") {
                NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
            }
            Button("Aus Inbox entfernen", role: .destructive) {
                try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
                appState.inboxLaden()
            }
        }
    }
}


// ------------------------------------------------------------
// Detail: Status / Fortschritt
// ------------------------------------------------------------
struct StatusView: View {
    @Environment(AppState.self) var appState

    var fortschritt: Double {
        guard appState.gesamt > 0 else { return 0 }
        return Double(appState.verarbeitet) / Double(appState.gesamt)
    }

    var body: some View {
        @Bindable var appState = appState
        VStack(spacing: 24) {
            Spacer()

            if appState.laeuft {
                // Fortschrittsanzeige
                VStack(spacing: 16) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.accentColor)
                        .symbolEffect(.pulse)

                    Text("Verarbeitung läuft...")
                        .font(.title2)
                        .bold()

                    if !appState.aktuelleDatei.isEmpty {
                        Text(appState.aktuelleDatei)
                            .font(.callout)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    if !appState.aktuellerSchritt.isEmpty {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text(appState.aktuellerSchritt)
                                .font(.callout)
                        }
                    }

                    if appState.gesamt > 0 {
                        VStack(spacing: 6) {
                            ProgressView(value: fortschritt)
                                .frame(width: 300)
                                .animation(.easeInOut, value: fortschritt)
                            Text("Beleg \(appState.verarbeitet) von \(appState.gesamt)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

            } else if appState.inboxDateien.isEmpty {
                // Willkommen
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 48))
                        .foregroundColor(.green)
                    Text("Alles erledigt")
                        .font(.title2)
                        .bold()
                    Text("Lege neue Belege in die Inbox\num sie zu verarbeiten.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            } else {
                // Bereit
                VStack(spacing: 12) {
                    Image(systemName: "tray.full")
                        .font(.system(size: 48))
                        .foregroundColor(.accentColor)
                    Text("\(appState.inboxDateien.count) Beleg(e) bereit")
                        .font(.title2)
                        .bold()
                    Text("Klicke auf 'Verarbeiten' um zu starten.")
                        .font(.callout)
                        .foregroundColor(.secondary)

                    Button("Jetzt verarbeiten") {
                        NotificationCenter.default.post(name: .verarbeitenStarten, object: nil)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.top, 8)
                }
            }

            Spacer()

            // Konfigurationsinfo unten
            HStack {
                Image(systemName: "person.2")
                    .foregroundColor(.secondary)
                    .font(.caption)
                Text(konfigInfo)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Image(systemName: "brain")
                    .foregroundColor(.secondary)
                    .font(.caption)
                Text(appState.konfig.ollamaModell)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert("Fehler", isPresented: Binding(
            get: { appState.fehler != nil },
            set: { if !$0 { appState.fehler = nil } }
        )) {
            Button("OK") { appState.fehler = nil }
        } message: {
            Text(appState.fehler ?? "")
        }
    }

    var konfigInfo: String {
        if appState.konfig.modus == .einzel {
            return appState.konfig.person1.isEmpty ? "Nicht konfiguriert" : appState.konfig.person1
        } else {
            let p1 = appState.konfig.person1.isEmpty ? "Person 1" : appState.konfig.person1
            let p2 = appState.konfig.person2.isEmpty ? "Person 2" : appState.konfig.person2
            return "\(p1) & \(p2)"
        }
    }
}
