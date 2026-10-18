import NativeCommands

#if canImport(AppKit)
import AppKit
#endif

/// Captures the keys the user presses while Settings records a shortcut, before the menu bar can
/// act on them (recording ⌘N mustn't start a session).
///
/// On the Mac a local event monitor takes each key press, and modifier changes so the recorder can
/// show the keys held so far. iPadOS has no hook ahead of the key commands, so there the recorder
/// listens with `onKeyPress` and a key the menu claims runs its command instead
/// (`capturesBeforeMenus` is false).
@MainActor
final class PlatformKeyRecorder {
    static let capturesBeforeMenus: Bool = {
        #if canImport(AppKit)
        true
        #else
        false
        #endif
    }()

    #if canImport(AppKit)
    private var monitor: Any?
    #endif

    /// Starts capturing until `stop()`: `onModifiers` gets the modifiers held, `onKey` each key
    /// pressed with them (nil for a key a shortcut can't use).
    func start(
        onModifiers: @escaping @MainActor (KeyShortcut.Modifiers) -> Void,
        onKey: @escaping @MainActor (KeyShortcut?) -> Void
    ) {
        stop()
        #if canImport(AppKit)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            MainActor.assumeIsolated {
                if event.type == .flagsChanged {
                    onModifiers(KeyShortcut.Modifiers(event.modifierFlags))
                } else {
                    onKey(KeyShortcut(event))
                }
            }
            return nil
        }
        #endif
    }

    func stop() {
        #if canImport(AppKit)
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        #endif
    }
}

#if canImport(AppKit)
extension KeyShortcut.Modifiers {
    fileprivate init(_ flags: NSEvent.ModifierFlags) {
        self = []
        if flags.contains(.command) { insert(.command) }
        if flags.contains(.shift) { insert(.shift) }
        if flags.contains(.option) { insert(.option) }
        if flags.contains(.control) { insert(.control) }
    }
}

extension KeyShortcut {
    /// The key by its position, so ⇧⌘[ is "[" with shift rather than "{", and ⌥ doesn't turn a
    /// letter into a symbol.
    fileprivate init?(_ event: NSEvent) {
        let modifiers = Modifiers(event.modifierFlags)
        if let special = Self.specialKeyCodes[event.keyCode] {
            self.init(special, modifiers: modifiers)
            return
        }
        guard let character = event.characters(byApplyingModifiers: [])?.first,
            character.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }),
            !character.isWhitespace,
            // Function keys and the like arrive as private-use characters.
            character.unicodeScalars.allSatisfy({ !(0xF700...0xF8FF).contains($0.value) })
        else { return nil }
        self.init(.character(character), modifiers: modifiers)
    }

    private static let specialKeyCodes: [UInt16: Key] = [
        36: .return, 76: .return, 48: .tab, 49: .space, 51: .delete, 117: .forwardDelete, 53: .escape,
        126: .upArrow, 125: .downArrow, 123: .leftArrow, 124: .rightArrow,
        115: .home, 119: .end, 116: .pageUp, 121: .pageDown,
    ]
}
#endif
