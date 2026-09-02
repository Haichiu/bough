import Foundation

/// Pure, deterministic display labels for the open-document tab bar.
///
/// The active slot is deliberately resolved from the live editor values rather
/// than its last stashed session snapshot. Suffixes are allocated after middle
/// truncation so the string rendered by SwiftUI is already unique.
public enum TabDisplayTitles {
    public static let defaultMaximumGraphemes = 16

    public static func resolve(
        sessions: [EditorSession],
        activeIndex: Int,
        liveDocument: MindDocument,
        liveFilePath: URL?,
        maximumGraphemes: Int = defaultMaximumGraphemes
    ) -> [String] {
        let budget = max(maximumGraphemes, 1)
        var used = Set<String>()

        return sessions.indices.map { index in
            let document: MindDocument
            let filePath: URL?
            if index == activeIndex {
                document = liveDocument
                filePath = liveFilePath
            } else {
                document = sessions[index].document
                filePath = sessions[index].filePath
            }

            let base = middleTruncate(baseName(document: document, filePath: filePath),
                                      maximumGraphemes: budget)
            return allocate(base, used: &used)
        }
    }

    private static func baseName(document: MindDocument, filePath: URL?) -> String {
        let rootText = trimmed(document.root.text)
        if !rootText.isEmpty && rootText != "中心主題" {
            return rootText
        }

        if let filePath {
            let fileName = trimmed(filePath.deletingPathExtension().lastPathComponent)
            if !fileName.isEmpty {
                return fileName
            }
        }

        let documentTitle = trimmed(document.title)
        if !documentTitle.isEmpty && documentTitle != "未命名心智圖" {
            return documentTitle
        }

        if let descendant = firstNonEmptyDescendant(of: document.root) {
            return descendant
        }
        return "中心主題"
    }

    private static func firstNonEmptyDescendant(of node: MindNode) -> String? {
        for child in node.children {
            let text = trimmed(child.text)
            if !text.isEmpty {
                return text
            }
            if let descendant = firstNonEmptyDescendant(of: child) {
                return descendant
            }
        }
        return nil
    }

    private static func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func middleTruncate(_ value: String, maximumGraphemes: Int) -> String {
        let characters = Array(value)
        guard characters.count > maximumGraphemes else { return value }

        // The ellipsis occupies one grapheme; keep the extra character on the
        // leading side so the split is stable for both odd and even budgets.
        let retained = maximumGraphemes - 1
        let leading = (retained + 1) / 2
        let trailing = retained - leading
        return String(characters.prefix(leading))
            + "…"
            + String(characters.suffix(trailing))
    }

    private static func allocate(_ base: String, used: inout Set<String>) -> String {
        guard used.contains(base) else {
            used.insert(base)
            return base
        }

        var suffix = 2
        while true {
            let candidate = "\(base) · \(suffix)"
            if !used.contains(candidate) {
                used.insert(candidate)
                return candidate
            }
            suffix += 1
        }
    }
}
