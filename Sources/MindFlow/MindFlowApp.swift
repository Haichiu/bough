import SwiftUI
import MindFlowKit

/// Installed once per launch, no matter how often windows appear.
private var didInstallQuitAutosave = false

func installQuitAutosave(_ vm: MindMapViewModel) {
    guard !didInstallQuitAutosave else { return }
    didInstallQuitAutosave = true
    NotificationCenter.default.addObserver(
        forName: NSApplication.willTerminateNotification,
        object: nil, queue: .main
    ) { _ in
        MainActor.assumeIsolated {
            vm.autosaveAllSessions()
        }
    }
}

private struct SettingsView: View {
    @AppStorage("defaultTheme") private var defaultTheme = "ocean"
    @AppStorage("defaultDirection") private var defaultDirection = MapDirection.logicRight.rawValue

    var body: some View {
        Form {
            Picker("預設主題", selection: $defaultTheme) {
                ForEach(Theme.all) { theme in
                    Text(theme.name).tag(theme.id)
                }
            }
            Picker("預設版面", selection: $defaultDirection) {
                Text("邏輯圖（右展）").tag(MapDirection.logicRight.rawValue)
                Text("平衡圖（左右）").tag(MapDirection.balanced.rawValue)
                Text("魚骨圖").tag(MapDirection.fishbone.rawValue)
                Text("括號圖").tag(MapDirection.bracket.rawValue)
            }
            Text("設定會套用之後新建的文件。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 380)
    }
}

@main
struct MindFlowApp: App {
    @StateObject private var vm = MindMapViewModel()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup("MindFlow", id: "main") {
            ContentView()
                .environmentObject(vm)
                .frame(minWidth: 960, minHeight: 620)
                .onAppear {
                    KeyboardMonitor.shared.start(vm: vm)
                    installQuitAutosave(vm)
                    vm.startSnapshotTimer()
                }
        }
        .commands {
            CommandGroup(after: .help) {
                Button("鍵盤快速鍵…") { vm.showHelp = true }
                    .keyboardShortcut("/", modifiers: [.command])
            }
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新增心智圖…") { vm.showTemplatePicker = true }
                    .keyboardShortcut("n")
                Button("新增視窗") { openWindow(id: "main") }
                    .keyboardShortcut("n", modifiers: [.command, .option])
                Button("開啟…") { vm.open() }
                    .keyboardShortcut("o")
                Button("匯入 Markdown…") { vm.importMarkdown() }
                    .keyboardShortcut("i", modifiers: [.command, .shift])
                Button("匯入 OPML…") { vm.importOPML() }
                Button("匯入 FreeMind…") { vm.importFreeMind() }
                Button("儲存…") { vm.save() }
                    .keyboardShortcut("s")
                Divider()
                Menu("匯出") {
                    Button("Markdown…") { vm.exportRequest = .markdown }
                    Button("OPML…") { vm.exportRequest = .opml }
                    Button("PNG 圖片…") { vm.exportRequest = .png }
                    Button("PNG 圖片（透明背景）…") { vm.exportRequest = .pngTransparent }
                    Button("PNG 大圖（3x）…") { vm.exportRequest = .pngLarge }
                    Divider()
                    Button("複製為 Markdown") { vm.copyAsMarkdown() }
                        .keyboardShortcut("c", modifiers: [.command, .shift])
                    Button("複製為 OPML") { vm.copyAsOPML() }
                    Button("PDF 文件…") { vm.exportRequest = .pdf }
                    Button("SVG 向量圖…") { vm.exportRequest = .svg }
                    Button("FreeMind (.mm)…") { vm.exportRequest = .freemind }
                    Divider()
                    Button("分支 PNG…") { vm.exportRequest = .pngBranch }
                    Button("分支 SVG…") { vm.exportRequest = .svgBranch }
                    Divider()
                    Button("貼上剪貼簿條列") { vm.pasteAsNodes() }
                        .keyboardShortcut("v", modifiers: [.command, .shift])
                }
            }
            CommandMenu("分頁") {
                Button("下一個分頁") { vm.cycleTab(1) }
                    .keyboardShortcut(.tab, modifiers: [.control])
                Button("上一個分頁") { vm.cycleTab(-1) }
                    .keyboardShortcut(.tab, modifiers: [.control, .shift])
                Divider()
                Button("建立目前分頁副本") { vm.duplicateActiveTab() }
                    .keyboardShortcut("d", modifiers: [.command, .option])
                Button("關閉分頁／視窗") {
                    vm.closeActiveTabOrWindow()
                }
                .keyboardShortcut("w", modifiers: [.command])
                Button("重新開啟上次關閉的分頁") { vm.reopenLastClosedTab() }
                    .keyboardShortcut("t", modifiers: [.command, .shift])
                Divider()
                Button("列印…") { vm.printRequest = true }
                    .keyboardShortcut("p", modifiers: [.command])
            }
            CommandMenu("顯示") {
                // Menu registration and the local monitor share one exact dispatcher.
                Button(vm.zenMode ? "離開專注模式" : "專注模式") {
                    KeyboardMonitor.performCoreShortcut(
                        characters: "f", modifiers: [.command, .option], vm: vm)
                }
                .keyboardShortcut("f", modifiers: [.command, .option])
                Button("切換圖／大綱") {
                    KeyboardMonitor.performCoreShortcut(
                        characters: "m", modifiers: [.shift, .command], vm: vm)
                }
                .keyboardShortcut("m", modifiers: [.shift, .command])
                Button("回中心主題") {
                    KeyboardMonitor.performCoreShortcut(
                        characters: "r", modifiers: [.command], vm: vm)
                }
                .keyboardShortcut("r", modifiers: [.command])
                Button("全部收合／展開") {
                    KeyboardMonitor.performCoreShortcut(
                        characters: "/", modifiers: [.option, .command], vm: vm)
                }
                .keyboardShortcut("/", modifiers: [.option, .command])
                Divider()
                Button(vm.showOutlineNumbers ? "隱藏大綱編號" : "大綱顯示編號") {
                    vm.showOutlineNumbers.toggle()
                }
                Button("聚焦所選分支") {
                    if let sel = vm.selection { vm.toggleFocus(on: sel) }
                }
                .disabled(vm.selection == nil || vm.zenMode)
                Button(vm.presentationActive ? "結束簡報" : "簡報模式（逐層揭開）") {
                    KeyboardMonitor.performCoreShortcut(
                        characters: "p", modifiers: [.command, .option], vm: vm)
                }
                .keyboardShortcut("p", modifiers: [.command, .option])
                .disabled(vm.zenMode)
            }
            CommandMenu("版面") {
                Button("循環切換版面") { vm.cycleDirection() }
                    .keyboardShortcut("l", modifiers: [.command, .option])
                Divider()
                Button("邏輯圖（右展）") { vm.setDirection(.logicRight) }
                    .keyboardShortcut("1", modifiers: [.command, .option])
                Button("平衡圖（左右）") { vm.setDirection(.balanced) }
                    .keyboardShortcut("2", modifiers: [.command, .option])
                Button("魚骨圖") { vm.setDirection(.fishbone) }
                    .keyboardShortcut("3", modifiers: [.command, .option])
                Button("括號圖") { vm.setDirection(.bracket) }
                    .keyboardShortcut("4", modifiers: [.command, .option])
            }
            CommandMenu("尋找") {
                Button("搜尋主題…") { vm.showSearch = true }
                    .keyboardShortcut("f", modifiers: [.command])
                Button("下一個結果") { vm.jumpToNextResult() }
                    .keyboardShortcut("g", modifiers: [.command])
            }
            CommandMenu("主題") {
                Button("複製主題與子樹") {
                    KeyboardMonitor.performCoreShortcut(
                        characters: "d", modifiers: [.command], vm: vm)
                }
                .keyboardShortcut("d", modifiers: [.command])
                Button("切換星號標記") {
                    if let selection = vm.selection { vm.toggleMark(id: selection) }
                }
                .keyboardShortcut("l", modifiers: [.command])
                Divider()
                Button("收合同類兄弟") {
                    if let selection = vm.selection { vm.collapseOtherSiblings(id: selection) }
                }
                .keyboardShortcut("c", modifiers: [.option, .command])
                Divider()
                // No bare-key menu shortcut. macOS matches menu key equivalents before the
                // first responder sees the key, so an unmodified Tab/Return/Delete/z here
                // fires the menu item even while a text field is being typed into.
                // KeyboardMonitor already owns these keys and knows about editing state.
                Button("加入子主題") { vm.addChild(to: vm.selection ?? vm.document.root.id) }
                Button("加入兄弟主題") {
                    if let selection = vm.selection, selection != vm.document.root.id {
                        vm.addSibling(of: selection)
                    }
                }
                Button("刪除主題") {
                    if let selection = vm.selection { vm.delete(id: selection) }
                }
                Divider()
                Button("復原") { vm.undo() }.keyboardShortcut("z", modifiers: [.command])
                Button("重做") { vm.redo() }.keyboardShortcut("z", modifiers: [.command, .shift])
            }
        }
    }
}
