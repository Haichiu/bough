import CoreGraphics
import Foundation

public struct MindNode: Codable, Identifiable, Equatable {
    public var id: UUID = UUID()
    public var text: String = ""
    public var note: String = ""
    public var collapsed: Bool = false
    public var marked: Bool = false
    public var url: String?
    public var colorTag: String?
    public var children: [MindNode] = []

    private enum CodingKeys: String, CodingKey {
        case id, text, note, collapsed, marked, colorTag, url, children
    }

    public init(id: UUID = UUID(), text: String = "", note: String = "",
                collapsed: Bool = false, marked: Bool = false,
                colorTag: String? = nil, url: String? = nil,
                children: [MindNode] = []) {
        self.id = id
        self.text = text
        self.note = note
        self.collapsed = collapsed
        self.marked = marked
        self.colorTag = colorTag
        self.url = url
        self.children = children
    }

    /// Tolerant decoding so documents saved before newer fields exist still load.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        collapsed = try container.decodeIfPresent(Bool.self, forKey: .collapsed) ?? false
        colorTag = try container.decodeIfPresent(String.self, forKey: .colorTag)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        marked = try container.decodeIfPresent(Bool.self, forKey: .marked) ?? false
        children = try container.decodeIfPresent([MindNode].self, forKey: .children) ?? []
    }

    public func find(_ id: UUID) -> MindNode? {
        if id == self.id { return self }
        for child in children {
            if let hit = child.find(id) { return hit }
        }
        return nil
    }

    public func contains(_ id: UUID) -> Bool {
        find(id) != nil
    }

    /// Ordered texts of every hidden descendant (breadth-first), capped at limit.
    public func hiddenTopicPreview(limit: Int = 6) -> [String] {
        var out: [String] = []
        var queue: [MindNode] = children
        while !queue.isEmpty && out.count < limit {
            let node = queue.removeFirst()
            out.append(node.text)
            queue.append(contentsOf: node.children)
        }
        return out
    }

    public var displayText: String {
        (marked ? "★ " : "") + text
    }

    public func isAncestor(of id: UUID) -> Bool {
        children.contains { $0.id == id || $0.isAncestor(of: id) }
    }

    /// Returns the node whose direct child has the given id.
    public func parent(of id: UUID) -> MindNode? {
        if children.contains(where: { $0.id == id }) { return self }
        for child in children {
            if let hit = child.parent(of: id) { return hit }
        }
        return nil
    }

    public func descendantIDs() -> Set<UUID> {
        var ids = Set<UUID>()
        for child in children {
            ids.insert(child.id)
            ids.formUnion(child.descendantIDs())
        }
        return ids
    }

    /// Mutates the node with the given id in place. Returns true if found.
    @discardableResult
    public mutating func update(_ id: UUID, _ transform: (inout MindNode) -> Void) -> Bool {
        if id == self.id {
            transform(&self)
            return true
        }
        for index in children.indices {
            if children[index].update(id, transform) { return true }
        }
        return false
    }

    /// Removes the node with the given id (only from nested positions).
    @discardableResult
    public mutating func remove(_ id: UUID) -> MindNode? {
        if let index = children.firstIndex(where: { $0.id == id }) {
            return children.remove(at: index)
        }
        for index in children.indices {
            if let removed = children[index].remove(id) { return removed }
        }
        return nil
    }
}

public struct MindLink: Codable, Equatable, Identifiable {
    public var id: UUID = UUID()
    public var from: UUID
    public var to: UUID
    /// Optional text shown on the associative line (e.g. 「導致」「參考」).
    public var label: String = ""

    public init(id: UUID = UUID(), from: UUID, to: UUID, label: String = "") {
        self.id = id
        self.from = from
        self.to = to
        self.label = label
    }

    private enum CodingKeys: String, CodingKey { case id, from, to, label }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        from = try c.decode(UUID.self, forKey: .from)
        to = try c.decode(UUID.self, forKey: .to)
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
    }
}

public struct MindDocument: Codable, Equatable {
    public var title: String
    public var themeName: String
    public var directionName: String
    public var root: MindNode
    public var links: [MindLink]
    public var offsets: [String: CGPoint]

    private enum CodingKeys: String, CodingKey {
        case title, themeName, directionName, root, links, offsets
    }

    public init(title: String = "未命名心智圖", themeName: String = "ocean",
                directionName: String = MapDirection.logicRight.rawValue, root: MindNode,
                links: [MindLink] = [], offsets: [String: CGPoint] = [:]) {
        self.title = title
        self.themeName = themeName
        self.directionName = directionName
        self.root = root
        self.links = links
        self.offsets = offsets
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "未命名心智圖"
        themeName = try container.decodeIfPresent(String.self, forKey: .themeName) ?? "ocean"
        directionName = try container.decodeIfPresent(String.self, forKey: .directionName)
            ?? MapDirection.logicRight.rawValue
        root = try container.decode(MindNode.self, forKey: .root)
        links = try container.decodeIfPresent([MindLink].self, forKey: .links) ?? []
        offsets = try container.decodeIfPresent([String: CGPoint].self, forKey: .offsets) ?? [:]
    }

    public static func new() -> MindDocument {
        let defaults = UserDefaults.standard
        let theme = defaults.string(forKey: "defaultTheme") ?? "ocean"
        let direction = defaults.string(forKey: "defaultDirection")
            ?? MapDirection.logicRight.rawValue
        return MindDocument(title: "未命名心智圖", themeName: theme,
                            directionName: direction, root: MindNode(text: "中心主題"))
    }
}
