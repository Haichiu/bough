import AppKit
import SwiftUI

/// Everything that decides how one node looks and how much room its text needs.
///
/// Layout measures with it, the canvas draws with it, and the exporters redraw with
/// it, so those three cannot drift apart. They previously hardcoded the same facts
/// independently and had already diverged: exported SVG drew depth≥2 text at 12pt
/// while the screen measured and drew it at 13pt, used corner radius 9 for every
/// depth against the screen's 12/18/15, and never wrapped, so any node that showed
/// three lines on screen exported as one overflowing line.
///
/// Sizing is independent of colour, so `branchColor` is only needed when painting.
public struct NodeStyle {
    public let font: NSFont
    public let cornerRadius: CGFloat
    public let textColor: Color
    /// Paint as `fillBase.opacity(fillOpacity)`. Kept unmultiplied so SVG can emit
    /// `fill` and `fill-opacity` separately instead of losing the alpha to a hex string.
    public let fillBase: Color
    public let fillOpacity: Double
    public let strokeBase: Color?
    public let strokeOpacity: Double
    public let strokeWidth: CGFloat
    public let horizontalInset: CGFloat
    public let verticalInset: CGFloat
    public let lineLimit: Int
    public let maxTextWidth: CGFloat
    public let minSize: CGSize

    /// Hard ceilings so one very long topic cannot dominate the map.
    public static let maxNodeWidth: CGFloat = 340
    public static let maxNodeHeight: CGFloat = 120

    public static func of(depth: Int, branchColor: Color = .accentColor) -> NodeStyle {
        switch depth {
        case 0:
            return NodeStyle(font: .systemFont(ofSize: 18, weight: .semibold),
                             cornerRadius: 14,
                             textColor: Theme.rootForeground,
                             fillBase: Theme.rootBackground, fillOpacity: 1,
                             strokeBase: nil, strokeOpacity: 0, strokeWidth: 0,
                             horizontalInset: 24, verticalInset: 13,
                             lineLimit: 3, maxTextWidth: 280,
                             minSize: CGSize(width: 140, height: 52))
        case 1:
            return NodeStyle(font: .systemFont(ofSize: 15, weight: .medium),
                             cornerRadius: 11,
                             textColor: .white,
                             fillBase: branchColor, fillOpacity: 1,
                             strokeBase: nil, strokeOpacity: 0, strokeWidth: 0,
                             horizontalInset: 18, verticalInset: 10,
                             lineLimit: 3, maxTextWidth: 260,
                             minSize: CGSize(width: 76, height: 38))
        default:
            // A tinted wash keyed to the branch colour reads as belonging to that
            // branch, where the old white box plus 1.5pt outline read as a form field.
            return NodeStyle(font: .systemFont(ofSize: 13),
                             cornerRadius: 9,
                             textColor: .primary,
                             fillBase: branchColor, fillOpacity: 0.12,
                             strokeBase: branchColor, strokeOpacity: 0.38, strokeWidth: 1,
                             horizontalInset: 14, verticalInset: 8,
                             lineLimit: 4, maxTextWidth: 250,
                             minSize: CGSize(width: 64, height: 32))
        }
    }

    public var fill: Color { fillBase.opacity(fillOpacity) }
    public var stroke: Color? { strokeBase?.opacity(strokeOpacity) }

    /// The box this text needs under this style. Callers that draw must use the same
    /// font, insets and line limit, or text will clip.
    public func size(for text: String, hasImage: Bool = false) -> CGSize {
        let laid = layOut(text)
        let width = max(minSize.width,
                        min(ceil(laid.widest) + horizontalInset * 2, Self.maxNodeWidth))
        var height = min(max(minSize.height,
                             CGFloat(laid.lines.count) * laid.lineHeight + verticalInset * 2),
                         Self.maxNodeHeight)
        if hasImage { height += LayoutEngine.imageDisplayHeight }
        return CGSize(width: width, height: height)
    }

    /// The exact lines this text breaks into. Exporters draw these so a node that shows
    /// three lines on screen also exports as three lines, instead of one overflowing run.
    public func wrappedLines(for text: String) -> [String] { layOut(text).lines }

    /// Line height without measuring a string; font metrics already carry it.
    public var lineHeight: CGFloat { ceil(font.ascender - font.descender + font.leading) }

    private func width(of text: String) -> CGFloat {
        text.size(withAttributes: [.font: font]).width
    }

    /// Single wrapping algorithm shared by measurement and every renderer.
    /// The common case — a label that already fits — costs one measurement, which is what
    /// the layout memo depends on to stay cheap on large maps.
    private func layOut(_ text: String) -> (lines: [String], widest: CGFloat, lineHeight: CGFloat) {
        let source = text.isEmpty ? " " : text
        let full = width(of: source)
        if full <= maxTextWidth {
            return ([source], full, lineHeight)
        }

        // Prefer breaking at spaces, and fall back to characters for scripts that do not
        // use them, which is the normal case for Chinese topics.
        var segments: [String] = []
        let pieces = source.components(separatedBy: " ")
        for (index, piece) in pieces.enumerated() {
            segments.append(index == pieces.count - 1 ? piece : piece + " ")
        }

        var lines: [String] = []
        var current = ""
        func flush() {
            if !current.isEmpty { lines.append(current); current = "" }
        }
        for segment in segments where !segment.isEmpty {
            if width(of: current + segment) <= maxTextWidth { current += segment; continue }
            flush()
            if width(of: segment) <= maxTextWidth { current = segment; continue }
            for character in segment {
                if width(of: current + String(character)) <= maxTextWidth {
                    current.append(character)
                } else {
                    flush()
                    current = String(character)
                }
            }
        }
        flush()

        if lines.count > lineLimit { lines = Array(lines.prefix(lineLimit)) }
        if lines.isEmpty { lines = [source] }
        let widest = lines.map(width(of:)).max() ?? full
        return (lines, min(widest, maxTextWidth), lineHeight)
    }
}
