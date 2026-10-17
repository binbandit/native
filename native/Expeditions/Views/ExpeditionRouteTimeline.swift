#if EXPEDITIONS_WIP
import NativeAutomation
import NativeExpeditions
import SwiftUI

/// The route as it's being worked: each leg, its assignments and fix rounds, and its checkpoint,
/// with who's on each and what it has taken.
struct ExpeditionRouteTimeline: View {
    let expedition: Expedition
    @Binding var selected: CrewSlot?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            SectionHeader("Route")
            ForEach(Array((expedition.route?.legs ?? []).enumerated()), id: \.element.id) { index, leg in
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    HStack(spacing: DS.Space.sm) {
                        Text("Leg \(index + 1)")
                            .font(.dsMonoCaption)
                            .foregroundStyle(.dsTextTertiary)
                        Text(leg.title)
                            .font(.dsBodyMedium)
                            .foregroundStyle(.dsTextPrimary)
                        Spacer()
                        if let checkpoint = expedition.checkpoint(leg.id), checkpoint.status.isFinished {
                            Badge(checkpoint.status == .skipped ? "Skipped" : "Passed", tone: checkpoint.status == .skipped ? .neutral : .success, style: .soft)
                        }
                    }
                    Text(leg.outcome)
                        .font(.dsCaption)
                        .foregroundStyle(.dsTextSecondary)
                        .padding(.bottom, DS.Space.xs)
                    ForEach(expedition.assignments(in: leg.id)) { run in
                        ExpeditionSeatRow(
                            expedition: expedition, slot: .assignment(run.id), status: run.status,
                            title: run.assignment.title, agent: expedition.agent(of: .assignment(run.id)),
                            started: run.startedAt, ended: run.endedAt, cost: run.cost, isIndented: run.isFix,
                            isSelected: selected == .assignment(run.id)
                        ) { selected = .assignment(run.id) }
                    }
                    if let checkpoint = expedition.checkpoint(leg.id) {
                        ExpeditionSeatRow(
                            expedition: expedition, slot: .checkpoint(leg.id), status: checkpoint.status,
                            title: checkpoint.rounds > 0 ? "Checkpoint · round \(checkpoint.rounds)" : "Checkpoint",
                            agent: expedition.crew.reviewer, started: checkpoint.startedAt, ended: checkpoint.endedAt,
                            cost: checkpoint.sessionCost, isIndented: false, isSelected: selected == .checkpoint(leg.id)
                        ) { selected = .checkpoint(leg.id) }
                    }
                }
            }
        }
    }
}

/// One seat's row: status, title, agent, time and cost. Selecting it opens its session.
struct ExpeditionSeatRow: View {
    let expedition: Expedition
    let slot: CrewSlot
    let status: WorkflowStepStatus
    let title: String
    let agent: WorkflowAgent
    let started: Date?
    let ended: Date?
    let cost: Double?
    let isIndented: Bool
    let isSelected: Bool
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: DS.Space.md) {
                StatusIndicator(status: status.expeditionTaskStatus)
                Text(title)
                    .font(.dsBody)
                    .foregroundStyle(status == .waiting || status == .skipped ? .dsTextTertiary : .dsTextPrimary)
                    .strikethrough(status == .skipped)
                    .lineLimit(1)
                Spacer(minLength: DS.Space.md)
                Label(agent.name, systemImage: agent.symbol)
                    .font(.dsCaption)
                    .foregroundStyle(.dsTextTertiary)
                    .lineLimit(1)
                if let started {
                    if status.isActive {
                        ElapsedTimeText(since: started)
                            .font(.dsMonoCaption)
                            .foregroundStyle(.dsTextTertiary)
                    } else if let ended {
                        Text(DSFormat.duration(ended.timeIntervalSince(started)))
                            .font(.dsMonoCaption)
                            .foregroundStyle(.dsTextTertiary)
                    }
                }
                if let cost {
                    Text(DSFormat.cost(cost))
                        .font(.dsMonoCaption)
                        .foregroundStyle(.dsTextTertiary)
                }
            }
            .padding(.leading, isIndented ? DS.Space.xl : 0)
            .padding(.horizontal, DS.Space.sm)
            .frame(minHeight: DS.Size.rowMinHeight)
            .background(isSelected ? .dsSelected : .clear, in: .rect(cornerRadius: DS.Radius.row))
            .contentShape(.rect)
        }
        .buttonStyle(SidebarRowButtonStyle())
        .help(status.reason ?? status.label)
        .accessibilityElement(children: .combine)
        .accessibilityValue(status.label)
    }
}
#endif
