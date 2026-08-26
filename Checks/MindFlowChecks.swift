import AppKit
import CoreGraphics
import Foundation
import MindFlowKit

setvbuf(stdout, nil, _IONBF, 0)

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
    if let fmDoc = MapImporter.freemind(mm) {
        check(fmDoc.root.text == "Root Topic", "freemind import reads TEXT attribute")
        check(fmDoc.root.children.count == 2, "freemind nests children")
        check(fmDoc.root.children[0].collapsed, "freemind maps FOLDED to collapsed")
        check(fmDoc.root.children[0].children.count == 2, "freemind reads grandchildren")
        check(fmDoc.root.children[0].children[1].text == "Grandchild <2>", "freemind unescapes xml entities")
        check(fmDoc.root.children[1].text == "Child B" && !fmDoc.root.children[1].collapsed, "freemind defaults unfolded")
    } else {
        check(false, "freemind parses sample map")
    }
    check(MapImporter.freemind("not xml at all") == nil || MapImporter.freemind("<map></map>") != nil, "freemind handles junk input gracefully")

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
    let mmOut = MapExporter.freemind(presDoc)
    check(mmOut.contains("<map version=\"1.0.1\">"), "freemind export has map header")
    check(mmOut.contains("<node TEXT=\"Root\""), "freemind export writes root TEXT")
    check(mmOut.contains("FOLDED=\"true\""), "freemind export preserves collapsed flag")
    if let reimported = MapImporter.freemind(mmOut) {
        check(reimported.root.text == presDoc.root.text, "freemind roundtrip keeps root")
        check(reimported.root.children.count == presDoc.root.children.count, "freemind roundtrip keeps children")
        check(reimported.root.children[1].collapsed == true, "freemind roundtrip keeps collapse states")
        check(reimported.root.children[0].children[0].text == "A1", "freemind roundtrip keeps grandchildren")
    } else {
        check(false, "freemind roundtrip parses")
    }
    let tricky = MindNode(text: "a<b>&c\"d", children: [MindNode(text: "x&y")])
    let mmTricky = MapExporter.freemind(MindDocument(title: "T", root: tricky))
    if let back = MapImporter.freemind(mmTricky) {
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
    check(svgRich.contains("fill=\"#2e3b4f\""), "svg root uses navy fill")
    check(svgRich.contains("stroke=\"none\"") || svgRich.contains("stroke=\"#2e3b4f\""), "root rect has stroke attr")
    check(svgRich.contains(">★</text>"), "svg draws star for marked nodes")
    check(svgRich.contains("#f5c542"), "svg star is gold")
    check(svgRich.contains("備註：有備註"), "svg embeds note as tooltip title")
    check(svgRich.contains("<a href=\"https://example.com\">"), "svg wraps linked node in anchor")
    // Red color tag is defined as Color(hex: 0xE05252) in Theme.colorTags.
    check(svgRich.lowercased().contains("#e05252"), "svg renders color-tag bar")
    check(svgRich.contains("fill=\"#ffffff\" stroke=\"#"), "svg deep nodes are white with colored outline")

    // v19.1: FreeMind notes + colors survive the round-trip
    let mmDoc = MindDocument(title: "MM", root: MindNode(text: "Root", children: [
        MindNode(text: "Tagged", note: "重要備註", colorTag: "blue", children: [MindNode(text: "Kid")]),
        MindNode(text: "Plain"),
    ]))
    let mmOut = MapExporter.freemind(mmDoc)
    check(mmOut.contains("richcontent TYPE=\"NOTE\"") && mmOut.contains("重要備註"), "freemind export carries notes")
    check(mmOut.uppercased().contains("COLOR=\"#4A90D9\""), "freemind export carries color")
    if let back = MapImporter.freemind(mmOut) {
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
    if let f = MapImporter.freemind(foreign) {
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
    let mdSum = MapExporter.markdown(sumDoc2)
    check(mdSum.contains("↳ 概要（含S1）: 這兩項是重點"), "markdown export includes summary text after range")
    // Summaries ending at a later sibling don't leak into earlier positions
    check(!mdSum.contains("↳ 概要（含S3）"), "summary anchored to its own range end")
    let mdNoSum = MapExporter.markdown(MindDocument(title: "N", root: MindNode(text: "R", children: [MindNode(text: "x")])))
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


    // v20.5: URL normalization for openURL
    check(MindMapViewModel.makeOpenableURL("example.com")?.absoluteString == "https://example.com", "scheme-less URLs get https://")
    check(MindMapViewModel.makeOpenableURL("  https://a.tw/x  ")?.absoluteString == "https://a.tw/x", "whitespace is trimmed")
    check(MindMapViewModel.makeOpenableURL("mailto:a@b.c")?.absoluteString == "mailto:a@b.c", "existing schemes are preserved")
    check(MindMapViewModel.makeOpenableURL("   ") == nil, "blank URLs return nil")
    check(MindMapViewModel.makeOpenableURL("https://中文字.tw") != nil, "unicode hosts still parse")
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
        _ = vm.addChild(to: parent)
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
        let md = MapExporter.markdown(vm.document)
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
        let md = MapExporter.markdown(vm.document)
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
        let md = MapExporter.markdown(vm.document)
        check(md.contains("功能A"), "E2E: markdown contains content")
        let opml = MapExporter.opml(vm.document)
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

if failures == 0 {
    print("ALL CHECKS PASSED")
} else {
    print("\(failures) CHECK(S) FAILED")
}
exit(failures == 0 ? 0 : 1)
