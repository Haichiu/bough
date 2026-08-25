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

        // Nodes.
        for l in layouts.values.sorted(by: { $0.depth < $1.depth }) {
            guard let node = document.root.find(l.id) else { continue }
            let f = l.frame
            let color = hex(theme.color(forIndex: l.colorIndex))
            parts.append("<rect x=\"\(f.minX)\" y=\"\(f.minY)\" width=\"\(f.width)\" height=\"\(f.height)\" rx=\"9\" fill=\"\(color)\" stroke=\"\(color)\" stroke-width=\"1.5\"/>")
            let fontSize: CGFloat = l.depth == 0 ? 17 : (l.depth == 1 ? 14 : 12)
            let textColor = l.depth == 0 ? "#ffffff" : "#1a1a1a"
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
            let folded = node.collapsed && !node.children.isEmpty ? " FOLDED=\"true\"" : ""
            if node.children.isEmpty {
                return "\(indent)<node TEXT=\"\(esc(node.text))\"\(folded)/>"
            }
            let inner = node.children.map { nodeXML($0, depth: depth + 1) }.joined(separator: "\n")
            return "\(indent)<node TEXT=\"\(esc(node.text))\"\(folded)>\n\(inner)\n\(indent)</node>"
        }
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <map version="1.0.1">
        \(nodeXML(document.root, depth: 1))
        </map>
        """
    }
}
