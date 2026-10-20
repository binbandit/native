import SwiftUI

/// A question with no fields to fill in: the agent's message, to continue past or skip.
struct AgentConfirmationRow: View {
    let message: String
    let onContinue: () -> Void
    let onSkip: () -> Void

    var body: some View {
        HStack(spacing: DS.Space.md) {
            Text(message)
                .font(.dsBody)
                .foregroundStyle(.dsTextPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Skip", action: onSkip)
                .buttonStyle(.ds(.ghost))
            Button("Continue", action: onContinue)
                .buttonStyle(.ds(.primary))
        }
        .padding(DS.Space.md)
    }
}

#if DEBUG
#Preview("Agent confirmation") {
    DSPreviewPair {
        VStack(spacing: DS.Space.xl) {
            ComposerSurface {
                AgentConfirmationRow(message: "Ready to apply the migration?", onContinue: {}, onSkip: {})
            }
            ComposerSurface {
                AgentConfirmationRow(
                    message:
                        "I'm about to rewrite the history of fix/composer-focus to drop the two debugging commits. Continue only if nobody else has pulled this branch.",
                    onContinue: {}, onSkip: {})
            }
        }
        .frame(width: 560)
    }
}
#endif
