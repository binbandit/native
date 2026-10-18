import NativeAutomation
import NativeExpeditions
import SwiftUI

/// Who's on the crew and what each is doing right now, grouped the way the user scans it: waiting
/// on you, working, then idle. The lead's message field sits at the bottom.
struct ExpeditionCrewPanel: View {
    let expedition: Expedition
    @Binding var selected: CrewSlot?
    let send: (ExpeditionEvent) -> Void

    @Environment(ExpeditionCenter.self) private var center
    @State private var message = ""
    @FocusState private var isMessageFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            SectionHeader("Crew")
            ForEach(members, id: \.slot) { member in
                memberRow(member)
            }
            if expedition.lead.task != nil, !expedition.phase.isOver {
                HStack(spacing: DS.Space.sm) {
                    TextField("Message \(expedition.crew.lead.name), the lead…", text: $message, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...4)
                        .focused($isMessageFocused)
                        .onSubmit(sendMessage)
                    Button("Send", systemImage: "arrow.up", action: sendMessage)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.ds(.primary))
                        .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.top, DS.Space.xs)
                // Focus Composer's key (⌘L unless remapped); here, the lead's field is the composer.
                .background {
                    Button("Message the Lead") { isMessageFocused = true }
                        .keyboardShortcut(CommandRegistry.shared.keyboardShortcut(for: .composerFocus))
                        .hidden()
                }
            }
        }
    }

    private struct Member {
        let slot: CrewSlot
        let agent: WorkflowAgent
        let status: WorkflowStepStatus
        let doing: String
    }

    /// The lead, the seat each builder is on (or was on last), and the reviewer's latest checkpoint.
    private var members: [Member] {
        var members = [
            Member(slot: .lead, agent: expedition.crew.lead, status: expedition.lead.status, doing: leadDoing)
        ]
        for builder in expedition.crew.builders {
            let runs = expedition.assignments.filter { $0.assignment.assignee == builder.id }
            let current =
                runs.first { $0.status.isActive || $0.status.isStopped } ?? runs.last { $0.status == .succeeded }
                ?? runs.first
            guard let current else { continue }
            members.append(
                Member(
                    slot: .assignment(current.id), agent: builder, status: current.status,
                    doing: current.assignment.title))
        }
        if let checkpoint = expedition.checkpoints.first(where: { $0.status != .waiting && !$0.status.isFinished })
            ?? expedition.checkpoints.last(where: { $0.status.isFinished && $0.status != .skipped })
        {
            members.append(
                Member(
                    slot: .checkpoint(checkpoint.leg), agent: expedition.crew.reviewer, status: checkpoint.status,
                    doing: expedition.title(of: .checkpoint(checkpoint.leg))))
        }
        return members.sorted { rank($0.status) < rank($1.status) }
    }

    private var leadDoing: String {
        let working = expedition.lead.status.isActive
        return switch expedition.lead.job {
        case .planning: working ? "Planning the route" : "Proposed the route"
        case .revising: working ? "Revising the route" : "Revised the route"
        case .reviewingLeg: working ? "Looking at the legs ahead" : "Standing by"
        case .debriefing: working ? "Writing the debrief" : "Wrote the debrief"
        case .conversation: working ? "Answering you" : "Standing by"
        }
    }

    private func rank(_ status: WorkflowStepStatus) -> Int {
        if status.isStopped { return 0 }
        if status.isActive { return 1 }
        return 2
    }

    private func memberRow(_ member: Member) -> some View {
        Button {
            selected = member.slot
        } label: {
            HStack(alignment: .top, spacing: DS.Space.md) {
                StatusIndicator(status: member.status.expeditionTaskStatus)
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    HStack(spacing: DS.Space.xs) {
                        Text(member.agent.name)
                            .font(.dsBodyMedium)
                            .foregroundStyle(.dsTextPrimary)
                        Text(expedition.role(of: member.slot))
                            .font(.dsCaption)
                            .foregroundStyle(.dsTextTertiary)
                    }
                    Text(activity(member))
                        .font(.dsCaption)
                        .foregroundStyle(.dsTextSecondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(DS.Space.sm)
            .background(selected == member.slot ? .dsSelected : .clear, in: .rect(cornerRadius: DS.Radius.row))
            .contentShape(.rect)
        }
        .buttonStyle(SidebarRowButtonStyle())
        .accessibilityElement(children: .combine)
    }

    /// What the member is doing this moment: its session's own activity line while it works,
    /// never just "Working…".
    private func activity(_ member: Member) -> String {
        if member.status.isActive, let task = expedition.task(of: member.slot),
            let session = center.host?.session(for: task),
            let line = GoalMarker.stripping(session.state.latestReply ?? "").split(whereSeparator: \.isNewline).last
                .map(String.init),
            !line.isEmpty
        {
            return "\(member.doing): \(line)"
        }
        // The glyph already says done or waiting; only a stop needs saying.
        return member.status.isStopped ? "\(member.doing) · \(member.status.label)" : member.doing
    }

    private func sendMessage() {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        send(.messageLead(text))
        message = ""
    }
}
