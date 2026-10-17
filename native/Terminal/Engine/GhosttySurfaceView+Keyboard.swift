#if canImport(GhosttyKit) && TERMINAL_ENGINE_WIP
import AppKit
import Carbon
import GhosttyKit

// Keyboard input, ported from Ghostty's macOS app: keys go through AppKit's input method system
// first (`interpretKeyEvents`), so dead keys, Korean, Japanese and dictation compose the way they
// do in any Mac text field, then reach libghostty as key events with the composed text.
extension GhosttySurfaceView {
    override func keyDown(with event: NSEvent) {
        guard let surface else {
            interpretKeyEvents([event])
            return
        }

        // Option-as-Alt and similar settings change which modifiers produce text.
        let translationFlags = GhosttyInput.flags(
            ghostty_surface_key_translation_mods(surface, GhosttyInput.mods(event.modifierFlags)))
        var translationMods = event.modifierFlags
        for flag in [NSEvent.ModifierFlags.shift, .control, .option, .command] {
            if translationFlags.contains(flag) {
                translationMods.insert(flag)
            } else {
                translationMods.remove(flag)
            }
        }
        // Reuse the original event when nothing changed: input methods (Korean in particular)
        // rely on getting the same event back.
        let translationEvent =
            translationMods == event.modifierFlags
            ? event
            : NSEvent.keyEvent(
                with: event.type,
                location: event.locationInWindow,
                modifierFlags: translationMods,
                timestamp: event.timestamp,
                windowNumber: event.windowNumber,
                context: nil,
                characters: event.characters(byApplyingModifiers: translationMods) ?? "",
                charactersIgnoringModifiers: event.charactersIgnoringModifiers ?? "",
                isARepeat: event.isARepeat,
                keyCode: event.keyCode
            ) ?? event

        let action = event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS
        keyTextAccumulator = []
        defer { keyTextAccumulator = nil }
        let hadMarkedText = markedText.length > 0
        let layoutBefore = hadMarkedText ? nil : Self.keyboardLayoutID
        lastPerformKeyEvent = nil

        interpretKeyEvents([translationEvent])

        // A key that switched the input source belongs to the input method, not the terminal.
        if !hadMarkedText, layoutBefore != Self.keyboardLayoutID {
            return
        }
        syncPreedit(clearIfNeeded: hadMarkedText)
        let composing = markedText.length > 0 || hadMarkedText

        if let committed = keyTextAccumulator, !committed.isEmpty {
            for text in committed where !Self.isComposingControl(text, composing: composing) {
                if hadMarkedText {
                    sendCommittedText(text, action: action)
                } else {
                    sendKey(action, event: event, translationEvent: translationEvent, text: text)
                }
            }
            return
        }
        if Self.isComposingControl(event.characters, composing: composing) {
            return
        }
        sendKey(
            action, event: event, translationEvent: translationEvent, text: translationEvent.ghosttyCharacters,
            composing: composing)
    }

    override func keyUp(with event: NSEvent) {
        sendKey(GHOSTTY_ACTION_RELEASE, event: event)
    }

    override func flagsChanged(with event: NSEvent) {
        let mod: UInt32
        switch event.keyCode {
        case 0x39: mod = GHOSTTY_MODS_CAPS.rawValue
        case 0x38, 0x3C: mod = GHOSTTY_MODS_SHIFT.rawValue
        case 0x3B, 0x3E: mod = GHOSTTY_MODS_CTRL.rawValue
        case 0x3A, 0x3D: mod = GHOSTTY_MODS_ALT.rawValue
        case 0x37, 0x36: mod = GHOSTTY_MODS_SUPER.rawValue
        default: return
        }
        guard !hasMarkedText() else { return }
        let pressed =
            GhosttyInput.mods(event.modifierFlags).rawValue & mod != 0
            && GhosttyInput.isRightSide(event.keyCode, in: event.modifierFlags)
        sendKey(pressed ? GHOSTTY_ACTION_PRESS : GHOSTTY_ACTION_RELEASE, event: event)
    }

    /// AppKit offers ⌘ and ⌃ keys here before the menus. The terminal's own bindings
    /// (`GhosttyConfiguration.keybinds`) are handled now; every other ⌘ key goes on to the menus
    /// (so Native's shortcuts work while typing in a terminal), and a ⌃ key no menu claims comes
    /// back through `keyDown` to reach the shell.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown, isFocused, let surface else { return false }

        var keyEvent = event.ghosttyKeyEvent(GHOSTTY_ACTION_PRESS)
        let isBinding = (event.characters ?? "").withCString { text in
            keyEvent.text = text
            return ghostty_surface_key_is_binding(surface, keyEvent, nil)
        }
        if isBinding {
            keyDown(with: event)
            return true
        }

        let equivalent: String
        switch event.charactersIgnoringModifiers {
        case "\r":
            // ⌃Return reaches the shell instead of opening a context menu.
            guard event.modifierFlags.contains(.control) else { return false }
            equivalent = "\r"
        case "/":
            // ⌃/ is ⌃_ in a terminal; AppKit would beep.
            guard event.modifierFlags.contains(.control),
                event.modifierFlags.isDisjoint(with: [.shift, .command, .option])
            else { return false }
            equivalent = "_"
        default:
            // AppKit sometimes synthesizes events with no timestamp (⌘. as Escape); leave them be.
            guard event.timestamp != 0, !event.modifierFlags.isDisjoint(with: [.command, .control]) else {
                lastPerformKeyEvent = nil
                return false
            }
            // The second time the same event arrives, no menu wanted it: it's for the terminal.
            if let last = lastPerformKeyEvent, last == event.timestamp {
                lastPerformKeyEvent = nil
                equivalent = event.characters ?? ""
            } else {
                lastPerformKeyEvent = event.timestamp
                return false
            }
        }

        guard
            let keyEvent = NSEvent.keyEvent(
                with: .keyDown,
                location: event.locationInWindow,
                modifierFlags: event.modifierFlags,
                timestamp: event.timestamp,
                windowNumber: event.windowNumber,
                context: nil,
                characters: equivalent,
                charactersIgnoringModifiers: equivalent,
                isARepeat: event.isARepeat,
                keyCode: event.keyCode
            )
        else { return false }
        keyDown(with: keyEvent)
        return true
    }

    /// Unhandled editing commands (⌃A as `moveToBeginningOfParagraph:`, ...) would beep. A ⌘ key
    /// AppKit turned into a command during `performKeyEquivalent` goes back through the event
    /// system so it reaches `keyDown`.
    override func doCommand(by selector: Selector) {
        if let last = lastPerformKeyEvent, let current = NSApp.currentEvent, last == current.timestamp {
            NSApp.sendEvent(current)
        }
    }

    private func sendKey(
        _ action: ghostty_input_action_e, event: NSEvent, translationEvent: NSEvent? = nil, text: String? = nil,
        composing: Bool = false
    ) {
        guard let surface else { return }
        var keyEvent = event.ghosttyKeyEvent(action, translationMods: translationEvent?.modifierFlags)
        keyEvent.composing = composing
        guard let text = text?.ghosttyKeyText else {
            ghostty_surface_key(surface, keyEvent)
            return
        }
        text.withCString { pointer in
            keyEvent.text = pointer
            ghostty_surface_key(surface, keyEvent)
        }
    }

    /// Text an input method committed, sent as typed input (never as a paste).
    func sendCommittedText(_ text: String, action: ghostty_input_action_e = GHOSTTY_ACTION_PRESS) {
        guard let surface else { return }
        var keyEvent = ghostty_input_key_s()
        keyEvent.action = action
        keyEvent.mods = GHOSTTY_MODS_NONE
        keyEvent.consumed_mods = GHOSTTY_MODS_NONE
        text.withCString { pointer in
            keyEvent.text = pointer
            ghostty_surface_key(surface, keyEvent)
        }
    }

    /// Tells libghostty what the input method is composing, so it draws it at the cursor.
    func syncPreedit(clearIfNeeded: Bool = true) {
        guard let surface else { return }
        if markedText.length > 0 {
            let text = markedText.string
            text.withCString { ghostty_surface_preedit(surface, $0, UInt(text.utf8.count)) }
        } else if clearIfNeeded {
            ghostty_surface_preedit(surface, nil, 0)
        }
    }

    /// A lone control character arriving mid-composition belongs to the input method.
    private static func isComposingControl(_ text: String?, composing: Bool) -> Bool {
        guard composing, let text, text.unicodeScalars.count == 1, let scalar = text.unicodeScalars.first else {
            return false
        }
        return scalar.value < 0x20
    }

    private static var keyboardLayoutID: String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
            let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID)
        else { return nil }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }
}

// MARK: - NSTextInputClient

extension GhosttySurfaceView: NSTextInputClient {
    func hasMarkedText() -> Bool {
        markedText.length > 0
    }

    func markedRange() -> NSRange {
        markedText.length > 0 ? NSRange(location: 0, length: markedText.length) : NSRange()
    }

    func selectedRange() -> NSRange {
        guard let surface else { return NSRange() }
        var text = ghostty_text_s()
        guard ghostty_surface_read_selection(surface, &text) else { return NSRange() }
        defer { ghostty_surface_free_text(surface, &text) }
        return NSRange(location: Int(text.offset_start), length: Int(text.offset_len))
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        switch string {
        case let attributed as NSAttributedString:
            markedText = NSMutableAttributedString(attributedString: attributed)
        case let plain as String:
            markedText = NSMutableAttributedString(string: plain)
        default:
            return
        }
        // Outside keyDown (a layout switch mid-composition), show it right away.
        if keyTextAccumulator == nil {
            syncPreedit()
        }
    }

    func unmarkText() {
        guard markedText.length > 0 else { return }
        markedText.mutableString.setString("")
        syncPreedit()
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        []
    }

    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        guard let surface, range.length > 0 else { return nil }
        var text = ghostty_text_s()
        guard ghostty_surface_read_selection(surface, &text) else { return nil }
        defer { ghostty_surface_free_text(surface, &text) }
        return NSAttributedString(string: String(cString: text.text))
    }

    func characterIndex(for point: NSPoint) -> Int {
        0
    }

    /// Where the input method's candidate window goes: under the cursor.
    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        guard let surface else { return NSRect(origin: frame.origin, size: .zero) }
        var x = 0.0
        var y = 0.0
        var width = cellSize.width
        var height = cellSize.height
        ghostty_surface_ime_point(surface, &x, &y, &width, &height)
        if range.length == 0, width > 0 {
            width = 0
            x += cellSize.width * Double(range.location)
        }
        let rect = NSRect(x: x, y: bounds.height - y, width: width, height: max(height, cellSize.height))
        let inWindow = convert(rect, to: nil)
        return window?.convertToScreen(inWindow) ?? inWindow
    }

    func insertText(_ string: Any, replacementRange: NSRange) {
        guard NSApp.currentEvent != nil else { return }
        let text: String
        switch string {
        case let attributed as NSAttributedString: text = attributed.string
        case let plain as String: text = plain
        default: return
        }
        unmarkText()
        // Inside keyDown the text goes out with the key event.
        if keyTextAccumulator != nil {
            keyTextAccumulator?.append(text)
            return
        }
        if !text.isEmpty {
            sendCommittedText(text)
        }
    }
}
#endif
