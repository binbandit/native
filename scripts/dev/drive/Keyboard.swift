import CoreGraphics
import Foundation

/// Key presses and typing, posted to one process with `CGEvent.postToPid`: they reach that app's
/// event queue and nothing else, whatever app has focus.
struct Keyboard {
    let pid: pid_t

    /// Presses a combo like `cmd+shift+n`, `return`, `escape` or `opt+cmd+up`.
    func press(_ combo: String, hold: Double = 0.012) throws(DriveError) {
        guard hold.isFinite, (0...3).contains(hold) else {
            throw DriveError("--hold must be between 0 and 3 seconds", code: 2)
        }
        let (code, flags) = try Self.parse(combo)
        try post(code: code, flags: flags, text: nil, hold: hold)
    }

    /// Types `text` a character at a time, as unicode key events; a newline is Shift-Return, the
    /// composer's new line.
    func type(_ text: String) throws(DriveError) {
        for character in text {
            if character == "\n" {
                try post(code: 36, flags: .maskShift, text: nil)
            } else {
                try post(code: 0, flags: [], text: String(character))
            }
        }
    }

    private func post(code: CGKeyCode, flags: CGEventFlags, text: String?, hold: Double = 0.012) throws(DriveError) {
        // A private source, so keys held on the real keyboard don't leak into the event.
        let source = CGEventSource(stateID: .privateState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true),
            let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
        else { throw DriveError("couldn't make a key event") }
        for event in [down, up] {
            event.flags = flags
            if let text {
                let units = Array(text.utf16)
                event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
            }
        }
        down.postToPid(pid)
        usleep(useconds_t(hold * 1_000_000))
        up.postToPid(pid)
        usleep(30_000)
    }

    static func parse(_ combo: String) throws(DriveError) -> (CGKeyCode, CGEventFlags) {
        var parts = combo.lowercased().split(separator: "+", omittingEmptySubsequences: false).map(String.init)
        // `cmd++` is Command and the plus key.
        if combo.hasSuffix("++") { parts = parts.dropLast(2) + ["+"] }
        guard let key = parts.last, !key.isEmpty else { throw DriveError("no key in \(combo)", code: 2) }
        var flags = CGEventFlags()
        for modifier in parts.dropLast() {
            guard let flag = modifiers[modifier] else {
                throw DriveError("unknown modifier \(modifier) in \(combo): use cmd, shift, opt, ctrl or fn", code: 2)
            }
            flags.insert(flag)
        }
        if let named = keys[key] {
            // Arrows and the navigation keys carry the function-key flag, as from a real keyboard.
            if named.code >= 115 && named.code <= 126 { flags.insert(.maskSecondaryFn) }
            if named.code >= 123 { flags.insert(.maskNumericPad) }
            if named.shift { flags.insert(.maskShift) }
            return (named.code, flags)
        }
        throw DriveError("unknown key \(key) in \(combo); see drive.sh help", code: 2)
    }

    private static let modifiers: [String: CGEventFlags] = [
        "cmd": .maskCommand, "command": .maskCommand, "⌘": .maskCommand,
        "shift": .maskShift, "⇧": .maskShift,
        "opt": .maskAlternate, "option": .maskAlternate, "alt": .maskAlternate, "⌥": .maskAlternate,
        "ctrl": .maskControl, "control": .maskControl, "⌃": .maskControl,
        "fn": .maskSecondaryFn,
    ]

    private struct Key {
        let code: CGKeyCode
        var shift = false
    }

    /// US layout virtual key codes.
    private static let keys: [String: Key] = {
        var keys: [String: Key] = [
            "return": Key(code: 36), "enter": Key(code: 76), "tab": Key(code: 48), "space": Key(code: 49),
            "delete": Key(code: 51), "backspace": Key(code: 51), "escape": Key(code: 53), "esc": Key(code: 53),
            "forwarddelete": Key(code: 117), "home": Key(code: 115), "end": Key(code: 119),
            "pageup": Key(code: 116), "pagedown": Key(code: 121),
            "left": Key(code: 123), "right": Key(code: 124), "down": Key(code: 125), "up": Key(code: 126),
            "f1": Key(code: 122), "f2": Key(code: 120), "f3": Key(code: 99), "f4": Key(code: 118),
            "f5": Key(code: 96), "f6": Key(code: 97), "f7": Key(code: 98), "f8": Key(code: 100),
            "f9": Key(code: 101), "f10": Key(code: 109), "f11": Key(code: 103), "f12": Key(code: 111),
            "plus": Key(code: 24, shift: true), "+": Key(code: 24, shift: true), "minus": Key(code: 27),
            "equal": Key(code: 24), "comma": Key(code: 43), "period": Key(code: 47), "slash": Key(code: 44),
            "backslash": Key(code: 42), "semicolon": Key(code: 41), "quote": Key(code: 39),
            "backtick": Key(code: 50), "grave": Key(code: 50), "bracketleft": Key(code: 33),
            "bracketright": Key(code: 30),
        ]
        let characters: [Character: CGKeyCode] = [
            "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12,
            "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23,
            "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34,
            "p": 35, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44, "n": 45, "m": 46,
            ".": 47, "`": 50,
        ]
        for (character, code) in characters { keys[String(character)] = Key(code: code) }
        return keys
    }()
}
