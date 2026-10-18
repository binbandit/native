import NativeHostProtocol
import SwiftUI

/// Sending to a task: a message while it's idle, or queue / steer while it works (the same choice
/// as the Mac's Return and ⌘Return). Text leaves the field only once it's accepted; a message that
/// couldn't be sent comes back into the draft, marked "Not sent".
struct CompanionComposer: View {
    let host: HostConnection
    let session: HostSessionSummary

    @State private var draft = ""
    @State private var behavior = PromptBehavior.queue
    @State private var notSent: String?
    @State private var isSending = false
    @State private var delivered: String?
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            if let notSent {
                Label("Not sent: \(notSent)", systemImage: "exclamationmark.circle")
                    .font(CompanionType.caption)
                    .foregroundStyle(.dsDanger)
                    .accessibilityIdentifier("notSent")
            } else if let delivered {
                Text(delivered)
                    .font(CompanionType.caption)
                    .foregroundStyle(.dsTextSecondary)
            }
            if session.isWorking {
                Picker("When", selection: $behavior) {
                    Text("Queue").tag(PromptBehavior.queue)
                    Text("Steer").tag(PromptBehavior.steer)
                }
                .pickerStyle(.segmented)
                .disabled(!session.supportsSteering)
                Text(hint)
                    .font(CompanionType.caption)
                    .foregroundStyle(.dsTextTertiary)
            }
            HStack(alignment: .bottom, spacing: DS.Space.md) {
                TextField(placeholder, text: $draft, axis: .vertical)
                    .font(CompanionType.body)
                    .lineLimit(1...CompanionMetrics.composerMaxLines)
                    .focused($isFocused)
                    .padding(.vertical, DS.Space.md)
                    .accessibilityIdentifier("composer")
                Button {
                    send()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(CompanionType.bodyMedium)
                        .frame(width: DS.Size.minimumHitTarget, height: DS.Size.minimumHitTarget)
                }
                .buttonStyle(.ds(.primary, size: .large))
                .clipShape(.circle)
                .disabled(trimmed.isEmpty || isSending || !host.phase.isConnected)
                .accessibilityLabel(session.isWorking ? (behavior == .steer ? "Steer" : "Queue") : "Send")
                .accessibilityIdentifier("send")
            }
            .padding(.horizontal, DS.Space.lg)
            .padding(.vertical, DS.Space.xs)
            .glassEffect(.regular, in: .rect(cornerRadius: DS.Radius.panel * 2))
        }
        .padding(.horizontal, DS.Space.lg)
        .padding(.bottom, DS.Space.sm)
    }

    private var trimmed: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var placeholder: String {
        host.phase.isConnected ? "Message \(session.agentName)" : "\(host.name) isn't connected"
    }

    private var hint: String {
        guard session.supportsSteering else { return "Queues until this turn ends. \(session.agentName) can't take messages mid-turn." }
        return behavior == .steer ? "Joins the running turn." : "Queues until this turn ends."
    }

    private func send() {
        let text = trimmed
        guard !text.isEmpty else { return }
        draft = ""
        notSent = nil
        delivered = nil
        isSending = true
        Task {
            let outcome = await host.send(text, to: session.id, behavior: session.isWorking ? behavior : .queue)
            isSending = false
            switch outcome {
            case .delivered(let delivery):
                delivered = switch delivery {
                case .queued: "Queued. It goes out when this turn ends."
                case .steered: "Joined the running turn."
                case .prompted, .unknown: nil
                }
            case .notSent(let reason):
                // Back into the draft, ahead of anything typed meanwhile.
                draft = draft.isEmpty ? text : "\(text)\n\(draft)"
                notSent = reason
                isFocused = true
            }
        }
    }
}
