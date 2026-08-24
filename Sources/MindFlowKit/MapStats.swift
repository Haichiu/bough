import Foundation

/// Aggregate health metrics for a whole document.
public struct MapStats: Equatable {
    public let nodeCount: Int
    public let maxDepth: Int
    public let noteCount: Int
    public let markedCount: Int
    public let collapsedCount: Int
    public let linkCount: Int
}

public extension MindDocument {
    func stats() -> MapStats {
        var nodeCount = 0
        var maxDepth = 0
        var notes = 0
        var marks = 0
        var collapsedCount = 0

        func walk(_ node: MindNode, depth: Int) {
            nodeCount += 1
            maxDepth = max(maxDepth, depth)
            if !node.note.isEmpty { notes += 1 }
            if node.marked { marks += 1 }
            if node.collapsed { collapsedCount += 1 }
            for child in node.children {
                walk(child, depth: depth + 1)
            }
        }
        walk(root, depth: 0)

        return MapStats(nodeCount: nodeCount,
                        maxDepth: maxDepth + 1,
                        noteCount: notes,
                        markedCount: marks,
                        collapsedCount: collapsedCount,
                        linkCount: links.count)
    }
}
