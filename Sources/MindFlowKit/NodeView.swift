import SwiftUI

struct NodeView: View {
    let node: MindNode
    let layout: NodeLayout
    let palette: Palette
    let interactionScale: CGFloat
    let branchColor: Color
    let isSelected: Bool
    var isBatchMember: Bool = false
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
    /// Live-store seed for the editor draft (D2): the replacement lands in the
    /// store before the editor opens, so the draft must be read from the live
    /// document at seed time, never from a possibly pre-replacement snapshot.
    var editSeed: (() -> String)? = nil
    let onCancelEdit: (String) -> Void
    /// Called when editing ends without an explicit Return — clicking away, or the
    /// selection moving on. Commits the text and nothing else.
    let onCommitEdit: (String) -> Void
    /// Called only for an explicit Return inside the editor. Kept separate because
    /// Return also means "give me the next sibling", and that must not fire on the
    /// implicit commit path.
    var onSubmitEdit: ((String) -> Void)? = nil

    @State private var editText = ""
    @State private var isHovered = false
    @State private var escDiscard = false
    /// Return already committed through onSubmitEdit; stop the isEditing observer
    /// from committing the same text a second time.
    @State private var submitted = false
    @State private var freshScale: CGFloat = 1
    @State private var freshOpacity: Double = 1
    @FocusState private var editFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The editor's starting draft: the live document text when available, the
    /// snapshot only as a fallback. Seeding from the snapshot alone resurrects
    /// the pre-replacement text on commit (the D2 swallow bug).
    static func editSeed(live: String?, snapshot: String) -> String {
        live ?? snapshot
    }

    var body: some View {
        let depth = layout.depth
        let radius = LayoutEngine.cornerRadius(for: depth)

        ZStack {
            background(depth: depth, radius: radius)
            if let nsImage = ImageStore.shared.image(forDataURL: node.image) {
                VStack(spacing: 3) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: layout.frame.width - 14)
                        .frame(height: LayoutEngine.imageDisplayHeight - 6)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    content(depth: depth)
                }
                .padding(.horizontal, 5)
            } else {
                content(depth: depth)
            }
        }
        .frame(width: layout.frame.width, height: layout.frame.height)
        .overlay(selectionRing(radius: radius))
        .scaleEffect(freshScale)
        .opacity(freshOpacity)
        .opacity(dimmed ? 0.15 : 1)
        .opacity(isDragging ? 0.6 : 1)
        .offset(x: dragOffset?.width ?? 0, y: dragOffset?.height ?? 0)
        .overlay(alignment: .trailing) { collapsedBadge }
        .overlay(alignment: .topLeading) { markedBadge }
        .overlay(alignment: .leading) { colorBar }
        .overlay(alignment: .topLeading) { noteBadge }
        .overlay(alignment: .topTrailing) { urlBadge }
        .accessibilityLabel(node.displayText + (node.note.isEmpty ? "" : "，有備註"))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .help(node.note.isEmpty ? "" : "備註：\(node.note)")
        .help(node.note.isEmpty ? "" : "備註：\(node.note)")
        .onChange(of: isEditing) { editing in
            // Clicking away confirms the edit; only Esc discards.
            if !editing && !escDiscard && !submitted {
                let trimmed = editText.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed != node.text.trimmingCharacters(in: .whitespacesAndNewlines) {
                    onCommitEdit(editText)
                }
            }
            escDiscard = false
            submitted = false
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15),
                   value: isSelected || isHovered || isDropTarget)
        .onChange(of: isEditing) { editing in
            if editing {
                editText = Self.editSeed(live: editSeed?(), snapshot: node.text)
                editFocused = true
            }
        }
        .onAppear {
            if isEditing {
                editText = Self.editSeed(live: editSeed?(), snapshot: node.text)
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
        let style = NodeStyle.of(depth: depth, palette: palette, branchColor: branchColor)
        return RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(style.fill)
            .overlay {
                if isDropTarget {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(palette.secondarySurface.opacity(0.2))
                }
            }
            .overlay {
                if let stroke = style.stroke {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(stroke, lineWidth: style.strokeWidth)
                }
            }
    }

    @ViewBuilder
    private func content(depth: Int) -> some View {
        if isEditing {
            ZStack(alignment: .center) {
                if editText.isEmpty {
                    Text("輸入文字…")
                        .font(Font(LayoutEngine.font(for: depth)))
                        .foregroundStyle(palette.textSecondary.opacity(0.6))
                        .allowsHitTesting(false)
                }
                TextField("", text: $editText)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .font(Font(LayoutEngine.font(for: depth)))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 10)
                .focused($editFocused)
                .onSubmit {
                    submitted = true
                    (onSubmitEdit ?? onCommitEdit)(editText)
                }
                .onExitCommand {
                    escDiscard = true
                    onCancelEdit(editText)
                }
            }
        } else {
            let style = NodeStyle.of(depth: depth, palette: palette, branchColor: branchColor)
            Text(node.text.isEmpty ? " " : node.text)
                .font(Font(style.font))
                .foregroundStyle(style.textColor)
                .lineLimit(style.lineLimit)
                .multilineTextAlignment(.center)
                // Must match NodeStyle.size's insets or the drawn text wraps
                // differently from the measured text and clips.
                .padding(.horizontal, style.horizontalInset)
        }
    }

    @ViewBuilder
    private func selectionRing(radius: CGFloat) -> some View {
        let stateRadius = radius + InteractionSignalGeometry.local(
            screenPoints: 3, scale: interactionScale)
        if isSearchHit && !isSelected && !isDropTarget {
            RoundedRectangle(cornerRadius: stateRadius, style: .continuous)
                .stroke(palette.statusHighlight,
                        lineWidth: InteractionSignalGeometry.local(screenPoints: 2, scale: interactionScale))
                .padding(-InteractionSignalGeometry.local(screenPoints: 4, scale: interactionScale))
        }
        if isBatchMember {
            RoundedRectangle(cornerRadius: stateRadius, style: .continuous)
                .stroke(palette.accent, style: StrokeStyle(
                    lineWidth: InteractionSignalGeometry.local(screenPoints: 2, scale: interactionScale),
                    dash: [InteractionSignalGeometry.local(screenPoints: 5, scale: interactionScale),
                           InteractionSignalGeometry.local(screenPoints: 3, scale: interactionScale)]))
                .padding(-InteractionSignalGeometry.local(screenPoints: 4, scale: interactionScale))
        }
        if isDropTarget {
            RoundedRectangle(cornerRadius: stateRadius, style: .continuous)
                .stroke(palette.accent,
                        lineWidth: InteractionSignalGeometry.local(screenPoints: 2.5, scale: interactionScale))
                .padding(-InteractionSignalGeometry.local(screenPoints: 3, scale: interactionScale))
        } else if isSelected || isHovered {
            RoundedRectangle(cornerRadius: stateRadius, style: .continuous)
                .stroke(isSelected ? palette.accent : palette.textSecondary.opacity(0.45),
                        lineWidth: InteractionSignalGeometry.local(
                            screenPoints: isSelected ? 2 : 1.5, scale: interactionScale))
                .padding(-InteractionSignalGeometry.local(
                    screenPoints: isSelected ? 2 : 4, scale: interactionScale))
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
                .foregroundStyle(palette.textSecondary)
                .offset(x: -9, y: -9)
        }
    }

    @ViewBuilder
    private var markedBadge: some View {
        if node.marked && !isEditing {
            let footprint = MarkedBadgeGeometry.screenLocalFootprint(for: layout.frame)
            ZStack(alignment: .topLeading) {
                Image(systemName: "star.fill")
                    .font(.system(size: MarkedBadgeGeometry.screenFontSize))
                    .foregroundStyle(palette.statusHighlight)
                    .frame(width: footprint.width, height: footprint.height)
                    .offset(x: footprint.minX, y: footprint.minY)
            }
            .frame(width: layout.frame.width, height: layout.frame.height,
                   alignment: .topLeading)
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
                .foregroundStyle(palette.accent)
                .offset(x: -6, y: -6)
        }
    }

    @ViewBuilder
    private var collapsedBadge: some View {
        if node.collapsed && !node.children.isEmpty {
            Text("+\(hiddenCount)")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(palette.creamText)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Capsule().fill(branchColor))
                .overlay(Capsule().stroke(palette.creamText.opacity(0.8), lineWidth: 1))
                .offset(x: 10)
                .onTapGesture { onToggleCollapse?() }
                .help("收合中（共 \(hiddenCount) 個主題）：\n" + node.hiddenTopicPreview().joined(separator: "\n"))
        }
    }
}
