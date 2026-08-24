import Foundation

/// Text-based export formats for mind maps.
public enum MapExporter {
    public static func markdown(_ document: MindDocument) -> String {
        var lines: [String] = ["# \(document.root.text)"]
        if !document.root.note.isEmpty {
            lines.append("> \(document.root.note)")
        }
        func walk(_ node: MindNode, level: Int) {
            for child in node.children {
                let indent = String(repeating: "  ", count: level)
                let star = child.marked ? "★ " : ""
                lines.append("\(indent)- \(star)\(child.text)")
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
}
