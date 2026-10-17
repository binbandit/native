/// Native's terminal configuration in Ghostty's config file syntax (`key = value` lines), which is
/// how libghostty takes its settings. It never reads the user's own Ghostty config: the terminal
/// looks like Native, and Native's settings are the only ones that apply.
public struct GhosttyConfiguration: Hashable, Sendable {
    public var settings: TerminalSettings
    public var colors: TerminalColors
    /// The family used when `settings.fontFamily` is nil: the app's code font.
    public var defaultFontFamily: String
    /// Space between the text and the edge of the terminal, in points.
    public var padding: Padding

    public struct Padding: Hashable, Sendable {
        public var horizontal: Int
        public var vertical: Int

        public init(horizontal: Int, vertical: Int) {
            self.horizontal = horizontal
            self.vertical = vertical
        }
    }

    public init(settings: TerminalSettings, colors: TerminalColors, defaultFontFamily: String, padding: Padding) {
        self.settings = settings
        self.colors = colors
        self.defaultFontFamily = defaultFontFamily
        self.padding = padding
    }

    /// The config file's contents.
    public var text: String {
        var lines: [String] = []
        func set(_ key: String, _ value: String) {
            lines.append("\(key) = \(value)")
        }

        set("font-family", Self.quoted(settings.fontFamily ?? defaultFontFamily))
        set("font-size", Self.number(settings.fontSize))

        let chrome = colors.chrome
        set("background", chrome.background.description)
        set("foreground", chrome.foreground.description)
        set("cursor-color", chrome.cursor.description)
        set("cursor-text", chrome.cursorText.description)
        set("selection-background", chrome.selectionBackground.description)
        for (index, color) in colors.palette.enumerated() {
            set("palette", "\(index)=\(color)")
        }
        set("window-padding-x", String(padding.horizontal))
        set("window-padding-y", String(padding.vertical))
        set("window-padding-balance", "true")

        // The line limit is the one users choose; the byte limit would otherwise cut in first.
        switch settings.scrollback {
        case .lines(let count): set("scrollback-limit-lines", String(count))
        case .unlimited: set("scrollback-limit-lines", "unlimited")
        }
        set("scrollback-limit-bytes", "unlimited")

        // Native shows its own state when a shell exits or fails to start, keeps the tab around
        // until the user closes it, and asks before closing a tab with a running process.
        set("wait-after-command", "true")
        set("confirm-close-surface", "false")
        // Programs may copy (OSC 52) but never read the clipboard.
        set("clipboard-read", "deny")
        set("clipboard-write", "allow")
        set("mouse-hide-while-typing", "true")
        set("desktop-notifications", "false")

        lines.append(contentsOf: Self.keybinds.map { "keybind = \($0)" })
        return lines.joined(separator: "\n") + "\n"
    }

    /// Ghostty's default bindings would take keys the app owns (⌘N, ⌘W, ⌘Q, ⌘T, ⌘D, ...), so
    /// they're cleared, and only these terminal-local ones come back (docs/keyboard.md, Terminal).
    /// Copy, paste and select all go through the Edit menu instead.
    static let keybinds = [
        "clear",
        "performable:super+k=clear_screen",
        "super+home=scroll_to_top",
        "super+end=scroll_to_bottom",
        "super+page_up=scroll_page_up",
        "super+page_down=scroll_page_down",
        "shift+page_up=scroll_page_up",
        "shift+page_down=scroll_page_down",
        "super+shift+arrow_up=jump_to_prompt:-1",
        "super+shift+arrow_down=jump_to_prompt:1",
        // macOS text editing, as in Ghostty and Terminal.
        "super+arrow_left=text:\\x01",
        "super+arrow_right=text:\\x05",
        "super+backspace=text:\\x15",
        "alt+arrow_left=esc:b",
        "alt+arrow_right=esc:f",
    ]

    /// A quoted config value. Ghostty strips one pair of surrounding quotes; a line break or quote
    /// inside would end the value early, so those are dropped.
    static func quoted(_ value: String) -> String {
        "\"" + value.filter { $0 != "\"" && !$0.isNewline } + "\""
    }

    static func number(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}
