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

    public static func markdown(_ document: MindDocument, limits: ImportLimits = .standard) throws -> String {
        try validateDepth(document.root, level: 1, limits: limits)
        var emitter = BoundedTextEmitter(limits: limits)
        try emitter.append("# ")
        try emitter.append(document.root.text)
        if !document.root.note.isEmpty {
            try emitter.append("\n> ")
            try emitter.append(document.root.note)
        }

        func walk(_ node: MindNode, level: Int) throws {
            for child in node.children {
                let childLevel = level + 1
                let indent = String(repeating: "  ", count: max(0, childLevel - 2))
                try emitter.append("\n")
                try emitter.append(indent)
                try emitter.append("- ")
                try emitter.append(colorEmoji(child.colorTag))
                if child.marked { try emitter.append("★ ") }
                try emitter.append(child.text)
                if !child.note.isEmpty {
                    try emitter.append("\n")
                    try emitter.append(indent)
                    try emitter.append("  > ")
                    try emitter.append(child.note)
                }
                try walk(child, level: childLevel)
                // Summaries ending at this child are emitted right after its subtree,
                // so the annotated content stays visible in text-based exports.
                for s in document.summaries where s.parentID == node.id && s.endID == child.id {
                    if !s.text.isEmpty {
                        let startIndex = node.children.firstIndex(where: { $0.id == s.startID }) ?? 0
                        let startText = node.children[startIndex].text
                        try emitter.append("\n")
                        try emitter.append(indent)
                        try emitter.append("- ↳ 概要（含")
                        try emitter.append(startText)
                        try emitter.append("）: ")
                        try emitter.append(s.text)
                    }
                }
            }
        }
        try walk(document.root, level: 1)
        try emitter.append("\n")
        return emitter.output()
    }

    public static func opml(_ document: MindDocument, limits: ImportLimits = .standard) throws -> String {
        try validateDepth(document.root, level: 1, limits: limits)
        var emitter = BoundedTextEmitter(limits: limits)
        try emitter.append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n")
        try emitter.append("<opml version=\"2.0\">\n")
        try emitter.append("  <head><title>")
        try emitter.appendEscapedXML(document.title)
        try emitter.append("</title></head>\n  <body>\n")

        func outline(_ node: MindNode, level: Int, indentation: Int) throws {
            let indent = String(repeating: "  ", count: indentation)
            try emitter.append(indent)
            try emitter.append("<outline text=\"")
            try emitter.appendEscapedXML(node.text)
            if !node.note.isEmpty {
                try emitter.append("\" _note=\"")
                try emitter.appendEscapedXML(node.note)
            }
            if node.children.isEmpty {
                try emitter.append("\"/>\n")
                return
            }
            try emitter.append("\">\n")
            for child in node.children {
                try outline(child, level: level + 1, indentation: indentation + 1)
            }
            try emitter.append(indent)
            try emitter.append("</outline>\n")
        }

        try outline(document.root, level: 1, indentation: 2)
        try emitter.append("  </body>\n</opml>\n")
        return emitter.output()
    }

    // MARK: - SVG (向量圖)

    /// Render the whole map as an SVG document. Vector output scales
    /// losslessly for print, slides, and web embedding.
    public static func svg(_ document: MindDocument, transparent: Bool = false) -> String {
        let direction = MapDirection(rawValue: document.directionName) ?? .logicRight
        let palette = Palette.light
        let layouts = LayoutEngine.layout(root: document.root, direction: direction)

        var bounds = CGRect.null
        for l in layouts.values { bounds = bounds.union(l.frame) }
        let pad: CGFloat = 40
        bounds = bounds.insetBy(dx: -pad, dy: -pad)
        let width = max(bounds.width, 1), height = max(bounds.height, 1)

        // SVG is a document export, so it is intentionally stable in light Palette A.
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
            parts.append("<rect width=\"100%\" height=\"100%\" fill=\"\(palette.canvasRGB.hex)\"/>")
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
                let color = hex(palette.color(forIndex: cl.colorIndex))
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
                    parts.append("<text x=\"\(lx)\" y=\"\(ly)\" font-size=\"11\" fill=\"\(hex(palette.textSecondary))\" text-anchor=\"middle\">\(esc(childLinkLabel(child)))</text>")
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
            parts.append("<path d=\"M \(g.tickA.x) \(g.tickA.y) L \(g.spineA.x) \(g.spineA.y) L \(g.spineB.x) \(g.spineB.y) L \(g.tickB.x) \(g.tickB.y)\" fill=\"none\" stroke=\"\(hex(palette.textSecondary))\" stroke-width=\"1.5\"/>")
            let label = s.text.isEmpty ? "概要" : s.text
            parts.append("<text x=\"\(g.textAnchor.x)\" y=\"\(g.textAnchor.y)\" font-size=\"12\" font-weight=\"bold\" fill=\"\(hex(palette.textSecondary))\" text-anchor=\"middle\">\(esc(label))</text>")
        }

        // Nodes use the same NodeStyle geometry as the screen, with Palette.light paint.
        // LayoutEngine remains colour-independent, so its sizing cache is unchanged.
        for l in layouts.values.sorted(by: { $0.depth < $1.depth }) {
            guard let node = document.root.find(l.id) else { continue }
            let f = l.frame
            let style = NodeStyle.of(depth: l.depth, palette: palette, branchColor: palette.color(forIndex: l.colorIndex))
            let strokeAttrs = style.strokeBase.map {
                "stroke=\"\(hex($0))\" stroke-opacity=\"\(style.strokeOpacity)\" stroke-width=\"\(style.strokeWidth)\""
            } ?? "stroke=\"none\""
            var rect = "<rect x=\"\(f.minX)\" y=\"\(f.minY)\" width=\"\(f.width)\" height=\"\(f.height)\" rx=\"\(style.cornerRadius)\" fill=\"\(hex(style.fillBase))\" fill-opacity=\"\(style.fillOpacity)\" \(strokeAttrs)/>"
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
            if let imageDataURL = node.image, !imageDataURL.isEmpty {
                // Embed the attached picture in the upper part of the node frame.
                let imgH = LayoutEngine.imageDisplayHeight
                parts.append("<image href=\"\(esc(imageDataURL))\" x=\"\(f.minX + 7)\" y=\"\(f.minY + 6)\" width=\"\(max(f.width - 14, 1))\" height=\"\(max(imgH - 10, 1))\" preserveAspectRatio=\"xMidYMid meet\"/>")
            }
            if node.marked {
                parts.append("<text x=\"\(f.minX + 6)\" y=\"\(f.minY + 14)\" font-size=\"10\" fill=\"\(hex(palette.statusHighlight))\">★</text>")
            }
            let lines = style.wrappedLines(for: node.text)
            let lineHeight = style.lineHeight
            // Centre the whole block, then step down one line at a time.
            let firstBaseline = f.midY - CGFloat(lines.count - 1) * lineHeight / 2 + lineHeight * 0.35
            for (index, line) in lines.enumerated() {
                let y = firstBaseline + CGFloat(index) * lineHeight
                parts.append("<text x=\"\(f.midX)\" y=\"\(y)\" font-family=\"-apple-system, PingFang TC, sans-serif\" font-size=\"\(style.font.pointSize)\" fill=\"\(hex(style.textColor))\" text-anchor=\"middle\">\(esc(line))</text>")
            }
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
    public static func freemind(_ document: MindDocument, limits: ImportLimits = .standard) throws -> String {
        try validateDepth(document.root, level: 1, limits: limits)
        var emitter = BoundedTextEmitter(limits: limits)
        try emitter.append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n")
        try emitter.append("<map version=\"1.0.1\">\n")

        func nodeXML(_ node: MindNode, level: Int, indentation: Int) throws {
            let indent = String(repeating: "  ", count: indentation)
            try emitter.append(indent)
            try emitter.append("<node TEXT=\"")
            try emitter.appendEscapedXML(node.text)
            if let key = node.colorTag, let color = Theme.colorTag(named: key) {
                let ns = NSColor(color).usingColorSpace(.sRGB) ?? NSColor.black
                let hex = String(format: "%02x%02x%02x", Int(round(ns.redComponent * 255)),
                                 Int(round(ns.greenComponent * 255)), Int(round(ns.blueComponent * 255)))
                try emitter.append("\" COLOR=\"#\(hex)")
            }
            if node.collapsed && !node.children.isEmpty {
                try emitter.append("\" FOLDED=\"true")
            }
            if node.note.isEmpty && node.children.isEmpty {
                try emitter.append("\"/>")
                return
            }
            try emitter.append("\">")
            if !node.note.isEmpty {
                try emitter.append("\n")
                try emitter.append(String(repeating: "  ", count: indentation + 1))
                try emitter.append("<richcontent TYPE=\"NOTE\"><html><body><p>")
                try emitter.appendEscapedXML(node.note)
                try emitter.append("</p></body></html></richcontent>")
            }
            if !node.children.isEmpty {
                try emitter.append("\n")
                for (index, child) in node.children.enumerated() {
                    if index > 0 { try emitter.append("\n") }
                    try nodeXML(child, level: level + 1, indentation: indentation + 1)
                }
                try emitter.append("\n")
                try emitter.append(indent)
            } else {
                try emitter.append("\n")
                try emitter.append(indent)
            }
            try emitter.append("</node>")
        }

        try nodeXML(document.root, level: 1, indentation: 1)
        try emitter.append("\n</map>\n")
        return emitter.output()
    }

    private static func validateDepth(_ node: MindNode, level: Int, limits: ImportLimits) throws {
        guard level <= limits.maxLevels else {
            throw InterchangeError.tooDeep(limit: limits.maxLevels, observedLevel: level)
        }
        for child in node.children {
            try validateDepth(child, level: level + 1, limits: limits)
        }
    }
}
