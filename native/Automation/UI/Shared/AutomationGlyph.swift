import NativeAutomation
import SwiftUI

/// The status glyph for a goal, a workflow step or a run. Everything maps onto the design system's
/// task statuses, so steps read like any other task; only a step cut off by the host quitting has a
/// glyph of its own, since no task status means that.
enum AutomationGlyph: Hashable {
    case task(TaskStatus)
    case interrupted

    init(step status: WorkflowStepStatus, needsApproval: Bool = false) {
        switch status {
        case .waiting, .skipped: self = .task(.idle)
        case .awaitingApproval: self = .task(.needsPermission)
        case .starting: self = .task(.starting)
        case .running: self = needsApproval ? .task(.needsPermission) : .task(.working)
        case .paused: self = .task(.paused)
        case .blocked: self = .task(.needsInput)
        case .limited: self = .task(.limited)
        case .failed: self = .task(.failed)
        case .cancelled: self = .task(.cancelled)
        case .interrupted: self = .interrupted
        case .succeeded: self = .task(.done)
        }
    }

    init(goal status: GoalStatus, isWorking: Bool) {
        switch status {
        case .active: self = .task(isWorking ? .working : .waiting)
        case .paused: self = .task(.paused)
        case .blocked: self = .task(.needsInput)
        case .limited: self = .task(.limited)
        case .complete: self = .task(.done)
        }
    }

    init(run phase: WorkflowRunPhase) {
        switch phase {
        case .running: self = .task(.working)
        case .paused: self = .task(.paused)
        case .awaitingApproval: self = .task(.needsPermission)
        case .blocked: self = .task(.needsInput)
        case .halted: self = .task(.failed)
        case .succeeded: self = .task(.done)
        case .cancelled: self = .task(.cancelled)
        }
    }

    /// The task status closest to it, for places that only take one (sidebar rows).
    var taskStatus: TaskStatus {
        switch self {
        case .task(let status): status
        case .interrupted: .limited
        }
    }

    /// The color that goes with it, for labels next to the glyph.
    var tint: Color {
        switch self {
        case .task(let status): status.tint
        case .interrupted: .dsWarning
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
        case .interrupted:
            Image(systemName: "bolt.horizontal.circle")
                .font(.system(size: size * 0.75, weight: .regular))
                .foregroundStyle(glyph.tint)
                .frame(width: size, height: size)
                .help("Interrupted")
                .accessibilityLabel("Interrupted")
        }
    }
}
