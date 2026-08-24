import Foundation

public struct OutlineRow: Equatable, Identifiable {
    public let id: UUID
    public let text: String
    public let marked: Bool
    public let note: String
    public let depth: Int
    public let isRoot: Bool
    public let hasChildren: Bool
    public let collapsed: Bool
}

/// Flattens the node tree into ordered rows for the outline view,
/// skipping children of collapsed branches (stays in sync with the map).
public enum OutlineFlattener {
    public static func flatten(_ root: MindNode) -> [OutlineRow] {
        var rows: [OutlineRow] = []
        func walk(_ node: MindNode, depth: Int, isRoot: Bool) {
            rows.append(OutlineRow(id: node.id,
                                   text: node.text,
                                   marked: node.marked,
                                   note: node.note,
                                   depth: depth,
                                   isRoot: isRoot,
                                   hasChildren: !node.children.isEmpty,
                                   collapsed: node.collapsed))
            guard !node.collapsed else { return }
            for child in node.children {
                walk(child, depth: depth + 1, isRoot: false)
            }
        }
        walk(root, depth: 0, isRoot: true)
        return rows
    }
}
