import SwiftUI

/// Branch connectors shared by the interactive canvas and static rendering.
struct MapConnectionsView: View {
    let items: [NodeItem]
    let layouts: [UUID: NodeLayout]
    let theme: Theme
    let origin: CGPoint
    var direction: MapDirection = .logicRight
    var focusIDs: Set<UUID> = []

    var body: some View {
        Canvas { context, _ in
            if direction == .fishbone {
                drawFishbone(context: &context, items: items, layouts: layouts, theme: theme, origin: origin)
                return
            }
            for item in items where !item.node.collapsed {
                for child in item.node.children {
                    guard let childLayout = layouts[child.id] else { continue }
                    if !focusIDs.isEmpty && !(focusIDs.contains(item.node.id) && focusIDs.contains(child.id)) { continue }
                    let toLeft = childLayout.side == .left
                    let from = CGPoint(x: (toLeft ? item.layout.frame.minX : item.layout.frame.maxX) + origin.x,
                                       y: item.layout.frame.midY + origin.y)
                    let to = CGPoint(x: (toLeft ? childLayout.frame.maxX : childLayout.frame.minX) + origin.x,
                                     y: childLayout.frame.midY + origin.y)
                    var path = Path()
                    if direction == .bracket {
                        // Right-angle elbow connectors.
                        let midX = from.x + (to.x - from.x) / 2
                        path.move(to: from)
                        path.addLine(to: CGPoint(x: midX, y: from.y))
                        path.addLine(to: CGPoint(x: midX, y: to.y))
                        path.addLine(to: to)
                    } else {
                        let midX = (from.x + to.x) / 2
                        path.move(to: from)
                        path.addCurve(to: to,
                                      control1: CGPoint(x: midX, y: from.y),
                                      control2: CGPoint(x: midX, y: to.y))
                    }
                    let width: CGFloat = item.layout.depth == 0 ? 3.5 : 2.5
                    context.stroke(path, with: .color(theme.color(forIndex: item.layout.colorIndex)), lineWidth: width)
                }
            }
        }
        .allowsHitTesting(false)
    }

    /// Spine + ribs + diagonal chains for the fishbone layout.
    private func drawFishbone(context: inout GraphicsContext, items: [NodeItem],
                                     layouts: [UUID: NodeLayout], theme: Theme, origin: CGPoint) {
        guard let rootItem = items.first(where: { $0.layout.depth == 0 }) else { return }
        let spineY = rootItem.layout.center.y + origin.y
        let startX = rootItem.layout.frame.maxX + origin.x
        var endX = startX + 120

        // Main spine.
        var spine = Path()
        spine.move(to: CGPoint(x: startX, y: spineY))
        spine.addLine(to: CGPoint(x: endX, y: spineY))
        context.stroke(spine, with: .color(theme.color(forIndex: 0).opacity(0.35)), lineWidth: 4)

        // Branch roots sitting alternately above / below the spine.
        let branchRoots = items.filter { $0.layout.depth == 1 }
            .sorted { $0.layout.frame.minX < $1.layout.frame.minX }
        for (index, branch) in branchRoots.enumerated() {
            let bx = branch.layout.center.x + origin.x
            let by = branch.layout.center.y + origin.y
            endX = max(endX, bx + 60)
            var rib = Path()
            rib.move(to: CGPoint(x: bx, y: spineY))
            rib.addLine(to: CGPoint(x: bx, y: by))
            context.stroke(rib, with: .color(theme.color(forIndex: index)), lineWidth: 2.5)
        }

        // Diagonal chain segments parent -> child.
        for item in items where item.node.collapsed == false {
            for child in item.node.children {
                guard let cl = layouts[child.id], let pl = layouts[item.node.id] else { continue }
                let from = CGPoint(x: pl.center.x + origin.x, y: pl.center.y + origin.y)
                let to = CGPoint(x: cl.center.x + origin.x, y: cl.center.y + origin.y)
                var path = Path()
                path.move(to: from)
                path.addLine(to: to)
                context.stroke(path, with: .color(theme.color(forIndex: pl.colorIndex)),
                               lineWidth: pl.depth == 0 ? 3 : 2)
            }
        }
    }
}

/// Gesture-free rendering of the whole map, used for PNG export.
struct StaticMapView: View {
    let document: MindDocument
    var transparentBackground = false

    var body: some View {
        let direction = MapDirection(rawValue: document.directionName) ?? .logicRight
        let layouts = LayoutEngine.layout(root: document.root, direction: direction,
                                          offsets: document.offsets)
        let theme = Theme.named(document.themeName)
        let bounds = LayoutEngine.contentBounds(of: layouts).insetBy(dx: -80, dy: -60)
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
            ForEach(items) { item in
                NodeView(node: item.node,
                         layout: item.layout,
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
        .background(transparentBackground ? Color.clear : Color(nsColor: .textBackgroundColor))
    }
}
