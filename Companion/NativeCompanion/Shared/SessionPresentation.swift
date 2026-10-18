import ACP
import Foundation
import NativeHostProtocol

/// How a host's session reads on the phone, in the Mac's words (`TaskStatus`, titles, steps).
extension HostSessionSummary {
    func taskStatus(_ mirror: SessionMirror?) -> TaskStatus {
        switch phase {
        case .loading: return .starting
        case .recovering: return .working
        case .prompting: return needsApproval ? .needsPermission : .working
        case .disconnected: return .failed
        case .idle, .unknown:
            if needsApproval { return .needsPermission }
            switch lastStopReason {
            case nil: return .idle
            case "cancelled": return .cancelled
            case "end_turn": return .done
            default: return .failed
            }
        }
    }

    var projectName: String {
        URL(filePath: cwd).lastPathComponent
    }

    func displayTitle(_ mirror: SessionMirror?) -> String {
        if let title, !title.isEmpty { return title }
        if let title = mirror?.state.title, !title.isEmpty { return title }
        if let first = mirror?.userMessages.first?.split(separator: "\n").first { return String(first.prefix(80)) }
        return "\(agentName) in \(projectName)"
    }

    /// What it's doing right now ("Editing Composer.swift"), or how it ended.
    func statusLine(_ mirror: SessionMirror?) -> String {
        if phase == .disconnected { return problem ?? "The agent can't run right now." }
        if phase == .recovering { return "Resuming after an interruption" }
        if needsApproval, let pending = mirror?.state.pendingPermissions.first,
            let call = mirror?.state.toolCall(id: pending.toolCallID)
        {
            return "Needs approval · \(CompanionToolSummary(call).subject)"
        }
        if isWorking {
            if let call = mirror?.state.items.reversed().lazy.compactMap({ item -> ToolCallState? in
                if case .toolCall(let call) = item, call.status == .inProgress || call.status == .pending { call } else { nil }
            }).first {
                let presentation = CompanionToolSummary(call)
                return [presentation.verbs?.progressive, presentation.subject].compactMap { $0 }.joined(separator: " ")
            }
            return queue.isEmpty ? "Working" : "Working · \(queue.count) queued"
        }
        switch taskStatus(mirror) {
        case .cancelled: return "Stopped"
        case .failed: return "Ended with an error"
        case .done: return "Done"
        default: return "\(agentName) · \(projectName)"
        }
    }
}

extension SessionState {
    func toolCall(id: String) -> ToolCallState? {
        for item in items {
            if case .toolCall(let call) = item, call.id == id { return call }
        }
        return nil
    }
}
