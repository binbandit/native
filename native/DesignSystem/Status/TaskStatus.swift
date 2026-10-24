import SwiftUI

/// What a task (an agent session) is doing, as the sidebar shows it: active states animate, states
/// that need the user turn amber (`dsAttention`) so they stand out under any accent, and settled
/// states are quiet.
public nonisolated enum TaskStatus: Hashable, Sendable, CaseIterable {
    /// Not started, or finished and read: a hollow circle.
    case idle
    /// The agent is starting up.
    case starting
    /// The agent is working on a turn.
    case working
    /// Waiting on background tasks.
    case waiting
    /// The agent asked a question.
    case needsInput
    /// A tool call is waiting for approval.
    case needsPermission
    /// A plan is waiting for review.
    case needsPlanReview
    /// The last turn finished.
    case done
    /// The last turn or the agent failed.
    case failed
    /// The last turn was cancelled.
    case cancelled
    /// Stopped on purpose until someone resumes it (a paused goal or workflow).
    case paused
    /// Stopped by a usage limit until it resets.
    case limited

    /// The tooltip and accessibility text for the status, in the words every surface uses for a
    /// task: working, needs you (a question, an approval, a plan), finished, failed, stopped.
    public var label: String {
        switch self {
        case .idle: "Idle"
        case .starting: "Starting"
        case .working: "Working"
        case .waiting: "Waiting on background work"
        case .needsInput: "Has a question for you"
        case .needsPermission: "Waiting for your approval"
        case .needsPlanReview: "Plan ready for your review"
        // The user's own words for these: a turn finishes, and they press Stop.
        case .done: "Finished"
        case .failed: "Failed"
        case .cancelled: "Stopped"
        case .paused: "Paused"
        case .limited: "Usage limit reached"
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
        case .idle, .cancelled, .paused: .dsTextTertiary
        case .starting, .working, .waiting: .dsTextSecondary
        case .needsInput, .needsPermission, .needsPlanReview: .dsAttention
        case .done: .dsSuccess
        case .failed: .dsDanger
        case .limited: .dsWarning
        }
    }

    /// The SF Symbol for settled and attention states.
    var symbolName: String? {
        switch self {
        case .needsInput: "questionmark.bubble"
        case .needsPermission: "exclamationmark.circle"
        case .needsPlanReview: "list.bullet.clipboard"
        case .done: "checkmark.circle"
        case .failed: "xmark.circle"
        case .cancelled: "slash.circle"
        case .paused: "pause.circle"
        case .limited: "hourglass"
        case .idle, .starting, .working, .waiting: nil
        }
    }

    /// The animated loader for busy states.
    var loader: DotGridLoader.Pattern? {
        switch self {
        case .starting: .settingUp
        case .working: .typing
        case .waiting: .waiting
        default: nil
        }
    }
}

/// The 16pt status glyph that leads a task row: an animated dot
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
                // Smaller than SF's circle (r 9 of 24 at 14pt), so idle reads quieter than the glyphs.
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

#if DEBUG
#Preview("Task status") {
    DSPreviewPair {
        GalleryStatus()
    }
}
#endif
