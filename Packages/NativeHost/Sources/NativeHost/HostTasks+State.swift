import ACP
import Foundation
import NativeHostProtocol
import NativeOrchestration

extension HostTasks {
    /// How the session reads as a task. The transcript is folded only when the state needs it.
    func snapshot(_ session: HostSession, reading: Bool = true) -> TaskSnapshot {
        var state = ownSnapshot(session, reading: reading)
        if (state.status == .idle || state.status == .failed), hasUnfinishedDescendants(session.id) {
            state.status = .running
            state.detail = [
                state.detail, "Waiting for child tasks and their completion delivery.",
                session.record.isQueuePaused ? "The task is paused; ask the user to resume or Stop its children." : nil,
            ]
            .compactMap { $0 }.joined(separator: " ")
        }
        return state
    }

    func ownSnapshot(_ session: HostSession, reading: Bool = true) -> TaskSnapshot {
        let phase: TaskSnapshot.Phase =
            switch session.phase {
            case .loading, .recovering: .loading
            case .prompting: .running
            case .disconnected: .disconnected
            case .idle, .unknown: session.turn != nil || session.retryAt != nil ? .running : .idle
            }
        let stopReason = session.record.lastStopReason.map(SessionMirror.stopReason)
        let needsApproval = !session.pendingPermissions.isEmpty || !session.pendingQuestions.isEmpty
        guard reading else {
            // The card only shows the reason a turn failed; anything else reads without the transcript.
            return TaskSnapshot(
                phase: phase, needsApproval: needsApproval, lastStopReason: stopReason, agentName: session.agentName,
                state: SessionState())
        }
        return TaskSnapshot(
            phase: phase, needsApproval: needsApproval, lastStopReason: stopReason, agentName: session.agentName,
            state: session.mirror.state)
    }

}
