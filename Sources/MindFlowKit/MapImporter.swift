import AppKit
import Foundation

/// Imports indented Markdown outlines (bullets, headings) and OPML files as mind maps.
public enum MapImporter {

    /// Imports OPML outlines produced by this app and most outlining tools.
    public static func opml(_ xml: String) -> MindDocument? {
        let parser = XMLParser(data: Data(xml.utf8))
        let delegate = OPMLParserDelegate()
        parser.delegate = delegate
        guard parser.parse(), let root = delegate.root else { return nil }
        return MindDocument(title: delegate.title ?? root.text, root: root)
    }

    /// Imports FreeMind / XMind `.mm` files so users can migrate their maps.
    public static func freemind(_ xml: String) -> MindDocument? {
        let parser = XMLParser(data: Data(xml.utf8))
        let delegate = FreeMindParserDelegate()
        parser.delegate = delegate
        guard parser.parse(), let root = delegate.root else { return nil }
        return MindDocument(title: delegate.title ?? root.text, root: root)
    }
}

private final class FreeMindParserDelegate: NSObject, XMLParserDelegate {
    private final class Node {
        var text = ""
        var note = ""
        var collapsed = false
        var colorTag: String? = nil
        var children: [Node] = []
    }

    private var stack: [Node] = []
    private var rootNode: Node?
    private(set) var title: String?
    private var noteBuffer: String? = nil

    var root: MindNode? {
        rootNode.map(convert)
    }

    private func convert(_ node: Node) -> MindNode {
        MindNode(text: node.text, note: node.note, collapsed: node.collapsed,
                 colorTag: node.colorTag, children: node.children.map(convert))
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        switch name.lowercased() {
        case "node":
            let node = Node()
            // FreeMind stores the label in the TEXT attribute; some exporters use TEXT="" with richcontent.
            func attr(_ key: String) -> String {
                attributeDict.first(where: { $0.key.caseInsensitiveCompare(key) == .orderedSame })?.value ?? ""
            }
            node.text = attr("text")
            node.collapsed = attr("folded").lowercased() == "true"
            // FreeMind colors nodes with a hex COLOR attribute; map to our nearest tag.
            let colorHex = attr("color").trimmingCharacters(in: CharacterSet(charactersIn: "#")).lowercased()
            if !colorHex.isEmpty {
                node.colorTag = Theme.colorTags.first(where: { tag in
                    let ns = NSColor(tag.color).usingColorSpace(.sRGB) ?? NSColor.black
                    let candidate = String(format: "%02x%02x%02x", Int(round(ns.redComponent * 255)), Int(round(ns.greenComponent * 255)), Int(round(ns.blueComponent * 255)))
                    return candidate == colorHex
                })?.key
            }
            if let parent = stack.last {
                parent.children.append(node)
            } else {
                rootNode = node
            }
            stack.append(node)
        case "richcontent":
            let type = attributeDict.first(where: { $0.key.caseInsensitiveCompare("type") == .orderedSame })?.value ?? ""
            if type.uppercased() == "NOTE" && noteBuffer == nil {
                noteBuffer = ""
            }
        case "map":
            if let name = attributeDict["name"], !name.isEmpty { title = name }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if noteBuffer != nil { noteBuffer? += string }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName qName: String?) {
        let lower = name.lowercased()
        switch lower {
        case "richcontent":
            // FreeMind wraps notes in <richcontent TYPE="NOTE">…<p>text</p>…</richcontent>
            if let buffered = noteBuffer?.trimmingCharacters(in: .whitespacesAndNewlines), !buffered.isEmpty,
               let current = stack.last {
                current.note = current.note.isEmpty ? buffered : current.note + "\n" + buffered
            }
            noteBuffer = nil
        case "node":
            if !stack.isEmpty { stack.removeLast() }
        default:
            break
        }
    }
}

private final class OPMLParserDelegate: NSObject, XMLParserDelegate {
    private final class Node {
        var text = ""
        var note = ""
        var children: [Node] = []
    }

    private var stack: [Node] = []
    private var rootNode: Node?
    private(set) var title: String?
    private var inTitle = false
    private var titleBuffer = ""

    var root: MindNode? {
        rootNode.map(convert)
    }

    private func convert(_ node: Node) -> MindNode {
        MindNode(text: node.text, note: node.note, children: node.children.map(convert))
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        switch name.lowercased() {
        case "outline":
            let node = Node()
            node.text = attributeDict["text"] ?? ""
            node.note = attributeDict["_note"] ?? ""
            if let parent = stack.last {
                parent.children.append(node)
            } else if let establishedRoot = rootNode {
                establishedRoot.children.append(node)
            } else {
                rootNode = node
            }
            stack.append(node)
        case "title":
            inTitle = true
            titleBuffer = ""
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inTitle { titleBuffer += string }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch name.lowercased() {
        case "outline":
            stack.removeLast()
        case "title":
            let trimmed = titleBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            title = trimmed.isEmpty ? nil : trimmed
            inTitle = false
        default:
            break
        }
    }
}

extension MapImporter {
    private final class TempNode {
        var text: String
        var note: String = ""
        var children: [TempNode] = []
        init(text: String) { self.text = text }
    }

    public static func markdown(_ text: String) -> MindDocument? {
        var rootNode = TempNode(text: "中心主題")
        // Path of (node, indent) from root to current position.
        var stack: [(node: TempNode, indent: Int)] = [(rootNode, -1)]
        var last: TempNode?

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine).trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            if line.hasPrefix("#") {
                let heading = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                if !heading.isEmpty {
                    rootNode.text = heading
                    last = nil
                }
                continue
            }

            if line.hasPrefix(">") {
                let note = line.dropFirst().trimmingCharacters(in: .whitespaces)
                if !note.isEmpty { last?.note = note }
                continue
            }

            let leading = String(rawLine).prefix(while: { $0 == " " || $0 == "\t" })
            let indent = leading.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
            let bullet = line.drop(while: { $0 == "-" || $0 == "*" || $0 == "+" || $0 == " " })
            let content = bullet.trimmingCharacters(in: .whitespaces)
            guard !content.isEmpty else { continue }

            while stack.count > 1, let top = stack.last, top.indent >= indent {
                stack.removeLast()
            }
            let node = TempNode(text: content)
            stack.last!.node.children.append(node)
            stack.append((node, indent))
            last = node
        }

        func convert(_ temp: TempNode) -> MindNode {
            MindNode(text: temp.text, note: temp.note,
                     children: temp.children.map(convert))
        }
        return MindDocument(title: rootNode.text, root: convert(rootNode))
    }
}
