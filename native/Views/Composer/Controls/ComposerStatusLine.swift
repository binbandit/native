import SwiftUI

/// The controls row's trailing note: what the last action did, else why sending is blocked, else
/// what Return does while the agent works.
struct ComposerStatusLine: View {
    let feedback: ComposerFeedback?
    let blocker: SendBlocker?
    let followUpHint: FollowUpHint?
    let onUndo: () -> Void

    var body: some View {
        Group {
            if let feedback {
                HStack(spacing: DS.Space.sm) {
                    Image(systemName: symbol(for: feedback.tone))
                        .foregroundStyle(color(for: feedback.tone))
                    Text(feedback.message)
                        .foregroundStyle(.dsTextSecondary)
                    if feedback.canUndo {
                        Button("Undo", action: onUndo)
                            .buttonStyle(.plain)
                            .foregroundStyle(.dsAccentText)
                            .help("Undo (⌘Z)")
                    }
                }
                .id(feedback.id)
                .accessibilityElement(children: .combine)
            } else if let blocker {
                Label(blocker.message, systemImage: "exclamationmark.circle")
                    .foregroundStyle(.dsTextSecondary)
            } else if let followUpHint {
                Text(followUpHint.text)
                    .foregroundStyle(.dsTextTertiary)
                    .help(followUpHint.help)
            }
        }
        .font(.dsBody)
        .lineLimit(1)
        .truncationMode(.tail)
        .transition(.opacity)
        .animation(.dsQuick, value: feedback)
    }

    private func symbol(for tone: ComposerFeedback.Tone) -> String {
        switch tone {
        case .done: "checkmark.circle"
        case .notice: "info.circle"
        case .problem: "exclamationmark.circle"
        }
    }

    private func color(for tone: ComposerFeedback.Tone) -> Color {
        switch tone {
        case .done: .dsSuccess
        case .notice: .dsTextSecondary
        case .problem: .dsWarning
        }
    }
}
