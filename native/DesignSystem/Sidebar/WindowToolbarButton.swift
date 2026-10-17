import SwiftUI

/// A 24pt square button for the window's toolbar row: the sidebar toggle, back and forward
/// (the reference app `WindowToolbarButton`: 4pt radius, secondary glyph, filled and primary on hover).
public struct WindowToolbarButton: View {
    let label: String
    let systemImage: String
    let isActive: Bool
    let shortcut: KeyboardShortcut?
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    public init(
        _ label: String,
        systemImage: String,
        isActive: Bool = false,
        shortcut: KeyboardShortcut? = nil,
        action: @escaping () -> Void
    ) {
        self.label = label
        self.systemImage = systemImage
        self.isActive = isActive
        self.shortcut = shortcut
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .regular))
                .frame(width: DS.Size.toolbarButton, height: DS.Size.toolbarButton)
                .contentShape(.rect)
        }
        .buttonStyle(WindowToolbarButtonStyle(isHovered: isHovered && isEnabled, isActive: isActive))
        .keyboardShortcut(shortcut)
        .help(shortcut.map { "\(label) (\($0.displayString))" } ?? label)
        .accessibilityLabel(label)
        .trackHover($isHovered)
    }
}

private struct WindowToolbarButtonStyle: ButtonStyle {
    let isHovered: Bool
    let isActive: Bool

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
        let isHighlighted = isHovered || isActive || configuration.isPressed
        configuration.label
            .foregroundStyle(isHighlighted ? .dsTextPrimary : .dsTextSecondary)
            .background(configuration.isPressed ? .dsPressed : isHighlighted ? .dsSelected : .clear, in: shape)
            .contentShape(.focusEffect, shape)
    }
}

/// Collapses or shows the sidebar, placed right after the traffic lights as the reference app does.
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

/// Back and forward through navigation history: the reference app's pair of chevrons after the update
/// button, bound to ⌘[ and ⌘].
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
            WindowToolbarButton("Back", systemImage: "chevron.left", shortcut: KeyboardShortcut("[", modifiers: .command), action: onBack)
                .disabled(!canGoBack)
            WindowToolbarButton("Forward", systemImage: "chevron.right", shortcut: KeyboardShortcut("]", modifiers: .command), action: onForward)
                .disabled(!canGoForward)
        }
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
