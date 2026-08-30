import SwiftUI
import UniformTypeIdentifiers

struct ReparentDrag: Equatable {
    let id: UUID
    let source: CGPoint
    let current: CGPoint
    var translation: CGSize = .zero
}

struct ReorderHint: Equatable {
    let targetID: UUID
    let after: Bool
    let y: CGFloat
    let minX: CGFloat
    let maxX: CGFloat
    let targetIndex: Int
}

struct NodeItem: Identifiable {
    let node: MindNode
    let layout: NodeLayout
    var id: UUID { node.id }
}

struct MapCanvasView: View {
    @EnvironmentObject var vm: MindMapViewModel

    @State private var pan: CGSize = .zero
    @State private var lastPan: CGSize = .zero
    @State private var scale: CGFloat = 1
    @State private var lastZoom: CGFloat = 1
    @State private var drag: ReparentDrag?
    @State private var reorderHint: ReorderHint?
    @State private var canvasSize: CGSize = .zero
    @State private var freeMoveID: UUID?
    @State private var textDropActive = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let zoomRange = CanvasFit.zoomRange

    var body: some View {
        GeometryReader { geo in
            let layouts = LayoutEngine.layout(root: vm.document.root, direction: vm.direction,
                                              offsets: vm.document.offsets)
            // (offsets already applied here — single source of truth)
            let theme = Theme.named(vm.document.themeName)
            let bounds = LayoutEngine.contentBounds(of: layouts).insetBy(dx: -180, dy: -140)
            let origin = CGPoint(x: -bounds.minX, y: -bounds.minY)
            let items = nodeItems(layouts: layouts)
            let dropTarget = drag.flatMap { hitTest(point: $0.current, draggedID: $0.id, layouts: layouts) }
            let focusIDs = vm.focusSet()

            ZStack {
                self.backgroundLayer(layouts: layouts, bounds: bounds,
                                 geoSize: geo.size, origin: origin)

                mapContent(items: items, layouts: layouts, theme: theme, bounds: bounds,
                           origin: origin, geoSize: geo.size, dropTarget: dropTarget, focusIDs: focusIDs)
            }
            // The map container is deliberately larger than the viewport, and a ZStack takes
            // the size of its largest child, so this stack grew to the container's size.
            // GeometryReader pins oversized content to its top-leading corner rather than
            // centring it, which parked the map half its overflow down and to the right and
            // pushed the lower nodes off the bottom of the window. Pinning the stack to the
            // viewport puts the centring back where it belongs.
            .frame(width: geo.size.width, height: geo.size.height)
            .overlay(alignment: .bottomTrailing) { zoomControls }
            .overlay { dropHighlightBorder }
            .animation(reduceMotion ? nil : .spring(response: 0.3), value: vm.statusMessage)
            .onAppear {
                canvasSize = geo.size
                fitToView(bounds: bounds, geo: geo.size)
            }
            .onChange(of: geo.size) { canvasSize = $0 }
            .onChange(of: vm.selection) { id in
                guard vm.lastNavWasKeyboard else { return }
                revealNode(id, layouts: layouts, bounds: bounds, geo: geo.size)
                vm.lastNavWasKeyboard = false
            }
            .onReceive(NotificationCenter.default.publisher(for: .mindFlowFit)) { _ in
                fitToView(bounds: bounds, geo: geo.size)
            }
            .overlay(alignment: .center) { emptyStateHint(items: items) }
            .onHover { hovering in vm.isCursorOverCanvas = hovering }
            .overlay(alignment: .bottom) { statusToast }
            .overlay {
                if let rect = lassoRect {
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.08))
                        .overlay(
                            Rectangle().stroke(Color.accentColor,
                                               style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .allowsHitTesting(false)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .mindFlowPan)) { note in
                let dx = note.userInfo?["dx"] as? Double ?? 0
                let dy = note.userInfo?["dy"] as? Double ?? 0
                pan = CGSize(width: lastPan.width + CGFloat(dx) * 2,
                             height: lastPan.height - CGFloat(dy) * 2)
                lastPan = pan
            }
            .onReceive(NotificationCenter.default.publisher(for: .mindFlowZoom)) { note in
                let factor = note.userInfo?["factor"] as? CGFloat ?? 1
                scale = min(Self.zoomRange.upperBound, max(Self.zoomRange.lowerBound, scale * factor))
                lastZoom = scale
            }
            .onReceive(NotificationCenter.default.publisher(for: .mindFlowReset)) { _ in
                scale = 1
                lastZoom = 1
                pan = .zero
                lastPan = .zero
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: - Layers

    private func backgroundLayer(layouts: [UUID: NodeLayout], bounds: CGRect,
                                 geoSize: CGSize, origin: CGPoint) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(panGesture(layouts: layouts, bounds: bounds,
                                geoSize: geoSize, origin: origin))
            .simultaneousGesture(zoomGesture)
            .onTapGesture {
                vm.stopEditing()
                vm.selection = nil
                vm.showSearch = false
            }
    }

    private func connectionsCanvas(items: [NodeItem], layouts: [UUID: NodeLayout],
                                   theme: Theme, origin: CGPoint,
                                   focusIDs: Set<UUID>) -> some View {
        MapConnectionsView(items: items, layouts: layouts, theme: theme,
                           origin: origin, direction: vm.direction, focusIDs: focusIDs)
    }

    @ViewBuilder
    private func dragIndicator(origin: CGPoint) -> some View {
        if let dragState = drag {
            Path { path in
                path.move(to: CGPoint(x: dragState.source.x + origin.x, y: dragState.source.y + origin.y))
                path.addLine(to: CGPoint(x: dragState.current.x + origin.x, y: dragState.current.y + origin.y))
            }
            .stroke(Color.secondary, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            .allowsHitTesting(false)
        }
    }

    /// NOT WIRED UP. This was dead code in the original codebase (defined, never called),
    /// and wiring it in on 2026-08-29 coincided with a report of a blank canvas. The
    /// coordinate inversion below has therefore never been verified against a running app.
    /// Do not enable it without a rendering test that proves nodes still appear.
    /// The measured layout win came from LayoutEngine memoization, not from culling.
    private func visibleItems(items: [NodeItem], geoSize: CGSize, bounds: CGRect) -> [NodeItem] {
        let origin = CGPoint(x: -bounds.minX, y: -bounds.minY)
        let center = CGPoint(x: bounds.width / 2, y: bounds.height / 2)

        func toMap(_ screen: CGPoint) -> CGPoint {
            let sx = screen.x - (geoSize.width - bounds.width) / 2 - pan.width
            let sy = screen.y - (geoSize.height - bounds.height) / 2 - pan.height
            let qx = center.x + (sx - center.x) / scale
            let qy = center.y + (sy - center.y) / scale
            return CGPoint(x: qx - origin.x, y: qy - origin.y)
        }
        let a = toMap(CGPoint.zero)
        let b = toMap(CGPoint(x: geoSize.width, y: geoSize.height))
        let viewport = CGRect(x: min(a.x, b.x) - 200, y: min(a.y, b.y) - 150,
                              width: abs(a.x - b.x) + 400, height: abs(a.y - b.y) + 300)
        return items.filter { viewport.intersects($0.layout.frame) }
    }

    private func nodeView(item: NodeItem, theme: Theme, dropTarget: UUID?, origin: CGPoint,
                          layouts: [UUID: NodeLayout], geoSize: CGSize, bounds: CGRect,
                          isSearchHit: Bool, dimmed: Bool = false, colorTag: String? = nil,
                          onToggleCollapse: (() -> Void)? = nil) -> some View {
        NodeView(node: item.node,
                 layout: item.layout,
                 branchColor: theme.color(forIndex: item.layout.colorIndex),
                 isSelected: vm.selection == item.node.id,
                 isBatchMember: vm.batchSelection.contains(item.node.id),
                 isEditing: vm.editingID == item.node.id,
                 isDropTarget: dropTarget == item.node.id,
                 onToggleCollapse: onToggleCollapse,
                 isFresh: vm.recentlyAddedID == item.node.id,
                 isDragging: drag?.id == item.node.id,
                 dragOffset: drag?.id == item.node.id ? drag?.translation : nil,
                 isSearchHit: vm.searchResults.contains(item.node.id),
                 colorTag: item.node.colorTag,
                 onCancelEdit: { text in
                     vm.cancelNodeEditing(id: item.node.id, draft: text)
                 },
                 onCommitEdit: { text in
                     guard text.trimmingCharacters(in: .whitespacesAndNewlines)
                           != item.node.text.trimmingCharacters(in: .whitespacesAndNewlines) else {
                         vm.stopEditing()
                         return
                     }
                     vm.commitNodeText(id: item.node.id, text: text)
                     vm.stopEditing()
                 },
                 onSubmitEdit: { text in
                     // D2: Return inside the editor means "done — now the next sibling".
                     // Empty text is excluded so a blank node cannot chain blank siblings.
                     let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                     if trimmed != item.node.text.trimmingCharacters(in: .whitespacesAndNewlines) {
                         vm.commitNodeText(id: item.node.id, text: text)
                     }
                     vm.stopEditing()
                     if !trimmed.isEmpty, item.node.id != vm.document.root.id {
                         vm.addSibling(of: item.node.id)
                     }
                 })
        .contextMenu {
            Button("加入子主題") { vm.addChild(to: item.node.id) }
            if item.node.id != vm.document.root.id {
                Button("加入兄弟主題") { vm.addSibling(of: item.node.id) }
            }
            if item.node.id != vm.document.root.id {
                Button("加入概要括線（含下一個兄弟）") { _ = vm.addSummaryWithNextSibling(of: item.node.id) }
            }
            if vm.document.offsets[item.node.id.uuidString] != nil {
                Button("重設此節點位置") { vm.clearOffset(id: item.node.id) }
            }
            if let selected = vm.selection, selected != item.node.id,
               !vm.document.links.contains(where: {
                   ($0.from == selected && $0.to == item.node.id) || ($0.from == item.node.id && $0.to == selected)
               }) {
                Button("從選取主題建立關聯線") { vm.addLink(from: selected, to: item.node.id) }
            }
            Button(item.node.marked ? "移除星星" : "加上星星") { vm.toggleMark(id: item.node.id) }
            Menu("色標") {
                ForEach(Theme.colorTags, id: \.key) { tag in
                    Button(tag.name) { vm.setColorTag(id: item.node.id, tag: tag.key) }
                }
                Divider()
                Button("清除色標") { vm.setColorTag(id: item.node.id, tag: nil) }
            }
            Menu("子樹批次") {
                Menu("全部加上色標") {
                    ForEach(Theme.colorTags, id: \.key) { tag in
                        Button(tag.name) { vm.setSubtreeColorTag(id: item.node.id, tag: tag.key) }
                    }
                    Divider()
                    Button("清除色標") { vm.setSubtreeColorTag(id: item.node.id, tag: nil) }
                }
                Button("整棵子樹加星星") { vm.setSubtreeMark(id: item.node.id, to: true) }
                Button("移除整棵子樹的星星") { vm.setSubtreeMark(id: item.node.id, to: false) }
            }
            Button("複製此分支 Markdown") { vm.copyBranchAsMarkdown(id: item.node.id) }
            if item.node.id != vm.document.root.id {
                Button("插入父主題") { vm.insertParent(id: item.node.id) }
                Button("收合同類兄弟") { vm.collapseOtherSiblings(id: item.node.id) }
            }
            Divider()
            if !item.node.children.isEmpty {
                Button(item.node.collapsed ? "展開" : "收合") { vm.toggleCollapse(id: item.node.id) }
            }
            Divider()
            if vm.focusBranchID == nil {
                Button("聚焦此分支") { vm.focusBranchID = item.node.id }
            } else {
                Button("取消聚焦") { vm.focusBranchID = nil }
            }
            Divider()
            if !vm.batchSelection.isEmpty {
                Menu("批次（\(vm.batchSelection.count) 個）") {
                    Menu("全部加上色標") {
                        ForEach(Theme.colorTags, id: \.key) { tag in
                            Button(tag.name) { vm.setColorTagForBatch(tag: tag.key) }
                        }
                        Divider()
                        Button("清除色標") { vm.setColorTagForBatch(tag: nil) }
                    }
                    Button("整批加星星") { vm.setMarkForBatch(to: true) }
                    Button("移除整批的星星") { vm.setMarkForBatch(to: false) }
                    Divider()
                    Button("清空批次選取") { vm.clearBatchSelection() }
                    Divider()
                    Button("刪除整批", role: .destructive) { vm.deleteBatch() }
                }
                Divider()
            }
            Button("為批次建立概要括線") { _ = vm.addSummaryForBatch() }
            Divider()
            if item.node.id != vm.document.root.id {
                Button("刪除", role: .destructive) { vm.delete(id: item.node.id) }
            }
        }
        .position(x: item.layout.center.x + origin.x, y: item.layout.center.y + origin.y)
        // Double-tap gesture removed (v25.8): it forced a ~300ms delay on every
        // single tap while SwiftUI waited to disambiguate single vs double.
        // Editing entry works via "click selected node again" pattern below.
        .gesture(nodePointerGesture(item: item, origin: origin, layouts: layouts,
                                    geoSize: geoSize, bounds: bounds))
    }

    // MARK: - Gestures

    /// Shift+drag on empty canvas draws a lasso rectangle that batch-selects
    /// every intersecting node; plain drag keeps panning the canvas.
    @State private var lassoMode: Bool?
    @State private var lassoRect: CGRect?

    private func panGesture(layouts: [UUID: NodeLayout], bounds: CGRect,
                            geoSize: CGSize, origin: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                if lassoMode == nil { lassoMode = isShiftHeld() }
                if lassoMode == true {
                    let start = value.startLocation
                    let current = value.location
                    lassoRect = CGRect(x: min(start.x, current.x), y: min(start.y, current.y),
                                       width: abs(current.x - start.x),
                                       height: abs(current.y - start.y))
                    return
                }
                pan = CGSize(width: lastPan.width + value.translation.width,
                             height: lastPan.height + value.translation.height)
            }
            .onEnded { value in
                if lassoMode == true {
                    let rect = CGRect(x: min(value.startLocation.x, value.location.x),
                                      y: min(value.startLocation.y, value.location.y),
                                      width: abs(value.location.x - value.startLocation.x),
                                      height: abs(value.location.y - value.startLocation.y))
                    completeLasso(geoRect: rect, layouts: layouts, bounds: bounds,
                                  geoSize: geoSize, origin: origin)
                } else {
                    lastPan = pan
                }
                lassoMode = nil
                lassoRect = nil
            }
    }

    private func completeLasso(geoRect: CGRect, layouts: [UUID: NodeLayout],
                               bounds: CGRect, geoSize: CGSize, origin: CGPoint) {
        guard !geoRect.isNull, geoRect.width > 4, geoRect.height > 4 else { return }
        let center = CGPoint(x: bounds.width / 2, y: bounds.height / 2)
        func toMap(_ screen: CGPoint) -> CGPoint {
            let sx = screen.x - (geoSize.width - bounds.width) / 2 - pan.width
            let sy = screen.y - (geoSize.height - bounds.height) / 2 - pan.height
            let qx = center.x + (sx - center.x) / scale
            let qy = center.y + (sy - center.y) / scale
            return CGPoint(x: qx - origin.x, y: qy - origin.y)
        }
        let a = toMap(geoRect.origin)
        let b = toMap(CGPoint(x: geoRect.maxX, y: geoRect.maxY))
        let mapRect = CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
                             width: abs(a.x - b.x), height: abs(a.y - b.y)).insetBy(dx: -8, dy: -8)
        var hits: Set<UUID> = []
        for (id, layout) in layouts where mapRect.intersects(layout.frame) {
            hits.insert(id)
        }
        vm.batchSelection.formUnion(hits)
        if !hits.isEmpty { vm.notify("已框選 \(hits.count) 個主題") }
    }

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = min(Self.zoomRange.upperBound, max(Self.zoomRange.lowerBound, lastZoom * value))
            }
            .onEnded { _ in lastZoom = scale }
    }

    /// Below this displacement a pointer sequence is a click, not a drag.
    private static let dragThreshold: CGFloat = 4
    @State private var pointerMoved = false

    /// A node used to carry both .onTapGesture and DragGesture(minimumDistance: 8).
    /// SwiftUI has to disambiguate those against each other, which made drags skip on
    /// the first frames and let taps get eaten. One pointer sequence, one state machine:
    /// under the threshold it is a click, over it a drag.
    private func nodePointerGesture(item: NodeItem, origin: CGPoint, layouts: [UUID: NodeLayout],
                                    geoSize: CGSize, bounds: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !pointerMoved {
                    let moved = max(abs(value.translation.width), abs(value.translation.height))
                    guard moved > Self.dragThreshold else { return }
                    pointerMoved = true
                }
                dragChanged(value, item: item, layouts: layouts, geoSize: geoSize, bounds: bounds)
            }
            .onEnded { _ in
                defer {
                    drag = nil
                    reorderHint = nil
                    freeMoveID = nil
                    pointerMoved = false
                }
                guard pointerMoved else {
                    handleNodeClick(item: item)
                    return
                }
                dragEnded(layouts: layouts)
            }
    }

    private func handleNodeClick(item: NodeItem) {
        if isShiftHeld() {
            if !vm.presentationActive { vm.toggleBatchMember(item.node.id) }
            return
        }
        if vm.editingID != nil && vm.editingID != item.node.id { vm.stopEditing() }
        if vm.selection == item.node.id {
            // Second click on the selected node starts editing — no double-click needed.
            vm.editingID = item.node.id
        } else {
            vm.selection = item.node.id
        }
    }

    private func dragChanged(_ value: DragGesture.Value, item: NodeItem,
                             layouts: [UUID: NodeLayout], geoSize: CGSize, bounds: CGRect) {
        // Hold Option while dragging for free placement.
        if NSEvent.modifierFlags.contains(.option) {
            freeMoveID = item.node.id
        }
        // Keep coordinates in map space; the drawing layer applies origin.
        let current = CGPoint(x: item.layout.center.x + value.translation.width / scale,
                              y: item.layout.center.y + value.translation.height / scale)
        drag = ReparentDrag(id: item.node.id, source: item.layout.center, current: current,
                            translation: value.translation)
        if freeMoveID == nil {
            reorderHint = reorderHint(at: current, draggedID: item.node.id, layouts: layouts)
            autoScrollToward(current, geoSize: geoSize, bounds: bounds)
        }
    }

    private func dragEnded(layouts: [UUID: NodeLayout]) {
        guard let dragState = drag else { return }
        if freeMoveID == dragState.id {
            vm.nudgeOffset(id: dragState.id,
                           dx: dragState.translation.width / scale,
                           dy: dragState.translation.height / scale)
        } else if let target = hitTest(point: dragState.current, draggedID: dragState.id, layouts: layouts) {
            vm.move(id: dragState.id, toParent: target)
        } else if let hint = reorderHint {
            vm.moveSibling(id: dragState.id, toIndex: hint.targetIndex)
        }
    }

    /// While dragging over a sibling's row (but not onto a node), suggest a reordering slot.
    private func reorderHint(at point: CGPoint, draggedID: UUID, layouts: [UUID: NodeLayout]) -> ReorderHint? {
        guard hitTest(point: point, draggedID: draggedID, layouts: layouts) == nil,
              let parent = vm.document.root.parent(of: draggedID),
              let draggedSide = layouts[draggedID]?.side else { return nil }
        for sibling in parent.children where sibling.id != draggedID {
            guard let layout = layouts[sibling.id],
                  layout.side == draggedSide,
                  point.y >= layout.frame.minY - LayoutEngine.vGap / 2,
                  point.y <= layout.frame.maxY + LayoutEngine.vGap / 2 else { continue }
            let after = point.x > layout.frame.midX
            let fullIndex = parent.children.firstIndex(where: { $0.id == sibling.id }) ?? 0
            return ReorderHint(targetID: sibling.id,
                               after: after,
                               y: after ? layout.frame.maxY + LayoutEngine.vGap / 2
                                        : layout.frame.minY - LayoutEngine.vGap / 2,
                               minX: layout.frame.minX - 16,
                               maxX: layout.frame.maxX + 44,
                               targetIndex: after ? fullIndex + 1 : fullIndex)
        }
        return nil
    }

    @ViewBuilder
    private func reorderIndicator(origin: CGPoint) -> some View {
        if let hint = reorderHint {
            Path { path in
                path.move(to: CGPoint(x: hint.minX + origin.x, y: hint.y + origin.y))
                path.addLine(to: CGPoint(x: hint.maxX + origin.x, y: hint.y + origin.y))
            }
            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            .allowsHitTesting(false)
        }
    }

    // MARK: - Helpers

    private func nodeItems(layouts: [UUID: NodeLayout]) -> [NodeItem] {
        var items: [NodeItem] = []
        func walk(_ node: MindNode) {
            if let layout = layouts[node.id] {
                items.append(NodeItem(node: node, layout: layout))
            }
            node.children.forEach(walk)
        }
        walk(vm.document.root)
        return items
    }

    /// Glows around the canvas while text is being dragged over it.
    private var dropHighlightBorder: some View {
        RoundedRectangle(cornerRadius: 14)
            .stroke(Color.accentColor.opacity(textDropActive ? 0.6 : 0), lineWidth: 3)
    }

    /// The scaled, pannable map layer. Kept as its own view-building method
    /// so `body` stays within the type-checker complexity budget.
    private func mapContent(items: [NodeItem], layouts: [UUID: NodeLayout], theme: Theme,
                            bounds: CGRect, origin: CGPoint, geoSize: CGSize, dropTarget: UUID?,
                            focusIDs: Set<UUID>) -> some View {
        ZStack {
            connectionsCanvas(items: items, layouts: layouts, theme: theme,
                              origin: origin, focusIDs: focusIDs)
            linksCanvas(layouts: layouts, origin: origin, focusIDs: focusIDs)
            summariesCanvas(layouts: layouts, origin: origin)
            dragIndicator(origin: origin)
            reorderIndicator(origin: origin)
            ForEach(items) { item in
                nodeView(item: item, theme: theme, dropTarget: dropTarget, origin: origin,
                         layouts: layouts, geoSize: geoSize, bounds: bounds,
                         isSearchHit: vm.searchResults.contains(item.node.id),
                         dimmed: !focusIDs.isEmpty && !focusIDs.contains(item.node.id),
                         colorTag: item.node.colorTag,
                         onToggleCollapse: item.node.collapsed ? { vm.toggleCollapse(id: item.node.id) } : nil)
            }
        }
        .frame(width: bounds.width, height: bounds.height)
        .onDrop(of: [UTType.text], delegate: textDropDelegate(layouts: layouts, origin: origin))
        .scaleEffect(scale)
        .offset(pan)
    }
    /// Shift modifier at click time — enables shift-click batch selection.
    private func isShiftHeld() -> Bool {
        NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false
    }

    private func summariesCanvas(layouts: [UUID: NodeLayout], origin: CGPoint) -> some View {
        ForEach(vm.document.summaries) { summary in
            summaryView(summary: summary, layouts: layouts, origin: origin)
        }
    }

    @ViewBuilder
    private func summaryView(summary: MindSummary, layouts: [UUID: NodeLayout], origin: CGPoint) -> some View {
        if let parentNode = vm.document.root.find(summary.parentID),
           let geo = SummaryGeometry.bracket(for: summary, parentNode: parentNode,
                                             layouts: layouts, origin: origin) {
            let isSelected = vm.selectedSummaryID == summary.id
            Path { p in
                p.move(to: geo.tickA)
                p.addLine(to: geo.spineA)
                p.addLine(to: geo.spineB)
                p.addLine(to: geo.tickB)
            }
            .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.8),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .allowsHitTesting(false)
            Text(summary.text.isEmpty ? "概要…" : summary.text)
                .font(.caption.bold())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(isSelected ? Color.accentColor : Color.clear))
                .position(geo.textAnchor)
                .fixedSize()
                .onTapGesture {
                    vm.selectedSummaryID = vm.selectedSummaryID == summary.id ? nil : summary.id
                }
                .accessibilityLabel("概要 \(summary.text.isEmpty ? "未命名" : summary.text)")
        }
    }

    private func textDropDelegate(layouts: [UUID: NodeLayout], origin: CGPoint) -> CanvasTextDropDelegate {
        CanvasTextDropDelegate(
            layouts: layouts,
            origin: origin,
            setActive: { textDropActive = $0 },
            hitTest: { point, draggedID in self.hitTest(point: point, draggedID: draggedID, layouts: layouts) },
            insert: { text, parentID in vm.insertTextAsNodes(text, sourceLabel: "拖入的文字", parentID: parentID) },
            attach: { dataURL, targetID in
                let target = targetID ?? vm.selection ?? vm.document.root.id
                vm.setNodeImage(id: target, to: dataURL)
            }
        )
    }
/// Drop delegate for plain-text drops on the map canvas. Uses DropInfo so the
/// landing position can be hit-tested against node layouts (the closure-based
/// onDrop overload does not expose a location on this SDK).
struct CanvasTextDropDelegate: DropDelegate {
    let layouts: [UUID: NodeLayout]
    let origin: CGPoint
    let setActive: (Bool) -> Void
    let hitTest: (CGPoint, UUID) -> UUID?
    let insert: (String, UUID?) -> Void
    let attach: (String, UUID?) -> Void

    func dropEntered(info: DropInfo) { setActive(true) }
    func dropExited(info: DropInfo) { setActive(false) }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .copy) }

    func performDrop(info: DropInfo) -> Bool {
        setActive(false)
        let mapPoint = CGPoint(x: info.location.x - origin.x, y: info.location.y - origin.y)
        let hoveredID = hitTest(mapPoint, UUID())

        // Image files/payloads attach to the hovered node.
        if let imageProvider = info.itemProviders(for: [UTType.image]).first {
            _ = imageProvider.loadObject(ofClass: NSImage.self) { obj, _ in
                guard let image = obj as? NSImage,
                      let dataURL = ImageStore.pngDataURL(from: image, maxBytes: 2_800_000) else { return }
                DispatchQueue.main.async {
                    attach(dataURL, hoveredID)
                }
            }
            return true
        }

        // Otherwise treat the payload as text and grow a subtree.
        if let provider = info.itemProviders(for: [UTType.text]).first {
            _ = provider.loadObject(ofClass: NSString.self) { text, _ in
                guard let text = text as? String else { return }
                DispatchQueue.main.async {
                    attach(text, hoveredID)
                }
            }
            return true
        }
        return false
    }
}
    private func hitTest(point: CGPoint, draggedID: UUID, layouts: [UUID: NodeLayout]) -> UUID? {
        let excluded = vm.document.root.find(draggedID)?.descendantIDs() ?? []
        var best: (UUID, Int)?
        for (id, layout) in layouts where id != draggedID && !excluded.contains(id) {
            if layout.frame.insetBy(dx: -8, dy: -8).contains(point) {
                if best == nil || layout.depth > best!.1 {
                    best = (id, layout.depth)
                }
            }
        }
        return best?.0
    }

    @ViewBuilder
    private var statusToast: some View {
        if let message = vm.statusMessage {
            Text(message)
                .font(.callout)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(Color.secondary.opacity(0.15)))
                .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                .padding(.bottom, 20)
        }
    }

    /// Dashed associative curves between arbitrary nodes, with a tap-to-select handle.
    @ViewBuilder
    private func linksCanvas(layouts: [UUID: NodeLayout], origin: CGPoint,
                             focusIDs: Set<UUID>) -> some View {
        ForEach(vm.document.links) { link in
            if let fromLayout = layouts[link.from], let toLayout = layouts[link.to],
               focusIDs.isEmpty || (focusIDs.contains(link.from) && focusIDs.contains(link.to)) {
                self.linkCanvas(link: link, fromLayout: fromLayout, toLayout: toLayout, origin: origin)
            }
        }
    }

    /// One associative line: dashed curve, tap-to-select handle, optional label.
    private func linkCanvas(link: MindLink, fromLayout: NodeLayout, toLayout: NodeLayout,
                            origin: CGPoint) -> some View {
        let p0 = CGPoint(x: fromLayout.center.x + origin.x, y: fromLayout.center.y + origin.y)
        let p1 = CGPoint(x: toLayout.center.x + origin.x, y: toLayout.center.y + origin.y)
        let mid = CGPoint(x: (p0.x + p1.x) / 2, y: (p0.y + p1.y) / 2)
        let dx = p1.x - p0.x
        let dy = p1.y - p0.y
        let length = max(sqrt(dx * dx + dy * dy), 1)
        let control = CGPoint(x: mid.x - dy / length * length * 0.18,
                              y: mid.y + dx / length * length * 0.18)
        let curveMid = CGPoint(x: 0.25 * p0.x + 0.5 * control.x + 0.25 * p1.x,
                               y: 0.25 * p0.y + 0.5 * control.y + 0.25 * p1.y)
        let isSelected = vm.selectedLinkID == link.id
        return Group {
            Path { path in
                path.move(to: p0)
                path.addQuadCurve(to: p1, control: control)
            }
            .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.65),
                    style: StrokeStyle(lineWidth: isSelected ? 2.5 : 1.5, dash: [6, 4]))
            .allowsHitTesting(false)
            Circle()
                .fill(isSelected ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                .overlay(Circle().stroke(isSelected ? Color.accentColor : Color.secondary, lineWidth: 1.5))
                .frame(width: 13, height: 13)
                .position(curveMid)
                .contentShape(Circle())
                .onTapGesture {
                    vm.selectedLinkID = vm.selectedLinkID == link.id ? nil : link.id
                }
                .help("選取此關聯線，按 Delete 刪除")
            if !link.label.isEmpty {
                Text(link.label)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().stroke(Color.secondary.opacity(0.35)))
                    .position(x: curveMid.x, y: curveMid.y - 18)
                    .fixedSize()
                    .accessibilityLabel("關聯線標籤 \(link.label)")
                    .allowsHitTesting(false)
            }
        }
    }

    /// Nudges the canvas when dragging near an edge so big maps stay reachable.
    private func autoScrollToward(_ mapPoint: CGPoint, geoSize: CGSize, bounds: CGRect) {
        let q = CGPoint(x: mapPoint.x - bounds.minX, y: mapPoint.y - bounds.minY)
        let center = CGPoint(x: bounds.width / 2, y: bounds.height / 2)
        let scaled = CGPoint(x: center.x + (q.x - center.x) * scale,
                             y: center.y + (q.y - center.y) * scale)
        let screen = CGPoint(x: (geoSize.width - bounds.width) / 2 + scaled.x + pan.width,
                             y: (geoSize.height - bounds.height) / 2 + scaled.y + pan.height)
        let edge: CGFloat = 80
        let step: CGFloat = 18
        var dx: CGFloat = 0
        var dy: CGFloat = 0
        if screen.x < edge { dx = step } else if screen.x > geoSize.width - edge { dx = -step }
        if screen.y < edge { dy = step } else if screen.y > geoSize.height - edge { dy = -step }
        if dx != 0 || dy != 0 {
            pan = CGSize(width: pan.width + dx, height: pan.height + dy)
            lastPan = pan
        }
    }

    private func fitToView(bounds: CGRect, geo: CGSize) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        scale = CanvasFit.scale(content: bounds.size, viewport: geo)
        lastZoom = scale
        pan = .zero
        lastPan = .zero
    }

    /// Pans the canvas just enough to bring the selected node on screen.
    private func revealNode(_ id: UUID?, layouts: [UUID: NodeLayout], bounds: CGRect, geo: CGSize) {
        guard let id, let layout = layouts[id] else { return }
        let q = CGPoint(x: layout.center.x - bounds.minX, y: layout.center.y - bounds.minY)
        let center = CGPoint(x: bounds.width / 2, y: bounds.height / 2)
        let scaled = CGPoint(x: center.x + (q.x - center.x) * scale,
                             y: center.y + (q.y - center.y) * scale)
        let screen = CGPoint(x: (geo.width - bounds.width) / 2 + scaled.x + pan.width,
                             y: (geo.height - bounds.height) / 2 + scaled.y + pan.height)
        let marginX = geo.width * 0.15
        let marginY = geo.height * 0.15
        let clampedX = min(max(screen.x, marginX), max(geo.width - marginX, marginX))
        let clampedY = min(max(screen.y, marginY), max(geo.height - marginY, marginY))
        let dx = clampedX - screen.x
        let dy = clampedY - screen.y
        if abs(dx) > 1 || abs(dy) > 1 {
            pan = CGSize(width: pan.width + dx, height: pan.height + dy)
            lastPan = pan
        }
    }

    @ViewBuilder
    private func emptyStateHint(items: [NodeItem]) -> some View {
        if items.count <= 1 {
            Text("按 Tab 加入你的第一個主題")
                .font(.title3)
                .foregroundStyle(.secondary)
                .padding(.top, 140)
                .allowsHitTesting(false)
        }
    }

    private var zoomControls: some View {
        HStack(spacing: 10) {
            Button("−") { zoom(by: 0.85) }
            Text("\(Int((scale * 100).rounded()))%")
                .font(.caption.monospacedDigit())
                .frame(minWidth: 40)
                .onTapGesture {
                    scale = 1
                    lastZoom = 1
                }
                .help("點一下回到 100%")
            Button("+") { zoom(by: 1.15) }
            if let level = vm.activeCollapseLevel {
                Text("第 \(level) 層")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Button("全圖") { NotificationCenter.default.post(name: .mindFlowFit, object: nil) }
                .font(.caption)
                .help("縮放至整張圖")
            Button("居中") {
                scale = 1
                lastZoom = 1
                pan = .zero
                lastPan = .zero
            }
            .font(.caption)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(16)
    }

    private func zoom(by factor: CGFloat) {
        scale = min(Self.zoomRange.upperBound, max(Self.zoomRange.lowerBound, scale * factor))
        lastZoom = scale
    }
}
