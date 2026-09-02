import SwiftUI

/// Branch connectors shared by the interactive canvas and static rendering.
struct MapConnectionsView: View {
    let items: [NodeItem]
    let layouts: [UUID: NodeLayout]
    let theme: Palette
    let origin: CGPoint
    var direction: MapDirection = .logicRight
    var visibleIDs: Set<UUID> = []
    var focusIDs: Set<UUID> = []

    var body: some View {
        Canvas { context, _ in
            guard let rootItem = items.first(where: { $0.layout.depth == 0 }) else { return }
            let strokes = ConnectionGeometry.strokes(
                root: rootItem.node, layouts: layouts, direction: direction, origin: origin)
            for stroke in strokes {
                if direction != .fishbone,
                   !focusIDs.isEmpty,
                   let sourceID = stroke.sourceID,
                   let targetID = stroke.targetID,
                   !(focusIDs.contains(sourceID) && focusIDs.contains(targetID)) {
                    continue
                }
                let color = theme.color(forIndex: stroke.colorIndex).opacity(stroke.opacity)
                context.stroke(path(for: stroke.shape), with: .color(color), lineWidth: stroke.lineWidth)
            }
        }
        .allowsHitTesting(false)
    }

    private func path(for shape: ConnectionShape) -> Path {
        var path = Path()
        switch shape {
        case let .cubic(from, control1, control2, to):
            path.move(to: from)
            path.addCurve(to: to, control1: control1, control2: control2)
        case let .polyline(points):
            guard let first = points.first else { return path }
            path.move(to: first)
            for point in points.dropFirst() { path.addLine(to: point) }
        }
        return path
    }
}

/// Gesture-free rendering of the whole map, used for PNG export.
public struct StaticMapView: View {
    public static let exportPalette = Palette.light

    let document: MindDocument
    var transparentBackground = false

    public init(document: MindDocument, transparentBackground: Bool = false) {
        self.document = document
        self.transparentBackground = transparentBackground
    }

    public var body: some View {
        let direction = MapDirection(rawValue: document.directionName) ?? .logicRight
        let layouts = LayoutEngine.layout(root: document.root, direction: direction,
                                          offsets: document.offsets)
        let theme = Self.exportPalette
        let contentBounds = LayoutEngine.contentBounds(of: layouts)
            .union(MarkedBadgeGeometry.screenBounds(for: document.root, layouts: layouts))
        let bounds = contentBounds.insetBy(dx: -80, dy: -60)
        let origin = CGPoint(x: -bounds.minX, y: -bounds.minY)
        var items: [NodeItem] = []
        func walk(_ node: MindNode) {
            if let layout = layouts[node.id] {
                items.append(NodeItem(node: node, layout: layout))
            }
            node.children.forEach(walk)
        }
        walk(document.root)

        return ZStack {
            MapConnectionsView(items: items, layouts: layouts, theme: theme,
                               origin: origin, direction: direction)
            summaryBrackets(layouts: layouts, origin: origin, palette: theme)
            ForEach(items) { item in
                NodeView(node: item.node,
                         layout: item.layout,
                         palette: theme,
                         interactionScale: 1.0,
                         branchColor: theme.color(forIndex: item.layout.colorIndex),
                         isSelected: false,
                         isEditing: false,
                         isDropTarget: false,
                         isFresh: false,
                         isDragging: false,
                         onCancelEdit: { _ in },
                         onCommitEdit: { _ in })
                    .position(x: item.layout.center.x + origin.x,
                              y: item.layout.center.y + origin.y)
            }
        }
        .frame(width: bounds.width, height: bounds.height)
        .background(transparentBackground ? Color.clear : theme.canvasBackground)
    }

    /// Summary brackets share the same geometry as canvas + SVG rendering.
    @ViewBuilder
    private func summaryBrackets(layouts: [UUID: NodeLayout], origin: CGPoint, palette: Palette) -> some View {
        ForEach(document.summaries) { summary in
            if let parentNode = document.root.find(summary.parentID),
               let geo = SummaryGeometry.bracket(for: summary, parentNode: parentNode,
                                                 layouts: layouts, origin: origin) {
                Path { p in
                    p.move(to: geo.tickA)
                    p.addLine(to: geo.spineA)
                    p.addLine(to: geo.spineB)
                    p.addLine(to: geo.tickB)
                }
                .stroke(palette.textSecondary, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                if !summary.text.isEmpty {
                    Text(summary.text)
                        .font(.caption.bold())
                        .foregroundStyle(palette.textSecondary)
                        .position(geo.textAnchor)
                }
            }
        }
    }
}
