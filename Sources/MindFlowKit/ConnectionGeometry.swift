import CoreGraphics
import Foundation

/// Renderer-neutral shape data for a branch connector or fishbone stroke.
/// Renderers own Path/GraphicsContext/SVG conversion; this type owns only geometry.
public enum ConnectionShape: Equatable {
    case cubic(from: CGPoint, control1: CGPoint, control2: CGPoint, to: CGPoint)
    case polyline([CGPoint])
}

/// One ordered connector primitive shared by screen, static, and SVG renderers.
public struct ConnectionStroke: Equatable {
    public let shape: ConnectionShape
    public let colorIndex: Int
    public let lineWidth: CGFloat
    public let opacity: Double
    public let sourceID: UUID?
    public let targetID: UUID?

    public init(shape: ConnectionShape, colorIndex: Int, lineWidth: CGFloat,
                opacity: Double = 1, sourceID: UUID? = nil, targetID: UUID? = nil) {
        self.shape = shape
        self.colorIndex = colorIndex
        self.lineWidth = lineWidth
        self.opacity = opacity
        self.sourceID = sourceID
        self.targetID = targetID
    }
}

/// The one source of truth for branch connector topology and stroke facts.
public enum ConnectionGeometry {
    public static func strokes(root: MindNode, layouts: [UUID: NodeLayout],
                               direction: MapDirection,
                               origin: CGPoint = .zero) -> [ConnectionStroke] {
        switch direction {
        case .fishbone:
            return fishbone(root: root, layouts: layouts, origin: origin)
        case .logicRight, .balanced, .bracket:
            return tree(root: root, layouts: layouts, direction: direction, origin: origin)
        }
    }

    private static func tree(root: MindNode, layouts: [UUID: NodeLayout],
                             direction: MapDirection, origin: CGPoint) -> [ConnectionStroke] {
        var result: [ConnectionStroke] = []

        func visit(_ node: MindNode) {
            guard !node.collapsed, let parentLayout = layouts[node.id] else { return }
            for child in node.children {
                guard let childLayout = layouts[child.id] else { continue }
                let toLeft = childLayout.side == .left
                let from = translated(CGPoint(
                    x: toLeft ? parentLayout.frame.minX : parentLayout.frame.maxX,
                    y: parentLayout.frame.midY), by: origin)
                let to = translated(CGPoint(
                    x: toLeft ? childLayout.frame.maxX : childLayout.frame.minX,
                    y: childLayout.frame.midY), by: origin)
                let shape: ConnectionShape
                if direction == .bracket {
                    let midX = from.x + (to.x - from.x) / 2
                    shape = .polyline([
                        from,
                        CGPoint(x: midX, y: from.y),
                        CGPoint(x: midX, y: to.y),
                        to,
                    ])
                } else {
                    let midX = (from.x + to.x) / 2
                    shape = .cubic(
                        from: from,
                        control1: CGPoint(x: midX, y: from.y),
                        control2: CGPoint(x: midX, y: to.y),
                        to: to)
                }
                result.append(ConnectionStroke(
                    shape: shape,
                    colorIndex: childLayout.colorIndex,
                    lineWidth: parentLayout.depth == 0 ? 3.5 : 2.5,
                    sourceID: node.id,
                    targetID: child.id))
                visit(child)
            }
        }

        visit(root)
        return result
    }

    private static func fishbone(root: MindNode, layouts: [UUID: NodeLayout],
                                 origin: CGPoint) -> [ConnectionStroke] {
        guard let rootLayout = layouts[root.id] else { return [] }
        let branchRoots: [(node: MindNode, layout: NodeLayout)] = root.children.compactMap { node in
            guard let layout = layouts[node.id] else { return nil }
            return (node: node, layout: layout)
        }.sorted { $0.layout.frame.minX < $1.layout.frame.minX }

        let spineY = rootLayout.center.y
        let startX = rootLayout.frame.maxX
        let farthestBranchX = branchRoots.map { $0.layout.center.x + 60 }.max() ?? startX + 120
        let endX = max(startX + 120, farthestBranchX)
        var result: [ConnectionStroke] = [ConnectionStroke(
            shape: .polyline([
                translated(CGPoint(x: startX, y: spineY), by: origin),
                translated(CGPoint(x: endX, y: spineY), by: origin),
            ]),
            colorIndex: 0,
            lineWidth: 4,
            opacity: 0.35)]

        for branch in branchRoots {
            let from = CGPoint(x: branch.layout.center.x, y: spineY)
            let shape = fishboneRootRib(node: branch.node, layout: branch.layout,
                                         from: from, to: branch.layout.center, spineY: spineY)
            result.append(ConnectionStroke(
                shape: translated(shape, by: origin),
                colorIndex: branch.layout.colorIndex,
                lineWidth: 2.5))
        }

        func visit(_ node: MindNode) {
            guard !node.collapsed, let parentLayout = layouts[node.id] else { return }
            for child in node.children {
                guard let childLayout = layouts[child.id] else { continue }
                result.append(ConnectionStroke(
                    shape: .polyline([
                        translated(parentLayout.center, by: origin),
                        translated(childLayout.center, by: origin),
                    ]),
                    colorIndex: childLayout.colorIndex,
                    lineWidth: parentLayout.depth == 0 ? 3 : 2,
                    sourceID: node.id,
                    targetID: child.id))
                visit(child)
            }
        }

        visit(root)
        return result
    }

    // Only an upper marked branch can have its spine-to-centre rib pass through
    // its bottom badge. The final centre-to-card segment is behind the card.
    private static func fishboneRootRib(node: MindNode, layout: NodeLayout,
                                        from: CGPoint, to: CGPoint,
                                        spineY: CGFloat) -> ConnectionShape {
        let original = ConnectionShape.polyline([from, to])
        guard node.marked, layout.center.y < spineY else { return original }

        let reserved = MarkedBadgeGeometry.layoutReservedFootprint(for: layout.frame)
        guard fishboneCorridorIntersects(from: from, to: to, footprint: reserved,
                                         lineWidth: 2.5) else { return original }
        guard let attachmentX = fishboneAttachmentX(frame: layout.frame, from: from,
                                                     footprint: reserved, lineWidth: 2.5)
        else { return original }

        return .polyline([
            from,
            CGPoint(x: attachmentX, y: layout.frame.maxY),
            to,
        ])
    }

    // The corridor is the visible segment expanded by its half stroke width and
    // one design unit of clearance. A missing in-card candidate intentionally
    // leaves the old shape so checks can stop rather than route outside the card.
    private static func fishboneAttachmentX(frame: CGRect, from: CGPoint,
                                             footprint: CGRect, lineWidth: CGFloat) -> CGFloat? {
        guard frame.minX.isFinite, frame.maxX.isFinite, frame.width >= 0 else { return nil }
        let maxDistance = max(0, Int(ceil(frame.width / 2)))
        for distance in 0...maxDistance {
            let offsets: [CGFloat] = distance == 0 ? [0] : [-1, 1]
            for offset in offsets {
                let x = frame.midX + CGFloat(distance) * offset
                guard x >= frame.minX, x <= frame.maxX else { continue }
                let probes = [-1, 0, 1].map { x + CGFloat($0) }
                guard probes.allSatisfy({ probe in
                    probe >= frame.minX && probe <= frame.maxX
                        && !fishboneCorridorIntersects(
                            from: from,
                            to: CGPoint(x: probe, y: frame.maxY),
                            footprint: footprint,
                            lineWidth: lineWidth)
                }) else { continue }
                return x
            }
        }
        return nil
    }

    private static func fishboneCorridorIntersects(from: CGPoint, to: CGPoint,
                                                   footprint: CGRect,
                                                   lineWidth: CGFloat) -> Bool {
        let radius = lineWidth / 2 + 1
        return segmentIntersects(from: from, to: to,
                                 rectangle: footprint.insetBy(dx: -radius, dy: -radius))
    }

    // Liang–Barsky keeps this renderer-neutral and tests the whole expanded
    // segment rather than only its endpoints.
    private static func segmentIntersects(from: CGPoint, to: CGPoint,
                                          rectangle: CGRect) -> Bool {
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

    private static func translated(_ shape: ConnectionShape, by origin: CGPoint) -> ConnectionShape {
        switch shape {
        case let .cubic(from, control1, control2, to):
            return .cubic(from: translated(from, by: origin),
                          control1: translated(control1, by: origin),
                          control2: translated(control2, by: origin),
                          to: translated(to, by: origin))
        case let .polyline(points):
            return .polyline(points.map { translated($0, by: origin) })
        }
    }

    private static func translated(_ point: CGPoint, by origin: CGPoint) -> CGPoint {
        CGPoint(x: point.x + origin.x, y: point.y + origin.y)
    }
}
