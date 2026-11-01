import Foundation
import MCP

extension TaskOrchestrator {
    // MARK: - Reports

    func report(_ peer: Peer, _ snapshot: TaskSnapshot?, waited: Bool = false) -> MCPToolResult {
        var structured: [String: JSON] = [
            "task_id": .string(peer.id), "agent": .string(peer.session.agent),
            "relation": .string(peer.relation.rawValue),
        ]
        structured["title"] = peer.title.map(JSON.string)
        let name = peer.relation == .parent ? "Your parent task (\(peer.agentName))" : peer.label
        guard let snapshot else {
            structured["status"] = "failed"
            structured["detail"] = "The task is no longer open in Native."
            return MCPToolResult(
                text: "\(name) is no longer open in Native.", structuredContent: .object(structured))
        }
        structured["status"] = .string(snapshot.status.rawValue)
        structured["reply"] = snapshot.reply.map(JSON.string)
        structured["detail"] = snapshot.detail.map(JSON.string)

        let keepWaiting = waited ? " Call wait_for_task again to keep waiting." : ""
        let state =
            switch snapshot.status {
            case .running: "is still running.\(keepWaiting)"
            case .needsApproval:
                "is waiting for the user to approve \(snapshot.detail ?? "a tool call") in Native. It continues once they answer.\(keepWaiting)"
            case .idle: "finished its turn" + (snapshot.detail.map { " (\($0))" } ?? "") + "."
            case .failed: "failed: \(snapshot.detail ?? "its agent stopped running")."
            case .cancelled: "was cancelled."
            }
        var text = "\(name) \(state)"
        switch (snapshot.status, snapshot.reply) {
        case (.running, let reply?), (.needsApproval, let reply?): text += "\n\nReply so far:\n\(reply)"
        case (_, let reply?): text += "\n\nReply:\n\(reply)"
        case (.idle, nil): text += " It didn't reply."
        case (_, nil): break
        }
        return MCPToolResult(text: text, structuredContent: .object(structured))
    }

    func resultReport(
        _ peer: Peer, _ snapshot: TaskSnapshot?, caller: OrchestrationCaller, waited: Bool = false
    ) async throws -> MCPToolResult {
        if peer.relation == .child, let snapshot, snapshot.status != .running, snapshot.status != .needsApproval {
            try await runtime.acknowledgeResult(of: peer.session, by: caller.clientID)
        }
        var report = report(peer, snapshot, waited: waited)
        if peer.relation != .assigned, let original = await runtime.originalResult(of: peer.session),
            case .object(var fields) = report.structuredContent
        {
            var result: [String: JSON] = ["status": .string(original.status.rawValue)]
            result["reply"] = original.reply.map(JSON.string)
            result["detail"] = original.detail.map(JSON.string)
            fields["original_result"] = .object(result)
            report.structuredContent = .object(fields)
        }
        return report
    }
}
