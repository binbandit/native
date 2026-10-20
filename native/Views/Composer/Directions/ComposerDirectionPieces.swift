#if DEBUG
import SwiftUI

/// Text that acts: tertiary at rest, primary under the pointer. The directions' quiet controls.
struct DirectionTextButtonStyle: ButtonStyle {
    var rest: Color = .dsTextTertiary

    func makeBody(configuration: Configuration) -> some View {
        DirectionTextButtonLabel(configuration: configuration, rest: rest)
    }
}

private struct DirectionTextButtonLabel: View {
    let configuration: ButtonStyleConfiguration
    let rest: Color
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .foregroundStyle(isHovered || configuration.isPressed ? .dsTextPrimary : rest)
            .contentShape(.rect)
            .dsHitTarget(DS.Size.controlXS)
            .trackHover($isHovered)
    }
}

/// One value among a setting's values, laid out in a row: the current one filled.
struct DirectionChoiceStyle: ButtonStyle {
    let isCurrent: Bool

    func makeBody(configuration: Configuration) -> some View {
        DirectionChoiceLabel(configuration: configuration, isCurrent: isCurrent)
    }
}

private struct DirectionChoiceLabel: View {
    let configuration: ButtonStyleConfiguration
    let isCurrent: Bool
    @State private var isHovered = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
        configuration.label
            .font(.dsBody)
            .lineLimit(1)
            .foregroundStyle(isCurrent || isHovered ? .dsTextPrimary : .dsTextSecondary)
            .padding(.horizontal, DS.Space.md)
            .frame(height: DS.Size.controlXS)
            .background(isCurrent ? Color.dsSelected : isHovered ? .dsHover : .clear, in: shape)
            .contentShape(shape)
            .dsHitTarget(DS.Size.controlXS)
            .trackHover($isHovered)
    }
}

/// A round send or stop button: the one primary action, in one place. Its glyph says what it does
/// with the draft: send (or steer into the running turn), or queue it for after the turn.
struct DirectionRoundButton: View {
    enum Kind {
        case send, queue, stop

        /// Send, or while the agent works, what Return does with a follow-up.
        static func send(followUp: FollowUpBehavior, isWorking: Bool, supportsSteering: Bool) -> Kind {
            isWorking && (followUp == .queue || !supportsSteering) ? .queue : .send
        }
    }

    let kind: Kind
    var isEnabled = true
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Group {
                switch kind {
                case .send, .queue:
                    Image(systemName: kind == .send ? "arrow.up" : "text.append")
                        .font(.dsCaptionMedium)
                        .foregroundStyle(.dsTextOnAccent)
                case .stop:
                    RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous)
                        .fill(.dsTextInverse)
                        .frame(width: DS.Space.md, height: DS.Space.md)
                }
            }
            .frame(width: DS.Size.composerAction, height: DS.Size.composerAction)
            .background(fill, in: .circle)
            .contentShape(.circle)
            .dsHitTarget(DS.Size.composerAction)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
        .trackHover($isHovered)
        .help(help)
        .accessibilityLabel(kind == .stop ? "Stop Agent" : "Send Message")
    }

    private var help: String {
        switch kind {
        case .send: "Send (↩)"
        case .queue: "Queue it for when the turn ends"
        case .stop: "Stop (Esc)"
        }
    }

    private var fill: Color {
        switch kind {
        case .send, .queue: isHovered ? .dsAccentHover : .dsAccent
        case .stop: isHovered ? .dsTextSecondary : .dsTextPrimary
        }
    }
}

/// A dot in the attention color: something waits on the user.
struct DirectionAttentionDot: View {
    var body: some View {
        Circle()
            .fill(.dsAttention)
            .frame(width: DS.Space.sm, height: DS.Space.sm)
            .accessibilityHidden(true)
    }
}

/// A hairline between a direction's sections.
struct DirectionRule: View {
    var body: some View {
        Rectangle()
            .fill(.dsSeparator)
            .frame(height: 1)
    }
}

extension String {
    /// A setting value's name without the agent's parenthetical ("GPT-6.1 Sol (fast)" reads "GPT-6.1 Sol").
    var directionShortName: String {
        let short = replacing(/\s*\(.*\)\s*$/, with: "")
        return short.isEmpty ? self : short
    }
}
#endif
