import SwiftUI

struct TaskPeekFailureView: View {
    let session: SessionModel
    let recover: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            Text("\(session.agentName) stopped").font(.dsCalloutMedium).foregroundStyle(.dsTextPrimary)
            Text(detail).font(.dsBody).foregroundStyle(.dsTextSecondary)
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            Text(
                session.phase == .disconnected
                    ? "Your conversation is kept. Restart the agent to continue."
                    : "Your conversation is kept. Continue asks the agent to pick up where it left off."
            )
            .font(.dsBody).foregroundStyle(.dsTextTertiary)
            HStack {
                Spacer()
                Button(session.phase == .disconnected ? "Restart Agent" : "Continue Task") {
                    recover()
                }
                .buttonStyle(.ds(.primary))
            }
        }
    }

    private var detail: String {
        session.state.items.reversed().compactMap { item -> String? in
            guard case .notice(let notice) = item, notice.isError else { return nil }
            return notice.text
        }.first ?? "The agent couldn't finish this turn."
    }
}

#if DEBUG
#Preview("Peek failure") { TaskPeekPreviewFixtures.view(.failure) }
#endif
