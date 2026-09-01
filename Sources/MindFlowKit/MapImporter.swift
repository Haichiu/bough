import AppKit
import Foundation

/// Imports Markdown, OPML, and FreeMind interchange documents under one shared
/// byte/depth budget. Native `.mindmap` decoding remains in FileIO.
public enum MapImporter {
    /// Parses OPML bytes after checking the byte budget and UTF-8 validity.
    public static func opml(_ data: Data, limits: ImportLimits = .standard) throws -> MindDocument {
        try opml(checkedText(data, limits: limits), limits: limits)
    }

    /// Parses an OPML string. Root level is 1.
    public static func opml(_ xml: String, limits: ImportLimits = .standard) throws -> MindDocument {
        try checkTextSize(xml, limits: limits)
        let parser = XMLParser(data: Data(xml.utf8))
        let delegate = OPMLParserDelegate(limits: limits)
        parser.delegate = delegate
        guard parser.parse() else {
            if let failure = delegate.failure { throw failure }
            throw InterchangeError.invalidFormat
        }
        if let failure = delegate.failure { throw failure }
        guard let root = delegate.root else { throw InterchangeError.invalidFormat }
        return MindDocument(title: delegate.title ?? root.text, root: root)
    }

    /// Parses FreeMind/XMind bytes after checking the byte budget and UTF-8.
    public static func freemind(_ data: Data, limits: ImportLimits = .standard) throws -> MindDocument {
        try freemind(checkedText(data, limits: limits), limits: limits)
    }

    /// Parses a FreeMind/XMind string. Root level is 1.
    public static func freemind(_ xml: String, limits: ImportLimits = .standard) throws -> MindDocument {
        try checkTextSize(xml, limits: limits)
        let parser = XMLParser(data: Data(xml.utf8))
        let delegate = FreeMindParserDelegate(limits: limits)
        parser.delegate = delegate
        guard parser.parse() else {
            if let failure = delegate.failure { throw failure }
            throw InterchangeError.invalidFormat
        }
        if let failure = delegate.failure { throw failure }
        guard let root = delegate.root else { throw InterchangeError.invalidFormat }
        return MindDocument(title: delegate.title ?? root.text, root: root)
    }

    /// Parses Markdown bytes after checking the byte budget and UTF-8.
    public static func markdown(_ data: Data, limits: ImportLimits = .standard) throws -> MindDocument {
        try markdown(checkedText(data, limits: limits), limits: limits)
    }

    /// Parses an indented Markdown outline. The synthetic root is level 1;
    /// the first outline item is level 2.
    public static func markdown(_ text: String, limits: ImportLimits = .standard) throws -> MindDocument {
        try checkTextSize(text, limits: limits)
        let rootNode = TempNode(text: "中心主題")
        var stack: [(node: TempNode, indent: Int, level: Int)] = [(rootNode, -1, 1)]
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
            let level = stack.last!.level + 1
            guard level <= limits.maxLevels else {
                throw InterchangeError.tooDeep(limit: limits.maxLevels, observedLevel: level)
            }
            let node = TempNode(text: content)
            stack.last!.node.children.append(node)
            stack.append((node, indent, level))
            last = node
        }

        func convert(_ temp: TempNode) -> MindNode {
            MindNode(text: temp.text, note: temp.note,
                     children: temp.children.map(convert))
        }
        return MindDocument(title: rootNode.text, root: convert(rootNode))
    }

    private static func checkedText(_ data: Data, limits: ImportLimits) throws -> String {
        guard data.count <= limits.maxBytes else {
            throw InterchangeError.tooLarge(limit: limits.maxBytes, observed: data.count)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw InterchangeError.invalidUTF8
        }
        return text
    }

    private static func checkTextSize(_ text: String, limits: ImportLimits) throws {
        guard text.utf8.count <= limits.maxBytes else {
            throw InterchangeError.tooLarge(limit: limits.maxBytes, observed: text.utf8.count)
        }
    }

    private final class TempNode {
        var text: String
        var note: String = ""
        var children: [TempNode] = []

        init(text: String) {
            self.text = text
        }
    }
}

private final class FreeMindParserDelegate: NSObject, XMLParserDelegate {
    private final class Node {
        var text = ""
        var note = ""
        var collapsed = false
        var colorTag: String?
        var children: [Node] = []
    }

    private let limits: ImportLimits
    private var stack: [Node] = []
    private var rootNode: Node?
    private(set) var title: String?
    private var noteBuffer: String?
    private(set) var failure: InterchangeError?

    init(limits: ImportLimits) {
        self.limits = limits
    }

    var root: MindNode? {
        rootNode.map(convert)
    }

    private func convert(_ node: Node) -> MindNode {
        MindNode(text: node.text, note: node.note, collapsed: node.collapsed,
                 colorTag: node.colorTag, children: node.children.map(convert))
    }

    private func rejectTooDeep(_ parser: XMLParser, level: Int) {
        guard failure == nil else { return }
        failure = .tooDeep(limit: limits.maxLevels, observedLevel: level)
        parser.abortParsing()
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        switch name.lowercased() {
        case "node":
            let level = stack.count + 1
            guard level <= limits.maxLevels else {
                rejectTooDeep(parser, level: level)
                return
            }
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
        switch name.lowercased() {
        case "richcontent":
            // FreeMind wraps notes in <richcontent TYPE="NOTE">…<p>text</p>…</richcontent>.
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

    private let limits: ImportLimits
    // Keep the effective document level with each parser node. Later OPML
    // top-level outlines are adopted under the first root, so stack depth alone
    // is not their structural depth.
    private var stack: [(node: Node, level: Int)] = []
    private var rootNode: Node?
    private(set) var title: String?
    private var inTitle = false
    private var titleBuffer = ""
    private(set) var failure: InterchangeError?

    init(limits: ImportLimits) {
        self.limits = limits
    }

    var root: MindNode? {
        rootNode.map(convert)
    }

    private func convert(_ node: Node) -> MindNode {
        MindNode(text: node.text, note: node.note, children: node.children.map(convert))
    }

    private func rejectTooDeep(_ parser: XMLParser, level: Int) {
        guard failure == nil else { return }
        failure = .tooDeep(limit: limits.maxLevels, observedLevel: level)
        parser.abortParsing()
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        switch name.lowercased() {
        case "outline":
            // OPML permits multiple body outlines; the existing importer treats
            // later top-level outlines as children of the established root.
            // Carry the adopted node's actual level so its children continue at
            // level + 1 rather than restarting from parser stack depth.
            let level = stack.last.map { $0.level + 1 } ?? (rootNode == nil ? 1 : 2)
            guard level <= limits.maxLevels else {
                rejectTooDeep(parser, level: level)
                return
            }
            let node = Node()
            node.text = attributeDict["text"] ?? ""
            node.note = attributeDict["_note"] ?? ""
            if let parent = stack.last {
                parent.node.children.append(node)
            } else if let establishedRoot = rootNode {
                establishedRoot.children.append(node)
            } else {
                rootNode = node
            }
            stack.append((node, level))
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
            if !stack.isEmpty { stack.removeLast() }
        case "title":
            let trimmed = titleBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
            title = trimmed.isEmpty ? nil : trimmed
            inTitle = false
        default:
            break
        }
    }
}
