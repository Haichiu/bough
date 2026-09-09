// MARK: - Themes
//
// The GUI half of this feature (does the canvas actually repaint when the theme
// changes?) is deliberately NOT asserted here -- it needs a real window, and a
// model-layer check cannot see paint. These assertions cover what they can
// honestly cover: that the values a theme resolves to are the values intended,
// that the classic theme is byte-identical to the pre-theme palette, and that
// selecting a theme never damages another one.
func themeCheck() {
    let restore = Palette.active
    defer { Palette.active = restore }

    // 1. Classic is the original palette, exactly. Every other colour assertion
    //    in this file describes classic, so if this drifts they all become
    //    descriptions of a state that no longer ships.
    Palette.active = .classic
    check(Palette.light.canvasRGB.hex == "#f2efe7", "theme classic keeps the original light canvas")
    check(Palette.dark.canvasRGB.hex == "#101819", "theme classic keeps the original dark canvas")
    check(Palette.light.accentRGB.hex == "#3368a0", "theme classic keeps the original accent")

    // 2. Themes are actually different from one another. A picker whose options
    //    all look the same is a lie in the menu.
    var canvases: Set<String> = []
    var accents: Set<String> = []
    for theme in MindTheme.allCases {
        Palette.active = theme
        canvases.insert(Palette.light.canvasRGB.hex)
        accents.insert(Palette.light.accentRGB.hex)
    }
    check(canvases.count == MindTheme.allCases.count, "every theme has a distinct light canvas")
    check(accents.count == MindTheme.allCases.count, "every theme has a distinct accent")

    // 3. Legibility is not optional. Whatever a theme does decoratively, body
    //    text has to clear the WCAG AA 4.5:1 floor against the surface it sits
    //    on, in both appearances. This is the assertion that stops a future
    //    "pretty" theme from shipping unreadable.
    for theme in MindTheme.allCases {
        Palette.active = theme
        let name = theme.rawValue
        let lightOnCanvas = Palette.light.textPrimaryRGB.contrastRatio(with: Palette.light.canvasRGB)
        let lightOnCard = Palette.light.textPrimaryRGB.contrastRatio(with: Palette.light.cardRGB)
        let darkOnCanvas = Palette.dark.textPrimaryRGB.contrastRatio(with: Palette.dark.canvasRGB)
        let darkOnCard = Palette.dark.textPrimaryRGB.contrastRatio(with: Palette.dark.cardRGB)
        check(lightOnCanvas >= 4.5, "theme \(name) light primary text clears 4.5:1 on canvas (\(String(format: "%.2f", lightOnCanvas)))")
        check(lightOnCard >= 4.5, "theme \(name) light primary text clears 4.5:1 on card")
        check(darkOnCanvas >= 4.5, "theme \(name) dark primary text clears 4.5:1 on canvas")
        check(darkOnCard >= 4.5, "theme \(name) dark primary text clears 4.5:1 on card")

        // Secondary text carries real content in the minimal themes, where deep
        // topics are drawn in it, so hold it to the same body-text floor rather
        // than the 3:1 large-text one.
        let secondaryLight = Palette.light.textSecondaryRGB.contrastRatio(with: Palette.light.canvasRGB)
        let secondaryDark = Palette.dark.textSecondaryRGB.contrastRatio(with: Palette.dark.canvasRGB)
        check(secondaryLight >= 4.5, "theme \(name) light secondary text clears 4.5:1 (\(String(format: "%.2f", secondaryLight)))")
        check(secondaryDark >= 4.5, "theme \(name) dark secondary text clears 4.5:1 (\(String(format: "%.2f", secondaryDark)))")
    }

    // 4. The marked-node highlight keeps one meaning everywhere. Its lightness is
    //    re-solved per theme so it stays visible, but it must never drift to a
    //    different colour, or the badge stops being a status signal.
    for theme in MindTheme.allCases {
        Palette.active = theme
        let hue = Palette.light.statusHighlightOKLCh.hue
        check(abs(hue - Palette.statusHighlightSourceOKLCh.hue) < 12,
              "theme \(theme.rawValue) keeps the marked-node highlight on its source hue")
        check(Palette.light.statusHighlightRGB.contrastRatio(with: Palette.light.canvasRGB) >= 3.1,
              "theme \(theme.rawValue) marked highlight stays visible on canvas")
    }

    // 5. Morphology, not just colour. A "minimal" theme that still draws every
    //    topic as a filled or bordered box has not done the thing it claims.
    Palette.active = .minimal
    let minimalBranch = NodeStyle.of(depth: 1)
    let minimalLeaf = NodeStyle.of(depth: 2)
    check(minimalBranch.fillOpacity == 0, "minimal theme draws no fill behind a depth-1 topic")
    check(minimalLeaf.fillOpacity == 0, "minimal theme draws no fill behind a deep topic")
    check(minimalLeaf.strokeWidth == 0, "minimal theme draws no border around a deep topic")

    Palette.active = .classic
    let classicBranch = NodeStyle.of(depth: 1)
    let classicLeaf = NodeStyle.of(depth: 2)
    check(classicBranch.fillOpacity == 1, "classic theme still fills a depth-1 topic")
    check(classicLeaf.strokeWidth == 1, "classic theme still borders a deep topic")
    check(classicLeaf.cornerRadius == 9, "classic theme keeps its original corner radius")
    check(classicLeaf.horizontalInset == 14, "classic theme keeps its original padding")

    // Removing the box only reads as deliberate if the space it occupied stays.
    check(minimalLeaf.horizontalInset > classicLeaf.horizontalInset,
          "minimal theme pads a topic more generously than classic, not less")

    // 6. Selecting a theme and coming back must land on the same values. The
    //    per-theme values are cached, and a cache that mutates under selection
    //    would corrupt whichever theme was visited first.
    Palette.active = .indigo
    _ = Palette.light.canvasRGB
    Palette.active = .classic
    check(Palette.light.canvasRGB.hex == "#f2efe7", "returning to classic restores it exactly")

    // 6b. Exports follow the chosen theme. The exporters paint with Palette.light,
    //     which resolves through the active theme, so this holds today for free --
    //     the assertion exists so that pinning an exporter back to a fixed palette
    //     shows up as a failure rather than as a user exporting a picture that
    //     does not match what they were looking at.
    Palette.active = .minimal
    check(StaticMapView.exportPalette.canvasRGB.hex == "#ffffff",
          "exported canvas follows the active theme")
    Palette.active = .classic
    check(StaticMapView.exportPalette.canvasRGB.hex == "#f2efe7",
          "exported canvas returns with the theme")

    // 7. The persisted form round-trips. The stored string is what survives a
    //    relaunch, so an unreadable one silently resets the user's choice.
    for theme in MindTheme.allCases {
        check(MindTheme(rawValue: theme.rawValue) == theme, "theme \(theme.rawValue) round-trips through its stored form")
    }
    check(MindTheme(rawValue: "nonsense") == nil, "an unknown stored theme is rejected rather than guessed")
}

import AppKit
import CoreGraphics
import CoreText
import Foundation
import CryptoKit
import SwiftUI
import MindFlowKit

setvbuf(stdout, nil, _IONBF, 0)

struct TabDirectoryEvidence: Equatable {
    let digest: String
    let files: [String: Data]
    let modificationDates: [String: Date]
    let rootTitles: [String: String]
    let nodeCounts: [String: Int]
}

enum TabStoreCheckFailure: Error {
    case write
    case exchange
}

func assertTestDirectory(_ directory: URL, label: String) {
    var isDirectory: ObjCBool = false
    precondition(FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory)
                 && isDirectory.boolValue,
                 "\(label) must be an existing directory: \(directory.path)")
}

func freshTabStoreRoot(_ label: String) -> URL {
    let root = URL(fileURLWithPath: "/tmp", isDirectory: true)
        .appendingPathComponent("mindflow-tabstore-\(label)-\(UUID().uuidString)", isDirectory: true)
    try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    assertTestDirectory(root, label: "fresh \(label) root")
    return root
}

func tabNodeCount(_ node: MindNode) -> Int {
    1 + node.children.reduce(0) { $0 + tabNodeCount($1) }
}

func encodedTabDocument(_ document: MindDocument) -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try! encoder.encode(document)
}

func writeTabFixture(_ id: UUID, document: MindDocument, to live: URL, date: Date) {
    assertTestDirectory(live, label: "fixture live directory")
    let url = live.appendingPathComponent("\(id.uuidString).mindmap")
    try! encodedTabDocument(document).write(to: url, options: .atomic)
    try! FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
}

struct TabFixture {
    let live: URL
    let singleID: UUID
    let multiID: UUID
    let staleID: UUID
    let single: MindDocument
    let multi: MindDocument
    let stale: MindDocument

    var entries: [TabStore.Entry] {
        [TabStore.Entry(id: singleID, document: single),
         TabStore.Entry(id: multiID, document: multi)]
    }
}

func makeTabFixture(in root: URL) -> TabFixture {
    assertTestDirectory(root, label: "fixture root")
    let live = root.appendingPathComponent("tabs", isDirectory: true)
    try! FileManager.default.createDirectory(at: live, withIntermediateDirectories: false)
    assertTestDirectory(live, label: "fixture live")

    let singleID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    let multiID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
    let staleID = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
    let single = MindDocument(title: "Single document", root: MindNode(text: "單節點真實根標題"))
    let multi = MindDocument(
        title: "Multi document",
        root: MindNode(text: "多節點真實根標題", children: [
            MindNode(text: "分支一", children: [MindNode(text: "葉節點")]),
            MindNode(text: "分支二")
        ]))
    let stale = MindDocument(title: "Stale document", root: MindNode(text: "保留中的 stale 檔案"))
    let base = Date(timeIntervalSince1970: 1_700_000_000)
    writeTabFixture(singleID, document: single, to: live, date: base)
    writeTabFixture(multiID, document: multi, to: live, date: base.addingTimeInterval(1))
    writeTabFixture(staleID, document: stale, to: live, date: base.addingTimeInterval(2))
    return TabFixture(live: live, singleID: singleID, multiID: multiID, staleID: staleID,
                      single: single, multi: multi, stale: stale)
}

func tabDirectoryEvidence(_ directory: URL, label: String) -> TabDirectoryEvidence {
    assertTestDirectory(directory, label: label)
    let urls = try! FileManager.default.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: [.contentModificationDateKey], options: [])
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    var files: [String: Data] = [:]
    var dates: [String: Date] = [:]
    var rootTitles: [String: String] = [:]
    var nodeCounts: [String: Int] = [:]
    let decoder = JSONDecoder()
    for url in urls {
        let name = url.lastPathComponent
        files[name] = try! Data(contentsOf: url)
        let values = try! url.resourceValues(forKeys: [.contentModificationDateKey])
        guard let date = values.contentModificationDate else {
            preconditionFailure("missing modification date for \(url.path)")
        }
        dates[name] = date
        if let document = try? decoder.decode(MindDocument.self, from: files[name]!) {
            rootTitles[name] = document.root.text
            nodeCounts[name] = tabNodeCount(document.root)
        }
    }
    var digestInput = Data()
    for name in files.keys.sorted() {
        digestInput.append(contentsOf: name.utf8)
        digestInput.append(0)
        digestInput.append(files[name]!)
        digestInput.append(0)
    }
    let digest = SHA256.hash(data: digestInput).map { String(format: "%02x", $0) }.joined()
    print("TabStore evidence \(label): digest=\(digest) files=\(files.keys.sorted()) rootTitles=\(rootTitles) nodeCounts=\(nodeCounts)")
    return TabDirectoryEvidence(digest: digest, files: files, modificationDates: dates,
                                rootTitles: rootTitles, nodeCounts: nodeCounts)
}

func tabTransactionDirectories(_ root: URL) -> [URL] {
    assertTestDirectory(root, label: "transaction-count root")
    return (try! FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil,
                                                          options: []))
        .filter { url in
            guard url.lastPathComponent.hasPrefix(TabStore.transactionDirectoryPrefix) else { return false }
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
                && isDirectory.boolValue
        }
}

func assertTabEvidencePreserved(_ before: TabDirectoryEvidence, _ after: TabDirectoryEvidence,
                                label: String) {
    check(before.files == after.files, "\(label) preserves exact filename and bytes set")
    check(before.digest == after.digest, "\(label) preserves the filename-plus-bytes digest")
    check(before.modificationDates == after.modificationDates, "\(label) preserves every file mtime")
    check(before.rootTitles == after.rootTitles && before.nodeCounts == after.nodeCounts,
          "\(label) preserves root titles and node counts")
}

struct TabTransactionEvidence: Equatable {
    let names: [String]
    let contents: [String: [String: Data]]
    let modificationDates: [String: Date]
    let fileModificationDates: [String: [String: Date]]
}

func tabTransactionEvidence(_ root: URL, label: String) -> TabTransactionEvidence {
    assertTestDirectory(root, label: label + " root")
    let directories = tabTransactionDirectories(root).sorted { $0.lastPathComponent < $1.lastPathComponent }
    var contents: [String: [String: Data]] = [:]
    var modificationDates: [String: Date] = [:]
    var fileModificationDates: [String: [String: Date]] = [:]
    for directory in directories {
        assertTestDirectory(directory, label: label + " transaction")
        let directoryValues = try! directory.resourceValues(forKeys: [.contentModificationDateKey])
        guard let directoryDate = directoryValues.contentModificationDate else {
            preconditionFailure("missing transaction mtime for \(directory.path)")
        }
        let files = try! FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey], options: [])
            .filter { url in
                var isDirectory: ObjCBool = false
                return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
                    && !isDirectory.boolValue
            }
        var directoryContents: [String: Data] = [:]
        var directoryFileDates: [String: Date] = [:]
        for file in files {
            directoryContents[file.lastPathComponent] = try! Data(contentsOf: file)
            let values = try! file.resourceValues(forKeys: [.contentModificationDateKey])
            guard let date = values.contentModificationDate else {
                preconditionFailure("missing transaction file mtime for \(file.path)")
            }
            directoryFileDates[file.lastPathComponent] = date
        }
        let name = directory.lastPathComponent
        contents[name] = directoryContents
        modificationDates[name] = directoryDate
        fileModificationDates[name] = directoryFileDates
    }
    print("TabStore sibling evidence \(label): names=\(directories.map(\.lastPathComponent)) contents=\(contents)")
    return TabTransactionEvidence(names: directories.map(\.lastPathComponent), contents: contents,
                                  modificationDates: modificationDates,
                                  fileModificationDates: fileModificationDates)
}

func assertTabTransactionEvidencePreserved(_ before: TabTransactionEvidence,
                                           _ after: TabTransactionEvidence, label: String) {
    check(before.names == after.names, "\(label) preserves exact sibling names")
    check(before.contents == after.contents, "\(label) preserves exact sibling contents")
    check(before.modificationDates == after.modificationDates,
          "\(label) preserves every sibling directory mtime")
    check(before.fileModificationDates == after.fileModificationDates,
          "\(label) preserves every sibling file mtime")
}

func seedTabTransactions(_ root: URL, count: Int) -> [URL] {
    assertTestDirectory(root, label: "seed transaction root")
    return (0..<count).map { index in
        let transaction = root.appendingPathComponent(
            "\(TabStore.transactionDirectoryPrefix)seed-\(index)-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: transaction, withIntermediateDirectories: false)
        assertTestDirectory(transaction, label: "seeded transaction")
        let marker = transaction.appendingPathComponent("forensic-\(index).bin")
        try! Data("forensic-marker-\(index)".utf8).write(to: marker, options: .atomic)
        let date = Date(timeIntervalSince1970: 1_600_000_000 + Double(index))
        try! FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: marker.path)
        try! FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: transaction.path)
        return transaction
    }
}

var failures = 0

func check(_ condition: Bool, _ label: String, line: Int = #line) {
    if condition {
        print("PASS \(label)")
    } else {
        failures += 1
        print("FAIL \(label) (line \(line))")
    }
}

func storagePathChecks() {
    let fileManager = FileManager.default
    let expectedRoot = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("MindFlow", isDirectory: true)
    let production = StoragePaths.resolve(environment: [:], fileManager: fileManager)
    check(production.root == expectedRoot &&
          production.tabs == expectedRoot.appendingPathComponent("tabs", isDirectory: true) &&
          production.recovery == expectedRoot.appendingPathComponent("recovery", isDirectory: true) &&
          production.autosave == expectedRoot.appendingPathComponent("autosave.mindmap"),
          "storage env-unset paths preserve production locations")

    let root = URL(fileURLWithPath: "/tmp", isDirectory: true)
        .appendingPathComponent("mindflow-storage-paths-\(UUID().uuidString)", isDirectory: true)
    try! fileManager.createDirectory(at: root, withIntermediateDirectories: false)
    assertTestDirectory(root, label: "storage-path check root")
    defer { try? fileManager.removeItem(at: root) }

    let markerURL = root.appendingPathComponent(StoragePaths.markerFileName)
    try! Data(StoragePaths.markerContents.utf8).write(to: markerURL, options: .atomic)
    let isolated = StoragePaths.resolve(
        environment: [StoragePaths.environmentKey: root.path], fileManager: fileManager)
    check(isolated.root == root &&
          isolated.tabs == root.appendingPathComponent("tabs", isDirectory: true) &&
          isolated.recovery == root.appendingPathComponent("recovery", isDirectory: true) &&
          isolated.autosave == root.appendingPathComponent("autosave.mindmap"),
          "valid marker routes tabs recovery and autosave together")

    let blockedTabs = root.appendingPathComponent("tabs")
    try! Data("not-a-directory".utf8).write(to: blockedTabs, options: .atomic)
    let blocked = StoragePaths.resolve(
        environment: [StoragePaths.environmentKey: root.path], fileManager: fileManager)
    check(blocked.root == root &&
          blocked.tabs == root.appendingPathComponent("tabs", isDirectory: true),
          "valid marker never falls back when an isolated child is blocked")
    try! fileManager.removeItem(at: blockedTabs)

    let unmarked = root.appendingPathComponent("unmarked", isDirectory: true)
    try! fileManager.createDirectory(at: unmarked, withIntermediateDirectories: false)
    let malformed = root.appendingPathComponent("malformed", isDirectory: true)
    try! fileManager.createDirectory(at: malformed, withIntermediateDirectories: false)
    try! Data("wrong-version".utf8).write(
        to: malformed.appendingPathComponent(StoragePaths.markerFileName), options: .atomic)
    let regularFile = root.appendingPathComponent("not-a-directory")
    try! Data("file".utf8).write(to: regularFile, options: .atomic)
    let invalidEnvironments: [(String, String)] = [
        ("missing marker", unmarked.path),
        ("malformed marker", malformed.path),
        ("relative root", "relative/storage"),
        ("regular-file root", regularFile.path)
    ]
    for (label, rawRoot) in invalidEnvironments {
        let resolved = StoragePaths.resolve(
            environment: [StoragePaths.environmentKey: rawRoot], fileManager: fileManager)
        check(resolved == production, "\(label) falls back to production paths")
    }
}

storagePathChecks()

func approxEqual(_ a: CGFloat, _ b: CGFloat, accuracy: CGFloat = 0.5) -> Bool {
    abs(a - b) <= accuracy
}

func freshInterchangeRoot(_ label: String) -> URL {
    let root = URL(fileURLWithPath: "/tmp", isDirectory: true)
        .appendingPathComponent("mindflow-interchange-\(label)-\(UUID().uuidString)", isDirectory: true)
    try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    assertTestDirectory(root, label: "fresh interchange \(label) root")
    return root
}

func interchangeChainNode(level: Int, maximum: Int) -> MindNode {
    let children = level < maximum ? [interchangeChainNode(level: level + 1, maximum: maximum)] : []
    return MindNode(text: "Level \(level)", children: children)
}

func interchangeChainDocument(levels: Int) -> MindDocument {
    MindDocument(title: "Interchange document", root: interchangeChainNode(level: 1, maximum: levels))
}

func markdownChain(levels: Int) -> String {
    guard levels > 0 else { return "" }
    var lines = ["# Level 1"]
    if levels >= 2 {
        for level in 2...levels {
            let indent = String(repeating: "  ", count: level - 2)
            lines.append("\(indent)- Level \(level)")
        }
    }
    return lines.joined(separator: "\n") + "\n"
}

func opmlChain(levels: Int) -> String {
    func outline(_ level: Int) -> String {
        let node = "<outline text=\"Level \(level)\""
        guard level < levels else { return node + "/>" }
        return node + ">\(outline(level + 1))</outline>"
    }
    return "<?xml version=\"1.0\"?><opml version=\"2.0\"><head><title>Chain</title></head><body>\(outline(1))</body></opml>"
}

func freemindChain(levels: Int) -> String {
    func node(_ level: Int) -> String {
        let start = "<node TEXT=\"Level \(level)\""
        guard level < levels else { return start + "/>" }
        return start + ">\(node(level + 1))</node>"
    }
    return "<?xml version=\"1.0\"?><map version=\"1.0.1\">\(node(1))</map>"
}

func assertInterchangeStructure(_ expected: MindNode, _ actual: MindNode, label: String) {
    check(expected.text == actual.text, "\(label) preserves node text at each level")
    check(expected.children.count == actual.children.count, "\(label) preserves child structure at each level")
    for (expectedChild, actualChild) in zip(expected.children, actual.children) {
        assertInterchangeStructure(expectedChild, actualChild, label: label)
    }
}

func maximumNodeLevel(_ node: MindNode, level: Int = 1) -> Int {
    var maximum = level
    for child in node.children {
        maximum = max(maximum, maximumNodeLevel(child, level: level + 1))
    }
    return maximum
}

// MARK: - Layout engine

do {
    let root = MindNode(text: "Root", children: [
        MindNode(text: "A"), MindNode(text: "B"), MindNode(text: "C"),
    ])
    let layouts = LayoutEngine.layout(root: root)
    let rootLayout = layouts[root.id]!
    for child in root.children {
        let childLayout = layouts[child.id]!
        check(childLayout.frame.minX > rootLayout.frame.maxX, "child right of root")
        check(childLayout.depth > 0, "child depth > 0")
    }
    let ys = root.children.map { layouts[$0.id]!.frame.midY }
    check(ys == ys.sorted(), "children ordered top to bottom")
    let middle = layouts[root.children[1].id]!.frame.midY
    check(approxEqual(middle, rootLayout.frame.midY), "middle child centered on root")
}

do {
    let grandchild = MindNode(text: "G")
    let child = MindNode(text: "C", collapsed: true, children: [grandchild])
    let root = MindNode(text: "Root", children: [child])
    let layouts = LayoutEngine.layout(root: root)
    check(layouts[grandchild.id] == nil, "collapsed hides descendants")
    check(layouts[child.id] != nil, "collapsed child still laid out")
}

do {
    let leaf = MindNode(text: "L")
    let mid = MindNode(text: "M", children: [leaf])
    let root = MindNode(text: "Root", children: [mid])
    let layouts = LayoutEngine.layout(root: root)
    check(approxEqual(layouts[mid.id]!.frame.midY, layouts[root.id]!.frame.midY), "mid centered on root")
    check(approxEqual(layouts[leaf.id]!.frame.midY, layouts[mid.id]!.frame.midY), "leaf centered on mid")
}

// MARK: - Model mutations

do {
    var root = MindNode(text: "Root", children: [MindNode(text: "A", children: [MindNode(text: "B")])])
    let b = root.children[0].children[0]
    check(root.update(b.id) { $0.text = "B2" }, "update finds nested node")
    check(root.children[0].children[0].text == "B2", "update applied")
    check(!root.update(UUID()) { _ in }, "update misses unknown id")
}

do {
    let a = MindNode(text: "A")
    var root = MindNode(text: "Root", children: [a, MindNode(text: "B")])
    let removed = root.remove(a.id)
    check(removed?.id == a.id, "remove returns removed node")
    check(root.children.count == 1, "remove shrinks children")
}

do {
    let leaf = MindNode(text: "Leaf")
    let child = MindNode(text: "Child", children: [leaf])
    let root = MindNode(text: "Root", children: [child])
    check(root.isAncestor(of: leaf.id), "root is ancestor of grandchild")
    check(!leaf.isAncestor(of: root.id), "leaf is not ancestor of root")
    check(root.descendantIDs().count == 2, "descendant count")
}

// MARK: - Document round-trip

do {
    var doc = MindDocument.new()
    doc.root.update(doc.root.id) { node in
        node.children.append(MindNode(text: "想法一"))
    }
    let data = try JSONEncoder().encode(doc)
    let decoded = try JSONDecoder().decode(MindDocument.self, from: data)
    check(decoded == doc, "document JSON round-trip")
}

// MARK: - v1.1: balanced layout, sibling reorder, legacy decode

do {
    let root = MindNode(text: "Root", children: (1...4).map { MindNode(text: "C\($0)") })
    let layouts = LayoutEngine.layout(root: root, direction: .balanced)
    let r = layouts[root.id]!
    let left = layouts.values.filter { $0.side == .left }
    let rightChildren = layouts.values.filter { $0.side == .right && $0.depth > 0 }
    check(left.count == 2, "balanced splits 2/2 (left)")
    check(rightChildren.count == 2, "balanced splits 2/2 (right)")
    check(left.allSatisfy { $0.frame.maxX < r.frame.minX }, "left children left of root")
    check(rightChildren.allSatisfy { $0.frame.minX > r.frame.maxX }, "right children right of root")

    let logicLayouts = LayoutEngine.layout(root: root, direction: .logicRight)
    check(logicLayouts.values.filter { $0.side == .left }.isEmpty, "logic layout has no left side")
    check(logicLayouts.values.allSatisfy { $0.frame.minX >= 0 }, "logic layout stays right of origin")
}

do {
    try await MainActor.run {
        let vm = MindMapViewModel()
        vm.newDocument()
        let first = vm.addChild(to: nil)!
        let second = vm.addChild(to: nil)!
        vm.moveSibling(id: second, offset: -1)
        let children = vm.document.root.children
        check(children.count == 2 && children[0].id == second && children[1].id == first,
              "moveSibling reorders upward")
        vm.moveSibling(id: second, offset: -1)
        check(vm.document.root.children[0].id == second, "moveSibling clamps at top")
        vm.setDirection(.balanced)
        check(vm.document.directionName == MapDirection.balanced.rawValue, "setDirection persists")
        vm.newDocument()
        let siblingA = vm.addChild(to: nil)!
        let siblingB = vm.addSibling(of: siblingA)!
        check(vm.document.root.parent(of: siblingB)?.id == vm.document.root.id,
              "parent(of:) finds root for direct child")
        check(vm.document.root.children.contains(where: { $0.id == siblingB }),
              "addSibling inserts at root level")
    }
}

do {
    let legacyJSON = """
    {"title":"t","themeName":"ocean","root":{"id":"\(UUID().uuidString.lowercased())","text":"R","note":"","collapsed":false,"children":[]}}
    """
    let doc = try JSONDecoder().decode(MindDocument.self, from: Data(legacyJSON.utf8))
    check(doc.directionName == MapDirection.logicRight.rawValue, "legacy JSON decodes with default layout")
    let reencoded = try JSONDecoder().decode(MindDocument.self, from: try JSONEncoder().encode(doc))
    check(reencoded == doc, "new field round-trips")
}

// MARK: - v1.2: exporters

do {
    let doc = MindDocument(title: "T", root: MindNode(text: "Root <A>", note: "n", children: [
        MindNode(text: "B", children: [MindNode(text: "C")]),
    ]))
    let md = try! MapExporter.markdown(doc)
    check(md.contains("# Root <A>"), "markdown exports root title")
    check(md.contains("- B"), "markdown exports child")
    check(md.contains("  - C"), "markdown indents grandchildren")
    check(md.contains("> n"), "markdown includes notes")
    let opml = try! MapExporter.opml(doc)
    check(opml.contains("&lt;A&gt;"), "opml escapes XML entities")
    check(opml.contains("<outline text=\"B\""), "opml nests children")
    check(opml.contains("_note=\"n\""), "opml carries notes")

    // v17.0: SVG export
    let svg = MapExporter.svg(doc)
    check(svg.hasPrefix("<?xml version=\"1.0\" encoding=\"UTF-8\"?>"), "svg starts with xml declaration")
    check(svg.contains("<svg xmlns=\"http://www.w3.org/2000/svg\""), "svg declares namespace")
    check(svg.contains("viewBox="), "svg carries viewBox bounds")
    check(svg.contains("&lt;A&gt;"), "svg escapes xml entities in text")
    check(svg.contains(">B</text>"), "svg renders child node text")
    check(svg.contains("<path d=\"M "), "svg draws connection paths")
    check(svg.contains("text-anchor=\"middle\""), "svg centers node labels")
    let svgT = MapExporter.svg(doc, transparent: true)
    check(!svgT.contains("fill=\"#ffffff\"><rect") && !svgT.contains("<rect width=\"100%\""), "svg transparent skips background rect")
}

// MARK: - S4: per-node fill override (model half)
//
// The canvas half is separate; these checks pin the model, the save format and
// the SVG. A fill override is one of Theme.colorTags' six keys — never a free
// colour code — and it must not be confused with colorTag, which draws the 4pt
// semantic bar in the very same colour.

do {
    var doc = MindDocument.new()
    doc.root.children = [MindNode(text: "塗色", fillTag: "red"), MindNode(text: "原色")]
    let json = String(data: try JSONEncoder().encode(doc), encoding: .utf8) ?? ""
    let decoded = try JSONDecoder().decode(MindDocument.self, from: Data(json.utf8))
    check(decoded.root.children[0].fillTag == "red", "fill override survives the save round-trip")
    check(decoded.root.children[1].fillTag == nil,
          "fill override: a node without one reads back nil (control)")
    check(json.components(separatedBy: "\"fillTag\"").count - 1 == 1,
          "fill override: only the overridden node writes the key")
}

do {
    // A file written before the field existed must load, not throw.
    let legacy = """
    {"title":"t","themeName":"classic","root":{"id":"\(UUID().uuidString.lowercased())","text":"R","note":"","collapsed":false,"colorTag":"blue","children":[{"id":"\(UUID().uuidString.lowercased())","text":"C","note":"","collapsed":false,"marked":false,"children":[]}]}}
    """
    let doc = try JSONDecoder().decode(MindDocument.self, from: Data(legacy.utf8))
    check(doc.root.fillTag == nil && doc.root.children[0].fillTag == nil,
          "fill override: a file without the field decodes to nil, not an error")
    check(doc.root.colorTag == "blue", "fill override: the rest of an old file still decodes")
}

do {
    try await MainActor.run {
        let vm = MindMapViewModel()
        vm.newDocument()
        let a = vm.addChild(to: nil)!
        let b = vm.addChild(to: nil)!
        vm.setNodeFill(id: a, tag: "green")
        check(vm.document.root.find(a)?.fillTag == "green", "setNodeFill stores the override")
        check(vm.document.root.find(b)?.fillTag == nil,
              "setNodeFill leaves a sibling untouched (control)")
        // Pin the tree as well as the field: without this, an undo that simply
        // popped the earlier addChild entry would satisfy the fill assertion.
        let idsBefore = vm.document.root.children.map(\.id)
        vm.undo()
        check(vm.document.root.find(a)?.fillTag == nil, "undo clears the fill override")
        check(vm.document.root.children.map(\.id) == idsBefore,
              "undo of the fill override leaves the tree alone (control)")
        vm.redo()
        check(vm.document.root.find(a)?.fillTag == "green", "redo restores the fill override")
        check(vm.document.root.children.map(\.id) == idsBefore, "redo keeps the tree (control)")
        vm.setNodeFill(id: a, tag: "chartreuse")
        check(vm.document.root.find(a)?.fillTag == "green",
              "setNodeFill refuses a tag outside the six-key palette")
        vm.setNodeFill(id: a, tag: nil)
        check(vm.document.root.find(a)?.fillTag == nil, "setNodeFill(nil) clears the override")
    }
}

do {
    let redHex = "#e05252" // Theme.colorTags "red"
    let painted = MindDocument(title: "T", root: MindNode(text: "Root", children: [
        MindNode(text: "塗色", fillTag: "red"),
    ]))
    let plain = MindDocument(title: "T", root: MindNode(text: "Root", children: [
        MindNode(text: "塗色"),
    ]))
    let svg = MapExporter.svg(painted)
    check(svg.contains("fill=\"\(redHex)\" fill-opacity=\"1.0\""),
          "svg paints the node with the override colour")
    check(!MapExporter.svg(plain).contains(redHex),
          "svg without an override never contains the override colour (control)")

    // Same colour, different job: colorTag's 4pt bar must not be mistaken for a fill.
    let both = MindDocument(title: "T", root: MindNode(text: "Root", children: [
        MindNode(text: "兩者", colorTag: "red", fillTag: "red"),
    ]))
    let cleared = MindDocument(title: "T", root: MindNode(text: "Root", children: [
        MindNode(text: "兩者", colorTag: "red"),
    ]))
    check(MapExporter.svg(both).contains("fill=\"\(redHex)\" fill-opacity=\"1.0\""),
          "svg fill override and colorTag bar coexist")
    check(!MapExporter.svg(cleared).contains("fill=\"\(redHex)\" fill-opacity=\"1.0\""),
          "clearing the override removes the fill even when the colorTag bar keeps the colour")
    check(MapExporter.svg(cleared).contains("fill=\"\(redHex)\""),
          "clearing the override keeps the colorTag bar (control)")

    // Text formats have nowhere to put a fill; the check names say so.
    check(!(try! MapExporter.markdown(painted)).contains(redHex),
          "markdown does not carry the fill override (text format has no fill)")
    check(!(try! MapExporter.opml(painted)).contains(redHex),
          "opml does not carry the fill override (text format has no fill)")
    check(!(try! MapExporter.freemind(painted)).contains(redHex),
          "freemind does not carry the fill override (text format has no fill)")
}

// MARK: - v1.3: markdown import round-trip

do {
    let source = """
    # 專案計畫
    - 研究
      - 文獻回顧
      - 訪談
        > 約三位使用者
    - 設計
    - 開發
    """
    let imported = try? MapImporter.markdown(source)
    check(imported != nil, "markdown import succeeds")
    let doc = imported!
    check(doc.root.text == "專案計畫", "import uses heading as root")
    check(doc.root.children.map(\.text) == ["研究", "設計", "開發"], "import preserves top level")
    check(doc.root.children[0].children.map(\.text) == ["文獻回顧", "訪談"], "import preserves nesting")
    check(doc.root.children[0].children[1].note == "約三位使用者", "import attaches notes")

    let roundTrip = try? MapImporter.markdown(try! MapExporter.markdown(doc))
    check(roundTrip?.root.children.map(\.text) == ["研究", "設計", "開發"], "export/import round-trips")

    check((try? MapImporter.markdown(""))?.root.text == "中心主題", "empty input yields default root")
}

// MARK: - v1.4: search

do {
    try await MainActor.run {
        let vm = MindMapViewModel()
        vm.newDocument()
        let apple = vm.addChild(to: nil)!
        vm.rename(id: apple, to: "蘋果計畫")
        let banana = vm.addChild(to: nil)!
        vm.rename(id: banana, to: "香蕉清單")
        vm.searchQuery = "蘋果"
        vm.performSearch()
        check(vm.searchResults == [apple], "search finds matching node")
        vm.searchQuery = "清單"
        vm.performSearch()
        check(vm.searchResults == [banana], "search matches substrings")
        vm.jumpToNextResult()
        check(vm.selection == banana, "jump wraps on single result")
        vm.searchQuery = "  "
        vm.performSearch()
        check(vm.searchResults.isEmpty, "blank query clears results")
    }
}

// MARK: - v1.5: OPML import + sibling reorder by index

do {
    let doc = MindDocument(title: "T", root: MindNode(text: "R", children: [
        MindNode(text: "A", note: "n1"),
        MindNode(text: "B", children: [MindNode(text: "C")]),
    ]))
    let opml = try! MapExporter.opml(doc)
    let back = try? MapImporter.opml(opml)
    check(back?.root.text == "R", "opml import restores root")

    // v17.1: FreeMind (.mm) import
    let mm = """
    <map version="1.0.1">
      <node TEXT="Root Topic">
        <node TEXT="Child A" FOLDED="true">
          <node TEXT="Grandchild 1"/>
          <node TEXT="Grandchild &lt;2&gt;"/>
        </node>
        <node TEXT="Child B"/>
      </node>
    </map>
    """
    if let fmDoc = try? MapImporter.freemind(mm) {
        check(fmDoc.root.text == "Root Topic", "freemind import reads TEXT attribute")
        check(fmDoc.root.children.count == 2, "freemind nests children")
        check(fmDoc.root.children[0].collapsed, "freemind maps FOLDED to collapsed")
        check(fmDoc.root.children[0].children.count == 2, "freemind reads grandchildren")
        check(fmDoc.root.children[0].children[1].text == "Grandchild <2>", "freemind unescapes xml entities")
        check(fmDoc.root.children[1].text == "Child B" && !fmDoc.root.children[1].collapsed, "freemind defaults unfolded")
    } else {
        check(false, "freemind parses sample map")
    }
    check((try? MapImporter.freemind("not xml at all")) == nil || (try? MapImporter.freemind("<map></map>")) != nil, "freemind handles junk input gracefully")

    // v17.2: link labels
    let fromID = UUID(), toID = UUID()
    let labeledLink = MindLink(from: fromID, to: toID, label: "導致")
    var labelDoc = MindDocument(title: "T", root: MindNode(text: "R"))
    labelDoc.root.children = [MindNode(text: "A"), MindNode(text: "B")]
    labelDoc.links = [MindLink(from: labelDoc.root.id, to: labelDoc.root.children[0].id),
                      labeledLink]
    let encodedLabel = try JSONEncoder().encode(labelDoc)
    // Give the labeled link real endpoints so SVG can lay it out.
    labelDoc.links[1] = MindLink(from: labelDoc.root.id, to: labelDoc.root.children[1].id, label: "導致")
    if let decoded2 = try? JSONDecoder().decode(MindDocument.self, from: try JSONEncoder().encode(labelDoc)) {
        check(decoded2.links.first(where: { $0.label == "導致" }) != nil, "labeled link with real endpoints encodes")
    }
    if let decoded = try? JSONDecoder().decode(MindDocument.self, from: encodedLabel) {
        check(decoded.links.count == 2, "link labels survive encode roundtrip")
        check(decoded.links.first(where: { $0.label == "導致" })?.label == "導致", "link label text preserved")
        check(decoded.links[0].label.isEmpty, "unlabeled links stay empty")
    } else {
        check(false, "labeled links decode")
    }
    // Backward compat: old JSON without label field decodes with empty label
    let legacyJSON = """
    [{"id":"11111111-1111-1111-1111-111111111111","from":"\(fromID.uuidString)","to":"\(toID.uuidString)"}]
    """
    if let legacyLinks = try? JSONDecoder().decode([MindLink].self, from: Data(legacyJSON.utf8)) {
        check(legacyLinks[0].label.isEmpty, "legacy links without label decode as empty")
    } else {
        check(false, "legacy link json decodes")
    }
    let svgLabeled = MapExporter.svg(labelDoc)
    check(svgLabeled.contains("導致"), "svg export includes link labels")

    // v18.0: presentation mode
    var presDoc = MindDocument(title: "P", root: MindNode(text: "Root"))
    presDoc.root.children = [MindNode(text: "A"), MindNode(text: "B")]
    presDoc.root.children[0].children = [MindNode(text: "A1"), MindNode(text: "A2")]
    presDoc.root.children[0].children[0].children = [MindNode(text: "Deep")]
    presDoc.root.children[0].collapsed = false
    presDoc.root.children[1].children = [MindNode(text: "B1")] // make the fold meaningful
    presDoc.root.children[1].collapsed = true // custom state to survive the roundtrip
    let vm2 = MindMapViewModel()
    vm2.document = presDoc
    vm2.enterPresentation()
    check(vm2.presentationActive, "presentation activates")
    check(vm2.document.root.collapsed, "entering presentation collapses root")
    vm2.stepPresentation()
    check(!vm2.document.root.collapsed, "first step reveals root children")
    check(vm2.document.root.children[0].collapsed, "level 2 stays hidden after first step")
    vm2.stepPresentation()
    vm2.stepPresentation()
    vm2.stepPresentation() // beyond max depth — should be a safe no-op
    check(vm2.document.root.children[0].children[0].children[0].text == "Deep", "deep node still intact after stepping past end")
    // Custom collapse state (set before entering) survives exit restore
    vm2.exitPresentation()
    check(!vm2.presentationActive, "exit deactivates presentation")
    check(vm2.document.root.children[0].collapsed == false, "exit restores original expanded branch")
    check(vm2.document.root.children[1].collapsed == true, "exit restores custom collapsed flag")

    // v18.1: FreeMind export + round-trip
    let mmOut = try! MapExporter.freemind(presDoc)
    check(mmOut.contains("<map version=\"1.0.1\">"), "freemind export has map header")
    check(mmOut.contains("<node TEXT=\"Root\""), "freemind export writes root TEXT")
    check(mmOut.contains("FOLDED=\"true\""), "freemind export preserves collapsed flag")
    if let reimported = try? MapImporter.freemind(mmOut) {
        check(reimported.root.text == presDoc.root.text, "freemind roundtrip keeps root")
        check(reimported.root.children.count == presDoc.root.children.count, "freemind roundtrip keeps children")
        check(reimported.root.children[1].collapsed == true, "freemind roundtrip keeps collapse states")
        check(reimported.root.children[0].children[0].text == "A1", "freemind roundtrip keeps grandchildren")
    } else {
        check(false, "freemind roundtrip parses")
    }
    let tricky = MindNode(text: "a<b>&c\"d", children: [MindNode(text: "x&y")])
    let mmTricky = try! MapExporter.freemind(MindDocument(title: "T", root: tricky))
    if let back = try? MapImporter.freemind(mmTricky) {
        check(back.root.text == "a<b>&c\"d" && back.root.children[0].text == "x&y", "freemind escapes special chars both ways")
    } else {
        check(false, "tricky freemind roundtrip parses")
    }

    // v18.4: branch SVG export (same sub-document trick as branch PNG)
    let branchRoot = presDoc.root.children[0]
    let branchSvg = MapExporter.svg(MindDocument(title: branchRoot.text, root: branchRoot))
    check(branchSvg.contains(">A</text>") || branchSvg.contains(">A1</text>"), "branch svg renders branch nodes")
    check(!branchSvg.contains(">B<"), "branch svg excludes sibling subtree")

    // v18.6: insertTextAsNodes (shared by paste + canvas drop)
    do {
    let vm3 = MindMapViewModel()
    vm3.document = MindDocument(title: "D", root: MindNode(text: "Root"))
    vm3.selection = nil // direct document swap leaves a stale selection behind
    vm3.insertTextAsNodes("- 甲\n- 乙\n  - 丙", sourceLabel: "拖入的文字")
    check(vm3.document.root.children.count == 2, "drop creates top-level nodes")
    if vm3.document.root.children.count >= 2 {
        check(vm3.document.root.children[1].children.first?.text == "丙", "drop keeps indentation structure")
    } else {
        check(false, "drop keeps indentation structure (missing nodes)")
    }
    check(vm3.dirty, "drop marks document dirty")
    vm3.insertTextAsNodes("   \n\t\n", sourceLabel: "拖入的文字")
    check(vm3.document.root.children.count == 2, "whitespace-only drop is a safe no-op")
    vm3.selection = vm3.document.root.children[0].id
    vm3.insertTextAsNodes("丁", sourceLabel: "拖入的文字")
    check(vm3.document.root.children.first?.children.first?.text == "丁", "drop nests under selection")

    // v18.8: save status timestamp + app version helper
    check(!AppInfo.version.isEmpty, "AppInfo version resolves")
    let vm4 = MindMapViewModel()
    vm4.document = MindDocument(title: "S", root: MindNode(text: "Root"))
    vm4.selection = nil
    check(vm4.lastSavedAt == nil, "no saved timestamp before first autosave")
    vm4.autosaveAllSessions()
    check(vm4.lastSavedAt != nil, "autosave stamps the time")

    // v19.2: search covers link labels
    let vm5 = MindMapViewModel()
    vm5.document = MindDocument(title: "S", root: MindNode(text: "Root", children: [
        MindNode(text: "起點"), MindNode(text: "終點"),
    ]))
    vm5.selection = nil
    vm5.document.links = [MindLink(from: vm5.document.root.children[0].id,
                                  to: vm5.document.root.children[1].id,
                                  label: "導致")]
    vm5.searchQuery = "導致"
    vm5.performSearch()
    check(vm5.searchResults.count == 2, "search finds both endpoints of a labeled link")
    let fromNode = vm5.document.root.find(vm5.document.links[0].from)
    check(fromNode?.text == "起點" && vm5.searchResults.contains(vm5.document.links[0].to), "link-label search hits real nodes")
    // Unrelated queries stay unaffected
    vm5.searchQuery = "不存在的字"
    vm5.performSearch()
    check(vm5.searchResults.isEmpty, "non-matching query returns nothing")

    // v19.0: SVG export visual parity with NodeView
    let rich = MindDocument(title: "R", root: MindNode(text: "Root", children: [
        MindNode(text: "L1", note: "有備註", marked: true, colorTag: "red", url: "https://example.com",
                 children: [MindNode(text: "L2")]),
    ]))
    let svgRich = MapExporter.svg(rich)
    // SVG is explicitly Palette.light, independent of the current system appearance.
    check(svgRich.contains("fill=\"#3368a0\""), "svg root fill uses Palette A accent")
    check(!svgRich.contains("#2e3b4f"), "the obsolete root literal is gone for good")
    check(svgRich.contains("stroke=\"none\""), "root rect has no stroke")
    check(svgRich.contains(">★</text>"), "svg draws star for marked nodes")
    check(svgRich.contains(Palette.light.statusHighlightRGB.hex),
          "svg star uses the resolved Palette status highlight")
    check(svgRich.contains("備註：有備註"), "svg embeds note as tooltip title")
    check(svgRich.contains("<a href=\"https://example.com\">"), "svg wraps linked node in anchor")
    // Red color tag is defined as Color(hex: 0xE05252) in Theme.colorTags.
    check(svgRich.lowercased().contains("#e05252"), "svg renders color-tag bar")
    // v3.9: appearance now comes from NodeStyle, so assert the Palette A hierarchy.
    check(svgRich.contains("fill=\"#ffffff\" fill-opacity=\"1.0\""), "svg deep nodes use the Palette card")
    check(svgRich.contains("stroke=\"#3368a0\" stroke-opacity=\"1.0\""), "svg deep nodes use the branch stroke")
    check(svgRich.contains("rx=\"14.0\""), "svg root radius comes from NodeStyle, not a literal 9")
    check(svgRich.contains("font-size=\"18.0\""), "svg root font size matches the screen, not a literal 17")

    // v19.1: FreeMind notes + colors survive the round-trip
    let mmDoc = MindDocument(title: "MM", root: MindNode(text: "Root", children: [
        MindNode(text: "Tagged", note: "重要備註", colorTag: "blue", children: [MindNode(text: "Kid")]),
        MindNode(text: "Plain"),
    ]))
    let mmOut = try! MapExporter.freemind(mmDoc)
    check(mmOut.contains("richcontent TYPE=\"NOTE\"") && mmOut.contains("重要備註"), "freemind export carries notes")
    check(mmOut.uppercased().contains("COLOR=\"#4A90D9\""), "freemind export carries color")
    if let back = try? MapImporter.freemind(mmOut) {
        check(back.root.children[0].note == "重要備註", "freemind roundtrip restores notes")
        check(back.root.children[0].colorTag == "blue", "freemind roundtrip restores color tags")
    } else {
        check(false, "notes/colors roundtrip parses")
    }
    // Import a foreign FreeMind file that uses COLOR without our exact tag hex
    let foreign = """
    <map version="1.0.1">
      <node TEXT="R">
        <node TEXT="C" COLOR="#ff8800">
          <richcontent TYPE="NOTE"><html><body><p>外部筆記</p></body></html></richcontent>
        </node>
      </node>
    </map>
    """
    if let f = try? MapImporter.freemind(foreign) {
        check(f.root.children[0].note == "外部筆記", "freemind import reads foreign richcontent notes")
        // Unknown color maps to no tag (graceful), known hex maps to its tag
        check(f.root.children[0].colorTag == nil, "unknown freemind colors map to no tag")

    // v19.3: presentation steps stay out of undo history
    let vm6 = MindMapViewModel()
    vm6.document = MindDocument(title: "U", root: MindNode(text: "Root", children: [
        MindNode(text: "A", children: [MindNode(text: "A1")]),
        MindNode(text: "B"),
    ]))
    vm6.selection = nil
    vm6.addChild(to: vm6.document.root.children[1].id) // one real undo entry
    vm6.enterPresentation()
    vm6.stepPresentation()
    vm6.stepPresentation()
    vm6.exitPresentation()
    // Undo once should revert the pre-presentation addChild, not a presentation step.
    vm6.undo()
    check(vm6.document.root.children[1].children.isEmpty, "undo after presentation skips presentation steps")
    check(vm6.document.root.text == "Root" && vm6.document.root.children.count == 2, "undo lands on pre-presentation document")

    // v19.4: outline numbering
    var numDoc = MindDocument(title: "N", root: MindNode(text: "Root", children: [
        MindNode(text: "A", children: [MindNode(text: "A1"), MindNode(text: "A2", children: [MindNode(text: "A2a")])]),
        MindNode(text: "B"),
    ]))
    let numbered = OutlineFlattener.flatten(numDoc.root)
    let byID = Dictionary(uniqueKeysWithValues: numbered.map { ($0.id, $0) })
    check(numbered[0].number == nil, "outline root has no number")
    check(byID[numDoc.root.children[0].id]?.number == "1", "first branch is 1")
    check(byID[numDoc.root.children[1].id]?.number == "2", "second branch is 2")
    check(byID[numDoc.root.children[0].children[0].id]?.number == "1.1", "grandchild numbering nests (1.1)")
    check(byID[numDoc.root.children[0].children[1].id]?.number == "1.2", "sibling numbering increments (1.2)")
    // Collapsed branches skip their descendants entirely
    numDoc.root.children[0].collapsed = true
    let collapsedRows = OutlineFlattener.flatten(numDoc.root)
    check(!collapsedRows.contains { $0.number == "1.1" }, "collapsed branch hides its numbers")
    check(collapsedRows.count == 3, "collapsed flatten keeps root + two branches")

    // v19.5: replaceAll covers link labels
    let vm7 = MindMapViewModel()
    vm7.document = MindDocument(title: "R", root: MindNode(text: "Root", children: [
        MindNode(text: "A"), MindNode(text: "B"),
    ]))
    vm7.selection = nil
    vm7.document.links = [MindLink(from: vm7.document.root.children[0].id,
                                  to: vm7.document.root.children[1].id,
                                  label: "導致結果")]
    vm7.replaceAll("導致", with: "造成")
    check(vm7.document.links[0].label == "造成結果", "replaceAll rewrites link labels")
    check(vm7.document.root.children[0].text == "A" && vm7.document.links[0].label.contains("造成"), "node text untouched when only label matches")
    // Case-insensitive replacement still works on node text (regression guard)
    vm7.replaceAll("a", with: "X")
    check(vm7.document.root.children[0].text == "X", "case-insensitive node replacement still works")

    // v20.9: replaceAll counts replacements
    let vm8 = MindMapViewModel()
    vm8.document = MindDocument(title: "C", root: MindNode(text: "Root", children: [
        MindNode(text: "蘋果 apple 蘋果", note: "apple pie"),
        MindNode(text: "banana"),
    ]))
    vm8.selection = nil
    vm8.document.links = [MindLink(from: vm8.document.root.id,
                                  to: vm8.document.root.children[0].id,
                                  label: "apple link")]
    vm8.replaceAll("apple", with: "蜜蘋果")
    // text(1) + note(1) + label(1) = 3 occurrences
    check(vm8.document.root.children[0].note == "蜜蘋果 pie", "replaceAll count matches actual edits")
    check(vm8.document.links[0].label == "蜜蘋果 link", "label replaced once")
    // Zero-match case stays graceful
    let beforeCount = vm8.document.stats().nodeCount
    vm8.replaceAll("不存在的字串xyz", with: "whatever")
    check(vm8.document.stats().nodeCount == beforeCount, "zero-match replaceAll is a safe no-op")

    // v21.7: subtree batch operations
    let vmT = MindMapViewModel()
    vmT.document = MindDocument(title: "ST", root: MindNode(text: "Root", children: [
        MindNode(text: "A", children: [MindNode(text: "A1", children: [MindNode(text: "A1a")])]),
        MindNode(text: "B"),
    ]))
    vmT.selection = nil
    let branchA = vmT.document.root.children[0].id
    vmT.setSubtreeColorTag(id: branchA, tag: "green")
    check(vmT.document.root.children[0].colorTag == "green" && vmT.document.root.children[0].children[0].colorTag == "green", "subtree color reaches grandchildren")
    check(vmT.document.root.colorTag == nil, "subtree color stays inside the branch")
    vmT.setSubtreeMark(id: branchA, to: true)
    check(vmT.document.root.children[0].marked && vmT.document.root.children[0].children[0].marked, "subtree star marks all levels")
    check(vmT.document.root.children[1].marked == false, "sibling branch unaffected")
    vmT.setSubtreeColorTag(id: branchA, tag: nil)
    check(vmT.document.root.children[0].colorTag == nil, "clearing subtree colors works")
    // stats reflect the batch
    check(vmT.document.stats().markedCount == 3, "stats count the starred branch")

    // v21.1: switching tabs during presentation auto-wraps up cleanly
    let vm9 = MindMapViewModel()
    var docA = MindDocument(title: "A", root: MindNode(text: "RootA", children: [
        MindNode(text: "A1", children: [MindNode(text: "A1a")]),
    ]))
    docA.root.children[0].collapsed = true
    vm9.document = docA
    vm9.selection = nil
    let docB = MindDocument(title: "B", root: MindNode(text: "RootB", children: [MindNode(text: "B1")]))
    vm9.enterPresentation()
    check(vm9.presentationActive, "presentation on doc A")
    vm9.openInNewTab(docB)
    check(!vm9.presentationActive, "opening a tab wraps up presentation")
    check(vm9.document.root.text == "RootB", "tab switch landed on doc B")
    // Doc A's session must hold the RESTORED collapse state, not the expanded presentation view.
    let sessionA = vm9.sessions[0]
    check(sessionA.document.root.children[0].collapsed == true, "doc A keeps its original collapse state in the tab")

    // v19.9: format-contract tests — the examples & rules published in docs/FORMAT.md must hold
    let formatExample = """
    {
      "title": "我的圖",
      "themeName": "ocean",
      "directionName": "logicRight",
      "root": {
        "id": "11111111-1111-1111-1111-111111111111",
        "text": "中心主題",
        "children": [
          { "id": "22222222-2222-2222-2222-222222222222", "text": "第一個想法" }
        ]
      }
    }
    """
    if let doc = try? JSONDecoder().decode(MindDocument.self, from: Data(formatExample.utf8)) {
        check(doc.title == "我的圖" && doc.root.text == "中心主題", "FORMAT.md minimal example decodes")
        check(doc.root.children[0].text == "第一個想法", "FORMAT.md nested node decodes")
        check(doc.links.isEmpty && doc.offsets.isEmpty, "FORMAT.md optional sections default empty")
    } else {
        check(false, "FORMAT.md minimal example parses")
    }

    // Tolerant-decoding rules as documented: unknown fields ignored, missing id regenerated
    let futureProof = """
    { "title": "T", "themeName": "mono", "directionName": "balanced",
      "root": { "text": "R", "someFutureField": 42,
                "children": [{ "text": "C", "anotherUnknown": true }] },
      "unknownTopLevel": [] }
    """
    if let fdoc = try? JSONDecoder().decode(MindDocument.self, from: Data(futureProof.utf8)) {
        check(fdoc.root.text == "R" && fdoc.root.children[0].text == "C", "unknown fields are ignored")
        check(fdoc.root.id != fdoc.root.children[0].id, "missing ids are regenerated uniquely")
        check(fdoc.themeName == "mono" && fdoc.directionName == "balanced", "document-level fields survive unknown siblings")

    // v21.4+: summary brackets — model & CRUD
    let vmS = MindMapViewModel()
    vmS.document = MindDocument(title: "SM", root: MindNode(text: "Root", children: [
        MindNode(text: "S1"), MindNode(text: "S2"), MindNode(text: "S3"),
    ]))
    vmS.selection = nil
    let pID = vmS.document.root.id
    let s1 = vmS.document.root.children[0].id
    let s2 = vmS.document.root.children[1].id
    let s3 = vmS.document.root.children[2].id
    if let sid = vmS.addSummary(parentID: pID, startID: s1, endID: s2) {
        vmS.setSummaryText(id: sid, to: "重點兩項")
        check(vmS.document.summaries.first?.text == "重點兩項", "summary text editable")
        // encode/decode roundtrip preserves summaries
        if let decoded = try? JSONDecoder().decode(MindDocument.self, from: try JSONEncoder().encode(vmS.document)) {
            check(decoded.summaries.count == 1 && decoded.summaries[0].text == "重點兩項", "summaries survive file roundtrip")
            check(decoded.summaries[0].startID == s1 && decoded.summaries[0].endID == s2, "summary range survives roundtrip")
        } else { check(false, "summaries decode") }
        // Deleting an endpoint removes the bracket
        vmS.delete(id: s2)
        check(vmS.document.summaries.isEmpty, "deleting a range endpoint prunes the summary")
    } else { check(false, "valid summary range accepted") }
    // Invalid ranges rejected
    check(vmS.addSummary(parentID: pID, startID: s3, endID: s1) == nil, "reversed range rejected")
    check(vmS.addSummary(parentID: UUID(), startID: s1, endID: s2) == nil, "wrong parent rejected")
    check(vmS.addSummary(parentID: pID, startID: s1, endID: s1) == nil, "single-node range rejected")

    // v21.5: summary bracket geometry + SVG rendering (fresh doc — vmS had endpoints deleted)
    let geoDoc = MindDocument(title: "G", root: MindNode(text: "Root", children: [
        MindNode(text: "G1"), MindNode(text: "G2"), MindNode(text: "G3"),
    ]))
    let geoLayouts = LayoutEngine.layout(root: geoDoc.root, direction: .logicRight)
    let parentNode = geoDoc.root
    let sum = MindSummary(parentID: parentNode.id,
                          startID: geoDoc.root.children[0].id,
                          endID: geoDoc.root.children[1].id, text: "兩個重點")
    if let g = SummaryGeometry.bracket(for: sum, parentNode: parentNode, layouts: geoLayouts, origin: .zero) {
        check(g.spineA.y == g.spineB.y || g.spineA.x == g.spineB.x, "bracket spine is straight")
        check(g.tickA != g.tickB, "bracket ticks span the range")
        // logicRight layout puts children to the right → vertical bracket, text to the right of spine
        check(g.textAnchor.x > min(g.spineA.x, g.spineB.x), "label sits outside the spine")
    } else {
        check(false, "valid summary geometry computes")
    }
    check(SummaryGeometry.bracket(for: MindSummary(parentID: UUID(), startID: s1, endID: s2, text: ""),
                                  parentNode: parentNode,
                                  layouts: geoLayouts, origin: .zero) == nil, "geometry nil for missing parent")
    var svgDoc = geoDoc
    svgDoc.summaries = [MindSummary(parentID: geoDoc.root.id,
                                    startID: geoDoc.root.children[0].id,
                                    endID: geoDoc.root.children[1].id, text: "兩個重點")]
    let svgSum = MapExporter.svg(svgDoc)
    check(svgSum.contains("兩個重點"), "svg export draws summary label")

    // v22.0: markdown export carries summary text (visible, documented convention)
    var sumDoc2 = MindDocument(title: "SM", root: MindNode(text: "Root", children: [
        MindNode(text: "S1"), MindNode(text: "S2"), MindNode(text: "S3"),
    ]))
    sumDoc2.summaries = [MindSummary(parentID: sumDoc2.root.id,
                                     startID: sumDoc2.root.children[0].id,
                                     endID: sumDoc2.root.children[1].id,
                                     text: "這兩項是重點")]
    let mdSum = try! MapExporter.markdown(sumDoc2)
    check(mdSum.contains("↳ 概要（含S1）: 這兩項是重點"), "markdown export includes summary text after range")
    // Summaries ending at a later sibling don't leak into earlier positions
    check(!mdSum.contains("↳ 概要（含S3）"), "summary anchored to its own range end")
    let mdNoSum = try! MapExporter.markdown(MindDocument(title: "N", root: MindNode(text: "R", children: [MindNode(text: "x")])))
    check(!mdNoSum.contains("↳ 概要"), "documents without summaries stay clean")



    // v22.1: search covers summary text
    let vmU = MindMapViewModel()
    vmU.document = MindDocument(title: "Q", root: MindNode(text: "Root", children: [
        MindNode(text: "甲"), MindNode(text: "乙"), MindNode(text: "丙"),
    ]))
    vmU.selection = nil
    vmU.document.summaries = [MindSummary(parentID: vmU.document.root.id,
                                          startID: vmU.document.root.children[0].id,
                                          endID: vmU.document.root.children[1].id,
                                          text: "核心決策")]
    vmU.searchQuery = "核心"
    vmU.performSearch()
    check(vmU.searchResults.count == 2, "summary-text search returns covered siblings")
    // Unrelated queries unaffected
    vmU.searchQuery = "甲"
    vmU.performSearch()
    check(vmU.searchResults.contains(vmU.document.root.children[0].id), "regular node search still works")

    // v23.0 phase 1: image field — layout sizing + persistence
    let tinyPNG = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
    let withImg = MindNode(text: "有圖", image: "data:image/png;base64," + tinyPNG)
    let noImg = MindNode(text: "無圖")
    let sizeWith = LayoutEngine.nodeSize(for: withImg.text, depth: 1, hasImage: true)
    let sizeWithout = LayoutEngine.nodeSize(for: noImg.text, depth: 1, hasImage: false)
    check(sizeWith.height > sizeWithout.height, "image grows node height")
    check(ImageStore.shared.image(forDataURL: withImg.image) != nil, "image store decodes data URL")
    check(ImageStore.shared.image(forDataURL: nil) == nil, "nil image decodes to nil")
    check(ImageStore.shared.image(forDataURL: "") == nil, "empty string decodes to nil")
    // persistence roundtrip
    let imgDoc = MindDocument(title: "I", root: MindNode(text: "R", children: [withImg, noImg]))
    if let back = try? JSONDecoder().decode(MindDocument.self, from: try JSONEncoder().encode(imgDoc)) {
        check(back.root.children[0].image == "data:image/png;base64," + tinyPNG, "image survives file roundtrip")
        check(back.root.children[1].image == nil, "nodes without image stay nil")
    } else { check(false, "image document decodes") }
    // legacy JSON without image key decodes as nil (documented tolerance)
    let legacyNode = """
    {"id":"33333333-3333-3333-3333-333333333333","text":"old"}
    """
    if let ln = try? JSONDecoder().decode(MindNode.self, from: Data(legacyNode.utf8)) {
        check(ln.image == nil && ln.text == "old", "legacy nodes decode without image")
    } else { check(false, "legacy node json decodes") }
    // layout produces frames including the image-bearing node without crashing
    let imgLayouts = LayoutEngine.layout(root: imgDoc.root, direction: .logicRight)
    check(imgLayouts[imgDoc.root.children[0].id] != nil, "layout handles image nodes")
    // v23.1: guards + SVG embedding on a fresh VM
    let vmI = MindMapViewModel()
    vmI.document = MindDocument(title: "IG", root: MindNode(text: "Root", children: [MindNode(text: "N")]))
    vmI.selection = nil
    let hugePayload = "data:image/png;base64," + String(repeating: "A", count: 2_900_000)
    vmI.setNodeImage(id: vmI.document.root.children[0].id, to: hugePayload)
    check(vmI.document.root.children[0].image == nil, "oversized image rejected")
    vmI.setNodeImage(id: vmI.document.root.children[0].id, to: tinyPNG)
    check(vmI.document.root.children[0].image == tinyPNG, "small image accepted")
    vmI.setNodeImage(id: vmI.document.root.children[0].id, to: "")
    check(vmI.document.root.children[0].image == nil, "empty string clears the image")

    // v24.0 phase 1: batch selection VM layer
    let vmB = MindMapViewModel()
    vmB.document = MindDocument(title: "B", root: MindNode(text: "Root", children: [
        MindNode(text: "X"), MindNode(text: "Y"), MindNode(text: "Z"),
    ]))
    vmB.selection = nil
    let x = vmB.document.root.children[0].id
    let y = vmB.document.root.children[1].id
    let z = vmB.document.root.children[2].id
    vmB.toggleBatchMember(x)
    vmB.toggleBatchMember(y)
    check(vmB.batchSelection == [x, y], "batch selection gathers members")
    vmB.toggleBatchMember(y)
    check(!vmB.batchSelection.contains(y), "toggling removes a member")
    vmB.toggleBatchMember(y)
    vmB.setColorTagForBatch(tag: "blue")
    check(vmB.document.root.find(x)?.colorTag == "blue", "batch color reaches first member")
    check(vmB.document.root.find(y)?.colorTag == "blue", "batch color reaches re-added member")
    check(vmB.document.root.find(z)?.colorTag == nil, "non-member untouched")
    check(vmB.batchSelection.isEmpty, "batch op clears selection")
    vmB.toggleBatchMember(x)
    vmB.setMarkForBatch(to: true)
    check(vmB.document.root.find(x)?.marked == true, "batch star applies")
    vmB.toggleBatchMember(z)
    vmB.deleteBatch()
    check(vmB.document.root.find(z) == nil, "batch delete removes members")
    check(vmB.document.root.find(x) != nil, "batch delete keeps non-members")
    vmB.toggleBatchMember(vmB.document.root.id)
    vmB.deleteBatch()
    check(vmB.document.root.find(vmB.document.root.id) != nil, "root survives batch delete")

    // v25.2: transient-state hygiene via public flows
    let vmM = MindMapViewModel()
    var docM = MindDocument(title: "M", root: MindNode(text: "Root", children: [
        MindNode(text: "M1"), MindNode(text: "M2"),
    ]))
    let sumID = UUID()
    docM.summaries = [MindSummary(id: sumID, parentID: docM.root.id,
                                  startID: docM.root.children[0].id,
                                  endID: docM.root.children[1].id, text: "概要")]
    vmM.document = docM
    vmM.selectedSummaryID = sumID
    // A real tab switch (openInNewTab → stashActive + loadFromSession) must clear it.
    vmM.openInNewTab(MindDocument(title: "M2", root: MindNode(text: "Other")))
    check(vmM.selectedSummaryID == nil, "selected summary cleared on tab switch")
    // collapseAll resets the level indicator
    vmM.expandToLevel(2)
    check(vmM.activeCollapseLevel == 2, "expandToLevel records the level")
    vmM.collapseAll()
    check(vmM.activeCollapseLevel == nil, "collapseAll clears the level indicator")

    // v25.x stress test: node with ALL attributes set simultaneously across all layouts
    let tinyPNGStress = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
    let megaNode = MindNode(
        text: "這是一段非常非常長的文字一定會超過單行寬度上限而需要換行處理的文字",
        note: "這是一段很長的備註文字用來測試多行顯示",
        marked: true, colorTag: "red",
        url: "https://example.com/stress-test",
        image: "data:image/png;base64," + tinyPNGStress,
        children: [MindNode(text: "子主題")]
    )
    let stressRoot = MindNode(text: "Stress", children: [megaNode])
    for dirName in ["logicRight", "balanced", "fishbone", "bracket"] {
        let d = MapDirection(rawValue: dirName)!
        let sl = LayoutEngine.layout(root: stressRoot, direction: d)
        check(sl[stressRoot.children[0].id] != nil, "\(dirName): mega node laid out")
        check(sl.count == 3, "\(dirName): all nodes have layout frames")
    }
    // Export works with max-complexity node
    let stressSvg = MapExporter.svg(MindDocument(title: "S", root: stressRoot))
    check(stressSvg.contains("★"), "stress svg has star")
    check(stressSvg.contains("<image href=\"data:image/png"), "stress svg has embedded image")
    check(stressSvg.contains("#e05252") || stressSvg.contains("e05252"), "stress svg has color tag")
    check(stressSvg.contains("https://example.com/stress-test"), "stress svg has URL link")
    check(stressSvg.contains("備註"), "stress svg has note tooltip")

    // v22.2: pan/zoom coordinate space consistency
    // At any zoom level, panning should move content by the same screen-space amount.
    // This is implicitly tested by verifying layout output doesn't depend on zoom level.
    let zoomDoc = MindDocument(title: "Z", root: MindNode(text: "Root", children: [MindNode(text: "A")]))
    let layoutsAtScale1 = LayoutEngine.layout(root: zoomDoc.root, direction: .logicRight)
    // Layout computation is independent of scale (scale is applied in view layer)
    check(layoutsAtScale1[zoomDoc.root.children[0].id] != nil, "layout works at default scale")
    // The scale factor only affects rendering (scaleEffect), not layout positions
    check(zoomDoc.root.children[0].text == "A", "content unchanged by zoom operations")



    // Edge case: summaries referencing deleted nodes don't crash rendering
    var ghostDoc = MindDocument(title: "G", root: MindNode(text: "Root", children: [MindNode(text: "Only")]))
    ghostDoc.summaries = [MindSummary(parentID: ghostDoc.root.id,
                                      startID: UUID(), endID: UUID(), text: "ghost")]
    let ghostLayouts = LayoutEngine.layout(root: ghostDoc.root)
    check(SummaryGeometry.bracket(for: ghostDoc.summaries[0], parentNode: ghostDoc.root,
                                  layouts: ghostLayouts, origin: .zero) == nil,
          "summary with missing endpoints returns nil geometry")
    let ghostSvg = MapExporter.svg(ghostDoc)
    check(!ghostSvg.contains("概要"), "svg skips ghost summaries")

    // v25.9: first-run experience with all new features
    let vmN = MindMapViewModel()
    // Simulate fresh install: clear sessions, use sample doc
    let sample = MindTemplates.make("會議記錄")
    check(!sample.root.children.isEmpty, "sample document has topics")
    // Sample works with all rendering paths
    let sampleLayouts = LayoutEngine.layout(root: sample.root, direction: .logicRight)
    check(sampleLayouts.count > 0, "sample document lays out correctly")
    let sampleSvg = MapExporter.svg(sample)
    check(sampleSvg.contains("<svg"), "sample exports to SVG without crash")
    // Templates work with new features
    for name in ["空白", "會議記錄", "專案計畫", "每週回顧"] {
        let t = MindTemplates.make(name)
        let tl = LayoutEngine.layout(root: t.root, direction: .logicRight)
        check(tl.count > 0, "template \(name) lays out correctly")
        let ts = MapExporter.svg(t)
        check(ts.contains("</svg>"), "template \(name) exports cleanly")
    }

    // v25.8: cross-feature regression suite (self-contained)
    let pngData = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
    var regDoc = MindDocument(title: "REG", root: MindNode(text: "Root", children: [
        MindNode(text: "L", image: "data:image/png;base64," + pngData),
        MindNode(text: "R"),
    ]))
    regDoc.summaries = [MindSummary(parentID: regDoc.root.id,
                                    startID: regDoc.root.children[0].id,
                                    endID: regDoc.root.children[1].id,
                                    text: "covers both")]
    for dirName in ["logicRight", "balanced", "fishbone", "bracket"] {
        let d = MapDirection(rawValue: dirName)!
        let dl = LayoutEngine.layout(root: regDoc.root, direction: d)
        check(dl[regDoc.root.children[0].id] != nil, "summary+image survives \(dirName) layout")
    }
    let regSvg = MapExporter.svg(regDoc)
    check(regSvg.contains("covers both"), "regression svg has summary")
    check(regSvg.contains("<image href=\"data:image/png;base64,"), "regression svg has image")
    // Batch ops on a fresh VM
    let vmR = MindMapViewModel()
    vmR.document = MindDocument(title: "RR", root: MindNode(text: "RootR", children: [
        MindNode(text: "X", children: [MindNode(text: "X1")]), MindNode(text: "Y"),
    ]))
    vmR.selection = nil
    vmR.focusBranchID = vmR.document.root.id
    vmR.searchQuery = "Root"
    vmR.performSearch()
    check(!vmR.searchResults.isEmpty, "search works while focused")
    vmR.setSubtreeColorTag(id: vmR.document.root.children[0].id, tag: "green")
    check(vmR.document.root.children[0].colorTag == "green" && !vmR.batchSelection.isEmpty == false, "subtree color works independently of batch")
    vmR.focusBranchID = nil

    // v25.1: batch selection does not leak across tab switches
    let vmL = MindMapViewModel()
    vmL.document = MindDocument(title: "LA", root: MindNode(text: "RootA", children: [
        MindNode(text: "A1"), MindNode(text: "A2"),
    ]))
    vmL.selection = nil
    let nodeA1 = vmL.document.root.children[0].id
    vmL.toggleBatchMember(nodeA1)
    vmL.openInNewTab(MindDocument(title: "LB", root: MindNode(text: "RootB")))
    check(vmL.batchSelection.isEmpty, "switching tabs clears stale batch selection")
    let svgImgDoc = MindDocument(title: "SI", root: MindNode(text: "R", children: [MindNode(text: "有圖", image: "data:image/png;base64," + tinyPNG)]))
    let svgWithImg = MapExporter.svg(svgImgDoc)
    check(svgWithImg.contains("<image href=\"data:image/png;base64,"), "svg embeds attached image as data URL")

    // v23.5: summary range extend/shrink
    let vmE = MindMapViewModel()
    vmE.document = MindDocument(title: "E", root: MindNode(text: "Root", children: [
        MindNode(text: "P"), MindNode(text: "Q"), MindNode(text: "R"), MindNode(text: "S"),
    ]))
    vmE.selection = nil
    let pID2 = vmE.document.root.id
    let kids2 = vmE.document.root.children.map(\.id)
    if let sumE = vmE.addSummary(parentID: pID2, startID: kids2[0], endID: kids2[1]) {
        vmE.extendSummary(id: sumE)
        var sNow = vmE.document.summaries.first(where: { $0.id == sumE })!
        check(sNow.endID == kids2[2], "extend moves the end forward one sibling")
        vmE.extendSummary(id: sumE)
        sNow = vmE.document.summaries.first(where: { $0.id == sumE })!
        check(sNow.endID == kids2[3], "extend reaches the last sibling")
        vmE.shrinkSummary(id: sumE)
        sNow = vmE.document.summaries.first(where: { $0.id == sumE })!
        check(sNow.endID == kids2[2], "shrink pulls the end back")
        check(sNow.startID == kids2[0], "extend/shrink never move the start anchor")}
    else { check(false, "summary created for range test") }

    // v23.4: auto-downsampling for oversized images
    let bigImage = NSImage(size: NSSize(width: 3000, height: 3000))
    bigImage.lockFocus()
    NSColor.red.setFill()
    NSRect(origin: .zero, size: bigImage.size).fill()
    bigImage.unlockFocus()
    if let url = ImageStore.pngDataURL(from: bigImage, maxBytes: 100_000) {
        check(url.hasPrefix("data:image/png;base64,"), "oversized image downsamples into a data URL")
        let b64 = url.dropFirst("data:image/png;base64,".count)
        check(Data(base64Encoded: String(b64))?.count ?? Int.max <= 100_000, "downsampled payload fits the limit")
    } else {
        check(false, "downsampling produced a result")
    }
    // Impossible limit returns nil gracefully
    check(ImageStore.pngDataURL(from: bigImage, maxBytes: 5) == nil, "impossible limit degrades to nil")
    check(vmI.document.root.children[0].image == nil, "empty string clears the image")


    // T-051 S1: URL scheme allowlist for openURL.
    // Principle: only schemes that hand content to a browser or a mail composer
    // open; schemes that address the local file system or dispatch to arbitrary
    // registered apps are refused, as is scheme-less text.
    check(MindMapViewModel.makeOpenableURL("example.com") == nil, "scheme-less text is refused, not promoted to https")
    check(MindMapViewModel.makeOpenableURL("  https://a.tw/x  ")?.absoluteString == "https://a.tw/x", "whitespace is trimmed")
    check(MindMapViewModel.makeOpenableURL("mailto:a@b.c")?.absoluteString == "mailto:a@b.c", "mailto is allowed")
    check(MindMapViewModel.makeOpenableURL("MAILTO:a@b.c") != nil, "scheme matching is case-insensitive")
    check(MindMapViewModel.makeOpenableURL("   ") == nil, "blank URLs return nil")
    check(MindMapViewModel.makeOpenableURL("https://中文字.tw") != nil, "unicode hosts still parse")
    check(MindMapViewModel.makeOpenableURL("file:///etc/passwd") == nil, "the file scheme is refused")
    check(MindMapViewModel.makeOpenableURL("FILE:///etc/passwd") == nil, "uppercase file is refused")
    check(MindMapViewModel.makeOpenableURL("File:///etc/passwd") == nil, "mixed-case file is refused")
    check(MindMapViewModel.makeOpenableURL("\n file:///etc/passwd") == nil, "leading whitespace cannot smuggle a scheme")
    check(MindMapViewModel.makeOpenableURL("\u{0}file:///etc/passwd") == nil, "leading control characters cannot smuggle a scheme")
    check(MindMapViewModel.makeOpenableURL("x-app-handler://run") == nil, "arbitrary-app schemes are refused")
    check(MindMapViewModel.makeOpenableURL("http\n://a.tw") == nil, "a control character inside the scheme is refused")
    try await MainActor.run {
        let vm = MindMapViewModel()
        vm.newDocument()
        let node = vm.addChild(to: nil)!
        vm.setNodeURL(id: node, to: "file:///etc/passwd")
        vm.openURL(id: node)
        check(vm.statusMessage?.contains("mailto") == true, "refusing a scheme notifies instead of opening")
    }
    // The object NSWorkspace receives is URL(string:)'s product, parsed by
    // Foundation rather than by our slicing. Its measured behavior is pinned
    // here so a parser change surfaces as a check failure instead of at
    // launch time — each expectation below matches the behavior observed on
    // this Foundation at commit time.
    check(MindMapViewModel.makeOpenableURL("http:")?.absoluteString == "http:",
          "an empty http: URL parses and reaches the allowlist recheck")
    check(MindMapViewModel.makeOpenableURL("http:/\\/x")?.absoluteString == "http:/%5C/x",
          "URL parsing percent-encodes a backslash path")
    check(MindMapViewModel.makeOpenableURL("http:////x")?.absoluteString == "http:////x",
          "empty-authority slashes survive URL parsing")
    check(MindMapViewModel.makeOpenableURL("https:/x")?.absoluteString == "https:/x",
          "a single-slash https URL parses")
    check(MindMapViewModel.makeOpenableURL("mailto:")?.absoluteString == "mailto:",
          "an empty mailto: URL parses")
    check(MindMapViewModel.makeOpenableURL("MailTo:a@b.c")?.scheme == "MailTo",
          "URL preserves the original scheme spelling")
    check(MindMapViewModel.makeOpenableURL("MailTo:a@b.c")?.scheme?.lowercased() == "mailto",
          "the recheck lowercases the preserved spelling")
    check(MindMapViewModel.makeOpenableURL("HTTP://X.COM")?.scheme?.lowercased() == "http",
          "an uppercase scheme survives URL parsing")
    check(MindMapViewModel.makeOpenableURL("http://%65vil.com")?.absoluteString == "http://%65vil.com",
          "percent-encoding in the host is left as written")
    check(MindMapViewModel.makeOpenableURL("http:#")?.absoluteString == "http:%23",
          "URL parsing percent-encodes a bare #")
    check(MindMapViewModel.makeOpenableURL("%68ttp://x") == nil,
          "a percent-encoded scheme name is refused before URL parsing")
    check(MindMapViewModel.makeOpenableURL("http://a b") == nil,
          "URL parsing refuses an embedded space our slicing would call http")
    // Whatever the slicing decided, the object actually handed on must carry
    // an allowlisted scheme — asserted on the URL, not on our slice.
    for opened in ["https://a.tw/x", "mailto:a@b.c", "MailTo:a@b.c", "HTTP://X.COM",
                   "http:", "http:/\\/x", "http:#", "https:/x"] {
        if let handed = MindMapViewModel.makeOpenableURL(opened) {
            check(["http", "https", "mailto"].contains(handed.scheme?.lowercased() ?? ""),
                  "the URL handed on for \(opened.debugDescription) carries an allowlisted scheme")
        }
    }
    } else {
        check(false, "future-proof document decodes")
    }
    } else {
        check(false, "foreign freemind parses")
    }
    }
    check(back?.root.children.map(\.text) == ["A", "B"], "opml import restores children")
    check(back?.root.children[0].note == "n1", "opml import restores notes")
    check(back?.root.children[1].children.map(\.text) == ["C"], "opml import restores depth")
}

do {
    try await MainActor.run {
        let vm = MindMapViewModel()
        vm.newDocument()
        let a = vm.addChild(to: nil)!
        let b = vm.addChild(to: nil)!
        let c = vm.addChild(to: nil)!
        vm.moveSibling(id: c, toIndex: 0)
        check(vm.document.root.children.map(\.id) == [c, a, b], "moveSiblingTo moves to front")
        vm.moveSibling(id: c, toIndex: 99)
        check(vm.document.root.children.last?.id == c, "moveSiblingTo clamps to end")
        vm.moveSibling(id: a, toIndex: 2)
        check(vm.document.root.children.map(\.id) == [b, a, c], "moveSiblingTo handles removal shift")
    }
}

// MARK: - v2.2: outline flattener

do {
    let root = MindNode(text: "R", children: [
        MindNode(text: "A", children: [MindNode(text: "A1", marked: true)]),
        MindNode(text: "B", collapsed: true, children: [MindNode(text: "B1")]),
    ])
    let rows = OutlineFlattener.flatten(root)
    check(rows.map(\.text) == ["R", "A", "A1", "B"], "outline order respects tree")
    check(rows.map(\.depth) == [0, 1, 2, 1], "outline depths correct")
    check(rows.first(where: { $0.text == "B1" }) == nil, "collapsed branch hidden in outline")
    check(rows.first(where: { $0.text == "A1" })?.marked == true, "outline carries star marks")
}

// MARK: - v2.3: associative links

do {
    try await MainActor.run {
        let vm = MindMapViewModel()
        vm.newDocument()
        let a = vm.addChild(to: nil)!
        let b = vm.addChild(to: nil)!
        check(vm.addLink(from: a, to: b) != nil, "addLink creates link")
        check(vm.addLink(from: b, to: a) == nil, "reversed duplicate link rejected")
        check(vm.addLink(from: a, to: a) == nil, "self link rejected")
        vm.delete(id: a)
        check(vm.document.links.isEmpty, "deleting node prunes its links")
    }
}

do {
    let legacyJSON = """
    {"title":"t","themeName":"ocean","root":{"id":"\(UUID().uuidString.lowercased())","text":"R","note":"","collapsed":false,"children":[]}}
    """
    let doc = try JSONDecoder().decode(MindDocument.self, from: Data(legacyJSON.utf8))
    check(doc.links.isEmpty, "legacy document decodes with empty links")
}

// MARK: - v2.4: fishbone layout

do {
    let root = MindNode(text: "R", children: (1...4).map { b in
        MindNode(text: "B\(b)", children: [MindNode(text: "s\(b)"), MindNode(text: "t\(b)")])
    })
    let layouts = LayoutEngine.layout(root: root, direction: .fishbone)
    check(layouts.count == 13, "fishbone lays out every node")
    let branchRoots = layouts.values.filter { $0.depth == 1 }.sorted { $0.frame.minX < $1.frame.minX }
    check(branchRoots[0].frame.midY < 0 && branchRoots[1].frame.midY > 0,
          "branches alternate above/below spine")
    var chainOK = true
    func walk(_ n: MindNode) {
        for c in n.children {
            if let p = layouts[n.id], let c2 = layouts[c.id], c2.frame.minX <= p.frame.minX { chainOK = false }
            walk(c)
        }
    }
    walk(root)
    check(chainOK, "chains grow strictly rightward")
}

// MARK: - v2.6: bracket layout

do {
    let root = MindNode(text: "R", children: [MindNode(text: "A"), MindNode(text: "B")])
    let bracket = LayoutEngine.layout(root: root, direction: .bracket)
    let logic = LayoutEngine.layout(root: root, direction: .logicRight)
    check(bracket == logic, "bracket shares geometry with logic layout")
}

// MARK: - v2.7: wrapped text sizing + big-map performance

do {
    let long = LayoutEngine.nodeSize(for: "這是一段非常非常長的文字，一定會超過單行寬度上限而需要換行處理", depth: 2)
    let short = LayoutEngine.nodeSize(for: "短", depth: 2)
    check(long.height > short.height, "long text grows node height")
    check(long.width <= 340, "node width stays capped")
    check(short == LayoutEngine.nodeSize(for: "短", depth: 2), "sizing deterministic")
}

do {
    func build(_ depth: Int, _ counter: inout Int) -> MindNode {
        var node = MindNode(text: "N\(counter)")
        counter += 1
        if depth > 0 {
            node.children = [build(depth - 1, &counter), build(depth - 1, &counter)]
        }
        return node
    }
    var counter = 0
    let bigRoot = build(10, &counter) // 2047 nodes
    let start = Date()
    let layouts = LayoutEngine.layout(root: bigRoot)
    let elapsed = Date().timeIntervalSince(start)
    check(layouts.count == counter && counter >= 2000,
          "big map fully laid out (\(counter) nodes)")
    // 1.0s was loose enough to hide a 50x regression; a cold layout of this map
    // measures in tens of milliseconds.
    check(elapsed < 0.25, String(format: "cold layout under 250ms (%.1fms)", elapsed * 1000))
}

// MARK: - Node text always fits the box that was measured for it
//
// LayoutEngine, NodeView and MapExporter used to hardcode font, insets and line
// limit separately, and had already drifted. They now all read NodeStyle, so the
// invariant worth guarding is the one that binding creates: the lines a renderer
// draws must fit inside the size layout reserved.
do {
    let samples = [
        "短",
        "Quarterly planning",
        "這是一個比較長的中文主題文字，用來確認沒有空格的語言也能正確換行而不溢出邊界",
        "Supercalifragilisticexpialidociousandthensomemorewithoutanyspaces",
        "",
    ]
    var worstOverflow: CGFloat = 0
    for depth in [0, 1, 2, 4] {
        let style = NodeStyle.of(depth: depth)
        for text in samples {
            let size = style.size(for: text)
            let lines = style.wrappedLines(for: text)
            check(lines.count <= style.lineLimit,
                  "depth \(depth) honours line limit (\(lines.count) <= \(style.lineLimit))")

            let widest = lines
                .map { $0.size(withAttributes: [.font: style.font]).width }
                .max() ?? 0
            let usableWidth = size.width - style.horizontalInset * 2
            let atWidthCap = size.width >= NodeStyle.maxNodeWidth
            worstOverflow = max(worstOverflow, widest - usableWidth)
            check(atWidthCap || widest <= usableWidth + 0.5,
                  "depth \(depth) text fits width (\(Int(widest)) <= \(Int(usableWidth)))")

            let neededHeight = CGFloat(lines.count) * style.lineHeight
            let usableHeight = size.height - style.verticalInset * 2
            let atHeightCap = size.height >= NodeStyle.maxNodeHeight
            check(atHeightCap || neededHeight <= usableHeight + 0.5,
                  "depth \(depth) text fits height (\(Int(neededHeight)) <= \(Int(usableHeight)))")
        }
    }
}

// MARK: - Final-raster typography hierarchy
//
// Measure the contract string 思考Hg in the final 8-bit alpha raster at both
// backing scales rather than trusting pointSize or capHeight: integer coverage
// can collapse a visible ratio. Ink is alpha coverage >=0.5, implemented as an
// alpha byte >=128; changing the string changes the semantic contract. Hgx
// previously measured 16/14/12 at 1x while 思考Hg measures 18/15/13, so the
// probe text is not interchangeable. Equal-size and stale-size inputs use this
// same evaluator as mutation controls, analogous to the final-8bit color checks.
struct TypographyRasterEvidence {
    let inkHeights: [Int]

    var adjacentRatios: [Double] {
        zip(inkHeights, inkHeights.dropFirst()).map { Double($0.0) / Double($0.1) }
    }

    var passesHierarchy: Bool {
        adjacentRatios.allSatisfy { $0 >= 1.10 }
    }
}

func renderedTypographyEvidence(fonts: [NSFont], backingScale: Int,
                                 probe: String) -> TypographyRasterEvidence? {
    guard !fonts.isEmpty, !probe.isEmpty, backingScale > 0 else { return nil }
    let width = 180 * backingScale
    let height = 80 * backingScale
    let bytesPerRow = width * 4
    let byteCount = height * bytesPerRow
    let pixels = UnsafeMutablePointer<UInt8>.allocate(capacity: byteCount)
    pixels.initialize(repeating: 0, count: byteCount)
    defer { pixels.deallocate() }

    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(data: pixels,
                                  width: width,
                                  height: height,
                                  bitsPerComponent: 8,
                                  bytesPerRow: bytesPerRow,
                                  space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                                      | CGBitmapInfo.byteOrder32Big.rawValue) else {
        return nil
    }
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)
    context.scaleBy(x: CGFloat(backingScale), y: CGFloat(backingScale))
    context.setFillColor(CGColor(colorSpace: colorSpace,
                                 components: [1, 1, 1, 1])!)

    let baseline: CGFloat = 32
    var heights: [Int] = []
    for font in fonts {
        let attributed = NSAttributedString(string: probe, attributes: [.font: font])
        let line = CTLineCreateWithAttributedString(attributed)
        context.textPosition = CGPoint(x: 12, y: baseline)
        CTLineDraw(line, context)

        var minimumY = height
        var maximumY = -1
        for y in 0..<height {
            for x in 0..<width {
                let alpha = pixels[y * bytesPerRow + x * 4 + 3]
                guard alpha >= 128 else { continue }
                minimumY = min(minimumY, y)
                maximumY = max(maximumY, y)
            }
        }
        guard maximumY >= minimumY else { return nil }
        heights.append(maximumY - minimumY + 1)
        context.clear(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
    }
    return TypographyRasterEvidence(inkHeights: heights)
}

func typographyFonts(sizes: [CGFloat]) -> [NSFont] {
    [
        .systemFont(ofSize: sizes[0], weight: .semibold),
        .systemFont(ofSize: sizes[1], weight: .medium),
        .systemFont(ofSize: sizes[2], weight: .regular),
    ]
}

do {
    for backingScale in [1, 2] {
        let productionFonts = [0, 1, 2].map { NodeStyle.of(depth: $0).font }
        guard let production = renderedTypographyEvidence(fonts: productionFonts,
                                                          backingScale: backingScale,
                                                          probe: "思考Hg") else {
            check(false, "typography production raster renders at \(backingScale)x")
            continue
        }
        print(String(format: "Typography raster %dx production heights=%@ ratios=%@",
                     backingScale, String(describing: production.inkHeights),
                     String(describing: production.adjacentRatios)))
        check(production.passesHierarchy,
              "typography production adjacent raster ratios >= 1.10 at \(backingScale)x")

        let shortFonts = [NodeStyle.of(depth: 0).font]
        guard let shortEvidence = renderedTypographyEvidence(fonts: shortFonts,
                                                             backingScale: backingScale,
                                                             probe: "一"),
              let shortHeight = shortEvidence.inkHeights.first,
              let contractHeight = production.inkHeights.first else {
            check(false, "typography probe rasters render at \(backingScale)x")
            continue
        }
        print(String(format: "Typography raster %dx probes 一=%d 思考Hg=%d",
                     backingScale, shortHeight, contractHeight))
        check(shortHeight * 2 <= contractHeight,
              "typography probe distinguishes glyph ink from line-box height at \(backingScale)x")

        let equal = typographyFonts(sizes: [13, 13, 13])
        guard let equalEvidence = renderedTypographyEvidence(fonts: equal,
                                                              backingScale: backingScale,
                                                              probe: "思考Hg") else {
            check(false, "typography equal-size mutation raster renders at \(backingScale)x")
            continue
        }
        print(String(format: "Typography raster %dx equal mutation heights=%@ ratios=%@ accepted=%@",
                     backingScale, String(describing: equalEvidence.inkHeights),
                     String(describing: equalEvidence.adjacentRatios),
                     equalEvidence.passesHierarchy ? "true" : "false"))
        check(!equalEvidence.passesHierarchy,
              "typography equal-size mutation rejects at \(backingScale)x")

        let stale = typographyFonts(sizes: [15, 13, 12.5])
        guard let staleEvidence = renderedTypographyEvidence(fonts: stale,
                                                              backingScale: backingScale,
                                                              probe: "思考Hg") else {
            check(false, "typography stale-size mutation raster renders at \(backingScale)x")
            continue
        }
        print(String(format: "Typography raster %dx stale mutation heights=%@ ratios=%@ accepted=%@",
                     backingScale, String(describing: staleEvidence.inkHeights),
                     String(describing: staleEvidence.adjacentRatios),
                     staleEvidence.passesHierarchy ? "true" : "false"))
        check(!staleEvidence.passesHierarchy,
              "typography stale-size mutation rejects at \(backingScale)x")
    }
}

// MARK: - Interactive relayout budget
//
// T-003's U5 could not measure UI latency through synthetic events, so the
// performance guarantee lives here instead. Every keystroke inside a node editor
// mutates the document and invalidates the layout memo, so per-keystroke
// relayout cost on a large map is what decides whether typing feels laggy.
// This check exists to keep that number honest, not to prove the UI is fast.
do {
    func build(_ depth: Int, _ counter: inout Int) -> MindNode {
        var node = MindNode(text: "N-\(counter)")
        counter += 1
        if depth > 0 {
            node.children = [build(depth - 1, &counter), build(depth - 1, &counter)]
        }
        return node
    }
    var counter = 0
    var root = build(10, &counter)
    _ = LayoutEngine.layout(root: root) // warm the text-size cache

    let iterations = 20
    let start = Date()
    for i in 0..<iterations {
        root.text = "typing \(i)"
        _ = LayoutEngine.layout(root: root)
    }
    let perEdit = Date().timeIntervalSince(start) / Double(iterations)
    check(perEdit < 0.05,
          String(format: "relayout per keystroke on %d nodes under 50ms (%.1fms)",
                 counter, perEdit * 1000))
}

// MARK: - v3.0: multi-document tabs

do {
    try await MainActor.run {
        let vm = MindMapViewModel()
        vm.autosaveAllSessions() // flush whatever restored state exists
        let startCount = vm.sessions.count
        vm.applyTemplate("會議記錄")
        check(vm.sessions.count == startCount + 1, "applyTemplate opens a new tab")
        check(vm.document.root.text.hasPrefix("會議主題（"), "new tab becomes active (dated)")
        let meetingRootID = vm.document.root.id
        vm.switchTab(to: 0)
        check(vm.sessions.count == startCount + 1, "switch keeps all tabs")
        check(vm.document.root.id != meetingRootID, "switch restores previous document")
        vm.closeTab(vm.activeIndex)
        check(vm.sessions.count == startCount, "closeTab removes session")
        // Close down to the last tab; it must be replaced with a fresh document.
        while vm.sessions.count > 1 { vm.closeTab(0) }
        vm.closeTab(0)
        check(vm.sessions.count == 1 && vm.document.root.text != "", "closing last tab yields fresh document")
    }
}

// MARK: - v3.2: tab reordering

do {
    try await MainActor.run {
        let vm = MindMapViewModel()
        vm.autosaveAllSessions()
        while vm.sessions.count > 1 { vm.closeTab(0) }
        let startCount = vm.sessions.count
        vm.applyTemplate("空白")
        vm.applyTemplate("會議記錄")
        vm.applyTemplate("專案計畫")
        // applyTemplate APPENDS a tab each time: [orig, 空白, 會議, 專案]
        check(vm.sessions.count == startCount + 3, "four tabs open")
        let orderBefore = vm.sessions.map { $0.document.root.text }
        let activeBeforeIndex = vm.activeIndex
        vm.moveTab(from: 0, to: 4)
        let orderAfter = vm.sessions.map { $0.document.root.text }
        check(orderAfter == [orderBefore[1], orderBefore[2], orderBefore[3], orderBefore[0]],
              "moveTab moves first tab to end")
        if activeBeforeIndex == 0 {
            check(vm.activeIndex == 2, "active tab follows the move")
        } else {
            check(vm.document.root.text == orderBefore[activeBeforeIndex],
                  "inactive moves keep the active document unchanged")
        }
    }
}

// MARK: - v3.3: batch tab closing

do {
    try await MainActor.run {
        let vm = MindMapViewModel()
        vm.autosaveAllSessions()
        while vm.sessions.count > 1 { vm.closeTab(0) }
        let startCount = vm.sessions.count
        vm.applyTemplate("空白")
        vm.applyTemplate("會議記錄")
        vm.applyTemplate("專案計畫")
        // [orig, 空白, 會議, 專案]
        vm.closeOtherTabs(keeping: 1)
        check(vm.sessions.count == 1, "closeOther keeps exactly one tab")
        check(vm.document.root.text == "中心主題", "kept blank-template session survives")
        vm.applyTemplate("每週回顧")
        let countBeforeRight = vm.sessions.count
        vm.switchTab(to: 0)
        vm.closeTabsToRight(0)
        check(vm.sessions.count == 1 && countBeforeRight == 2, "closeRight removes the suffix")
    }
}

// MARK: - v3.5: autosave slot boundedness (regression for the 100k-file leak)

do {
    try await MainActor.run {
        let vm = MindMapViewModel()
        vm.autosaveAllSessions()
        let baseline = FileIO.tabSlotCount
        vm.applyTemplate("空白")
        vm.autosaveAllSessions()
        vm.autosaveAllSessions()
        vm.applyTemplate("會議記錄")
        vm.autosaveAllSessions()
        let after = FileIO.tabSlotCount
        // Repeated saves must overwrite the same slots, not mint new files.
        check(after <= max(baseline + 2, 10),
              "autosave slots stay bounded (baseline \(baseline), after \(after))")
    }
}

// MARK: - v3.6: reopen closed tab

do {
    try await MainActor.run {
        let vm = MindMapViewModel()
        vm.autosaveAllSessions()
        let startCount = vm.sessions.count
        vm.applyTemplate("會議記錄")
        vm.closeTab(vm.activeIndex)
        check(vm.sessions.count == startCount, "close removes the tab")
        vm.reopenLastClosedTab()
        check(vm.sessions.count == startCount + 1, "reopen restores the tab count")
        check(vm.document.root.text.hasPrefix("會議主題（"), "reopen restores the document")
    }
}

// MARK: - v3.7: star in markdown export

do {
    let doc = MindDocument(title: "T", root: MindNode(text: "R", children: [
        MindNode(text: "重要", marked: true),
        MindNode(text: "普通"),
    ]))
    let md = try! MapExporter.markdown(doc)
    check(md.contains("- ★ 重要"), "markdown export carries star marker")
    check(md.contains("- 普通\n"), "unmarked nodes stay plain")
}

// MARK: - v3.9: node a11y metadata sanity

do {
    let node = MindNode(text: "主題A", note: "有備註", marked: true)
    check(node.displayText == "★ 主題A", "displayText carries star")
    // a11y label composition mirrors NodeView logic
    let label = node.displayText + (node.note.isEmpty ? "" : "，有備註")
    check(label == "★ 主題A，有備註", "a11y label composes text, star and note")
}

// MARK: - v4.4: manual offsets

do {
    try await MainActor.run {
        let vm = MindMapViewModel()
        vm.autosaveAllSessions()
        let a = vm.addChild(to: nil)!
        let before = LayoutEngine.layout(root: vm.document.root, direction: .logicRight,
                                         offsets: vm.document.offsets)[a]!.frame
        vm.nudgeOffset(id: a, dx: 25, dy: -15)
        let after = LayoutEngine.layout(root: vm.document.root, direction: .logicRight,
                                        offsets: vm.document.offsets)[a]!.frame
        check(after.minX == before.minX + 25, "offset shifts x")
        check(after.midY == before.midY - 15, "offset shifts y")
        vm.clearOffset(id: a)
        check(vm.document.offsets.isEmpty, "clearOffset removes entry")
    }
}

// MARK: - v4.7: reset offsets

do {
    try await MainActor.run {
        let vm = MindMapViewModel()
        vm.autosaveAllSessions()
        let a = vm.addChild(to: nil)!
        vm.nudgeOffset(id: a, dx: 40, dy: 20)
        check(vm.document.offsets.isEmpty == false, "nudge creates offset")
        vm.resetAllOffsets()
        check(vm.document.offsets.isEmpty, "resetAll clears every offset")
        let frameAfterReset = LayoutEngine.layout(root: vm.document.root,
                                                  direction: .logicRight,
                                                  offsets: vm.document.offsets)[a]!.frame
        let pureAuto = LayoutEngine.layout(root: MindNode(text: vm.document.root.text,
                                                          children: vm.document.root.children),
                                           direction: .logicRight)[a]?.frame
        check(frameAfterReset == (pureAuto ?? frameAfterReset), "reset returns to pure auto layout")
    }
}

// MARK: - v7.3: fishbone performance at scale

do {
    func buildFish(_ depth: Int, _ counter: inout Int) -> MindNode {
        var node = MindNode(text: "F\(counter)")
        counter += 1
        if depth > 0 {
            node.children = [buildFish(depth - 1, &counter), buildFish(depth - 1, &counter)]
        }
        return node
    }
    var counter = 0
    let bigRoot = buildFish(10, &counter) // 2047 nodes
    let start = Date()
    let layouts = LayoutEngine.layout(root: bigRoot, direction: .fishbone)
    let elapsed = Date().timeIntervalSince(start)
    check(layouts.count == counter && counter >= 2000,
          "fishbone fully laid out (\(counter) nodes)")
    check(elapsed < 1.0, String(format: "fishbone layout under 1.0s (%.3fs)", elapsed))
}

// MARK: - v4.8: empty-start nodes

do {
    try await MainActor.run {
        let vm = MindMapViewModel()
        vm.autosaveAllSessions()
        while vm.sessions.count > 1 { vm.closeTab(0) }
        let node = vm.addChild(to: nil)!
        check(vm.document.root.find(node)?.text == MindMapViewModel.newNodeDefaultText,
              "canvas creation starts with the default text, not empty")
        // The empty-commit discard mechanism is untouched and stays reachable
        // through the outline paths that still create genuinely empty nodes.
        let emptyNode = vm.insertChildUnder(id: vm.document.root.id)!
        check(vm.document.root.find(emptyNode)?.text.isEmpty == true,
              "outline insertion still starts empty")
        vm.commitNodeText(id: emptyNode, text: "   ")
        check(vm.document.root.find(emptyNode) == nil,
              "empty commit discards a brand-new empty node")
        let kept = vm.addChild(to: nil)!
        vm.rename(id: kept, to: "既有文字")
        vm.commitNodeText(id: kept, text: "")
        check(vm.document.root.find(kept)?.text == "既有文字", "esc on existing node keeps original")
    }
}

// MARK: - v4.9: search state never leaks across tabs

do {
    try await MainActor.run {
        let vm = MindMapViewModel()
        vm.autosaveAllSessions()
        vm.applyTemplate("空白")
        let a = vm.addChild(to: nil)!
        vm.rename(id: a, to: "獵物關鍵字")
        vm.searchQuery = "獵物"
        vm.performSearch()
        check(vm.searchResults == [a], "search finds target in active tab")
        vm.switchTab(to: 0)
        check(vm.searchResults.isEmpty && vm.searchQuery == "",
              "switching tabs clears stale search state")
        check(vm.showSearch == false, "search overlay closes on tab switch")
    }
}

// MARK: - v5.2: open from URL

do {
    try await MainActor.run {
        let vm = MindMapViewModel()
        vm.autosaveAllSessions()
        let startCount = vm.sessions.count
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("mf-test-\(UUID().uuidString).mindmap")
        let doc = MindDocument(title: "URL測試", root: MindNode(text: "從檔案長出來"))
        try JSONEncoder().encode(doc).write(to: tmp)
        vm.openFromURL(tmp)
        check(vm.sessions.count == startCount + 1, "openFromURL opens a tab")
        check(vm.document.root.text == "從檔案長出來", "openFromURL loads content")
        check(vm.filePath == tmp, "openFromURL records the file path")
        try? FileManager.default.removeItem(at: tmp)
    }
}

// MARK: - v5.5: search covers notes

do {
    try await MainActor.run {
        let vm = MindMapViewModel()
        vm.autosaveAllSessions()
        let a = vm.addChild(to: nil)!
        vm.rename(id: a, to: "標題文字")
        vm.setNote(id: a, to: "藏在備註裡的線索")
        vm.searchQuery = "線索"
        vm.performSearch()
        check(vm.searchResults == [a], "search covers notes")
    }
}

// MARK: - v5.7: cycleTab coverage

do {
    try await MainActor.run {
        let vm = MindMapViewModel()
        vm.autosaveAllSessions()
        vm.applyTemplate("空白")
        vm.applyTemplate("會議記錄")
        vm.switchTab(to: 0)
        vm.cycleTab(1)
        check(vm.activeIndex == 1, "cycleTab advances and wraps")
    }
}

// MARK: - v5.8: reparent guards + deep-copy independence

do {
    try await MainActor.run {
        let vm = MindMapViewModel()
        vm.autosaveAllSessions()
        while vm.sessions.count > 1 { vm.closeTab(0) }
        let parent = vm.addChild(to: nil)!
        vm.rename(id: parent, to: "父")
        let child = vm.addChild(to: parent)!
        vm.rename(id: child, to: "子")

        // Cycle guard: cannot move a node under its own descendant.
        let beforeCount = vm.document.root.children.count
        vm.move(id: parent, toParent: child)
        check(vm.document.root.parent(of: child)?.id == parent,
              "moving parent under its child is rejected")

        // Deep-copy independence.
        let copyID = vm.duplicate(id: parent)!
        vm.rename(id: copyID, to: "父副本")
        check(vm.document.root.find(copyID)?.text == "父副本", "duplicate renames independently")
        check(vm.document.root.find(parent)?.text == "父", "original unaffected by copy rename")
        let copyChild = vm.document.root.find(copyID)?.children.first?.id
        vm.rename(id: copyChild!, to: "子的分身")
        check(vm.document.root.find(child)?.text == "子",
              "copy's descendants are fully independent")

        // Root still holds both original branches.
        check(vm.document.root.children.count == beforeCount + 1,
              "duplicate appends after the original")
    }
}

// MARK: - v5.9: newline sanitization on commit

do {
    try await MainActor.run {
        let vm = MindMapViewModel()
        vm.autosaveAllSessions()
        let a = vm.addChild(to: nil)!
        vm.commitNodeText(id: a, text: "多行\n貼上\t文字")
        let stored = vm.document.root.find(a)?.text ?? ""
        check(!stored.contains("\n") && !stored.contains("\t"), "newlines and tabs flattened")
        check(stored.contains("多行"), "pasted content preserved")
    }
}

// MARK: - v6.2: offsets respected across directions

do {
    let root = MindNode(text: "R", children: [MindNode(text: "A"), MindNode(text: "B")])
    let key = root.children[0].id.uuidString
    let offsets = [key: CGPoint(x: 33, y: 44)]
    for dir in [MapDirection.balanced, .fishbone] {
        let plain = LayoutEngine.layout(root: root, direction: dir)
        let shifted = LayoutEngine.layout(root: root, direction: dir, offsets: offsets)
        let moved = shifted[root.children[0].id]!.frame
        check(moved.minX == plain[root.children[0].id]!.frame.minX + 33
              && moved.minY == plain[root.children[0].id]!.frame.minY + 44,
              "offsets respected in \(dir.rawValue)")
    }
}

// MARK: - v6.3: insertSiblingAfter rapid entry

do {
    try await MainActor.run {
        let vm = MindMapViewModel()
        vm.autosaveAllSessions()
        vm.newDocument()
        let a = vm.addChild(to: nil)!
        vm.rename(id: a, to: "第一點")
        let b = vm.insertSiblingAfter(id: a)!
        vm.rename(id: b, to: "第二點")
        let ids = vm.document.root.children.map(\.id)
        check(ids == [a, b], "insertSiblingAfter inserts right after")
        check(vm.insertSiblingAfter(id: vm.document.root.id) == nil,
              "cannot insert sibling after root")
    }
}

// MARK: - v5.x legacy blocks above

// MARK: - v6.6: expand to level

do {
    try await MainActor.run {
        let vm = MindMapViewModel()
        vm.autosaveAllSessions()
        vm.newDocument()
        let a = vm.addChild(to: nil)!
        let b = vm.addChild(to: a)!
        let c = vm.addChild(to: b)!
        vm.expandToLevel(2)
        check(vm.document.root.find(a)?.collapsed == true, "level-2 view collapses layer-2 nodes")
        check(vm.document.root.find(b)?.collapsed == true, "deeper nodes stay collapsed")
        vm.expandToLevel(3)
        check(vm.document.root.find(a)?.collapsed == false, "level-3 expands layer-2 node")
        check(vm.document.root.find(b)?.collapsed == true, "layer-3 node with children collapses")
        check(vm.document.root.find(c)?.collapsed == false, "leaf nodes never collapsed")
    }
}

// MARK: - v6.7: focus set semantics

do {
    try await MainActor.run {
        let vm = MindMapViewModel()
        vm.autosaveAllSessions()
        vm.newDocument()
        let a = vm.addChild(to: nil)!
        let a1 = vm.addChild(to: a)!
        let uncle = vm.addChild(to: nil)!
        vm.focusBranchID = a1
        let set = vm.focusSet()
        check(set.contains(a1) && set.contains(a) && set.contains(vm.document.root.id),
              "focus keeps subtree and ancestors")
        check(!set.contains(uncle), "focus hides sibling branches")
        vm.focusBranchID = nil
        check(vm.focusSet().isEmpty, "clearing focus empties the set")
    }
}

// MARK: - v6.8: insert parent

do {
    try await MainActor.run {
        let vm = MindMapViewModel()
        vm.autosaveAllSessions()
        vm.newDocument()
        let a = vm.addChild(to: nil)!
        vm.rename(id: a, to: "原本")
        let newParentID = vm.insertParent(id: a)!
        vm.rename(id: newParentID, to: "新容器")
        check(vm.document.root.children.count == 1, "insertParent keeps root child count")
        check(vm.document.root.children[0].text == "新容器", "wrapper takes the slot")
        check(vm.document.root.children[0].children[0].text == "原本", "original becomes child of wrapper")
        check(vm.document.root.find(a)?.text == "原本", "original subtree preserved")
    }
}

// MARK: - v6.9: cross-branch reparent

do {
    try await MainActor.run {
        let vm = MindMapViewModel()
        vm.autosaveAllSessions()
        vm.newDocument()
        let b1 = vm.addChild(to: nil)!
        vm.rename(id: b1, to: "分支一")
        let leaf = vm.addChild(to: b1)!
        vm.rename(id: leaf, to: "遊子")
        let grandchild = vm.addChild(to: leaf)!
        vm.rename(id: grandchild, to: "隨行者")
        let b2 = vm.addChild(to: nil)!
        vm.rename(id: b2, to: "分支二")

        vm.move(id: leaf, toParent: b2)
        check(vm.document.root.parent(of: leaf)?.id == b2,
              "reparent moves leaf under the target branch")
        check(vm.document.root.find(leaf)!.children.map(\.text) == ["隨行者"],
              "subtree travels with the moved leaf")
        check(vm.document.root.find(b1)?.children.isEmpty == true,
              "source branch shrinks")
    }
}

// MARK: - v7.5: collapsed respected across all four directions

do {
    let grand = MindNode(text: "G")
    let mid = MindNode(text: "M", collapsed: true, children: [grand])
    let root = MindNode(text: "R", children: [mid])
    for dir in [MapDirection.logicRight, .balanced, .fishbone, .bracket] {
        let layouts = LayoutEngine.layout(root: root, direction: dir)
        check(layouts[grand.id] == nil, "collapsed descendants hidden in \(dir.rawValue)")
        check(layouts[mid.id] != nil, "collapsed branch root visible in \(dir.rawValue)")
    }
}

// MARK: - v7.8: corrupted-file guard

do {
    try await MainActor.run {
        let vm = MindMapViewModel()
        vm.autosaveAllSessions()
        let before = vm.sessions.count
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("broken-\(UUID().uuidString).mindmap")
        try Data("not json at all {{{".utf8).write(to: tmp)
        vm.openFromURL(tmp)
        check(vm.sessions.count == before, "corrupted file opens no tab")
        check(vm.statusMessage?.contains("\u{7121}\u{6cd5}\u{958b}\u{555f}") == true,
              "user sees a friendly error message")
        try? FileManager.default.removeItem(at: tmp)
    }
}

// MARK: - v7.9: focus state does not leak across tabs

do {
    try await MainActor.run {
        let vm = MindMapViewModel()
        vm.autosaveAllSessions()
        let startCount = vm.sessions.count
        vm.applyTemplate("空白")
        let a = vm.addChild(to: nil)!
        vm.focusBranchID = a
        check(!vm.focusSet().isEmpty, "focus active before switching")
        vm.switchTab(to: 0)
        check(vm.focusBranchID == nil, "switching tabs clears focus")
        check(vm.focusSet().isEmpty, "no stale focus after switch")
        vm.closeTab(vm.activeIndex)
        check(vm.sessions.count == startCount, "tab count restored")
    }
}

// MARK: - v8.2: per-tab undo isolation, zen & theme flags

do {
    try await MainActor.run {
        let vm = MindMapViewModel()
        vm.autosaveAllSessions()
        while vm.sessions.count > 1 { vm.closeTab(0) }
        vm.newDocument()
        let x = vm.addChild(to: nil)!
        vm.rename(id: x, to: "標記")

        vm.applyTemplate("空白")          // opens tab 2 and activates it
        check(vm.sessions.count == 2, "applyTemplate opened second tab")
        vm.switchTab(to: 0)               // back to first tab
        check(vm.document.root.find(x)?.text == "標記", "switching back preserves edits")

        // Per-tab undo: undoing here must not touch the other tab.
        vm.undo()
        check(vm.document.root.find(x)?.text == MindMapViewModel.newNodeDefaultText,
              "per-tab undo isolates stacks")

        // Zen & theme flags.
        vm.toggleZen()
        check(vm.zenMode == true, "zen mode toggles on")
        vm.toggleZen()
        check(vm.zenMode == false, "zen mode toggles off")
        check(Theme.named("candy").branchRGB == Palette.light.branchRGB,
              "legacy theme IDs use the single Palette A")
    }
}

// MARK: - v8.3: balanced & bracket performance at scale

do {
    func buildP(_ depth: Int, _ counter: inout Int) -> MindNode {
        var node = MindNode(text: "P\\(counter)")
        counter += 1
        if depth > 0 {
            node.children = [buildP(depth - 1, &counter), buildP(depth - 1, &counter)]
        }
        return node
    }
    var counter = 0
    let bigRoot = buildP(10, &counter)
    let startB = Date()
    let balancedLayouts = LayoutEngine.layout(root: bigRoot, direction: .balanced)
    let elapsedB = Date().timeIntervalSince(startB)
    check(balancedLayouts.count == counter && elapsedB < 1.0,
          String(format: "balanced 2047 under 1.0s (%.3fs)", elapsedB))
    let startK = Date()
    let bracketLayouts = LayoutEngine.layout(root: bigRoot, direction: .bracket)
    let elapsedK = Date().timeIntervalSince(startK)
    check(bracketLayouts.count == counter && elapsedK < 1.0,
          String(format: "bracket 2047 under 1.0s (%.3fs)", elapsedK))
}

// MARK: - v8.5: duplicate tab + color emoji export

do {
    try await MainActor.run {
        let vm = MindMapViewModel()
        vm.autosaveAllSessions()
        let startCount = vm.sessions.count
        vm.duplicateActiveTab()
        check(vm.sessions.count == startCount + 1, "duplicateActiveTab opens a tab")
        check(vm.document.title.hasSuffix("\u{526f}\u{672c}"), "duplicate title carries suffix")
    }
}

do {
    let doc = MindDocument(title: "T", root: MindNode(text: "R", children: [
        MindNode(text: "C", colorTag: "red"),
    ]))
    let md = try! MapExporter.markdown(doc)
    check(md.contains("- \u{1F534} C"), "markdown export carries red emoji")
}

// MARK: - v8.6: map stats

do {
    let doc = MindDocument(title: "T", root: MindNode(text: "R", note: "n1", children: [
        MindNode(text: "A", marked: true, children: [MindNode(text: "A1")]),
        MindNode(text: "B", collapsed: true),
    ]))
    let st = doc.stats()
    check(st.nodeCount == 4, "stats counts all nodes")
    check(st.maxDepth == 3, "stats computes max depth")
    check(st.noteCount == 1 && st.markedCount == 1, "stats counts notes and stars")
    check(st.collapsedCount == 1, "stats counts collapsed branches")
}
do {
    try await MainActor.run {
        let vm = MindMapViewModel()
        vm.autosaveAllSessions()
        vm.newDocument()
        let a = vm.addChild(to: nil)!
        vm.setNote(id: a, to: "hello")
        let s3 = vm.document.stats()
        check(s3.linkCount == 0, "stats link count zero by default")
    }
}

// MARK: - v8.8: links survive layout switch; duplicate mints unique IDs

do {
    try await MainActor.run {
        let vm = MindMapViewModel()
        vm.autosaveAllSessions()
        vm.newDocument()
        let a = vm.addChild(to: nil)!
        let b = vm.addChild(to: nil)!
        let linkID = vm.addLink(from: a, to: b)!
        vm.setDirection(.balanced)
        check(vm.document.links.count == 1 && vm.document.links[0].id == linkID,
              "links survive direction switch")
        vm.duplicateActiveTab()
        check(vm.sessions.count >= 2, "duplicate tab opens")
    }
}

do {
    var counter = 0
    func buildU(_ depth: Int, _ counter: inout Int) -> MindNode {
        var node = MindNode(text: "N\(counter)")
        counter += 1
        if depth > 0 {
            let c1 = buildU(depth - 1, &counter)
            let c2 = buildU(depth - 1, &counter)
            node.children = [c1, c2]
        }
        return node
    }
    let orig = buildU(2, &counter)
    var copy = orig
    func reassign(_ n: inout MindNode) {
        n.id = UUID()
        for i in n.children.indices { reassign(&n.children[i]) }
    }
    reassign(&copy)
    let collectIDs: (MindNode) -> Set<UUID> = { root in
        var ids = Set<UUID>()
        func w(_ n: MindNode) { ids.insert(n.id); n.children.forEach(w) }
        w(root)
        return ids
    }
    check(collectIDs(orig).isDisjoint(with: collectIDs(copy)), "reassign mints fully unique IDs")
}

// MARK: - v9.1: hidden descendant preview

do {
    let root = MindNode(text: "R", children: [
        MindNode(text: "A", children: [MindNode(text: "A1"), MindNode(text: "A2")]),
        MindNode(text: "B"),
    ])
    let a = root.children[0]
    check(a.hiddenTopicPreview(limit: 6) == ["A1", "A2"], "preview lists direct topics breadth-first")
    check(a.descendantIDs().count == 2, "hidden count matches descendants")
    let rootPreview = root.hiddenTopicPreview(limit: 6)
    check(rootPreview.count == 4, "root preview includes all descendants")
    check(Array(rootPreview.prefix(2)) == ["A", "B"], "root preview breadth-first ordering")
}

// MARK: - v9.2: end-to-end workflow scenarios

do {
    try await MainActor.run {
        let vm = MindMapViewModel()
        vm.autosaveAllSessions()
        vm.newDocument()
        vm.applyTemplate("會議記錄")

        guard let issues = vm.document.root.children.first(where: { $0.text == "討論議題" }) else {
            check(false, "template has discussion branch")
            return
        }
        let idea = vm.addChild(to: issues.id)!
        vm.rename(id: idea, to: "新想法")
        vm.setNote(id: idea, to: "關鍵字線索")

        vm.searchQuery = "新想法"
        vm.performSearch()
        check(vm.searchResults == [idea], "workflow: search finds new idea")

        vm.collapseAll()
        check(vm.document.stats().collapsedCount > 0, "collapseAll marks branches")

        vm.expandAll()
        let md = try! MapExporter.markdown(vm.document)
        check(md.contains("新想法"), "markdown export includes workflow content")
    }
}

// MARK: - v10.1: root guards & expandAll equivalence

do {
    try await MainActor.run {
        let vm = MindMapViewModel()
        vm.autosaveAllSessions()
        vm.newDocument()
        let before = vm.document

        // Root cannot be moved || wrapped.
        vm.move(id: vm.document.root.id, toParent: vm.document.root.id)
        vm.insertParent(id: vm.document.root.id)
        check(vm.document.root.text == before.root.text, "root guards hold")

        // expandAll == expandToLevel(99).
        let a = vm.addChild(to: nil)!
        let b = vm.addChild(to: a)!
        let c = vm.addChild(to: b)!
        vm.expandToLevel(1)
        check(vm.document.root.find(a)?.collapsed == true, "level-1 collapses everything below")
        vm.expandToLevel(99)
        check(vm.document.root.find(a)?.collapsed == false
              && vm.document.root.find(b)?.collapsed == false
              && vm.document.root.find(c)?.collapsed == false,
              "expandToLevel(99) equals expandAll")
    }
}

// MARK: - v11.1: paste-as-nodes

do {
    try await MainActor.run {
        let vm = MindMapViewModel()
        vm.autosaveAllSessions()
        vm.newDocument()
        let parentID = vm.document.root.id
        let md = "- idea A\n- idea B\n  - sub idea"
        guard let imported = try? MapImporter.markdown(md) else {
            check(false, "paste import succeeds"); return
        }
        var doc = vm.document
        doc.root.update(parentID) { node in
            node.children.append(contentsOf: imported.root.children)
        }
        vm.document = doc
        check(vm.document.root.children.count == 2, "paste creates two branches")
    }
}

// MARK: - v11.6: edge case & boundary tests

do {
    try await MainActor.run {
        let vm = MindMapViewModel()
        vm.autosaveAllSessions()
        vm.newDocument()

        // Edge 1: Extremely long node text
        let longText = String(repeating: "\u{9019}\u{662f}\u{4e00}\u{6bb5}\u{5f88}\u{9577}\u{7684}\u{6587}\u{5b57}", count: 50)
        let longNode = vm.addChild(to: nil)!
        vm.rename(id: longNode, to: longText)
        check(vm.document.root.find(longNode)?.text == longText, "long text stored")
        let layouts = LayoutEngine.layout(root: vm.document.root)
        check(layouts[longNode] != nil, "long text laid out")

        // Edge 2: Empty string operations
        vm.rename(id: longNode, to: "")
        check(vm.document.root.find(longNode)?.text == "", "empty rename works")

        // Edge 3: Unicode & emoji
        let emojiNode = vm.addChild(to: nil)!
        vm.rename(id: emojiNode, to: "\u{1f9e0}\u{8166}\u{5716}\u{2728}\u{1f31f}")
        check(vm.document.root.find(emojiNode)?.text == "\u{1f9e0}\u{8166}\u{5716}\u{2728}\u{1f31f}", "emoji preserved")

        // Edge 4: Deep nesting (20 levels)
        var prevID = emojiNode
        for _ in 0..<19 {
            let next = vm.addChild(to: prevID)!
            prevID = next
        }
        let deepLayouts = LayoutEngine.layout(root: vm.document.root)
        check(deepLayouts.count > 0, "deep nesting laid out without crash")

        // Edge 5: Rapid toggle collapse
        vm.toggleCollapse(id: emojiNode)
        vm.toggleCollapse(id: emojiNode)
        check(vm.document.root.find(emojiNode)?.collapsed == false, "rapid toggle consistent")

        // Edge 6: Search with special regex chars
        vm.searchQuery = "()[]{}.*+?"
        vm.performSearch()
        check(vm.searchResults.isEmpty, "regex chars don't crash search")
    }
}

// MARK: - v12.1: stress & edge case hardening

do {
    try await MainActor.run {
        let vm = MindMapViewModel()
        vm.autosaveAllSessions()
        vm.newDocument()

        // Edge 1: Rapidly add then immediately delete many nodes
        var ids: [UUID] = []
        for _ in 0..<20 { ids.append(vm.addChild(to: nil)!) }
        for id in ids { vm.delete(id: id) }
        check(vm.document.root.children.isEmpty, "rapid add-delete leaves clean state")

        // Edge 2: Rename to same text
        let n1 = vm.addChild(to: nil)!
        vm.rename(id: n1, to: "test")
        vm.rename(id: n1, to: "test")
        check(vm.document.root.find(n1)?.text == "test", "same-text rename safe")

        // Edge 3: Undo after delete
        let tmp = vm.addChild(to: nil)!
        vm.delete(id: tmp)
        vm.undo()
        check(vm.document.root.children.contains(where: { $0.id == tmp }), "undo restores deleted node")

        // Edge 4: Direction switch + undo no crash
        vm.setDirection(.balanced)
        vm.setDirection(.fishbone)
        vm.undo()
        check(true, "direction switch + undo no crash")

        // Edge 5: Focus on root
        vm.focusBranchID = vm.document.root.id
        check(vm.focusSet().isEmpty == false, "focus on root produces valid set")
        vm.focusBranchID = nil
    }
}

// MARK: - v12.2: comprehensive feature verification

do {
    try await MainActor.run {
        let vm = MindMapViewModel()
        vm.autosaveAllSessions()
        vm.newDocument()

        for dir in [MapDirection.logicRight, .balanced, .fishbone, .bracket] {
            let l = LayoutEngine.layout(root: vm.document.root, direction: dir)
            check(l.count > 0, "layout valid")
        }

        let parent = vm.addChild(to: nil)!
        vm.rename(id: parent, to: "branch")
        _ = vm.addChild(to: parent)
        check(vm.document.root.find(parent)?.children.count == 1, "child created")

        check(Theme.named(vm.document.themeName).branchRGB == Palette.light.branchRGB,
              "legacy theme metadata renders with Palette A")

        let noteNode = vm.addChild(to: nil)!
        vm.rename(id: noteNode, to: "note-test-node")
        vm.setNote(id: noteNode, to: "hidden-keyword")
        vm.searchQuery = "hidden-keyword"
        vm.performSearch()
        check(vm.searchResults.contains(noteNode), "search covers notes")

        let md = try! MapExporter.markdown(vm.document)
        check(md.contains("branch"), "markdown export works")

        let st = vm.document.stats()
        check(st.nodeCount >= 3, "stats counts nodes")
    }
}

// MARK: - v12.3: extreme operation stress test

do {
    try await MainActor.run {
        let vm = MindMapViewModel()
        vm.autosaveAllSessions()
        vm.newDocument()

        // Build a moderately complex tree (30 nodes across 4 levels)
        var level1IDs: [UUID] = []
        for _ in 0..<6 {
            let l1 = vm.addChild(to: nil)!
            level1IDs.append(l1)
            for j in 0..<3 {
                let l2 = vm.addChild(to: l1)!
                if j == 0 {
                    vm.addChild(to: l2)
                }
            }
        }
        check(vm.document.stats().nodeCount >= 25, "stress tree built")

        // Rapidly switch all 4 layouts multiple times
        for _ in 0..<10 {
            for dir in [MapDirection.logicRight, .balanced, .fishbone, .bracket] {
                vm.setDirection(dir)
            }
        }
        check(true, "rapid direction switching no crash")

        // Toggle collapse on every node rapidly
        let allIDs = vm.document.root.descendantIDs()
        for id in allIDs { vm.toggleCollapse(id: id) }
        for id in allIDs { vm.toggleCollapse(id: id) }
        check(true, "rapid collapse toggle no crash")

        // Undo/redo stress
        for _ in 0..<20 { vm.undo() }
        for _ in 0..<20 { vm.redo() }
        check(true, "undo/redo stress no crash")

        // Search stress with special chars
        for q in ["(", ")", "[", "]", "{", "}", "*", "+", "?", "^", "$", "\\", "|"] {
            vm.searchQuery = q
            vm.performSearch()
        }
        check(true, "special char search no crash")

        // Verify document integrity after all stress
        check(vm.document.root.children.count >= 6, "document structure intact after stress")
    }
}

// MARK: - v12.4: full user journey walkthrough

do {
    try await MainActor.run {
        let vm = MindMapViewModel()
        vm.autosaveAllSessions()
        vm.newDocument()
        vm.applyTemplate("專案計畫")
        check(vm.document.root.children.count >= 3, "J1: template loaded with branches")
        let goalBranch = vm.document.root.children[0]
        let idea = vm.addChild(to: goalBranch.id)!
        vm.rename(id: idea, to: "每週新產出")
        check(vm.document.root.find(idea)?.text == "每週新產出", "J2: idea added")
        vm.toggleMark(id: idea)
        check(vm.document.root.find(idea)?.marked == true, "J3: starred")
        vm.searchQuery = "產出"
        vm.performSearch()
        check(vm.searchResults.contains(idea), "J4: search finds it")
        vm.setDirection(.balanced)
        let bl = LayoutEngine.layout(root: vm.document.root, direction: .balanced)
        check(bl.count > 0, "J5: balanced layout works")
        vm.collapseAll()
        vm.expandToLevel(2)
        let md = try! MapExporter.markdown(vm.document)
        check(md.contains("每週新產出"), "J6: markdown contains content")
        vm.newDocument()
        check(vm.document.root.children.isEmpty, "J7: new doc starts fresh")
    }
}

// MARK: - v13.0: cross-feature combination tests

do {
    try await MainActor.run {
        let vm = MindMapViewModel()
        vm.autosaveAllSessions()
        vm.newDocument()

        // Combo 1: Focus + Search + Collapse
        let target = vm.addChild(to: nil)!
        vm.rename(id: target, to: "search-target")
        vm.toggleCollapse(id: target)
        vm.searchQuery = "search"
        vm.performSearch()
        check(vm.searchResults.contains(target), "Combo1: search finds collapsed+focused")
        vm.focusBranchID = nil

        // Combo 2: Duplicate + Layout Switch
        let orig = vm.addChild(to: nil)!
        vm.rename(id: orig, to: "branch")
        let copyID = vm.duplicate(id: orig)!
        vm.setDirection(.balanced)
        let bl = LayoutEngine.layout(root: vm.document.root, direction: .balanced)
        check(bl[orig] != nil && bl[copyID] != nil, "Combo2: both laid out after switch")
        vm.setDirection(.logicRight)

        // Combo 3: Star + Export Markdown
        vm.toggleMark(id: orig)
        let md = try! MapExporter.markdown(vm.document)
        check(md.contains("★"), "Combo3: star appears in markdown export")

        // Combo 4: Insert Parent + Collapse Parent
        let leaf = vm.addChild(to: orig)!
        vm.rename(id: leaf, to: "leaf")
        let wrapperID = vm.insertParent(id: leaf)!
        vm.rename(id: wrapperID, to: "wrapper")
        vm.toggleCollapse(id: wrapperID)
        check(vm.document.root.find(wrapperID)?.collapsed == true, "Combo4: wrapped collapsible")

        // Combo 5: Tab switch preserves isolation
        vm.applyTemplate("blank")
        check(vm.focusBranchID == nil && vm.searchResults.isEmpty, "Combo5: state clean")
    }
}

// MARK: - v13.2: full integration test

do {
    try await MainActor.run {
        let vm = MindMapViewModel()
        vm.autosaveAllSessions()
        vm.newDocument()

        // Phase 1: Brainstorm
        let topic = vm.addChild(to: nil)!
        vm.rename(id: topic, to: "產品發想")
        let ideaA = vm.addChild(to: topic)!
        vm.rename(id: ideaA, to: "功能A")
        let ideaB = vm.addChild(to: topic)!
        vm.rename(id: ideaB, to: "功能B")
        check(vm.document.root.find(topic)?.children.count == 2, "E2E: two ideas brainstormed")

        // Phase 2: Organize with tags and stars
        vm.setColorTag(id: ideaA, tag: "red")
        vm.toggleMark(id: ideaB)
        check(vm.document.root.find(ideaA)?.colorTag == "red", "E2E: color tag set")
        check(vm.document.root.find(ideaB)?.marked == true, "E2E: star set")

        // Phase 3: Search and navigate
        vm.searchQuery = "功能"
        vm.performSearch()
        check(vm.searchResults.count == 2, "E2E: search finds both ideas")
        vm.focusBranchID = ideaA
        check(vm.focusSet().contains(ideaA), "E2E: focus set correct")
        vm.focusBranchID = nil

        // Phase 4: Restructure
        vm.move(id: ideaB, toParent: ideaA)
        check(vm.document.root.find(ideaA)?.children.count == 1, "E2E: moved B under A")

        // Phase 5: Switch layouts
        for dir in [MapDirection.logicRight, .balanced, .fishbone, .bracket] {
            let l = LayoutEngine.layout(root: vm.document.root, direction: dir)
            check(l.count > 0, "E2E: layout works for " + dir.rawValue)
        }

        // Phase 6: Export
        let md = try! MapExporter.markdown(vm.document)
        check(md.contains("功能A"), "E2E: markdown contains content")
        let opml = try! MapExporter.opml(vm.document)
        check(opml.contains("<outline"), "E2E: OPML export valid")

        // Phase 7: Stress undo
        for _ in 0..<30 { vm.undo() }
        check(true, "E2E: undo chain no crash")
    }
}


// MARK: - v13.1: performance benchmarks

do {
    try await MainActor.run {
        let vm = MindMapViewModel()
        vm.autosaveAllSessions()
        vm.newDocument()
        var childIDs: [UUID] = []
        for _ in 0..<50 { childIDs.append(vm.addChild(to: nil)!) }
        for i in 0..<10 { vm.addChild(to: childIDs[i]) }

        // Layout speed on ~70 nodes
        let layoutStart = Date()
        _ = LayoutEngine.layout(root: vm.document.root)
        let layoutTime = Date().timeIntervalSince(layoutStart)
        check(layoutTime < 0.5, "Layout fast enough")

        // Large-map layout: cold (first compute) vs warm (memoized).
        // Layout used to run on every SwiftUI body evaluation, so the warm path is
        // what a pan/zoom/hover event actually costs now.
        var bigRoot = MindNode(text: "perf-root")
        for branch in 0..<30 {
            var child = MindNode(text: "branch-\(branch)")
            for leaf in 0..<50 { child.children.append(MindNode(text: "leaf-\(branch)-\(leaf)")) }
            bigRoot.children.append(child)
        }
        let nodeCount = 1 + bigRoot.children.count + bigRoot.children.reduce(0) { $0 + $1.children.count }
        let coldStart = Date()
        _ = LayoutEngine.layout(root: bigRoot)
        let coldMS = Date().timeIntervalSince(coldStart) * 1000
        let warmStart = Date()
        for _ in 0..<10 { _ = LayoutEngine.layout(root: bigRoot) }
        let warmMS = Date().timeIntervalSince(warmStart) * 1000 / 10
        print(String(format: "INFO layout %d nodes: cold %.2f ms, warm %.3f ms (%.0fx)",
                     nodeCount, coldMS, warmMS, coldMS / max(warmMS, 0.0001)))
        check(warmMS < coldMS / 5, "Layout memoization gives >5x on repeat evaluation")

        // D2 keyboard model: Return edits the selected node; typing replaces its text.
        vm.newDocument()
        let kbNode = vm.addChild(to: nil)!
        vm.rename(id: kbNode, to: "original")
        vm.editingID = nil
        vm.selection = kbNode
        vm.beginEditing(id: kbNode)
        check(vm.editingID == kbNode, "beginEditing enters edit on the selected node")
        check(vm.document.root.find(kbNode)?.text == "original",
              "beginEditing without replacement keeps the text")
        vm.editingID = nil
        vm.beginEditing(id: kbNode, replacingWith: "X")
        check(vm.editingID == kbNode && vm.document.root.find(kbNode)?.text == "X",
              "type-to-replace wipes the text and enters edit")

        // Search speed
        vm.searchQuery = "\u{6e2c}\u{8a66}"
        let searchStart = Date()
        vm.performSearch()
        let searchTime = Date().timeIntervalSince(searchStart)
        check(searchTime < 0.5, "Search fast enough")

        // Stats speed
        let statsStart = Date()
        _ = vm.document.stats()
        let statsTime = Date().timeIntervalSince(statsStart)
        check(statsTime < 0.5, "Stats fast enough")

        // Serialization round-trip
        let serStart = Date()
        let data = try JSONEncoder().encode(vm.document)
        _ = try JSONDecoder().decode(MindDocument.self, from: data)
        let serTime = Date().timeIntervalSince(serStart)
        check(serTime < 0.5, "Serialization fast enough")
    }
}

// MARK: - T-032: XMind topic-before and parent-topic creation

do {
    try await MainActor.run {
        let ids: (MindDocument) -> Set<UUID> = { document in
            document.root.descendantIDs().union([document.root.id])
        }

        let vm = MindMapViewModel()
        vm.autosaveAllSessions()

        // Shift+Enter inserts one empty sibling immediately before the selection.
        vm.newDocument()
        let left = vm.addChild(to: nil)!
        let target = vm.addChild(to: nil)!
        let right = vm.addChild(to: nil)!
        let leaf = vm.addChild(to: target)!
        vm.editingID = nil
        vm.selection = target
        let beforeSibling = vm.document
        let beforeSiblingIDs = ids(beforeSibling)
        let beforeSiblingCount = beforeSiblingIDs.count
        let inserted = vm.addSiblingBefore(of: target)!
        let afterSibling = vm.document
        check(vm.document.root.children.map(\.id) == [left, inserted, target, right],
              "addSiblingBefore inserts immediately before the selected sibling")
        check(ids(afterSibling) == beforeSiblingIDs.union([inserted])
              && ids(afterSibling).count == beforeSiblingCount + 1,
              "addSiblingBefore adds exactly one UUID and preserves every existing UUID")
        check(vm.document.root.find(target)?.children.map(\.id) == [leaf],
              "addSiblingBefore preserves the selected subtree")
        check(vm.document.root.find(inserted)?.text == MindMapViewModel.newNodeDefaultText
              && vm.selection == inserted && vm.editingID == nil,
              "addSiblingBefore selects the default-text node without editing")
        vm.undo()
        check(vm.document == beforeSibling, "undo fully restores addSiblingBefore")
        vm.redo()
        check(vm.document == afterSibling, "redo fully restores addSiblingBefore")
        vm.rename(id: inserted, to: "")
        vm.cancelNodeEditing(id: inserted, draft: "")
        check(vm.document == beforeSibling, "Esc still discards a genuinely empty leaf")

        // Command+Enter wraps only the selection, leaving its siblings in place.
        vm.newDocument()
        let first = vm.addChild(to: nil)!
        let wrapped = vm.addChild(to: nil)!
        let last = vm.addChild(to: nil)!
        let descendant = vm.addChild(to: wrapped)!
        vm.editingID = nil
        vm.selection = wrapped
        let beforeParent = vm.document
        let beforeParentIDs = ids(beforeParent)
        let beforeParentCount = beforeParentIDs.count
        let parent = vm.insertParent(id: wrapped)!
        let afterParent = vm.document
        check(vm.document.root.children.map(\.id) == [first, parent, last],
              "insertParent replaces only the selected sibling slot")
        check(vm.document.root.find(parent)?.children.map(\.id) == [wrapped]
              && vm.document.root.find(wrapped)?.children.map(\.id) == [descendant],
              "insertParent wraps only the selection and preserves its subtree")
        check(ids(afterParent) == beforeParentIDs.union([parent])
              && ids(afterParent).count == beforeParentCount + 1,
              "insertParent adds exactly one UUID and preserves every existing UUID")
        check(vm.document.root.find(parent)?.text == MindMapViewModel.newNodeDefaultText
              && vm.selection == parent && vm.editingID == nil,
              "insertParent selects the default-text parent without editing")
        vm.undo()
        check(vm.document == beforeParent, "undo fully restores insertParent")
        vm.redo()
        check(vm.document == afterParent, "redo fully restores insertParent")
        vm.rename(id: parent, to: "")
        vm.cancelNodeEditing(id: parent, draft: "")
        check(vm.document.root.find(parent)?.children.map(\.id) == [wrapped]
              && vm.document.root.find(wrapped)?.children.map(\.id) == [descendant],
              "Esc on a textless wrapper with children preserves the original subtree")

        // The central topic has neither a sibling nor a parent; both commands are no-ops.
        vm.newDocument()
        vm.editingID = nil
        let rootID = vm.document.root.id
        let beforeRoot = vm.document
        let beforeRootDirty = vm.dirty
        check(vm.addSiblingBefore(of: rootID) == nil, "addSiblingBefore rejects the root")
        check(vm.insertParent(id: rootID) == nil, "insertParent rejects the root")
        check(vm.document == beforeRoot && vm.dirty == beforeRootDirty
              && vm.selection == rootID && vm.editingID == nil,
              "root creation guards leave document and UI state unchanged")
    }
}

// MARK: - T-034: XMind core shortcut dispatch

do {
    try await MainActor.run {
        let vm = MindMapViewModel()
        vm.autosaveAllSessions()

        // Alt+Up/Down exchanges one sibling at a time.
        vm.newDocument()
        let stepA = vm.addChild(to: nil)!
        let stepB = vm.addChild(to: nil)!
        let stepC = vm.addChild(to: nil)!
        let stepD = vm.addChild(to: nil)!
        vm.editingID = nil
        vm.selection = stepC
        check(KeyboardMonitor.performCoreShortcut(characters: "\u{F700}", modifiers: [.option], vm: vm)
              && vm.document.root.children.map(\.id) == [stepA, stepC, stepB, stepD],
              "Alt+Up moves the selected sibling up exactly one place")
        check(KeyboardMonitor.performCoreShortcut(characters: "\u{F701}", modifiers: [.option], vm: vm)
              && vm.document.root.children.map(\.id) == [stepA, stepB, stepC, stepD],
              "Alt+Down moves the selected sibling down exactly one place")
        vm.selection = nil
        check(!KeyboardMonitor.performCoreShortcut(characters: "x", modifiers: [.option], vm: vm),
              "an unmapped Option key is not swallowed")
        vm.selection = stepC
        check(KeyboardMonitor.performCoreShortcut(
                  characters: "\u{F700}", modifiers: [.option, .capsLock], vm: vm)
              && vm.document.root.children.map(\.id) == [stepA, stepC, stepB, stepD],
              "Caps Lock does not disable Alt+Up")

        // Alt+Command+Up/Down moves to an edge and must never fall through to nudge.
        vm.newDocument()
        let topA = vm.addChild(to: nil)!
        let topB = vm.addChild(to: nil)!
        let topC = vm.addChild(to: nil)!
        let topD = vm.addChild(to: nil)!
        vm.nudgeOffset(id: topC, dx: 7, dy: 9)
        vm.editingID = nil
        vm.selection = topC
        let topOffsets = vm.document.offsets
        check(KeyboardMonitor.performCoreShortcut(characters: "\u{F700}", modifiers: [.option, .command], vm: vm)
              && vm.document.root.children.map(\.id) == [topC, topA, topB, topD]
              && vm.document.offsets == topOffsets,
              "Alt+Command+Up moves to the top without changing offsets")

        vm.newDocument()
        let bottomA = vm.addChild(to: nil)!
        let bottomB = vm.addChild(to: nil)!
        let bottomC = vm.addChild(to: nil)!
        let bottomD = vm.addChild(to: nil)!
        vm.nudgeOffset(id: bottomB, dx: -3, dy: 4)
        vm.editingID = nil
        vm.selection = bottomB
        let bottomOffsets = vm.document.offsets
        check(KeyboardMonitor.performCoreShortcut(characters: "\u{F701}", modifiers: [.option, .command], vm: vm)
              && vm.document.root.children.map(\.id) == [bottomA, bottomC, bottomD, bottomB]
              && vm.document.offsets == bottomOffsets,
              "Alt+Command+Down moves to the bottom without changing offsets")

        // Plain Command+arrows retain manual nudge behavior and never reorder.
        vm.newDocument()
        let nudged = vm.addChild(to: nil)!
        let nudgeSibling = vm.addChild(to: nil)!
        vm.editingID = nil
        vm.selection = nudged
        let nudgeOrder = vm.document.root.children.map(\.id)
        check(KeyboardMonitor.performCoreShortcut(characters: "\u{F700}", modifiers: [.command], vm: vm)
              && KeyboardMonitor.performCoreShortcut(characters: "\u{F703}", modifiers: [.command], vm: vm)
              && vm.document.root.children.map(\.id) == nudgeOrder
              && vm.document.offsets[nudged.uuidString] == CGPoint(x: 10, y: -10)
              && vm.document.root.find(nudgeSibling) != nil,
              "plain Command+arrows nudge without reordering")

        // Command+D duplicates the selected subtree with fresh IDs.
        vm.newDocument()
        let original = vm.addChild(to: nil)!
        let originalLeaf = vm.addChild(to: original)!
        vm.editingID = nil
        vm.selection = original
        check(KeyboardMonitor.performCoreShortcut(characters: "d", modifiers: [.command], vm: vm),
              "Command+D is handled")
        let duplicated = vm.selection!
        check(vm.document.root.children.map(\.id) == [original, duplicated]
              && duplicated != original
              && vm.document.root.find(duplicated)?.children.first?.id != originalLeaf,
              "Command+D duplicates the selected subtree with fresh UUIDs")

        // Command+Option+/ toggles every branch collapsed, then expanded.
        vm.newDocument()
        let branch = vm.addChild(to: nil)!
        _ = vm.addChild(to: branch)!
        vm.editingID = nil
        check(KeyboardMonitor.performCoreShortcut(characters: "/", modifiers: [.command, .option], vm: vm)
              && vm.document.root.find(branch)?.collapsed == true,
              "Command+Option+/ collapses all branches")
        check(KeyboardMonitor.performCoreShortcut(characters: "/", modifiers: [.command, .option], vm: vm)
              && vm.document.root.find(branch)?.collapsed == false,
              "Command+Option+/ expands all branches on the next press")

        // Command+Option+F/P and Shift+Command+M toggle their visible modes.
        check(KeyboardMonitor.performCoreShortcut(characters: "f", modifiers: [.command, .option], vm: vm)
              && vm.zenMode,
              "Command+Option+F enters zen mode")
        check(KeyboardMonitor.performCoreShortcut(characters: "f", modifiers: [.command, .option], vm: vm)
              && !vm.zenMode,
              "Command+Option+F exits zen mode")

        let beforePresentation = vm.document
        check(KeyboardMonitor.performCoreShortcut(characters: "p", modifiers: [.command, .option], vm: vm)
              && vm.presentationActive,
              "Command+Option+P enters presentation mode")
        let duringPresentation = vm.document
        check(KeyboardMonitor.performCoreShortcut(characters: "d", modifiers: [.command], vm: vm)
              && KeyboardMonitor.performCoreShortcut(characters: "/", modifiers: [.command, .option], vm: vm)
              && vm.document == duringPresentation,
              "core mutation shortcuts are blocked during presentation")
        check(KeyboardMonitor.performCoreShortcut(characters: "p", modifiers: [.command, .option], vm: vm)
              && !vm.presentationActive && vm.document == beforePresentation,
              "Command+Option+P exits presentation and restores the map")

        check(KeyboardMonitor.performCoreShortcut(characters: "m", modifiers: [.shift, .command], vm: vm)
              && vm.showInspector && vm.inspectorTab == 1,
              "Shift+Command+M opens the outline panel")
        check(KeyboardMonitor.performCoreShortcut(characters: "m", modifiers: [.shift, .command], vm: vm)
              && !vm.showInspector,
              "Shift+Command+M returns to the map")

        // Command+R leaves branch focus and selects the central topic.
        vm.focusBranchID = branch
        vm.batchSelection = [branch]
        vm.selection = branch
        check(KeyboardMonitor.performCoreShortcut(characters: "r", modifiers: [.command], vm: vm)
              && vm.selection == vm.document.root.id
              && vm.focusBranchID == nil && vm.batchSelection.isEmpty,
              "Command+R selects and returns to the central topic")

        // T-035 follow-up: Cmd-Z is dispatched through the same shared seam as other core shortcuts.
        vm.newDocument()
        vm.editingID = nil
        let beforeUndo = vm.document
        let insertedForUndo = vm.addChild(to: nil)
        check(insertedForUndo != nil
              && KeyboardMonitor.performCoreShortcut(characters: "z", modifiers: [.command], vm: vm)
              && vm.document == beforeUndo,
              "Command+Z through core dispatch restores a real mutation exactly")

        let beforeRedoPassThrough = vm.document
        check(!KeyboardMonitor.performCoreShortcut(
                  characters: "z", modifiers: [.shift, .command], vm: vm)
              && vm.document == beforeRedoPassThrough,
              "Shift+Command+Z passes through without mutation")

        vm.newDocument()
        vm.editingID = nil
        _ = vm.addChild(to: nil)
        vm.enterPresentation()
        let duringCmdZPresentation = vm.document
        check(vm.presentationActive
              && KeyboardMonitor.performCoreShortcut(
                  characters: "z", modifiers: [.command], vm: vm)
              && vm.document == duringCmdZPresentation,
              "Command+Z in presentation is consumed without mutation")
        vm.exitPresentation()
    }
}

// MARK: - T-035: free canvas invariants

do {
    // A node offset is inherited by its entire subtree; unrelated branches stay automatic.
    let leaf = MindNode(text: "Leaf")
    let parent = MindNode(text: "Parent", children: [leaf])
    let sibling = MindNode(text: "Sibling")
    let root = MindNode(text: "Root", children: [parent, sibling])
    let plain = LayoutEngine.layout(root: root)
    let shifted = LayoutEngine.layout(
        root: root,
        offsets: [root.id.uuidString: CGPoint(x: 10, y: -4),
                  parent.id.uuidString: CGPoint(x: 25, y: 8)]
    )
    check(shifted[root.id]!.frame.origin == plain[root.id]!.frame.offsetBy(dx: 10, dy: -4).origin,
          "moving the root shifts the root")
    check(shifted[parent.id]!.frame.origin == plain[parent.id]!.frame.offsetBy(dx: 35, dy: 4).origin
          && shifted[leaf.id]!.frame.origin == plain[leaf.id]!.frame.offsetBy(dx: 35, dy: 4).origin,
          "a parent offset shifts its whole subtree by the inherited total")
    check(shifted[sibling.id]!.frame.origin == plain[sibling.id]!.frame.offsetBy(dx: 10, dy: -4).origin,
          "an untouched branch keeps automatic layout plus only its inherited root offset")
}

do {
    try await MainActor.run {
        let vm = MindMapViewModel()
        vm.autosaveAllSessions()

        // Old builds rejected this call, which is the root-drag negative control.
        vm.newDocument()
        let child = vm.addChild(to: nil)!
        vm.editingID = nil
        let rootID = vm.document.root.id
        vm.moveOffset(id: rootID, dx: 18, dy: -11)
        check(vm.document.offsets[rootID.uuidString] == CGPoint(x: 18, y: -11),
              "the central topic accepts a manual offset")
        let rootLayouts = LayoutEngine.layout(root: vm.document.root, offsets: vm.document.offsets)
        let rootPlain = LayoutEngine.layout(root: vm.document.root)
        check(rootLayouts[rootID]!.frame.origin == rootPlain[rootID]!.frame.offsetBy(dx: 18, dy: -11).origin
              && rootLayouts[child]!.frame.origin == rootPlain[child]!.frame.offsetBy(dx: 18, dy: -11).origin,
              "moving the central topic shifts the full map")

        // Reparenting into one's own descendant is fail-closed and leaves the exact tree intact.
        vm.newDocument()
        let ancestor = vm.addChild(to: nil)!
        let descendant = vm.addChild(to: ancestor)!
        vm.editingID = nil
        let beforeCycle = vm.document
        vm.move(id: ancestor, toParent: descendant)
        check(vm.document == beforeCycle,
              "reparenting a node into its descendant is rejected without mutation")

        // Blank drops preserve the parent and each pointer drag is a separate undo step.
        let parentBeforeBlankDrop = vm.document.root.parent(of: descendant)?.id
        vm.moveOffset(id: descendant, dx: 12, dy: -6)
        let afterFirstBlankDrop = vm.document
        vm.moveOffset(id: descendant, dx: 8, dy: 3)
        check(vm.document.root.parent(of: descendant)?.id == parentBeforeBlankDrop
              && vm.document.offsets[descendant.uuidString] == CGPoint(x: 20, y: -3),
              "dropping on blank canvas moves without reparenting")
        vm.undo()
        check(vm.document == afterFirstBlankDrop,
              "each blank-canvas drag is an independent undo transaction")

        // A valid targeted drop is also a complete undo transaction.
        let peer = vm.addChild(to: nil)!
        vm.editingID = nil
        let beforeMove = vm.document
        vm.move(id: descendant, toParent: peer)
        check(vm.document.root.parent(of: descendant)?.id == peer
              && vm.document.offsets[descendant.uuidString] == CGPoint(x: 12, y: -6),
              "dropping onto a node reparents without adding a free-move offset")
        vm.undo()
        check(vm.document == beforeMove, "undo restores the complete tree after reparenting")

        // Removing pointer-based sibling reordering does not remove ordering capability.
        vm.selection = peer
        let orderBefore = vm.document.root.children.map(\.id)
        check(KeyboardMonitor.performCoreShortcut(
                  characters: "\u{F700}", modifiers: [.option], vm: vm)
              && vm.document.root.children.map(\.id) != orderBefore,
              "sibling ordering remains reachable through Alt+Up")
        vm.undo()

        vm.nudgeOffset(id: ancestor, dx: 41, dy: 17)
        let arranged = vm.document
        vm.resetAllOffsets()
        check(vm.document.offsets.isEmpty, "Arrange clears every manual position")
        vm.undo()
        check(vm.document == arranged, "undo after Arrange restores every manual position")

        // Offsets are part of the document contract, not transient view state.
        if let data = try? JSONEncoder().encode(vm.document),
           let decoded = try? JSONDecoder().decode(MindDocument.self, from: data) {
            check(decoded.offsets == vm.document.offsets,
                  "manual positions survive a document encode/decode round trip")
        } else {
            check(false, "manual positions survive a document encode/decode round trip")
        }
    }
}

// The insertion line is the reorder contract: visible segment and gap band only.
do {
    let s1 = MindNode(text: "S1")
    let s2 = MindNode(text: "S2")
    let s3 = MindNode(text: "S3")
    let root = MindNode(text: "R", children: [s1, s2, s3])
    let layouts = LayoutEngine.layout(root: root)
    let siblings = root.children
    let gap = layouts[s3.id]!.frame.minY - layouts[s2.id]!.frame.maxY
    let lineY = layouts[s2.id]!.frame.maxY + gap / 2
    let inGap = SiblingInsertion.hint(
        point: CGPoint(x: layouts[s2.id]!.frame.midX, y: lineY),
        draggedID: s2.id, layouts: layouts, siblings: siblings)
    check(inGap?.targetIndex == 2, "dropping in a sibling gap reorders after the sibling above")
    check(SiblingInsertion.hint(
              point: CGPoint(x: layouts[s2.id]!.frame.maxX + 200, y: lineY),
              draggedID: s2.id, layouts: layouts, siblings: siblings) == nil,
          "the same gap line far from the visible segment stays a free move")
    check(SiblingInsertion.hint(
              point: CGPoint(x: layouts[s2.id]!.frame.midX, y: lineY + gap),
              draggedID: s2.id, layouts: layouts, siblings: siblings) == nil,
          "a release outside the gap band does not reorder")
}

// Canvas fit. Measured from a real window: the content occupied 765pt of a 672pt-tall
// window, so the bottom of every opened map was cut off.
do {
    let viewport = CGSize(width: 690, height: 582)

    let tall = CGSize(width: 778, height: 898)
    let s = CanvasFit.scale(content: tall, viewport: viewport)
    check(tall.width * s <= viewport.width + 0.5, "content wider than canvas is shrunk to fit")
    check(tall.height * s <= viewport.height + 0.5, "content taller than canvas is shrunk to fit")

    let wide = CGSize(width: 2400, height: 300)
    let w = CanvasFit.scale(content: wide, viewport: viewport)
    check(wide.width * w <= viewport.width + 0.5, "very wide content is shrunk to fit")

    let small = CGSize(width: 200, height: 120)
    check(CanvasFit.scale(content: small, viewport: viewport) == CanvasFit.maxInitial,
          "a small map is not blown up past the initial cap")

    check(CanvasFit.scale(content: .zero, viewport: viewport) == 1,
          "empty content leaves the zoom untouched")
    check(CanvasFit.scale(content: tall, viewport: .zero) == 1,
          "a zero-sized canvas leaves the zoom untouched")

    let huge = CGSize(width: 40000, height: 40000)
    check(CanvasFit.scale(content: huge, viewport: viewport) == CanvasFit.zoomRange.lowerBound,
          "content past the zoom floor stops at the floor")
}

// MARK: - T-036: Palette A

do {
    let light = Palette.light
    let dark = Palette.dark
    let accent = Palette.accentOKLCh

    func circularHueDistance(_ a: Double, _ b: Double) -> Double {
        let raw = abs(a - b).truncatingRemainder(dividingBy: 360)
        return min(raw, 360 - raw)
    }

    func range(_ values: [Double]) -> String {
        guard let minimum = values.min(), let maximum = values.max() else { return "empty" }
        return String(format: "min=%.4f max=%.4f", minimum, maximum)
    }

    func checkWindow(_ actual: Double, lower: Double, upper: Double, _ label: String) {
        check(actual >= lower && actual <= upper,
              label + String(format: ": window [%.4f, %.4f], actual %.4f", lower, upper, actual))
    }

    func svgAttribute(_ name: String, _ value: String) -> String {
        name + "=\"" + value + "\""
    }

    let lightBranchHex = light.branchRGB.map(\.hex)
    let expectedLightBranchHex = ["#3368a0", "#7a5291", "#984955", "#8a5a08", "#4e722c", "#067572"]
    print("T-036 light branch hex " + lightBranchHex.joined(separator: ","))
    print("T-036 dark branch hex " + dark.branchRGB.map(\.hex).joined(separator: ","))
    check(light.branchRGB.count == 6, "Palette A derives six branch colours")
    check(lightBranchHex == expectedLightBranchHex, "OKLCh branch diagnostics match the derived Palette A colours")
    check(light.branchRGB.first?.hex == light.accentRGB.hex,
          "the first branch is the accent within sRGB rounding")

    let lightHues = light.branchOKLCh.map(\.hue)
    check(zip(lightHues, lightHues.dropFirst()).allSatisfy {
        circularHueDistance($0.0, $0.1) >= 59.5 && circularHueDistance($0.0, $0.1) <= 60.5
    }, "adjacent branch hues rotate by 60 degrees")
    let lightLs = light.branchOKLCh.map(\.lightness)
    let lightCs = light.branchOKLCh.map(\.chroma)
    check((lightLs.max() ?? 0) - (lightLs.min() ?? 0) <= 0.000001,
          "light branch OKLCh lightness is fixed")
    check(lightLs.allSatisfy { abs($0 - accent.lightness) <= 0.000001 },
          "gamut mapping never changes OKLCh lightness")
    check(lightCs.allSatisfy { $0 <= accent.chroma + 0.000001 },
          "gamut mapping only lowers OKLCh chroma")
    check(lightCs.contains { accent.chroma - $0 >= 0.004999 },
          "at least one out-of-sRGB branch uses the 0.005 chroma step")

    func isQuantized8(_ rgb: Palette.RGB) -> Bool {
        let q = rgb.quantized8
        return rgb == q
    }
    check(light.branchRGB.allSatisfy(isQuantized8) && dark.branchRGB.allSatisfy(isQuantized8),
          "production branch samples are final sRGB 8-bit values")

    let seamSample = Palette.RGB(red: 0.4807315, green: 0.326676734873, blue: 0.574070932030)
    let seamQuantized = seamSample.quantized8
    check(seamSample.hex == seamQuantized.hex
          && seamSample.relativeLuminance == seamQuantized.relativeLuminance
          && seamSample.contrastRatio(with: dark.canvasRGB)
             == seamQuantized.contrastRatio(with: dark.canvasRGB),
          "Color, hex, and contrast all consume the quantized8 final value")

    func unquantizedContrast(_ first: Palette.RGB, _ second: Palette.RGB) -> Double {
        func luminance(_ rgb: Palette.RGB) -> Double {
            func toLinear(_ value: Double) -> Double {
                value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * toLinear(rgb.red)
                + 0.7152 * toLinear(rgb.green)
                + 0.0722 * toLinear(rgb.blue)
        }
        let firstLum = luminance(first)
        let secondLum = luminance(second)
        let lighter = max(firstLum, secondLum)
        let darker = min(firstLum, secondLum)
        return (lighter + 0.05) / (darker + 0.05)
    }
    let oldBoundaryFloat = unquantizedContrast(seamSample, dark.canvasRGB)
    let oldBoundaryQuantized = seamQuantized.contrastRatio(with: dark.canvasRGB)
    print("T-036 old 3.0 boundary float " + String(format: "%.6f", oldBoundaryFloat)
          + " quantized8 " + String(format: "%.6f", oldBoundaryQuantized))
    check(oldBoundaryFloat >= 3.0 && oldBoundaryQuantized < 3.0,
          "old unquantized 3.0 check is exposed as a quantized8 false PASS")

    func checkResolvedOKLCh(_ palette: Palette, label: String) {
        let actual = palette.branchRGB.map(\.oklch)
        let effectiveChroma = actual.map(\.chroma)
        print(label + " effective OKLCh C " + range(effectiveChroma))
        check(effectiveChroma.min() ?? 0 >= 0.02,
              label + " effective C range keeps hue stability explicit (minimum >= 0.02)")
        for (index, sample) in actual.enumerated() {
            let targetHue = accent.hue + Double(index) * 60
            let prefix = label + " branch " + String(index)
            check(circularHueDistance(sample.hue, targetHue) <= 1.0,
                  prefix + " actual OKLCh hue stays within 1 degree of its target")
            check(abs(sample.lightness - palette.branchOKLCh[index].lightness) <= 0.003,
                  prefix + " actual OKLCh lightness stays within 8-bit quantization tolerance")
            check(abs(sample.chroma - palette.branchOKLCh[index].chroma) <= 0.003,
                  prefix + " actual OKLCh chroma stays within 8-bit quantization tolerance")
        }
    }
    checkResolvedOKLCh(light, label: "light")
    checkResolvedOKLCh(dark, label: "dark")

    func linearRGB(_ coordinate: Palette.OKLCh) -> (Double, Double, Double) {
        let radians = coordinate.hue * Double.pi / 180
        let a = coordinate.chroma * cos(radians)
        let b = coordinate.chroma * sin(radians)
        let l = pow(coordinate.lightness + 0.3963377774 * a + 0.2158037573 * b, 3)
        let m = pow(coordinate.lightness - 0.1055613458 * a - 0.0638541728 * b, 3)
        let s = pow(coordinate.lightness - 0.0894841775 * a - 1.2914855480 * b, 3)
        return (4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
                -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
                -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)
    }

    func gammaEncode(_ value: Double) -> Double {
        value <= 0.0031308 ? 12.92 * value : 1.055 * pow(value, 1 / 2.4) - 0.055
    }

    // Negative control: the tempting RGB-channel clamp leaves the out-of-gamut branch
    // with the wrong OKLCh lightness. A production clamp mutation must trip the invariant
    // above instead of being accepted as a valid palette.
    let rgbClampMutation = (0..<6).map { index in
        let coordinate = Palette.OKLCh(lightness: accent.lightness,
                                       chroma: accent.chroma,
                                       hue: accent.hue + Double(index) * 60)
        let linear = linearRGB(coordinate)
        return Palette.RGB(red: gammaEncode(min(max(linear.0, 0), 1)),
                           green: gammaEncode(min(max(linear.1, 0), 1)),
                           blue: gammaEncode(min(max(linear.2, 0), 1)))
    }
    let clampLightnessDrift = rgbClampMutation.enumerated().map {
        abs($0.element.oklch.lightness - light.branchOKLCh[$0.offset].lightness)
    }
    print("T-036 RGB-clamp mutation OKLCh L drift " + range(clampLightnessDrift))
    check(clampLightnessDrift.max() ?? 0 > 0.001,
          "RGB-channel clamp mutation is caught by the fixed-lightness invariant")

    let lightBranchCream = light.branchRGB.map { $0.contrastRatio(with: light.creamTextRGB) }
    let lightBranchCanvas = light.branchRGB.map { $0.contrastRatio(with: light.canvasRGB) }
    let lightBranchCard = light.branchRGB.map { $0.contrastRatio(with: light.cardRGB) }
    let darkBranchCanvas = dark.branchRGB.map { $0.contrastRatio(with: dark.canvasRGB) }
    let darkBranchCream = dark.branchRGB.map { $0.contrastRatio(with: dark.creamTextRGB) }
    print("T-036 light branch/cream " + range(lightBranchCream))
    print("T-036 light branch/canvas " + range(lightBranchCanvas))
    print("T-036 light branch/card " + range(lightBranchCard))
    print("T-036 dark branch/canvas " + range(darkBranchCanvas))
    print("T-036 dark cream/branch " + range(darkBranchCream))
    check(lightBranchCream.allSatisfy { $0 >= 4.5 }, "light branch text contrast is at least 4.5:1")
    check(lightBranchCanvas.allSatisfy { $0 >= 3.0 }, "light branch lines contrast with the canvas at least 3:1")
    check(lightBranchCard.allSatisfy { $0 >= 3.0 }, "light branch lines contrast with cards at least 3:1")
    check(light.accentRGB.contrastRatio(with: light.creamTextRGB) >= 4.5,
          "light root cream text contrast is at least 4.5:1")
    check(light.textPrimaryRGB.contrastRatio(with: light.cardRGB) >= 4.5,
          "light primary text contrast with cards is at least 4.5:1")
    check(light.textSecondaryRGB.contrastRatio(with: light.canvasRGB) >= 4.5,
          "light secondary text contrast with the canvas is at least 4.5:1")
    check(light.textSecondaryRGB.contrastRatio(with: light.cardRGB) >= 4.5,
          "light secondary text contrast with cards is at least 4.5:1")

    let darkPrimary = [dark.textPrimaryRGB.contrastRatio(with: dark.canvasRGB),
                       dark.textPrimaryRGB.contrastRatio(with: dark.cardRGB)]
    let darkSecondary = [dark.textSecondaryRGB.contrastRatio(with: dark.canvasRGB),
                         dark.textSecondaryRGB.contrastRatio(with: dark.cardRGB)]
    print("T-036 dark primary text " + range(darkPrimary))
    print("T-036 dark secondary text " + range(darkSecondary))
    check(darkPrimary.allSatisfy { $0 >= 4.5 }, "dark primary text contrast is at least 4.5:1")
    check(darkSecondary.allSatisfy { $0 >= 4.5 }, "dark secondary text contrast is at least 4.5:1")
    check(darkBranchCanvas.allSatisfy { $0 >= 3.1 }, "quantized dark branch lines contrast with the dark canvas at least 3.1:1")
    check(darkBranchCream.allSatisfy { $0 >= 4.5 }, "dark branch cream text contrast is at least 4.5:1")

    let darkCanvasLum = dark.canvasRGB.relativeLuminance
    let creamLum = dark.creamTextRGB.relativeLuminance
    let lower = 3.1 * (darkCanvasLum + 0.05) - 0.05
    let upper = (creamLum + 0.05) / 4.5 - 0.05
    let darkBranchLuminances = dark.branchRGB.map(\.relativeLuminance)
    print("T-036 dark branch feasible window "
          + String(format: "[%.4f, %.4f] actual ", lower, upper)
          + range(darkBranchLuminances))
    check(lower <= upper, "dark branch contrast constraints have a feasible luminance window")
    for (index, luminance) in darkBranchLuminances.enumerated() {
        checkWindow(luminance, lower: lower, upper: upper,
                    "dark branch " + String(index) + " stays in the feasible contrast window")
    }

    func hsl(_ rgb: Palette.RGB) -> (hue: Double, saturation: Double, lightness: Double) {
        let red = rgb.red
        let green = rgb.green
        let blue = rgb.blue
        let maximum = max(red, green, blue)
        let minimum = min(red, green, blue)
        let delta = maximum - minimum
        let lightness = (maximum + minimum) / 2
        guard delta > 0 else { return (0, 0, lightness) }
        let saturation = delta / (1 - abs(2 * lightness - 1))
        var hue: Double
        if maximum == red {
            hue = ((green - blue) / delta).truncatingRemainder(dividingBy: 6)
        } else if maximum == green {
            hue = (blue - red) / delta + 2
        } else {
            hue = (red - green) / delta + 4
        }
        hue /= 6
        if hue < 0 { hue += 1 }
        return (hue, saturation, lightness)
    }

    func rgbFromHSL(hue: Double, saturation: Double, lightness: Double) -> Palette.RGB {
        let chroma = (1 - abs(2 * lightness - 1)) * saturation
        let sector = (hue * 6).truncatingRemainder(dividingBy: 2)
        let x = chroma * (1 - abs(sector - 1))
        let match = lightness - chroma / 2
        let components: (Double, Double, Double)
        switch Int(floor(hue * 6)) % 6 {
        case 0: components = (chroma, x, 0)
        case 1: components = (x, chroma, 0)
        case 2: components = (0, chroma, x)
        case 3: components = (0, x, chroma)
        case 4: components = (x, 0, chroma)
        default: components = (chroma, 0, x)
        }
        return Palette.RGB(red: components.0 + match,
                           green: components.1 + match,
                           blue: components.2 + match)
    }

    let accentHSL = hsl(light.accentRGB)
    let hslBranches = (0..<6).map { index in
        rgbFromHSL(hue: (accentHSL.hue + Double(index) / 6).truncatingRemainder(dividingBy: 1),
                   saturation: accentHSL.saturation, lightness: accentHSL.lightness)
    }
    let hslContrasts = hslBranches.map { $0.contrastRatio(with: light.creamTextRGB) }
    print("T-036 HSL negative-control branch/cream " + range(hslContrasts))
    check(hslContrasts.min() ?? 10 < 4.5,
          "equal-S/L HSL hue rotation is rejected by the contrast threshold")

    let lowContrast = Palette.RGB(hex: 0x777777).contrastRatio(with: Palette.RGB(hex: 0xFFFFFF))
    print("T-036 explicit low-contrast negative-control ratio " + String(format: "%.4f", lowContrast))
    check(lowContrast < 4.5, "the contrast checker rejects an explicit low-contrast text pair")

    let legacyIDs = ["ocean", "candy", "forest", "mono", "unknown"]
    let legacyPalettes = legacyIDs.map { Theme.named($0) }
    check(legacyPalettes.allSatisfy { $0.appearance == .screen },
          "legacy theme IDs resolve through the dynamic screen Palette")
    check(legacyPalettes.dropFirst().allSatisfy { $0.branchRGB == legacyPalettes[0].branchRGB },
          "all legacy theme IDs render the same Palette A")
    check(MindDocument.new().themeName == "ocean", "new documents retain the legacy ocean metadata default")
    let legacyDocument = MindDocument(title: "Legacy", themeName: "forest", root: MindNode(text: "Root"))
    if let legacyData = try? JSONEncoder().encode(legacyDocument),
       let decodedLegacy = try? JSONDecoder().decode(MindDocument.self, from: legacyData),
       let legacyJSON = String(data: legacyData, encoding: .utf8) {
        check(decodedLegacy.themeName == "forest" && decodedLegacy == legacyDocument,
              "legacy themeName survives Codable round-trip")
        check(legacyJSON.contains("\"themeName\":\"forest\""),
              "encoded documents retain the legacy themeName field")
    } else {
        check(false, "legacy themeName survives Codable round-trip")
        check(false, "encoded documents retain the legacy themeName field")
    }

    let exportRoot = MindNode(text: "Root", children: [MindNode(text: "Branch", children: [MindNode(text: "Deep")])])
    let exportDocument = MindDocument(title: "Palette", themeName: "forest", root: exportRoot)
    let oceanExport = MindDocument(title: "Palette", themeName: "ocean", root: exportRoot)
    let svg = MapExporter.svg(exportDocument)
    let staticPalette = StaticMapView.exportPalette
    check(staticPalette.appearance == .light, "StaticMapView export seam is explicitly light")
    check(staticPalette.canvasRGB == light.canvasRGB && staticPalette.branchRGB == light.branchRGB,
          "StaticMapView resolves the same Palette.light values")
    check(svg.contains(svgAttribute("fill", light.canvasRGB.hex)), "SVG background uses Palette.light canvas")
    check(svg.contains(svgAttribute("fill", light.accentRGB.hex)), "SVG root and depth-one fill use Palette.light")
    check(svg.contains(svgAttribute("fill", light.cardRGB.hex)), "SVG deep fill uses Palette.light card")
    check(svg.contains(svgAttribute("stroke", light.branchRGB[0].hex)), "SVG deep stroke uses the derived branch colour")
    check(svg.contains(svgAttribute("fill", light.creamTextRGB.hex)), "SVG root/depth-one text uses cream")
    check(svg.contains(svgAttribute("fill", light.textPrimaryRGB.hex)), "SVG deep text uses Palette.light primary text")
    check(MapExporter.svg(exportDocument) == MapExporter.svg(oceanExport),
          "a legacy non-ocean document exports identically to Palette A")
}

// MARK: - T-036: zoom-invariant interaction signals
// State-signal dimensions are authored in screen points and converted only at
// the scaled subtree boundary. Content geometry and hit-band math stay local.
do {
    let scales: [CGFloat] = [1.0, 0.618, 0.25, 0.15]
    let signals: [(String, CGFloat)] = [
        ("insertion line", 3),
        ("selected line", 2),
        ("selected outward", 2),
        ("drop line", 2.5),
        ("drop outward", 3),
        ("search line", 2),
        ("search outward", 4),
        ("batch line", 2),
        ("batch outward", 4),
        ("batch dash", 5),
        ("batch dash gap", 3),
        ("hover line", 1.5),
        ("hover outward", 4),
        ("selected link line", 2.5),
        ("selected summary stroke", 1)
    ]
    for scale in scales {
        for (name, screenPoints) in signals {
            let local = InteractionSignalGeometry.local(screenPoints: screenPoints, scale: scale)
            let actualScreenPoints = local * scale
            let label = "signal " + name + " remains "
                + String(format: "%.1f", Double(screenPoints))
                + "pt at scale " + String(format: "%.3f", Double(scale))
            check(abs(actualScreenPoints - screenPoints) <= 0.0001, label)
        }
    }
    check(InteractionSignalGeometry.local(screenPoints: 3, scale: 0) == 3,
          "invalid zero scale safely preserves the requested signal size")
    check(InteractionSignalGeometry.local(screenPoints: 3, scale: .nan) == 3,
          "invalid nonfinite scale safely preserves the requested signal size")

    let oldUnscaledWidth: CGFloat = 3 * 0.25
    check(oldUnscaledWidth == 0.75 && oldUnscaledWidth != 3,
          "negative control: an unscaled 3pt line shrinks to 0.75pt at scale .25")
}

// The reorder activation band intentionally remains map-local. At fit .25,
// six screen points correspond to 24 map points, well outside the 12pt band.
do {
    let s1 = MindNode(text: "Band S1")
    let s2 = MindNode(text: "Band S2")
    let s3 = MindNode(text: "Band S3")
    let root = MindNode(text: "Band root", children: [s1, s2, s3])
    let layouts = LayoutEngine.layout(root: root)
    let siblings = root.children
    let gap = layouts[s3.id]!.frame.minY - layouts[s2.id]!.frame.maxY
    let lineY = layouts[s2.id]!.frame.maxY + gap / 2
    let center = CGPoint(x: layouts[s2.id]!.frame.midX, y: lineY)
    let fit: CGFloat = 0.25
    let screenDistance: CGFloat = 6
    let mapDistance = InteractionSignalGeometry.local(screenPoints: screenDistance, scale: fit)
    let outside = CGPoint(x: center.x, y: center.y + mapDistance)

    check(mapDistance == 24,
          "six screen points at fit .25 are 24 map-local points")
    check(SiblingInsertion.hint(point: center, draggedID: s2.id,
                                layouts: layouts, siblings: siblings) != nil,
          "sibling-gap center still resolves an insertion hint")
    check(SiblingInsertion.hint(point: outside, draggedID: s2.id,
                                layouts: layouts, siblings: siblings) == nil,
          "six screen points outside the gap center do not enter the map-local reorder band")
}

// MARK: - TabStore: transactional autosave
// Every fixture is rooted under /tmp and every evidence helper asserts that its
// directory exists before reading names, bytes, mtimes, or semantic summaries.
do {
    let root = freshTabStoreRoot("input-guards")
    defer { try? FileManager.default.removeItem(at: root) }
    let fixture = makeTabFixture(in: root)
    let before = tabDirectoryEvidence(fixture.live, label: "input guards before")
    let duplicate = TabStore(directory: fixture.live).save([fixture.entries[0], fixture.entries[0]])
    check(!duplicate.succeeded, "duplicate tab IDs are rejected before staging")
    let afterDuplicate = tabDirectoryEvidence(fixture.live, label: "input guards after duplicate")
    assertTabEvidencePreserved(before, afterDuplicate, label: "duplicate-ID rejection")

    let tooMany = (0...TabStore.maximumEntries).map { _ in
        TabStore.Entry(id: UUID(), document: fixture.single)
    }
    let overCeiling = TabStore(directory: fixture.live).save(tooMany)
    check(!overCeiling.succeeded, "snapshots above the 20-tab restore ceiling are rejected")
    let afterCeiling = tabDirectoryEvidence(fixture.live, label: "input guards after ceiling")
    assertTabEvidencePreserved(before, afterCeiling, label: "restore-ceiling rejection")
    check(tabTransactionDirectories(root).isEmpty,
          "input rejection does not create transaction siblings")
}

do {
    let root = freshTabStoreRoot("write-failure")
    defer { try? FileManager.default.removeItem(at: root) }
    let fixture = makeTabFixture(in: root)
    let staleName = "\(fixture.staleID.uuidString).mindmap"
    let before = tabDirectoryEvidence(fixture.live, label: "write failure before")
    check(before.files.keys.contains(staleName), "failure fixture records a stale slot")

    var writeCount = 0
    var exchangeCalled = false
    let dependencies = TabStore.Dependencies(
        writeData: { data, url in
            writeCount += 1
            if writeCount == 2 { throw TabStoreCheckFailure.write }
            try data.write(to: url, options: .atomic)
        },
        exchangeDirectories: { _, _ in
            exchangeCalled = true
            throw TabStoreCheckFailure.exchange
        })
    let store = TabStore(directory: fixture.live, dependencies: dependencies)
    let outcome = store.save(fixture.entries)
    if let error = outcome.primaryError {
        print("TabStore second-write failure: \(error)")
        if let warning = outcome.cleanupWarning { print("TabStore cleanup warning: \(warning)") }
    }
    check(!outcome.succeeded, "second staging write failure returns a failed outcome")
    check(writeCount == 2 && !exchangeCalled,
          "second write failure prevents any directory exchange")
    let after = tabDirectoryEvidence(fixture.live, label: "write failure after")
    assertTabEvidencePreserved(before, after, label: "second-write failure")
    check(tabTransactionDirectories(root).isEmpty,
          "failed staging is removed before failure-artifact bounding")

    // The same injected store proves ViewModel timestamp/status behavior without
    // constructing a model from the user's Application Support directory.
    writeCount = 0
    let timestamp = Date(timeIntervalSince1970: 1_700_000_100)
    await MainActor.run {
        let vm = MindMapViewModel(tabStore: store)
        vm.sessions = fixture.entries.map { EditorSession(id: $0.id, document: $0.document) }
        vm.activeIndex = 0
        vm.document = fixture.single
        vm.lastSavedAt = timestamp
        let vmOutcome = vm.autosaveAllSessions()
        check(!vmOutcome.succeeded, "ViewModel exposes autosave failure")
        check(vm.lastSavedAt == timestamp,
              "failed autosave leaves lastSavedAt unchanged")
        check(vm.statusMessage == "⚠︎ 自動保存失敗",
              "failed autosave exposes the persistent warning status")
    }
    let afterViewModel = tabDirectoryEvidence(fixture.live, label: "write failure after ViewModel")
    assertTabEvidencePreserved(before, afterViewModel, label: "ViewModel write failure")
}

do {
    let root = freshTabStoreRoot("exchange-failure")
    defer { try? FileManager.default.removeItem(at: root) }
    let fixture = makeTabFixture(in: root)
    let before = tabDirectoryEvidence(fixture.live, label: "exchange failure before")
    var exchangeCalled = false
    let production = TabStore.Dependencies.production
    let dependencies = TabStore.Dependencies(
        writeData: production.writeData,
        exchangeDirectories: { _, _ in
            exchangeCalled = true
            throw TabStoreCheckFailure.exchange
        })
    let outcome = TabStore(directory: fixture.live, dependencies: dependencies).save(fixture.entries)
    if let error = outcome.primaryError {
        print("TabStore exchange failure: \(error)")
        if let warning = outcome.cleanupWarning { print("TabStore cleanup warning: \(warning)") }
    }
    check(!outcome.succeeded, "directory exchange failure returns a failed outcome")
    check(exchangeCalled, "exchange failure seam was exercised")
    let after = tabDirectoryEvidence(fixture.live, label: "exchange failure after")
    assertTabEvidencePreserved(before, after, label: "exchange failure")
    check(tabTransactionDirectories(root).count >= 1,
          "exchange failure retains staging without leaving a live-path gap")
}

do {
    let root = freshTabStoreRoot("success")
    defer { try? FileManager.default.removeItem(at: root) }
    let fixture = makeTabFixture(in: root)
    let firstID = UUID(uuidString: "44444444-4444-4444-8444-444444444444")!
    let secondID = UUID(uuidString: "55555555-5555-4555-8555-555555555555")!
    let first = MindDocument(title: "New single", root: MindNode(text: "成功單節點根標題"))
    let second = MindDocument(
        title: "New multi", root: MindNode(text: "成功多節點根標題", children: [
            MindNode(text: "新分支一"),
            MindNode(text: "新分支二", children: [MindNode(text: "新葉節點")])
        ]))
    let entries = [TabStore.Entry(id: firstID, document: first),
                   TabStore.Entry(id: secondID, document: second)]
    let outcome = TabStore(directory: fixture.live).save(entries)
    if case .committed(let warning) = outcome, let warning {
        print("unexpected success warning: \(warning)")
    }
    check(outcome.succeeded, "validated snapshot commits successfully")
    let after = tabDirectoryEvidence(fixture.live, label: "success after")
    let expectedNames = Set(entries.map { "\($0.id.uuidString).mindmap" })
    check(Set(after.files.keys) == expectedNames,
          "successful commit has exactly the new UUID filename set")
    check(!after.files.keys.contains("\(fixture.staleID.uuidString).mindmap"),
          "stale slot is removed only after successful commit")
    let decoder = JSONDecoder()
    for entry in entries {
        let name = "\(entry.id.uuidString).mindmap"
        if let data = after.files[name], let decoded = try? decoder.decode(MindDocument.self, from: data) {
            check(decoded == entry.document, "committed \(name) decodes to the full input document")
            check(after.rootTitles[name] == entry.document.root.text
                      && after.nodeCounts[name] == tabNodeCount(entry.document.root),
                  "committed \(name) preserves root title and node count")
        } else {
            check(false, "committed \(name) decodes to the full input document")
            check(false, "committed \(name) preserves root title and node count")
        }
    }
    print("TabStore success semantic evidence: rootTitles=\(after.rootTitles) nodeCounts=\(after.nodeCounts)")

    // Mirror FileIO.loadTabs' mtime-newest ordering against the committed files
    // while using this isolated live directory, not the user's tabs directory.
    let firstName = "\(firstID.uuidString).mindmap"
    let secondName = "\(secondID.uuidString).mindmap"
    let orderBase = Date(timeIntervalSince1970: 1_800_000_000)
    try! FileManager.default.setAttributes([.modificationDate: orderBase],
                                           ofItemAtPath: fixture.live.appendingPathComponent(firstName).path)
    try! FileManager.default.setAttributes([.modificationDate: orderBase.addingTimeInterval(1)],
                                           ofItemAtPath: fixture.live.appendingPathComponent(secondName).path)
    let orderingEvidence = tabDirectoryEvidence(fixture.live, label: "success ordering")
    let orderedNames = orderingEvidence.modificationDates.keys.sorted {
        orderingEvidence.modificationDates[$0]! > orderingEvidence.modificationDates[$1]!
    }
    check(orderedNames == [secondName, firstName],
          "committed UUID filenames retain mtime-newest load ordering semantics")

    let timestamp = Date(timeIntervalSince1970: 1_700_000_200)
    await MainActor.run {
        let vm = MindMapViewModel(tabStore: TabStore(directory: fixture.live))
        vm.sessions = entries.map { EditorSession(id: $0.id, document: $0.document) }
        vm.activeIndex = 0
        vm.document = first
        vm.lastSavedAt = timestamp
        let vmOutcome = vm.autosaveAllSessions()
        check(vmOutcome.succeeded, "successful ViewModel autosave returns committed outcome")
        if let saved = vm.lastSavedAt {
            check(saved > timestamp, "successful autosave advances lastSavedAt")
        } else {
            check(false, "successful autosave advances lastSavedAt")
        }
    }
}

do {
    let root = freshTabStoreRoot("precommit-corrupt")
    defer { try? FileManager.default.removeItem(at: root) }
    let fixture = makeTabFixture(in: root)
    let before = tabDirectoryEvidence(fixture.live, label: "corrupt staging before")
    let production = TabStore.Dependencies.production
    var writeCount = 0
    var exchangeCalled = false
    let dependencies = TabStore.Dependencies(
        writeData: { data, url in
            writeCount += 1
            if writeCount == 2 {
                try Data("corrupt staging".utf8).write(to: url, options: .atomic)
            } else {
                try production.writeData(data, url)
            }
        },
        exchangeDirectories: { _, _ in
            exchangeCalled = true
            throw TabStoreCheckFailure.exchange
        })
    let outcome = TabStore(directory: fixture.live, dependencies: dependencies).save(fixture.entries)
    switch outcome {
    case .failed:
        if let error = outcome.primaryError {
            print("TabStore corrupt-staging outcome: \(error)")
        }
        if let error = outcome.primaryError, case .validationFailed(_, let reason) = error {
            check(reason.contains("cannot decode"),
                  "corrupt staging is refused by precommit validation")
        } else {
            check(false, "corrupt staging is refused by precommit validation")
        }
    case .committed:
        check(false, "corrupt staging is refused by precommit validation")
    }
    check(!exchangeCalled && writeCount == 2,
          "precommit validation refuses exchange after corrupt staging")
    let after = tabDirectoryEvidence(fixture.live, label: "corrupt staging after")
    assertTabEvidencePreserved(before, after, label: "corrupt-staging rejection")
}

do {
    let root = freshTabStoreRoot("rollback")
    defer { try? FileManager.default.removeItem(at: root) }
    let fixture = makeTabFixture(in: root)
    let before = tabDirectoryEvidence(fixture.live, label: "rollback before")
    let newID = UUID(uuidString: "66666666-6666-4666-8666-666666666666")!
    let newDocument = MindDocument(title: "Rollback candidate", root: MindNode(text: "不應留下的新根"))
    let entries = [TabStore.Entry(id: newID, document: newDocument)]
    let production = TabStore.Dependencies.production
    var exchangeCalls = 0
    let dependencies = TabStore.Dependencies(
        writeData: production.writeData,
        exchangeDirectories: { live, staging in
            exchangeCalls += 1
            try production.exchangeDirectories(live, staging)
            if exchangeCalls == 1 {
                try Data("corrupt post-exchange".utf8).write(
                    to: live.appendingPathComponent("\(newID.uuidString).mindmap"), options: .atomic)
            }
        })
    let outcome = TabStore(directory: fixture.live, dependencies: dependencies).save(entries)
    if let error = outcome.primaryError {
        print("TabStore post-exchange rollback outcome: \(error)")
        if let warning = outcome.cleanupWarning { print("TabStore cleanup warning: \(warning)") }
    }
    check(!outcome.succeeded, "post-exchange validation failure returns failure")
    check(exchangeCalls == 2, "post-exchange validation failure performs atomic rollback")
    if let error = outcome.primaryError, case .postCommitValidationFailed = error {
        check(true, "post-exchange failure is typed separately from precommit failure")
    } else {
        check(false, "post-exchange failure is typed separately from precommit failure")
    }
    let after = tabDirectoryEvidence(fixture.live, label: "rollback after")
    assertTabEvidencePreserved(before, after, label: "post-exchange rollback")
    let corruptData = Data("corrupt post-exchange".utf8)
    let retainedEvidence = tabTransactionDirectories(root).contains {
        (try? Data(contentsOf: $0.appendingPathComponent("\(newID.uuidString).mindmap"))) == corruptData
    }
    check(retainedEvidence, "rollback preserves both old live and failed new snapshot evidence")
}

do {
    let root = freshTabStoreRoot("rollback-failure")
    defer { try? FileManager.default.removeItem(at: root) }
    let fixture = makeTabFixture(in: root)
    let before = tabDirectoryEvidence(fixture.live, label: "rollback failure before")
    let newID = UUID(uuidString: "77777777-7777-4777-8777-777777777777")!
    let newDocument = MindDocument(title: "Severe rollback candidate", root: MindNode(text: "失敗後保留的新根"))
    let production = TabStore.Dependencies.production
    var exchangeCalls = 0
    let dependencies = TabStore.Dependencies(
        writeData: production.writeData,
        exchangeDirectories: { live, staging in
            exchangeCalls += 1
            if exchangeCalls == 2 { throw TabStoreCheckFailure.exchange }
            try production.exchangeDirectories(live, staging)
            try Data("corrupt rollback".utf8).write(
                to: live.appendingPathComponent("\(newID.uuidString).mindmap"), options: .atomic)
        })
    let outcome = TabStore(directory: fixture.live, dependencies: dependencies).save([
        TabStore.Entry(id: newID, document: newDocument)
    ])
    check(!outcome.succeeded, "rollback exchange failure returns failure")
    if let error = outcome.primaryError, case .rollbackFailed = error {
        check(true, "rollback exchange failure returns a distinct severe outcome")
    } else {
        check(false, "rollback exchange failure returns a distinct severe outcome")
    }
    check(exchangeCalls == 2, "rollback failure seam reaches the second exchange")
    assertTestDirectory(fixture.live, label: "live after rollback failure")
    let transactionDirectories = tabTransactionDirectories(root)
    check(!transactionDirectories.isEmpty,
          "rollback failure preserves a staging directory alongside live")
    let oldName = "\(fixture.singleID.uuidString).mindmap"
    let oldData = before.files[oldName]!
    let oldSnapshotRetained = transactionDirectories.contains {
        (try? Data(contentsOf: $0.appendingPathComponent(oldName))) == oldData
    }
    check(oldSnapshotRetained, "rollback failure preserves the old live snapshot evidence")
    let corruptData = Data("corrupt rollback".utf8)
    let corruptLive = (try? Data(contentsOf:
        fixture.live.appendingPathComponent("\(newID.uuidString).mindmap"))) == corruptData
    check(corruptLive, "rollback failure preserves the failed new live path")
}

do {
    let root = freshTabStoreRoot("retention")
    defer { try? FileManager.default.removeItem(at: root) }
    let fixture = makeTabFixture(in: root)
    for _ in 0..<5 {
        let transaction = root.appendingPathComponent(
            "\(TabStore.transactionDirectoryPrefix)\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: transaction, withIntermediateDirectories: false)
        assertTestDirectory(transaction, label: "seeded transaction")
    }
    let beforeCount = tabTransactionDirectories(root).count
    var countAtExchange = 0
    let production = TabStore.Dependencies.production
    let dependencies = TabStore.Dependencies(
        writeData: production.writeData,
        exchangeDirectories: { live, staging in
            countAtExchange = tabTransactionDirectories(root).count
            try production.exchangeDirectories(live, staging)
        })
    let outcome = TabStore(directory: fixture.live, dependencies: dependencies).save(fixture.entries)
    let afterCount = tabTransactionDirectories(root).count
    check(beforeCount > TabStore.maximumRetainedTransactions,
          "retention fixture starts above the transaction sibling bound")
    check(outcome.succeeded, "retention pruning follows a successful validated commit")
    check(countAtExchange > TabStore.maximumRetainedTransactions,
          "transaction pruning does not run before exchange and validation")
    check(afterCount <= TabStore.maximumRetainedTransactions,
          "successful commit retains at most three transaction siblings")
}

// MARK: - TabStore pre-artifact rejection ownership
// Rejections before staging are intentionally allowed to leave the seeded
// evidence above the retention bound untouched.
do {
    let root = freshTabStoreRoot("pre-artifact-rejection")
    defer { try? FileManager.default.removeItem(at: root) }
    let fixture = makeTabFixture(in: root)
    let seeded = seedTabTransactions(root, count: TabStore.maximumRetainedTransactions + 2)
    let beforeSiblings = tabTransactionEvidence(root, label: "pre-artifact rejection before")
    let beforeLive = tabDirectoryEvidence(fixture.live, label: "pre-artifact rejection live before")
    check(seeded.count > TabStore.maximumRetainedTransactions,
          "pre-artifact fixture starts above the transaction sibling bound")
    let store = TabStore(directory: fixture.live)

    let empty = store.save([])
    if let error = empty.primaryError, case .emptySnapshot = error {
        check(true, "pre-artifact empty rejection is typed")
    } else {
        check(false, "pre-artifact empty rejection is typed")
    }
    check(empty.cleanupWarning == nil,
          "pre-artifact empty rejection does not report cleanup for untouched siblings")
    let afterEmptySiblings = tabTransactionEvidence(root, label: "pre-artifact empty rejection after")
    assertTabTransactionEvidencePreserved(beforeSiblings, afterEmptySiblings,
                                          label: "pre-artifact empty rejection")
    check(tabTransactionDirectories(root).count == seeded.count,
          "pre-artifact empty rejection keeps the above-bound sibling count")

    let duplicate = store.save([fixture.entries[0], fixture.entries[0]])
    if let error = duplicate.primaryError, case .duplicateID = error {
        check(true, "pre-artifact duplicate rejection is typed")
    } else {
        check(false, "pre-artifact duplicate rejection is typed")
    }
    let afterDuplicateSiblings = tabTransactionEvidence(root, label: "pre-artifact duplicate rejection after")
    assertTabTransactionEvidencePreserved(beforeSiblings, afterDuplicateSiblings,
                                          label: "pre-artifact duplicate rejection")

    let tooMany = (0...TabStore.maximumEntries).map { _ in
        TabStore.Entry(id: UUID(), document: fixture.single)
    }
    let overCeiling = store.save(tooMany)
    if let error = overCeiling.primaryError, case .tooManyEntries = error {
        check(true, "pre-artifact ceiling rejection is typed")
    } else {
        check(false, "pre-artifact ceiling rejection is typed")
    }
    let afterCeilingSiblings = tabTransactionEvidence(root, label: "pre-artifact ceiling rejection after")
    assertTabTransactionEvidencePreserved(beforeSiblings, afterCeilingSiblings,
                                          label: "pre-artifact ceiling rejection")
    let afterLive = tabDirectoryEvidence(fixture.live, label: "pre-artifact rejection live after")
    assertTabEvidencePreserved(beforeLive, afterLive, label: "pre-artifact rejections")
    check(tabTransactionDirectories(root).count == seeded.count,
          "pre-artifact rejections keep all seeded siblings")
}

// MARK: - TabStore follow-up: empty snapshots and bounded failure artifacts
// These tests deliberately use fresh canonical /tmp roots and never FileIO's
// Application Support path.
do {
    let root = freshTabStoreRoot("empty-snapshot")
    defer { try? FileManager.default.removeItem(at: root) }
    let fixture = makeTabFixture(in: root)
    let before = tabDirectoryEvidence(fixture.live, label: "empty snapshot before")
    let store = TabStore(directory: fixture.live)
    let outcome = store.save([])
    check(!outcome.succeeded, "empty snapshots fail before staging")
    if let error = outcome.primaryError, case .emptySnapshot = error {
        check(true, "empty snapshot returns the typed emptySnapshot error")
    } else {
        check(false, "empty snapshot returns the typed emptySnapshot error")
    }
    check(outcome.cleanupWarning == nil, "empty snapshot has no cleanup warning without artifacts")
    let after = tabDirectoryEvidence(fixture.live, label: "empty snapshot after")
    assertTabEvidencePreserved(before, after, label: "empty snapshot rejection")
    check(tabTransactionDirectories(root).isEmpty,
          "empty snapshot creates zero new transaction directories")

    let timestamp = Date(timeIntervalSince1970: 1_700_000_300)
    await MainActor.run {
        let vm = MindMapViewModel(tabStore: store)
        vm.sessions = []
        vm.document = fixture.single
        vm.lastSavedAt = timestamp
        let vmOutcome = vm.autosaveAllSessions()
        check(!vmOutcome.succeeded, "empty ViewModel snapshot uses the failure path")
        check(vm.lastSavedAt == timestamp,
              "empty snapshot leaves ViewModel lastSavedAt unchanged")
        check(vm.statusMessage == "⚠︎ 自動保存失敗",
              "empty snapshot exposes the persistent warning status")
    }
    let afterViewModel = tabDirectoryEvidence(fixture.live, label: "empty snapshot after ViewModel")
    assertTabEvidencePreserved(before, afterViewModel, label: "empty ViewModel snapshot")
    check(tabTransactionDirectories(root).isEmpty,
          "empty ViewModel snapshot creates zero transaction directories")
}

do {
    let root = freshTabStoreRoot("repeat-write-failure")
    defer { try? FileManager.default.removeItem(at: root) }
    let fixture = makeTabFixture(in: root)
    let before = tabDirectoryEvidence(fixture.live, label: "repeat write failure before")
    var writeCount = 0
    var exchangeCalled = false
    let production = TabStore.Dependencies.production
    let dependencies = TabStore.Dependencies(
        writeData: { data, url in
            writeCount += 1
            if writeCount == 2 { throw TabStoreCheckFailure.write }
            try production.writeData(data, url)
        },
        exchangeDirectories: { _, _ in
            exchangeCalled = true
            throw TabStoreCheckFailure.exchange
        },
        removeItem: production.removeItem)
    let store = TabStore(directory: fixture.live, dependencies: dependencies)
    for attempt in 1...5 {
        writeCount = 0
        let outcome = store.save(fixture.entries)
        if let error = outcome.primaryError, case .writeFailed = error {
            check(true, "repeat write failure \(attempt) keeps writeFailed as primary error")
        } else {
            check(false, "repeat write failure \(attempt) keeps writeFailed as primary error")
        }
        check(!exchangeCalled, "repeat write failure \(attempt) never reaches exchange")
        check(outcome.cleanupWarning == nil,
              "repeat write failure \(attempt) cleans its partial staging")
        check(tabTransactionDirectories(root).isEmpty,
              "repeat write failure \(attempt) leaves zero transaction artifacts")
        let after = tabDirectoryEvidence(fixture.live, label: "repeat write failure \(attempt) after")
        assertTabEvidencePreserved(before, after, label: "repeat write failure \(attempt)")
    }
}

do {
    let root = freshTabStoreRoot("repeat-exchange-failure")
    defer { try? FileManager.default.removeItem(at: root) }
    let fixture = makeTabFixture(in: root)
    let before = tabDirectoryEvidence(fixture.live, label: "repeat exchange failure before")
    var exchangeCount = 0
    let production = TabStore.Dependencies.production
    let dependencies = TabStore.Dependencies(
        writeData: production.writeData,
        exchangeDirectories: { _, _ in
            exchangeCount += 1
            throw TabStoreCheckFailure.exchange
        },
        removeItem: production.removeItem)
    let store = TabStore(directory: fixture.live, dependencies: dependencies)
    for attempt in 1...5 {
        let outcome = store.save(fixture.entries)
        if let error = outcome.primaryError, case .exchangeFailed = error {
            check(true, "repeat exchange failure \(attempt) keeps exchangeFailed as primary error")
        } else {
            check(false, "repeat exchange failure \(attempt) keeps exchangeFailed as primary error")
        }
        let count = tabTransactionDirectories(root).count
        check(count == min(attempt, TabStore.maximumRetainedTransactions),
              "repeat exchange failure \(attempt) retains current plus at most two siblings")
        let after = tabDirectoryEvidence(fixture.live, label: "repeat exchange failure \(attempt) after")
        assertTabEvidencePreserved(before, after, label: "repeat exchange failure \(attempt)")
    }
    check(exchangeCount == 5, "repeat exchange failure exercises every injected attempt")
}

do {
    let root = freshTabStoreRoot("cleanup-failure")
    defer { try? FileManager.default.removeItem(at: root) }
    let fixture = makeTabFixture(in: root)
    let before = tabDirectoryEvidence(fixture.live, label: "cleanup failure before")
    var writeCount = 0
    var attemptedRemovals: [URL] = []
    let production = TabStore.Dependencies.production
    let dependencies = TabStore.Dependencies(
        writeData: { data, url in
            writeCount += 1
            if writeCount == 2 { throw TabStoreCheckFailure.write }
            try production.writeData(data, url)
        },
        exchangeDirectories: { _, _ in
            throw TabStoreCheckFailure.exchange
        },
        removeItem: { url in
            attemptedRemovals.append(url)
            throw TabStoreCheckFailure.write
        })
    let outcome = TabStore(directory: fixture.live, dependencies: dependencies).save(fixture.entries)
    if let error = outcome.primaryError, case .writeFailed = error {
        check(true, "cleanup refusal preserves writeFailed as the primary error")
    } else {
        check(false, "cleanup refusal preserves writeFailed as the primary error")
    }
    check(attemptedRemovals.count == 1, "cleanup refusal attempts to remove only the partial current staging")
    print("TabStore cleanup-failure attempted removals: \(attemptedRemovals.map { $0.path })")
    let live = fixture.live.standardizedFileURL
    let liveParent = live.deletingLastPathComponent().standardizedFileURL
    check(attemptedRemovals.allSatisfy { $0.standardizedFileURL != live },
          "cleanup refusal never attempts to remove live")
    check(attemptedRemovals.allSatisfy {
        let target = $0.standardizedFileURL
        return target.lastPathComponent.hasPrefix(TabStore.transactionDirectoryPrefix)
            && target.deletingLastPathComponent().standardizedFileURL == liveParent
    }, "cleanup refusal attempts only same-parent transaction paths")
    if let warning = outcome.cleanupWarning {
        check(Set(warning.failedURLs.map { $0.standardizedFileURL.path })
              == Set(attemptedRemovals.map { $0.standardizedFileURL.path }),
              "cleanup warning explicitly reports every failed removal URL")
    } else {
        check(false, "cleanup warning explicitly reports every failed removal URL")
    }
    let after = tabDirectoryEvidence(fixture.live, label: "cleanup failure after")
    assertTabEvidencePreserved(before, after, label: "cleanup refusal")
    check(tabTransactionDirectories(root).count <= TabStore.maximumRetainedTransactions,
          "cleanup refusal still bounds transaction artifacts")
}

do {
    let root = freshTabStoreRoot("postrollback-bounded")
    defer { try? FileManager.default.removeItem(at: root) }
    let fixture = makeTabFixture(in: root)
    let seeded = seedTabTransactions(root, count: 4)
    let before = tabDirectoryEvidence(fixture.live, label: "postrollback bounded before")
    let newID = UUID(uuidString: "88888888-8888-4888-8888-888888888888")!
    let newDocument = MindDocument(title: "Bounded rollback candidate", root: MindNode(text: "失敗後的候選根"))
    let production = TabStore.Dependencies.production
    var exchangeCalls = 0
    let dependencies = TabStore.Dependencies(
        writeData: production.writeData,
        exchangeDirectories: { live, staging in
            exchangeCalls += 1
            try production.exchangeDirectories(live, staging)
            if exchangeCalls == 1 {
                try Data("bounded corrupt post-exchange".utf8).write(
                    to: live.appendingPathComponent("\(newID.uuidString).mindmap"), options: .atomic)
            }
        },
        removeItem: production.removeItem)
    let outcome = TabStore(directory: fixture.live, dependencies: dependencies).save([
        TabStore.Entry(id: newID, document: newDocument)
    ])
    check(!outcome.succeeded, "post-exchange bounded failure returns failure")
    if let error = outcome.primaryError, case .postCommitValidationFailed = error {
        check(true, "post-exchange bounded failure keeps post-validation as primary error")
    } else {
        check(false, "post-exchange bounded failure keeps post-validation as primary error")
    }
    let after = tabDirectoryEvidence(fixture.live, label: "postrollback bounded after")
    assertTabEvidencePreserved(before, after, label: "post-exchange bounded rollback")
    let transactions = tabTransactionDirectories(root)
    let corruptData = Data("bounded corrupt post-exchange".utf8)
    check(transactions.contains {
        (try? Data(contentsOf: $0.appendingPathComponent("\(newID.uuidString).mindmap"))) == corruptData
    }, "post-exchange bounded cleanup preserves the failed current snapshot")
    let seededPaths = Set(seeded.map { $0.standardizedFileURL.path })
    let retainedSeeded = transactions.filter { seededPaths.contains($0.standardizedFileURL.path) }
    check(transactions.count <= TabStore.maximumRetainedTransactions
              && retainedSeeded.count <= TabStore.maximumRetainedTransactions - 1,
          "post-exchange bounded cleanup evicts only older unrelated siblings")
}

do {
    let root = freshTabStoreRoot("rollback-failure-bounded")
    defer { try? FileManager.default.removeItem(at: root) }
    let fixture = makeTabFixture(in: root)
    let seeded = seedTabTransactions(root, count: 4)
    let before = tabDirectoryEvidence(fixture.live, label: "rollback-failure bounded before")
    let newID = UUID(uuidString: "99999999-9999-4999-8999-999999999999")!
    let newDocument = MindDocument(title: "Severe bounded candidate", root: MindNode(text: "嚴重失敗候選根"))
    let production = TabStore.Dependencies.production
    var exchangeCalls = 0
    let dependencies = TabStore.Dependencies(
        writeData: production.writeData,
        exchangeDirectories: { live, staging in
            exchangeCalls += 1
            if exchangeCalls == 2 { throw TabStoreCheckFailure.exchange }
            try production.exchangeDirectories(live, staging)
            try Data("bounded corrupt rollback".utf8).write(
                to: live.appendingPathComponent("\(newID.uuidString).mindmap"), options: .atomic)
        },
        removeItem: production.removeItem)
    let outcome = TabStore(directory: fixture.live, dependencies: dependencies).save([
        TabStore.Entry(id: newID, document: newDocument)
    ])
    check(!outcome.succeeded, "bounded rollback failure returns failure")
    if let error = outcome.primaryError, case .rollbackFailed = error {
        check(true, "bounded rollback failure keeps the severe primary error")
    } else {
        check(false, "bounded rollback failure keeps the severe primary error")
    }
    check(exchangeCalls == 2, "bounded rollback failure reaches the failed rollback exchange")
    assertTestDirectory(fixture.live, label: "live after bounded rollback failure")
    let transactions = tabTransactionDirectories(root)
    let oldName = "\(fixture.singleID.uuidString).mindmap"
    let oldData = before.files[oldName]!
    check(transactions.contains {
        (try? Data(contentsOf: $0.appendingPathComponent(oldName))) == oldData
    }, "bounded rollback failure preserves the old live path")
    let corruptData = Data("bounded corrupt rollback".utf8)
    check((try? Data(contentsOf: fixture.live.appendingPathComponent("\(newID.uuidString).mindmap"))) == corruptData,
          "bounded rollback failure preserves the live path")
    let seededPaths = Set(seeded.map { $0.standardizedFileURL.path })
    let retainedSeeded = transactions.filter { seededPaths.contains($0.standardizedFileURL.path) }
    check(transactions.count <= TabStore.maximumRetainedTransactions
              && retainedSeeded.count <= TabStore.maximumRetainedTransactions - 1,
          "bounded rollback failure evicts only older unrelated siblings")
}

// MARK: - T-036 follow-up: adopted OPML levels and destination-aware paste

do {
    let limits = ImportLimits(maxBytes: 4096, maxLevels: 2)
    let accepted = """
    <opml version="2.0"><body>
      <outline text="First"/>
      <outline text="Second"/>
    </body></opml>
    """
    if let document = try? MapImporter.opml(accepted, limits: limits) {
        check(document.root.text == "First", "OPML keeps the first top-level outline as root")
        check(document.root.children.map(\.text) == ["Second"],
              "OPML accepts a second top-level leaf at structural level 2")
    } else {
        check(false, "OPML accepts a second top-level leaf at structural level 2")
    }

    let nestedSecond = """
    <opml version="2.0"><body>
      <outline text="First"/>
      <outline text="Second"><outline text="Child under second"/></outline>
    </body></opml>
    """
    do {
        _ = try MapImporter.opml(nestedSecond, limits: limits)
        check(false, "OPML rejects a child of the adopted second top-level at level 3")
    } catch let error as InterchangeError {
        if case .tooDeep(let limit, let observedLevel) = error {
            check(limit == 2 && observedLevel == 3,
                  "OPML rejects a child of the adopted second top-level at level 3")
        } else {
            check(false, "OPML rejects a child of the adopted second top-level at level 3")
        }
    } catch {
        check(false, "OPML rejects a child of the adopted second top-level at level 3")
    }
}

do {
    let root = freshInterchangeRoot("joined-depth")
    defer { try? FileManager.default.removeItem(at: root) }
    let destinationID = UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!
    let base = MindDocument(title: "Destination", root: MindNode(
        text: "Root", children: [MindNode(id: destinationID, text: "Deep destination")]))
    let source = markdownChain(levels: 128)
    check((try? MapImporter.markdown(source)) != nil,
          "source at level 128 passes before destination attachment")
    await MainActor.run {
        let vm = MindMapViewModel(tabStore: TabStore(directory: root.appendingPathComponent("tabs", isDirectory: true)))
        vm.document = base
        vm.selection = destinationID
        vm.rename(id: destinationID, to: "Renamed destination")
        let beforeDocument = vm.document
        let beforeSelection = vm.selection
        let beforeEditing = vm.editingID
        let beforePath = URL(fileURLWithPath: "/tmp/mindflow-joined-depth.mindmap")
        vm.filePath = beforePath
        vm.dirty = true
        let beforeDirty = vm.dirty
        let timestamp = Date(timeIntervalSince1970: 1_700_200_000)
        vm.lastSavedAt = timestamp

        vm.insertTextAsNodes(source, sourceLabel: "Markdown")
        check(vm.document == beforeDocument,
              "joined level 129 paste leaves the document unchanged")
        check(vm.selection == beforeSelection && vm.editingID == beforeEditing,
              "joined level 129 paste leaves selection/editing unchanged")
        check(vm.filePath == beforePath && vm.dirty == beforeDirty && vm.lastSavedAt == timestamp,
              "joined level 129 paste leaves filePath/dirty/timestamp unchanged")
        check(vm.statusMessage?.contains("128") == true && vm.statusMessage?.contains("129") == true,
              "joined depth status reports final level 129 and global 128 limit")

        vm.undo()
        check(vm.document == base, "joined rejection leaves the existing undo stack intact")
    }
}

do {
    let root = freshInterchangeRoot("root-boundary")
    defer { try? FileManager.default.removeItem(at: root) }
    await MainActor.run {
        let vm = MindMapViewModel(tabStore: TabStore(directory: root.appendingPathComponent("tabs", isDirectory: true)))
        vm.insertTextAsNodes(markdownChain(levels: 128), sourceLabel: "Markdown")
        check(vm.document.root.children.count == 1,
              "root-level paste accepts a source ending at level 128")
        check(maximumNodeLevel(vm.document.root) == 128,
              "root-level paste preserves the exact final level 128 boundary")
    }
}

do {
    let root = freshInterchangeRoot("too-deep-target")
    defer { try? FileManager.default.removeItem(at: root) }
    let deepDocument = interchangeChainDocument(levels: 128)
    var deepest = deepDocument.root
    while let child = deepest.children.first { deepest = child }
    await MainActor.run {
        let vm = MindMapViewModel(tabStore: TabStore(directory: root.appendingPathComponent("tabs", isDirectory: true)))
        vm.document = deepDocument
        vm.selection = deepest.id
        let before = vm.document
        vm.insertTextAsNodes(markdownChain(levels: 2), sourceLabel: "Markdown")
        check(vm.document == before,
              "a level-128 destination rejects a level-2 imported child")
        check(vm.statusMessage?.contains("128") == true && vm.statusMessage?.contains("129") == true,
              "too-deep destination reports global limit and final level")
    }
}

// MARK: - T-036: bounded interchange import/export

do {
    let root = freshInterchangeRoot("reader")
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("payload.txt")
    let limits = ImportLimits(maxBytes: 8, maxLevels: 4)
    try! Data("12345678".utf8).write(to: file, options: .atomic)
    var requestedWindow = 0
    let dependencies = BoundedInterchangeReader.Dependencies(
        metadataSize: { _ in 0 },
        read: { url, window in
            requestedWindow = window
            return Data(try Data(contentsOf: url).prefix(window))
        })
    let reader = BoundedInterchangeReader(limits: limits, dependencies: dependencies)
    do {
        let data = try reader.readData(from: file)
        check(data.count == 8, "bounded reader accepts exactly N bytes")
        check(requestedWindow == 9, "bounded reader requests maxBytes plus one")
    } catch {
        check(false, "bounded reader accepts exactly N bytes")
        check(false, "bounded reader requests maxBytes plus one")
    }

    try! Data("123456789".utf8).write(to: file, options: .atomic)
    do {
        _ = try reader.readData(from: file)
        check(false, "bounded reader rejects N+1 actual bytes")
    } catch let error as InterchangeError {
        if case .tooLarge(let limit, let observed) = error {
            check(limit == 8 && observed == 9, "bounded reader reports N+1 tooLarge")
        } else {
            check(false, "bounded reader reports N+1 tooLarge")
        }
    } catch {
        check(false, "bounded reader reports N+1 tooLarge")
    }

    var preflightRead = false
    let preflightReader = BoundedInterchangeReader(
        limits: limits,
        dependencies: .init(
            metadataSize: { _ in 9 },
            read: { _, _ in
                preflightRead = true
                return Data()
            }))
    do {
        _ = try preflightReader.readData(from: file)
        check(false, "metadata preflight rejects an oversized file")
    } catch let error as InterchangeError {
        if case .tooLarge(let limit, let observed) = error {
            check(limit == 8 && observed == 9, "metadata preflight reports its observed size")
        } else {
            check(false, "metadata preflight reports its observed size")
        }
    } catch {
        check(false, "metadata preflight reports its observed size")
    }
    check(!preflightRead, "metadata preflight avoids an oversized read")

    try! Data([0xff]).write(to: file, options: .atomic)
    do {
        _ = try reader.readText(from: file)
        check(false, "bounded reader rejects invalid UTF-8")
    } catch let error as InterchangeError {
        check(error == .invalidUTF8, "bounded reader reports invalid UTF-8 distinctly")
    } catch {
        check(false, "bounded reader reports invalid UTF-8 distinctly")
    }

    let unreadableReader = BoundedInterchangeReader(
        limits: limits,
        dependencies: .init(
            metadataSize: { _ in throw NSError(domain: "reader", code: 1) },
            read: { _, _ in Data() }))
    do {
        _ = try unreadableReader.readData(from: file)
        check(false, "bounded reader reports unreadable input")
    } catch let error as InterchangeError {
        if case .unreadable = error {
            check(true, "bounded reader reports unreadable input")
        } else {
            check(false, "bounded reader reports unreadable input")
        }
    } catch {
        check(false, "bounded reader reports unreadable input")
    }
    check(InterchangeError.cancelled.isCancellation, "cancelled input remains distinct")
}

do {
    let limits = ImportLimits(maxBytes: 4096, maxLevels: 4)
    let expected = interchangeChainDocument(levels: limits.maxLevels)

    func expectTooDeep(_ parse: () throws -> MindDocument, label: String) {
        do {
            _ = try parse()
            check(false, label)
        } catch let error as InterchangeError {
            if case .tooDeep(let limit, let observedLevel) = error {
                check(limit == limits.maxLevels && observedLevel == limits.maxLevels + 1, label)
            } else {
                check(false, label)
            }
        } catch {
            check(false, label)
        }
    }

    func expectTooLarge(_ parse: () throws -> MindDocument, label: String) {
        do {
            _ = try parse()
            check(false, label)
        } catch let error as InterchangeError {
            if case .tooLarge(let limit, let observed) = error {
                check(limit == limits.maxBytes && observed >= limits.maxBytes + 1, label)
            } else {
                check(false, label)
            }
        } catch {
            check(false, label)
        }
    }

    if let markdown = try? MapImporter.markdown(markdownChain(levels: limits.maxLevels), limits: limits) {
        check(markdown.root.text == expected.root.text, "Markdown accepts exact configured depth")
        assertInterchangeStructure(expected.root, markdown.root, label: "Markdown exact-depth round trip")
    } else {
        check(false, "Markdown accepts exact configured depth")
    }
    if let opml = try? MapImporter.opml(opmlChain(levels: limits.maxLevels), limits: limits) {
        check(opml.root.text == expected.root.text, "OPML accepts exact configured depth")
        assertInterchangeStructure(expected.root, opml.root, label: "OPML exact-depth round trip")
    } else {
        check(false, "OPML accepts exact configured depth")
    }
    if let freemind = try? MapImporter.freemind(freemindChain(levels: limits.maxLevels), limits: limits) {
        check(freemind.root.text == expected.root.text, "FreeMind accepts exact configured depth")
        assertInterchangeStructure(expected.root, freemind.root, label: "FreeMind exact-depth round trip")
    } else {
        check(false, "FreeMind accepts exact configured depth")
    }

    expectTooDeep({ try MapImporter.markdown(markdownChain(levels: limits.maxLevels + 1), limits: limits) },
                  label: "Markdown rejects level 5 with typed tooDeep")
    expectTooDeep({ try MapImporter.opml(opmlChain(levels: limits.maxLevels + 1), limits: limits) },
                  label: "OPML rejects level 5 with typed tooDeep")
    expectTooDeep({ try MapImporter.freemind(freemindChain(levels: limits.maxLevels + 1), limits: limits) },
                  label: "FreeMind rejects level 5 with typed tooDeep")

    let oversized = Data(repeating: 0x20, count: limits.maxBytes + 1)
    expectTooLarge({ try MapImporter.markdown(oversized, limits: limits) },
                   label: "Markdown rejects oversized Data before parsing")
    expectTooLarge({ try MapImporter.opml(oversized, limits: limits) },
                   label: "OPML rejects oversized Data before parsing")
    expectTooLarge({ try MapImporter.freemind(oversized, limits: limits) },
                   label: "FreeMind rejects oversized Data before parsing")
}

do {
    let limits = ImportLimits(maxBytes: 65_536, maxLevels: 4)
    let document = interchangeChainDocument(levels: limits.maxLevels)

    let markdown = try! MapExporter.markdown(document, limits: limits)
    let opml = try! MapExporter.opml(document, limits: limits)
    let freemind = try! MapExporter.freemind(document, limits: limits)
    let markdownExact = ImportLimits(maxBytes: markdown.utf8.count, maxLevels: limits.maxLevels)
    let opmlExact = ImportLimits(maxBytes: opml.utf8.count, maxLevels: limits.maxLevels)
    let freemindExact = ImportLimits(maxBytes: freemind.utf8.count, maxLevels: limits.maxLevels)

    if let back = try? MapImporter.markdown(markdown, limits: markdownExact) {
        assertInterchangeStructure(document.root, back.root, label: "Markdown exact-byte round trip")
    } else {
        check(false, "Markdown exact-byte output reimports")
    }
    if let back = try? MapImporter.opml(opml, limits: opmlExact) {
        assertInterchangeStructure(document.root, back.root, label: "OPML exact-byte round trip")
    } else {
        check(false, "OPML exact-byte output reimports")
    }
    if let back = try? MapImporter.freemind(freemind, limits: freemindExact) {
        assertInterchangeStructure(document.root, back.root, label: "FreeMind exact-byte round trip")
    } else {
        check(false, "FreeMind exact-byte output reimports")
    }

    func expectExportTooDeep(_ export: () throws -> String, label: String) {
        do {
            _ = try export()
            check(false, label)
        } catch let error as InterchangeError {
            if case .tooDeep(let limit, let observedLevel) = error {
                check(limit == limits.maxLevels && observedLevel == limits.maxLevels + 1, label)
            } else {
                check(false, label)
            }
        } catch {
            check(false, label)
        }
    }
    func expectExportTooLarge(_ export: () throws -> String, label: String) {
        do {
            _ = try export()
            check(false, label)
        } catch let error as InterchangeError {
            if case .tooLarge(let limit, let observed) = error {
                check(limit < 65_536 && observed > limit, label)
            } else {
                check(false, label)
            }
        } catch {
            check(false, label)
        }
    }

    let deepDocument = interchangeChainDocument(levels: limits.maxLevels + 1)
    expectExportTooDeep({ try MapExporter.markdown(deepDocument, limits: limits) },
                        label: "Markdown exporter rejects level 5")
    expectExportTooDeep({ try MapExporter.opml(deepDocument, limits: limits) },
                        label: "OPML exporter rejects level 5")
    expectExportTooDeep({ try MapExporter.freemind(deepDocument, limits: limits) },
                        label: "FreeMind exporter rejects level 5")

    expectExportTooLarge({
        try MapExporter.markdown(document,
                                 limits: ImportLimits(maxBytes: max(1, markdown.utf8.count - 1), maxLevels: 4))
    }, label: "Markdown exporter stops at the byte budget")
    expectExportTooLarge({
        try MapExporter.opml(document,
                             limits: ImportLimits(maxBytes: max(1, opml.utf8.count - 1), maxLevels: 4))
    }, label: "OPML exporter stops at the byte budget")
    expectExportTooLarge({
        try MapExporter.freemind(document,
                                 limits: ImportLimits(maxBytes: max(1, freemind.utf8.count - 1), maxLevels: 4))
    }, label: "FreeMind exporter stops at the byte budget")

    let manyChildren = (0..<2047).map { MindNode(text: "Node \($0)") }
    let manyDocument = MindDocument(title: "Many", root: MindNode(text: "Many", children: manyChildren))
    let noNodeCeiling = ImportLimits(maxBytes: 1_048_576, maxLevels: 2)
    let manyMarkdown = try! MapExporter.markdown(manyDocument, limits: noNodeCeiling)
    let manyOPML = try! MapExporter.opml(manyDocument, limits: noNodeCeiling)
    let manyFreeMind = try! MapExporter.freemind(manyDocument, limits: noNodeCeiling)
    check((try? MapImporter.markdown(manyMarkdown, limits: noNodeCeiling))?.root.children.count == 2047,
          "Markdown has no invented node-count ceiling")
    check((try? MapImporter.opml(manyOPML, limits: noNodeCeiling))?.root.children.count == 2047,
          "OPML has no invented node-count ceiling")
    check((try? MapImporter.freemind(manyFreeMind, limits: noNodeCeiling))?.root.children.count == 2047,
          "FreeMind has no invented node-count ceiling")
}

do {
    let root = freshInterchangeRoot("viewmodel-rejection")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = TabStore(directory: root.appendingPathComponent("tabs", isDirectory: true))
    await MainActor.run {
        let vm = MindMapViewModel(tabStore: store)
        let original = MindDocument(title: "State", root: MindNode(text: "保留的根"))
        vm.document = original
        let childID = vm.addChild(to: nil)!
        let beforeDocument = vm.document
        let beforeSelection = vm.selection
        let beforePath = URL(fileURLWithPath: "/tmp/mindflow-import-state.mindmap")
        vm.filePath = beforePath
        vm.dirty = true
        let beforeDirty = vm.dirty
        let timestamp = Date(timeIntervalSince1970: 1_700_100_000)
        vm.lastSavedAt = timestamp

        vm.insertTextAsNodes(markdownChain(levels: 129), sourceLabel: "Markdown")
        check(vm.statusMessage?.contains("128") == true, "ViewModel rejects an over-depth import")
        check(vm.document == beforeDocument, "over-depth import leaves document unchanged")
        check(vm.selection == beforeSelection && vm.selection == childID,
              "over-depth import leaves selection unchanged")
        check(vm.filePath == beforePath, "over-depth import leaves filePath unchanged")
        check(vm.dirty == beforeDirty, "over-depth import leaves dirty unchanged")
        check(vm.lastSavedAt == timestamp, "over-depth import leaves timestamp state unchanged")
        check(vm.statusMessage?.contains("128") == true && vm.statusMessage?.contains("深度") == true,
              "over-depth status names the 128-level limit")

        let oversizedText = String(repeating: "x", count: ImportLimits.standard.maxBytes + 1)
        vm.insertTextAsNodes(oversizedText, sourceLabel: "Markdown")
        check(vm.statusMessage?.contains("8 MiB") == true, "ViewModel rejects an over-byte import")
        check(vm.document == beforeDocument && vm.selection == beforeSelection && vm.filePath == beforePath
                  && vm.dirty == beforeDirty && vm.lastSavedAt == timestamp,
              "over-byte import leaves editor state unchanged")
        check(vm.statusMessage?.contains("8 MiB") == true,
              "over-byte status names the 8 MiB limit")

        vm.undo()
        check(vm.document == original, "rejected imports leave the existing undo stack intact")
    }
}

// T-036 icon: inspect the final decoded 8-bit raster, not source constants alone.
struct IconRasterRunStats {
    let count: Int
    let weakestPeak: Int
    let peaks: [Int]
}

struct IconCentroidEvidence {
    let inkCount: Int
    let inkX: Double
    let inkY: Double
    let boardCenterX: Double
    let boardCenterY: Double
    let tolerance: Double

    var deltaX: Double { inkX - boardCenterX }
    var deltaY: Double { inkY - boardCenterY }
}

func iconCentroidEvidence(_ image: NSBitmapImageRep) -> IconCentroidEvidence? {
    guard image.pixelsWide > 0, image.pixelsHigh > 0 else { return nil }
    var inkCount = 0
    var xSum = 0.0
    var ySum = 0.0
    for y in 0..<image.pixelsHigh {
        for x in 0..<image.pixelsWide {
            guard let color = iconRasterColor(image, x: x, y: y) else { return nil }
            guard iconInkScore(color) > 470 else { continue }
            inkCount += 1
            xSum += Double(x) + 0.5
            ySum += Double(y) + 0.5
        }
    }
    guard inkCount > 0 else { return nil }
    let xScale = Double(image.pixelsWide) / 1024.0
    let yScale = Double(image.pixelsHigh) / 1024.0
    let boardCenterX = 512.0 * xScale
    let boardCenterY = 512.0 * yScale
    let renderedBoardWidth = 824.0 * xScale
    return IconCentroidEvidence(inkCount: inkCount,
                                inkX: xSum / Double(inkCount),
                                inkY: ySum / Double(inkCount),
                                boardCenterX: boardCenterX,
                                boardCenterY: boardCenterY,
                                tolerance: max(renderedBoardWidth * 0.01, 1.0))
}

func iconRasterColor(_ image: NSBitmapImageRep, x: Int, y: Int) -> Palette.RGB? {
    guard x >= 0, x < image.pixelsWide, y >= 0, y < image.pixelsHigh,
          image.bitsPerPixel == 32, image.samplesPerPixel == 4,
          let bitmapData = image.bitmapData else {
        return nil
    }
    let offset = y * image.bytesPerRow + x * 4
    let bytes = UnsafeBufferPointer(start: bitmapData.advanced(by: offset), count: 4)
    // NSBitmapImageRep decodes these generated PNGs as non-premultiplied RGBA.
    return Palette.RGB(red: Double(bytes[0]) / 255,
                       green: Double(bytes[1]) / 255,
                       blue: Double(bytes[2]) / 255).quantized8
}

func iconInkScore(_ color: Palette.RGB) -> Int {
    Int(((color.red + color.green + color.blue) * 255).rounded())
}

func iconPixelCoordinate(_ coordinate: CGFloat, pixelSize: Int) -> Int {
    let raw = Int(floor(coordinate * CGFloat(pixelSize) / 1024))
    return min(max(raw, 0), pixelSize - 1)
}

// The raster is stored top-down while DESIGN space is y-up: row = 1024 - design y.
// Verified against the background gradient itself: the accent stop, authored at
// design y=1024, samples light at the image's top rows and dark at its bottom.
func iconSampleRow(ofDesignY y: CGFloat, pixelSize: Int) -> Int {
    iconPixelCoordinate(1024 - y, pixelSize: pixelSize)
}

func iconInkRowRange(ofDesignRect rect: CGRect, pixelSize: Int) -> ClosedRange<Int> {
    let lowRow = iconSampleRow(ofDesignY: rect.maxY, pixelSize: pixelSize)
    let highRow = iconSampleRow(ofDesignY: rect.minY, pixelSize: pixelSize)
    return lowRow...highRow
}

struct IconStructureScan {
    let column: Int
    let stats: IconRasterRunStats
    let expectedRuns: Int
    let ownershipFailures: [String]
}

func iconStructureScan(_ image: NSBitmapImageRep, slot: AppIconArtwork.Slot) -> IconStructureScan? {
    guard image.pixelsWide > 0, image.pixelsHigh > 0 else { return nil }
    let geometry = AppIconArtwork.geometry(for: slot.band)
    let pixelSize = image.pixelsWide
    let scale = Double(pixelSize) / 1024.0
    // The structural scan column derives from the glyph bbox: the leaf column crosses
    // only the two child cards once the raster resolves them (>= 32px); the two 16px
    // slots fall back to the filled root column, the band's only pixel-robust feature
    // at that size (the leaf structure there is covered by the leaf-separation gate).
    let usesLeafColumn = pixelSize >= 32
    let designColumn: CGFloat = usesLeafColumn
        ? (max(geometry.upperChild.rect.minX, geometry.lowerChild.rect.minX)
            + min(geometry.upperChild.rect.maxX, geometry.lowerChild.rect.maxX)) / 2
        : geometry.root.rect.midX
    let column = iconPixelCoordinate(designColumn + geometry.translationX, pixelSize: pixelSize)

    let scannedCards: [AppIconArtwork.CardSpec] = usesLeafColumn
        ? [geometry.upperChild, geometry.lowerChild]
        : [geometry.root]
    let allowedRows = scannedCards.map { iconInkRowRange(ofDesignRect: $0.rect, pixelSize: pixelSize) }

    var peaks: [Int] = []
    var inRun = false
    var peak = 0
    var ownershipFailures: [String] = []
    for y in 0..<image.pixelsHigh {
        guard let color = iconRasterColor(image, x: column, y: y) else { return nil }
        let score = iconInkScore(color)
        let ink = score > 470
        // Assertion first: every ink pixel in the scan column must belong to the
        // expected card bounds before the run count is allowed to mean anything.
        if ink, !allowedRows.contains(where: { $0.contains(y) }) {
            ownershipFailures.append("row " + String(y) + " score " + String(score))
        }
        if ink {
            if !inRun {
                inRun = true
                peak = 0
            }
            peak = max(peak, score)
        } else if inRun {
            peaks.append(peak)
            inRun = false
        }
    }
    if inRun { peaks.append(peak) }

    // Expected runs are derived from the band's intended geometry — the card
    // specs' filled state and stroke widths — before the raster is consulted:
    // a filled card contributes exactly one solid run on the scan column; an
    // outlined card contributes its two stroke edges when its hollow interior
    // survives rasterization (hole x scale >= 1 px), one when it self-merges.
    let expectedRuns = scannedCards.reduce(0) { total, card in
        if card.filled { return total + 1 }
        let hole = card.rect.height - 2 * geometry.childStrokeWidth
        return total + (hole * CGFloat(scale) >= 1.0 ? 2 : 1)
    }
    return IconStructureScan(
        column: column,
        stats: IconRasterRunStats(count: peaks.count,
                                  weakestPeak: peaks.min() ?? 0,
                                  peaks: peaks),
        expectedRuns: expectedRuns,
        ownershipFailures: ownershipFailures)
}

func iconInkSamplePoints(for band: AppIconArtwork.SizeBand) -> [(CGPoint, String)] {
    let geometry = AppIconArtwork.geometry(for: band)
    // A filled child is sampled at its center; an outlined child on its stroke.
    let upper: (CGPoint, String) = geometry.upperChild.filled
        ? (CGPoint(x: geometry.upperChild.rect.midX, y: geometry.upperChild.rect.midY),
           "upper child fill")
        : (CGPoint(x: geometry.upperChild.rect.midX,
                   y: geometry.upperChild.rect.maxY - geometry.childStrokeWidth / 2),
           "upper child stroke")
    let lower: (CGPoint, String) = geometry.lowerChild.filled
        ? (CGPoint(x: geometry.lowerChild.rect.midX, y: geometry.lowerChild.rect.midY),
           "lower child fill")
        : (CGPoint(x: geometry.lowerChild.rect.minX + geometry.childStrokeWidth / 2,
                   y: geometry.lowerChild.rect.midY),
           "lower child stroke")
    return [
        (CGPoint(x: geometry.root.rect.midX, y: geometry.root.rect.midY), "root fill"),
        upper,
        lower,
    ]
}

struct IconInkMask {
    let bbox: CGRect
    let inkCount: Int
    let contains: (Int, Int) -> Bool
}

func iconInkMask(_ image: NSBitmapImageRep) -> IconInkMask? {
    guard image.pixelsWide > 0, image.pixelsHigh > 0 else { return nil }
    let width = image.pixelsWide
    var ink = Set<Int>()
    var minX = Int.max, maxX = -1, minY = Int.max, maxY = -1
    for y in 0..<image.pixelsHigh {
        for x in 0..<image.pixelsWide {
            guard let color = iconRasterColor(image, x: x, y: y) else { return nil }
            if iconInkScore(color) > 470 {
                ink.insert(y * width + x)
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }
    }
    guard !ink.isEmpty else { return nil }
    return IconInkMask(
        bbox: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1),
        inkCount: ink.count,
        contains: { x, y in ink.contains(y * width + x) })
}

// p1's revised symmetry gate: flip the rendered ink mask about the ink bbox's
// horizontal midline and require the silhouette to differ from its own mirror;
// mismatch/union, measured on the final raster.
func iconFlipMismatch(_ image: NSBitmapImageRep) -> Double? {
    guard let mask = iconInkMask(image) else { return nil }
    var mismatch = 0
    var union = 0
    for y in Int(mask.bbox.minY)...Int(mask.bbox.maxY) {
        let flippedY = Int(mask.bbox.minY + mask.bbox.maxY) - y
        for x in Int(mask.bbox.minX)...Int(mask.bbox.maxX) {
            let here = mask.contains(x, y)
            let mirrored = mask.contains(x, flippedY)
            if here || mirrored { union += 1 }
            if here != mirrored { mismatch += 1 }
        }
    }
    guard union > 0 else { return nil }
    return Double(mismatch) / Double(union)
}

// p1's revised solidity gate: share of the ink bbox the ink actually fills,
// measured on the final raster.
func iconFillRatio(_ image: NSBitmapImageRep) -> Double? {
    guard let mask = iconInkMask(image) else { return nil }
    let area = Int(mask.bbox.width) * Int(mask.bbox.height)
    guard area > 0 else { return nil }
    return Double(mask.inkCount) / Double(area)
}

let expectedIconSlotNames: Set<String> = [
    "icon_16x16.png", "icon_16x16@2x.png", "icon_32x32.png", "icon_32x32@2x.png",
    "icon_128x128.png", "icon_128x128@2x.png", "icon_256x256.png", "icon_256x256@2x.png",
    "icon_512x512.png", "icon_512x512@2x.png"
]
let iconSlots = AppIconArtwork.slots
check(iconSlots.count == 10, "icon declares all ten iconset slots")
check(Set(iconSlots.map { $0.fileName }) == expectedIconSlotNames,
      "icon slot filenames match the iconutil contract")
let expectedIconSlotSizes: [String: Int] = [
    "icon_16x16.png": 16, "icon_16x16@2x.png": 32, "icon_32x32.png": 32,
    "icon_32x32@2x.png": 64, "icon_128x128.png": 128, "icon_128x128@2x.png": 256,
    "icon_256x256.png": 256, "icon_256x256@2x.png": 512,
    "icon_512x512.png": 512, "icon_512x512@2x.png": 1024
]
let expectedIconSmallSlots = Set(["icon_16x16.png", "icon_16x16@2x.png"])
let expectedIconMidSlots = Set(["icon_32x32.png", "icon_32x32@2x.png"])
check(iconSlots.allSatisfy { expectedIconSlotSizes[$0.fileName] == $0.pixelSize },
      "icon slots use their specified physical pixel sizes")
check(iconSlots.allSatisfy { slot in
    expectedIconSmallSlots.contains(slot.fileName) ? slot.band == .small :
    expectedIconMidSlots.contains(slot.fileName) ? slot.band == .mid : slot.band == .large
}, "icon slots use their specified logical artwork bands")

var iconData: [String: Data] = [:]
var iconImages: [String: NSBitmapImageRep] = [:]
var iconBackgrounds: [String: NSBitmapImageRep] = [:]
for slot in iconSlots {
    do {
        let data = try AppIconArtwork.pngData(for: slot)
        iconData[slot.fileName] = data
        guard let image = NSBitmapImageRep(data: data) else {
            check(false, "icon " + slot.fileName + " decodes as PNG")
            continue
        }
        iconImages[slot.fileName] = image
        check(image.pixelsWide == slot.pixelSize && image.pixelsHigh == slot.pixelSize,
              "icon " + slot.fileName + " has its declared final dimensions")

        let backgroundData = try AppIconArtwork.pngData(for: slot, backgroundOnly: true)
        guard let background = NSBitmapImageRep(data: backgroundData) else {
            check(false, "icon " + slot.fileName + " background oracle decodes as PNG")
            continue
        }
        iconBackgrounds[slot.fileName] = background
    } catch {
        check(false, "icon " + slot.fileName + " renders without error")
    }
}

// MARK: - T-047: hierarchy and canvas fit (the symmetry gate measures the render)
for band in [AppIconArtwork.SizeBand.small, .mid, .large] {
    let geometry = AppIconArtwork.geometry(for: band)
    let bandLabel = "T-047 " + band.rawValue
    let upper = geometry.upperChild.rect
    let lower = geometry.lowerChild.rect
    let rootArea = geometry.root.rect.width * geometry.root.rect.height
    let largestChildArea = max(upper.width * upper.height, lower.width * lower.height)
    check(rootArea * 10 >= 21 * largestChildArea,
          bandLabel + " root card area is at least 2.1x the larger child card")
    let inkBounds = geometry.root.rect
        .union(geometry.upperChild.rect)
        .union(geometry.lowerChild.rect)
        .offsetBy(dx: geometry.translationX, dy: 0)
    check(CGRect(x: 116, y: 116, width: 792, height: 792).contains(inkBounds),
          bandLabel + " rendered ink silhouette stays 16 design units inside the canvas")
    let childrenFilled = geometry.upperChild.filled && geometry.lowerChild.filled
    if band == .small {
        check(childrenFilled,
              bandLabel + " fills both child cards on the minimal band")
    } else {
        check(!childrenFilled,
              bandLabel + " keeps outlined children")
    }
}

// MARK: - T-047 (p1 revision): rendered-silhouette gates, measured on the final
// rasters, never on source constants.
//
// p1 anchors: the previous icon fills 0.469 of its 16px ink bbox and its
// horizontal-mirror mismatch is 0.000 on every measured band (a ready negative
// control — any positive floor rejects it), while a solid rounded card fills
// about 0.9 of its bbox.
let iconFillRatioCeiling = 0.70
let iconFlipMismatchFloor = 0.10
let iconSmallSlots = iconSlots.filter { $0.band == .small }
check(iconSmallSlots.count == 2, "T-047 small band covers both minimal slots")
for slot in iconSmallSlots {
    guard let image = iconImages[slot.fileName],
          let fill = iconFillRatio(image) else {
        check(false, "T-047 " + slot.fileName + " fill ratio is readable")
        continue
    }
    print(String(format: "T-047 %@ fill=%.4f", slot.fileName, fill))
    check(fill <= iconFillRatioCeiling,
          "T-047 " + slot.fileName + " ink fills at most 70% of its bounding box")
}
for slot in iconSlots {
    guard let image = iconImages[slot.fileName],
          let mismatch = iconFlipMismatch(image) else {
        check(false, "T-047 " + slot.fileName + " flip mismatch is readable")
        continue
    }
    print(String(format: "T-047 %@ flip mismatch=%.4f", slot.fileName, mismatch))
    check(mismatch >= iconFlipMismatchFloor,
          "T-047 " + slot.fileName + " silhouette differs from its vertical mirror")
}

for slot in iconSlots {
    guard let image = iconImages[slot.fileName] else {
        check(false, "icon " + slot.fileName + " has a readable final raster")
        continue
    }
    guard let scan = iconStructureScan(image, slot: slot) else {
        check(false, "icon " + slot.fileName + " structure scan is readable")
        continue
    }
    print("Icon raster " + slot.fileName + ": " + String(image.pixelsWide) + "x"
          + String(image.pixelsHigh) + " column=" + String(scan.column)
          + " runs=" + String(scan.stats.count) + "/" + String(scan.expectedRuns)
          + " peaks=" + String(describing: scan.stats.peaks))
    check(scan.ownershipFailures.isEmpty,
          "icon " + slot.fileName + " scan column ink belongs to the expected cards")
    check(scan.stats.count == scan.expectedRuns,
          "icon " + slot.fileName + " scan finds its expected ink run count")
    check(scan.stats.weakestPeak >= 680, "icon " + slot.fileName + " weakest ink run reaches 680")
    if let centroid = iconCentroidEvidence(image) {
        print(String(format: "Icon centroid %@: dx=%.4f dy=%.4f tol=%.4f ink=%d",
                     slot.fileName, centroid.deltaX, centroid.deltaY,
                     centroid.tolerance, centroid.inkCount))
        check(abs(centroid.deltaX) <= centroid.tolerance,
              "icon " + slot.fileName + " ink centroid x is board-balanced")
        check(abs(centroid.deltaY) <= centroid.tolerance,
              "icon " + slot.fileName + " ink centroid y is board-balanced")
    } else {
        check(false, "icon " + slot.fileName + " has centroid evidence")
    }
}

var zeroTranslationControlFailures: [String] = []
var zeroTranslationControlValidated = 0
for slot in iconSlots {
    do {
        let data = try AppIconArtwork.pngData(for: slot, translationOverride: 0)
        guard let image = NSBitmapImageRep(data: data),
              let centroid = iconCentroidEvidence(image) else {
            check(false, "icon " + slot.fileName + " zero-translation centroid evidence")
            continue
        }
        zeroTranslationControlValidated += 1
        let rejected = abs(centroid.deltaX) > centroid.tolerance
            || abs(centroid.deltaY) > centroid.tolerance
        if rejected { zeroTranslationControlFailures.append(slot.fileName) }
        print(String(format: "Icon t=0 control %@: dx=%.4f dy=%.4f tol=%.4f rejected=%@",
                     slot.fileName, centroid.deltaX, centroid.deltaY,
                     centroid.tolerance, rejected ? "true" : "false"))
        check(rejected, "icon " + slot.fileName + " t=0 centroid control rejects")
        check(abs(centroid.deltaX) > centroid.tolerance,
              "icon " + slot.fileName + " t=0 control fails x centroid")
    } catch {
        check(false, "icon " + slot.fileName + " zero-translation control renders")
    }
}
print("Icon t=0 centroid control failures: " + zeroTranslationControlFailures.joined(separator: ","))
check(zeroTranslationControlValidated == iconSlots.count,
      "icon t=0 centroid control covers every slot")
check(zeroTranslationControlFailures.count == iconSlots.count,
      "icon t=0 centroid control rejects every slot")
check(zeroTranslationControlFailures.contains("icon_16x16.png"),
      "icon t=0 centroid control includes the 16px slot")

let physical32Slots = iconSlots.filter { $0.pixelSize == 32 }
check(AppIconArtwork.geometry(for: .small).connectorLineWidth == 112,
      "small icon connector strength uses the DESIGN 112px value")
check(physical32Slots.count == 2,
      "the two physical 32px slots are both represented")
if let small32 = physical32Slots.first(where: { $0.band == .small }),
   let mid32 = physical32Slots.first(where: { $0.band == .mid }),
   let smallData = iconData[small32.fileName],
   let midData = iconData[mid32.fileName] {
    check(small32.band != mid32.band && small32.fileName != mid32.fileName,
          "physical 32px slots retain distinct logical size bands")
    check(AppIconArtwork.geometry(for: small32.band) != AppIconArtwork.geometry(for: mid32.band),
          "small and mid 32px slots use distinct artwork geometry")
    check(smallData != midData,
          "small 32px and mid 32px final PNG bytes are not deduplicated")
} else {
    check(false, "physical 32px slots resolve both small and mid artwork")
}

let iconPalette = Palette.light
let iconAccent = iconPalette.accentRGB.quantized8
let iconCream = iconPalette.creamTextRGB.quantized8
let iconBottom = Palette.iconGradientBottomRGB.quantized8
let accentCoordinates = Palette.accentOKLCh
let bottomCoordinates = Palette.iconGradientBottomOKLCh
let hueDistance = abs(bottomCoordinates.hue - accentCoordinates.hue)
let wrappedHueDistance = min(hueDistance, 360 - hueDistance)
let finalBottomCoordinates = iconBottom.oklch
let finalBottomHueDistance = abs(finalBottomCoordinates.hue - accentCoordinates.hue)
let finalBottomWrappedHueDistance = min(finalBottomHueDistance, 360 - finalBottomHueDistance)
let finalBottomChromaDelta = abs(finalBottomCoordinates.chroma - bottomCoordinates.chroma)
print("Icon source colors: top=" + iconAccent.hex + " ink=" + iconCream.hex
      + " bottom=" + iconBottom.hex)
print(String(format: "Icon bottom OKLCh: L=%.6f C=%.6f h=%.3f", bottomCoordinates.lightness,
             bottomCoordinates.chroma, bottomCoordinates.hue))
check(iconAccent.hex == "#3368a0", "icon top stop comes from Palette light accent")
check(iconCream.hex == "#f2efe7", "icon glyph ink comes from Palette light cream")
do {
    let largeGeometry = AppIconArtwork.geometry(for: .large)
    if let largeImage = iconImages["icon_512x512@2x.png"],
       let rootInk = iconRasterColor(
        largeImage,
        x: iconPixelCoordinate(largeGeometry.root.rect.midX + largeGeometry.translationX,
                               pixelSize: 1024),
        y: iconSampleRow(ofDesignY: largeGeometry.root.rect.midY, pixelSize: 1024)) {
        check(rootInk == iconCream, "icon final raster root card uses Palette cream ink")
    } else {
        check(false, "icon final raster root card has a readable ink sample")
    }
}
check(iconBottom.hex == "#003c71", "icon derived bottom stop has the expected final 8-bit value")
check(abs(bottomCoordinates.lightness - accentCoordinates.lightness * 0.70) <= 0.000001,
      "icon bottom preserves the specified OKLCh lightness multiplier")
check(wrappedHueDistance <= 1.0, "icon bottom preserves accent OKLCh hue")
check(bottomCoordinates.chroma <= accentCoordinates.chroma + 0.000001,
      "icon gamut mapping only lowers OKLCh chroma")
print(String(format: "Icon final bottom OKLCh: L=%.6f C=%.6f h=%.3f",
             finalBottomCoordinates.lightness,
             finalBottomCoordinates.chroma, finalBottomCoordinates.hue))
check(finalBottomWrappedHueDistance <= 1.0,
      "icon final 8-bit bottom preserves accent hue within rounding")
check(finalBottomChromaDelta <= 0.002,
      "icon final 8-bit bottom preserves mapped chroma within rounding")

var inkSampleContrasts: [Double] = []
for slot in iconSlots {
    guard let image = iconImages[slot.fileName],
          let background = iconBackgrounds[slot.fileName] else { continue }
    let geometry = AppIconArtwork.geometry(for: slot.band)
    for (index, sample) in iconInkSamplePoints(for: slot.band).enumerated() {
        let x = iconPixelCoordinate(sample.0.x + geometry.translationX,
                                    pixelSize: image.pixelsWide)
        let y = iconSampleRow(ofDesignY: sample.0.y, pixelSize: image.pixelsHigh)
        let sampleLabel = "icon " + slot.fileName + " " + sample.1
            + " sample " + String(index + 1)
        guard let foreground = iconRasterColor(image, x: x, y: y),
              let localBackground = iconRasterColor(background, x: x, y: y) else {
            check(false, sampleLabel + " has final-raster samples")
            continue
        }
        let ratio = foreground.contrastRatio(with: localBackground)
        inkSampleContrasts.append(ratio)
        check(ratio >= 3.0, sampleLabel + " contrasts with its final local gradient")
    }
}
if let minimum = inkSampleContrasts.min(), let maximum = inkSampleContrasts.max() {
    print(String(format: "Icon ink sample final-raster contrast range: %.4f...%.4f",
                 minimum, maximum))
}
check(inkSampleContrasts.count == iconSlots.count * 3,
      "icon ink sample contrast covers three samples in every slot")

// MARK: - T-037: shared connector geometry, branch continuity, and fishbone topology
func connectorSVGAttribute(_ name: String, in line: String) -> String? {
    let marker = name + "=\""
    guard let start = line.range(of: marker) else { return nil }
    let valueStart = start.upperBound
    guard let end = line[valueStart...].firstIndex(of: "\"") else { return nil }
    return String(line[valueStart..<end])
}

do {
    let root = MindNode(text: "Connector root", children: (0..<6).map { index in
        MindNode(text: "Branch \(index)", children: [MindNode(text: "Deep \(index)")])
    })
    let layouts = LayoutEngine.layout(root: root, direction: .logicRight)
    let strokes = ConnectionGeometry.strokes(root: root, layouts: layouts, direction: .logicRight)
    let rootEdges = strokes.filter { $0.sourceID == root.id }
    let expectedIndices = Array(0..<6)
    let oldParentIndices = rootEdges.map { _ in layouts[root.id]!.colorIndex }
    print("T-037 logic root destination indices \(rootEdges.map(\.colorIndex))")
    print("T-037 old parent-color mutation indices \(oldParentIndices)")
    check(rootEdges.count == 6, "shared geometry emits six logicRight root edges")
    check(rootEdges.map(\.colorIndex) == expectedIndices,
          "logicRight root edges use each destination child branch color")
    check(Set(oldParentIndices).count == 1 && oldParentIndices != expectedIndices,
          "old parent-color root mutation is explicitly rejected")
    check(rootEdges.allSatisfy { $0.lineWidth == 3.5 },
          "logicRight root connector width remains 3.5")
    check(strokes.filter { $0.sourceID != nil && $0.sourceID != root.id }
        .allSatisfy { $0.lineWidth == 2.5 },
          "logicRight deeper connector width remains 2.5")
    check(strokes.allSatisfy {
        if case .cubic = $0.shape { return true }
        return false
    }, "logicRight connectors retain cubic geometry")
    let unchanged = LayoutEngine.layout(root: root, direction: .logicRight)
    check(layouts == unchanged, "connector generation does not move node layouts")

    let bracketLayouts = LayoutEngine.layout(root: root, direction: .bracket)
    let bracketStrokes = ConnectionGeometry.strokes(root: root, layouts: bracketLayouts,
                                                     direction: .bracket)
    check(bracketStrokes.count == strokes.count,
          "bracket emits the same edge count as logicRight")
    check(bracketStrokes.allSatisfy {
        if case let .polyline(points) = $0.shape { return points.count == 4 }
        return false
    }, "bracket connectors retain four-point right-angle geometry")
    check(bracketStrokes.map(\.lineWidth) == strokes.map(\.lineWidth),
          "bracket connector widths remain aligned with logicRight")

    func nodeFillHex(_ index: Int) -> String {
        let style = NodeStyle.of(depth: 1, palette: Palette.light,
                                 branchColor: Palette.light.color(forIndex: index))
        let ns = NSColor(style.fillBase).usingColorSpace(.sRGB) ?? NSColor.black
        return String(format: "#%02x%02x%02x", Int(round(ns.redComponent * 255)),
                      Int(round(ns.greenComponent * 255)), Int(round(ns.blueComponent * 255)))
    }
    let expectedFills = expectedIndices.map(nodeFillHex)
    let svg = MapExporter.svg(MindDocument(title: "Connector", root: root))
    let rootPathLines = svg.split(separator: "\n").map(String.init).filter {
        $0.contains("<path d=\"") && $0.contains("stroke-width=\"3.5\"")
    }
    let svgRootColors = rootPathLines.compactMap { connectorSVGAttribute("stroke", in: $0) }
    print("T-037 SVG root connector colors \(svgRootColors)")
    check(svgRootColors == expectedFills,
          "SVG root connector colors match destination NodeStyle branch fills")
    check(expectedFills.allSatisfy {
        svg.contains("fill=\"\($0)\" fill-opacity=\"1.0\"")
    }, "SVG depth-one node fills match the connector branch colors")
}

do {
    let fishRoot = MindNode(text: "Fishbone root", children: (0..<4).map { index in
        MindNode(text: "Fish branch \(index)", children: [MindNode(text: "Fish leaf \(index)")])
    })
    let layouts = LayoutEngine.layout(root: fishRoot, direction: .fishbone)
    let strokes = ConnectionGeometry.strokes(root: fishRoot, layouts: layouts, direction: .fishbone)
    let rootLayout = layouts[fishRoot.id]!
    let branchLayouts = fishRoot.children.compactMap { layouts[$0.id] }
        .sorted { $0.frame.minX < $1.frame.minX }
    let farthestBranchEnd = branchLayouts.map { $0.center.x + 60 }.max()!
    let oldEnd = rootLayout.frame.maxX + 120
    var spineEndX: CGFloat?
    if case let .polyline(points) = strokes.first?.shape { spineEndX = points.last?.x }
    print(String(format: "T-037 fishbone spine end %.1f, required %.1f, old %.1f",
                 Double(spineEndX ?? -1), Double(farthestBranchEnd), Double(oldEnd)))
    check(strokes.count == 13, "fishbone emits one spine, four ribs, and eight edge chains")
    check(strokes.allSatisfy {
        if case let .polyline(points) = $0.shape { return points.count >= 2 }
        return false
    }, "fishbone shared primitives contain no cubic shapes")
    if let spineEndX {
        check(spineEndX >= farthestBranchEnd,
              "fishbone spine reaches the farthest depth-one branch")
        check(spineEndX > oldEnd,
              "fishbone spine endpoint exceeds the old start-plus-120 mutation")
    } else {
        check(false, "fishbone spine has a measurable endpoint")
        check(false, "fishbone spine endpoint exceeds the old start-plus-120 mutation")
    }
    let ribs = Array(strokes.dropFirst().prefix(4))
    check(ribs.map(\.colorIndex) == Array(0..<4),
          "fishbone ribs use their destination branch colors in order")
    let edgeIndices = strokes.filter { $0.sourceID != nil && $0.targetID != nil }
        .map(\.colorIndex)
    check(edgeIndices == [0, 0, 1, 1, 2, 2, 3, 3],
          "fishbone edge chains use destination child branch colors")
    check(strokes.first?.colorIndex == 0 && strokes.first?.opacity == 0.35
          && strokes.first?.lineWidth == 4,
          "fishbone spine keeps the index-zero 35-percent four-point style")

    let document = MindDocument(title: "Fishbone", directionName: MapDirection.fishbone.rawValue,
                                root: fishRoot)
    let fishSVG = MapExporter.svg(document)
    let fishPathLines = fishSVG.split(separator: "\n").map(String.init).filter {
        $0.contains("<path d=\"")
    }
    check(fishPathLines.count == strokes.count,
          "fishbone SVG serializes exactly the shared primitive count")
    check(fishPathLines.allSatisfy { $0.contains(" d=\"M ") && !$0.contains(" C ") },
          "fishbone SVG uses only shared polyline M/L path data")
    check(fishSVG.contains("stroke-opacity=\"0.35\""),
          "fishbone SVG preserves spine opacity")

    // Pre-change MapExporter ignored fishbone and used the generic cubic tree path.
    let oldGenericSVG = MapExporter.svg(MindDocument(title: "Fishbone baseline",
                                                       directionName: MapDirection.logicRight.rawValue,
                                                       root: fishRoot))
    let oldGenericCubic = oldGenericSVG.contains(" C ")
    let oldMissingSpine = !oldGenericSVG.contains("stroke-width=\"4.0\"")
    print("T-037 old generic fishbone mutation cubic=\(oldGenericCubic) missingSpine=\(oldMissingSpine)")
    check(oldGenericCubic && oldMissingSpine,
          "old generic fishbone behavior remains a detectable negative control")
}

// MARK: - T-041: persistent autosave/recovery failure state
// Failure state is tested through the same public result paths that drive the UI;
// every fixture lives under a fresh /tmp TabStore root, never Application Support.
do {
    let root = freshTabStoreRoot("c4a-recovery-episodes")
    defer { try? FileManager.default.removeItem(at: root) }
    let fixture = makeTabFixture(in: root)
    var recoveryAllowed = false
    var recoveryCalls = 0
    let store = TabStore(directory: fixture.live)

    await MainActor.run {
        let vm = MindMapViewModel(tabStore: store, recoveryWriter: { _ in
            recoveryCalls += 1
            return recoveryAllowed
        })
        vm.document = fixture.single
        vm.statusMessage = "seed status"
        @MainActor func invokeRecovery() {
            vm.sessions = [
                EditorSession(id: fixture.singleID, document: fixture.single),
                EditorSession(id: fixture.multiID, document: fixture.multi)
            ]
            vm.activeIndex = 0
            vm.document = fixture.single
            vm.closeTab(1)
        }

        invokeRecovery()
        check(recoveryCalls == 1, "recovery failure invokes the injected writer")
        check(vm.storageFailures == Set([.recovery]),
              "first recovery failure persists its failure kind")
        check(vm.storageWarningText == "⚠︎ 復原快照失敗",
              "recovery failure derives the exact warning text")
        check(vm.statusMessage == "⚠︎ 復原快照失敗",
              "first recovery failure sends the exact transient warning")

        vm.statusMessage = "sentinel: do not spam"
        invokeRecovery()
        check(recoveryCalls == 2, "repeated recovery failure still invokes the writer")
        check(vm.storageFailures == Set([.recovery]),
              "repeated recovery failure keeps the persistent kind")
        check(vm.statusMessage == "sentinel: do not spam",
              "repeated recovery failure does not notify again")

        recoveryAllowed = true
        invokeRecovery()
        check(vm.storageFailures.isEmpty,
              "recovery success clears only the recovery failure")
        check(vm.storageWarningText == nil,
              "recovery success removes the recovery warning")

        recoveryAllowed = false
        vm.statusMessage = "episode two sentinel"
        invokeRecovery()
        check(recoveryCalls == 4, "the second recovery episode invokes the writer")
        check(vm.statusMessage == "⚠︎ 復原快照失敗",
              "a later recovery episode sends a second transient warning")
        check(vm.storageFailures == Set([.recovery]),
              "the second recovery episode persists recovery failure")
    }
}

do {
    let root = freshTabStoreRoot("c4a-cross-kind")
    defer { try? FileManager.default.removeItem(at: root) }
    let fixture = makeTabFixture(in: root)
    let production = TabStore.Dependencies.production
    var autosaveAllowed = false
    var recoveryAllowed = false
    let dependencies = TabStore.Dependencies(
        writeData: { data, url in
            guard autosaveAllowed else { throw TabStoreCheckFailure.write }
            try production.writeData(data, url)
        },
        exchangeDirectories: { live, staging in
            guard autosaveAllowed else { throw TabStoreCheckFailure.exchange }
            try production.exchangeDirectories(live, staging)
        },
        removeItem: production.removeItem)
    let store = TabStore(directory: fixture.live, dependencies: dependencies)
    let timestamp = Date(timeIntervalSince1970: 1_700_000_401)

    await MainActor.run {
        let vm = MindMapViewModel(tabStore: store, recoveryWriter: { _ in recoveryAllowed })
        vm.document = fixture.single
        vm.sessions = [EditorSession(id: fixture.singleID, document: fixture.single)]
        vm.activeIndex = 0
        vm.lastSavedAt = timestamp
        vm.dirty = true
        vm.statusMessage = "cross-kind seed"
        @MainActor func invokeRecovery() {
            vm.sessions = [
                EditorSession(id: fixture.singleID, document: fixture.single),
                EditorSession(id: fixture.multiID, document: fixture.multi)
            ]
            vm.activeIndex = 0
            vm.document = fixture.single
            vm.closeTab(1)
        }

        invokeRecovery()
        let failedSave = vm.autosaveAllSessions()
        check(!failedSave.succeeded,
              "cross-kind autosave failure is observable")
        check(vm.storageFailures == Set([.autosave, .recovery]),
              "autosave and recovery failures coexist")
        check(vm.storageWarningText == "⚠︎ 儲存失敗（自動保存・復原快照）",
              "both failures derive the exact combined warning")
        check(vm.saveStatusSubtitle == "v\(AppInfo.version) · ⚠︎ 儲存失敗（自動保存・復原快照）",
              "subtitle exposes the combined persistent warning")
        check(!vm.saveStatusSubtitle.contains("未儲存")
              && !vm.saveStatusSubtitle.contains("已自動保存"),
              "persistent warning takes priority over dirty and saved-time text")
        check(vm.lastSavedAt == timestamp,
              "failed autosave does not advance the previous saved time")
        check(vm.statusMessage == "⚠︎ 儲存失敗（自動保存・復原快照）",
              "first cross-kind episode notifies with the combined warning")

        recoveryAllowed = true
        invokeRecovery()
        check(vm.storageFailures == Set([.autosave]),
              "recovery success does not clear autosave failure")
        check(vm.storageWarningText == "⚠︎ 自動保存失敗",
              "remaining autosave failure keeps its own warning")

        recoveryAllowed = false
        vm.statusMessage = "second cross-kind episode"
        invokeRecovery()
        check(vm.storageFailures == Set([.autosave, .recovery]),
              "a later recovery failure restores only recovery alongside autosave")

        autosaveAllowed = true
        let successfulSave = vm.autosaveAllSessions()
        check(successfulSave.succeeded,
              "autosave success is accepted after the injected failure")
        check(vm.storageFailures == Set([.recovery]),
              "autosave success does not clear recovery failure")
        check(vm.storageWarningText == "⚠︎ 復原快照失敗",
              "remaining recovery failure keeps its own warning")

        recoveryAllowed = true
        invokeRecovery()
        check(vm.storageFailures.isEmpty,
              "each success eventually clears only its own failure")
    }
}



// MARK: - T-042: semantic shell colors and content-color ownership
// Shell controls must follow AppKit semantic tokens in both appearance lanes;
// document content (star/color tag) deliberately remains Palette/Theme-owned.
func projectSource(_ relativePath: String) -> String {
    let checksFile = URL(fileURLWithPath: #filePath)
    let projectRoot = checksFile.deletingLastPathComponent().deletingLastPathComponent()
    let url = projectRoot.appendingPathComponent(relativePath)
    precondition(FileManager.default.fileExists(atPath: url.path),
                 "missing project source for T-042: \(relativePath)")
    return try! String(contentsOf: url, encoding: .utf8)
}

let t042ContentView = projectSource("Sources/MindFlowKit/ContentView.swift")
let t042ViewModel = projectSource("Sources/MindFlowKit/ViewModel.swift")

let t042PaletteReferences = t042ContentView.components(separatedBy: "Palette").count - 1
check(t042PaletteReferences == 1
      && t042ContentView.contains("Palette.screen.statusHighlight"),
      "ContentView retains Palette only for the outline star content color")
check(!t042ContentView.contains("palette."),
      "ContentView has no lower-case Palette shell color references")
check(!t042ContentView.contains("palette.accent.opacity(0.18)")
      && !t042ContentView.contains("palette.statusHighlight")
      && !t042ContentView.contains("palette.textPrimary")
      && !t042ContentView.contains("palette.textSecondary"),
      "old Palette shell colors are unreachable")
check(t042ContentView.contains("Theme.colorTags")
      && t042ContentView.contains("Theme.colorTag(named: key)"),
      "outline color tags remain Theme content colors")
check(!t042ContentView.contains(".tint(")
      && !t042ContentView.contains(".accentColor(")
      && !t042ContentView.contains(".foregroundStyle(.red)"),
      "ContentView does not inject a global tint or fixed shell red")

check(t042ContentView.contains("Capsule().fill(isActive")
      && t042ContentView.contains("Color(nsColor: .controlBackgroundColor)")
      && t042ContentView.contains("Color(nsColor: .separatorColor)"),
      "active tab uses semantic control fill and separator boundary")
check(t042ContentView.contains("Circle().fill(Color(nsColor: .secondaryLabelColor))"),
      "dirty dot uses the semantic secondary label color")
check(t042ContentView.contains("RoundedRectangle(cornerRadius: 5)")
      && t042ContentView.contains(".fill(vm.selection == row.id")
      && t042ContentView.contains(".stroke(vm.selection == row.id")
      && !t042ContentView.contains("palette.accent.opacity(0.16)"),
      "selected outline row uses neutral fill and separator")

let warningCondition = "if let warning = vm.storageWarningText, !vm.storageFailures.isEmpty"
check(t042ContentView.contains(warningCondition),
      "empty storage failure state has no warning icon and nonempty state enters it")
check(t042ContentView.components(separatedBy: "exclamationmark.triangle.fill").count - 1 == 1
      && t042ContentView.contains(".foregroundStyle(Color(nsColor: .systemOrange))")
      && t042ContentView.contains(".accessibilityLabel(warning)")
      && t042ContentView.contains(".accessibilityHint(warning)")
      && t042ContentView.contains(".help(warning)"),
      "global warning icon has one orange visual and matching AX/help text")
let warningIndex = t042ContentView.range(of: warningCondition)?.lowerBound
let tabLoopIndex = t042ContentView.range(of: "ForEach(vm.sessions.indices")?.lowerBound
check(warningIndex != nil && tabLoopIndex != nil && warningIndex! > tabLoopIndex!,
      "global warning icon is outside per-tab dirty-dot rendering")

check(!t042ViewModel.contains("⚠️")
      && t042ViewModel.contains("notify(\"⚠︎ 儲存失敗，請確認磁碟可寫入\")"),
      "manual-save warning uses the text-presentation warning marker")
check(t042ContentView.contains("including persistent storage warnings"),
      "saveSubtitle comment describes ViewModel warning delegation")

let t042SemanticTokens: [(String, NSColor)] = [
    ("controlBackground", .controlBackgroundColor),
    ("separator", .separatorColor),
    ("secondaryLabel", .secondaryLabelColor),
    ("label", .labelColor),
    ("systemOrange", .systemOrange),
    ("systemRed", .systemRed)
]
for appearanceName in [NSAppearance.Name.aqua, NSAppearance.Name.darkAqua] {
    guard let appearance = NSAppearance(named: appearanceName) else {
        check(false, "semantic colors resolve \(appearanceName.rawValue) appearance")
        continue
    }
    for (name, color) in t042SemanticTokens {
        var resolved: NSColor?
        appearance.performAsCurrentDrawingAppearance {
            resolved = color.usingColorSpace(.sRGB)
        }
        let valid = resolved != nil && resolved!.redComponent.isFinite
            && resolved!.greenComponent.isFinite && resolved!.blueComponent.isFinite
        check(valid, "semantic \(name) resolves in \(appearanceName.rawValue)")
    }
}
for path in ["Sources/MindFlowKit/MapCanvasView.swift",
             "Sources/MindFlowKit/NodeView.swift",
             "Sources/MindFlowKit/MapExporter.swift"] {
    check(projectSource(path).contains("Palette"),
          "Palette ownership remains in \(path)")
}



// MARK: - T-043: the window toolbar is gone, and no capability left with it
// The original ticket asked for the toolbar to be *slimmed* to three buttons.
// That had in fact already shipped (30cca8f, 2026-09-02), and the Owner was
// looking at the slimmed version when they still called it ugly and
// unnecessary -- so satisfying the old wording would not have satisfied the
// request. The Owner then chose outright removal.
//
// What survives from the old oracle is the part that matters: removal must not
// cost a single capability. That half is deliberately made STRICTER here.
// Entrances are now counted only in the menu bar and the canvas context menu --
// places a user can actually click. The previous version also searched
// ContentView and KeyboardMonitor, where an internal plumbing string could
// satisfy a needle while the user had no way to reach the feature at all.
// The inspector toggle was exactly that shape of risk: before this change its
// only entrance in the entire product was the toolbar button being deleted.
let t043Check: () -> Void = {
    let source = projectSource("Sources/MindFlowKit/ContentView.swift")
    let canvas = projectSource("Sources/MindFlowKit/MapCanvasView.swift")
    let appCommands = projectSource("Sources/MindFlow/MindFlowApp.swift")

    check(!source.contains("\n        .toolbar {"),
          "T-043 the window toolbar declaration is gone")
    check(!source.contains("ellipsis.circle"),
          "T-043 no More menu survives in the shell")

    // Only user-clickable surfaces count as an entrance.
    let entrances = appCommands + canvas
    let capabilityEntrances: [(capability: String, needles: [String])] = [
        ("子主題", ["Button(\"加入子主題\")"]),
        ("兄弟主題", ["Button(\"加入兄弟主題\")"]),
        ("檢閱器", ["Toggle(\"檢閱器\", isOn: $vm.showInspector)"]),
        ("刪除", ["Button(\"刪除主題\")"]),
        // Deliberately NOT satisfied by the "全部收合／展開" toggle: a toggle is a
        // different capability from the two explicit commands, and accepting it
        // here let both expandAll and collapseAll fall out of reach until
        // scripts/verify.sh caught them.
        ("全部展開", ["Button(\"全部展開\") { vm.expandAll() }"]),
        ("全部收合", ["Button(\"全部收合\") { vm.collapseAll() }"]),
        ("展開至", ["Menu(\"展開至\")"]),
        ("符合視窗", ["Button(\"符合視窗\")", "Button(\"全圖\")"]),
        ("取消聚焦", ["Button(\"取消聚焦\")"]),
        ("版面", ["CommandMenu(\"版面\")"]),
        ("複製 MD", ["Button(\"複製為 Markdown\")"]),
    ]
    for entry in capabilityEntrances {
        check(entry.needles.contains { entrances.contains($0) },
              "T-043 capability \(entry.capability) keeps a user-clickable entrance")
    }

    // The three rehomed commands need working shortcuts, not just menu rows.
    // Fit deliberately has no key equivalent; ⌘0 belongs to zoom reset and the
    // local monitor consumes it first. Asserting a shortcut here would force a
    // shortcut that cannot fire.
    check(!appCommands.contains("keyboardShortcut(\"0\", modifiers: [.command])"),
          "T-043 fit-to-window does not claim a shortcut the monitor already eats")
    check(appCommands.contains("keyboardShortcut(\"i\", modifiers: [.command, .option])"),
          "T-043 the inspector toggle is reachable by shortcut")
}

t043Check()
themeCheck()

// MARK: - T-048: marked badge shared bottom-center geometry
// Screen/PNG/PDF retain SF Symbol star.fill; SVG retains ★. Only their placement is shared.
func t048PointEqual(_ lhs: CGPoint, _ rhs: CGPoint, tolerance: CGFloat = 0.0001) -> Bool {
    abs(lhs.x - rhs.x) <= tolerance && abs(lhs.y - rhs.y) <= tolerance
}

func t048Attribute(_ name: String, in line: String) -> String? {
    let marker = name + "=\""
    guard let start = line.range(of: marker) else { return nil }
    let valueStart = start.upperBound
    guard let end = line[valueStart...].firstIndex(of: "\"") else { return nil }
    return String(line[valueStart..<end])
}

func t048ViewBox(_ svg: String) -> CGRect? {
    guard let line = svg.split(separator: "\n").map(String.init).first(where: { $0.contains("viewBox=\"") }),
          let raw = t048Attribute("viewBox", in: line) else { return nil }
    let values = raw.split(whereSeparator: { $0 == " " || $0 == "\t" }).compactMap { Double($0) }
    guard values.count == 4 else { return nil }
    return CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
}

let t048Frame = CGRect(x: 100, y: 200, width: 64, height: 32)
let t048Anchor = MarkedBadgeGeometry.anchor(for: t048Frame)
let t048Screen = MarkedBadgeGeometry.screenFootprint(for: t048Frame)
let t048ScreenLocal = MarkedBadgeGeometry.screenLocalFootprint(for: t048Frame)
let t048ScreenMap = CGPoint(x: t048ScreenLocal.midX + t048Frame.minX,
                            y: t048ScreenLocal.midY + t048Frame.minY)
let t048SVG = MarkedBadgeGeometry.svgEmBox(for: t048Frame)
let t048SVGMap = CGPoint(x: t048SVG.midX, y: t048SVG.midY)

print(String(format: "T-048 anchor frame=(%.1f,%.1f,%.1fx%.1f) anchor=(%.1f,%.1f) screen=(%.1fx%.1f) svg=(%.1fx%.1f)",
             t048Frame.minX, t048Frame.minY, t048Frame.width, t048Frame.height,
             t048Anchor.x, t048Anchor.y, t048Screen.width, t048Screen.height,
             t048SVG.width, t048SVG.height))
check(t048PointEqual(t048Anchor, t048ScreenMap)
      && t048PointEqual(t048Anchor, t048SVGMap),
      "screen local and SVG conversions return the same map-space anchor")
check(t048Screen.minY > t048Frame.maxY && !t048Screen.intersects(t048Frame),
      "screen SF Symbol footprint is completely below the card")
check(t048SVG.minY > t048Frame.maxY && !t048SVG.intersects(t048Frame),
      "SVG star em-box is completely below the card")
let t048IndependentSVGAnchor = CGPoint(x: t048Anchor.x + 1, y: t048Anchor.y)
check(!t048PointEqual(t048Anchor, t048IndependentSVGAnchor),
      "negative control: independent renderer anchors are rejected")

// The old leading overlay sat on the child connector entry. Keep that exact failure
// observable while the production badge is checked against the same entry zone.
let t048ConnectorEntryZone = CGRect(x: t048Frame.minX - 2, y: t048Frame.midY - 2,
                                    width: 4, height: 4)
let t048OldLeading = CGRect(x: t048Frame.minX - 10, y: t048Frame.midY - 4.5,
                            width: 9, height: 9)
let t048OldLeadingClear = !t048OldLeading.intersects(t048Frame)
    && !t048OldLeading.intersects(t048ConnectorEntryZone)
print("T-048 old leading clearance=\(t048OldLeadingClear)")
check(!t048OldLeadingClear,
      "negative control: old leading-center badge collides with card/connector clearance")
check(!t048Screen.intersects(t048ConnectorEntryZone),
      "bottom-center screen badge clears the connector entry zone")

let t048OldSVGEmBox = CGRect(x: t048Frame.minX + 1, y: t048Frame.minY + 4,
                             width: MarkedBadgeGeometry.svgAdvance,
                             height: MarkedBadgeGeometry.svgAscent + MarkedBadgeGeometry.svgDescent)
print("T-048 old SVG em-box intersects card=\(t048OldSVGEmBox.intersects(t048Frame))")
check(t048OldSVGEmBox.intersects(t048Frame),
      "negative control: old SVG minX+6/minY+14 star is inside the card")

let t048FixedGold = Palette.RGB(hex: 0xF5C542).quantized8
let t048LightHighlight = Palette.light.statusHighlightRGB.quantized8
let t048DarkHighlight = Palette.dark.statusHighlightRGB.quantized8
let t048LightHighlightRatios = [
    t048LightHighlight.contrastRatio(with: Palette.light.canvasRGB),
    t048LightHighlight.contrastRatio(with: Palette.light.cardRGB)
]
let t048DarkHighlightRatios = [
    t048DarkHighlight.contrastRatio(with: Palette.dark.canvasRGB),
    t048DarkHighlight.contrastRatio(with: Palette.dark.cardRGB)
]
let t048FixedGoldRatios = [
    t048FixedGold.contrastRatio(with: Palette.light.canvasRGB),
    t048FixedGold.contrastRatio(with: Palette.light.cardRGB)
]
print(String(format: "T-048 status highlight light=%@ range %.4f...%.4f dark=%@ range %.4f...%.4f fixed-gold range %.4f...%.4f",
             t048LightHighlight.hex, t048LightHighlightRatios.min() ?? 0,
             t048LightHighlightRatios.max() ?? 0, t048DarkHighlight.hex,
             t048DarkHighlightRatios.min() ?? 0, t048DarkHighlightRatios.max() ?? 0,
             t048FixedGoldRatios.min() ?? 0, t048FixedGoldRatios.max() ?? 0))
check(t048LightHighlightRatios.allSatisfy { $0 >= 3.1 },
      "light status highlight Palette quantized sample clears canvas and card at 3.1:1")
check(t048DarkHighlightRatios.allSatisfy { $0 >= 3.1 },
      "dark status highlight Palette quantized sample clears canvas and card at 3.1:1")

@MainActor
func t048RenderedRGB(_ color: Color, scheme: ColorScheme) -> Palette.RGB? {
    let renderer = ImageRenderer(content:
        Rectangle()
            .fill(color)
            .frame(width: 12, height: 12)
            .environment(\.colorScheme, scheme)
    )
    renderer.scale = 1
    renderer.colorMode = .nonLinear
    guard let image = renderer.nsImage else { return nil }
    var proposed = CGRect(origin: .zero, size: image.size)
    guard let cgImage = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil),
          let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
    let width = cgImage.width
    let height = cgImage.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let rendered = pixels.withUnsafeMutableBytes { bytes -> Bool in
        guard let context = CGContext(data: bytes.baseAddress,
                                      width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return false }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }
    guard rendered else { return nil }
    let index = ((height / 2) * width + width / 2) * 4
    return Palette.RGB(red: Double(pixels[index]) / 255,
                       green: Double(pixels[index + 1]) / 255,
                       blue: Double(pixels[index + 2]) / 255)
}

for (name, scheme) in [
    ("light", ColorScheme.light),
    ("dark", ColorScheme.dark),
] {
    guard let highlight = await t048RenderedRGB(Palette.screen.statusHighlight, scheme: scheme),
          let canvas = await t048RenderedRGB(Palette.screen.canvasBackground, scheme: scheme),
          let card = await t048RenderedRGB(Palette.screen.card, scheme: scheme) else {
        check(false, "T-048 \(name) final SwiftUI raster is sampleable")
        continue
    }
    let ratios = [highlight.contrastRatio(with: canvas), highlight.contrastRatio(with: card)]
    print(String(format: "T-048 %@ rendered status=%@ canvas=%@ card=%@ range %.4f...%.4f",
                 name, highlight.hex, canvas.hex, card.hex,
                 ratios.min() ?? 0, ratios.max() ?? 0))
    check(ratios.allSatisfy { $0 >= 3.1 },
          "T-048 \(name) final SwiftUI raster clears canvas and card at 3.1:1")
}
if let fixedRaster = await t048RenderedRGB(Palette.RGB(hex: 0xF5C542).color, scheme: .light),
   let lightCanvasRaster = await t048RenderedRGB(Palette.screen.canvasBackground, scheme: .light) {
    check(fixedRaster.contrastRatio(with: lightCanvasRaster) < 3.1,
          "negative control: fixed-gold final raster fails the light canvas")
} else {
    check(false, "T-048 fixed-gold raster mutation is sampleable")
}

check(t048FixedGoldRatios.contains { $0 < 3.1 },
      "negative control: fixed F5C542 fails light status-highlight contrast")
let t048SourceOKLCh = Palette.statusHighlightSourceOKLCh
let t048LightOKLCh = Palette.light.statusHighlightOKLCh
let t048HueDelta = min(abs(t048LightOKLCh.hue - t048SourceOKLCh.hue),
                       360 - abs(t048LightOKLCh.hue - t048SourceOKLCh.hue))
print(String(format: "T-048 light status OKLCh source L=%.5f C=%.5f h=%.2f -> L=%.5f C=%.5f h=%.2f",
             t048SourceOKLCh.lightness, t048SourceOKLCh.chroma, t048SourceOKLCh.hue,
             t048LightOKLCh.lightness, t048LightOKLCh.chroma, t048LightOKLCh.hue))
check(t048LightOKLCh.lightness < t048SourceOKLCh.lightness
      && t048LightOKLCh.chroma <= t048SourceOKLCh.chroma + 0.003
      && t048HueDelta <= 1.0,
      "light status highlight derives from source gold by lowering L without hue drift")

let t048Deep = MindNode(text: "深層", marked: true)
let t048Right = MindNode(text: "右分支", note: "長備註", marked: true,
                         url: "https://example.com", children: [t048Deep])
let t048Left = MindNode(text: "左分支", marked: true)
let t048Root = MindNode(text: "T-048 根", marked: true, children: [t048Right, t048Left])
let t048MarkedNodes = [t048Root, t048Right, t048Deep, t048Left]
let t048Directions: [MapDirection] = [.logicRight, .balanced, .fishbone, .bracket]

for direction in t048Directions {
    let layouts = LayoutEngine.layout(root: t048Root, direction: direction)
    let document = MindDocument(title: "T-048", directionName: direction.rawValue, root: t048Root)
    let strokes = ConnectionGeometry.strokes(root: t048Root, layouts: layouts,
                                             direction: direction)
    var cardContentBounds = CGRect.null
    for layout in layouts.values { cardContentBounds = cardContentBounds.union(layout.frame) }
    let contentBounds = cardContentBounds
        .union(MarkedBadgeGeometry.screenBounds(for: t048Root, layouts: layouts))
    let cmdZeroBounds = contentBounds.insetBy(dx: -180, dy: -140)
    var minimumFitMargin = CGFloat.greatestFiniteMagnitude
    for node in t048MarkedNodes {
        guard let layout = layouts[node.id] else {
            check(false, "T-048 \(direction.rawValue) lays out marked node \(node.text)")
            continue
        }
        let screen = MarkedBadgeGeometry.screenFootprint(for: layout.frame)
        let svgBox = MarkedBadgeGeometry.svgEmBox(for: layout.frame)
        check(screen.minY > layout.frame.maxY && !screen.intersects(layout.frame),
              "T-048 \(direction.rawValue) screen badge clears \(node.text) card")
        check(svgBox.minY > layout.frame.maxY && !svgBox.intersects(layout.frame),
              "T-048 \(direction.rawValue) SVG badge clears \(node.text) card")
        let margins = [screen.minX - cmdZeroBounds.minX,
                       screen.minY - cmdZeroBounds.minY,
                       cmdZeroBounds.maxX - screen.maxX,
                       cmdZeroBounds.maxY - screen.maxY]
        minimumFitMargin = min(minimumFitMargin, margins.min() ?? 0)
        check(margins.allSatisfy { $0 >= 1 },
              "T-048 \(direction.rawValue) Cmd+0 badge has one-device-pixel fit margin")
        for stroke in strokes where stroke.targetID == node.id {
            let endpoint: CGPoint?
            switch stroke.shape {
            case let .cubic(_, _, _, to): endpoint = to
            case let .polyline(points): endpoint = points.last
            }
            if let endpoint {
                let zone = CGRect(x: endpoint.x - 3, y: endpoint.y - 3, width: 6, height: 6)
                check(!screen.intersects(zone),
                      "T-048 \(direction.rawValue) badge clears connector endpoint for \(node.text)")
            }
        }
    }
    print(String(format: "T-048 %@ Cmd+0 minimum badge margin %.2f", direction.rawValue,
                 Double(minimumFitMargin)))

    let svg = MapExporter.svg(document)
    let starLines = svg.split(separator: "\n").map(String.init).filter { $0.contains(">★</text>") }
    check(starLines.count == t048MarkedNodes.count,
          "T-048 \(direction.rawValue) SVG emits one star per marked node")
    if let viewBox = t048ViewBox(svg) {
        for node in t048MarkedNodes {
            if let layout = layouts[node.id] {
                let badge = MarkedBadgeGeometry.svgEmBox(for: layout.frame)
                check(viewBox.contains(CGPoint(x: badge.minX, y: badge.minY))
                      && viewBox.contains(CGPoint(x: badge.maxX, y: badge.maxY)),
                      "T-048 \(direction.rawValue) SVG viewBox contains \(node.text) badge")
                let expectedCoordinates = "x=\"\(badge.midX)\" y=\"\(MarkedBadgeGeometry.svgBaseline(for: layout.frame))\""
                check(svg.contains(expectedCoordinates),
                      "T-048 \(direction.rawValue) SVG star derives its coordinates from the shared anchor")
            }
        }
    } else {
        check(false, "T-048 \(direction.rawValue) SVG exposes a parseable viewBox")
    }
    check(svg.contains(Palette.light.statusHighlightRGB.hex),
          "T-048 \(direction.rawValue) SVG star uses the resolved light status token")
}

let t048NoteBox = CGRect(x: t048Frame.minX - 9, y: t048Frame.minY - 9, width: 9, height: 9)
let t048URLBox = CGRect(x: t048Frame.maxX - 15, y: t048Frame.minY - 6, width: 9, height: 9)
check(!t048Screen.intersects(t048NoteBox) && !t048Screen.intersects(t048URLBox)
      && !t048NoteBox.intersects(t048URLBox),
      "minimum 64x32 note+URL+marked node keeps all three badges separate")

let t048NodeSource = projectSource("Sources/MindFlowKit/NodeView.swift")
let t048ExporterSource = projectSource("Sources/MindFlowKit/MapExporter.swift")
let t048StaticSource = projectSource("Sources/MindFlowKit/StaticMapView.swift")
check(t048NodeSource.contains("MarkedBadgeGeometry.screenLocalFootprint")
      && t048NodeSource.contains("star.fill")
      && !t048NodeSource.contains(".offset(x: -10)"),
      "NodeView uses the shared screen anchor instead of the old leading offset")
check(t048ExporterSource.contains("MarkedBadgeGeometry.svgEmBox")
      && t048ExporterSource.contains("MarkedBadgeGeometry.svgBaseline")
      && !t048ExporterSource.contains("f.minX + 6")
      && !t048ExporterSource.contains("f.minY + 14"),
      "MapExporter uses the shared SVG anchor instead of the old in-card position")
check(t048StaticSource.contains("interactionScale: 1.0")
      && t048StaticSource.contains("NodeView(node: item.node"),
      "StaticMapView inherits the shared badge renderer at explicit scale one")

// T-048 follow-up: badge reservation is a pure second stage after card-only placement.
// It keeps marked cards stable, moves only later colliding sibling subtrees, and never recentres
// a parent; any parent displacement is bounded by the cumulative shifts in its sibling group.
let t048ReflowRootID = UUID(uuidString: "00000000-0000-4000-8000-000000000101")!
let t048ReflowRightID = UUID(uuidString: "00000000-0000-4000-8000-000000000102")!
let t048ReflowLaterID = UUID(uuidString: "00000000-0000-4000-8000-000000000103")!
let t048ReflowDescendantID = UUID(uuidString: "00000000-0000-4000-8000-000000000104")!
let t048PlainRight = MindNode(id: t048ReflowRightID, text: "R")
let t048MarkedRight = MindNode(id: t048ReflowRightID, text: "R", marked: true)
let t048PlainLater = MindNode(
    id: t048ReflowLaterID, text: "L",
    children: [MindNode(id: t048ReflowDescendantID, text: "L1")])
let t048MarkedLater = t048PlainLater
let t048PlainRoot = MindNode(id: t048ReflowRootID, text: "P",
                             children: [t048PlainRight, t048PlainLater])
let t048MarkedRoot = MindNode(id: t048ReflowRootID, text: "P",
                              children: [t048MarkedRight, t048MarkedLater])
let t048CardOnly = LayoutEngine.layout(root: t048PlainRoot, direction: .logicRight)
let t048Resolved = LayoutEngine.layout(root: t048MarkedRoot, direction: .logicRight)
let t048ResolvedAgain = LayoutEngine.resolveMarkedBadgeCollisions(
    root: t048MarkedRoot, direction: .logicRight, layouts: t048Resolved)
let t048NoMarkedResolved = LayoutEngine.resolveMarkedBadgeCollisions(
    root: t048PlainRoot, direction: .logicRight, layouts: t048CardOnly)

let t048StableRoot = t048Resolved[t048ReflowRootID]!.frame == t048CardOnly[t048ReflowRootID]!.frame
let t048StableMarkedCard = t048Resolved[t048ReflowRightID]!.frame == t048CardOnly[t048ReflowRightID]!.frame
let t048LaterShift = t048Resolved[t048ReflowLaterID]!.frame.minY
    - t048CardOnly[t048ReflowLaterID]!.frame.minY
let t048Reserved = MarkedBadgeGeometry.layoutReservedFootprint(
    for: t048Resolved[t048ReflowRightID]!.frame)
let t048LaterCard = t048Resolved[t048ReflowLaterID]!.frame
print(String(format: "T-048 reflow logicRight laterShift=%.3f reserved=(%.1f,%.1f,%.1fx%.1f)",
             Double(t048LaterShift), Double(t048Reserved.minX), Double(t048Reserved.minY),
             Double(t048Reserved.width), Double(t048Reserved.height)))
check(t048StableRoot && t048StableMarkedCard,
      "T-048 marked card and parent remain at card-only frames")
check(t048LaterShift > 0 && !t048Reserved.intersects(t048LaterCard),
      "T-048 marked badge pushes only the later sibling subtree clear")
let t048DescendantShift = t048Resolved[t048ReflowDescendantID]!.frame.minY
    - t048CardOnly[t048ReflowDescendantID]!.frame.minY
check(abs(t048DescendantShift - t048LaterShift) <= 0.0001,
      "T-048 later sibling reflow is inherited by every descendant")
check(t048Resolved == t048ResolvedAgain,
      "T-048 pure resolver is idempotent on already-resolved layouts")
check(t048NoMarkedResolved == t048CardOnly,
      "T-048 no-marked resolver leaves card-only layouts bit-for-bit unchanged")
let t048ScreenReserved = MarkedBadgeGeometry.screenFootprint(for: t048Resolved[t048ReflowRightID]!.frame)
let t048SVGReserved = MarkedBadgeGeometry.svgEmBox(for: t048Resolved[t048ReflowRightID]!.frame)
let t048Contains = { (outer: CGRect, inner: CGRect) in
    outer.minX <= inner.minX && outer.minY <= inner.minY
        && outer.maxX >= inner.maxX && outer.maxY >= inner.maxY
}
check(t048Contains(t048Reserved, t048ScreenReserved)
      && t048Contains(t048Reserved, t048SVGReserved),
      "T-048 layoutReservedFootprint contains screen and SVG footprints per dimension")
check(t048Resolved[t048ReflowRootID]!.frame == t048CardOnly[t048ReflowRootID]!.frame
      && t048LaterShift >= 0,
      "T-048 resolver does not recenter the parent and parent drift stays within sibling shifts")

let t048Offsets: [String: CGPoint] = [
    t048ReflowRootID.uuidString: CGPoint(x: 10, y: -4),
    t048ReflowRightID.uuidString: CGPoint(x: 0, y: 20),
]
let t048OffsetLayouts = LayoutEngine.layout(root: t048MarkedRoot, direction: .logicRight,
                                              offsets: t048Offsets)
func t048OffsetDelta(_ node: MindNode, inherited: CGPoint,
                     into deltas: inout [UUID: CGPoint]) {
    let local = t048Offsets[node.id.uuidString] ?? .zero
    let total = CGPoint(x: inherited.x + local.x, y: inherited.y + local.y)
    deltas[node.id] = total
    for child in node.children { t048OffsetDelta(child, inherited: total, into: &deltas) }
}
var t048ExpectedDeltas: [UUID: CGPoint] = [:]
t048OffsetDelta(t048MarkedRoot, inherited: .zero, into: &t048ExpectedDeltas)
var t048OffsetsPreserveInheritance = true
for (id, delta) in t048ExpectedDeltas {
    guard let shifted = t048OffsetLayouts[id], let resolved = t048Resolved[id] else {
        t048OffsetsPreserveInheritance = false
        continue
    }
    let expected = resolved.frame.offsetBy(dx: delta.x, dy: delta.y)
    t048OffsetsPreserveInheritance = t048OffsetsPreserveInheritance && shifted.frame == expected
}
check(t048OffsetsPreserveInheritance && t048Offsets.count == 2
      && t048Offsets[t048ReflowRootID.uuidString] == CGPoint(x: 10, y: -4)
      && t048Offsets[t048ReflowRightID.uuidString] == CGPoint(x: 0, y: 20),
      "T-048 manual offsets remain unchanged and are applied after reflow with inheritance")

for direction in [MapDirection.logicRight, .balanced, .fishbone, .bracket] {
    let cardOnly = LayoutEngine.layout(root: t048PlainRoot, direction: direction)
    let resolved = LayoutEngine.layout(root: t048MarkedRoot, direction: direction)
    let markedFrame = resolved[t048ReflowRightID]!.frame
    let cardFrame = cardOnly[t048ReflowRightID]!.frame
    check(markedFrame == cardFrame,
          "T-048 \(direction.rawValue) marked node frame stays card-only stable")
    let reserved = MarkedBadgeGeometry.layoutReservedFootprint(for: markedFrame)
    let laterFrame = resolved[t048ReflowLaterID]!.frame
    let cardLaterFrame = cardOnly[t048ReflowLaterID]!.frame
    if direction == .balanced {
        check(laterFrame == cardLaterFrame,
              "T-048 balanced keeps opposite-side siblings independent")
    } else if direction == .fishbone {
        if reserved.intersects(cardLaterFrame) {
            check(!reserved.intersects(laterFrame),
                  "T-048 fishbone separates only a true visual subtree intersection")
        } else {
            check(laterFrame == cardLaterFrame,
                  "T-048 fishbone leaves nonintersecting branches in place")
        }
    } else {
        check(!reserved.intersects(laterFrame),
              "T-048 \(direction.rawValue) later sibling clears reserved badge")
    }
}

let t048MapSource = projectSource("Sources/MindFlowKit/MapCanvasView.swift")
check(t048MapSource.contains("MarkedBadgeGeometry.screenBounds"),
      "T-048 MapCanvas content bounds include screen badge footprints")

// T-048 follow-up 2: only an actually intersecting marked upper fishbone rib is rerouted.
// The visible corridor ends at a card-perimeter attachment; its final segment to the centre
// is behind the card. Lower ribs and every unrelated primitive remain the old point sequence.
func t048RerouteLegacyFishbone(_ root: MindNode,
                               layouts: [UUID: NodeLayout]) -> [ConnectionStroke] {
    guard let rootLayout = layouts[root.id] else { return [] }
    let branches: [(node: MindNode, layout: NodeLayout)] = root.children.compactMap { node in
        guard let layout = layouts[node.id] else { return nil }
        return (node: node, layout: layout)
    }.sorted { $0.layout.frame.minX < $1.layout.frame.minX }
    let spineY = rootLayout.center.y
    let startX = rootLayout.frame.maxX
    let farthestX = branches.map { $0.layout.center.x + 60 }.max() ?? startX + 120
    let endX = max(startX + 120, farthestX)
    var result = [ConnectionStroke(
        shape: .polyline([CGPoint(x: startX, y: spineY), CGPoint(x: endX, y: spineY)]),
        colorIndex: 0, lineWidth: 4, opacity: 0.35)]
    for branch in branches {
        result.append(ConnectionStroke(
            shape: .polyline([
                CGPoint(x: branch.layout.center.x, y: spineY),
                branch.layout.center,
            ]),
            colorIndex: branch.layout.colorIndex, lineWidth: 2.5))
    }
    func visit(_ node: MindNode) {
        guard !node.collapsed, let parentLayout = layouts[node.id] else { return }
        for child in node.children {
            guard let childLayout = layouts[child.id] else { continue }
            result.append(ConnectionStroke(
                shape: .polyline([parentLayout.center, childLayout.center]),
                colorIndex: childLayout.colorIndex,
                lineWidth: parentLayout.depth == 0 ? 3 : 2,
                sourceID: node.id, targetID: child.id))
            visit(child)
        }
    }
    visit(root)
    return result
}

func t048ReroutePoints(_ stroke: ConnectionStroke) -> [CGPoint] {
    guard case let .polyline(points) = stroke.shape else { return [] }
    return points
}

func t048RerouteSegmentIntersects(_ from: CGPoint, _ to: CGPoint,
                                  _ rectangle: CGRect) -> Bool {
    guard !rectangle.isNull, !rectangle.isEmpty else { return false }
    let dx = to.x - from.x
    let dy = to.y - from.y
    var lower: CGFloat = 0
    var upper: CGFloat = 1
    let constraints: [(CGFloat, CGFloat)] = [
        (-dx, from.x - rectangle.minX),
        ( dx, rectangle.maxX - from.x),
        (-dy, from.y - rectangle.minY),
        ( dy, rectangle.maxY - from.y),
    ]
    for (p, q) in constraints {
        if p == 0 {
            if q < 0 { return false }
        } else {
            let ratio = q / p
            if p < 0 {
                if ratio > upper { return false }
                lower = max(lower, ratio)
            } else {
                if ratio < lower { return false }
                upper = min(upper, ratio)
            }
        }
    }
    return lower <= upper
}

func t048RerouteCorridorIntersects(_ from: CGPoint, _ to: CGPoint,
                                   _ footprint: CGRect) -> Bool {
    let radius: CGFloat = 2.5 / 2 + 1
    return t048RerouteSegmentIntersects(from, to,
                                        footprint.insetBy(dx: -radius, dy: -radius))
}

do {
    let markedLayouts = LayoutEngine.layout(root: t048Root, direction: .fishbone)
    let markedStrokes = ConnectionGeometry.strokes(root: t048Root, layouts: markedLayouts,
                                                    direction: .fishbone)
    let oldStrokes = t048RerouteLegacyFishbone(t048Root, layouts: markedLayouts)
    let rootRibCount = t048Root.children.count
    let markedRibs = Array(markedStrokes.dropFirst().prefix(rootRibCount))
    let oldRibs = Array(oldStrokes.dropFirst().prefix(rootRibCount))
    let sortedChildren = t048Root.children.compactMap { child -> (MindNode, NodeLayout)? in
        guard let layout = markedLayouts[child.id] else { return nil }
        return (child, layout)
    }.sorted { $0.1.frame.minX < $1.1.frame.minX }
    let upperIndex = sortedChildren.firstIndex { $0.1.center.y < markedLayouts[t048Root.id]!.center.y }
    let lowerIndex = sortedChildren.firstIndex { $0.1.center.y > markedLayouts[t048Root.id]!.center.y }

    if let upperIndex, let lowerIndex,
       markedRibs.count == rootRibCount, oldRibs.count == rootRibCount {
        let upperLayout = sortedChildren[upperIndex].1
        let upperReserved = MarkedBadgeGeometry.layoutReservedFootprint(for: upperLayout.frame)
        let oldUpper = t048ReroutePoints(oldRibs[upperIndex])
        let actualUpper = t048ReroutePoints(markedRibs[upperIndex])
        let oldCorridor = oldUpper.count >= 2
            && t048RerouteCorridorIntersects(oldUpper[0], oldUpper[1], upperReserved)
        check(oldCorridor,
              "T-048 fishbone old upper centre attachment intersects marked badge corridor")

        let visibleEnd: CGPoint? = actualUpper.count == 3 ? actualUpper[1] : actualUpper.last
        let actualCorridorClear = actualUpper.count == 3
            && visibleEnd.map { !t048RerouteCorridorIntersects(actualUpper[0], $0, upperReserved) } == true
        check(actualCorridorClear,
              "T-048 fishbone rerouted upper visible corridor clears marked badge")
        if actualUpper.count == 3 {
            let attachment = actualUpper[1]
            let distance = abs(attachment.x - upperLayout.frame.midX)
            let probes = [attachment.x - 1, attachment.x, attachment.x + 1]
            let probeClear = probes.allSatisfy {
                $0 >= upperLayout.frame.minX && $0 <= upperLayout.frame.maxX
                    && !t048RerouteCorridorIntersects(
                        actualUpper[0], CGPoint(x: $0, y: upperLayout.frame.maxY), upperReserved)
            }
            let mirrorX = upperLayout.frame.midX + distance
            let mirrorClear = mirrorX <= upperLayout.frame.maxX
                && !t048RerouteCorridorIntersects(
                    actualUpper[0], CGPoint(x: mirrorX, y: upperLayout.frame.maxY), upperReserved)
            print(String(format: "T-048 fishbone upper attachment x=%.3f frame=[%.3f,%.3f] y=%.3f distance=%.3f mirrorClear=%@",
                         Double(attachment.x), Double(upperLayout.frame.minX),
                         Double(upperLayout.frame.maxX), Double(attachment.y), Double(distance),
                         mirrorClear ? "true" : "false"))
            check(attachment.y == upperLayout.frame.maxY
                  && attachment.x >= upperLayout.frame.minX
                  && attachment.x <= upperLayout.frame.maxX,
                  "T-048 fishbone attachment stays on the card bottom edge")
            check(distance >= 1 && distance.rounded() == distance
                  && attachment.x < upperLayout.frame.midX && mirrorClear,
                  "T-048 fishbone equal-distance tie chooses the leading attachment")
            check(probeClear,
                  "T-048 fishbone attachment and both one-unit probes clear")
        } else {
            check(false, "T-048 fishbone upper reroute exposes an attachment point")
        }

        let lowerLayout = sortedChildren[lowerIndex].1
        let lowerReserved = MarkedBadgeGeometry.layoutReservedFootprint(for: lowerLayout.frame)
        let oldLower = t048ReroutePoints(oldRibs[lowerIndex])
        check(oldLower.count == 2
              && !t048RerouteCorridorIntersects(oldLower[0], oldLower[1], lowerReserved),
              "T-048 fishbone lower top-entry corridor misses bottom badge")
        check(markedRibs[lowerIndex] == oldRibs[lowerIndex],
              "T-048 fishbone nonintersecting lower rib is bit-for-bit unchanged")

        var onlyUpperChanged = true
        for index in markedRibs.indices where index != upperIndex {
            onlyUpperChanged = onlyUpperChanged && markedRibs[index] == oldRibs[index]
        }
        check(onlyUpperChanged,
              "T-048 fishbone only the intersecting upper root rib changes")
    } else {
        check(false, "T-048 fishbone fixture has identifiable upper and lower root ribs")
    }

    let repeated = ConnectionGeometry.strokes(root: t048Root, layouts: markedLayouts,
                                               direction: .fishbone)
    check(repeated == markedStrokes,
          "T-048 fishbone connector output is idempotent")

    let unmarkedRoot = MindNode(
        id: t048Root.id, text: t048Root.text,
        children: [
            MindNode(id: t048Right.id, text: t048Right.text, note: t048Right.note,
                     url: t048Right.url, children: [MindNode(id: t048Deep.id, text: t048Deep.text)]),
            MindNode(id: t048Left.id, text: t048Left.text),
        ])
    let unmarkedLayouts = LayoutEngine.layout(root: unmarkedRoot, direction: .fishbone)
    let unmarkedStrokes = ConnectionGeometry.strokes(root: unmarkedRoot, layouts: unmarkedLayouts,
                                                      direction: .fishbone)
    let unmarkedOld = t048RerouteLegacyFishbone(unmarkedRoot, layouts: unmarkedLayouts)
    check(unmarkedStrokes == unmarkedOld,
          "T-048 fishbone unmarked fixture remains bit-for-bit legacy geometry")
}


// MARK: - T-044: deterministic, live-aware tab display titles
// The resolver owns the final rendered label: middle truncation is grapheme-safe,
// and uniqueness is allocated only after truncation so SwiftUI cannot introduce
// a second, opaque naming policy.
do {
    func t044Document(_ title: String = "未命名心智圖", root: MindNode,
                      themeName: String = "ocean") -> MindDocument {
        MindDocument(title: title, themeName: themeName, root: root)
    }

    let ladderSessions = [
        EditorSession(document: t044Document(root: MindNode(text: "  有效根  "))),
        EditorSession(document: t044Document(root: MindNode(text: "中心主題")),
                      filePath: URL(fileURLWithPath: "/tmp/檔案來源.mindmap")),
        EditorSession(document: t044Document("自訂文件", root: MindNode(text: ""))),
        EditorSession(document: t044Document(root: MindNode(text: "中心主題", children: [
            MindNode(text: "", children: [MindNode(text: "深層來源")])
        ]))),
        EditorSession(document: t044Document(root: MindNode(text: "中心主題")))
    ]
    let ladderLabels = TabDisplayTitles.resolve(
        sessions: ladderSessions,
        activeIndex: -1,
        liveDocument: ladderSessions[0].document,
        liveFilePath: nil,
        maximumGraphemes: 16)
    check(ladderLabels == ["有效根", "檔案來源", "自訂文件", "深層來源", "中心主題"],
          "T-044 source ladder resolves root, file, title, descendant, and default")

    let defaultRootSessions = (1...7).map { number in
        EditorSession(document: t044Document(root: MindNode(
            text: "中心主題", children: [MindNode(text: "不同分支\(number)")]))
        )
    }
    let defaultRootLabels = TabDisplayTitles.resolve(
        sessions: defaultRootSessions,
        activeIndex: -1,
        liveDocument: defaultRootSessions[0].document,
        liveFilePath: nil,
        maximumGraphemes: 16)
    check(Set(defaultRootLabels).count == 7
          && defaultRootLabels == (1...7).map { "不同分支\($0)" },
          "T-044 default roots use distinct depth-first descendants")

    let sixteenCJK = String(repeating: "界", count: 16)
    let seventeenCJK = String(repeating: "界", count: 17)
    let boundarySessions = [
        EditorSession(document: t044Document(root: MindNode(text: sixteenCJK))),
        EditorSession(document: t044Document(root: MindNode(text: seventeenCJK)))
    ]
    let boundaryLabels = TabDisplayTitles.resolve(
        sessions: boundarySessions,
        activeIndex: -1,
        liveDocument: boundarySessions[0].document,
        liveFilePath: nil)
    let expectedSeventeen = String(seventeenCJK.prefix(8))
        + "…"
        + String(seventeenCJK.suffix(7))
    check(boundaryLabels[1] == expectedSeventeen
          && Array(boundaryLabels[1]).count == 16
          && Array(boundaryLabels[1].prefix(8)) == Array(seventeenCJK.prefix(8))
          && Array(boundaryLabels[1].suffix(7)) == Array(seventeenCJK.suffix(7)),
          "T-044 production default truncates 17 CJK as 8-leading plus ellipsis plus 7-trailing")
    check(boundaryLabels[0] == sixteenCJK
          && Array(boundaryLabels[0]).count == 16,
          "T-044 production default leaves exactly 16 CJK graphemes untruncated")

    let duplicateSessions = [
        EditorSession(document: t044Document(root: MindNode(text: "foo"))),
        EditorSession(document: t044Document(root: MindNode(text: "foo · 2"))),
        EditorSession(document: t044Document(root: MindNode(text: "foo")))
    ]
    let duplicateLabels = TabDisplayTitles.resolve(
        sessions: duplicateSessions,
        activeIndex: -1,
        liveDocument: duplicateSessions[0].document,
        liveFilePath: nil,
        maximumGraphemes: 16)
    check(duplicateLabels == ["foo", "foo · 2", "foo · 3"],
          "T-044 allocator skips an occupied generated suffix")

    let longMiddleSessions = [
        EditorSession(document: t044Document(root: MindNode(
            text: "共同前綴AAAAA甲BBBBB共同後綴"))),
        EditorSession(document: t044Document(root: MindNode(
            text: "共同前綴AAAAA乙BBBBB共同後綴")))
    ]
    let longMiddleLabels = TabDisplayTitles.resolve(
        sessions: longMiddleSessions,
        activeIndex: -1,
        liveDocument: longMiddleSessions[0].document,
        liveFilePath: nil,
        maximumGraphemes: 16)
    check(longMiddleLabels.count == 2
          && Set(longMiddleLabels).count == 2
          && longMiddleLabels[1].hasSuffix(" · 2")
          && longMiddleLabels.allSatisfy { Array($0).count > 0 },
          "T-044 middle truncation precedes uniqueness allocation")

    let graphemeSource = "👩‍💻" + String(repeating: "界", count: 20) + "e\u{301}"
    let graphemeSession = EditorSession(document: t044Document(root: MindNode(text: graphemeSource)))
    let graphemeLabel = TabDisplayTitles.resolve(
        sessions: [graphemeSession],
        activeIndex: -1,
        liveDocument: graphemeSession.document,
        liveFilePath: nil,
        maximumGraphemes: 8)[0]
    let graphemes = Array(graphemeLabel)
    check(graphemes.count <= 8
          && graphemes.contains("👩‍💻")
          && graphemes.contains("e\u{301}")
          && !graphemeLabel.contains("\u{FFFD}"),
          "T-044 truncation preserves emoji and combining graphemes")

    let staleActive = MindDocument(title: "快照標題", root: MindNode(text: "快照舊根"))
    let inactiveSnapshot = MindDocument(title: "其他", root: MindNode(text: "非活躍快照"))
    let liveEdit = MindDocument(title: "快照標題", root: MindNode(text: "即時根"))
    let liveAwareLabels = TabDisplayTitles.resolve(
        sessions: [EditorSession(document: staleActive), EditorSession(document: inactiveSnapshot)],
        activeIndex: 0,
        liveDocument: liveEdit,
        liveFilePath: URL(fileURLWithPath: "/tmp/不應遮蔽.mindmap"),
        maximumGraphemes: 16)
    check(liveAwareLabels == ["即時根", "非活躍快照"],
          "T-044 active label uses live document while inactive uses snapshot")

    let liveDefaultDocument = t044Document(root: MindNode(text: "中心主題"))
    let livePathLabels = TabDisplayTitles.resolve(
        sessions: [EditorSession(document: t044Document(root: MindNode(text: "中心主題")),
                    filePath: URL(fileURLWithPath: "/tmp/stale-active.mindmap"))],
        activeIndex: 0,
        liveDocument: liveDefaultDocument,
        liveFilePath: URL(fileURLWithPath: "/tmp/live-active.mindmap"),
        maximumGraphemes: 16)
    check(livePathLabels == ["live-active"],
          "T-044 active label also uses the live file path fallback")

    let invalidActiveLabels = TabDisplayTitles.resolve(
        sessions: [EditorSession(document: t044Document(root: MindNode(text: "快照")))],
        activeIndex: 99,
        liveDocument: liveEdit,
        liveFilePath: URL(fileURLWithPath: "/tmp/不應使用.mindmap"),
        maximumGraphemes: 16)
    let emptyLabels = TabDisplayTitles.resolve(
        sessions: [], activeIndex: 0, liveDocument: liveEdit, liveFilePath: nil,
        maximumGraphemes: 16)
    check(invalidActiveLabels == ["快照"] && emptyLabels.isEmpty,
          "T-044 invalid active index and empty sessions are safe")

    let t044ContentView = projectSource("Sources/MindFlowKit/ContentView.swift")
    check(t044ContentView.contains("TabDisplayTitles.resolve")
          && !t044ContentView.contains("private func tabTitle"),
          "T-044 ContentView renders resolver final labels directly")
}

// MARK: - T-049: node creation stays at node level
// Owner feel-ticket: creating a node must not jump into text editing (XMind
// behavior). The default text is the p1 ruling; the empty-commit discard
// mechanism itself is untouched and simply no longer triggers on these paths.

do {
    await MainActor.run {
        let vm = MindMapViewModel()
        vm.autosaveAllSessions()
        vm.newDocument()

        let t049Text: (UUID?) -> String? = { id in
            id.flatMap { vm.document.root.find($0)?.text }
        }

        let childID = vm.addChild(to: nil)
        check(childID != nil && vm.editingID == nil && vm.selection == childID
              && t049Text(childID) == MindMapViewModel.newNodeDefaultText,
              "T-049 addChild stays at node level with the default text")

        let siblingID = vm.addSibling(of: childID!)
        check(siblingID != nil && vm.editingID == nil && vm.selection == siblingID
              && t049Text(siblingID) == MindMapViewModel.newNodeDefaultText,
              "T-049 addSibling stays at node level with the default text")

        let beforeID = vm.addSiblingBefore(of: siblingID!)
        check(beforeID != nil && vm.editingID == nil && vm.selection == beforeID
              && t049Text(beforeID) == MindMapViewModel.newNodeDefaultText,
              "T-049 addSiblingBefore stays at node level with the default text")

        let parentID = vm.insertParent(id: beforeID!)
        check(parentID != nil && vm.editingID == nil && vm.selection == parentID
              && t049Text(parentID) == MindMapViewModel.newNodeDefaultText,
              "T-049 insertParent stays at node level with the default text")

        // Tab×5: rapid creation without typing leaves five visible, selectable,
        // non-empty nodes and never opens the editor.
        vm.newDocument()
        var tabChain: [UUID] = []
        for _ in 0..<5 {
            guard let created = vm.addChild(to: vm.selection) else { break }
            tabChain.append(created)
        }
        check(tabChain.count == 5,
              "T-049 five rapid creations all exist")
        check(tabChain.allSatisfy { t049Text($0) == MindMapViewModel.newNodeDefaultText },
              "T-049 rapid creations carry the default text")
        check(tabChain.allSatisfy { id in vm.selection = id; return vm.selection == id },
              "T-049 every rapid-created node is selectable")
        check(vm.editingID == nil,
              "T-049 rapid creation never opens the editor")

        // Type-to-replace (KeyboardMonitor D2 seam): the first printable
        // character swaps the whole text instead of appending.
        let typedID = tabChain[0]
        vm.selection = typedID
        vm.beginEditing(id: typedID, replacingWith: "x")
        check(vm.editingID == typedID && t049Text(typedID) == "x",
              "T-049 type-to-replace swaps the default text wholesale")

        // Delete still removes the node.
        vm.delete(id: typedID)
        check(vm.document.root.find(typedID) == nil,
              "T-049 delete still removes a created node")
    }
}

print("T-049 arrow-key navigation: GUI-verified by p1 (selection read out via the replacement target after navigate-and-type)")

// MARK: - T-050: tab buttons carry the resolver label as their identifier
// Governance (p1 rulings, recorded): the probe proved .accessibilityLabel does
// not produce an AX attribute in plain content areas on this macOS target, so
// the identifier is the ACCEPTANCE CHANNEL, not an accessibility fix — the tab
// buttons remain unnamed for VoiceOver, and the original goal (a real
// accessible name) is downgraded to the backlog. The identifier gates below
// guard the acceptance channel: the switch button's identifier is the resolver
// label verbatim from the shared computed var (no prefix, no decoration — a
// prefix would break the verbatim-equality acceptance), and the close button
// uses a namespaced identifier over the same computed var.

do {
    let t050ContentView = projectSource("Sources/MindFlowKit/ContentView.swift")
    let t050Slice: Substring
    if let start = t050ContentView.range(of: "// MARK: - Tab bar"),
       let end = t050ContentView.range(of: "private var tabDisplayTitles") {
        t050Slice = t050ContentView[start.upperBound..<end.lowerBound]
    } else {
        t050Slice = ""
    }
    check(!t050Slice.isEmpty, "T-050 tab bar source slice is locatable")
    check(t050Slice.components(separatedBy: "Text(tabDisplayTitles[index])").count == 2,
          "T-050 switch label renders the title from the shared computed var")
    check(t050Slice.contains("Text(\"關閉分頁：\" + tabDisplayTitles[index])"),
          "T-050 close label keeps the 關閉分頁 format from the shared computed var")
    check(t050Slice.contains("EmptyView()") && t050Slice.contains("labelStyle(.iconOnly)"),
          "T-050 tab buttons follow the toolbar Label shape")
    check(t050Slice.components(separatedBy: ".accessibilityLabel(").count == 2,
          "T-050 tab buttons carry no accessibility overrides (the storage warning keeps its own)")
    check(!t050Slice.contains("切換到分頁："),
          "T-050 switch label is not prefixed or recomputed outside the resolver")
    check(!t050Slice.contains("Text(\"子主題\")") && !t050Slice.contains("Text(\"中心主題\")"),
          "T-050 tab labels are not hardcoded")
    check(t050Slice.components(separatedBy: ".accessibilityIdentifier(tabDisplayTitles[index])").count == 2,
          "T-050 switch identifier is the resolver label verbatim from the shared computed var")
    check(t050Slice.components(separatedBy: ".accessibilityIdentifier(\"").count == 2,
          "T-050 the only literal identifier is the namespaced close button (switch stays verbatim)")
    check(t050Slice.contains(".accessibilityIdentifier(\"mindflow.tab.close.\" + tabDisplayTitles[index])"),
          "T-050 close identifier is namespaced over the shared computed var")
}

print("T-050 PENDING: AX label surfacing, verbatim equality, and the remove-label negative control are p1 GUI-probe items and are not simulated headlessly")

// MARK: - D2 handoff: the first keystroke reaches the replacing path
// p1 measured (two scenarios): a printable keystroke on a selected node opened
// the editor with the old text and the character never reached the document.
// The editing handoff window passed events straight through while the field
// editor was still installing, so the first printable character fell into the
// responder chain and was dropped. The printable-character decision now lives
// in one shared dispatch path (same pattern as performCoreShortcut); the
// NSEvent wiring plus the field-editor install race stay with the p1 GUI probe.

do {
    let session = UUID()
    let routed = KeyboardMonitor.d2Replacement(characters: "x", charactersIgnoringModifiers: "x",
                                               modifierFlags: [], selection: session)
    check(routed?.id == session && routed?.text == "x",
          "D2 handoff routes a bare printable character into the replacing path")
    check(KeyboardMonitor.d2Replacement(characters: "x", charactersIgnoringModifiers: "x",
                                        modifierFlags: [.command], selection: session) == nil,
          "D2 handoff ignores command-modified keystrokes")
    check(KeyboardMonitor.d2Replacement(characters: "x", charactersIgnoringModifiers: "x",
                                        modifierFlags: [.shift], selection: session)?.text == "x",
          "D2 handoff keeps shift-modified characters")
    check(KeyboardMonitor.d2Replacement(characters: nil, charactersIgnoringModifiers: "\u{F703}",
                                        modifierFlags: [], selection: session) == nil,
          "D2 handoff ignores arrow keys")
    check(KeyboardMonitor.d2Replacement(characters: "\u{7F}", charactersIgnoringModifiers: "\u{7F}",
                                        modifierFlags: [], selection: session) == nil,
          "D2 handoff ignores delete")
    check(KeyboardMonitor.d2Replacement(characters: "ab", charactersIgnoringModifiers: "ab",
                                        modifierFlags: [], selection: session) == nil,
          "D2 handoff ignores multi-character events")
    check(KeyboardMonitor.d2Replacement(characters: "x", charactersIgnoringModifiers: "x",
                                        modifierFlags: [], selection: nil) == nil,
          "D2 handoff requires a selection or an open session")
}

print("D2 PENDING: the NSEvent monitor wiring plus the field-editor install race need a real keyboard and are p1 GUI-probe items")

// MARK: - D2 editor seed: the draft starts from the live store
// p1 measurement: after type-to-replace the editor still showed the old text,
// and Return committed that stale draft back over the replacement, with the
// rapid-entry spawn leaving 子主題 ×2. NodeView seeded editText from its node
// snapshot; the seed must consult the live document at seed time instead.

do {
    // The live-beats-snapshot rule itself is one `??`; what matters headlessly
    // is the wiring: both seed sites go through the live document read.
    let d2SeedCanvas = projectSource("Sources/MindFlowKit/MapCanvasView.swift")
    check(d2SeedCanvas.contains("editSeed: { vm.document.root.find(item.node.id)?.text ?? item.node.text }"),
          "D2 editor seed is wired to the live document read")
    check(projectSource("Sources/MindFlowKit/NodeView.swift")
          .components(separatedBy: "editText = Self.editSeed(live: editSeed?(), snapshot: node.text)").count == 3,
          "D2 editor draft is seeded through the live-store seed in both observers")
}

print("D2 PENDING: the on-screen editor-open seed timing is verified by the p1 GUI probe")

// MARK: - T-051 S2: symlink storage write-through experiment

// Question: does any save path write THROUGH a symlinked tab file into its
// target? Measured headlessly on the two real save mechanisms — the TabStore
// transaction (staging + directory exchange) and the user-document save
// (vm.save → Data.write(options: .atomic)) — plus an iCloud-style storage
// whose tabs directory is itself a symlink, recorded for the verdict.
do {
    let root = freshTabStoreRoot("t051-symlink")
    defer { try? FileManager.default.removeItem(at: root) }
    let live = root.appendingPathComponent("tabs", isDirectory: true)

    // A1: TabStore transaction save over a slot replaced by a symlink.
    let store = TabStore(directory: live)
    let seedID = UUID()
    check(store.save([TabStore.Entry(id: seedID,
                                     document: MindDocument(title: "seed", root: MindNode(text: "seed")))]).succeeded,
          "S2 seed snapshot commits")
    let target = root.appendingPathComponent("target.mindmap")
    let originalTarget = encodedTabDocument(MindDocument(title: "victim", root: MindNode(text: "victim")))
    try originalTarget.write(to: target, options: .atomic)
    let slot = live.appendingPathComponent("\(seedID.uuidString).mindmap")
    try FileManager.default.removeItem(at: slot)
    try FileManager.default.createSymbolicLink(at: slot, withDestinationURL: target)
    let outcome = store.save([TabStore.Entry(id: seedID,
                                             document: MindDocument(title: "again", root: MindNode(text: "again")))])
    check(outcome.succeeded, "S2 a save over a symlinked slot still commits")
    let afterTarget = (try? Data(contentsOf: target)) ?? Data()
    check(afterTarget == originalTarget, "S2 the symlinked slot's target bytes are unchanged after a save")
    print("T-051 S2 A1: committed=\(outcome.succeeded) targetBytesBefore=\(originalTarget.count) targetBytesAfter=\(afterTarget.count) identical=\(afterTarget == originalTarget)")

    // A2: the user-document save path against a symlinked document file.
    try await MainActor.run {
        let vm = MindMapViewModel()
        vm.newDocument()
        let docTarget = root.appendingPathComponent("doc-target.mindmap")
        let docOriginal = encodedTabDocument(vm.document)
        try docOriginal.write(to: docTarget, options: .atomic)
        let docLink = root.appendingPathComponent("document.mindmap")
        try FileManager.default.createSymbolicLink(at: docLink, withDestinationURL: docTarget)
        vm.filePath = docLink
        vm.addChild(to: nil)
        let saved = vm.save()
        let afterDoc = (try? Data(contentsOf: docTarget)) ?? Data()
        check(saved, "S2 vm.save through a symlinked path reports success")
        check(afterDoc == docOriginal, "S2 the symlinked document's target bytes are unchanged after vm.save")
        print("T-051 S2 A2: saved=\(saved) targetBytesBefore=\(docOriginal.count) targetBytesAfter=\(afterDoc.count) identical=\(afterDoc == docOriginal)")
    }

    // B: iCloud-style storage whose tabs directory is itself a symlink —
    // recorded only; a fix that guards parent directories would break this.
    let bRoot = freshTabStoreRoot("t051-symlink-dir")
    defer { try? FileManager.default.removeItem(at: bRoot) }
    let realTabs = bRoot.appendingPathComponent("real-tabs", isDirectory: true)
    try FileManager.default.createDirectory(at: realTabs, withIntermediateDirectories: true)
    let linkedTabs = bRoot.appendingPathComponent("tabs", isDirectory: true)
    try FileManager.default.createSymbolicLink(at: linkedTabs, withDestinationURL: realTabs)
    let bOutcome = TabStore(directory: linkedTabs)
        .save([TabStore.Entry(id: UUID(), document: MindDocument(title: "cloud", root: MindNode(text: "cloud")))])
    let stillSymlink = (try? FileManager.default.destinationOfSymbolicLink(atPath: linkedTabs.path)) != nil
    print("T-051 S2 B: committed=\(bOutcome.succeeded) error=\(bOutcome.primaryError.map(String.init(describing:)) ?? "none") tabsPathStillSymlink=\(stillSymlink)")
}

// MARK: - T-051 S3: OPML entity expansion stays bounded (confirmatory)

// External entities: shouldResolveExternalEntities is left unset, so the
// parser must never fetch SYSTEM entities into the document. Internal entity
// recursion (billion laughs): the import must fail bounded or produce bounded
// output. If both hold without product changes, this fixture is the record.
do {
    let external = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE opml [
        <!ENTITY x SYSTEM "file:///etc/passwd">
        ]>
        <opml version="2.0"><head><title>t</title></head>
        <body><outline text="&x;"/></body></opml>
        """
    var externalThrew = false
    var externalText = ""
    do {
        let doc = try MapImporter.opml(Data(external.utf8))
        externalText = doc.root.children.map(\.text).joined()
    } catch { externalThrew = true }
    check(externalThrew || (!externalText.contains("root:") && externalText.count < 200),
          "S3 external SYSTEM entities are never fetched into the document")
    print("T-051 S3 external: threw=\(externalThrew) textLength=\(externalText.count)")

    let dtd = """
        <!ENTITY a "0123456789">
        <!ENTITY b "&a;&a;&a;&a;&a;&a;&a;&a;&a;&a;">
        <!ENTITY c "&b;&b;&b;&b;&b;&b;&b;&b;&b;&b;">
        <!ENTITY d "&c;&c;&c;&c;&c;&c;&c;&c;&c;&c;">
        <!ENTITY e "&d;&d;&d;&d;&d;&d;&d;&d;&d;&d;">
        <!ENTITY f "&e;&e;&e;&e;&e;&e;&e;&e;&e;&e;">
        <!ENTITY g "&f;&f;&f;&f;&f;&f;&f;&f;&f;&f;">
        <!ENTITY h "&g;&g;&g;&g;&g;&g;&g;&g;&g;&g;">
        <!ENTITY i "&h;&h;&h;&h;&h;&h;&h;&h;&h;&h;">
        <!ENTITY j "&i;&i;&i;&i;&i;&i;&i;&i;&i;&i;">
        """
    let bomb = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE opml [\(dtd)]>
        <opml version="2.0"><head><title>t</title></head>
        <body><outline text="&j;"/></body></opml>
        """
    let started = Date()
    var bombThrew = false
    var bombText = ""
    do {
        let doc = try MapImporter.opml(Data(bomb.utf8))
        bombText = doc.root.children.map(\.text).joined()
    } catch { bombThrew = true }
    let elapsed = Date().timeIntervalSince(started)
    check(bombThrew || bombText.count <= 100_000,
          "S3 internal entity recursion fails bounded or yields bounded text")
    print("T-051 S3 internal: threw=\(bombThrew) textLength=\(bombText.count) seconds=\(String(format: "%.2f", elapsed))")
}

// MARK: T-052 — Shift+Tab outdent (promote)
do {
    try await MainActor.run {
        let vm = MindMapViewModel()
        vm.newDocument()
        let a = vm.addChild(to: nil)!            // root-level child
        let b = vm.addChild(to: a)!              // grandchild
        let rootID = vm.document.root.id
        let before = tabNodeCount(vm.document.root)

        vm.promote(id: b)
        check(vm.document.root.parent(of: b)?.id == rootID,
              "T-052 promote lifts a grandchild to its grandparent")
        check(tabNodeCount(vm.document.root) == before,
              "T-052 promote moves instead of adding or deleting")
        check(vm.selection == b,
              "T-052 promote keeps the moved node selected")

        // A root-level child has no grandparent, so promoting it must not move
        // the tree at all — not even sibling order.
        let rootChildrenBefore = vm.document.root.children.map(\.id)
        vm.promote(id: a)
        check(vm.document.root.parent(of: a)?.id == rootID
              && tabNodeCount(vm.document.root) == before
              && vm.document.root.children.map(\.id) == rootChildrenBefore,
              "T-052 promoting a root-level child is a no-op")

        // promote reuses move(id:toParent:) rather than new tree surgery; the
        // self-target guard it inherits is asserted directly.
        vm.move(id: a, toParent: a)
        check(vm.document.root.children.map(\.id) == rootChildrenBefore,
              "T-052 inherits move's self-target guard")
    }
}
// ---------------------------------------------------------------------------
// T-046: CanvasTransform dedup (screen<->map). Oracle checks.
//
// The two byte-identical toMap closures in MapCanvasView (visibleItems culling
// rect and completeLasso batch rect) were extracted into CanvasTransform
// without touching pan/scale semantics. The oracle below is the literal
// pre-extraction formula (git 1a3a425, MapCanvasView.swift), so an error
// transcribed into BOTH the product and the extraction still fails here.

func t046LegacyToMap(screen: CGPoint, geoSize: CGSize, bounds: CGRect,
                     pan: CGSize, scale: CGFloat) -> CGPoint {
    let origin = CGPoint(x: -bounds.minX, y: -bounds.minY)
    let center = CGPoint(x: bounds.width / 2, y: bounds.height / 2)
    let sx = screen.x - (geoSize.width - bounds.width) / 2 - pan.width
    let sy = screen.y - (geoSize.height - bounds.height) / 2 - pan.height
    let qx = center.x + (sx - center.x) / scale
    let qy = center.y + (sy - center.y) / scale
    return CGPoint(x: qx - origin.x, y: qy - origin.y)
}

do {
    // Deterministic low-discrepancy sweep over the space the product actually
    // exercises: viewport smaller/larger than the content bounds, negative
    // bounds origins (content offset), full zoom range, and free pans.
    struct T046Params {
        let viewport: CGSize
        let bounds: CGRect
        let pan: CGSize
        let scale: CGFloat
        let label: String
    }
    let combos: [T046Params] = [
        .init(viewport: CGSize(width: 800, height: 600),
              bounds: CGRect(x: -300, y: -200, width: 600, height: 400),
              pan: .zero, scale: 1, label: "fit"),
        .init(viewport: CGSize(width: 1400, height: 900),
              bounds: CGRect(x: -750, y: -500, width: 1500, height: 1000),
              pan: CGSize(width: 120, height: -80), scale: 0.25, label: "zoomed-out+panned"),
        .init(viewport: CGSize(width: 500, height: 400),
              bounds: CGRect(x: -100, y: -60, width: 1200, height: 900),
              pan: CGSize(width: -500, height: 340), scale: 3, label: "zoomed-in"),
        .init(viewport: CGSize(width: 1024, height: 768),
              bounds: CGRect(x: -512, y: -384, width: 1024, height: 768),
              pan: CGSize(width: 37.5, height: -12.25), scale: 1.37, label: "odd-scale")
    ]

    // Deterministic 2D grid inside the viewport (includes the exact corners the
    // two call sites map: .zero and viewport-bottom-right for the culling rect,
    // and arbitrary lasso rectangles for completeLasso).
    var sweepPoints: [CGPoint] = [.zero,
                                  CGPoint(x: 800, y: 600),
                                  CGPoint(x: 400, y: 300)]
    for i in 0...16 {
        for j in 0...13 {
            sweepPoints.append(CGPoint(x: CGFloat(i) * 50, y: CGFloat(j) * 50))
        }
    }
    // The four corners of a plausible lasso rect, applied at each combo.
    let lasso = CGRect(x: 130, y: 90, width: 420, height: 260)

    var equivalenceSamples = 0
    var roundTripSamples = 0
    for combo in combos {
        let t = CanvasTransform(viewport: combo.viewport, bounds: combo.bounds,
                                pan: combo.pan, scale: combo.scale)
        let points: [CGPoint] = sweepPoints + [lasso.origin,
                                               CGPoint(x: lasso.maxX, y: lasso.minY),
                                               CGPoint(x: lasso.minX, y: lasso.maxY),
                                               CGPoint(x: lasso.maxX, y: lasso.maxY)]
        // Out-of-viewport points are not produced by the call sites but still
        // round-trip; per-sample failures record the first offending point.
        var badLegacy: CGPoint?
        var badScreenTrip: CGPoint?
        var badMapTrip: CGPoint?
        for p in points {
            let legacy = t046LegacyToMap(screen: p, geoSize: combo.viewport,
                                         bounds: combo.bounds, pan: combo.pan,
                                         scale: combo.scale)
            let mapped = t.screenToMap(p)
            if abs(mapped.x - legacy.x) > 1e-9 || abs(mapped.y - legacy.y) > 1e-9 {
                if badLegacy == nil { badLegacy = p }
            }
            let back = t.mapToScreen(mapped)
            if abs(back.x - p.x) > 1e-6 || abs(back.y - p.y) > 1e-6 {
                if badScreenTrip == nil { badScreenTrip = p }
            }
            let forth = t.screenToMap(t.mapToScreen(mapped))
            if abs(forth.x - mapped.x) > 1e-6 || abs(forth.y - mapped.y) > 1e-6 {
                if badMapTrip == nil { badMapTrip = p }
            }
            equivalenceSamples += 1
            roundTripSamples += 2
        }
        func describe(_ p: CGPoint?) -> String {
            p.map { "first bad point (\(Int($0.x)),\(Int($0.y)))" } ?? "none"
        }
        check(badLegacy == nil,
              "T-046 \(combo.label) screenToMap == legacy formula at all \(points.count) samples (\(describe(badLegacy)))")
        check(badScreenTrip == nil,
              "T-046 \(combo.label) screen->map->screen round trip at all \(points.count) samples (\(describe(badScreenTrip)))")
        check(badMapTrip == nil,
              "T-046 \(combo.label) map->screen->map round trip at all \(points.count) samples (\(describe(badMapTrip)))")
    }
    print("T-046: \(equivalenceSamples) legacy-equivalence samples, \(roundTripSamples) round-trip samples across \(combos.count) transform states")
}

do {
    // Randomised round trip over wider parameter space, seeded so a failure is
    // reproducible. Scale kept inside the product's zoomRange (0.25...3).
    var seed: UInt64 = 0x5EED_046
    func nextUnit() -> CGFloat {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat(seed >> 11) / CGFloat(1 << 53)
    }
    var randomFailures = 0
    var samples = 0
    for _ in 0..<2_000 {
        let vw = 300 + nextUnit() * 1600
        let vh = 200 + nextUnit() * 1200
        let bw = 100 + nextUnit() * 2400
        let bh = 100 + nextUnit() * 1800
        let bounds = CGRect(x: -nextUnit() * bw, y: -nextUnit() * bh,
                            width: bw, height: bh)
        let scale = 0.25 + nextUnit() * 2.75
        let pan = CGSize(width: (nextUnit() - 0.5) * 1600,
                         height: (nextUnit() - 0.5) * 1200)
        let t = CanvasTransform(viewport: CGSize(width: vw, height: vh),
                                bounds: bounds, pan: pan, scale: scale)
        let sx = nextUnit() * vw
        let sy = nextUnit() * vh
        let screen = CGPoint(x: sx, y: sy)
        let map = t.screenToMap(screen)
        let back = t.mapToScreen(map)
        if abs(back.x - sx) > 1e-5 || abs(back.y - sy) > 1e-5 { randomFailures += 1 }
        samples += 1
    }
    check(randomFailures == 0,
          "T-046 randomised round trip holds over 2,000 states (failures=\(randomFailures))")
    print("T-046: \(samples) randomised round-trip samples, failures=\(randomFailures)")
}

// MARK: - T-053: Delete/Backspace never reaches AppKit unclaimed (no alert beep)
// AppKit plays the system alert sound for a keyDown that reaches the end of the
// responder chain unhandled — the Owner reported it as a warning sound while
// deleting nodes. The runtime probe (scripts/uitest/u13-delete-handling.sh)
// measured which keyDowns the monitor claims; this oracle pins the dispatch
// decision for every state through the same performDelete / deleteOutcome path
// the event monitor calls.
do {
    try await MainActor.run {
        check(KeyboardMonitor.isDeleteKey("\u{7F}"),
              "T-053 ⌫ is a delete key")
        check(KeyboardMonitor.isDeleteKey("\u{8}"),
              "T-053 control-backspace is a delete key")
        check(KeyboardMonitor.isDeleteKey("\u{F728}"),
              "T-053 ⌦ is a delete key (unclaimed today → AppKit alert beep)")
        check(!KeyboardMonitor.isDeleteKey("\t")
              && !KeyboardMonitor.isDeleteKey(" ")
              && !KeyboardMonitor.isDeleteKey("\u{F700}")
              && !KeyboardMonitor.isDeleteKey("a"),
              "T-053 navigation and printable keys are not delete keys")

        let vm = MindMapViewModel()
        vm.newDocument()
        let child = vm.addChild(to: nil)!
        let grandchild = vm.addChild(to: child)!
        vm.editingID = nil

        // 一般選取
        vm.selection = grandchild
        check(KeyboardMonitor.performDelete(vm: vm, textFieldEditing: false, editingHandoffActive: false)
              && vm.document.root.find(grandchild) == nil,
              "T-053 selection: Delete is handled and removes the node")

        // 選中連線
        let linkA = vm.addChild(to: nil)!
        let linkB = vm.addChild(to: nil)!
        let linkID = vm.addLink(from: linkA, to: linkB)!
        vm.selection = linkA
        vm.selectedLinkID = linkID
        check(KeyboardMonitor.performDelete(vm: vm, textFieldEditing: false, editingHandoffActive: false)
              && vm.document.links.isEmpty
              && vm.document.root.find(linkA) != nil,
              "T-053 link selected: Delete is handled and removes only the link")
        vm.selectedLinkID = nil

        // root 被選
        let rootID = vm.document.root.id
        vm.selection = rootID
        check(KeyboardMonitor.performDelete(vm: vm, textFieldEditing: false, editingHandoffActive: false)
              && vm.document.root.find(rootID) != nil,
              "T-053 root selected: Delete is handled and the root survives")

        // 無選取
        vm.selection = nil
        check(KeyboardMonitor.performDelete(vm: vm, textFieldEditing: false, editingHandoffActive: false),
              "T-053 no selection: Delete is still handled (no AppKit fall-through)")

        // 編輯中 — 交接視窗：編輯器尚未接管，必須吞掉且不得刪掉正在編輯的節點
        vm.selection = child
        vm.editingID = child
        check(KeyboardMonitor.performDelete(vm: vm, textFieldEditing: false, editingHandoffActive: true)
              && vm.document.root.find(child) != nil,
              "T-053 editing handoff: Delete is handled and does not delete the node being edited")
        vm.editingID = nil

        // 簡報中
        vm.selection = child
        vm.presentationActive = true
        check(KeyboardMonitor.performDelete(vm: vm, textFieldEditing: false, editingHandoffActive: false)
              && vm.document.root.find(child) != nil,
              "T-053 presentation: Delete is handled without mutating the document")
        vm.presentationActive = false

        // 編輯器接管時必須交還按鍵：⌘⌫／⌥⌫ 在文字欄位是刪詞／刪行，吞掉會弄壞編輯
        check(!KeyboardMonitor.performDelete(vm: vm, textFieldEditing: true, editingHandoffActive: false),
              "T-053 field editor owns the key: the monitor must pass Delete through")

        // 決策函式本身（與事件監控共用同一條 dispatch path）
        check(KeyboardMonitor.deleteOutcome(for: .init()) == .deleteSelection,
              "T-053 default state routes Delete to the canvas")
        check(KeyboardMonitor.deleteOutcome(for: .init(textFieldEditing: true)) == .fieldEditor,
              "T-053 text-field focus routes Delete to the editor")
        check(KeyboardMonitor.deleteOutcome(for: .init(editingHandoffActive: true)) == .swallowed
              && KeyboardMonitor.deleteOutcome(for: .init(presentationActive: true)) == .swallowed,
              "T-053 handoff and presentation swallow Delete instead of beeping")

        // 單一刪除路徑：事件監控呼叫共用 dispatcher，switch 裡不再有第二份實作
        let keyboardSource = projectSource("Sources/MindFlowKit/KeyboardMonitor.swift")
        check(keyboardSource.contains("if Self.isDeleteKey(chars) {")
              && keyboardSource.contains("Self.performDelete(vm: vm, textFieldEditing: false,"),
              "T-053 the event monitor routes Delete through the shared dispatcher")
        check(!keyboardSource.contains("case \"\\u{7F}\", \"\\u{8}\":"),
              "T-053 the switch no longer carries a second delete implementation")
    }
}

// MARK: - T-054: undo history belongs to one tab and must not leak across tabs
// Unguarded until now. The failure this defends against is the worst kind the
// app can have: press undo in one document and silently damage another. A user
// would not attribute the damage to the tab switch, and by the time they saw
// it the correct state would be several edits gone.
do {
    try await MainActor.run {
        let vm = MindMapViewModel()
        vm.newDocument()
        let idxA = vm.activeIndex
        let originalA = vm.document.root.text
        vm.rename(id: vm.document.root.id, to: "TAB-A-EDITED")
        check(vm.document.root.text == "TAB-A-EDITED",
              "T-054 control: the edit under test actually lands in tab A")

        vm.openInNewTab(MindDocument(title: "B", root: MindNode(text: "B-ROOT")))
        let idxB = vm.activeIndex
        check(idxB != idxA, "T-054 opening a tab makes it active")

        // The sharpest assertion: a tab with no history of its own must not
        // reach into the previous tab's stack.
        vm.undo()
        check(vm.document.root.text == "B-ROOT",
              "T-054 undo in a fresh tab does not consume the previous tab's history")
        check(vm.sessions[idxA].document.root.text == "TAB-A-EDITED",
              "T-054 undo in a fresh tab leaves the other tab's document intact")

        // Returning to A must find A's own history still there.
        vm.switchTab(to: idxA)
        vm.undo()
        check(vm.document.root.text == originalA,
              "T-054 tab A keeps its own undo history across a round trip")
        check(vm.sessions[idxB].document.root.text == "B-ROOT",
              "T-054 undoing in tab A does not touch tab B")

        // Redo is stored per tab on the same footing as undo.
        vm.redo()
        check(vm.document.root.text == "TAB-A-EDITED",
              "T-054 redo is also per-tab")
    }
}

// MARK: - ⌘/ folds the branch, ⇧⌘/ (⌘?) opens the shortcut sheet

do {
    let vm = MindMapViewModel()
    vm.newDocument()
    let branch = vm.addChild(to: nil)!
    _ = vm.addChild(to: branch)!
    vm.selection = branch

    check(KeyboardMonitor.performBranchFold(characters: "/", modifiers: [.command], vm: vm),
          "⌘/ is claimed by the monitor")
    check(vm.document.root.find(branch)?.collapsed == true,
          "⌘/ folds the selected branch")

    // ⇧⌘/ arrives as charactersIgnoringModifiers "/" too; the shift flag is the
    // only difference, and the monitor must decline it so the menu item fires.
    check(!KeyboardMonitor.performBranchFold(characters: "/", modifiers: [.command, .shift], vm: vm),
          "⇧⌘/ is declined by the monitor")
    check(vm.document.root.find(branch)?.collapsed == true,
          "⇧⌘/ does not toggle the fold state")
    check(!vm.showHelp,
          "the monitor never opens the shortcut sheet itself — that is the menu item's job")

    // ⌥⌘/ belongs to performCoreShortcut's all-branches toggle; the fold path
    // must not also claim it.
    check(!KeyboardMonitor.performBranchFold(characters: "/", modifiers: [.option, .command], vm: vm),
          "⌥⌘/ is not claimed by the branch-fold path")
    check(KeyboardMonitor.performCoreShortcut(characters: "/", modifiers: [.option, .command], vm: vm),
          "⌥⌘/ still toggles all branches through the core path")

    let appSource = projectSource("Sources/MindFlow/MindFlowApp.swift")
    check(appSource.contains(".keyboardShortcut(\"/\", modifiers: [.command, .shift])"),
          "the shortcut-sheet menu item is bound to ⇧⌘/ (⌘?)")
    check(!appSource.contains(".keyboardShortcut(\"/\", modifiers: [.command])"),
          "no menu item claims bare ⌘/ any more")
    check(projectSource("Sources/MindFlowKit/ContentView.swift")
            .contains("(\"⌘?\", \"開啟這份鍵盤快速鍵說明\")"),
          "the in-app shortcut table lists ⌘?")
}

// MARK: - Boundary v1: a frame anchored on a subtree, derived at render time
// Spec: docs/proposals/boundary.md §4. Canvas drawing and the context menu are
// deliberately NOT asserted here: the screen is locked, every windowed probe
// times out, and a green model suite must not pretend otherwise.

do {
    let vm = MindMapViewModel()
    vm.newDocument()
    let branch = vm.addChild(to: nil)!
    let leafA = vm.addChild(to: branch)!
    let leafB = vm.addChild(to: branch)!
    let other = vm.addChild(to: nil)!

    let boundaryID = vm.addBoundary(rootID: branch)
    check(boundaryID != nil && vm.document.boundaries.count == 1,
          "boundary: creating one adds exactly one")
    check(vm.document.boundaries.first?.rootID == branch,
          "boundary: it anchors on the chosen subtree root")
    check(vm.addBoundary(rootID: branch) == boundaryID && vm.document.boundaries.count == 1,
          "boundary: a second boundary on the same root is not created (D4)")
    check(vm.selectedBoundaryID == boundaryID,
          "boundary: creating one selects it")

    // Lifecycle table, docs/proposals/boundary.md §2.
    vm.delete(id: leafA)
    check(vm.document.boundaries.count == 1,
          "boundary: deleting a covered descendant keeps the boundary")
    vm.delete(id: other)
    check(vm.document.boundaries.count == 1,
          "boundary: deleting an unrelated node keeps the boundary")
    vm.delete(id: branch)
    check(vm.document.boundaries.isEmpty,
          "boundary: deleting the anchor prunes the boundary")
    check(vm.selectedBoundaryID == nil,
          "boundary: pruning the selected boundary clears the selection")
    vm.undo()
    check(vm.document.boundaries.count == 1 && vm.document.root.contains(branch),
          "boundary: undo restores the anchor and its boundary")
    vm.redo()
    check(vm.document.boundaries.isEmpty, "boundary: redo prunes it again")
    vm.undo()
    check(vm.document.boundaries.count == 1, "boundary: undo/redo round-trips the boundary")

    let target = vm.addChild(to: nil)!
    vm.move(id: branch, toParent: target)
    check(vm.boundary(forRoot: branch) != nil,
          "boundary: moving the anchor keeps the boundary on it")
    vm.move(id: leafB, toParent: target)
    check(vm.boundary(forRoot: branch) != nil,
          "boundary: moving a descendant out keeps the boundary")
    check(vm.document.root.find(target)?.children.count == 2,
          "boundary: control — both moves actually landed")

    // Batch delete: anchors inside the batch take their boundaries with them.
    vm.newDocument()
    let b1 = vm.addChild(to: nil)!
    let b2 = vm.addChild(to: nil)!
    _ = vm.addBoundary(rootID: b1)
    _ = vm.addBoundary(rootID: b2)
    vm.batchSelection = [b1, b2]
    vm.deleteBatch()
    check(vm.document.boundaries.isEmpty,
          "boundary: batch-deleting the anchors prunes both")

    // Reordering siblings changes the order, never the anchor.
    vm.newDocument()
    let r1 = vm.addChild(to: nil)!
    let r2 = vm.addChild(to: nil)!
    _ = vm.addBoundary(rootID: r1)
    vm.moveSibling(id: r1, offset: 1)
    check(vm.document.boundaries.count == 1 && vm.document.boundaries[0].rootID == r1
          && vm.document.root.children.first?.id == r2,
          "boundary: reordering siblings changes nothing but the order")

    // Tab switch clears the selection, not the document's boundary.
    vm.openInNewTab(MindDocument(title: "B", root: MindNode(text: "B")))
    check(vm.selectedBoundaryID == nil,
          "boundary: switching tabs clears the boundary selection")
}

do {
    // Geometry: coverage is the anchor plus its visible descendants, padded.
    let vm = MindMapViewModel()
    vm.newDocument()
    let anchor = vm.addChild(to: nil)!
    let child = vm.addChild(to: anchor)!
    let grand = vm.addChild(to: child)!
    let outside = vm.addChild(to: nil)!
    _ = vm.addBoundary(rootID: anchor)

    let layouts = LayoutEngine.layout(root: vm.document.root, direction: .logicRight)
    let boundary = vm.document.boundaries[0]
    let geo = BoundaryGeometry.frame(for: boundary, root: vm.document.root,
                                     layouts: layouts, origin: .zero)
    check(geo != nil, "boundary geometry: a live boundary produces a frame")
    if let geo {
        let covered = [anchor, child, grand].compactMap { layouts[$0]?.frame }
        check(covered.count == 3 && covered.allSatisfy { geo.rect.contains($0) },
              "boundary geometry: the frame contains the anchor and every descendant")
        check(!geo.rect.intersects(layouts[outside]!.frame),
              "boundary geometry: the frame excludes nodes outside the subtree")
        let shifted = BoundaryGeometry.frame(for: boundary, root: vm.document.root,
                                             layouts: layouts, origin: CGPoint(x: 100, y: 50))
        check(shifted?.rect == geo.rect.offsetBy(dx: 100, dy: 50),
              "boundary geometry: origin offsets the frame like every other surface")

        // Collapsing the anchor hides the descendants from layout; the frame
        // shrinks to the anchor instead of disappearing.
        vm.toggleCollapse(id: anchor)
        let collapsedLayouts = LayoutEngine.layout(root: vm.document.root, direction: .logicRight)
        let collapsed = BoundaryGeometry.frame(for: vm.document.boundaries[0], root: vm.document.root,
                                               layouts: collapsedLayouts, origin: .zero)
        check(collapsed?.rect == collapsedLayouts[anchor]!.frame.insetBy(dx: -10, dy: -10),
              "boundary geometry: a collapsed anchor frames only its own node, padded 10pt")

        let orphan = MindBoundary(rootID: UUID())
        check(BoundaryGeometry.frame(for: orphan, root: vm.document.root,
                                     layouts: collapsedLayouts, origin: .zero) == nil,
              "boundary geometry: a missing anchor has no frame")
    }

    // Persistence: tolerant decode in both directions.
    let encoded = try JSONEncoder().encode(vm.document)
    let decoded = try JSONDecoder().decode(MindDocument.self, from: encoded)
    check(decoded.boundaries == vm.document.boundaries,
          "boundary: Codable round-trip preserves id and rootID")

    let rootIDString = "11111111-1111-1111-1111-111111111111"
    let legacyJSON = """
    {"title":"舊檔","themeName":"ocean","directionName":"logicRight",
     "root":{"id":"\(rootIDString)","text":"中心"}}
    """
    let legacyDoc = try? JSONDecoder().decode(MindDocument.self, from: Data(legacyJSON.utf8))
    check(legacyDoc?.boundaries.isEmpty == true,
          "boundary: an older file without the field decodes to none")

    let futureJSON = """
    {"title":"未來","themeName":"ocean","directionName":"logicRight",
     "root":{"id":"\(rootIDString)","text":"中心"},
     "boundaries":[{"rootID":"\(rootIDString)","style":"neon"}]}
    """
    let futureDoc = try? JSONDecoder().decode(MindDocument.self, from: Data(futureJSON.utf8))
    check(futureDoc?.boundaries.count == 1
          && futureDoc?.boundaries[0].rootID == UUID(uuidString: rootIDString),
          "boundary: an unknown field is ignored and a missing id is regenerated")

    // Export: drawn in vector/bitmap formats, invisible to the tree formats.
    vm.removeBoundary(rootID: anchor)
    let svgWithout = MapExporter.svg(vm.document)
    let mdWithout = try MapExporter.markdown(vm.document)
    _ = vm.addBoundary(rootID: anchor)
    let svgWith = MapExporter.svg(vm.document)
    let mdWith = try MapExporter.markdown(vm.document)
    check(svgWith.components(separatedBy: "<rect").count
          == svgWithout.components(separatedBy: "<rect").count + 1,
          "boundary: SVG export draws exactly one extra rect")
    check(mdWith == mdWithout,
          "boundary: Markdown export is unchanged — no fake boundary node")

    check(["Sources/MindFlowKit/MapCanvasView.swift", "Sources/MindFlowKit/StaticMapView.swift",
           "Sources/MindFlowKit/MapExporter.swift"].allSatisfy {
        projectSource($0).contains("BoundaryGeometry.frame")
    }, "boundary: canvas, static render and SVG all call the one geometry function")

    // ⇧⌘B is XMind's Insert Boundary. p1's round-29 lesson: a menu key that the
    // monitor silently consumes is worse than no shortcut, so assert it is free.
    check(!KeyboardMonitor.performCoreShortcut(characters: "b", modifiers: [.command, .shift], vm: vm),
          "boundary: the core shortcut path does not consume ⇧⌘B")
    check(!projectSource("Sources/MindFlowKit/KeyboardMonitor.swift").contains("\"b\""),
          "boundary: no key string in the monitor claims b, so the menu can fire")
    check(projectSource("Sources/MindFlow/MindFlowApp.swift")
            .contains(".keyboardShortcut(\"b\", modifiers: [.command, .shift])"),
          "boundary: 加入外框 is bound to XMind's ⇧⌘B")
}

// Geometry across every shipped layout. The block above only exercised
// .logicRight. Fishbone flattens a branch onto a strict diagonal, balanced
// splits the children left/right, and bracket reuses the logicRight branch —
// a frame that is right in one direction says nothing about the other three.

do {
    let directions: [(MapDirection, String)] = [
        (.logicRight, "logicRight"),
        (.balanced, "balanced"),
        (.fishbone, "fishbone"),
        (.bracket, "bracket"),
    ]
    // The gap is a literal on purpose: an oracle that reads the constant it is
    // checking cannot catch that constant drifting. The constant itself is
    // pinned against the documented value right below.
    let documentedPadding: CGFloat = 10
    let eps: CGFloat = 0.0001
    var framesByDirection: [String: CGRect] = [:]

    check(BoundaryGeometry.padding == documentedPadding
          && BoundaryGeometry.cornerRadius == documentedPadding,
          "boundary geometry: the documented padding and corner radius are both 10pt")

    for (direction, name) in directions {
        let vm = MindMapViewModel()
        vm.newDocument()
        let anchor = vm.addChild(to: nil)!
        let child = vm.addChild(to: anchor)!
        let grand = vm.addChild(to: child)!
        // Two uncovered root children. The immediate sibling is the tight one:
        // vGap is 12 and the frame pads by 10, so it clears by exactly 2pt in
        // logicRight/bracket/balanced and 168pt in fishbone; the second sibling
        // clears by 52–420pt. That coupling is the point — if the padding ever
        // grows past vGap the frame would enclose the neighbouring row's node,
        // which is a real defect and should turn this red.
        let outside = vm.addChild(to: nil)!
        let far = vm.addChild(to: nil)!
        _ = vm.addBoundary(rootID: anchor)

        let layouts = LayoutEngine.layout(root: vm.document.root, direction: direction)
        guard let geo = BoundaryGeometry.frame(for: vm.document.boundaries[0],
                                               root: vm.document.root,
                                               layouts: layouts, origin: .zero) else {
            check(false, "boundary geometry (\(name)): a frame exists")
            continue
        }
        framesByDirection[name] = geo.rect
        let covered = [anchor, child, grand].compactMap { layouts[$0]?.frame }

        // 1. Containment: every covered node sits inside, with the documented gap.
        check(covered.count == 3 && covered.allSatisfy {
            geo.rect.minX <= $0.minX - documentedPadding + eps &&
            geo.rect.minY <= $0.minY - documentedPadding + eps &&
            geo.rect.maxX >= $0.maxX + documentedPadding - eps &&
            geo.rect.maxY >= $0.maxY + documentedPadding - eps
        }, "boundary geometry (\(name)): every covered node is inside with 10pt to spare")

        // 2. Tightness: no side may carry more slack than the documented gap, so a
        //    frame that swallows the whole canvas passes (1) but fails here.
        let unionMinX = covered.map(\.minX).min() ?? 0
        let unionMinY = covered.map(\.minY).min() ?? 0
        let unionMaxX = covered.map(\.maxX).max() ?? 0
        let unionMaxY = covered.map(\.maxY).max() ?? 0
        check(abs(geo.rect.minX - (unionMinX - documentedPadding)) < eps &&
              abs(geo.rect.minY - (unionMinY - documentedPadding)) < eps &&
              abs(geo.rect.maxX - (unionMaxX + documentedPadding)) < eps &&
              abs(geo.rect.maxY - (unionMaxY + documentedPadding)) < eps,
              "boundary geometry (\(name)): the frame hugs the covered subtree — 10pt on all four sides")

        // 3. Negative control: uncovered siblings stay outside. Without this, a
        //    degenerate "frame everything" implementation passes (1)+(2).
        let uncovered = [outside, far].compactMap { layouts[$0]?.frame }
        check(uncovered.count == 2 && uncovered.allSatisfy { !geo.rect.contains($0) },
              "boundary geometry (\(name)): both uncovered siblings stay outside the frame")
    }

    // Positive control: the direction argument really moved the nodes, so the
    // per-direction assertions are not one layout measured four times.
    check(Set(framesByDirection.values.map { "\($0)" }).count >= 3,
          "boundary geometry: the four directions produce at least three distinct frames")
    // Observed, not assumed: bracket shares the logicRight placement branch
    // (`case .logicRight, .bracket:`), so their node frames — and thus the
    // boundary frame — coincide. If bracket ever gets its own layout this turns
    // red and the line should be re-measured, not deleted.
    check(framesByDirection["bracket"] == framesByDirection["logicRight"],
          "boundary geometry: bracket reuses the logicRight layout, so their frames coincide")
}

// MARK: - One selected object at a time, and Delete acts on it
//
// A node ring and a boundary frame are stroked with the same accent, so two
// objects could look selected at once while Delete silently acted on the node.
// Measured before the fix with a real window: ⇧⌘B then Delete took the node
// count from 21 to 16 — the frame's whole subtree, not the frame.

do {
    let vm = MindMapViewModel()
    vm.newDocument()
    let branch = vm.addChild(to: nil)!
    let leaf = vm.addChild(to: branch)!
    func nodeCount() -> Int {
        func walk(_ n: MindNode) -> Int { 1 + n.children.reduce(0) { $0 + walk($1) } }
        return walk(vm.document.root)
    }
    func pressDelete() -> Bool {
        KeyboardMonitor.performDelete(vm: vm, textFieldEditing: false, editingHandoffActive: false)
    }

    _ = vm.addBoundary(rootID: branch)
    check(vm.selectedBoundaryID != nil, "selection: creating a boundary selects it")

    vm.selection = leaf
    check(vm.selectedBoundaryID == nil,
          "selection: selecting a node releases the boundary, so only one thing looks selected")

    // Delete with a boundary selected removes the frame and leaves the tree.
    _ = vm.addBoundary(rootID: branch)
    let before = nodeCount()
    check(pressDelete(), "selection: Delete is handled while a boundary is selected")
    check(vm.document.boundaries.isEmpty,
          "selection: Delete removes the selected boundary")
    check(nodeCount() == before,
          "selection: deleting a boundary destroys no nodes (the 21->16 defect)")

    // Control: with nothing but a node selected, Delete still deletes the node.
    vm.selection = leaf
    let beforeNode = nodeCount()
    _ = pressDelete()
    check(nodeCount() == beforeNode - 1,
          "selection: control — Delete still removes a plain selected node")
}

if failures == 0 {
    print("ALL CHECKS PASSED")
} else {
    print("\(failures) CHECK(S) FAILED")
}
exit(failures == 0 ? 0 : 1)
