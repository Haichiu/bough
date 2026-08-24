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
    var isSearchHit: Bool = false
    let onCancelEdit: () -> Void
    let onCommitEdit: (String) -> Void

    @State private var editText = ""
    @State private var isHovered = false
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
        .opacity(isDragging ? 0.85 : 1)
        .offset(x: dragOffset?.width ?? 0, y: dragOffset?.height ?? 0)
        .overlay(alignment: .trailing) { collapsedBadge }
        .overlay(alignment: .leading) { markedBadge }
        .overlay(alignment: .topLeading) { noteBadge }
        .accessibilityLabel(node.displayText + (node.note.isEmpty ? "" : "，有備註"))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .help(node.note.isEmpty ? "" : "備註：\(node.note)")
        .help(node.note.isEmpty ? "" : "備註：\(node.note)")
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
                .fill(Color(hex: 0x2E3A4E))
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
            TextField("", text: $editText)
                .textFieldStyle(.plain)
                .font(Font(LayoutEngine.font(for: depth)))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 10)
                .focused($editFocused)
                .onSubmit { onCommitEdit(editText) }
                .onExitCommand { onCancelEdit() }
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

    @ViewBuilder
    private var collapsedBadge: some View {
        if node.collapsed && !node.children.isEmpty {
            Text("\(node.children.count)")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(branchColor))
                .overlay(Circle().stroke(Color(nsColor: .controlBackgroundColor), lineWidth: 1.5))
                .offset(x: 10)
                .onTapGesture { onToggleCollapse?() }
                .help("展開子主題")
        }
    }
}
