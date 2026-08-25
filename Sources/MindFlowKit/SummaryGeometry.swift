import CoreGraphics
import Foundation

/// Computed line segments + label anchor for one summary bracket.
public struct SummaryBracketGeometry: Equatable {
    /// Outer ends of the two ticks (where the spine runs).
    public let spineA: CGPoint
    public let spineB: CGPoint
    /// Inner ends attached to the ranged nodes.
    public let tickA: CGPoint
    public let tickB: CGPoint
    /// Where the summary label sits (just past the spine).
    public let textAnchor: CGPoint
}

/// Pure geometry for summary brackets — shared by canvas, static render, and SVG
/// so every surface draws the exact same shape.
public enum SummaryGeometry {
    /// Computes bracket lines for `summary`, which spans the consecutive children
    /// of `parentNode` between its startID and endID. Coordinates are in canvas space.
    public static func bracket(for summary: MindSummary,
                               parentNode: MindNode,
                               layouts: [UUID: NodeLayout],
                               origin: CGPoint) -> SummaryBracketGeometry? {
        guard let parentLayout = layouts[summary.parentID],
              let startIndex = parentNode.children.firstIndex(where: { $0.id == summary.startID }),
              let endIndex = parentNode.children.firstIndex(where: { $0.id == summary.endID }),
              startIndex <= endIndex else { return nil }

        var box = CGRect.null
        for i in startIndex...endIndex {
            if let l = layouts[parentNode.children[i].id] {
                box = box.union(l.frame.offsetBy(dx: origin.x, dy: origin.y))
            }
        }
        guard !box.isNull else { return nil }

        let parentC = CGPoint(x: parentLayout.center.x + origin.x, y: parentLayout.center.y + origin.y)
        let boxC = CGPoint(x: box.midX, y: box.midY)
        let dx = boxC.x - parentC.x
        let dy = boxC.y - parentC.y
        let out: CGFloat = 14

        if abs(dx) >= abs(dy) {
            // Children arranged horizontally → vertical bracket on the outer side.
            let dir: CGFloat = dx >= 0 ? 1 : -1
            let sideX = dx >= 0 ? box.maxX : box.minX
            let spineX = sideX + dir * out
            return SummaryBracketGeometry(
                spineA: CGPoint(x: spineX, y: box.minY),
                spineB: CGPoint(x: spineX, y: box.maxY),
                tickA: CGPoint(x: sideX, y: box.minY),
                tickB: CGPoint(x: sideX, y: box.maxY),
                textAnchor: CGPoint(x: spineX + dir * 8, y: box.midY))
        } else {
            // Children stacked vertically → horizontal bracket above/below.
            let dir: CGFloat = dy >= 0 ? 1 : -1
            let sideY = dy >= 0 ? box.maxY : box.minY
            let spineY = sideY + dir * out
            return SummaryBracketGeometry(
                spineA: CGPoint(x: box.minX, y: spineY),
                spineB: CGPoint(x: box.maxX, y: spineY),
                tickA: CGPoint(x: box.minX, y: sideY),
                tickB: CGPoint(x: box.maxX, y: sideY),
                textAnchor: CGPoint(x: box.midX, y: spineY + dir * 14))
        }
    }
}