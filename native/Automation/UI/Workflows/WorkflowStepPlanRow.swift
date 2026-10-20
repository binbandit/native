import NativeAutomation
import SwiftUI

/// A step as the picker plans it, before anything runs: its order, what it waits for, the agent it
/// gets (which the user can change), and whether it's a goal or has a gate.
struct WorkflowStepPlanRow: View {
    let index: Int
    let step: WorkflowStep
    let definition: WorkflowDefinition
    let assignment: WorkflowAssignment?
    let agents: [WorkflowAgent]
    let onChoose: (WorkflowAgent.ID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            HStack(spacing: DS.Space.md) {
                Text("\(index + 1)")
                    .font(.dsMonoMicro)
                    .foregroundStyle(.dsTextSecondary)
                    .frame(width: DS.Size.rowLeading, height: DS.Size.rowLeading)
                    .overlay { Circle().strokeBorder(.dsBorderInner, lineWidth: 1) }
                Text(step.title)
                    .font(.dsBodyMedium)
                    .foregroundStyle(.dsTextPrimary)
                if let ordering {
                    Text(ordering)
                        .font(.dsCaption)
                        .foregroundStyle(.dsTextTertiary)
                }
                Spacer(minLength: DS.Space.md)
                if let budget = step.goal {
                    Badge(
                        "Goal · \(budget.maxIterations.map { "\($0) turns" } ?? "no limit")", tone: .accent,
                        style: .soft)
                }
                if step.approval != nil {
                    Badge("Approval")
                }
                agentControl
            }
            .tracking(DS.Tracking.tight)
            .frame(minHeight: DS.Size.composerPill)
            if let note = assignment?.note {
                Label(note, systemImage: "info.circle")
                    .font(.dsCaption)
                    .foregroundStyle(.dsWarning)
                    .padding(.leading, DS.Size.rowLeading + DS.Space.md)
            }
        }
    }

    @ViewBuilder private var agentControl: some View {
        if let runner = step.kind.runnerLabel {
            Label(runner.title, systemImage: runner.systemImage)
                .font(.dsBody)
                .foregroundStyle(.dsTextSecondary)
                .pillChrome()
        } else if let continued = step.continues.flatMap(definition.step) {
            Label(
                "\(assignment?.agent?.name ?? "Same agent") · \(continued.title)'s session",
                systemImage: "arrow.turn.down.right"
            )
            .font(.dsBody)
            .foregroundStyle(.dsTextSecondary)
            .pillChrome()
            .help("Continues in \(continued.title)'s session, so the agent keeps its context")
        } else {
            PillMenu(assignment?.agent?.name ?? "No agent", systemImage: assignment?.agent?.symbol) {
                ForEach(agents) { agent in
                    Button(agent.name, systemImage: agent.symbol) { onChoose(agent.id) }
                }
            }
            .help("Choose the agent for this step")
        }
    }

    /// When the step runs, if that isn't simply after the one before it.
    private var ordering: String? {
        let dependencies = definition.dependencies(of: step)
        guard let position = definition.steps.firstIndex(where: { $0.id == step.id }) else { return nil }
        let previous = position > 0 ? [definition.steps[position - 1].id] : []
        if dependencies == previous { return nil }
        if dependencies.isEmpty { return "starts right away" }
        let titles = dependencies.compactMap { definition.step($0)?.title }
        return "after \(titles.formatted(.list(type: .and)))"
    }
}

#if NATIVE_PREVIEWS_WIP
#Preview("Step plan rows") {
    DSPreviewPair {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            if let definition = AutomationPreviewFixtures.definition {
                let assignments = AutomationPreviewFixtures.assignments(for: definition)
                ForEach(Array(definition.steps.enumerated()), id: \.element.id) { index, step in
                    WorkflowStepPlanRow(
                        index: index, step: step, definition: definition, assignment: assignments[step.id],
                        agents: AutomationPreviewFixtures.agents, onChoose: { _ in })
                }
            }
        }
        .frame(width: 560)
    }
}
#endif
