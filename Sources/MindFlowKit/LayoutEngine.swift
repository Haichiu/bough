import Foundation
import CoreGraphics
import AppKit

public enum MapDirection: String {
    case logicRight
    case balanced
    case fishbone
    case bracket
}

public enum Side: Equatable {
    case right
    case left
}

public struct NodeLayout: Equatable {
    public let id: UUID
    public let frame: CGRect
    public let depth: Int
    public let colorIndex: Int
    public let side: Side

    public var center: CGPoint { CGPoint(x: frame.midX, y: frame.midY) }

    init(id: UUID, frame: CGRect, depth: Int, colorIndex: Int, side: Side) {
        self.id = id
        self.frame = frame
        self.depth = depth
        self.colorIndex = colorIndex
        self.side = side
    }
}

/// Tidy tree layout: right-growing "邏輯圖" or XMind-style balanced map.
public enum LayoutEngine {
    static let vGap: CGFloat = 12

    static func font(for depth: Int) -> NSFont {
        switch depth {
        case 0: return .systemFont(ofSize: 17, weight: .semibold)
        case 1: return .systemFont(ofSize: 14, weight: .medium)
        default: return .systemFont(ofSize: 13)
        }
    }

    public static func nodeSize(for text: String, depth: Int) -> CGSize {
        let attrs: [NSAttributedString.Key: Any] = [.font: font(for: depth)]
        let measured = (text.isEmpty ? " " : text).size(withAttributes: attrs)
        let padding: CGFloat = depth == 0 ? 44 : 30
        let minHeight: CGFloat = depth == 0 ? 48 : (depth == 1 ? 36 : 30)
        let minWidth: CGFloat = depth == 0 ? 120 : 56
        // Wrap long text into up to three lines and grow the box vertically.
        let maxTextWidth: CGFloat = depth == 0 ? 280 : 250
        let lines = max(1, min(3, Int(ceil(measured.width / maxTextWidth))))
        let textBlockWidth = min(measured.width, maxTextWidth)
        let width = max(minWidth, min(ceil(textBlockWidth) + padding + 10, 340))
        let lineHeight = ceil(measured.height)
        let height = min(max(minHeight, CGFloat(lines) * lineHeight + (depth == 0 ? 18 : 12)), 100)
        return CGSize(width: width, height: height)
    }

    static func cornerRadius(for depth: Int) -> CGFloat {
        switch depth {
        case 0: return 12
        case 1: return 18
        default: return 15
        }
    }

    static func hGap(for depth: Int) -> CGFloat { depth == 0 ? 72 : 44 }

    public static func layout(root: MindNode, direction: MapDirection = .logicRight) -> [UUID: NodeLayout] {
        var heights: [UUID: CGFloat] = [:]
        _ = subtreeHeight(root, depth: 0, heights: &heights)
        var result: [UUID: NodeLayout] = [:]
        let rootSize = nodeSize(for: root.text, depth: 0)
        let indexed = root.children.enumerated().map { (node: $0.element, index: $0.offset) }

        func span(of children: [MindNode]) -> CGFloat {
            children.reduce(0.0) { $0 + (heights[$1.id] ?? 0) } + CGFloat(max(children.count - 1, 0)) * vGap
        }

        func placeChildren(_ children: [(node: MindNode, index: Int)], side: Side,
                           innerX: CGFloat, centerY: CGFloat) {
            guard !children.isEmpty else { return }
            let total = span(of: children.map(\.node))
            var cursor = centerY - total / 2
            for child in children {
                placeSubtree(child.node, depth: 1, colorIndex: child.index, side: side,
                             innerX: innerX, yTop: cursor, heights: heights, into: &result)
                cursor += (heights[child.node.id] ?? 0) + vGap
            }
        }

        switch direction {
        case .fishbone:
            // Diagonal chains: every branch flattens onto one strict diagonal,
            // so positions are monotonically increasing and can never overlap.
            let rootSizeFB = nodeSize(for: root.text, depth: 0)
            result[root.id] = NodeLayout(
                id: root.id,
                frame: CGRect(origin: CGPoint(x: 0, y: -rootSizeFB.height / 2), size: rootSizeFB),
                depth: 0, colorIndex: 0, side: .right)
            let stepX: CGFloat = 96
            let stepY: CGFloat = 76
            var cursorX = rootSizeFB.width + 130
            for (index, branch) in root.children.enumerated() {
                let sign: CGFloat = index % 2 == 0 ? -1 : 1
                var chain: [(node: MindNode, depth: Int)] = []
                func collect(_ node: MindNode, depth: Int) {
                    chain.append((node, depth))
                    for child in node.children { collect(child, depth: depth + 1) }
                }
                collect(branch, depth: 1)
                for (offset, entry) in chain.enumerated() {
                    let size = nodeSize(for: entry.node.text, depth: min(entry.depth, 2))
                    let cx = cursorX + stepX * CGFloat(offset + 1)
                    let cy = sign * stepY * CGFloat(offset + 1)
                    result[entry.node.id] = NodeLayout(
                        id: entry.node.id,
                        frame: CGRect(origin: CGPoint(x: cx - size.width / 2, y: cy - size.height / 2), size: size),
                        depth: entry.depth,
                        colorIndex: index,
                        side: sign < 0 ? .left : .right)
                }
                let extent = stepX * CGFloat(chain.count + 1)
                cursorX += max(170, extent + 60)
            }
        case .logicRight, .bracket:
            result[root.id] = NodeLayout(id: root.id, frame: CGRect(origin: .zero, size: rootSize),
                                         depth: 0, colorIndex: 0, side: .right)
            placeChildren(indexed, side: .right,
                          innerX: rootSize.width + hGap(for: 0), centerY: rootSize.height / 2)
        case .balanced:
            result[root.id] = NodeLayout(id: root.id,
                                         frame: CGRect(origin: CGPoint(x: -rootSize.width / 2, y: -rootSize.height / 2), size: rootSize),
                                         depth: 0, colorIndex: 0, side: .right)
            let rightCount = (indexed.count + 1) / 2
            let gap = hGap(for: 0)
            placeChildren(Array(indexed[..<rightCount]), side: .right,
                          innerX: rootSize.width / 2 + gap, centerY: 0)
            if rightCount < indexed.count {
                placeChildren(Array(indexed[rightCount...]), side: .left,
                              innerX: -rootSize.width / 2 - gap, centerY: 0)
            }
        }
        return result
    }

    private static func placeSubtree(_ node: MindNode, depth: Int, colorIndex: Int, side: Side,
                                     innerX: CGFloat, yTop: CGFloat, heights: [UUID: CGFloat],
                                     into result: inout [UUID: NodeLayout]) {
        let size = nodeSize(for: node.text, depth: depth)
        let y = yTop + ((heights[node.id] ?? size.height) - size.height) / 2
        let x = side == .right ? innerX : innerX - size.width
        result[node.id] = NodeLayout(id: node.id, frame: CGRect(origin: CGPoint(x: x, y: y), size: size),
                                     depth: depth, colorIndex: colorIndex, side: side)
        guard !node.collapsed, !node.children.isEmpty else { return }

        let childSpan = node.children.reduce(0.0) { $0 + (heights[$1.id] ?? 0) }
            + CGFloat(node.children.count - 1) * vGap
        let childrenTop = y + size.height / 2 - childSpan / 2
        let childInnerX = side == .right ? x + size.width + hGap(for: depth) : x - hGap(for: depth)
        var cursor = childrenTop
        for child in node.children {
            placeSubtree(child, depth: depth + 1, colorIndex: colorIndex, side: side,
                         innerX: childInnerX, yTop: cursor, heights: heights, into: &result)
            cursor += (heights[child.id] ?? 0) + vGap
        }
    }

    private static func subtreeHeight(_ node: MindNode, depth: Int, heights: inout [UUID: CGFloat]) -> CGFloat {
        let own = nodeSize(for: node.text, depth: depth).height
        guard !node.collapsed, !node.children.isEmpty else {
            heights[node.id] = own
            return own
        }
        let span = node.children.reduce(0.0) { $0 + subtreeHeight($1, depth: depth + 1, heights: &heights) }
            + CGFloat(node.children.count - 1) * vGap
        let h = max(own, span)
        heights[node.id] = h
        return h
    }

    static func contentBounds(of layouts: [UUID: NodeLayout]) -> CGRect {
        guard !layouts.isEmpty else { return .zero }
        var rect = CGRect.null
        for value in layouts.values { rect = rect.union(value.frame) }
        return rect
    }
}
