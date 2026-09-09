import CoreGraphics
import Foundation

/// Computed frame for one boundary: a rounded rectangle around the anchored
/// subtree, already expanded by the boundary padding.
public struct BoundaryFrameGeometry: Equatable {
    public let rect: CGRect
    public let cornerRadius: CGFloat
}

/// Pure geometry for boundary frames — shared by canvas, static render, and SVG
/// so every surface draws the exact same shape (same pattern as SummaryGeometry).
public enum BoundaryGeometry {
    /// Gap between the outermost covered node frame and the boundary stroke.
    public static let padding: CGFloat = 10
    public static let cornerRadius: CGFloat = 10

    /// Frame around `boundary.rootID` and its visible descendants.
    ///
    /// Nodes hidden by a collapsed ancestor are skipped: the layout engine does
    /// not place them, and a frame cannot enclose what is not drawn. A collapsed
    /// root still contributes its own frame, so collapsing never makes a
    /// boundary disappear. Returns nil when the root is gone from the document
    /// or nothing is laid out.
    public static func frame(for boundary: MindBoundary,
                             root: MindNode,
                             layouts: [UUID: NodeLayout],
                             origin: CGPoint) -> BoundaryFrameGeometry? {
        guard let anchor = root.find(boundary.rootID) else { return nil }
        var box = CGRect.null
        func include(_ node: MindNode) {
            if let layout = layouts[node.id] {
                box = box.union(layout.frame.offsetBy(dx: origin.x, dy: origin.y))
            }
            guard !node.collapsed else { return }
            for child in node.children { include(child) }
        }
        include(anchor)
        guard !box.isNull else { return nil }
        return BoundaryFrameGeometry(rect: box.insetBy(dx: -padding, dy: -padding),
                                     cornerRadius: cornerRadius)
    }
}
