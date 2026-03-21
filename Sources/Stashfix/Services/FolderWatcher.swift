import Foundation
import AppKit

// ============================================================
// FolderWatcher.swift
// Überwacht einen Ordner auf neue PDF-Dateien.
// ============================================================

class FolderWatcher: @unchecked Sendable {
    private var source:       DispatchSourceFileSystemObject?
    private var fileDesc:     Int32 = -1
    private let pfad:         String
    private let onChange:     () -> Void
    private var letzteAnzahl: Int = 0

    init(pfad: String, onChange: @escaping () -> Void) {
        self.pfad     = pfad
        self.onChange = onChange
    }

    func starten() {
        stoppen()
        fileDesc = open(pfad, O_EVTONLY)
        guard fileDesc >= 0 else {
            print("FolderWatcher: Ordner nicht gefunden: \(pfad)")
            return
        }

        let pfadKopie = pfad
        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDesc,
            eventMask:      [.write, .rename, .attrib],
            queue:          DispatchQueue.global()
        )
        source?.setEventHandler { [weak self] in
            guard let self = self else { return }
            Thread.sleep(forTimeInterval: 1.0)
            let fm = FileManager.default
            guard let inhalt = try? fm.contentsOfDirectory(atPath: pfadKopie) else { return }
            let anzahl = inhalt.filter { $0.lowercased().hasSuffix(".pdf") }.count
            let alt    = self.letzteAnzahl
            self.letzteAnzahl = anzahl
            if anzahl > alt {
                Task { @MainActor in self.onChange() }
            }
        }
        source?.setCancelHandler { [weak self] in
            guard let self = self else { return }
            close(self.fileDesc)
            self.fileDesc = -1
        }
        source?.resume()
    }

    func stoppen() {
        source?.cancel()
        source = nil
    }
}
