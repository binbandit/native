import NativeAutomation
import NativeExpeditions
import SwiftUI

/// The selected seat beside the expedition: who's on it and where it stands, what can be done about
/// it, a field to steer or answer it, and its session's transcript.
struct ExpeditionInspector<Transcript: View>: View {
    let expedition: Expedition
    let slot: CrewSlot
    let send: (ExpeditionEvent) -> Void
    @ViewBuilder let transcript: (SessionModel) -> Transcript

    @Environment(ExpeditionCenter.self) private var center
    @State private var message = ""
    @State private var session: SessionModel?
    @State private var openError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(DS.Space.lg)
            SeparatorLine()
            Group {
                if let session {
                    transcript(session)
                } else if let openError {
                    ErrorState("Couldn't open the session", suggestion: openError, layout: .pane)
                } else if expedition.task(of: slot) == nil {
                    EmptyStateView("Not Started", systemImage: "circle.dashed", message: "This seat gets its session when its turn comes.") {
                        EmptyView()
                    }
                } else {
                    DotGridLoader(pattern: .typing)
                        .foregroundStyle(.dsTextTertiary)
                        .frame(width: DS.Size.statusGlyph, height: DS.Size.statusGlyph)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxHeight: .infinity)
            if expedition.task(of: slot) != nil, !expedition.phase.isOver {
                SeparatorLine()
                messageField
                    .padding(DS.Space.md)
            }
        }
        .background(.dsBackground)
        .task(id: expedition.task(of: slot)) { await openSession() }
    }

    private var status: WorkflowStepStatus {
        expedition.status(of: slot) ?? .waiting
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            HStack(spacing: DS.Space.sm) {
                StatusIndicator(status: status.expeditionTaskStatus)
                Text(expedition.title(of: slot))
                    .font(.dsBodyMedium)
                    .foregroundStyle(.dsTextPrimary)
                    .lineLimit(2)
            }
            Text("\(expedition.agent(of: slot).name) · \(expedition.role(of: slot)) · \(status.label)")
                .font(.dsCaption)
                .foregroundStyle(.dsTextTertiary)
            if let reason = status.reason {
                Text(reason)
                    .font(.dsCaption)
                    .foregroundStyle(.dsTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            actions
        }
    }

    @ViewBuilder private var actions: some View {
        HStack(spacing: DS.Space.sm) {
            if status == .running {
                Button("Stop Turn", systemImage: "stop.fill") { send(.stopSlot(slot)) }
                    .buttonStyle(.ds(.secondary))
            }
            if status.isStopped {
                Button(status == .interrupted ? "Resume" : "Retry") { send(status == .interrupted ? .resumeSlot(slot) : .retry(slot)) }
                    .buttonStyle(.ds(.primary))
            }
            if case .assignment(let id) = slot, !status.isActive, !status.isFinished {
                Menu("Reassign") {
                    ForEach(center.host?.expeditionAgents ?? []) { agent in
                        Button(agent.name) { send(.reassign(id, agent: agent)) }
                    }
                }
                .menuStyle(.button)
                .buttonStyle(.ds(.ghost))
                .fixedSize()
                .help("Move this assignment to another agent")
            }
        }
    }

    private var messageField: some View {
        HStack(spacing: DS.Space.sm) {
            TextField(status.isActive ? "Steer \(expedition.agent(of: slot).name)…" : "Message \(expedition.agent(of: slot).name)…", text: $message, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...5)
                .onSubmit(sendMessage)
            Button("Send", systemImage: "arrow.up", action: sendMessage)
                .labelStyle(.iconOnly)
                .buttonStyle(.ds(.primary))
                .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help(status.isActive ? "Steered into the running turn where the agent supports it, queued otherwise" : "Sent as its next prompt")
        }
    }

    private func sendMessage() {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        send(slot == .lead ? .messageLead(text) : .message(slot, text: text))
        message = ""
    }

    /// The seat's session, reopened from the agent if it didn't survive a restart.
    private func openSession() async {
        openError = nil
        guard let task = expedition.task(of: slot), let host = center.host else {
            session = nil
            return
        }
        if let open = host.session(for: task) {
            session = open
            return
        }
        do {
            session = try await host.liveSession(for: task)
        } catch {
            session = nil
            openError = error.localizedDescription
        }
    }
}
