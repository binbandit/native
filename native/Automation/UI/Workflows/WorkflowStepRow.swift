import SwiftUI

/// One step in a run's timeline, after the reference app's mission feature rows: status glyph, title, the
/// agent it runs on, and a line saying what it's doing or why it stopped, with the ways on below.
/// Its gate, or a reply box when it's asking something, opens right under it.
struct WorkflowStepRow: View {
    let step: WorkflowStepRun
    let run: WorkflowRun
    /// The step's session as it is now, while it has one.
    let report: WorkflowTaskReport?
    var isSelected = false
    var answersShortcuts = false
    let send: (WorkflowEvent) -> Void
    let onOpen: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.md) {
            AutomationStatusGlyph(glyph: AutomationGlyph(step: step.status, needsApproval: report?.needsApproval == true))
                .padding(.top, DS.Space.xxs)
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                header
                if let detail {
                    Text(detail)
                        .font(.dsCaption)
                        .tracking(DS.Tracking.tight)
                        .foregroundStyle(detailColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
                preview
                if step.status == .awaitingApproval {
                    WorkflowApprovalCard(
                        step: step,
                        answersShortcuts: answersShortcuts,
                        onApprove: { send(.approve(step: step.id, prompt: $0)) },
                        onSkip: { send(.skip(step: step.id)) },
                        onReject: { send(.reject(step: step.id)) }
                    )
                }
                if case .blocked = step.status {
                    WorkflowReplyField(agentName: step.assignment.agent?.name ?? "the agent") { send(.reply(step: step.id, text: $0)) }
                }
                actions
            }
        }
        .padding(DS.Space.md)
        .background(isSelected ? Color.dsSelected : .clear, in: .rect(cornerRadius: DS.Radius.card))
        .contentShape(.rect)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(step.step.title), \(step.status.label)")
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Space.md) {
            Text(step.step.title)
                .font(.dsCalloutMedium)
                .foregroundStyle(step.status == .skipped ? .dsTextTertiary : .dsTextPrimary)
                .strikethrough(step.status == .skipped, color: .dsTextTertiary)
            agentLabel
            if let budget = step.step.goal {
                Badge("Goal · \(budget.maxIterations.map { "\($0) turns" } ?? "no limit")", tone: .accent, style: .soft)
            }
            Spacer(minLength: DS.Space.md)
            Text(step.status.label)
                .font(.dsCaptionMedium)
                .foregroundStyle(AutomationGlyph(step: step.status, needsApproval: report?.needsApproval == true).tint)
            metrics
        }
        .tracking(DS.Tracking.tight)
        .lineLimit(1)
    }

    @ViewBuilder private var agentLabel: some View {
        if step.step.kind == .pullRequest {
            Label("GitHub", systemImage: "arrow.triangle.pull")
                .font(.dsCaption)
                .foregroundStyle(.dsTextTertiary)
        } else if let agent = step.assignment.agent {
            Label(step.step.continues.flatMap(run.stepRun).map { "\(agent.name) · in \($0.step.title)'s session" } ?? agent.name, systemImage: agent.symbol)
                .font(.dsCaption)
                .foregroundStyle(.dsTextTertiary)
        }
    }

    @ViewBuilder private var metrics: some View {
        let parts = [duration, step.cost.map(GoalUsage.costText)].compactMap(\.self)
        if !parts.isEmpty {
            Text(parts.joined(separator: " · "))
                .font(.dsMonoCaption)
                .monospacedDigit()
                .foregroundStyle(.dsTextTertiary)
        }
    }

    private var duration: String? {
        guard let start = step.startedAt, let end = step.endedAt else { return nil }
        return GoalUsage.durationText(end.timeIntervalSince(start))
    }

    // MARK: - What it's doing

    private var detail: String? {
        let agent = step.assignment.agent?.name ?? "The agent"
        switch step.status {
        case .waiting:
            let waitingFor = run.definition.dependencies(of: step.step).compactMap { run.stepRun($0)?.step.title }
            return waitingFor.isEmpty ? "Starts with the run" : "Starts after \(waitingFor.formatted(.list(type: .and)))"
        case .awaitingApproval, .succeeded:
            return step.assignment.note
        case .starting:
            return step.step.kind == .pullRequest ? "Opening the pull request…" : "Starting a \(agent) session…"
        case .running:
            if report?.needsApproval == true {
                return "\(agent) is waiting for you to approve a tool call. Open the step to answer."
            }
            if let loop = step.goal {
                let goal = loop.goal
                let iteration = "Iteration \(goal.iterations + 1)" + (goal.budget.maxIterations.map { " of \($0)" } ?? "")
                return [iteration, goal.lastReason ?? "working toward the step's goal"].joined(separator: " · ")
            }
            return "\(agent) is working"
        case .paused:
            return "Paused with the workflow. Its next prompt goes out when the workflow resumes."
        case .blocked(let reason):
            return "\(agent) needs you: \(reason)"
        case .limited(let reason):
            return reason
        case .failed(let reason):
            return reason
        case .cancelled:
            return "Stopped." + (step.task == nil ? "" : " Resume to continue in its session, or retry from the start.")
        case .skipped:
            return "Skipped. The steps after it ran without its result."
        }
    }

    private var detailColor: Color {
        switch step.status {
        case .failed: .dsDanger
        case .limited: .dsWarning
        case .blocked: .dsAttention
        default: .dsTextSecondary
        }
    }

    @ViewBuilder private var preview: some View {
        if step.step.kind == .pullRequest, step.status == .succeeded, let output = step.output, let url = URL(string: output) {
            Link(destination: url) {
                Label(url.lastPathComponent.isEmpty ? output : "Pull request #\(url.lastPathComponent)", systemImage: "arrow.up.right.square")
            }
            .font(.dsBody)
            .foregroundStyle(.dsAccentText)
        } else if let text = previewText, !text.isEmpty {
            Text(text)
                .font(.dsBody)
                .foregroundStyle(.dsTextSecondary)
                .lineLimit(3)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var previewText: String? {
        let text = step.status == .succeeded ? step.output : (report?.reply ?? step.latestReply).map(GoalMarker.stripping)
        return text?.split(whereSeparator: \.isNewline).prefix(3).joined(separator: " ")
    }

    // MARK: - Ways on

    @ViewBuilder private var actions: some View {
        let available = WorkflowStepAction.available(for: step, isRunCancelled: run.isCancelled)
        if available.primary != nil || !available.others.isEmpty || step.task != nil {
            HStack(spacing: DS.Space.sm) {
                if let primary = available.primary {
                    button(primary, style: .ds(.secondary))
                }
                ForEach(available.others) { action in
                    button(action, style: .ds(.ghost))
                }
                Spacer(minLength: 0)
                if step.task != nil {
                    Button("Open Session", systemImage: "sidebar.right", action: onOpen)
                        .buttonStyle(.ds(.ghost))
                        .help("Show this step's conversation")
                }
            }
        }
    }

    private func button(_ action: WorkflowStepAction, style: DSButtonStyle) -> some View {
        Button(action.title, systemImage: action.systemImage) {
            send(action.event(for: step.id))
        }
        .buttonStyle(style)
        .help(action.help)
    }
}
