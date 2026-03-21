import SwiftUI
import AppKit

// ============================================================
// EinstellungenFenster.swift
// ============================================================

@MainActor
class EinstellungenFenster {
    static let shared = EinstellungenFenster()
    private var fenster: NSWindow?

    func oeffnen(appState: AppState) {
        if let existing = fenster, existing.isVisible {
            NSApp.activate(ignoringOtherApps: true)
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let view    = EinstellungenView().environment(appState)
        let hosting = NSHostingController(rootView: view)
        let window  = NSWindow(contentViewController: hosting)
        window.title          = "Einstellungen"
        window.styleMask      = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 580, height: 520))
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        fenster = window
    }
}
