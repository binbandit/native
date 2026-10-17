import SwiftUI

/// What a task (an agent session) is doing, as the sidebar shows it. Mirrors Conductor's workspace
/// statuses, narrowed to agent states: active states animate, states that need the user turn
/// amber (`dsAttention`) so they stand out under any accent, and settled states are quiet.
public nonisolated enum TaskStatus: Hashable, Sendable, CaseIterable {
    /// Not started, or finished and read: a hollow circle.
    case idle
    /// The agent is starting up (Conductor `setting-up`).
    case starting
    /// The agent is working on a turn (Conductor `working`).
    case working
    /// Waiting on background tasks (Conductor `waiting`).
    case waiting
    /// The agent asked a question (Conductor `needs-user-input`).
    case needsInput
    /// A tool call is waiting for approval (Conductor `needs-user-permission`).
    case needsPermission
    /// A plan is waiting for review (Conductor `needs-plan-response`).
    case needsPlanReview
    /// The last turn finished.
    case done
    /// The last turn or the agent failed.
    case failed
    /// The last turn was cancelled.
    case cancelled

    /// Conductor's tooltip and accessibility text for the status.
    public var label: String {
        switch self {
        case .idle: "Idle"
        case .starting: "Starting"
        case .working: "Working"
        case .waiting: "Waiting for background tasks"
        case .needsInput: "Needs input"
        case .needsPermission: "Needs permission"
        case .needsPlanReview: "Needs plan response"
        case .done: "Done"
        case .failed: "Failed"
        case .cancelled: "Cancelled"
        }
    }

    /// Whether the status asks something of the user.
    public var needsAttention: Bool {
        switch self {
        case .needsInput, .needsPermission, .needsPlanReview: true
        default: false
        }
    }

    /// Whether the agent is busy.
    public var isActive: Bool {
        switch self {
        case .starting, .working, .waiting: true
        default: false
        }
    }

    /// The glyph's color.
    public var tint: Color {
        switch self {
        case .idle, .cancelled: .dsTextTertiary
        case .starting, .working, .waiting: .dsTextSecondary
        case .needsInput, .needsPermission, .needsPlanReview: .dsAttention
        case .done: .dsSuccess
        case .failed: .dsDanger
        }
    }

    /// The SF Symbol for settled and attention states (Conductor's lucide glyphs).
    var symbolName: String? {
        switch self {
        case .needsInput: "questionmark.bubble"
        case .needsPermission: "exclamationmark.circle"
        case .needsPlanReview: "list.bullet.clipboard"
        case .done: "checkmark.circle"
        case .failed: "xmark.circle"
        case .cancelled: "slash.circle"
        case .idle, .starting, .working, .waiting: nil
        }
    }

    /// The animated loader for busy states (Conductor's status sprites).
    var loader: DotGridLoader.Pattern? {
        switch self {
        case .starting: .settingUp
        case .working: .typing
        case .waiting: .waiting
        default: nil
        }
    }
}

/// The 16pt status glyph that leads a task row (Conductor `WorkspaceStatusIcon`): an animated dot
/// grid while the agent is busy, otherwise a symbol tinted by the status.
public struct StatusIndicator: View {
    let status: TaskStatus
    let size: CGFloat

    /// - Parameter size: The square the glyph is centered in; the glyph itself is 14pt at 16.
    public init(status: TaskStatus, size: CGFloat = DS.Size.rowLeading) {
        self.status = status
        self.size = size
    }

    public var body: some View {
        Group {
            if let pattern = status.loader {
                DotGridLoader(pattern: pattern)
                    .foregroundStyle(status.tint)
                    .frame(width: size * 0.875, height: size * 0.875)
            } else if status == .idle {
                // Conductor's hollow circle is smaller than SF's (r 9 of 24 at 14pt).
                Circle()
                    .strokeBorder(status.tint, lineWidth: 1.2)
                    .frame(width: size * 0.66, height: size * 0.66)
            } else if let symbolName = status.symbolName {
                Image(systemName: symbolName)
                    .font(.system(size: size * 0.75, weight: .regular))
                    .foregroundStyle(status.tint)
            }
        }
        .frame(width: size, height: size)
        .help(status.label)
        .accessibilityElement()
        .accessibilityLabel(status.label)
    }
}

#Preview("Task status") {
    DSPreviewPair {
        GalleryStatus()
    }
}
