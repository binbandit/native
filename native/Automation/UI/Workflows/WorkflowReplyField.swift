import SwiftUI

/// Answers a step that stopped to ask something, in its own session: the reply goes to the step's
/// agent and the step picks back up.
struct WorkflowReplyField: View {
    let agentName: String
    let onSend: (String) -> Void

    @State private var text = ""

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: DS.Space.md) {
            TextField("Reply", text: $text, prompt: Text("Reply to \(agentName)…").foregroundStyle(.dsTextQuaternary), axis: .vertical)
                .lineLimit(1...6)
                .automationField()
                .labelsHidden()
                .onSubmit(send)
            Button("Send", systemImage: "arrow.up", action: send)
                .buttonStyle(.ds(.primary, size: .medium))
                .disabled(!canSend)
        }
    }

    private func send() {
        guard canSend else { return }
        onSend(text)
        text = ""
    }
}
