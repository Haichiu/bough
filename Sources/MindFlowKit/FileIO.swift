import AppKit
import Foundation

public enum FileIO {
    /// One autosave slot per open tab.
    static var tabsDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MindFlow/tabs", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    static func autosaveTabs(_ entries: [(id: UUID, document: MindDocument)]) {
        let directory = tabsDirectory
        let keep = Set(entries.map { $0.id.uuidString })
        if let existing = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            // Cap deletions per pass so a huge backlog can never wedge the app.
            var removed = 0
            for url in existing where url.pathExtension == "mindmap" {
                if !keep.contains(url.deletingPathExtension().lastPathComponent) && removed < 2000 {
                    try? FileManager.default.removeItem(at: url)
                    removed += 1
                }
            }
        }
        for entry in entries {
            // Background saves must never surface a modal dialog.
            _ = writeQuiet(entry.document, to: directory.appendingPathComponent("\(entry.id.uuidString).mindmap"))
        }
    }

    /// Number of live autosave slots (used by regression checks).
    public static var tabSlotCount: Int {
        ((try? FileManager.default.contentsOfDirectory(at: tabsDirectory, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "mindmap" } ?? []).count
    }

    /// Restores previously open tabs, newest-modified first.
    /// The filename stem doubles as the stable session ID so slots get
    /// overwritten instead of accumulating under fresh names every launch.
    static func loadTabs() -> [(id: UUID, document: MindDocument)] {
        let directory = tabsDirectory
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey]))?
            .filter { $0.pathExtension == "mindmap" } ?? []
        let sorted = urls.sorted { lhs, rhs in
            let lDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return lDate > rDate
        }
        var result: [(id: UUID, document: MindDocument)] = []
        for url in sorted.prefix(20) {
            guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent),
                  let doc = load(from: url) else { continue }
            result.append((id: id, document: doc))
        }
        return result
    }

    /// Recoverable copies of closed tabs live here, never scanned as tabs.
    static var recoveryDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MindFlow/recovery", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    @discardableResult
    static func writeRecoveryCopy(_ document: MindDocument) -> Bool {
        let ok = writeQuiet(document, to: recoveryDirectory.appendingPathComponent("\(UUID().uuidString).mindmap"))
        pruneRecoveryCopies()
        return ok
    }

    /// Keeps the recovery folder bounded at the 50 newest copies.
    private static func pruneRecoveryCopies() {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: recoveryDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ))?.filter { $0.pathExtension == "mindmap" } ?? []
        guard urls.count > 50 else { return }
        let sorted = urls.sorted { lhs, rhs in
            let lDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return lDate > rDate
        }
        for url in sorted.dropFirst(50) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    static var autosaveURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MindFlow", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("autosave.mindmap")
    }

    @discardableResult
    static func write(_ document: MindDocument, to url: URL) -> Bool {
        writeQuiet(document, to: url)
    }

    /// Silent write for background paths; user-initiated saves surface errors via panels.
    @discardableResult
    static func writeQuiet(_ document: MindDocument, to url: URL) -> Bool {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(document)
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    static func load(from url: URL) -> MindDocument? {
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(MindDocument.self, from: data)
        } catch {
            return nil
        }
    }

    /// Shows a save panel; returns the chosen URL after writing, or nil when cancelled.
    static func saveAs(_ document: MindDocument) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = (document.root.text.isEmpty ? "未命名心智圖" : document.root.text) + ".mindmap"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return write(document, to: url) ? url : nil
    }

    static func openPanel() -> (MindDocument, URL)? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url, let doc = load(from: url) else { return nil }
        return (doc, url)
    }

    @discardableResult
    static func saveText(_ text: String, suggestedName: String) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            try Data(text.utf8).write(to: url, options: .atomic)
            return url
        } catch {
            NSAlert(error: error).runModal()
            return nil
        }
    }

    @discardableResult
    static func saveData(_ data: Data, suggestedName: String) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            NSAlert(error: error).runModal()
            return nil
        }
    }

    static func readText() -> (text: String, url: URL)? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return (text, url)
    }

    @discardableResult
    static func autosave(_ document: MindDocument) -> Bool {
        write(document, to: autosaveURL)
    }

    static func loadAutosave() -> MindDocument? {
        load(from: autosaveURL)
    }
}
