import SwiftUI

/// A keyboard shortcut hint: Geist Mono 10pt, in a keycap or plain beside an action.
public struct Kbd: View {
    public enum Style: Sendable { case keycap, plain }

    let keys: String
    let style: Style
    var compact = false

    public init(_ keys: String, compact: Bool = false, style: Style = .keycap) {
        self.keys = keys
        self.style = style
        self.compact = compact
    }

    public init(_ shortcut: KeyboardShortcut, compact: Bool = false) {
        keys = shortcut.displayString
        style = .keycap
        self.compact = compact
    }

    public var body: some View {
        let shape = RoundedRectangle(
            cornerRadius: compact ? DS.Sidebar.keycapRadius : DS.Radius.small, style: .continuous)
        HStack(spacing: 1) {
            // Geist Mono has no modifier glyphs, so those come from the system font.
            ForEach(Array(keys.enumerated()), id: \.offset) { _, character in
                Text(String(character))
                    .font(
                        Self.symbols.contains(character)
                            ? .system(size: 10, weight: style == .plain ? .regular : .medium)
                            : compact && style == .keycap ? DS.Sidebar.keycapFont : .dsMonoMicro)
            }
        }
        .tracking(DS.Tracking.tight)
        .foregroundStyle(style == .plain ? .dsTextTertiary : .dsTextSecondary)
        .padding(.horizontal, style == .plain ? 0 : compact ? DS.Space.xs : DS.Space.sm)
        .padding(.vertical, style == .plain || compact ? 0 : DS.Space.xxs)
        .frame(minHeight: style == .plain ? nil : compact ? DS.Sidebar.keycapHeight : 17)
        .background(style == .plain ? .clear : .dsSurface, in: shape)
        .overlay { if style == .keycap { shape.strokeBorder(.dsBorderInner, lineWidth: 1) } }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Shortcut \(keys)")
    }

    private static let symbols: Set<Character> = ["⌘", "⇧", "⌥", "⌃", "⏎", "↩", "⇥", "⌫", "⌦", "⎋", "↑", "↓", "←", "→"]
}

extension KeyboardShortcut {
    /// The shortcut as menus print it, e.g. "⇧⌘N".
    public var displayString: String {
        var result = ""
        if modifiers.contains(.control) { result += "⌃" }
        if modifiers.contains(.option) { result += "⌥" }
        if modifiers.contains(.shift) { result += "⇧" }
        if modifiers.contains(.command) { result += "⌘" }
        return result + key.displayString
    }
}

extension KeyEquivalent {
    /// The key as menus print it.
    public var displayString: String {
        switch self {
        case .return: "↩"
        case .escape: "⎋"
        case .delete: "⌫"
        case .deleteForward: "⌦"
        case .tab: "⇥"
        case .space: "Space"
        case .upArrow: "↑"
        case .downArrow: "↓"
        case .leftArrow: "←"
        case .rightArrow: "→"
        default: String(character).uppercased()
        }
    }
}

#if DEBUG
#Preview("Keyboard hints") {
    DSPreviewPair {
        HStack(spacing: DS.Space.md) {
            Kbd("⌘K")
            Kbd("⌘Z", style: .plain)
            Kbd(KeyboardShortcut("n", modifiers: [.command, .shift]))
            Kbd("Esc")
            Kbd("⇧⇥")
        }
    }
}
#endif
