import Foundation
import SwiftUI

/// Text-based export formats for mind maps.
public enum MapExporter {
    private static func colorEmoji(_ key: String?) -> String {
        switch key {
        case "red": return "\u{1F534} "
        case "orange": return "\u{1F7E0} "
        case "yellow": return "\u{1F7E1} "
        case "green": return "\u{1F7E2} "
        case "blue": return "\u{1F535} "
        case "purple": return "\u{1F7E3} "
        default: return ""
        }
    }

    public static func markdown(_ document: MindDocument) -> String {
        var lines: [String] = ["# \(document.root.text)"]
        if !document.root.note.isEmpty {
            lines.append("> \(document.root.note)")
        }
        func walk(_ node: MindNode, level: Int) {
            for child in node.children {
                let indent = String(repeating: "  ", count: level)
                let emoji = colorEmoji(child.colorTag)
                let star = child.marked ? "★ " : ""
                lines.append("\(indent)- \(emoji)\(star)\(child.text)")
                if !child.note.isEmpty {
                    lines.append("\(indent)  > \(child.note)")
                }
                walk(child, level: level + 1)
            }
        }
        walk(document.root, level: 0)
        return lines.joined(separator: "\n") + "\n"
    }

    public static func opml(_ document: MindDocument) -> String {
        func escape(_ string: String) -> String {
            string.replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\"", with: "&quot;")
        }

        func outline(_ node: MindNode, depth: Int) -> String {
            let indent = String(repeating: "  ", count: depth)
            let note = node.note.isEmpty ? "" : " _note=\"\(escape(node.note))\""
            if node.children.isEmpty {
                return "\(indent)<outline text=\"\(escape(node.text))\"\(note)/>"
            }
            let inner = node.children.map { outline($0, depth: depth + 1) }.joined(separator: "\n")
            return "\(indent)<outline text=\"\(escape(node.text))\"\(note)>\n\(inner)\n\(indent)</outline>"
        }

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
          <head><title>\(escape(document.title))</title></head>
          <body>
        \(outline(document.root, depth: 2))
          </body>
        </opml>
        """
    }

    // MARK: - SVG (向量圖)

    /// Render the whole map as an SVG document. Vector output scales
    /// losslessly for print, slides, and web embedding.
    public static func svg(_ document: MindDocument, transparent: Bool = false) -> String {
        let direction = MapDirection(rawValue: document.directionName) ?? .logicRight
        let theme = Theme.named(document.themeName)
        let layouts = LayoutEngine.layout(root: document.root, direction: direction)

        var bounds = CGRect.null
        for l in layouts.values { bounds = bounds.union(l.frame) }
        let pad: CGFloat = 40
        bounds = bounds.insetBy(dx: -pad, dy: -pad)
        let width = max(bounds.width, 1), height = max(bounds.height, 1)

        func hex(_ color: Color) -> String {
            let ns = NSColor(color).usingColorSpace(.sRGB) ?? NSColor.black
            return String(format: "#%02x%02x%02x", Int(round(ns.redComponent * 255)), Int(round(ns.greenComponent * 255)), Int(round(ns.blueComponent * 255)))
        }
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;")
             .replacingOccurrences(of: "<", with: "&lt;")
             .replacingOccurrences(of: ">", with: "&gt;")
             .replacingOccurrences(of: "\"", with: "&quot;")
        }

        func childLinkLabel(_ child: MindNode) -> String {
            document.links.first(where: { $0.to == child.id || $0.from == child.id })?.label ?? ""
        }
        var parts: [String] = []
        if !transparent {
            parts.append("<rect width=\"100%\" height=\"100%\" fill=\"#ffffff\"/>")
        }
        parts.append("<title>\(esc(document.title))</title>")

        // Connections (same shapes as on-screen rendering).
        func connect(_ node: MindNode) {
            guard !node.collapsed else { return }
            guard let pl = layouts[node.id] else { return }
            for child in node.children {
                guard let cl = layouts[child.id] else { continue }
                let toLeft = cl.side == .left
                let from = CGPoint(x: toLeft ? pl.frame.minX : pl.frame.maxX, y: pl.frame.midY)
                let to = CGPoint(x: toLeft ? cl.frame.maxX : cl.frame.minX, y: cl.frame.midY)
                let color = hex(theme.color(forIndex: cl.colorIndex))
                let w: CGFloat = cl.depth == 1 ? 3.5 : 2.5
                if direction == .bracket {
                    let midX = from.x + (to.x - from.x) / 2
                    parts.append("<path d=\"M \(from.x) \(from.y) L \(midX) \(from.y) L \(midX) \(to.y) L \(to.x) \(to.y)\" fill=\"none\" stroke=\"\(color)\" stroke-width=\"\(w)\"/>")
                } else {
                    let midX = (from.x + to.x) / 2
                    parts.append("<path d=\"M \(from.x) \(from.y) C \(midX) \(from.y) \(midX) \(to.y) \(to.x) \(to.y)\" fill=\"none\" stroke=\"\(color)\" stroke-width=\"\(w)\"/>")
                }
                if !childLinkLabel(child).isEmpty {
                    let lx = 0.25 * from.x + 0.5 * ((from.x + to.x) / 2) + 0.25 * to.x
                    let ly = 0.25 * from.y + 0.5 * ((from.y + to.y) / 2) + 0.25 * to.y - 14
                    parts.append("<text x=\"\(lx)\" y=\"\(ly)\" font-size=\"11\" fill=\"#666666\" text-anchor=\"middle\">\(esc(childLinkLabel(child)))</text>")
                }
                connect(child)
            }
        }
        connect(document.root)

        // Summary brackets (same geometry as on-screen rendering).
        for s in document.summaries {
            guard let parentNode = document.root.find(s.parentID),
                  let g = SummaryGeometry.bracket(for: s, parentNode: parentNode, layouts: layouts, origin: .zero)
            else { continue }
            parts.append("<path d=\"M \(g.tickA.x) \(g.tickA.y) L \(g.spineA.x) \(g.spineA.y) L \(g.spineB.x) \(g.spineB.y) L \(g.tickB.x) \(g.tickB.y)\" fill=\"none\" stroke=\"#888888\" stroke-width=\"1.5\"/>")
            let label = s.text.isEmpty ? "概要" : s.text
            parts.append("<text x=\"\(g.textAnchor.x)\" y=\"\(g.textAnchor.y)\" font-size=\"12\" font-weight=\"bold\" fill=\"#666666\" text-anchor=\"middle\">\(esc(label))</text>")
        }

        // Nodes (visual language matches NodeView: root navy, level-1 filled,
        // deeper levels outlined; color-tag bar, star mark, note tooltip, link).
        for l in layouts.values.sorted(by: { $0.depth < $1.depth }) {
            guard let node = document.root.find(l.id) else { continue }
            let f = l.frame
            let color = hex(theme.color(forIndex: l.colorIndex))
            let fill = l.depth >= 2 ? "#ffffff" : (l.depth == 0 ? "#2e3b4f" : color)
            let stroke = l.depth >= 2 ? color : "none"
            var rect = "<rect x=\"\(f.minX)\" y=\"\(f.minY)\" width=\"\(f.width)\" height=\"\(f.height)\" rx=\"9\" fill=\"\(fill)\" stroke=\"\(stroke)\" stroke-width=\"1.5\"/>"
            if !node.note.isEmpty {
                rect += "<title>備註：\(esc(node.note))</title>"
            }
            if let url = node.url, !url.isEmpty {
                parts.append("<a href=\"\(esc(url))\">\(rect)</a>")
            } else {
                parts.append(rect)
            }
            if let key = node.colorTag, let tag = Theme.colorTag(named: key) {
                parts.append("<rect x=\"\(f.minX + 3)\" y=\"\(f.minY + 7)\" width=\"4\" height=\"\(max(f.height - 14, 0))\" rx=\"1.5\" fill=\"\(hex(tag))\"/>")
            }
            if node.marked {
                parts.append("<text x=\"\(f.minX + 6)\" y=\"\(f.minY + 14)\" font-size=\"10\" fill=\"#f5c542\">★</text>")
            }
            let fontSize: CGFloat = l.depth == 0 ? 17 : (l.depth == 1 ? 14 : 12)
            let textColor = l.depth <= 1 ? "#ffffff" : "#1a1a1a"
            parts.append("<text x=\"\(f.midX)\" y=\"\(f.midY + fontSize * 0.35)\" font-family=\"-apple-system, PingFang TC, sans-serif\" font-size=\"\(fontSize)\" fill=\"\(textColor)\" text-anchor=\"middle\">\(esc(node.text))</text>")
        }

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="\(bounds.minX) \(bounds.minY) \(width) \(height)" width="\(width)" height="\(height)">
        \(parts.joined(separator: "\n"))
        </svg>
        """
    }

    // MARK: - FreeMind (.mm)

    /// Exports as a FreeMind `.mm` map so XMind / FreeMind users can open our maps.
    public static func freemind(_ document: MindDocument) -> String {
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;")
             .replacingOccurrences(of: "<", with: "&lt;")
             .replacingOccurrences(of: ">", with: "&gt;")
             .replacingOccurrences(of: "\"", with: "&quot;")
        }
        func nodeXML(_ node: MindNode, depth: Int) -> String {
            let indent = String(repeating: "  ", count: depth)
            var attrs = ""
            let folded = node.collapsed && !node.children.isEmpty ? " FOLDED=\"true\"" : ""
            if let key = node.colorTag, let color = Theme.colorTag(named: key) {
                let ns = NSColor(color).usingColorSpace(.sRGB) ?? NSColor.black
                attrs += String(format: " COLOR=\"#%02x%02x%02x\"", Int(round(ns.redComponent * 255)), Int(round(ns.greenComponent * 255)), Int(round(ns.blueComponent * 255)))
            }
            attrs += folded
            let noteBlock = node.note.isEmpty ? "" : "\n\(indent)  <richcontent TYPE=\"NOTE\"><html><body><p>\(esc(node.note))</p></body></html></richcontent>"
            if node.children.isEmpty {
                if noteBlock.isEmpty {
                    return "\(indent)<node TEXT=\"\(esc(node.text))\"\(attrs)/>"
                }
                return "\(indent)<node TEXT=\"\(esc(node.text))\"\(attrs)>\(noteBlock)\n\(indent)</node>"
            }
            let inner = node.children.map { nodeXML($0, depth: depth + 1) }.joined(separator: "\n")
            return "\(indent)<node TEXT=\"\(esc(node.text))\"\(attrs)>\(noteBlock)\n\(inner)\n\(indent)</node>"
        }
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <map version="1.0.1">
        \(nodeXML(document.root, depth: 1))
        </map>
        """
    }
}
