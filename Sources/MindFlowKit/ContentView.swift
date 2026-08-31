import PDFKit
import SwiftUI

public struct ContentView: View {
    @EnvironmentObject private var vm: MindMapViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var searchFocused: Bool
    @FocusState private var outlineFocused: Bool
    @FocusState private var noteFocused: Bool

    /// Single exit path for the search/replace bar, shared by Esc and the close button.
    private func closeSearch() {
        searchFocused = false
        vm.showSearch = false
        vm.searchQuery = ""
        vm.searchResults = []
    }
    @State private var noteDraft = ""
    // Closed on launch. The notes editor is the first text control in the window, so
    // whenever it was present and nothing else claimed focus, AppKit handed the caret to
    // it and typing silently went into 備註 instead of the map. Notes are summoned with
    // ⇧⌘N, which is what Xmind binds editor.showNotesEditor to.
    @State private var outlineEditingID: UUID?
    @State private var outlineDraft = ""
    @State private var autosaveTask: Task<Void, Never>?
    @State private var replaceText = ""
    @State private var draggingTab: Int?
    @State private var tabDragX: CGFloat = 0

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            if !vm.zenMode {
                tabBar
            }
            HStack(spacing: 0) {
                MapCanvasView()
                if vm.showInspector && !vm.zenMode {
                    inspector
                        .frame(width: 280)
                }
            }
        }
        .toolbar(vm.zenMode ? .hidden : .visible, for: .windowToolbar)
        .overlay(alignment: .topTrailing) {
            if vm.zenMode {
                Button {
                    vm.toggleZen()
                } label: {
                    Label("離開專注", systemImage: "arrow.uturn.backward.circle.fill")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.bordered)
                .padding(12)
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    vm.addChild(to: vm.selection ?? vm.document.root.id)
                } label: {
                    Label("子主題", systemImage: "plus.circle.fill")
                }
                .help("加入子主題（Tab）")

                Button {
                    if let selection = vm.selection, selection != vm.document.root.id {
                        vm.addSibling(of: selection)
                    } else {
                        vm.addChild(to: vm.document.root.id)
                    }
                } label: {
                    Label("兄弟主題", systemImage: "plus.square.on.square")
                }
                .help("加入兄弟主題（編輯中按 Return）")

                Button {
                    if let selection = vm.selection { vm.delete(id: selection) }
                } label: {
                    Label("刪除", systemImage: "trash")
                }
                .help("刪除選取主題（Delete）")

                Spacer()

                Button { vm.expandAll() } label: { Label("全部展開", systemImage: "rectangle.expand.vertical") }
                Button { vm.collapseAll() } label: { Label("全部收合", systemImage: "rectangle.compress.vertical") }
                Menu {
                    ForEach([1, 2, 3, 4], id: \.self) { level in
                        Button("顯示到第 \(level) 層") { vm.expandToLevel(level) }
                    }
                } label: {
                    Label("展開至", systemImage: "lineweight.thin")
                }
                Button { NotificationCenter.default.post(name: .mindFlowFit, object: nil) } label: {
                    Label("符合視窗", systemImage: "arrow.down.right.and.arrow.up.left")
                }
                .help("縮放至整張圖")

                if vm.focusBranchID != nil {
                    Button {
                        vm.focusBranchID = nil
                    } label: {
                        Label("取消聚焦", systemImage: "scope")
                    }
                    .help("回到全圖檢視")
                }

                Menu {
                    Button("邏輯圖（右展）") { vm.setDirection(.logicRight) }
                    Button("平衡圖（左右）") { vm.setDirection(.balanced) }
                    Button("魚骨圖") { vm.setDirection(.fishbone) }
                    Button("括號圖") { vm.setDirection(.bracket) }
                    Divider()
                    Button("整理") { vm.resetAllOffsets() }
                        .disabled(vm.document.offsets.isEmpty)
                        .help("清除手動位置並回到自動排版（可復原）")
                } label: {
                    Label("版面", systemImage: "arrow.triangle.branch")
                }

                Menu {
                    ForEach(Theme.all) { theme in
                        Button(theme.name) { vm.setTheme(theme.id) }
                    }
                } label: {
                    Label("主題", systemImage: "paintpalette")
                }

                Button {
                    vm.copyAsMarkdown()
                } label: {
                    Label("複製 MD", systemImage: "doc.on.doc")
                }
                .help("把整張圖複製成 Markdown 到剪貼簿（⌘⇧C）")

                Toggle(isOn: $vm.showInspector) {
                    Label("檢閱器", systemImage: "sidebar.trailing")
                }
                .toggleStyle(.button)
            }
        }
        .navigationTitle(vm.document.root.text.isEmpty ? vm.document.title : vm.document.root.text)
        .navigationSubtitle(saveSubtitle)
        .overlay(alignment: .bottom) { breadcrumbBar }
        .onReceive(NotificationCenter.default.publisher(for: .mindFlowShowNotes)) { _ in
            guard vm.selection != nil else { return }
            vm.inspectorTab = 0
            vm.showInspector = true
            // The editor does not exist yet on this pass, so the focus request has to wait
            // for it to be installed.
            DispatchQueue.main.async { noteFocused = true }
        }
        .overlay(alignment: .topLeading) {
            if let fid = vm.focusBranchID, let fnode = vm.document.root.find(fid) {
                HStack(spacing: 6) {
                    Image(systemName: "scope")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("聚焦：\(fnode.text)")
                        .font(.callout)
                        .lineLimit(1)
                    Button {
                        vm.focusBranchID = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("取消聚焦")
                }
                .padding(8)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(12)
            }
        }
        .overlay(alignment: .top) {
            // This overlay had no condition, so the search/replace bar was rendered
            // permanently. showSearch was toggled by Cmd+F, Esc and the close button but
            // nothing read it, which is why the X button appeared dead and why the bar
            // "reappeared" on every interaction — it had never left.
            if vm.showSearch {
                searchOverlay
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: vm.showSearch)
        .sheet(isPresented: $vm.showHelp) { helpSheet }
        .onOpenURL { url in vm.openFromURL(url) }
        .sheet(isPresented: $vm.showTemplatePicker) { templatePicker }
        .onChange(of: vm.showSearch) { showing in
            if showing { searchFocused = true }
        }
        .onChange(of: vm.document) { _ in scheduleAutosave() }
        .onChange(of: vm.sessions) { _ in scheduleAutosave() }
        .onChange(of: vm.exportRequest) { request in
            guard let request else { return }
            performExport(request)
            vm.exportRequest = nil
        }
        .onChange(of: vm.printRequest) { request in
            guard request else { return }
            printMap()
            vm.printRequest = false
        }
        .onChange(of: vm.selection) { sel in
            noteDraft = sel.flatMap { vm.document.root.find($0)?.note } ?? ""
        }
        .onChange(of: vm.editingID) { editing in
            // When a node editor goes away AppKit hands first responder to the next
            // text control in the window, which is the notes editor in the inspector —
            // so finishing a node silently dropped the caret into 備註. Release first
            // responder instead. Deferred by one runloop turn because rapid entry
            // (Return/Tab) sets editingID to the next node immediately.
            guard editing == nil else { return }
            DispatchQueue.main.async {
                guard vm.editingID == nil, !vm.showSearch else { return }
                if NSApp.keyWindow?.firstResponder is NSTextView {
                    NSApp.keyWindow?.makeFirstResponder(nil)
                }
            }
        }
        .onAppear {
            if vm.selection == nil { vm.selection = vm.document.root.id }
        }
    }

    private var breadcrumbBar: some View {
        Group {
            if let selID = vm.selection {
                // A horizontal ScrollView always claims the full proposed width, so hanging
                // the capsule background on it smeared a translucent bar across the whole
                // window instead of drawing a pill around the path. The row sizes to its
                // own content instead, and deep paths are bounded by showing the tail.
                let path = vm.breadcrumbPath(to: selID)
                let shown = path.suffix(6)
                HStack(spacing: 4) {
                    if path.count > shown.count {
                        Text("\u{2026}")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(shown, id: \.id) { node in
                        Button(node.text.isEmpty ? "\u{2026}" : node.text) {
                            vm.selection = node.id
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .lineLimit(1)
                        if node.id != vm.selection {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial, in: Capsule())
                .fixedSize()
                .padding(.bottom, 40)
            }
        }
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
            ForEach(vm.sessions.indices, id: \.self) { index in
                let isActive = index == vm.activeIndex
                HStack(spacing: 4) {
                    Button {
                        vm.switchTab(to: index)
                    } label: {
                        HStack(spacing: 5) {
                            Text(tabTitle(vm.sessions[index]))
                                .font(.callout)
                                .lineLimit(1)
                            if vm.sessions[index].dirty || (isActive && vm.dirty) {
                                Circle().fill(Color.orange).frame(width: 6, height: 6)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(
                        Capsule().fill(isActive ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08))
                    )
                    .opacity(draggingTab == index ? 0.55 : 1)
                    .offset(x: draggingTab == index ? tabDragX : 0)
                    .gesture(
                        DragGesture(minimumDistance: 8)
                            .onChanged { value in
                                draggingTab = index
                                tabDragX = value.translation.width
                            }
                            .onEnded { value in
                                let slots = max(vm.sessions.count, 1)
                                let moved = Int((value.translation.width / 130).rounded())
                                let destination = min(max(index + moved, 0), slots)
                                vm.moveTab(from: index, to: destination)
                                draggingTab = nil
                                tabDragX = 0
                            }
                    )
                    .help("切換到此分頁（拖曳可排序）")
                    .accessibilityLabel("切換到分頁：\(tabTitle(vm.sessions[index]))")
                    .contextMenu {
                        Button("建立分頁副本") { vm.duplicateActiveTab() }
                        Divider()
                        Button("關閉此分頁") { vm.closeTab(index) }
                        Button("關閉其他分頁") { vm.closeOtherTabs(keeping: index) }
                        if index < vm.sessions.count - 1 {
                            Button("關閉右側分頁") { vm.closeTabsToRight(index) }
                        }
                    }
                    if vm.sessions.count > 1 {
                        Button {
                            vm.closeTab(index)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.secondary)
                                .padding(3)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help("關閉此分頁")
                        .accessibilityLabel("關閉分頁：\(tabTitle(vm.sessions[index]))")
                    }
                }
            }
            Button {
                vm.showTemplatePicker = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(5)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("新增分頁（⌘N）")
            Spacer(minLength: 0)
        }
        }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func tabTitle(_ session: EditorSession) -> String {
        let text = session.document.root.text.trimmingCharacters(in: .whitespaces)
        if !text.isEmpty { return text }
        if let path = session.filePath { return path.deletingPathExtension().lastPathComponent }
        return session.document.title
    }

    // MARK: - Inspector（備註 / 大綱）

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("模式", selection: $vm.inspectorTab) {
                Text("備註").tag(0)
                Text("大綱").tag(1)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if vm.inspectorTab == 0 {
                noteInspector
            } else {
                outlineView
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    /// Thumbnail + removal for the selected node's attached picture.
    @ViewBuilder
    private func nodeImageSection(id: UUID) -> some View {
        if let dataURL = vm.document.root.find(id)?.image, !dataURL.isEmpty {
            HStack(spacing: 8) {
                if let nsImage = ImageStore.shared.image(forDataURL: dataURL) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 72, maxHeight: 54)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .help("附加圖片預覽")
                }
                Button("移除圖片") { vm.setNodeImage(id: id, to: nil) }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
        }
    }

    /// Web-link field + open button for the selected node.
    private func nodeLinkSection(id: UUID) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "link").font(.caption).foregroundStyle(.secondary)
            TextField("網址（可選）", text: Binding(
                get: { vm.document.root.find(id)?.url ?? "" },
                set: { vm.setNodeURL(id: id, to: $0) }))
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .accessibilityLabel("節點網址輸入框")
            if let url = vm.document.root.find(id)?.url, !url.isEmpty {
                Button { vm.openURL(id: id) } label: { Image(systemName: "arrow.up.forward.app") }
                    .buttonStyle(.borderless)
                    .help("在預設瀏覽器開啟")
            }
        }
    }

    /// Six-color tag picker for the selected node.
    private func nodeColorTagSection(id: UUID) -> some View {
        HStack(spacing: 6) {
            Text("色標").font(.caption).foregroundStyle(.secondary)
            ForEach(Theme.colorTags, id: \.key) { tag in
                Circle()
                    .fill(tag.color)
                    .frame(width: 16, height: 16)
                    .overlay(Circle().stroke(
                        vm.document.root.find(id)?.colorTag == tag.key ? Color.primary : Color.clear,
                        lineWidth: 2))
                    .onTapGesture { vm.setColorTag(id: id, tag: tag.key) }
                    .help(tag.name)
                    .accessibilityLabel("色標 \(tag.name)")
            }
            Button("清除") { vm.setColorTag(id: id, tag: nil) }
                .buttonStyle(.borderless)
                .font(.caption)
        }
    }
    @ViewBuilder
    private var noteInspector: some View {
        if let sumID = vm.selectedSummaryID,
           vm.document.summaries.contains(where: { $0.id == sumID }) {
            Text("概要括線").font(.subheadline).foregroundStyle(.secondary)
            TextField("概要文字…", text: Binding(
                get: { vm.document.summaries.first(where: { $0.id == sumID })?.text ?? "" },
                set: { vm.setSummaryText(id: sumID, to: $0) }))
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .accessibilityLabel("概要文字輸入框")
            HStack(spacing: 8) {
                Button("◀ 縮小範圍") { vm.shrinkSummary(id: sumID) }
                    .buttonStyle(.borderless)
                    .font(.caption)
                Button("延伸範圍 ▶") { vm.extendSummary(id: sumID) }
                    .buttonStyle(.borderless)
                    .font(.caption)
                Spacer()
                Button("刪除這條概要") { vm.removeSummary(id: sumID) }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } else if let linkID = vm.selectedLinkID,
                  vm.document.links.contains(where: { $0.id == linkID }) {
            Text("關聯線").font(.subheadline).foregroundStyle(.secondary)
            TextField("關聯線標籤…", text: Binding(
                get: { vm.document.links.first(where: { $0.id == linkID })?.label ?? "" },
                set: { vm.setLinkLabel(id: linkID, to: $0) }))
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .accessibilityLabel("關聯線標籤輸入框")
            Button("刪除這條關聯線") { vm.removeLink(id: linkID) }
                .buttonStyle(.borderless)
                .font(.caption)
        } else if let id = vm.selection, let node = vm.document.root.find(id) {
            Text(node.id == vm.document.root.id ? "中心主題" : "主題")
                .font(.subheadline).foregroundStyle(.secondary)
            TextEditor(text: $noteDraft)
                .focused($noteFocused)
                .autocorrectionDisabled()
                .accessibilityLabel("備註內容")
                .onChange(of: noteDraft) { draft in
                    guard draft != (vm.document.root.find(id)?.note ?? "") else { return }
                    vm.setNote(id: id, to: draft)
                }
                .font(.body)
                .frame(maxHeight: .infinity)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
                .overlay(alignment: .topLeading) {
                    if noteDraft.isEmpty {
                        Text("備註…").foregroundStyle(.secondary).padding(6).allowsHitTesting(false)
                    }
                }
            Divider()
            nodeImageSection(id: id)
            Divider()
            nodeLinkSection(id: id)
            nodeColorTagSection(id: id)
            let s = vm.document.stats()
            Text("\(s.nodeCount) 個主題 · 最深 \(s.maxDepth) 層 · ★ \(s.markedCount) · 備註 \(s.noteCount) · 連結 \(s.linkCount)")
                .font(.caption).foregroundStyle(.secondary)
        } else {
            Text("尚未選取主題")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private var outlineRows: [OutlineRow] {
        OutlineFlattener.flatten(vm.document.root)
    }

    private var outlineView: some View {
        ScrollViewReader { proxy in
            let focusSet = vm.focusSet()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Button {
                            vm.addChild(to: vm.selection ?? vm.document.root.id)
                        } label: {
                            Label("子主題", systemImage: "plus.circle")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                        Button {
                            if let sel = vm.selection, sel != vm.document.root.id {
                                vm.addSibling(of: sel)
                            } else {
                                vm.addChild(to: vm.document.root.id)
                            }
                        } label: {
                            Label("兄弟", systemImage: "plus.square.on.square")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.bottom, 4)
                    if vm.focusBranchID != nil {
                        Text("聚焦模式中——非此分支的主題已淡化")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.bottom, 4)
                    }
                    ForEach(outlineRows) { row in
                        outlineRowView(row, focusSet: focusSet)
                            .id(row.id)
                    }
                }
                .padding(8)
            }
            .onChange(of: vm.selection) { sel in
                if let sel { proxy.scrollTo(sel) }
            }
            .onChange(of: outlineEditingID) { id in
                if let id { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }

    private func outlineDimmed(_ row: OutlineRow, focusSet: Set<UUID>) -> Double {
        guard !focusSet.isEmpty else { return 1 }
        return focusSet.contains(row.id) ? 1 : 0.3
    }



    /// Right-click actions for outline rows — keeps the outline a full editor,
    /// not just a viewer (parity with the map canvas context menu).
    @ViewBuilder
    private func outlineRowMenu(_ row: OutlineRow) -> some View {
        Button("加入子主題") { vm.addChild(to: row.id) }
        if !row.isRoot {
            Button("加入兄弟主題") { vm.addSibling(of: row.id) }
        }
        Button("複製整棵子樹") { vm.duplicate(id: row.id) }
        Button(row.marked ? "移除星星" : "加上星星") { vm.toggleMark(id: row.id) }
        Menu("色標") {
            ForEach(Theme.colorTags, id: \.key) { tag in
                Button(tag.name) { vm.setColorTag(id: row.id, tag: tag.key) }
            }
            Divider()
            Button("清除色標") { vm.setColorTag(id: row.id, tag: nil) }
        }
        Menu("子樹批次") {
            Menu("全部加上色標") {
                ForEach(Theme.colorTags, id: \.key) { tag in
                    Button(tag.name) { vm.setSubtreeColorTag(id: row.id, tag: tag.key) }
                }
                Divider()
                Button("清除色標") { vm.setSubtreeColorTag(id: row.id, tag: nil) }
            }
            Button("整棵子樹加星星") { vm.setSubtreeMark(id: row.id, to: true) }
            Button("移除整棵子樹的星星") { vm.setSubtreeMark(id: row.id, to: false) }
        }
        if !row.isRoot {
            Button("加入概要括線（含下一個兄弟）") { _ = vm.addSummaryWithNextSibling(of: row.id) }
        }
        Button("複製此分支 Markdown") { vm.copyBranchAsMarkdown(id: row.id) }
        Divider()
        if row.hasChildren {
            Button(row.collapsed ? "展開" : "收合") { vm.toggleCollapse(id: row.id) }
        }
        if !row.isRoot {
            Button("刪除", role: .destructive) { vm.delete(id: row.id) }
        }
    }
    private func outlineRowView(_ row: OutlineRow, focusSet: Set<UUID>) -> some View {
        HStack(spacing: 5) {
            if row.marked {
                Image(systemName: "star.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Color(hex: 0xF5C542))
            }
            if !row.note.isEmpty {
                Image(systemName: "note.text")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            }
            if row.hasImage {
                Image(systemName: "photo.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
                    .help("此主題附有圖片")
            }
            if let key = row.colorTag, let c = Theme.colorTag(named: key) {
                Circle().fill(c).frame(width: 7, height: 7)
            }
            if row.hasChildren && outlineEditingID != row.id {
                Button {
                    vm.toggleCollapse(id: row.id)
                } label: {
                    Image(systemName: row.collapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 14)
                }
                .buttonStyle(.plain)
                .help(row.collapsed ? "展開子主題" : "收合子主題")
            } else if !row.hasChildren {
                Color.clear.frame(width: 14)
            }
            if outlineEditingID == row.id {
                TextField("主題", text: $outlineDraft)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .font(.body)
                    .focused($outlineFocused)
                    .onAppear { outlineFocused = true }
                    .onSubmit {
                        vm.rename(id: row.id, to: outlineDraft)
                        outlineEditingID = nil
                        // XMind-style rapid entry: Return spawns the next sibling.
                        if let next = vm.insertSiblingAfter(id: row.id) {
                            outlineEditingID = next
                            outlineDraft = ""
                        }
                    }
                    .onExitCommand { outlineEditingID = nil }
            } else {
                if vm.showOutlineNumbers, let n = row.number {
                    Text(n)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 24, alignment: .trailing)
                        .help("大綱編號 \(n)")
                }
                Text(row.text.isEmpty ? "（空白）" : row.text)
                    .font(row.isRoot ? .body.bold() : .body)
                    .foregroundStyle(row.text.isEmpty ? Color.secondary : Color.primary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, CGFloat(row.depth) * 10 + 2)
        .padding(.trailing, 6)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .opacity(outlineDimmed(row, focusSet: focusSet))
        .background(
            vm.selection == row.id
                ? Color.accentColor.opacity(0.16)
                : Color.clear
        )
        .cornerRadius(5)
        .contextMenu { outlineRowMenu(row) }
        .onTapGesture {
            guard outlineEditingID != row.id else { return }
            vm.stopEditing()
            if vm.selection == row.id {
                // Second click on the selected row starts renaming — no double-click.
                outlineDraft = row.text
                outlineEditingID = row.id
            } else {
                vm.selection = row.id
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(row.text)
        .accessibilityAddTraits(vm.selection == row.id ? [.isSelected] : [])
        .contextMenu {
            Button("加入子主題") { vm.addChild(to: row.id) }
            Button("重新命名") {
                outlineDraft = row.text
                outlineEditingID = row.id
            }
            Divider()
            Button("刪除", role: .destructive) { vm.delete(id: row.id) }
        }
    }

    // MARK: - Autosave

    private func printMap() {
        let renderer = ImageRenderer(content: StaticMapView(document: vm.document))
        renderer.scale = 2
        guard let image = renderer.nsImage else { return }
        let imageView = NSImageView(frame: NSRect(origin: .zero, size: image.size))
        imageView.image = image
        let operation = NSPrintOperation(view: imageView)
        operation.showsPrintPanel = true
        operation.run()
        vm.notify("已送出列印 ✓")
    }

    /// Title-bar status: version, save state, and when auto-save last ran.
    private var saveSubtitle: String {
        if vm.dirty {
            return "v\(AppInfo.version) · 未儲存"
        }
        if let saved = vm.lastSavedAt {
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            return "v\(AppInfo.version) · 已自動保存 \(f.string(from: saved))"
        }
        return "v\(AppInfo.version) · \(vm.filePath?.lastPathComponent ?? "自動儲存中")"
    }

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            vm.autosaveAllSessions()
        }
    }

    // MARK: - Export

    private var exportBaseName: String {
        let name = vm.document.root.text.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "心智圖" : name
    }

    private func performExport(_ format: MindMapViewModel.ExportFormat) {
        switch format {
        case .markdown:
            if FileIO.saveText(MapExporter.markdown(vm.document), suggestedName: exportBaseName + ".md") != nil {
                vm.notify("已匯出 Markdown ✓")
            }
        case .opml:
            if FileIO.saveText(MapExporter.opml(vm.document), suggestedName: exportBaseName + ".opml") != nil {
                vm.notify("已匯出 OPML ✓")
            }
        case .png:
            let renderer = ImageRenderer(content: StaticMapView(document: vm.document))
            renderer.scale = 2
            guard let image = renderer.nsImage,
                  let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { return }
            if FileIO.saveData(png, suggestedName: exportBaseName + ".png") != nil {
                vm.notify("已匯出 PNG ✓")
            }
        case .pngBranch:
            guard let selID = vm.selection,
                  let node = vm.document.root.find(selID) else { return }
            let branchDoc = MindDocument(title: node.text, root: node)
            let renderer = ImageRenderer(content: StaticMapView(document: branchDoc))
            renderer.scale = 2
            guard let image = renderer.nsImage,
                  let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { return }
            if FileIO.saveData(png, suggestedName: node.text + ".png") != nil {
                vm.notify("已匯出分支 PNG ✓")
            }
        case .pngTransparent:
            let renderer = ImageRenderer(content: StaticMapView(document: vm.document, transparentBackground: true))
            renderer.scale = 2
            guard let image = renderer.nsImage,
                  let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { return }
            if FileIO.saveData(png, suggestedName: exportBaseName + "-transparent.png") != nil {
                vm.notify("已匯出透明背景 PNG ✓")
            }
        case .pngLarge:
            let renderer = ImageRenderer(content: StaticMapView(document: vm.document))
            renderer.scale = 3
            guard let image = renderer.nsImage,
                  let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { return }
            if FileIO.saveData(png, suggestedName: exportBaseName + "-3x.png") != nil {
                vm.notify("已匯出大圖 PNG ✓")
            }
        case .pdf:
            let renderer = ImageRenderer(content: StaticMapView(document: vm.document))
            renderer.scale = 2
            guard let image = renderer.nsImage,
                  let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let cgImage = rep.cgImage else { return }
            let pageRect = CGRect(x: 0, y: 0, width: CGFloat(cgImage.width), height: CGFloat(cgImage.height))
            let mutableData = NSMutableData()
            guard let consumer = CGDataConsumer(data: mutableData as CFMutableData) else { return }
            var mediaBox = pageRect
            guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return }
            context.beginPDFPage(nil)
            context.draw(cgImage, in: pageRect)
            context.endPDFPage()
            context.closePDF()
            if FileIO.saveData(mutableData as Data, suggestedName: exportBaseName + ".pdf") != nil {
                vm.notify("已匯出 PDF ✓")
            }
        case .svg:
            if FileIO.saveText(MapExporter.svg(vm.document), suggestedName: exportBaseName + ".svg") != nil {
                vm.notify("已匯出 SVG ✓")
            }
        case .freemind:
            if FileIO.saveText(MapExporter.freemind(vm.document), suggestedName: exportBaseName + ".mm") != nil {
                vm.notify("已匯出 FreeMind ✓")
            }
        case .svgBranch:
            guard let selID = vm.selection,
                  let node = vm.document.root.find(selID) else { return }
            let branchDoc = MindDocument(title: node.text, root: node)
            if FileIO.saveText(MapExporter.svg(branchDoc), suggestedName: node.text + ".svg") != nil {
                vm.notify("已匯出分支 SVG ✓")
            }
        }
    }

    // MARK: - Search overlay

    private var searchOverlay: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("搜尋主題…", text: $vm.searchQuery)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .frame(width: 220)
                .focused($searchFocused)
                .onSubmit { vm.jumpToNextResult() }
                // Esc could not close this bar. KeyboardMonitor passes every key through
                // while a text field is first responder, so the canvas Esc handler never
                // ran, and the X button was the only exit.
                .onExitCommand { closeSearch() }
            Text(vm.searchResults.isEmpty ? "0" : "\(vm.searchIndex + 1)/\(vm.searchResults.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 34)
            Button { vm.jumpToNextResult() } label: { Image(systemName: "chevron.down") }
                .buttonStyle(.borderless)
                .accessibilityLabel("跳到下一個搜尋結果")
            // A Divider inside an HStack has unbounded maxHeight, so it stretched this
            // bar to the full proposed height of the window. The .ultraThinMaterial
            // background then covered the entire canvas, which looked like the map had
            // failed to render. Pin it to the row height.
            Divider().frame(height: 22)
            TextField("取代為…", text: $replaceText)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .frame(width: 120)
            Button("全部取代") { vm.replaceAll(vm.searchQuery, with: replaceText) }
                .buttonStyle(.bordered)
                .disabled(replaceText.isEmpty)
            Button { closeSearch() } label: { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
                .accessibilityLabel("關閉搜尋")
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.top, 8)
        .onChange(of: vm.searchQuery) { _ in vm.performSearch() }
    }

    // MARK: - Sheets

    private var templatePicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("選一個範本").font(.title2).bold()
            ForEach(MindTemplates.all, id: \.name) { template in
                Button {
                    vm.applyTemplate(template.name)
                    vm.showTemplatePicker = false
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(template.name).font(.headline)
                        Text(template.subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            HStack {
                Spacer()
                Button("取消") { vm.showTemplatePicker = false }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 340)
    }

    private var helpSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("鍵盤快速鍵").font(.title2).bold()
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                ForEach([
                    ("Tab", "加入子主題"),
                    ("Return / ⇧Return", "新增兄弟主題（後／前）"),
                    ("⌘Return", "插入父主題"),
                    ("直接打字", "取代選中主題的文字並進入編輯"),
                    ("Delete", "刪除選取主題"),
                    ("點選後再點一次", "編輯文字"),
                    ("方向鍵 ↑↓", "在兄弟之間移動"),
                    ("← →", "跳到上層 / 下層"),
                    ("空白鍵", "編輯選中主題"),
                    ("⌘/ / ⌘⌥/", "收合分支 / 全部收合或展開"),
                    ("⌥↑↓ / ⌥⌘↑↓", "兄弟移一格 / 移到頭尾"),
                    ("拖曳節點", "放到節點上重掛；對準插入線排序；空白處移動"),
                    ("⌘F / ⌘G", "搜尋 / 下一個結果"),
                    ("⌘D", "複製整棵子樹"),
                    ("⌘L", "切換星星標記"),
                    ("⌘+ / ⌘- / ⌘0", "縮放"),
                    ("⌘方向鍵", "微調節點位置"),
                    ("⌘⇧T", "重新開啟關閉的分頁"),
                    ("⌃Tab", "切換分頁"),
                    ("⌘S", "另存新檔（平常自動保存）"),
                    ("⌘⇧C", "複製為 Markdown 到剪貼簿"),
                    ("⌘⌥D", "建立目前分頁副本"),
                    ("⌘⇧V", "貼上剪貼簿條列建節點"),
                    ("⌘⌥F / ⌘⌥P", "專注模式 / 簡報模式"),
                    ("⇧⌘M / ⌘R", "切換圖與大綱 / 回中心主題"),
                    ("⌘⌥1-4 / ⌘⌥L", "切換版面（指定／循環）"),
                    ("⌘P", "列印"),
                    ("⌘,", "偏好設定")
                ], id: \.0) { pair in
                    GridRow {
                        Text(pair.0).font(.body.bold()).frame(width: 110, alignment: .trailing)
                        Text(pair.1).font(.body)
                    }
                }
            }
            Text("小技巧：所有變更都會自動保存；每個分頁都是獨立的一份圖。分支聚焦可從顯示選單使用。")
                .font(.callout).foregroundStyle(.secondary)
            Text("更多功能：顯示選單的「簡報模式」可逐層揭開地圖上台報告；點關聯線中間的圓點可在檢閱器加標籤；檔案選單支援 Markdown、OPML、FreeMind、PNG、PDF、SVG 進出。")
                .font(.callout).foregroundStyle(.secondary)
            Text("小絕招：把網頁或筆記裡選取的文字直接拖進畫布，放開在哪個主題上就長成它的子樹；截圖後直接拖到主題上也能附圖（檢閱器可移除）。")
                .font(.callout).foregroundStyle(.secondary)
            Text("批次操作：按住 Shift 點選多個主題（或在空白處 Shift＋拖曳畫框圈選），再從右鍵選單一次上色／標星／刪除。Esc 清空批次。")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("好，開始用！") { vm.showHelp = false }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420)
        .overlay(alignment: .bottomTrailing) {
            Text("v\(AppInfo.version)")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .padding(6)
        }
    }
}
