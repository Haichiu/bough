@preconcurrency import AppKit

extension Notification.Name {
    public static let mindFlowPan = Notification.Name("mindflow.pan")
    public static let mindFlowZoom = Notification.Name("mindflow.zoom")
    public static let mindFlowFit = Notification.Name("mindflow.fit")
    public static let mindFlowReset = Notification.Name("mindflow.reset")
    public static let mindFlowShowNotes = Notification.Name("mindflow.shownotes")
}

/// Local event monitor implementing XMind-style shortcuts:
/// Tab = child, Return = sibling after, Shift+Return = sibling before,
/// Command+Return = parent, Space = edit, Delete = delete, arrows = navigate,
/// Option+Up/Down = reorder one step, Option+Cmd+Up/Down = move to edge, scroll = pan.
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
    /// Session id whose first printable character already went through the
    /// replacing path. Cleared when editing ends so re-editing the same node
    /// re-arms type-to-replace.
    private var replacedSessionID: UUID?

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

    /// The Delete/Backspace family: ⌫ and control-backspace arrive as U+007F /
    /// U+0008; the forward-delete key (⌦) arrives as U+F728 with .function set.
    public static func isDeleteKey(_ characters: String) -> Bool {
        characters == "\u{7F}" || characters == "\u{8}" || characters == "\u{F728}"
    }

    /// What the monitor must do with a Delete/Backspace keyDown. AppKit plays the
    /// system alert sound for a keyDown that reaches the end of the responder
    /// chain unhandled — the "warning sound" the Owner reported while deleting
    /// nodes — so every delete keyDown must end in one of these outcomes and
    /// never fall through to AppKit.
    public enum DeleteOutcome: Equatable {
        /// An editable text view owns the first responder: AppKit must deliver
        /// the key there (⌘⌫ / ⌥⌫ delete words and lines inside text fields).
        case fieldEditor
        /// The canvas owns the key and deletes the selected link or node.
        case deleteSelection
        /// The canvas owns the key but has nothing to delete right now (editing
        /// handoff, presentation); consume it silently instead of beeping.
        case swallowed
    }

    public struct DeleteContext: Equatable {
        public var textFieldEditing: Bool
        public var presentationActive: Bool
        public var editingHandoffActive: Bool

        public init(textFieldEditing: Bool = false,
                    presentationActive: Bool = false,
                    editingHandoffActive: Bool = false) {
            self.textFieldEditing = textFieldEditing
            self.presentationActive = presentationActive
            self.editingHandoffActive = editingHandoffActive
        }
    }

    public static func deleteOutcome(for context: DeleteContext) -> DeleteOutcome {
        if context.textFieldEditing { return .fieldEditor }
        if context.presentationActive || context.editingHandoffActive { return .swallowed }
        return .deleteSelection
    }

    /// Single dispatch path for Delete/Backspace, shared by the event monitor and
    /// the behavioral checks (same pattern as performCoreShortcut and
    /// d2Replacement). Returns true when the monitor must consume the key.
    ///
    /// Modifier flags are deliberately absent: the monitor calls this before its
    /// Command/Option/Control gates, because passing a delete keyDown to the
    /// responder chain is exactly what makes AppKit beep. ⌦ deletes like ⌫.
    @discardableResult
    public static func performDelete(vm: MindMapViewModel,
                                     textFieldEditing: Bool,
                                     editingHandoffActive: Bool) -> Bool {
        switch deleteOutcome(for: DeleteContext(
            textFieldEditing: textFieldEditing,
            presentationActive: vm.presentationActive,
            editingHandoffActive: editingHandoffActive)) {
        case .fieldEditor:
            return false
        case .swallowed:
            return true
        case .deleteSelection:
            // Delete removes the object that looks selected. A boundary or a
            // summary drawn in the selection accent used to fall through to the
            // node branch, so pressing Delete right after ⇧⌘B destroyed the
            // whole subtree the new frame was drawn around. The node is the last
            // resort, not the default.
            if let linkID = vm.selectedLinkID {
                vm.removeLink(id: linkID)
            } else if let boundaryID = vm.selectedBoundaryID {
                vm.removeBoundary(id: boundaryID)
            } else if let summaryID = vm.selectedSummaryID {
                vm.removeSummary(id: summaryID)
            } else if let selection = vm.selection {
                vm.delete(id: selection)
            }
            return true
        }
    }

    /// Performs the XMind core shortcuts that need exact modifier matching.
    /// The event monitor and behavioral checks share this one dispatch path.
    @discardableResult
    public static func performCoreShortcut(characters: String,
                                           modifiers rawModifiers: NSEvent.ModifierFlags,
                                           vm: MindMapViewModel) -> Bool {
        let modifiers = rawModifiers
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .help, .numericPad, .function])
        let key = characters.lowercased()
        let isVerticalArrow = key == "\u{F700}" || key == "\u{F701}"
        let isArrow = isVerticalArrow || key == "\u{F702}" || key == "\u{F703}"
        let isCoreShortcut =
            (modifiers == [.option] && isVerticalArrow)
            || (modifiers == [.option, .command] && (isVerticalArrow || ["/", "f", "p"].contains(key)))
            || (modifiers == [.command] && (isArrow || ["d", "r", "z"].contains(key)))
            || (modifiers == [.shift, .command] && key == "m")

        // Presentation owns the keyboard and trims its temporary undo history on exit.
        // Do not let a hidden core shortcut mutate the document into that trimmed range.
        if vm.presentationActive && isCoreShortcut {
            if modifiers == [.option, .command] && key == "p" { vm.exitPresentation() }
            return true
        }

        if modifiers == [.option], isVerticalArrow {
            if let selection = vm.selection {
                vm.moveSibling(id: selection, offset: key == "\u{F700}" ? -1 : 1)
            }
            return true
        }
        if modifiers == [.option, .command] {
            if isVerticalArrow {
                if let selection = vm.selection {
                    vm.moveSibling(id: selection, toIndex: key == "\u{F700}" ? 0 : .max)
                }
                return true
            }
            if key == "/" { vm.toggleAllBranches(); return true }
            if key == "f" { vm.toggleZen(); return true }
            if key == "p" {
                if !vm.zenMode { vm.enterPresentation() }
                return true
            }
        }
        if modifiers == [.command] {
            if isArrow {
                if let selection = vm.selection {
                    switch key {
                    case "\u{F700}": vm.nudgeOffset(id: selection, dx: 0, dy: -10)
                    case "\u{F701}": vm.nudgeOffset(id: selection, dx: 0, dy: 10)
                    case "\u{F702}": vm.nudgeOffset(id: selection, dx: -10, dy: 0)
                    case "\u{F703}": vm.nudgeOffset(id: selection, dx: 10, dy: 0)
                    default: break
                    }
                }
                return true
            }
            if key == "z" { vm.undo(); return true }
            if key == "d" {
                if let selection = vm.selection { vm.duplicate(id: selection) }
                return true
            }
            if key == "r" { vm.focusAndSelectCenter(); return true }
        }
        if modifiers == [.shift, .command], key == "m" {
            vm.toggleOutline()
            return true
        }
        return false
    }

    /// ⌘/ folds the selected branch (XMind's editor.toggleBranch). ⇧⌘/ is the
    /// macOS Help shortcut and what the "鍵盤快速鍵…" menu item advertises; both
    /// arrive as charactersIgnoringModifiers "/", so the shift flag is the only
    /// thing telling them apart. Returns true when the monitor must swallow the
    /// key — false lets it fall through to the menu key equivalent.
    @discardableResult
    public static func performBranchFold(characters: String,
                                         modifiers rawModifiers: NSEvent.ModifierFlags,
                                         vm: MindMapViewModel) -> Bool {
        let modifiers = rawModifiers
            .intersection(.deviceIndependentFlagsMask)
            .subtracting([.capsLock, .help, .numericPad, .function])
        guard characters == "/", modifiers == [.command] else { return false }
        if let selection = vm.selection { vm.toggleCollapse(id: selection) }
        return true
    }

    /// D2 decision shared by the event monitor and the behavioral checks — same
    /// dispatch-path pattern as performCoreShortcut. A bare printable character
    /// (p1-owned guard, unchanged: a selection or open session, no modifiers
    /// beyond shift, one printable non-delete scalar outside the private-use
    /// block) must land in the replacing path; anything else is not
    /// type-to-replace.
    public static func d2Replacement(characters: String?,
                                     charactersIgnoringModifiers: String,
                                     modifierFlags: NSEvent.ModifierFlags,
                                     selection: UUID?) -> (id: UUID, text: String)? {
        guard let selection,
              modifierFlags.subtracting(.shift).isEmpty,
              charactersIgnoringModifiers.count == 1,
              let scalar = charactersIgnoringModifiers.unicodeScalars.first,
              scalar.value >= 0x20, scalar.value != 0x7F, scalar.value < 0xF700 else {
            return nil
        }
        return (selection, characters ?? charactersIgnoringModifiers)
    }

    /// Runtime instrument for the "delete beeps" report (env `MINDFLOW_KEY_PROBE=<path>`).
    /// Every keyDown the monitor sees is appended as one TSV line carrying the decision
    /// (`handled` = the monitor returned nil, `passed` = AppKit's responder chain got the
    /// event and plays the system alert sound when nothing handles it) plus the state at
    /// decision time. Unset variable = no behaviour change, nothing written.
    private static var probePath: String? {
        guard let path = ProcessInfo.processInfo.environment["MINDFLOW_KEY_PROBE"],
              !path.isEmpty else { return nil }
        return path
    }

    private func probeSnapshot() -> String {
        let responder = NSApp.keyWindow?.firstResponder
        let editing = (responder as? NSTextView)?.isEditable == true
        let nodes = vm.map { $0.document.root.descendantIDs().count + 1 } ?? 0
        return [
            vm?.editingID == nil ? "editing=0" : "editing=1",
            vm?.selection == nil ? "selection=0" : "selection=1",
            vm?.selectedLinkID == nil ? "link=0" : "link=1",
            vm?.selectedSummaryID == nil ? "summary=0" : "summary=1",
            vm?.presentationActive == true ? "present=1" : "present=0",
            "nodes=\(nodes)",
            editing ? "editor=1" : "editor=0",
            String(describing: responder.map { type(of: $0) } ?? Optional<Any>.none),
        ].joined(separator: "\t")
    }

    private static func probeAppend(_ event: NSEvent, consumed: Bool, snapshot: String) {
        guard let path = probePath else { return }
        let scalars = (event.charactersIgnoringModifiers ?? "")
            .unicodeScalars.map { String(format: "U+%04X", $0.value) }.joined(separator: ",")
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue
        let line = "\(Date().timeIntervalSince1970)\t\(scalars)\tflags=\(flags)\t"
            + "\(consumed ? "handled" : "passed")\t\(snapshot)\n"
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? line.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        let snapshot = Self.probePath == nil ? "" : probeSnapshot()
        let decision = handleInner(event)
        if Self.probePath != nil {
            Self.probeAppend(event, consumed: decision == nil, snapshot: snapshot)
        }
        return decision
    }

    private func handleInner(_ event: NSEvent) -> NSEvent? {
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
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let chars = event.charactersIgnoringModifiers ?? ""

        if vm.editingID != lastSeenEditingID {
            lastSeenEditingID = vm.editingID
            editingHandoffStart = Date()
            if vm.editingID == nil { replacedSessionID = nil }
        }
        let editingHandoffActive = vm.editingID != nil
            && Date().timeIntervalSince(editingHandoffStart) < Self.editingHandoffWindow

        // Delete/Backspace is routed before every modifier gate and before the
        // editing handoff: a keyDown that falls through to AppKit makes it play
        // the system alert sound (the beep the Owner reported while deleting
        // nodes). The field editor keeps the key (guard above), every other
        // state is the canvas's — see performDelete.
        if Self.isDeleteKey(chars) {
            _ = Self.performDelete(vm: vm, textFieldEditing: false,
                                   editingHandoffActive: editingHandoffActive)
            return nil
        }

        if vm.editingID != nil, chars != "\u{1B}", editingHandoffActive {
            // The field editor installs a runloop turn or two after editingID
            // lands. Until it does, a printable keystroke passed through here
            // fell into the responder chain and was dropped: the editor opened
            // with the old text and the character never reached the document
            // (p1 measured this on two scenarios). Deliver the first character
            // of a session through the replacing path instead, reopening the
            // session one runloop turn later so the editor seeds from the
            // replaced text. Sessions already carrying a replacement (started
            // by type-to-replace itself) hand off as before.
            if let editing = vm.editingID, editing != replacedSessionID,
               let d2 = Self.d2Replacement(characters: event.characters,
                                           charactersIgnoringModifiers: chars,
                                           modifierFlags: flags,
                                           selection: editing) {
                vm.stopEditing()
                let target = d2.id
                let replacement = d2.text
                DispatchQueue.main.async {
                    guard vm.editingID == nil, vm.selection == target else { return }
                    vm.beginEditing(id: target, replacingWith: replacement)
                }
                replacedSessionID = target
                return nil
            }
            return event
        }

        if Self.performCoreShortcut(characters: chars, modifiers: flags, vm: vm) { return nil }

        // Remaining Command shortcuts.
        if flags.contains(.command) {
            // Xmind editor.addParentTopic is Command+Enter on macOS. Do not let extra
            // Shift/Option/Control modifiers silently trigger a different command.
            let commandOnly = flags.subtracting([.command, .numericPad, .function]).isEmpty
            if commandOnly, chars == "\r" || chars == "\u{3}" {
                if let selection = vm.selection { vm.insertParent(id: selection) }
                return nil
            }
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
            // Xmind parity: ⌘/ folds a branch, ⇧⌘N opens the notes editor. Both are read
            // straight out of Xmind's own command table (editor.toggleBranch,
            // editor.showNotesEditor) rather than guessed. ⇧⌘/ is the Help shortcut, so
            // performBranchFold declines it and the event reaches the menu item.
            if Self.performBranchFold(characters: chars, modifiers: flags, vm: vm) {
                return nil
            }
            if chars.lowercased() == "n", flags.contains(.shift) {
                NotificationCenter.default.post(name: .mindFlowShowNotes, object: nil)
                return nil
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
        case "\t", "\u{19}":
            // Shift+Tab outdents (XMind's outliner guide: "press Shift + Tab to
            // outdent"). Depending on the responder chain the shifted Tab arrives
            // either as charactersIgnoringModifiers "\u{19}" (the traditional
            // back-tab byte) or as a plain "\t" carrying .shift, so both spellings
            // route here and only the shifted one promotes.
            if chars == "\u{19}" || flags.contains(.shift) {
                if let selection = vm.selection { vm.promote(id: selection) }
            } else {
                vm.addChild(to: vm.selection ?? vm.document.root.id)
            }
            return nil
        case "\r", "\u{3}":
            if flags.contains(.shift) {
                // Xmind editor.addTopicBefore. The central topic has no sibling.
                if let selection = vm.selection { vm.addSiblingBefore(of: selection) }
            } else {
                // Xmind editor.addTopic. The central topic has no sibling, so plain Enter
                // there creates a new main topic. Space (editor.showEditBox) edits.
                if let selection = vm.selection, selection != vm.document.root.id {
                    vm.addSibling(of: selection)
                } else {
                    vm.addChild(to: vm.document.root.id)
                }
            }
            return nil
        case " ":
            // Xmind parity: editor.showEditBox. Folding moved to ⌘/ to free this up.
            if let selection = vm.selection {
                vm.beginEditing(id: selection)
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
            if let d2 = Self.d2Replacement(characters: event.characters,
                                           charactersIgnoringModifiers: chars,
                                           modifierFlags: flags,
                                           selection: vm.selection) {
                vm.beginEditing(id: d2.id, replacingWith: d2.text)
                replacedSessionID = d2.id
                return nil
            }
            return event
        }
    }
}
