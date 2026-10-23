import SwiftUI

/// A keyboard shortcut hint: Geist Mono 10pt in a 1pt-outlined, 2pt-rounded cap.
public struct Kbd: View {
    let keys: String
    var compact = false

    public init(_ keys: String, compact: Bool = false) {
        self.keys = keys
        self.compact = compact
    }

    public init(_ shortcut: KeyboardShortcut) {
        keys = shortcut.displayString
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
                            ? .system(size: 10, weight: .medium) : compact ? DS.Sidebar.keycapFont : .dsMonoMicro)
            }
        }
        .tracking(DS.Tracking.tight)
        .foregroundStyle(.dsTextSecondary)
        .padding(.horizontal, compact ? DS.Space.xs : DS.Space.sm)
        .padding(.vertical, compact ? 0 : DS.Space.xxs)
        .frame(minHeight: compact ? DS.Sidebar.keycapHeight : 17)
        .background(.dsSurface, in: shape)
        .overlay { shape.strokeBorder(.dsBorderInner, lineWidth: 1) }
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

#Preview("Keyboard hints") {
    DSPreviewPair {
        HStack(spacing: DS.Space.md) {
            Kbd("⌘K")
            Kbd(KeyboardShortcut("n", modifiers: [.command, .shift]))
            Kbd("Esc")
            Kbd("⇧⇥")
        }
    }
}
