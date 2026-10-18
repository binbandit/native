import NativeAutomation
import SwiftUI

/// The top of a run: what it's working on, where it stands, and pause, resume and stop for the
/// whole run. The progress bar has one segment per step, colored like its status.
struct WorkflowRunHeader: View {
    let run: WorkflowRun
    let send: (WorkflowEvent) -> Void

    var body: some View {
        // The start time reads as an age, which only moves by the minute.
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            content(now: timeline.date)
        }
    }

    private func content(now: Date) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            HStack(alignment: .top, spacing: DS.Space.md) {
                Image(systemName: run.definition.symbol)
                    .font(.system(size: 14))
                    .foregroundStyle(.dsTextSecondary)
                    .frame(width: DS.Size.controlSM, height: DS.Size.controlSM)
                    .background(.dsSurfaceRaised, in: .circle)
                    .overlay { Circle().strokeBorder(.dsSeparator, lineWidth: 1) }
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text(run.title)
                        .font(.dsTitle3)
                        .foregroundStyle(.dsTextPrimary)
                        .lineLimit(2)
                    Text([run.definition.name, run.cwd.lastPathComponent, run.startedText(now: now), run.cost.map { DSFormat.cost($0) }].compactMap(\.self).joined(separator: " · "))
                        .monospacedDigit()
                        .font(.dsCaption)
                    .foregroundStyle(.dsTextTertiary)
                }
                .tracking(DS.Tracking.tight)
                Spacer(minLength: DS.Space.lg)
                controls
            }
            HStack(spacing: DS.Space.md) {
                AutomationStatusGlyph(glyph: run.statusGlyph)
                Badge(run.statusLabel, tone: tone, style: .mono)
                StepSegments(steps: run.steps)
                Text("\(run.finishedCount) of \(run.steps.count) steps")
                    .font(.dsCaption)
                    .monospacedDigit()
                    .foregroundStyle(.dsTextTertiary)
                    .fixedSize()
            }
            if let note = phaseNote {
                Text(note)
                    .font(.dsCaption)
                    .foregroundStyle(.dsTextSecondary)
            }
        }
    }

    @ViewBuilder private var controls: some View {
        HStack(spacing: DS.Space.sm) {
            switch run.phase {
            case .running, .awaitingApproval, .blocked, .halted:
                Button("Pause", systemImage: "pause.fill") { send(.pauseRun) }
                    .buttonStyle(.ds(.secondary))
                    .help("Let running turns finish, then hold the workflow")
                Button("Stop", systemImage: "stop.fill") { send(.cancel) }
                    .buttonStyle(.ds(.ghost))
                    .help("Stop the workflow and every step's turn")
            case .paused:
                Button("Resume", systemImage: "play.fill") { send(.resumeRun) }
                    .buttonStyle(.ds(.primary))
                Button("Stop", systemImage: "stop.fill") { send(.cancel) }
                    .buttonStyle(.ds(.ghost))
            case .succeeded, .cancelled:
                EmptyView()
            }
        }
    }

    /// Why the run isn't moving, when it isn't.
    private var phaseNote: String? {
        switch run.phase {
        case .paused:
            let finishing = run.steps.count(where: \.status.isActive)
            return finishing > 0 ? "Paused. \(finishing == 1 ? "One step is" : "\(finishing) steps are") finishing the current turn; nothing new starts until you resume." : "Paused. Nothing new starts until you resume."
        case .halted:
            return "Nothing is running: a step stopped short. Retry, resume or skip it to go on."
        case .cancelled:
            return "Stopped. Finished steps keep their sessions and results."
        case .succeeded:
            return run.endedAt.map { "Finished in \(DSFormat.duration($0.timeIntervalSince(run.createdAt)))." }
        case .running, .awaitingApproval, .blocked:
            return nil
        }
    }

    private var tone: Badge.Tone {
        switch run.phase {
        case .running: .accent
        case .paused, .cancelled: .neutral
        case .awaitingApproval, .blocked: .attention
        case .halted: run.hasFailedStep ? .danger : .warning
        case .succeeded: .success
        }
    }
}

/// One thin segment per step: the run's progress at a glance.
private struct StepSegments: View {
    let steps: [WorkflowStepRun]

    var body: some View {
        HStack(spacing: DS.Space.xxs) {
            ForEach(steps) { step in
                Rectangle()
                    .fill(color(for: step.status))
                    .frame(height: DS.Space.xs)
                    .clipShape(.rect(cornerRadius: DS.Radius.small))
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    private func color(for status: WorkflowStepStatus) -> Color {
        switch status {
        case .succeeded: .dsSuccess
        case .skipped, .waiting: .dsSelected
        case .starting, .running: .dsAccent
        case .awaitingApproval, .blocked: .dsAttention
        case .paused, .cancelled: .dsTextQuaternary
        case .limited, .interrupted: .dsWarningFill
        case .failed: .dsDanger
        }
    }
}
