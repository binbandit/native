import SwiftUI

/// The status glyph for a goal or a workflow step. Everything that has a task status uses the design
/// system's `StatusIndicator`, so steps read like any other task; paused and limited have no task
/// status, so they get glyphs of their own in the same 16pt slot.
enum AutomationGlyph: Hashable {
    case task(TaskStatus)
    case paused
    case limited

    init(step status: WorkflowStepStatus, needsApproval: Bool = false) {
        switch status {
        case .waiting, .skipped: self = .task(.idle)
        case .awaitingApproval: self = .task(.needsPermission)
        case .starting: self = .task(.starting)
        case .running: self = needsApproval ? .task(.needsPermission) : .task(.working)
        case .paused: self = .paused
        case .blocked: self = .task(.needsInput)
        case .limited: self = .limited
        case .failed: self = .task(.failed)
        case .cancelled: self = .task(.cancelled)
        case .succeeded: self = .task(.done)
        }
    }

    init(goal status: GoalStatus, isWorking: Bool) {
        switch status {
        case .active: self = .task(isWorking ? .working : .waiting)
        case .paused: self = .paused
        case .blocked: self = .task(.needsInput)
        case .limited: self = .limited
        case .complete: self = .task(.done)
        }
    }

    init(run phase: WorkflowRunPhase) {
        switch phase {
        case .running: self = .task(.working)
        case .paused: self = .paused
        case .awaitingApproval: self = .task(.needsPermission)
        case .blocked: self = .task(.needsInput)
        case .halted: self = .task(.failed)
        case .succeeded: self = .task(.done)
        case .cancelled: self = .task(.cancelled)
        }
    }

    /// The color that goes with it, for labels next to the glyph.
    var tint: Color {
        switch self {
        case .task(let status): status.tint
        case .paused: .dsTextTertiary
        case .limited: .dsWarning
        }
    }
}

struct AutomationStatusGlyph: View {
    let glyph: AutomationGlyph
    var size: CGFloat = DS.Size.rowLeading

    var body: some View {
        switch glyph {
        case .task(let status):
            StatusIndicator(status: status, size: size)
        case .paused:
            symbol("pause.circle", label: "Paused")
        case .limited:
            symbol("gauge.with.dots.needle.100percent", label: "Limited")
        }
    }

    private func symbol(_ name: String, label: String) -> some View {
        Image(systemName: name)
            .font(.system(size: size * 0.75, weight: .regular))
            .foregroundStyle(glyph.tint)
            .frame(width: size, height: size)
            .help(label)
            .accessibilityLabel(label)
    }
}
