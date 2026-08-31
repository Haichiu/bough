import AppKit
import SwiftUI

/// Everything needed to freeze and restore one open tab.
public struct EditorSession: Equatable {
    public var id = UUID()
    public var document: MindDocument
    public var filePath: URL?
    public var dirty = false

    public init(id: UUID = UUID(), document: MindDocument, filePath: URL? = nil) {
        self.id = id
        self.document = document
        self.filePath = filePath
    }
}

@MainActor
public final class MindMapViewModel: ObservableObject {
    @Published public var document: MindDocument
    @Published public var selection: UUID?
    @Published public var editingID: UUID?
    @Published public var filePath: URL?
    @Published public var dirty = false
    /// When the last automatic save finished; shown in the title bar for reassurance.
    @Published public var lastSavedAt: Date?
    @Published public var exportRequest: ExportFormat?
    @Published public var recentlyAddedID: UUID?
    @Published public var statusMessage: String?
    private var statusTask: Task<Void, Never>?
    private let autosaveStore: TabStore?

    /// Shows a short transient confirmation for non-obvious actions.
    public func notify(_ message: String) {
        statusTask?.cancel()
        statusMessage = message
        statusTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            if !Task.isCancelled { self?.statusMessage = nil }
        }
    }

    public enum ExportFormat: String, Equatable {
        case markdown, opml, png, pdf, svg, freemind, pngBranch, svgBranch, pngTransparent, pngLarge
    }

    private var undoStack: [MindDocument] = []
    private var lastCoalesceKey: String?
    private var lastCoalesceTime = Date.distantPast
    private var redoStack: [MindDocument] = []
    private let undoLimit = 100

    // MARK: - Tabs (multi-document)

    @Published public var sessions: [EditorSession] = []
    @Published public var activeIndex = 0
    private var inactiveStacks: [UUID: ([MindDocument], [MindDocument])] = [:]
    private var inactiveSelections: [UUID: UUID?] = [:]

    /// Presentation applies to exactly one document; leave it quietly before any
    /// wholesale document switch so collapse-state restoration lands correctly.
    private func wrapUpPresentationIfActive() {
        if presentationActive { exitPresentation() }
    }

    private func stashActive() {
        guard sessions.indices.contains(activeIndex) else { return }
        sessions[activeIndex].document = document
        sessions[activeIndex].filePath = filePath
        sessions[activeIndex].dirty = dirty
        inactiveStacks[sessions[activeIndex].id] = (undoStack, redoStack)
        inactiveSelections[sessions[activeIndex].id] = selection
    }

    private func loadFromSession(_ index: Int) {
        wrapUpPresentationIfActive()
        guard sessions.indices.contains(index) else { return }
        activeIndex = index
        document = sessions[index].document
        filePath = sessions[index].filePath
        dirty = sessions[index].dirty
        (undoStack, redoStack) = inactiveStacks[sessions[index].id] ?? ([], [])
        selection = inactiveSelections[sessions[index].id] ?? document.root.id
        selectedLinkID = nil
        selectedSummaryID = nil
        // Focus belongs to a specific document — never leak across tabs.
        focusBranchID = nil
        // Search results belong to a specific document — never leak across tabs.
        searchQuery = ""
        searchResults = []
        batchSelection.removeAll()
        searchIndex = 0
        showSearch = false
        zenMode = false
        stopEditing()
    }

    /// Opens a document in its own tab and makes it active.
    public func openInNewTab(_ doc: MindDocument, filePath: URL? = nil) {
        stashActive()
        sessions.append(EditorSession(document: doc, filePath: filePath))
        loadFromSession(sessions.count - 1)
        selection = doc.root.id
        if zenMode { zenMode = false }
    }

    public func switchTab(to index: Int) {
        guard sessions.indices.contains(index), index != activeIndex else { return }
        stashActive()
        loadFromSession(index)
    }

    /// Recently closed tabs, newest first (in-memory for this launch).
    private var closedTabsStack: [EditorSession] = []

    /// Reopens the most recently closed tab.
    public func reopenLastClosedTab() {
        guard let session = closedTabsStack.popLast() else {
            notify("沒有最近關閉的分頁")
            return
        }
        openInNewTab(session.document, filePath: session.filePath)
        notify("已重新開啟分頁")
    }

    public func closeTab(_ index: Int) {
        guard sessions.indices.contains(index) else { return }
        // Keep a recoverable copy on disk before dropping the in-memory session.
        let doc = index == activeIndex ? document : sessions[index].document
        closedTabsStack.append(EditorSession(id: sessions[index].id, document: doc,
                                             filePath: index == activeIndex ? filePath : sessions[index].filePath))
        if closedTabsStack.count > 20 { closedTabsStack.removeFirst() }
        FileIO.writeRecoveryCopy(doc)
        inactiveStacks.removeValue(forKey: sessions[index].id)
        inactiveSelections.removeValue(forKey: sessions[index].id)
        sessions.remove(at: index)
        let wasActive = index == activeIndex
        if sessions.isEmpty {
            sessions = [EditorSession(document: .new())]
            document = sessions[0].document
            filePath = nil
            dirty = false
            undoStack = []
            redoStack = []
            selection = document.root.id
            activeIndex = 0
        } else if wasActive {
            loadFromSession(min(index, sessions.count - 1))
        } else if index < activeIndex {
            activeIndex -= 1
        }
    }

    private var snapshotTimer: Timer?

    /// Every 5 minutes, drop a recovery copy so long thinking sessions are protected.
    public func startSnapshotTimer() {
        snapshotTimer?.invalidate()
        snapshotTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.document.root.text.isEmpty || self.dirty else { return }
                FileIO.writeRecoveryCopy(self.document)
            }
        }
    }

    /// Writes every open tab as one verified transactional snapshot.
    @discardableResult
    public func autosaveAllSessions() -> TabStore.SaveOutcome {
        var snapshot = sessions
        if snapshot.indices.contains(activeIndex) {
            snapshot[activeIndex].document = document
            snapshot[activeIndex].filePath = filePath
        }
        let outcome: TabStore.SaveOutcome
        if let autosaveStore {
            outcome = autosaveStore.save(snapshot.map {
                TabStore.Entry(id: $0.id, document: $0.document)
            })
        } else {
            outcome = FileIO.autosaveTabs(snapshot.map { ($0.id, $0.document) })
        }
        switch outcome {
        case .committed(let warning):
            lastSavedAt = Date()
            if let warning {
                NSLog("MindFlow autosave committed with warning: \(warning)")
            }
        case .failed(let error):
            notify("自動保存失敗，已保留舊版本")
            NSLog("MindFlow autosave failed: \(error)")
        }
        return outcome
    }

    public init(tabStore: TabStore) {
        self.autosaveStore = tabStore
        let first = MindDocument.new()
        self.document = first
        self.selection = first.root.id
        self.sessions = [EditorSession(document: first)]
    }

    public init() {
        self.autosaveStore = nil
        let restored = FileIO.loadTabs()
        var initialSessions: [EditorSession]
        if restored.isEmpty {
            // Migrate the single-document autosave, or greet newcomers with a sample.
            let first = FileIO.loadAutosave() ?? Self.sampleDocument()
            initialSessions = [EditorSession(document: first)]
        } else {
            // Reuse the on-disk slot IDs so autosave overwrites instead of piling up.
            initialSessions = restored.map { EditorSession(id: $0.id, document: $0.document) }
        }
        let firstDocument = initialSessions[0].document
        sessions = initialSessions
        document = firstDocument
        selection = firstDocument.root.id
    }

    static func sampleDocument() -> MindDocument {
        func node(_ text: String, note: String = "", marked: Bool = false,
                  colorTag: String? = nil, children: [MindNode] = []) -> MindNode {
            MindNode(text: text, note: note, marked: marked, colorTag: colorTag, children: children)
        }
        let welcome = MindNode(text: "歡迎使用 MindFlow 🎉", note: "這張圖會教你所有基本操作", children: [
            node("選取我之後按 Tab，就能長出子主題", children: [
                node("再按 Tab 可以繼續往 deeper 長"),
            ]),
            node("按 Return 可以加一個隔壁的主題", marked: true),
            node("連點兩下直接改文字", colorTag: "blue"),
            node("拖曳節點可重掛、排序或自由移動", note: "節點上＝重掛；插入線上＝排序；空白處＝自由放置"),
            node("更多小技巧", children: [
                node("⌘F 搜尋主題", colorTag: "green"),
                node("⌘D 複製整棵子樹"),
                node("⌘L 加上星星標記", marked: true),
                node("⌥↑↓ 調整兄弟順序"),
                node("不用按儲存，全部自動保存"),
            ]),
        ])
        return MindDocument(title: "歡迎使用 MindFlow", root: welcome)
    }

    // MARK: - Mutation core

    /// Applies a mutation. Passing a coalesce key merges rapid successive edits
    /// (e.g. typing in a note) into a single undo step.
    private func mutate(_ coalesceKey: String? = nil, _ change: (inout MindDocument) -> Void) {
        let now = Date()
        let shouldPushUndo = !(coalesceKey != nil && coalesceKey == lastCoalesceKey
            && now.timeIntervalSince(lastCoalesceTime) < 3)
        if shouldPushUndo {
            undoStack.append(document)
            if undoStack.count > undoLimit { undoStack.removeFirst(undoStack.count - undoLimit) }
        }
        lastCoalesceKey = coalesceKey
        lastCoalesceTime = now
        redoStack.removeAll()
        change(&document)
        dirty = true
    }

    public func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(document)
        document = previous
        stopEditing()
    }

    public func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(document)
        document = next
        stopEditing()
    }

    // MARK: - Structure editing (XMind core interactions)

    @discardableResult
    public func addChild(to parentID: UUID?) -> UUID? {
        let target = parentID ?? document.root.id
        guard document.root.contains(target) else { return nil }
        // Start empty: typing replaces cleanly, empty commit discards the node.
        let newNode = MindNode(text: "")
        mutate { doc in
            doc.root.update(target) { node in
                node.collapsed = false
                node.children.append(newNode)
            }
        }
        selection = newNode.id
        editingID = newNode.id
        flash(newNode.id)
        notify("已新增子主題，直接輸入文字")
        return newNode.id
    }

    @discardableResult
    public func addSibling(of id: UUID) -> UUID? {
        guard id != document.root.id,
              let parentNode = document.root.parent(of: id),
              document.root.contains(id) else { return nil }
        let newNode = MindNode(text: "")
        mutate { doc in
            doc.root.update(parentNode.id) { parent in
                if let index = parent.children.firstIndex(where: { $0.id == id }) {
                    parent.children.insert(newNode, at: parent.children.index(after: index))
                } else {
                    parent.children.append(newNode)
                }
            }
        }
        selection = newNode.id
        editingID = newNode.id
        flash(newNode.id)
        notify("已新增兄弟主題，直接輸入文字")
        return newNode.id
    }

    /// Inserts a new sibling immediately before the selected node (Xmind Shift+Enter).
    @discardableResult
    public func addSiblingBefore(of id: UUID) -> UUID? {
        guard id != document.root.id,
              let parentNode = document.root.parent(of: id),
              let index = parentNode.children.firstIndex(where: { $0.id == id }) else { return nil }
        let newNode = MindNode(text: "")
        mutate { doc in
            doc.root.update(parentNode.id) { parent in
                parent.children.insert(newNode, at: index)
            }
        }
        selection = newNode.id
        editingID = newNode.id
        flash(newNode.id)
        notify("已在前方新增兄弟主題，直接輸入文字")
        return newNode.id
    }

    /// Cancels inline editing. Only a newly-created empty leaf is safe to discard.
    public func cancelNodeEditing(id: UUID, draft: String) {
        if draft.trimmingCharacters(in: .whitespaces).isEmpty,
           let node = document.root.find(id), node.text.isEmpty, node.children.isEmpty {
            delete(id: id)
            notify("已捨棄空白主題")
        }
        stopEditing()
    }

    /// Commits inline editing. Empty text on a brand-new node discards it.
    public func commitNodeText(id: UUID, text: String) {
        let flattened = text
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
        let trimmed = flattened.trimmingCharacters(in: .whitespaces)
        let current = document.root.find(id)?.text ?? ""
        if trimmed.isEmpty {
            if current.isEmpty {
                // Brand-new node abandoned mid-creation.
                delete(id: id)
                notify("已捨棄空白主題")
            } else {
                notify("主題不能空白，已保留原文字")
            }
            return
        }
        rename(id: id, to: trimmed)
    }

    public func delete(id: UUID) {
        guard id != document.root.id, document.root.contains(id) else {
            if id == document.root.id { notify("中心主題是整張圖的根，不能刪除喔") }
            return
        }
        let removed = document.root.find(id)?.descendantIDs() ?? []
        var allRemoved = removed
        allRemoved.insert(id)
        mutate { doc in
            _ = doc.root.remove(id)
            doc.links.removeAll { allRemoved.contains($0.from) || allRemoved.contains($0.to) }
            // Summaries spanning the removed endpoints no longer make sense.
            doc.summaries.removeAll { allRemoved.contains($0.startID) || allRemoved.contains($0.endID) || allRemoved.contains($0.parentID) }
            pruneSummaries(doc: &doc)
        }
        if selection == id { selection = nil }
        stopEditing()
        notify("已刪除主題（⌘Z 可復原）")
    }

    /// Enters edit mode on an existing node. `replacingWith` implements type-to-replace:
    /// typing a printable character on a selected node wipes the text and starts editing,
    /// the way MindNode and XMind behave.
    public func beginEditing(id: UUID, replacingWith text: String? = nil) {
        guard document.root.contains(id) else { return }
        if let text { mutate("replace:\(id)") { $0.root.update(id) { $0.text = text } } }
        selection = id
        editingID = id
    }

    public func rename(id: UUID, to text: String) {
        guard document.root.contains(id) else { return }
        mutate { $0.root.update(id) { $0.text = text } }
    }

    public func setNote(id: UUID, to note: String) {
        guard document.root.contains(id) else { return }
        mutate("note:\(id)") { doc in
            doc.root.update(id) { node in node.note = note }
        }
    }

    public func toggleCollapse(id: UUID) {
        guard document.root.contains(id) else { return }
        mutate { doc in
            doc.root.update(id) { node in node.collapsed.toggle() }
            // Manual collapse invalidates preset level
            activeCollapseLevel = nil
        }
    }

    /// Moves a node (with its subtree) under another node.
    public func move(id: UUID, toParent parentID: UUID) {
        guard id != document.root.id,
              id != parentID,
              let node = document.root.find(id),
              let currentParent = document.root.parent(of: id),
              currentParent.id != parentID,
              !node.isAncestor(of: parentID),
              let target = document.root.find(parentID) else { return }
        let moving = node
        mutate { doc in
            _ = doc.root.remove(id)
            doc.root.update(parentID) { parent in parent.children.append(moving) }
        }
        selection = id
        _ = target
    }

    public func expandAll() {
        mutate { doc in collapse(node: &doc.root, collapsed: false) }
        activeCollapseLevel = nil
    }

    @Published public var activeCollapseLevel: Int?

    /// Expands so exactly `levels` layers of topics are visible.
    public func expandToLevel(_ levels: Int) {
        guard levels >= 1 else { return }
        activeCollapseLevel = levels
        mutate { doc in
            func resetDeep(_ node: inout MindNode) {
                node.collapsed = !node.children.isEmpty
                for index in node.children.indices {
                    resetDeep(&node.children[index])
                }
            }

            func walk(_ node: inout MindNode, depth: Int) {
                guard !node.children.isEmpty else { return }
                let hideChildren = (depth + 1) >= levels
                node.collapsed = hideChildren
                if hideChildren {
                    for index in node.children.indices {
                        resetDeep(&node.children[index])
                    }
                } else {
                    for index in node.children.indices {
                        walk(&node.children[index], depth: depth + 1)
                    }
                }
            }
            walk(&doc.root, depth: 0)
        }
    }

    public func collapseAll() {
        mutate { doc in
            collapse(node: &doc.root, collapsed: false)
            for index in doc.root.children.indices {
                collapse(node: &doc.root.children[index], collapsed: true)
            }
        }
        // A blanket collapse is not a specific "level" — clear the indicator.
        activeCollapseLevel = nil
    }

    public func toggleAllBranches() {
        let hasExpandedBranch = document.root.children.contains {
            !$0.children.isEmpty && !$0.collapsed
        }
        if hasExpandedBranch { collapseAll() } else { expandAll() }
    }

    // MARK: - Presentation（簡報逐層揭開）

    @Published public var presentationActive = false
    private var savedCollapseStates: [UUID: Bool]?
    private var presentationDepth = 1
    /// True when the cursor is over the map canvas (not inspector/toolbar).
    /// Used to gate scroll-wheel handling so scrolling UI chrome doesn't pan the map.
    @Published public var isCursorOverCanvas = false
    /// Undo entries made before entering presentation; steps inside are non-undoable.
    private var undoBaselineCount: Int?

    /// Shows hierarchical numbers ("2.1") in the outline view. Persisted.
    @Published public var showOutlineNumbers: Bool = UserDefaults.standard.bool(forKey: "showOutlineNumbers") {
        didSet {
            guard oldValue != showOutlineNumbers else { return }
            UserDefaults.standard.set(showOutlineNumbers, forKey: "showOutlineNumbers")
        }
    }

    /// Enters presentation mode: shows only the first layer, ready to reveal more.
    public func enterPresentation() {
        guard !presentationActive else { return }
        var states: [UUID: Bool] = [:]
        func snap(_ node: MindNode) {
            states[node.id] = node.collapsed
            node.children.forEach(snap)
        }
        snap(document.root)
        savedCollapseStates = states
        undoBaselineCount = undoStack.count
        presentationDepth = 1
        presentationActive = true
        expandToLevel(1)
        NotificationCenter.default.post(name: .mindFlowFit, object: nil)
        notify("簡報模式：→ 或空白鍵揭開下一層，Esc 結束")
    }

    /// Reveals one more layer of topics.
    public func stepPresentation() {
        guard presentationActive else { return }
        let maxDepth = document.stats().maxDepth
        guard presentationDepth < maxDepth else {
            notify("已經是最後一層了")
            return
        }
        presentationDepth += 1
        expandToLevel(presentationDepth)
        NotificationCenter.default.post(name: .mindFlowFit, object: nil)
    }

    /// Steps back one layer.
    public func rewindPresentation() {
        guard presentationActive, presentationDepth > 1 else { return }
        presentationDepth -= 1
        expandToLevel(presentationDepth)
        NotificationCenter.default.post(name: .mindFlowFit, object: nil)
    }

    /// Leaves presentation mode and restores every node's original collapse state.
    public func exitPresentation() {
        guard presentationActive else { return }
        presentationActive = false
        if let saved = savedCollapseStates {
            mutate { doc in
                func restore(_ node: inout MindNode) {
                    node.collapsed = saved[node.id] ?? false
                    for index in node.children.indices {
                        restore(&node.children[index])
                    }
                }
                restore(&doc.root)
            }
        }
        activeCollapseLevel = nil
        savedCollapseStates = nil
        // Presentation steps never enter the undo history: trim back to baseline.
        if let baseline = undoBaselineCount, undoStack.count > baseline {
            undoStack.removeLast(undoStack.count - baseline)
            redoStack.removeAll()
        }
        undoBaselineCount = nil
        NotificationCenter.default.post(name: .mindFlowFit, object: nil)
        notify("已離開簡報模式")
    }

    private func collapse(node: inout MindNode, collapsed: Bool) {
        node.collapsed = node.children.isEmpty ? false : collapsed
        for index in node.children.indices {
            collapse(node: &node.children[index], collapsed: collapsed)
        }
    }

    // MARK: - Layout direction & sibling order

    public var direction: MapDirection {
        MapDirection(rawValue: document.directionName) ?? .logicRight
    }

    public func setDirection(_ direction: MapDirection) {
        mutate { $0.directionName = direction.rawValue }
        let name: String
        switch direction {
        case .logicRight: name = "邏輯圖（右展）"
        case .balanced: name = "平衡圖（左右）"
        case .fishbone: name = "魚骨圖"
        case .bracket: name = "括號圖"
        }
        notify("\u{5df2}\u{5207}\u{63db}\u{81f3}\(name)")
    }

    public func moveSibling(id: UUID, offset: Int) {
        guard id != document.root.id,
              let parent = document.root.parent(of: id),
              let index = parent.children.firstIndex(where: { $0.id == id }) else { return }
        let target = index + offset
        guard parent.children.indices.contains(target) else { return }
        mutate { doc in
            doc.root.update(parent.id) { node in
                let item = node.children.remove(at: index)
                node.children.insert(item, at: target)
            }
        }
        selection = id
        notify("已重新掛接")
    }


    // MARK: - Manual position nudges

    /// Applies a keyboard nudge. Rapid repeats coalesce into one undo step.
    public func nudgeOffset(id: UUID, dx: CGFloat, dy: CGFloat) {
        adjustOffset(id: id, dx: dx, dy: dy, coalesce: true)
    }

    /// Places a node after one pointer drag. Each drag is its own undo step.
    public func moveOffset(id: UUID, dx: CGFloat, dy: CGFloat) {
        adjustOffset(id: id, dx: dx, dy: dy, coalesce: false)
    }

    private func adjustOffset(id: UUID, dx: CGFloat, dy: CGFloat, coalesce: Bool) {
        guard document.root.contains(id), dx != 0 || dy != 0 else { return }
        let key = id.uuidString
        mutate(coalesce ? "offset:\(key)" : nil) { doc in
            var current = doc.offsets[key] ?? .zero
            current.x += dx
            current.y += dy
            doc.offsets[key] = current
        }
    }

    public func clearOffset(id: UUID) {
        guard document.root.contains(id) else { return }
        mutate { $0.offsets.removeValue(forKey: id.uuidString) }
        notify("已將節點歸位")
    }

    /// Resets every manual nudge back to pure auto layout.
    public func resetAllOffsets() {
        guard !document.offsets.isEmpty else { return }
        mutate { $0.offsets = [:] }
        notify("已回到自動排列")
    }

    // MARK: - Branch focus

    @Published public var focusBranchID: UUID?

    public func toggleFocus(on id: UUID) {
        focusBranchID = (focusBranchID == id) ? nil : id
        notify(focusBranchID == nil ? "已取消聚焦" : "已聚焦分支（Esc 取消）")
    }

    /// IDs visible during focus: the focused subtree plus its ancestor chain.
    public func focusSet() -> Set<UUID> {
        guard let fid = focusBranchID, let fnode = document.root.find(fid) else { return [] }
        var set: Set<UUID> = [fid]
        set.formUnion(fnode.descendantIDs())
        var cursor: UUID? = fid
        while let currentID = cursor, let parent = document.root.parent(of: currentID) {
            set.insert(parent.id)
            cursor = parent.id
            if parent.id == document.root.id { break }
        }
        return set
    }

    // MARK: - Clipboard paste as nodes

    /// Parses clipboard text (Markdown outline or plain lines) and creates
    /// child nodes under the currently selected topic.
    public func pasteAsNodes() {
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            // No text — but an image on the clipboard attaches to the selected node.
            if let img = NSPasteboard.general.data(forType: .tiff) {
                attachClipboardImage(img)
                return
            }
            notify("剪貼簿是空的")
            return
        }
        insertTextAsNodes(text, sourceLabel: "剪貼簿")
    }

    /// Encodes clipboard TIFF data as a PNG data URL, auto-downscaling oversized images.
    private func attachClipboardImage(_ tiffData: Data) {
        guard let target = idForImageAttachment else { return }
        guard let image = NSImage(data: tiffData),
              let dataURL = ImageStore.pngDataURL(from: image, maxBytes: 2_800_000) else {
            notify("這張圖太大了（上限約 2 MB），請先縮小再試")
            return
        }
        setNodeImage(id: target, to: dataURL)
    }

    /// Target node for clipboard image attachment: current selection or root.
    private var idForImageAttachment: UUID? {
        selection ?? document.root.id
    }

    /// Parses plain text / Markdown outline and appends it as nodes under
    /// `parentID` (falling back to the current selection, then root).
    /// Used by ⌘⇧V paste and canvas drop.
    public func insertTextAsNodes(_ rawText: String, sourceLabel: String, parentID: UUID? = nil) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            notify("沒有可加入的文字")
            return
        }
        guard let imported = MapImporter.markdown(text), !imported.root.children.isEmpty else {
            notify("無法解析\(sourceLabel)內容")
            return
        }
        // Attach imported tree under the given node (or selection/root).
        let parentID = parentID ?? selection ?? document.root.id
        let importedChildren = imported.root.children
        mutate { doc in
            doc.root.update(parentID) { node in
                node.children.append(contentsOf: importedChildren)
            }
        }
        dirty = true
        notify("已從\(sourceLabel)加入 \(importedChildren.count) 個主題 ✓")
    }

    /// True when the last selection change came from keyboard navigation
    /// (arrow keys), meaning revealNode should scroll to keep it visible.
    public var lastNavWasKeyboard = false

    /// Returns the chain of nodes from root to the given node (inclusive).
    public func breadcrumbPath(to id: UUID) -> [MindNode] {
        var chain: [MindNode] = []
        var cursor: UUID? = id
        while let currentID = cursor {
            guard let node = document.root.find(currentID) else { break }
            chain.insert(node, at: 0)
            if currentID == document.root.id { break }
            cursor = document.root.parent(of: currentID)?.id
        }
        return chain
    }

    // MARK: - Associative links

    @Published public var selectedLinkID: UUID?
    /// Currently selected summary bracket (for inspector text editing).
    @Published public var selectedSummaryID: UUID?

    /// Creates an associative link between two existing nodes.
    @discardableResult
    public func addLink(from: UUID, to: UUID) -> UUID? {
        guard from != to,
              document.root.contains(from),
              document.root.contains(to),
              !document.links.contains(where: { ($0.from == from && $0.to == to) || ($0.from == to && $0.to == from) })
        else { return nil }
        let link = MindLink(from: from, to: to)
        mutate { $0.links.append(link) }
        notify("已建立關聯線；點線中間的圓點再按 Delete 可刪除")
        return link.id
    }

    public func removeLink(id: UUID) {
        guard document.links.contains(where: { $0.id == id }) else { return }
        mutate { $0.links.removeAll { $0.id == id } }
        if selectedLinkID == id { selectedLinkID = nil }
        notify("已刪除關聯線")
    }

    public func setLinkLabel(id: UUID, to label: String) {
        guard document.links.first(where: { $0.id == id })?.label != label else { return }
        mutate { doc in
            if let i = doc.links.firstIndex(where: { $0.id == id }) {
                doc.links[i].label = label
            }
        }
    }

    /// Moves a node among its siblings to the given index (pre-adjusted for the removed item).
    public func moveSibling(id: UUID, toIndex rawIndex: Int) {
        guard id != document.root.id,
              let parent = document.root.parent(of: id),
              let currentIndex = parent.children.firstIndex(where: { $0.id == id }) else { return }
        var target = rawIndex
        if currentIndex < target { target -= 1 }
        target = max(0, min(target, parent.children.count - 1))
        guard target != currentIndex else { return }
        mutate { doc in
            doc.root.update(parent.id) { node in
                let item = node.children.remove(at: currentIndex)
                node.children.insert(item, at: target)
            }
        }
        selection = id
    }

    // MARK: - Search

    @Published public var showSearch = false
    @Published public var showHelp = false
    @Published public var printRequest = false
    @Published public var zenMode = false
    @Published public var showInspector = false
    @Published public var inspectorTab = 0

    public func toggleOutline() {
        if showInspector && inspectorTab == 1 {
            showInspector = false
        } else {
            inspectorTab = 1
            showInspector = true
        }
    }

    public func toggleZen() {
        zenMode.toggle()
        if zenMode {
            showSearch = false
            showHelp = false
            stopEditing()
            // Give a clean, framed view of the whole map.
            NotificationCenter.default.post(name: .mindFlowFit, object: nil)
            notify("專注模式：按 Esc 或左上角按鈕離開")
        }
    }
    @Published public var showTemplatePicker = false
    @Published public var searchQuery = ""
    @Published public var searchResults: [UUID] = []
    @Published public var searchIndex = 0

    public func performSearch() {
        let query = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else {
            searchResults = []
            searchIndex = 0
            return
        }
        var ids: [UUID] = []
        func walk(_ node: MindNode) {
            if node.text.localizedCaseInsensitiveContains(query)
                || node.note.localizedCaseInsensitiveContains(query) {
                ids.append(node.id)
            }
            node.children.forEach(walk)
        }
        walk(document.root)
        // A matching link label pulls both endpoint nodes into the results.
        for link in document.links where link.label.localizedCaseInsensitiveContains(query) {
            if !ids.contains(link.from) { ids.append(link.from) }
            if !ids.contains(link.to) { ids.append(link.to) }
        }
        // Summary text matches bring the whole covered sibling run into focus.
        for s in document.summaries where s.text.localizedCaseInsensitiveContains(query) {
            if let parentNode = document.root.find(s.parentID),
               let startIndex = parentNode.children.firstIndex(where: { $0.id == s.startID }),
               let endIndex = parentNode.children.firstIndex(where: { $0.id == s.endID }) {
                for child in parentNode.children[startIndex...endIndex] where !ids.contains(child.id) {
                    ids.append(child.id)
                }
            }
        }
        searchResults = ids
        searchIndex = 0
        if let first = ids.first {
            // Clear branch focus so search results are fully visible.
            focusBranchID = nil
            expandTo(id: first)
            selection = first
        }
    }

    /// Expands every collapsed ancestor so the node becomes visible.
    public func expandTo(id: UUID) {
        var cursor: UUID? = id
        while let currentID = cursor, let parent = document.root.parent(of: currentID) {
            if parent.collapsed {
                mutate("expand:\\(id)") { doc in
                    doc.root.update(parent.id) { node in node.collapsed = false }
                }
            }
            cursor = parent.id
        }
    }

    /// Reorders tabs. `destination` is the insertion slot in the original ordering.
    public func moveTab(from source: Int, to destination: Int) {
        guard sessions.indices.contains(source),
              destination >= 0, destination <= sessions.count,
              destination != source, destination != source + 1 else { return }
        var reordered = sessions
        let item = reordered.remove(at: source)
        let insertIndex = destination > source ? destination - 1 : destination
        reordered.insert(item, at: insertIndex)
        sessions = reordered

        // Track where the active document landed.
        if activeIndex == source {
            activeIndex = insertIndex
        } else {
            var p = activeIndex
            if source < p { p -= 1 }
            if insertIndex <= p { p += 1 }
            activeIndex = p
        }
    }

    /// Closes every tab except the given one (each gets a recoverable disk copy).
    public func closeOtherTabs(keeping index: Int) {
        guard sessions.indices.contains(index) else { return }
        stashActive()
        for (position, session) in sessions.enumerated() where position != index {
            FileIO.writeRecoveryCopy(session.document)
            inactiveStacks.removeValue(forKey: session.id)
            inactiveSelections.removeValue(forKey: session.id)
        }
        let kept = sessions[index]
        sessions = [kept]
        loadFromSession(0)
        notify("已關閉其他分頁")
    }

    /// Closes every tab to the right of the given one.
    public func closeTabsToRight(_ index: Int) {
        guard sessions.indices.contains(index), index < sessions.count - 1 else { return }
        stashActive()
        let removedRange = (index + 1)..<sessions.count
        for position in removedRange {
            FileIO.write(sessions[position].document,
                         to: FileIO.tabsDirectory.appendingPathComponent("closed-\(UUID().uuidString).mindmap"))
            inactiveStacks.removeValue(forKey: sessions[position].id)
            inactiveSelections.removeValue(forKey: sessions[position].id)
        }
        sessions.removeSubrange(removedRange)
        if activeIndex > index {
            loadFromSession(index)
        }
        notify("已關閉右側 \(removedRange.count) 個分頁")
    }

    /// ⌘W semantics: close the tab; on the last tab, close the window.
    public func closeActiveTabOrWindow() {
        if sessions.count > 1 {
            closeTab(activeIndex)
        } else {
            NSApp.keyWindow?.performClose(nil)
        }
    }

    /// Opens a duplicate of the active tab.
    public func duplicateActiveTab() {
        var copy = document
        copy.title += " 副本"
        stashActive()
        sessions.append(EditorSession(document: copy))
        loadFromSession(sessions.count - 1)
        selection = copy.root.id
        notify("已建立分頁副本")
    }

    /// Collapses all sibling branches except the selected one.
    public func collapseOtherSiblings(id: UUID) {
        guard id != document.root.id,
              let parent = document.root.parent(of: id) else { return }
        mutate { doc in
            doc.root.update(parent.id) { p in
                for i in p.children.indices where p.children[i].id != id {
                    p.children[i].collapsed = true
                }
                // Ensure target is expanded
                if let idx = p.children.firstIndex(where: { $0.id == id }) {
                    p.children[idx].collapsed = false
                }
            }
        }
        notify("已收合其他分支")
    }

    /// Cycles through layout directions (logic → balanced → fishbone → bracket → logic).
    public func cycleDirection() {
        let all: [MapDirection] = [.logicRight, .balanced, .fishbone, .bracket]
        let current = MapDirection(rawValue: document.directionName) ?? .logicRight
        let nextIndex = (all.firstIndex(of: current)! + 1) % all.count
        setDirection(all[nextIndex])
    }

    public func cycleTab(_ offset: Int) {
        guard sessions.count > 1 else { return }
        switchTab(to: (activeIndex + offset + sessions.count) % sessions.count)
    }

    /// Counts non-overlapping case-insensitive matches (same semantics as the replacement).
    nonisolated private static func countMatches(_ source: String, of find: String) -> Int {
        guard !find.isEmpty else { return 0 }
        var count = 0
        var searchRange = source.startIndex..<source.endIndex
        while let found = source.range(of: find, options: .caseInsensitive, range: searchRange) {
            count += 1
            searchRange = found.upperBound..<source.endIndex
        }
        return count
    }

    public func replaceAll(_ find: String, with replaceText: String) {
        guard !find.isEmpty else { return }
        var totalReplaced = 0
        mutate { doc in
            func walkAndReplace(_ node: inout MindNode) {
                totalReplaced += Self.countMatches(node.text, of: find)
                if node.text.localizedCaseInsensitiveContains(find) {
                    node.text = node.text.replacingOccurrences(
                        of: find,
                        with: replaceText,
                        options: .caseInsensitive
                    )
                }
                if !node.note.isEmpty {
                    totalReplaced += Self.countMatches(node.note, of: find)
                    node.note = node.note.replacingOccurrences(
                        of: find,
                        with: replaceText,
                        options: .caseInsensitive
                    )
                }
                for i in node.children.indices {
                    walkAndReplace(&node.children[i])
                }
            }
            walkAndReplace(&doc.root)
            // Link labels participate in search, so they get replaced too.
            for i in doc.links.indices where doc.links[i].label.localizedCaseInsensitiveContains(find) {
                totalReplaced += Self.countMatches(doc.links[i].label, of: find)
                doc.links[i].label = doc.links[i].label.replacingOccurrences(
                    of: find,
                    with: replaceText,
                    options: .caseInsensitive)
            }
        }
        notify(totalReplaced == 0 ? "沒有找到符合的項目" : "已取代 \(totalReplaced) 處 ✓")
    }

    public func jumpToNextResult() {
        if searchResults.isEmpty { performSearch() }
        guard !searchResults.isEmpty else { return }
        searchIndex = (searchIndex + 1) % searchResults.count
        let target = searchResults[searchIndex]
        expandTo(id: target)
        selection = target
    }

    /// Deep-copies a subtree (new IDs) and inserts it after the original.
    @discardableResult
    public func duplicate(id: UUID) -> UUID? {
        guard id != document.root.id,
              let node = document.root.find(id),
              let parent = document.root.parent(of: id),
              let index = parent.children.firstIndex(where: { $0.id == id }) else { return nil }
        func reassign(_ source: MindNode) -> MindNode {
            var copy = source
            copy.id = UUID()
            copy.children = copy.children.map(reassign)
            return copy
        }
        let copy = reassign(node)
        mutate { doc in
            doc.root.update(parent.id) { p in
                p.children.insert(copy, at: index + 1)
            }
        }
        selection = copy.id
        flash(copy.id)
        notify("已複製整棵子樹")
        return copy.id
    }

    public func setColorTag(id: UUID, tag: String?) {
        guard document.root.contains(id) else { return }
        mutate { $0.root.update(id) { node in node.colorTag = tag } }
        notify(tag == nil ? "已清除顏色標記" : "已加上顏色標記")
    }

    /// Applies (or clears with nil) one color tag across an entire subtree.
    public func setSubtreeColorTag(id: UUID, tag: String?) {
        guard document.root.contains(id) else { return }
        var count = 0
        mutate { doc in
            doc.root.update(id) { root in
                func walk(_ node: inout MindNode) {
                    node.colorTag = tag
                    count += 1
                    for i in node.children.indices { walk(&node.children[i]) }
                }
                walk(&root)
            }
        }
        notify(tag == nil ? "已清除 \(count) 個主題的顏色標記" : "已為 \(count) 個主題加上顏色標記")
    }

    /// Stars (or unstars) an entire subtree.
    public func setSubtreeMark(id: UUID, to marked: Bool) {
        guard document.root.contains(id) else { return }
        var count = 0
        mutate { doc in
            doc.root.update(id) { root in
                func walk(_ node: inout MindNode) {
                    node.marked = marked
                    count += 1
                    for i in node.children.indices { walk(&node.children[i]) }
                }
                walk(&root)
            }
        }
        notify(marked ? "已為 \(count) 個主題加上星星" : "已移除 \(count) 個主題的星星")
    }

    // MARK: 概要括線（summary brackets）

    // MARK: 批次選取（multi-select lite）

    /// Nodes gathered via shift-click; separate from the primary selection so
    /// every existing single-node flow stays untouched.
    @Published public var batchSelection: Set<UUID> = []

    /// True when id participates in any active summary bracket range.
    public func toggleBatchMember(_ id: UUID) {
        guard document.root.contains(id) else { return }
        if batchSelection.contains(id) {
            batchSelection.remove(id)
        } else {
            batchSelection.insert(id)
        }
    }

    public func clearBatchSelection() {
        batchSelection.removeAll()
    }

    /// Deletes every node in the batch selection as a single atomic operation.
    /// Produces exactly one undo entry regardless of how many nodes are removed.
    public func deleteBatch() {
        let ids = batchSelection.subtracting([document.root.id]).filter { document.root.contains($0) }
        guard !ids.isEmpty else { return }
        mutate { doc in
            // Removing a parent absorbs its subtree; order is safe either way.
            for id in ids {
                let removed = doc.root.find(id)?.descendantIDs() ?? []
                var allRemoved = removed
                allRemoved.insert(id)
                _ = doc.root.remove(id)
                doc.links.removeAll { allRemoved.contains($0.from) || allRemoved.contains($0.to) }
            }
            pruneSummaries(doc: &doc)
        }
        clearBatchSelection()
        notify("已刪除 \(ids.count) 個主題（⌘Z 可復原）")
    }

    /// Applies one color tag to every node in the batch selection.
    public func setColorTagForBatch(tag: String?) {
        guard !batchSelection.isEmpty else { return }
        mutate { doc in
            for id in batchSelection {
                doc.root.update(id) { node in node.colorTag = tag }
            }
        }
        clearBatchSelection()
        notify(tag == nil ? "已清除批次色標 ✓" : "已為批次加上顏色標記 ✓")
    }

    /// Sets the same star state on every node in the batch selection.
    public func setMarkForBatch(to marked: Bool) {
        guard !batchSelection.isEmpty else { return }
        mutate { doc in
            for id in batchSelection {
                doc.root.update(id) { node in node.marked = marked }
            }
        }
        clearBatchSelection()
        notify(marked ? "已為批次加上星星 ✓" : "已移除批次的星星 ✓")
    }

    /// Adds a summary bracket spanning [startID … endID] among parentID's children.
    /// Returns the new summary id, or nil when the range is not a valid sibling run.
    @discardableResult
    public func addSummary(parentID: UUID, startID: UUID, endID: UUID) -> UUID? {
        guard let parent = document.root.find(parentID),
              let startIndex = parent.children.firstIndex(where: { $0.id == startID }),
              let endIndex = parent.children.firstIndex(where: { $0.id == endID }),
              startIndex < endIndex else { return nil }
        let summary = MindSummary(parentID: parentID, startID: startID, endID: endID)
        mutate { $0.summaries.append(summary) }
        notify("已建立概要括線")
        return summary.id
    }

    /// Creates a summary spanning ALL currently batch-selected siblings.
    /// All members must share the same parent; returns nil otherwise.
    @discardableResult
    public func addSummaryForBatch() -> UUID? {
        var parentRef: MindNode?
        for id in batchSelection {
            guard let p = document.root.parent(of: id) else { return nil }
            if let existing = parentRef {
                guard existing.id == p.id else {
                    notify("批次中的主題必須在同一層")
                    return nil
                }
            } else {
                parentRef = p
            }
        }
        guard let parent = parentRef, batchSelection.count >= 2 else { return nil }
        let sorted = batchSelection.sorted { a, b in
            let ia = parent.children.firstIndex(where: { $0.id == a }) ?? .max
            let ib = parent.children.firstIndex(where: { $0.id == b }) ?? .max
            return ia < ib
        }
        return addSummary(parentID: parent.id, startID: sorted.first!, endID: sorted.last!)
    }

    /// Convenience: brackets this node together with its next sibling.
    @discardableResult
    public func addSummaryWithNextSibling(of id: UUID) -> UUID? {
        guard let parent = document.root.parent(of: id),
              let index = parent.children.firstIndex(where: { $0.id == id }),
              index + 1 < parent.children.count else {
            notify("這個主題沒有下一個兄弟")
            return nil
        }
        return addSummary(parentID: parent.id, startID: id, endID: parent.children[index + 1].id)
    }

    public func setSummaryText(id: UUID, to text: String) {
        guard document.summaries.first(where: { $0.id == id })?.text != text else { return }
        mutate { doc in
            if let i = doc.summaries.firstIndex(where: { $0.id == id }) {
                doc.summaries[i].text = text
            }
        }
    }

    public func removeSummary(id: UUID) {
        guard document.summaries.contains(where: { $0.id == id }) else { return }
        mutate { $0.summaries.removeAll { $0.id == id } }
        if selectedSummaryID == id { selectedSummaryID = nil }
        notify("已刪除概要括線")
    }

    /// Extends the bracket to include the next sibling after its current end.
    public func extendSummary(id: UUID) {
        guard let s = document.summaries.first(where: { $0.id == id }),
              let parent = document.root.find(s.parentID),
              let endIndex = parent.children.firstIndex(where: { $0.id == s.endID }),
              endIndex + 1 < parent.children.count else {
            notify("後面已經沒有主題可以納入了")
            return
        }
        let newEnd = parent.children[endIndex + 1].id
        mutate { doc in
            if let i = doc.summaries.firstIndex(where: { $0.id == id }) {
                doc.summaries[i].endID = newEnd
            }
        }
        notify("已納入下一個主題")
    }

    /// Pulls the bracket back so it ends at the previous sibling.
    /// Minimum coverage is two siblings; shrinking below that is rejected.
    public func shrinkSummary(id: UUID) {
        guard let s = document.summaries.first(where: { $0.id == id }),
              let parent = document.root.find(s.parentID),
              let startIndex = parent.children.firstIndex(where: { $0.id == s.startID }),
              let endIndex = parent.children.firstIndex(where: { $0.id == s.endID }),
              startIndex < endIndex else {
            notify("概要至少要涵蓋兩個主題")
            return
        }
        let newEnd = parent.children[endIndex - 1].id
        mutate { doc in
            if let i = doc.summaries.firstIndex(where: { $0.id == id }) {
                doc.summaries[i].endID = newEnd
            }
        }
        notify("已縮小概要範圍")
    }

    /// Drops summaries whose endpoints no longer sit under their parent (e.g. after deletions).
    private func pruneSummaries(doc: inout MindDocument) {
        doc.summaries.removeAll { s in
            guard let parent = doc.root.find(s.parentID) else { return true }
            return !parent.children.contains(where: { $0.id == s.startID })
                || !parent.children.contains(where: { $0.id == s.endID })
        }
    }

    /// Attaches (or clears) a node picture given as a data URL.
    /// Guards against oversized payloads so .mindmap files stay shareable.
    public func setNodeImage(id: UUID, to dataURL: String?) {
        guard document.root.contains(id) else { return }
        if let payload = dataURL, payload.count > 2_800_000 {
            notify("這張圖太大了（上限約 2 MB），請先縮小再試")
            return
        }
        mutate { $0.root.update(id) { node in
            node.image = (dataURL?.isEmpty == false) ? dataURL : nil
        } }
        if dataURL?.isEmpty == false {
            notify("已附上圖片 ✓")
        }
    }
    /// Sets (or clears with an empty string) the node's web link.
    public func setNodeURL(id: UUID, to urlString: String) {
        guard document.root.contains(id) else { return }
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        mutate { $0.root.update(id) { node in
            node.url = trimmed.isEmpty ? nil : trimmed
        } }
    }

    /// Wraps only the selected node in a new parent (Xmind Command+Enter).
    @discardableResult
    public func insertParent(id: UUID) -> UUID? {
        guard id != document.root.id,
              let node = document.root.find(id),
              let parentNode = document.root.parent(of: id),
              let index = parentNode.children.firstIndex(where: { $0.id == id }) else { return nil }
        let newParent = MindNode(text: "")
        mutate { doc in
            var wrapper = newParent
            wrapper.children = [node]
            doc.root.update(parentNode.id) { parent in
                parent.children[index] = wrapper
            }
        }
        selection = newParent.id
        editingID = newParent.id
        flash(newParent.id)
        notify("已插入父主題，直接輸入文字")
        return newParent.id
    }

    /// Inserts an empty child under the given node (outline Tab key).
    @discardableResult
    public func insertChildUnder(id: UUID) -> UUID? {
        guard document.root.contains(id) else { return nil }
        let newNode = MindNode(text: "")
        mutate { doc in
            doc.root.update(id) { node in
                node.children.append(newNode)
                node.collapsed = false
            }
        }
        selection = newNode.id
        flash(newNode.id)
        return newNode.id
    }

    /// Inserts an empty sibling directly after the given node (outline quick-entry).
    @discardableResult
    public func insertSiblingAfter(id: UUID) -> UUID? {
        guard id != document.root.id,
              let parentNode = document.root.parent(of: id),
              document.root.contains(id) else { return nil }
        let newNode = MindNode(text: "")
        mutate { doc in
            doc.root.update(parentNode.id) { parent in
                if let index = parent.children.firstIndex(where: { $0.id == id }) {
                    parent.children.insert(newNode, at: parent.children.index(after: index))
                } else {
                    parent.children.append(newNode)
                }
            }
        }
        selection = newNode.id
        flash(newNode.id)
        return newNode.id
    }

    /// Copies the whole map as OPML straight to the clipboard.
    public func copyAsOPML() {
        let opml = MapExporter.opml(document)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(opml, forType: .string)
        notify("已複製 OPML 到剪貼簿 ✓")
    }


    /// Opens the node's URL in the default browser.
    /// Normalizes user-typed URLs by adding `https://` when no scheme is present,
    /// so "example.com" opens like browsers would. Returns nil when unparseable.
    public static func makeOpenableURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let hasScheme = trimmed.range(of: "^[a-zA-Z][a-zA-Z0-9+.-]*:", options: .regularExpression) != nil
        return URL(string: hasScheme ? trimmed : "https://" + trimmed)
    }

    public func openURL(id: UUID) {
        guard let node = document.root.find(id),
              let urlString = node.url else {
            notify("這個主題沒有網址")
            return
        }
        guard let url = Self.makeOpenableURL(urlString) else {
            notify("網址格式無效，無法開啟")
            return
        }
        NSWorkspace.shared.open(url)
    }

    public func toggleMark(id: UUID) {
        guard document.root.contains(id) else { return }
        mutate { doc in
            doc.root.update(id) { node in node.marked.toggle() }
        }
        notify(document.root.find(id)?.marked == true ? "已加上星星 ⭐️" : "已移除星星")
    }

    private func flash(_ id: UUID?) {
        recentlyAddedID = id
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 450_000_000)
            if self?.recentlyAddedID == id { self?.recentlyAddedID = nil }
        }
    }

    // MARK: - Search

    public func focusAndSelectCenter() {
        focusBranchID = nil
        batchSelection.removeAll()
        selection = document.root.id
        NotificationCenter.default.post(name: .mindFlowReset, object: nil)
    }

    public func selectParent() {
        lastNavWasKeyboard = true
        if let id = selection, let parent = document.root.parent(of: id) {
            selection = parent.id
        } else {
            selection = document.root.id
        }
    }

    public func selectChild() {
        lastNavWasKeyboard = true
        guard let id = selection, let node = document.root.find(id) else {
            selection = document.root.id
            return
        }
        if node.collapsed {
            toggleCollapse(id: id)
        } else if let first = node.children.first {
            selection = first.id
        }
    }

    public func selectSibling(offset: Int) {
        lastNavWasKeyboard = true
        guard let id = selection,
              id != document.root.id,
              let parent = document.root.parent(of: id),
              let index = parent.children.firstIndex(where: { $0.id == id }) else { return }
        let next = index + offset
        guard parent.children.indices.contains(next) else { return }
        selection = parent.children[next].id
    }

    // MARK: - Editing state

    func stopEditing() {
        editingID = nil
    }

    // MARK: - Documents

    public func newDocument() {
        mutate { $0 = .new() }
        filePath = nil
        selection = document.root.id
    }

    /// Creates a fresh document from one of the built-in templates.
    public func applyTemplate(_ name: String) {
        openInNewTab(MindTemplates.make(name))
        notify(name == "空白" ? "已建立空白心智圖" : "已建立「\(name)」範本")
    }

    @discardableResult
    public func save() -> Bool {
        var target = filePath
        if let path = filePath {
            guard FileIO.write(document, to: path) else {
                notify("⚠️ 儲存失敗，請確認磁碟可寫入")
                return false
            }
        } else {
            guard let url = FileIO.saveAs(document) else { return false }
            target = url
        }
        filePath = target
        dirty = false
        if let url = target {
            NSDocumentController.shared.noteNewRecentDocumentURL(url)
        }
        notify("已儲存 ✓")
        if let url = target {
            document.title = url.deletingPathExtension().lastPathComponent
        }
        return true
    }

    /// Copies the whole map as Markdown straight to the clipboard.
    /// Copies a single branch (node + descendants) as Markdown to clipboard.
    public func copyBranchAsMarkdown(id: UUID) {
        guard let node = document.root.find(id) else { return }
        let branchDoc = MindDocument(title: node.text, root: node)
        let md = MapExporter.markdown(branchDoc)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(md, forType: .string)
        notify("已複製分支 Markdown ✓")
    }

    public func copyAsMarkdown() {
        let md = MapExporter.markdown(document)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(md, forType: .string)
        notify("已複製 Markdown 到剪貼簿 ✓")
    }

    /// Opens a .mindmap file (via Finder double-click or drag) into a new tab.
    public func openFromURL(_ url: URL) {
        guard let doc = FileIO.load(from: url) else {
            notify("無法開啟「\(url.lastPathComponent)」，格式可能不正確")
            return
        }
        openInNewTab(doc, filePath: url)
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        notify("已開啟「\(url.lastPathComponent)」")
    }

    public func importMarkdown() {
        wrapUpPresentationIfActive(); batchSelection.removeAll()
        guard let (text, url) = FileIO.readText() else { return }
        guard var imported = MapImporter.markdown(text) else {
            notify("讀不出這個檔案，請確認是 Markdown 大綱")
            return
        }
        imported.title = url.deletingPathExtension().lastPathComponent
        mutate { $0 = imported }
        filePath = nil
        selection = imported.root.id
        dirty = true
        notify("已匯入 Markdown ✓")
    }

    public func open() {
        guard let (doc, url) = FileIO.openPanel() else { return }
        openInNewTab(doc, filePath: url)
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        notify("已開啟「\(url.lastPathComponent)」")
    }

    public func importOPML() {
        wrapUpPresentationIfActive(); batchSelection.removeAll()
        guard let (text, url) = FileIO.readText() else { return }
        guard var imported = MapImporter.opml(text) else {
            notify("讀不出這個檔案，請確認是 OPML 格式")
            return
        }
        imported.title = url.deletingPathExtension().lastPathComponent
        mutate { $0 = imported }
        filePath = nil
        selection = imported.root.id
        dirty = true
        notify("已匯入 OPML ✓")
    }

    public func importFreeMind() {
        wrapUpPresentationIfActive(); batchSelection.removeAll()
        guard let (text, url) = FileIO.readText() else { return }
        guard var imported = MapImporter.freemind(text) else {
            notify("讀不出這個檔案，請確認是 FreeMind (.mm) 格式")
            return
        }
        imported.title = url.deletingPathExtension().lastPathComponent
        mutate { $0 = imported }
        filePath = nil
        selection = imported.root.id
        dirty = true
        notify("已匯入 FreeMind ✓")
    }

}
