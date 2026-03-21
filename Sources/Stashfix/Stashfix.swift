import SwiftUI
import AppKit
import Observation

// ============================================================
// Stashfix.swift – Menüleisten-App
// Aufgeräumte Version: kein toter Code, keine doppelten Strukturen
// ============================================================

@main
struct Stashfix: App {
    @State private var appState = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {

        // Hauptfenster
        WindowGroup {
            ContentView()
                .environment(appState)
                .frame(minWidth: 900, minHeight: 600)
                .onAppear {
                    appDelegate.setup(appState: appState)
                    // Onboarding beim ersten Start
                    if appState.zeigeOnboarding {
                        OnboardingFenster.shared.oeffnen(
                            appState: appState,
                            beimAbschluss: { appDelegate.setup(appState: appState) },
                            abbrechenErlaubt: true,
                            ersterStart: true
                        )
                    }
                }
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Einstellungen...") {
                    EinstellungenFenster.shared.oeffnen(appState: appState)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }

        // Menüleisten-Icon wird vom AppDelegate via NSStatusItem verwaltet
        // (ermöglicht Animation beim Verarbeiten)
    }
}


// ------------------------------------------------------------
// Menüleisten-Dropdown
// ------------------------------------------------------------
struct MenuBarInhalt: View {
    @Environment(AppState.self) var appState

    var body: some View {
        @Bindable var appState = appState
        VStack(alignment: .leading, spacing: 4) {

            // Inbox-Status
            let anzahl = appState.inboxDateien.count
            Label(
                anzahl == 0 ? "Inbox: leer" : "Inbox: \(anzahl) Datei(en)",
                systemImage: anzahl == 0 ? "tray" : "tray.full"
            )
            .foregroundColor(anzahl == 0 ? .secondary : .primary)

            Divider()

            Button {
                NotificationCenter.default.post(name: .verarbeitenStarten, object: nil)
            } label: {
                Label("Jetzt verarbeiten", systemImage: "play.circle")
            }
            .disabled(appState.inboxDateien.isEmpty || appState.laeuft)
            .keyboardShortcut("p")

            Button {
                NSApp.activate(ignoringOtherApps: true)
                NotificationCenter.default.post(name: .fensterOeffnen, object: nil)
            } label: {
                Label("Fenster öffnen", systemImage: "macwindow")
            }
            .keyboardShortcut("f")

            Divider()

            Toggle(isOn: $appState.konfig.autoModus) {
                Label("Auto-Modus", systemImage: "bolt")
            }
            .onChange(of: appState.konfig.autoModus) {
                appState.konfigurationSpeichern()
            }

            Divider()

            Button {
                NSApp.activate(ignoringOtherApps: true)
                EinstellungenFenster.shared.oeffnen(appState: appState)
            } label: {
                Label("Einstellungen...", systemImage: "gear")
            }
            .keyboardShortcut(",")

            Button("Beenden") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .padding(8)
        .frame(minWidth: 200)
        .onAppear { appState.inboxLaden() }
    }
}


// ------------------------------------------------------------
// AppDelegate
// Startet den InboxWatcher und verbindet den VerarbeitungsService
// ------------------------------------------------------------
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var inboxWatcher:         FolderWatcher?
    private var verarbeitungsService: VerarbeitungsService?
    private var appState:             AppState?
    private var setupDone = false

    // Menüleisten-Icon
    private var statusItem:    NSStatusItem?
    private var animTimer:     Timer?
    private var animFrame:     Int = 0
    

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Dock-Darstellung aus Konfiguration laden
        let konfig = Konfiguration.laden()
        NSApp.setActivationPolicy(konfig.zeigeImDock ? .regular : .accessory)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(verarbeitenStarten),
            name:     .verarbeitenStarten,
            object:   nil
        )
        statusItemEinrichten()
    }

    private func statusItemEinrichten() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image      = MenuBarIcons.idle
        item.button?.imageScaling = .scaleProportionallyDown
        item.button?.action     = #selector(statusItemGeklickt)
        item.button?.target     = self

        // Dropdown-Menü
        let menu = NSMenu()
        menu.addItem(withTitle: "Stashfix",        action: nil,                    keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Fenster öffnen",  action: #selector(fensterOeffnen), keyEquivalent: "f")
        menu.addItem(withTitle: "Verarbeiten",     action: #selector(verarbeitenStarten), keyEquivalent: "p")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Einstellungen…",  action: #selector(einstellungenOeffnen), keyEquivalent: ",")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Beenden",         action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu

        statusItem = item
    }

    @objc private func statusItemGeklickt() {
        statusItem?.button?.performClick(nil)
    }

    @objc private func fensterOeffnen() {
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.post(name: .fensterOeffnen, object: nil)
    }

    @objc private func einstellungenOeffnen() {
        NSApp.activate(ignoringOtherApps: true)
        if let state = appState {
            EinstellungenFenster.shared.oeffnen(appState: state)
        }
    }

    func animationStarten() {
        guard animTimer == nil else { return }
        animFrame = 0
        animTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.statusItem?.button?.image = MenuBarIcons.activeFrames[self.animFrame % 8]
                self.animFrame = (self.animFrame + 1) % 8
            }
        }
    }

    func animationStoppen() {
        animTimer?.invalidate()
        animTimer = nil
        statusItem?.button?.image = MenuBarIcons.idle
    }

    func setup(appState: AppState) {
        guard !setupDone else { return }
        setupDone = true
        self.appState = appState
        verarbeitungsService = VerarbeitungsService(appState: appState)
        inboxBeobachten(appState: appState)
        dropAufFensterRegistrieren()

        // Animation wird via didSet in AppState.laeuft getriggert –
        // AppDelegate beobachtet über eine einfache Polling-Methode nicht nötig,
        // da VerarbeitungsService animationStarten/Stoppen direkt aufruft.
        // Stattdessen: AppDelegate stellt Callbacks bereit die der Service nutzt.
        verarbeitungsService?.onStart = { [weak self] in self?.animationStarten() }
        verarbeitungsService?.onStop  = { [weak self] in self?.animationStoppen() }
    }

    private func dropAufFensterRegistrieren() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard let window = NSApp.windows.first,
                  let appState = self.appState else { return }
            // DropView über gesamtes ContentView legen
            let dropView = FensterDropView(appState: appState)
            dropView.frame = window.contentView?.bounds ?? .zero
            dropView.autoresizingMask = [.width, .height]
            window.contentView?.addSubview(dropView)
        }
    }

    private func inboxBeobachten(appState: AppState) {
        let inbox = appState.konfig.archivPfad + "/_Inbox"
        inboxWatcher = FolderWatcher(pfad: inbox) {
            Task { @MainActor in
                appState.inboxLaden()
                if appState.konfig.autoModus && !appState.laeuft {
                    NotificationCenter.default.post(name: .verarbeitenStarten, object: nil)
                }
            }
        }
        inboxWatcher?.starten()
        appState.inboxLaden()
    }

    @objc private func verarbeitenStarten() {
        guard let service = verarbeitungsService else { return }
        Task { await service.alleVerarbeiten() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        verarbeitungsService?.ollamaBeenden()
    }
}


// ------------------------------------------------------------
// Notification-Namen
// ------------------------------------------------------------
extension Notification.Name {
    static let verarbeitenStarten = Notification.Name("verarbeitenStarten")
    static let fensterOeffnen     = Notification.Name("fensterOeffnen")
}


// ------------------------------------------------------------
// FensterDropView – transparente Drop-Zone über dem gesamten Fenster
// Umgeht NavigationSplitView-Einschränkung für onDrop
// ------------------------------------------------------------
class FensterDropView: NSView {
    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
        super.init(frame: .zero)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingPasteboard.availableType(from: [.fileURL]) != nil else { return [] }
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        // Jedes PasteboardItem einzeln auslesen – robuster bei mehreren Dateien
        let pb = sender.draggingPasteboard
        var urls: [URL] = []

        if let items = pb.pasteboardItems {
            for item in items {
                if let str = item.string(forType: .fileURL),
                   let url = URL(string: str) {
                    urls.append(url)
                }
            }
        }

        // Fallback auf readObjects falls pasteboardItems leer
        if urls.isEmpty,
           let fallback = pb.readObjects(forClasses: [NSURL.self],
               options: [.urlReadingFileURLsOnly: true]) as? [URL] {
            urls = fallback
        }

        let pdfs      = urls.filter { $0.pathExtension.lowercased() == "pdf" }
        let nichtPdfs = urls.filter { $0.pathExtension.lowercased() != "pdf" }

        if pdfs.isEmpty && !nichtPdfs.isEmpty {
            DispatchQueue.main.async {
                let alert             = NSAlert()
                alert.messageText     = "Nur PDFs unterstützt"
                alert.informativeText = "Stashfix verarbeitet ausschließlich PDF-Dateien."
                alert.runModal()
            }
            return false
        }

        guard !pdfs.isEmpty else { return false }

        let inbox = URL(fileURLWithPath: appState.konfig.archivPfad + "/_Inbox")
        let fm    = FileManager.default
        try? fm.createDirectory(at: inbox, withIntermediateDirectories: true)

        var kopiert = false
        for url in pdfs {
            let ziel = inbox.appendingPathComponent(url.lastPathComponent)
            guard !fm.fileExists(atPath: ziel.path) else { continue }
            try? fm.copyItem(at: url, to: ziel)
            kopiert = true
        }

        if kopiert {
            DispatchQueue.main.async { self.appState.inboxLaden() }
        }
        return true
    }

    // Transparent – blockiert keine Klicks auf darunterliegende Views
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
