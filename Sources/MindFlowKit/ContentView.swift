import PDFKit
import SwiftUI

public struct ContentView: View {
    @EnvironmentObject private var vm: MindMapViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var searchFocused: Bool
    @State private var noteDraft = ""
    @State private var showInspector = true
    @State private var inspectorTab = 0
    @State private var outlineEditingID: UUID?
    @State private var outlineDraft = ""
    @State private var autosaveTask: Task<Void, Never>?
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
                if showInspector && !vm.zenMode {
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
                .help("加入兄弟主題（Return）")

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
                    Button("重設手動位置") { vm.resetAllOffsets() }
                        .disabled(vm.document.offsets.isEmpty)
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

                Toggle(isOn: $showInspector) {
                    Label("檢閱器", systemImage: "sidebar.trailing")
                }
                .toggleStyle(.button)
            }
        }
        .navigationTitle(vm.document.root.text.isEmpty ? vm.document.title : vm.document.root.text)
        .navigationSubtitle(vm.dirty ? "未儲存" : (vm.filePath?.lastPathComponent ?? "自動儲存中"))
        .overlay(alignment: .bottom) { breadcrumbBar }
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
                }
                .padding(8)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(12)
            }
        }
        .overlay(alignment: .top) {
            searchOverlay
                .transition(.move(edge: .top).combined(with: .opacity))
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: vm.showSearch)
        .sheet(isPresented: $vm.showHelp) { helpSheet }
        .onOpenURL { url in vm.openFromURL(url) }
        .sheet(isPresented: $vm.showTemplatePicker) { templatePicker }
        .onChange(of: vm.showSearch) { showing in
            if showing {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 120_000_000)
                    searchFocused = true
                }
            }
        }
        .onChange(of: vm.document) { _ in scheduleAutosave() }
        .onChange(of: vm.sessions) { _ in scheduleAutosave() }
        .onChange(of: vm.exportRequest) { request in
            guard let request else { return }
            performExport(request)
            vm.exportRequest = nil
        }
        .onChange(of: vm.zenMode) { _ in
            if vm.zenMode { showInspector = showInspector } // state preserved
        }
        .onChange(of: vm.printRequest) { request in
            guard request else { return }
            printMap()
            vm.printRequest = false
        }
        .onChange(of: vm.selection) { sel in
            noteDraft = sel.flatMap { vm.document.root.find($0)?.note } ?? ""
        }
        .onAppear {
            if vm.selection == nil { vm.selection = vm.document.root.id }
        }
    }

    private var breadcrumbBar: some View {
        Group {
            if let selID = vm.selection {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(vm.breadcrumbPath(to: selID), id: \.id) { node in
                            Button(node.text.isEmpty ? "\u{2026}" : node.text) {
                                vm.selection = node.id
                            }
                            .buttonStyle(.borderless)
                            .font(.caption)
                            if node.id != vm.selection {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial, in: Capsule())
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
                    .onTapGesture(count: 2) {
                        vm.switchTab(to: index)
                        vm.selection = vm.sessions[index].document.root.id
                        vm.editingID = vm.sessions[index].document.root.id
                    }
                    .help("切換到此分頁（拖曳可排序；雙擊改標題）")
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
            Picker("模式", selection: $inspectorTab) {
                Text("備註").tag(0)
                Text("大綱").tag(1)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if inspectorTab == 0 {
                noteInspector
            } else {
                outlineView
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private var noteInspector: some View {
        if let id = vm.selection, let node = vm.document.root.find(id) {
            Text(node.id == vm.document.root.id ? "中心主題" : "主題")
                .font(.subheadline).foregroundStyle(.secondary)
            TextEditor(text: $noteDraft)
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
            let s = vm.document.stats()
            Text("\(s.nodeCount) 個主題 · 最深 \(s.maxDepth) 層 · ★ \(s.markedCount) · 備註 \(s.noteCount)")
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
                    .font(.body)
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
        .onTapGesture(count: 2) {
            vm.selection = row.id
            outlineDraft = row.text
            outlineEditingID = row.id
        }
        .onTapGesture {
            guard outlineEditingID != row.id else { return }
            vm.stopEditing()
            vm.selection = row.id
        }
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
        }
    }

    // MARK: - Search overlay

    private var searchOverlay: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("搜尋主題…", text: $vm.searchQuery)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
                .focused($searchFocused)
                .onSubmit { vm.jumpToNextResult() }
            Text(vm.searchResults.isEmpty ? "0" : "\(vm.searchIndex + 1)/\(vm.searchResults.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 34)
            Button { vm.jumpToNextResult() } label: { Image(systemName: "chevron.down") }
                .buttonStyle(.borderless)
            Button { vm.showSearch = false } label: { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
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
                    ("Return", "加入兄弟主題"),
                    ("Delete", "刪除選取主題"),
                    ("雙擊", "編輯文字"),
                    ("方向鍵 ↑↓", "在兄弟之間移動"),
                    ("← →", "跳到上層 / 下層"),
                    ("空白鍵", "收合 / 展開"),
                    ("⌥⌘↑↓", "調整排序"),
                    ("拖曳節點", "重新掛接或排序"),
                    ("⌘F / ⌘G", "搜尋 / 下一個結果"),
                    ("⌘D", "複製整棵子樹"),
                    ("⌘L", "切換星星標記"),
                    ("⌘+ / ⌘- / ⌘0", "縮放"),
                    ("⌘方向鍵", "微調節點位置"),
                    ("⌥拖曳", "自由放置節點"),
                    ("⌘⇧T", "重新開啟關閉的分頁"),
                    ("⌃Tab", "切換分頁"),
                    ("⌘S", "另存新檔（平常自動保存）"),
                ], id: \.0) { pair in
                    GridRow {
                        Text(pair.0).font(.body.bold()).frame(width: 110, alignment: .trailing)
                        Text(pair.1).font(.body)
                    }
                }
            }
            Text("小技巧：所有變更都會自動保存；每個分頁都是獨立的一份圖。")
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
            Text("v11.7")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .padding(6)
        }
    }
}
