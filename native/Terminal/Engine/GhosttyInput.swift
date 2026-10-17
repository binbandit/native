#if canImport(GhosttyKit) && TERMINAL_ENGINE_WIP
import AppKit
import GhosttyKit

/// Translates AppKit input into libghostty's types.
enum GhosttyInput {
    /// Device-dependent bits of `NSEvent.ModifierFlags` that say which side's key is down
    /// (`NX_DEVICER*KEYMASK` in IOKit's IOLLEvent.h).
    private enum RightSide {
        static let shift: UInt = 0x0000_0004
        static let control: UInt = 0x0000_2000
        static let option: UInt = 0x0000_0040
        static let command: UInt = 0x0000_0010
    }

    static func mods(_ flags: NSEvent.ModifierFlags) -> ghostty_input_mods_e {
        var mods = GHOSTTY_MODS_NONE.rawValue
        if flags.contains(.shift) { mods |= GHOSTTY_MODS_SHIFT.rawValue }
        if flags.contains(.control) { mods |= GHOSTTY_MODS_CTRL.rawValue }
        if flags.contains(.option) { mods |= GHOSTTY_MODS_ALT.rawValue }
        if flags.contains(.command) { mods |= GHOSTTY_MODS_SUPER.rawValue }
        if flags.contains(.capsLock) { mods |= GHOSTTY_MODS_CAPS.rawValue }
        let raw = flags.rawValue
        if raw & RightSide.shift != 0 { mods |= GHOSTTY_MODS_SHIFT_RIGHT.rawValue }
        if raw & RightSide.control != 0 { mods |= GHOSTTY_MODS_CTRL_RIGHT.rawValue }
        if raw & RightSide.option != 0 { mods |= GHOSTTY_MODS_ALT_RIGHT.rawValue }
        if raw & RightSide.command != 0 { mods |= GHOSTTY_MODS_SUPER_RIGHT.rawValue }
        return ghostty_input_mods_e(mods)
    }

    static func flags(_ mods: ghostty_input_mods_e) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if mods.rawValue & GHOSTTY_MODS_SHIFT.rawValue != 0 { flags.insert(.shift) }
        if mods.rawValue & GHOSTTY_MODS_CTRL.rawValue != 0 { flags.insert(.control) }
        if mods.rawValue & GHOSTTY_MODS_ALT.rawValue != 0 { flags.insert(.option) }
        if mods.rawValue & GHOSTTY_MODS_SUPER.rawValue != 0 { flags.insert(.command) }
        return flags
    }

    /// Whether the right-hand key of a modifier pair is the one down.
    static func isRightSide(_ keyCode: UInt16, in flags: NSEvent.ModifierFlags) -> Bool {
        let raw = flags.rawValue
        return switch keyCode {
        case 0x3C: raw & RightSide.shift != 0
        case 0x3E: raw & RightSide.control != 0
        case 0x3D: raw & RightSide.option != 0
        case 0x36: raw & RightSide.command != 0
        default: true
        }
    }

    /// Scroll modifiers, packed as libghostty's `ScrollMods`: bit 0 precise, bits 1-3 momentum.
    static func scrollMods(precise: Bool, phase: NSEvent.Phase) -> ghostty_input_scroll_mods_t {
        let momentum: ghostty_input_mouse_momentum_e =
            switch phase {
            case .began: GHOSTTY_MOUSE_MOMENTUM_BEGAN
            case .stationary: GHOSTTY_MOUSE_MOMENTUM_STATIONARY
            case .changed: GHOSTTY_MOUSE_MOMENTUM_CHANGED
            case .ended: GHOSTTY_MOUSE_MOMENTUM_ENDED
            case .cancelled: GHOSTTY_MOUSE_MOMENTUM_CANCELLED
            case .mayBegin: GHOSTTY_MOUSE_MOMENTUM_MAY_BEGIN
            default: GHOSTTY_MOUSE_MOMENTUM_NONE
            }
        return ghostty_input_scroll_mods_t((precise ? 1 : 0) | Int32(momentum.rawValue) << 1)
    }
}

extension NSEvent {
    /// A libghostty key event without its text, which the caller sets for as long as it's valid.
    ///
    /// - Parameter translationMods: The modifiers that produced the text, when they differ from
    ///   the event's (Option used as Alt, say).
    func ghosttyKeyEvent(_ action: ghostty_input_action_e, translationMods: NSEvent.ModifierFlags? = nil)
        -> ghostty_input_key_s
    {
        var event = ghostty_input_key_s()
        event.action = action
        event.keycode = UInt32(keyCode)
        event.text = nil
        event.composing = false
        event.mods = GhosttyInput.mods(modifierFlags)
        // AppKit doesn't say which modifiers produced the text; as in Ghostty, assume all but
        // Control and Command did.
        event.consumed_mods = GhosttyInput.mods((translationMods ?? modifierFlags).subtracting([.control, .command]))
        event.unshifted_codepoint = 0
        if type == .keyDown || type == .keyUp, let scalar = characters(byApplyingModifiers: [])?.unicodeScalars.first {
            event.unshifted_codepoint = scalar.value
        }
        return event
    }

    /// The text to send with a key event. libghostty encodes control characters itself, and
    /// function keys arrive as private-use characters that aren't text.
    var ghosttyCharacters: String? {
        guard let characters else { return nil }
        if characters.count == 1, let scalar = characters.unicodeScalars.first {
            if scalar.value < 0x20 {
                return self.characters(byApplyingModifiers: modifierFlags.subtracting(.control))
            }
            if (0xF700...0xF8FF).contains(scalar.value) {
                return nil
            }
        }
        return characters
    }
}

extension String {
    /// The string as key event text: nil when empty or starting with an ASCII control character,
    /// which libghostty encodes from the key instead.
    var ghosttyKeyText: String? {
        guard let first = unicodeScalars.first else { return nil }
        return first.value < 0x20 || first.value == 0x7F ? nil : self
    }
}
#endif
