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
    @Published public var exportRequest: ExportFormat?
    @Published public var recentlyAddedID: UUID?
    @Published public var statusMessage: String?
    private var statusTask: Task<Void, Never>?

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
        case markdown, opml, png, pdf, pngTransparent, pngLarge
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

    private func stashActive() {
        guard sessions.indices.contains(activeIndex) else { return }
        sessions[activeIndex].document = document
        sessions[activeIndex].filePath = filePath
        sessions[activeIndex].dirty = dirty
        inactiveStacks[sessions[activeIndex].id] = (undoStack, redoStack)
        inactiveSelections[sessions[activeIndex].id] = selection
    }

    private func loadFromSession(_ index: Int) {
        guard sessions.indices.contains(index) else { return }
        activeIndex = index
        document = sessions[index].document
        filePath = sessions[index].filePath
        dirty = sessions[index].dirty
        (undoStack, redoStack) = inactiveStacks[sessions[index].id] ?? ([], [])
        selection = inactiveSelections[sessions[index].id] ?? document.root.id
        selectedLinkID = nil
        // Focus belongs to a specific document — never leak across tabs.
        focusBranchID = nil
        // Search results belong to a specific document — never leak across tabs.
        searchQuery = ""
        searchResults = []
        searchIndex = 0
        showSearch = false
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

    /// Writes every open tab to per-tab autosave slots.
    public func autosaveAllSessions() {
        var snapshot = sessions
        if snapshot.indices.contains(activeIndex) {
            snapshot[activeIndex].document = document
            snapshot[activeIndex].filePath = filePath
        }
        FileIO.autosaveTabs(snapshot.map { ($0.id, $0.document) })
    }

    public init() {
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
        func node(_ text: String, children: [MindNode] = []) -> MindNode {
            MindNode(text: text, children: children)
        }
        return MindDocument(
            title: "歡迎使用 MindFlow",
            root: MindNode(text: "歡迎使用 MindFlow 🎉", children: [
                node("選取我之後按 Tab，就能長出子主題"),
                node("按 Return 可以加一個隔壁的主題"),
                node("連點兩下直接改文字"),
                node("拖曳節點可以重新掛接或排序"),
                node("更多小技巧", children: [
                    node("⌘F 搜尋主題"),
                    node("⌘D 複製整棵子樹"),
                    node("⌘L 加上星星標記"),
                    node("不用按儲存，全部自動保存"),
                ]),
            ]))
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
        }
        if selection == id { selection = nil }
        stopEditing()
        notify("已刪除主題（⌘Z 可復原）")
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
        mutate { $0.root.update(id) { $0.collapsed.toggle() } }
    }

    /// Moves a node (with its subtree) under another node.
    public func move(id: UUID, toParent parentID: UUID) {
        guard id != document.root.id,
              id != parentID,
              !document.root.isAncestor(of: parentID) || parentID != id,
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
    }

    /// Expands so exactly `levels` layers of topics are visible.
    public func expandToLevel(_ levels: Int) {
        guard levels >= 1 else { return }
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

    /// Shifts a node's manual offset (used by ⌥-drag and ⌘-arrow keys).
    public func nudgeOffset(id: UUID, dx: CGFloat, dy: CGFloat) {
        guard document.root.contains(id), id != document.root.id else { return }
        let key = id.uuidString
        mutate("offset:\(key)") { doc in
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
        notify("已重設所有手動位置")
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
            notify("剪貼簿是空的")
            return
        }
        guard let imported = MapImporter.markdown(text) else {
            notify("無法解析剪貼簿內容")
            return
        }
        // Attach imported tree under the selected node (or root).
        let parentID = selection ?? document.root.id
        let importedChildren = imported.root.children
        guard !importedChildren.isEmpty else {
            notify("剪貼簿裡沒有可用的條列")
            return
        }
        mutate { doc in
            doc.root.update(parentID) { node in
                node.children.append(contentsOf: importedChildren)
            }
        }
        dirty = true
        notify("已從剪貼簿加入 \(importedChildren.count) 個主題 ✓")
    }

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
        searchResults = ids
        searchIndex = 0
        if let first = ids.first {
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

    public func cycleTab(_ offset: Int) {
        guard sessions.count > 1 else { return }
        switchTab(to: (activeIndex + offset + sessions.count) % sessions.count)
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

    /// Wraps the node in a brand-new parent at the same position.
    @discardableResult
    public func insertParent(id: UUID) -> UUID? {
        guard id != document.root.id,
              let node = document.root.find(id),
              let parentNode = document.root.parent(of: id),
              let index = parentNode.children.firstIndex(where: { $0.id == id }) else { return nil }
        let newParent = MindNode(text: "新主題")
        mutate { doc in
            var wrapper = newParent
            wrapper.children = [node]
            doc.root.update(parentNode.id) { parent in
                parent.children[index] = wrapper
            }
        }
        selection = newParent.id
        flash(newParent.id)
        notify("已插入父主題")
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

    func selectParent() {
        if let id = selection, let parent = document.root.parent(of: id) {
            selection = parent.id
        } else {
            selection = document.root.id
        }
    }

    func selectChild() {
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

    func selectSibling(offset: Int) {
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

    /// Writes the current document to the autosave location immediately.
    public func autosaveNow() {
        FileIO.autosave(document)
        dirty = false
    }

    public func open() {
        guard let (doc, url) = FileIO.openPanel() else { return }
        openInNewTab(doc, filePath: url)
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        notify("已開啟「\(url.lastPathComponent)」")
    }

    public func importOPML() {
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

    public func setTheme(_ id: String) {
        mutate { $0.themeName = id }
    }
}
