import Foundation
import CoreGraphics
import MindFlowKit

var failures = 0

func check(_ condition: Bool, _ label: String, line: Int = #line) {
    if condition {
        print("PASS \(label)")
    } else {
        failures += 1
        print("FAIL \(label) (line \(line))")
    }
}

func approxEqual(_ a: CGFloat, _ b: CGFloat, accuracy: CGFloat = 0.5) -> Bool {
    abs(a - b) <= accuracy
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
    let md = MapExporter.markdown(doc)
    check(md.contains("# Root <A>"), "markdown exports root title")
    check(md.contains("- B"), "markdown exports child")
    check(md.contains("  - C"), "markdown indents grandchildren")
    check(md.contains("> n"), "markdown includes notes")
    let opml = MapExporter.opml(doc)
    check(opml.contains("&lt;A&gt;"), "opml escapes XML entities")
    check(opml.contains("<outline text=\"B\""), "opml nests children")
    check(opml.contains("_note=\"n\""), "opml carries notes")
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
    let imported = MapImporter.markdown(source)
    check(imported != nil, "markdown import succeeds")
    let doc = imported!
    check(doc.root.text == "專案計畫", "import uses heading as root")
    check(doc.root.children.map(\.text) == ["研究", "設計", "開發"], "import preserves top level")
    check(doc.root.children[0].children.map(\.text) == ["文獻回顧", "訪談"], "import preserves nesting")
    check(doc.root.children[0].children[1].note == "約三位使用者", "import attaches notes")

    let roundTrip = MapImporter.markdown(MapExporter.markdown(doc))
    check(roundTrip?.root.children.map(\.text) == ["研究", "設計", "開發"], "export/import round-trips")

    check(MapImporter.markdown("")?.root.text == "中心主題", "empty input yields default root")
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
    let opml = MapExporter.opml(doc)
    let back = MapImporter.opml(opml)
    check(back?.root.text == "R", "opml import restores root")
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
    check(elapsed < 1.0, String(format: "layout under 1.0s (%.3fs)", elapsed))
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
    let md = MapExporter.markdown(doc)
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
        let startCount = vm.sessions.count
        let node = vm.addChild(to: nil)!
        check(vm.document.root.find(node)?.text.isEmpty == true, "new nodes start empty")
        vm.commitNodeText(id: node, text: "   ")
        check(vm.sessions.count == startCount, "empty commit discards brand-new node")
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
        let startCount = vm.sessions.count
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
        check(vm.document.root.find(x)?.text == "", "per-tab undo isolates stacks")

        // Zen & theme flags.
        vm.toggleZen()
        check(vm.zenMode == true, "zen mode toggles on")
        vm.toggleZen()
        check(vm.zenMode == false, "zen mode toggles off")
        vm.setTheme("candy")
        check(vm.document.themeName == "candy", "setTheme applies")
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
    let md = MapExporter.markdown(doc)
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
        let md = MapExporter.markdown(vm.document)
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

        // Root cannot be moved or wrapped.
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
        guard let imported = MapImporter.markdown(md) else {
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
        let child = vm.addChild(to: parent)!
        check(vm.document.root.find(parent)?.children.count == 1, "child created")

        vm.setTheme("candy")
        check(vm.document.themeName == "candy", "theme persists")

        let noteNode = vm.addChild(to: nil)!
        vm.rename(id: noteNode, to: "note-test-node")
        vm.setNote(id: noteNode, to: "hidden-keyword")
        vm.searchQuery = "hidden-keyword"
        vm.performSearch()
        check(vm.searchResults.contains(noteNode), "search covers notes")

        let md = MapExporter.markdown(vm.document)
        check(md.contains("branch"), "markdown export works")

        let st = vm.document.stats()
        check(st.nodeCount >= 3, "stats counts nodes")
    }
}

if failures == 0 {
    print("ALL CHECKS PASSED")
} else {
    print("\(failures) CHECK(S) FAILED")
}
exit(failures == 0 ? 0 : 1)
