import AppKit

extension Notification.Name {
    public static let mindFlowPan = Notification.Name("mindflow.pan")
    public static let mindFlowZoom = Notification.Name("mindflow.zoom")
    public static let mindFlowFit = Notification.Name("mindflow.fit")
    public static let mindFlowReset = Notification.Name("mindflow.reset")
}

/// Local event monitor implementing XMind-style shortcuts:
/// Tab = add child, Return = add sibling, Delete = delete,
/// arrows = navigate, Space = toggle collapse, Esc = deselect,
/// Option+Cmd+Up/Down = reorder sibling, two-finger scroll = pan, Cmd+scroll = zoom.
@MainActor
public final class KeyboardMonitor {
    public static let shared = KeyboardMonitor()
    private var monitor: Any?
    private weak var vm: MindMapViewModel?

    public func start(vm: MindMapViewModel) {
        self.vm = vm
        guard monitor == nil else { return }
        // Local monitors fire on the main thread, so assumeIsolated is safe here.
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .scrollWheel]) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handle(event) ?? event
            }
        }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard let vm else { return event }

        if event.type == .scrollWheel {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags.contains(.command) {
                let factor = max(0.8, min(1.25, 1 + event.scrollingDeltaY * 0.02))
                NotificationCenter.default.post(name: .mindFlowZoom, object: nil,
                                                userInfo: ["factor": CGFloat(factor)])
            } else {
                NotificationCenter.default.post(name: .mindFlowPan, object: nil, userInfo: [
                    "dx": Double(event.scrollingDeltaX),
                    "dy": Double(event.scrollingDeltaY),
                ])
            }
            return event
        }

        guard event.type == .keyDown else { return event }

        // Never intercept while a text field / editor has focus.
        if let textView = NSApp.keyWindow?.firstResponder as? NSTextView, textView.isEditable {
            return event
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let chars = event.charactersIgnoringModifiers ?? ""

        // Option+Cmd+Up/Down: move the selected node among its siblings.
        if flags.contains(.command) {
            // Standard zoom shortcuts.
            switch chars {
            case "+", "=":
                NotificationCenter.default.post(name: .mindFlowZoom, object: nil, userInfo: ["factor": CGFloat(1.15)])
                return nil
            case "-":
                NotificationCenter.default.post(name: .mindFlowZoom, object: nil, userInfo: ["factor": CGFloat(1 / 1.15)])
                return nil
            case "0":
                NotificationCenter.default.post(name: .mindFlowReset, object: nil)
                return nil
            default:
                break
            }
            if let selection = vm.selection {
                // ⌘ arrows nudge the node's manual offset.
                switch chars {
                case "\u{F700}":
                    vm.nudgeOffset(id: selection, dx: 0, dy: -10)
                    return nil
                case "\u{F701}":
                    vm.nudgeOffset(id: selection, dx: 0, dy: 10)
                    return nil
                case "\u{F702}":
                    vm.nudgeOffset(id: selection, dx: -10, dy: 0)
                    return nil
                case "\u{F703}":
                    vm.nudgeOffset(id: selection, dx: 10, dy: 0)
                    return nil
                default:
                    break
                }
                // ⌥⌘↑/↓ reorder siblings.
                if flags.contains(.option) {
                    switch chars {
                    case "\u{F700}":
                        vm.moveSibling(id: selection, offset: -1)
                        return nil
                    case "\u{F701}":
                        vm.moveSibling(id: selection, offset: 1)
                        return nil
                    default:
                        break
                    }
                }
            }
            return event // let remaining Cmd shortcuts pass through
        }

        guard flags.subtracting([.shift, .numericPad, .function]).isEmpty else { return event }

        switch chars {
        case "\t":
            vm.addChild(to: vm.selection ?? vm.document.root.id)
            return nil
        case "\r", "\u{3}":
            if let selection = vm.selection, selection != vm.document.root.id {
                vm.addSibling(of: selection)
            } else {
                vm.addChild(to: vm.document.root.id)
            }
            return nil
        case "\u{7F}", "\u{8}":
            if let linkID = vm.selectedLinkID {
                vm.removeLink(id: linkID)
            } else if let selection = vm.selection {
                vm.delete(id: selection)
            }
            return nil
        case " ":
            if let selection = vm.selection {
                vm.toggleCollapse(id: selection)
            }
            return nil
        case "\u{F700}": // up
            vm.selectSibling(offset: -1)
            return nil
        case "\u{F701}": // down
            vm.selectSibling(offset: 1)
            return nil
        case "\u{F702}": // left
            vm.selectParent()
            return nil
        case "\u{F703}": // right
            vm.selectChild()
            return nil
        case "\u{1B}": // esc
            if vm.zenMode { vm.toggleZen() }
            vm.focusBranchID = nil
            vm.stopEditing()
            vm.selection = nil
            if vm.showSearch {
                vm.showSearch = false
                vm.searchQuery = ""
                vm.searchResults = []
            }
            vm.showHelp = false
            return nil
        default:
            return event
        }
    }
}
