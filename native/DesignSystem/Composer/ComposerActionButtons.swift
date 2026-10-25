import SwiftUI

/// Sends the draft: a 24pt accent square with an up arrow (a chevron reads as "expand"). When sending
/// is blocked it stays in place, half transparent, and says why in its tooltip and accessibility
/// hint, so the composer's 24pt send/stop slot never shifts.
public struct ComposerSendButton: View {
    let disabledReason: String?
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnvironmentEnabled
    @State private var isHovered = false

    /// - Parameter disabledReason: Why sending is blocked right now ("Answer the permission
    ///   request first"); disables the button. Nil when sending is allowed.
    public init(disabledReason: String? = nil, action: @escaping () -> Void) {
        self.disabledReason = disabledReason
        self.action = action
    }

    private var isEnabled: Bool { isEnvironmentEnabled && disabledReason == nil }

    public var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.up")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.dsTextOnAccent)
                .frame(width: DS.Size.composerAction, height: DS.Size.composerAction)
                .dsHitTarget(DS.Size.composerAction)
        }
        .buttonStyle(ComposerActionStyle(kind: .send, isHovered: isHovered && isEnabled))
        .disabled(disabledReason != nil)
        .opacity(isEnabled ? 1 : 0.5)
        .accessibilityLabel("Send Message")
        .accessibilityHint(disabledReason ?? "")
        .trackHover($isHovered)
        // On the wrapper, so the tooltip still shows while the button is disabled.
        .help(isEnabled ? "Send (⏎)" : disabledReason ?? "Sending disabled")
    }
}

/// Stops the running turn: a 24pt foreground-colored square with an 8pt stop glyph. Binds Esc
/// unless `isEscapeEnabled` is false, for when something else in the composer needs it.
public struct ComposerStopButton: View {
    let isEscapeEnabled: Bool
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    public init(isEscapeEnabled: Bool = true, action: @escaping () -> Void) {
        self.isEscapeEnabled = isEscapeEnabled
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(.dsTextInverse)
                .frame(width: 8, height: 8)
                .frame(width: DS.Size.composerAction, height: DS.Size.composerAction)
                .dsHitTarget(DS.Size.composerAction)
        }
        .buttonStyle(ComposerActionStyle(kind: .stop, isHovered: isHovered && isEnabled))
        .keyboardShortcut(isEscapeEnabled ? .cancelAction : nil)
        .opacity(isEnabled ? 1 : 0.5)
        .help("Stop (Esc)")
        .accessibilityLabel("Stop Agent")
        .trackHover($isHovered)
    }
}

private struct ComposerActionStyle: ButtonStyle {
    enum Kind {
        case send, stop
    }

    let kind: Kind
    let isHovered: Bool

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
        configuration.label
            .background(fill(isPressed: configuration.isPressed), in: shape)
            .contentShape(shape)
            .dsFocusShape(shape)
    }

    private func fill(isPressed: Bool) -> Color {
        switch kind {
        case .send: isPressed ? .dsAccentPressed : isHovered ? .dsAccentHover : .dsAccent
        case .stop: isPressed || isHovered ? .dsTextSecondary : .dsTextPrimary
        }
    }
}

#Preview("Send and stop") {
    DSPreviewPair {
        HStack(spacing: DS.Space.md) {
            ComposerSendButton {}
            ComposerSendButton(disabledReason: "Answer the permission request first") {}
            ComposerStopButton(isEscapeEnabled: false) {}
        }
    }
}
