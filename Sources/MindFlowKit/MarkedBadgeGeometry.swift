import Foundation
import CoreGraphics

/// Renderer-neutral map-space geometry for a marked-node badge.
///
/// The anchor is a point at the centre of the conservative union of the screen SF Symbol
/// footprint and the SVG star's typographic em box. Both renderers position their own glyph
/// from that point; neither renderer's glyph geometry is used as the other's proxy.
public enum MarkedBadgeGeometry {
    /// The existing nominal SF Symbol size used by NodeView.
    public static let screenFontSize: CGFloat = 9
    public static let screenFootprintSize = CGSize(width: 9, height: 9)

    /// The SVG `★` size and conservative typographic upper bounds, not measured font metrics.
    /// The bounds deliberately over-approximate the exported glyph so layout never relies on
    /// a renderer-specific raster measurement.
    public static let svgFontSize: CGFloat = 10
    public static let svgAdvance: CGFloat = 10
    public static let svgAscent: CGFloat = 10
    public static let svgDescent: CGFloat = 3

    private static let clearance: CGFloat = 1

    /// Finds the first bottom-centre candidate whose footprint and ±1 design-unit probes
    /// are strictly below the node. Searching from the closest metric-derived candidate
    /// avoids a hand-written renderer-specific offset.
    public static func anchor(for nodeFrame: CGRect) -> CGPoint {
        guard nodeFrame != .null,
              nodeFrame.minX.isFinite, nodeFrame.maxX.isFinite,
              nodeFrame.minY.isFinite, nodeFrame.maxY.isFinite else {
            return .zero
        }

        let union = reservedFootprint(at: .zero)
        var candidateY = nodeFrame.maxY + union.height / 2
        for _ in 0..<10_000 {
            let candidate = CGPoint(x: nodeFrame.midX, y: candidateY)
            let safe = [-clearance, 0, clearance].allSatisfy { delta in
                let footprint = union.offsetBy(dx: candidate.x, dy: candidate.y + delta)
                return clears(nodeFrame: nodeFrame, footprint: footprint)
            }
            if safe { return candidate }
            candidateY += 1
        }

        // A finite fallback keeps malformed geometry from creating an infinite search.
        return CGPoint(x: nodeFrame.midX,
                       y: nodeFrame.maxY + union.height / 2 + clearance * 2)
    }

    /// Conservative layout reservation for either renderer's badge.
    /// It is the exact union of the screen footprint and SVG em-box, per dimension.
    public static func layoutReservedFootprint(for nodeFrame: CGRect) -> CGRect {
        reservedFootprint(at: anchor(for: nodeFrame))
    }

    /// The screen renderer's marked-badge bounds, in map coordinates.
    public static func screenBounds(for root: MindNode,
                                    layouts: [UUID: NodeLayout]) -> CGRect {
        markedBounds(in: root, layouts: layouts) { screenFootprint(for: $0.frame) }
    }

    /// The SVG renderer's marked-badge bounds, in map coordinates.
    public static func svgBounds(for root: MindNode,
                                 layouts: [UUID: NodeLayout]) -> CGRect {
        markedBounds(in: root, layouts: layouts) { svgEmBox(for: $0.frame) }
    }

    /// The nominal SF Symbol footprint in map coordinates.
    public static func screenFootprint(for nodeFrame: CGRect) -> CGRect {
        screenFootprint(at: anchor(for: nodeFrame))
    }

    /// The SVG `★` advance/ascent/descent em-box in map coordinates.
    public static func svgEmBox(for nodeFrame: CGRect) -> CGRect {
        svgEmBox(at: anchor(for: nodeFrame))
    }

    /// Baseline for the SVG renderer's own `★` glyph, derived from the shared anchor.
    public static func svgBaseline(for nodeFrame: CGRect) -> CGFloat {
        svgBaseline(at: anchor(for: nodeFrame))
    }

    /// Screen-local coordinates for NodeView's top-leading overlay.
    public static func screenLocalFootprint(for nodeFrame: CGRect) -> CGRect {
        screenFootprint(for: nodeFrame).offsetBy(dx: -nodeFrame.minX, dy: -nodeFrame.minY)
    }

    private static func svgBaseline(at anchor: CGPoint) -> CGFloat {
        anchor.y + (svgAscent - svgDescent) / 2
    }

    private static func markedBounds(in node: MindNode,
                                     layouts: [UUID: NodeLayout],
                                     footprint: (NodeLayout) -> CGRect) -> CGRect {
        var bounds = CGRect.null
        if node.marked, let layout = layouts[node.id] {
            bounds = bounds.union(footprint(layout))
        }
        for child in node.children {
            bounds = bounds.union(markedBounds(in: child, layouts: layouts, footprint: footprint))
        }
        return bounds
    }

    private static func reservedFootprint(at anchor: CGPoint) -> CGRect {
        screenFootprint(at: anchor).union(svgEmBox(at: anchor))
    }

    private static func screenFootprint(at anchor: CGPoint) -> CGRect {
        CGRect(x: anchor.x - screenFootprintSize.width / 2,
               y: anchor.y - screenFootprintSize.height / 2,
               width: screenFootprintSize.width,
               height: screenFootprintSize.height)
    }

    private static func svgEmBox(at anchor: CGPoint) -> CGRect {
        let baseline = anchor.y + (svgAscent - svgDescent) / 2
        return CGRect(x: anchor.x - svgAdvance / 2,
                      y: baseline - svgAscent,
                      width: svgAdvance,
                      height: svgAscent + svgDescent)
    }

    private static func clears(nodeFrame: CGRect, footprint: CGRect) -> Bool {
        footprint.minY > nodeFrame.maxY && !footprint.intersects(nodeFrame)
    }
}
