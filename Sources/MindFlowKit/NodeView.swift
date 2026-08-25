import SwiftUI

struct NodeView: View {
    let node: MindNode
    let layout: NodeLayout
    let branchColor: Color
    let isSelected: Bool
    let isEditing: Bool
    let isDropTarget: Bool
    var onToggleCollapse: (() -> Void)? = nil
    var isFresh: Bool = false
    var isDragging: Bool = false
    var dragOffset: CGSize? = nil
    var hasURL: Bool = false
    var isSearchHit: Bool = false
    var colorTag: String? = nil
    var dimmed: Bool = false
    let onCancelEdit: (String) -> Void
    let onCommitEdit: (String) -> Void

    @State private var editText = ""
    @State private var isHovered = false
    @State private var escDiscard = false
    @State private var freshScale: CGFloat = 1
    @State private var freshOpacity: Double = 1
    @FocusState private var editFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let depth = layout.depth
        let radius = LayoutEngine.cornerRadius(for: depth)

        ZStack {
            background(depth: depth, radius: radius)
            content(depth: depth)
        }
        .frame(width: layout.frame.width, height: layout.frame.height)
        .overlay(selectionRing(radius: radius))
        .scaleEffect(freshScale)
        .opacity(freshOpacity)
        .opacity(dimmed ? 0.15 : 1)
        .opacity(isDragging ? 0.85 : 1)
        .offset(x: dragOffset?.width ?? 0, y: dragOffset?.height ?? 0)
        .overlay(alignment: .trailing) { collapsedBadge }
        .overlay(alignment: .leading) { markedBadge }
        .overlay(alignment: .leading) { colorBar }
        .overlay(alignment: .topLeading) { noteBadge }
        .overlay(alignment: .topTrailing) { urlBadge }
        .accessibilityLabel(node.displayText + (node.note.isEmpty ? "" : "，有備註"))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .help(node.note.isEmpty ? "" : "備註：\(node.note)")
        .help(node.note.isEmpty ? "" : "備註：\(node.note)")
        .onChange(of: isEditing) { editing in
            // Clicking away confirms the edit; only Esc discards.
            if !editing && !escDiscard {
                let trimmed = editText.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed != node.text.trimmingCharacters(in: .whitespacesAndNewlines) {
                    onCommitEdit(editText)
                }
            }
            escDiscard = false
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15),
                   value: isSelected || isHovered || isDropTarget)
        .onChange(of: isEditing) { editing in
            if editing {
                editText = node.text
                editFocused = true
            }
        }
        .onAppear {
            if isEditing {
                editText = node.text
                DispatchQueue.main.async { editFocused = true }
            }
            if isFresh && !reduceMotion {
                freshScale = 0.85
                freshOpacity = 0.2
                withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) {
                    freshScale = 1
                    freshOpacity = 1
                }
            }
        }
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    @ViewBuilder
    private func background(depth: Int, radius: CGFloat) -> some View {
        if depth == 0 {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Theme.rootBackground)
        } else if depth == 1 {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(branchColor)
        } else {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(branchColor, lineWidth: 1.5)
                )
        }
    }

    @ViewBuilder
    private func content(depth: Int) -> some View {
        if isEditing {
            ZStack(alignment: .center) {
                if editText.isEmpty {
                    Text("輸入文字…")
                        .font(Font(LayoutEngine.font(for: depth)))
                        .foregroundStyle(Color.secondary.opacity(0.6))
                        .allowsHitTesting(false)
                }
                TextField("", text: $editText)
                .textFieldStyle(.plain)
                .font(Font(LayoutEngine.font(for: depth)))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 10)
                .focused($editFocused)
                .onSubmit { onCommitEdit(editText) }
                .onExitCommand {
                    escDiscard = true
                    onCancelEdit(editText)
                }
            }
        } else {
            Text(node.text.isEmpty ? " " : node.text)
                .font(Font(LayoutEngine.font(for: depth)))
                .foregroundStyle(depth <= 1 ? Color.white : Color.primary)
                .lineLimit(3)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 6)
        }
    }

    @ViewBuilder
    private func selectionRing(radius: CGFloat) -> some View {
        if isSearchHit && !isSelected && !isDropTarget {
            RoundedRectangle(cornerRadius: radius + 3, style: .continuous)
                .stroke(Color(hex: 0xF5C542), lineWidth: 2)
                .padding(-4)
        }
        if isSelected || isDropTarget || isHovered {
            RoundedRectangle(cornerRadius: radius + 3, style: .continuous)
                .stroke(isDropTarget ? Color.green
                            : (isSelected ? Color.accentColor : Color.secondary.opacity(0.45)),
                        lineWidth: isDropTarget ? 3 : (isSelected ? 2 : 1.5))
                .padding(-4)
        }
    }

    @ViewBuilder
    private var colorBar: some View {
        if let key = colorTag, let color = Theme.colorTag(named: key) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(color)
                .frame(width: 4)
                .padding(.vertical, 7)
                .padding(.leading, 3)
        }
    }

    @ViewBuilder
    private var noteBadge: some View {
        if !node.note.isEmpty && !isEditing {
            Image(systemName: "note.text")
                .font(.system(size: 9))
                .foregroundStyle(Color.secondary)
                .offset(x: -9, y: -9)
        }
    }

    @ViewBuilder
    private var markedBadge: some View {
        if node.marked && !isEditing {
            Image(systemName: "star.fill")
                .font(.system(size: 9))
                .foregroundStyle(Color(hex: 0xF5C542))
                .offset(x: -10)
        }
    }

    private var hiddenCount: Int {
        node.descendantIDs().count
    }

    @ViewBuilder
    private var urlBadge: some View {
        if hasURL {
            Image(systemName: "link.circle.fill")
                .font(.system(size: 9))
                .foregroundStyle(Color(hex: 0x4A90D9))
                .offset(x: -6, y: -6)
        }
    }

    @ViewBuilder
    private var collapsedBadge: some View {
        if node.collapsed && !node.children.isEmpty {
            Text("\(hiddenCount)")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(branchColor))
                .overlay(Circle().stroke(Color(nsColor: .controlBackgroundColor), lineWidth: 1.5))
                .offset(x: 10)
                .onTapGesture { onToggleCollapse?() }
                .help("收合中（共 \(hiddenCount) 個主題）：\n" + node.hiddenTopicPreview().joined(separator: "\n"))
        }
    }
}
