import SwiftUI

/// A 24pt square glyph button for the window's title-bar row: the sidebar toggle, back and
/// forward. Conductor's ghost style: a muted glyph that brightens on hover, with no fill, so it
/// sits in a macOS toolbar without competing with the system's own button treatment (put it in a
/// `ToolbarItem` with `.sharedBackgroundVisibility(.hidden)`). The tooltip shows the shortcut.
public struct WindowToolbarButton: View {
    let label: String
    let systemImage: String
    let glyphSize: CGFloat
    let isActive: Bool
    let shortcut: KeyboardShortcut?
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    /// - Parameters:
    ///   - glyphSize: The symbol's point size; 13 for panel toggles, 12 for arrows (Conductor
    ///     `size-4` and `size-3`).
    ///   - isActive: Keeps the glyph bright, for a toggle that is on.
    public init(
        _ label: String,
        systemImage: String,
        glyphSize: CGFloat = 13,
        isActive: Bool = false,
        shortcut: KeyboardShortcut? = nil,
        action: @escaping () -> Void
    ) {
        self.label = label
        self.systemImage = systemImage
        self.glyphSize = glyphSize
        self.isActive = isActive
        self.shortcut = shortcut
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: glyphSize, weight: .regular))
                .frame(width: DS.Size.toolbarButton, height: DS.Size.toolbarButton)
                .contentShape(.rect)
                .dsHitTarget(DS.Size.toolbarButton)
        }
        .buttonStyle(WindowToolbarButtonStyle(isHovered: isHovered && isEnabled, isActive: isActive))
        .opacity(isEnabled ? 1 : 0.4)
        .keyboardShortcut(shortcut)
        .help(shortcut.map { "\(label) \($0.displayString)" } ?? label)
        .accessibilityLabel(label)
        .trackHover($isHovered)
    }
}

private struct WindowToolbarButtonStyle: ButtonStyle {
    let isHovered: Bool
    let isActive: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isHovered || isActive ? .dsTextPrimary : .dsTextSecondary)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .dsFocusShape(RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
    }
}

/// Collapses or shows the sidebar, placed right after the traffic lights as Factory does.
public struct SidebarCollapseButton: View {
    let isExpanded: Bool
    let shortcut: KeyboardShortcut?
    let action: () -> Void

    public init(isExpanded: Bool, shortcut: KeyboardShortcut? = nil, action: @escaping () -> Void) {
        self.isExpanded = isExpanded
        self.shortcut = shortcut
        self.action = action
    }

    public var body: some View {
        WindowToolbarButton(
            isExpanded ? "Collapse Sidebar" : "Show Sidebar",
            systemImage: "sidebar.left",
            shortcut: shortcut,
            action: action
        )
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
    }
}

/// Back and forward through navigation history, bound to ⌘[ and ⌘]: Conductor's pair of 12pt
/// arrows at the sidebar header's trailing edge.
public struct HistoryNavigationButtons: View {
    let canGoBack: Bool
    let canGoForward: Bool
    let onBack: () -> Void
    let onForward: () -> Void

    public init(canGoBack: Bool, canGoForward: Bool, onBack: @escaping () -> Void, onForward: @escaping () -> Void) {
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
        self.onBack = onBack
        self.onForward = onForward
    }

    public var body: some View {
        HStack(spacing: DS.Space.xxs) {
            WindowToolbarButton(
                "Go back",
                systemImage: "arrow.left",
                glyphSize: 12,
                shortcut: KeyboardShortcut("[", modifiers: .command),
                action: onBack
            )
            .disabled(!canGoBack)
            WindowToolbarButton(
                "Go forward",
                systemImage: "arrow.right",
                glyphSize: 12,
                shortcut: KeyboardShortcut("]", modifiers: .command),
                action: onForward
            )
            .disabled(!canGoForward)
        }
        // In a toolbar item the pair reads as one group; its own label keeps the item from
        // borrowing the first button's, which VoiceOver then gave to both buttons.
        .accessibilityElement(children: .contain)
        .accessibilityLabel("History")
    }
}

#Preview("Window toolbar") {
    DSPreviewPair {
        HStack(spacing: DS.Space.xs) {
            SidebarCollapseButton(isExpanded: true) {}
            UpdateButton(version: "1.4.0") {}
                .padding(.horizontal, DS.Space.xs)
            HistoryNavigationButtons(canGoBack: true, canGoForward: false, onBack: {}, onForward: {})
        }
    }
}
