@preconcurrency import AppKit

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

    /// How long the keyboard is handed to a node after editingID changes, before the
    /// canvas takes shortcuts back. Long enough for AppKit to install the field editor,
    /// short enough that a stuck editingID cannot lock the keyboard out.
    private static let editingHandoffWindow: TimeInterval = 0.6
    private var lastSeenEditingID: UUID?
    private var editingHandoffStart = Date.distantPast

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
            guard vm.isCursorOverCanvas else { return event }
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

        // Closing the focus race: setting editingID triggers a SwiftUI update, but AppKit
        // only makes the field editor first responder on a later runloop turn. During that
        // window the guard above still sees the old responder, so keystrokes intended for
        // the node were being swallowed as canvas shortcuts (Tab spawned a child, Return
        // spawned a sibling, Space collapsed). Larger maps widened the window.
        //
        // The handoff is deliberately time-boxed. An unbounded "editingID != nil means
        // hands off" rule would kill the keyboard outright whenever editingID is set but
        // no editor ever appears. Esc is always excluded so there is a way back.
        if vm.editingID != lastSeenEditingID {
            lastSeenEditingID = vm.editingID
            editingHandoffStart = Date()
        }
        if vm.editingID != nil, event.charactersIgnoringModifiers != "\u{1B}",
           Date().timeIntervalSince(editingHandoffStart) < Self.editingHandoffWindow {
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

        // Presentation mode swallows editing keys and steers the reveal instead.
        if vm.presentationActive {
            switch chars {
            case "\u{F703}": vm.stepPresentation(); return nil          // right
            case " ": vm.stepPresentation(); return nil                 // space
            case "\u{F702}": vm.rewindPresentation(); return nil        // left
            case "\u{1B}": vm.exitPresentation(); return nil            // esc
            case "\u{F700}", "\u{F701}": return event                  // let up/down pass
            default: return nil
            }
        }

        switch chars {
        case "\t":
            vm.addChild(to: vm.selection ?? vm.document.root.id)
            return nil
        case "\r", "\u{3}":
            // D2 keyboard model: Return edits the selected node. Spawning the next
            // sibling is what Return does *while editing* (see onCommitEdit), which is
            // the MindNode/XMind rapid-entry loop. Return used to create a sibling here,
            // so there was no keyboard route into an existing node at all.
            if let selection = vm.selection {
                vm.beginEditing(id: selection)
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
            if vm.zenMode {
                vm.toggleZen()
                return nil // exiting focus mode should not also clear selection
            }
            vm.focusBranchID = nil
            vm.clearBatchSelection()
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
            // Type-to-replace (D2): a bare printable character on a selected node wipes
            // the text and drops straight into the editor, as MindNode and XMind do.
            // Excludes the 0xF700-0xF8FF private-use block, which is where AppKit puts
            // arrows and function keys.
            if let selection = vm.selection,
               flags.subtracting(.shift).isEmpty,
               chars.count == 1,
               let scalar = chars.unicodeScalars.first,
               scalar.value >= 0x20, scalar.value != 0x7F, scalar.value < 0xF700 {
                vm.beginEditing(id: selection, replacingWith: event.characters ?? chars)
                return nil
            }
            return event
        }
    }
}
