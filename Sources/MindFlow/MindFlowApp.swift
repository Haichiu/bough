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
                    .keyboardShortcut("n")
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
                Button(vm.zenMode ? "離開專注模式" : "專注模式") { vm.toggleZen() }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
                Divider()
                Button(vm.presentationActive ? "結束簡報" : "簡報模式（逐層揭開）") {
                    if vm.presentationActive { vm.exitPresentation() } else { vm.enterPresentation() }
                }
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
                    if let selection = vm.selection { vm.duplicate(id: selection) }
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
                Button("加入子主題") { vm.addChild(to: vm.selection ?? vm.document.root.id) }
                    .keyboardShortcut(KeyEquivalent.tab, modifiers: [])
                Button("加入兄弟主題") {
                    if let selection = vm.selection, selection != vm.document.root.id {
                        vm.addSibling(of: selection)
                    }
                }
                .keyboardShortcut(.return, modifiers: [])
                Button("刪除主題") {
                    if let selection = vm.selection { vm.delete(id: selection) }
                }
                .keyboardShortcut(.delete, modifiers: [])
                Divider()
                Button("復原") { vm.undo() }.keyboardShortcut("z", modifiers: [])
                Button("重做") { vm.redo() }.keyboardShortcut("z", modifiers: [.shift])
            }
        }
    }
}
