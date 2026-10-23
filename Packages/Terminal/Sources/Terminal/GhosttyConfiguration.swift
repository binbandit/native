/// Native's terminal configuration in Ghostty's config file syntax (`key = value` lines), which is
/// how libghostty takes its settings. It never reads the user's own Ghostty config: the terminal
/// looks like Native, and Native's settings are the only ones that apply.
public struct GhosttyConfiguration: Hashable, Sendable {
    public var settings: TerminalSettings
    public var colors: TerminalColors
    /// The font used when `settings.fontFamily` is nil: the app's code font.
    public var defaultFont: DefaultFont
    /// Space between the text and the edge of the terminal, in points.
    public var padding: Padding
    public var transparency: TerminalTransparency

    public struct Padding: Hashable, Sendable {
        public var horizontal: Int
        public var vertical: Int

        public init(horizontal: Int, vertical: Int) {
            self.horizontal = horizontal
            self.vertical = vertical
        }
    }

    public struct DefaultFont: Hashable, Sendable {
        public var family: String
        /// A variable font gets explicit regular and bold weights, since its default instance may
        /// be neither.
        public var isVariable: Bool

        public init(family: String, isVariable: Bool) {
            self.family = family
            self.isVariable = isVariable
        }
    }

    public init(
        settings: TerminalSettings, colors: TerminalColors, defaultFont: DefaultFont, padding: Padding,
        transparency: TerminalTransparency = .opaque
    ) {
        self.settings = settings
        self.colors = colors
        self.defaultFont = defaultFont
        self.padding = padding
        self.transparency = transparency
    }

    /// The config file's contents.
    public var text: String {
        var lines: [String] = []
        func set(_ key: String, _ value: String) {
            lines.append("\(key) = \(value)")
        }

        if let family = settings.fontFamily {
            set("font-family", Self.quoted(family))
        } else {
            set("font-family", Self.quoted(defaultFont.family))
            if defaultFont.isVariable {
                set("font-variation", "wght=400")
                set("font-variation-bold", "wght=700")
            }
        }
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
        set("background-opacity", Self.number(transparency.backgroundOpacity))
        set("cursor-style", settings.cursor.style.rawValue)
        set("cursor-style-blink", settings.cursor.blinks ? "true" : "false")
        set("window-padding-x", String(padding.horizontal))
        set("window-padding-y", String(padding.vertical))
        set("window-padding-balance", "true")

        // The line limit is the one users choose; the byte limit would otherwise cut in first.
        switch settings.scrollback {
        case .lines(let count): set("scrollback-limit-lines", String(count))
        case .unlimited: set("scrollback-limit-lines", "unlimited")
        }
        set("scrollback-limit-bytes", "unlimited")

        // Ghostty's own `xterm-ghostty` entry isn't on remote machines, and setuid programs (`top`,
        // anything under `sudo`) ignore the bundled one, so the terminal says it's xterm. Programs
        // still find truecolor (COLORTERM) and Ghostty's extensions by asking the terminal.
        set("term", "xterm-256color")
        lines.append(Self.embeddingOverrides)
        set("mouse-hide-while-typing", "true")
        set("desktop-notifications", "false")

        lines.append(contentsOf: Self.keybinds.map { "keybind = \($0)" })
        return lines.joined(separator: "\n") + "\n"
    }

    /// Read before the user's Ghostty config when "Use my Ghostty settings" is on: Native's choices
    /// where the user's config says nothing. The `xterm-ghostty` entry isn't on remote machines and
    /// setuid programs ignore the bundled one (see `text`), so Native says it's xterm unless the
    /// user's config sets `term`.
    public static let userConfigDefaults = """
        term = xterm-256color

        """

    /// Settings Native owns in every terminal, applied after the user's Ghostty config too
    /// (docs/terminal.md, "Using your Ghostty settings"): Native shows its own state when a shell
    /// exits or fails to start and keeps the tab until the user closes it, asks before closing a
    /// tab with a running process itself, and has no prompt for programs reading the clipboard
    /// (OSC 52), so they can copy but never read.
    public static let embeddingOverrides = """
        wait-after-command = true
        confirm-close-surface = true
        quit-after-last-window-closed = false
        clipboard-read = deny
        clipboard-write = allow

        """

    /// Applied after the user's Ghostty config: `embeddingOverrides`, and opaque when the system's
    /// Reduce Transparency is on, whatever the config's `background-opacity` says.
    public static func userConfigOverrides(_ transparency: TerminalTransparency) -> String {
        embeddingOverrides + (transparency.forcesOpaque ? "background-opacity = 1\n" : "")
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
