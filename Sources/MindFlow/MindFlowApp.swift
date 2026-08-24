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

    var body: some Scene {
        WindowGroup("MindFlow") {
            ContentView()
                .environmentObject(vm)
                .frame(minWidth: 960, minHeight: 620)
                .onAppear {
                    KeyboardMonitor.shared.start(vm: vm)
                    installQuitAutosave(vm)
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
                Button("開啟…") { vm.open() }
                    .keyboardShortcut("o")
                Button("匯入 Markdown…") { vm.importMarkdown() }
                    .keyboardShortcut("i", modifiers: [.command, .shift])
                Button("匯入 OPML…") { vm.importOPML() }
                Button("儲存…") { vm.save() }
                    .keyboardShortcut("s")
                Divider()
                Menu("匯出") {
                    Button("Markdown…") { vm.exportRequest = .markdown }
                    Button("OPML…") { vm.exportRequest = .opml }
                    Button("PNG 圖片…") { vm.exportRequest = .png }
                    Button("PDF 文件…") { vm.exportRequest = .pdf }
                }
            }
            CommandMenu("分頁") {
                Button("下一個分頁") { vm.cycleTab(1) }
                    .keyboardShortcut(.tab, modifiers: [.control])
                Button("上一個分頁") { vm.cycleTab(-1) }
                    .keyboardShortcut(.tab, modifiers: [.control, .shift])
                Divider()
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
