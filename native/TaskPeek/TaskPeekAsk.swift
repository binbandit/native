import ACP
import ApprovalAnalysis
import Foundation

/// The request and its owner travel together. A child request is displayed at the parent's row,
/// but is answered on the child. Capturing the request prevents a late click answering its successor.
struct TaskPeekAsk: Identifiable {
    nonisolated struct ID: Hashable, Sendable {
        let task: SessionKey
        let session: SessionKey
        let request: RequestID
        let tool: String?
    }

    enum Content {
        case permission(ToolCallState)
        case question(SessionModel.PendingQuestion)
    }

    let task: SessionKey
    let session: SessionModel
    let content: Content
    let id: ID
    let since: Date

    var sentence: String { sentence(pushPlace: nil) }

    func sentence(pushPlace: String?, pushBranch: String? = nil) -> String {
        switch content {
        case .permission(let call):
            call.approvalQuestion(workingDirectory: session.cwd.path, pushPlace: pushPlace, pushBranch: pushBranch)
        case .question(let question): question.request.message
        }
    }

    var pushRequest: ApprovalPushReach.Request? {
        guard case .permission(let call) = content, let command = call.shellCommand else { return nil }
        let directory = call.rawInput?["cwd"]?.stringValue ?? session.cwd.path
        guard let target = ApprovalCommand(command: command, workingDirectory: directory).pushTarget else { return nil }
        return .init(
            session: session.key, permission: call.permission?.requestID,
            folder: URL(filePath: directory, directoryHint: .isDirectory), target: target)
    }

    var isCurrent: Bool {
        guard session.phase != .disconnected else { return false }
        switch content {
        case .permission(let call): return session.permissionRequests.contains(call)
        case .question(let question): return session.pendingQuestion?.id == question.id
        }
    }

    static func requests(in session: SessionModel, task: SessionKey) -> [Self] {
        guard session.phase != .disconnected else { return [] }
        var result = session.permissionRequests.compactMap { call -> Self? in
            guard let permission = call.permission else { return nil }
            return Self(
                task: task, session: session, content: .permission(call),
                id: ID(task: task, session: session.key, request: permission.requestID, tool: call.id),
                since: permission.requestedAt)
        }
        if let question = session.pendingQuestion {
            result.append(
                Self(
                    task: task, session: session, content: .question(question),
                    id: ID(task: task, session: session.key, request: question.id, tool: nil),
                    since: question.requestedAt))
        }
        for child in session.children.values.sorted(by: { $0.id.rawValue < $1.id.rawValue }) {
            result += requests(in: child, task: task)
        }
        return result.sorted { $0.since < $1.since }
    }
}
