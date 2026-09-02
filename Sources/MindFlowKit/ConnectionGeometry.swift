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
        let branchRoots = root.children.compactMap { layouts[$0.id] }
            .sorted { $0.frame.minX < $1.frame.minX }

        let spineY = rootLayout.center.y
        let startX = rootLayout.frame.maxX
        let farthestBranchX = branchRoots.map { $0.center.x + 60 }.max() ?? startX + 120
        let endX = max(startX + 120, farthestBranchX)
        var result: [ConnectionStroke] = [ConnectionStroke(
            shape: .polyline([
                translated(CGPoint(x: startX, y: spineY), by: origin),
                translated(CGPoint(x: endX, y: spineY), by: origin),
            ]),
            colorIndex: 0,
            lineWidth: 4,
            opacity: 0.35)]

        for branchLayout in branchRoots {
            result.append(ConnectionStroke(
                shape: .polyline([
                    translated(CGPoint(x: branchLayout.center.x, y: spineY), by: origin),
                    translated(branchLayout.center, by: origin),
                ]),
                colorIndex: branchLayout.colorIndex,
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

    private static func translated(_ point: CGPoint, by origin: CGPoint) -> CGPoint {
        CGPoint(x: point.x + origin.x, y: point.y + origin.y)
    }
}
