import SwiftUI

/// Sends the draft: a 24pt accent square with a chevron (Factory `ChatSubmitButton`), half
/// transparent while disabled.
public struct ComposerSendButton: View {
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    public init(action: @escaping () -> Void) {
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.up")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.dsTextOnAccent)
                .frame(width: DS.Size.composerAction, height: DS.Size.composerAction)
                .dsHitTarget(DS.Size.composerAction)
        }
        .buttonStyle(ComposerActionStyle(kind: .send, isHovered: isHovered && isEnabled))
        .opacity(isEnabled ? 1 : 0.5)
        .help(isEnabled ? "Send (⏎)" : "Sending disabled")
        .accessibilityLabel("Send Message")
        .trackHover($isHovered)
    }
}

/// Stops the running turn: a 24pt foreground-colored square with an 8pt stop glyph (Factory v2
/// `ChatStopButton`). Binds Esc unless `isEscapeEnabled` is false, for when something else in the
/// composer needs it.
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
            .contentShape(.focusEffect, shape)
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
            ComposerSendButton {}.disabled(true)
            ComposerStopButton(isEscapeEnabled: false) {}
        }
    }
}
