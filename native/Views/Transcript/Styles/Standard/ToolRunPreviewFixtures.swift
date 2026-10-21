#if DEBUG
import ACP
import SwiftUI

enum ToolRunPreviewFixtures {
    enum State {
        case closed, awaitingApproval, opened
    }

    static func make(in app: AppModel, state: State) -> (session: SessionModel, run: TranscriptActivityRun)? {
        guard let session = SessionModel.preview(in: app) else { return nil }
        for index in 1...8 {
            let json = """
                {"toolCallId":"preview-\(index)","title":"printf 'Step \(index)'","kind":"execute",
                 "status":"\(index == 8 ? "failed" : "completed")",
                 "rawInput":{"command":"printf 'Step \(index)'"}}
                """
            guard let update = SessionModel.previewDecode(ToolCallUpdate.self, json) else { return nil }
            session.state.apply(.toolCall(update))
        }
        if state == .awaitingApproval {
            session.previewPermissionRequest(command: "swift test")
        }
        let calls = session.state.items.compactMap { item in
            if case .toolCall(let call) = item { call } else { nil }
        }
        // Normal grouping leaves approvals outside runs. Feed one directly to the container too,
        // so its defensive visibility rule can be inspected independently of the planner.
        let rows = [(row: TranscriptRow.exploration(calls), itemIndex: 0)]
        guard let run = TranscriptActivityRun(rows: rows[...], in: session.state) else { return nil }
        if state == .opened { session.transcriptDisclosures.openRun(run.id) }
        return (session, run)
    }
}
#endif
