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
