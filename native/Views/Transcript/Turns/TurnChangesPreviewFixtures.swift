#if DEBUG
import ACP
import Foundation

enum TurnChangesPreviewFixtures {
    static let files: [TurnSummary.ChangedFile] = [
        .init(path: "/project/README.md", added: 2),
        .init(path: "/project/docs/a-long-folder-name/usage-and-configuration.md", added: 12, removed: 3),
        .init(path: "/project/images/example.png"),
    ]

    static var summary: TurnSummary {
        var summary = TurnSummary(items: [TranscriptItem]())
        summary.changedFiles = files
        return summary
    }

    static func session(in app: AppModel) -> SessionModel? {
        guard let session = SessionModel.preview(in: app, cwd: "/project") else { return nil }
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        session.state.appendUserMessage("Update the docs using a shell command, then commit.", at: start)
        session.state.apply(
            .toolCall(
                ToolCallUpdate(toolCallId: "shell", title: "Update documentation", kind: .execute, status: .completed)),
            at: start.addingTimeInterval(1))
        session.state.apply(
            .agentMessageChunk(ContentChunk(content: .text("Committed the documentation changes."))),
            at: start.addingTimeInterval(2))
        session.state.endTurn(.endTurn, at: start.addingTimeInterval(3))
        return session
    }

    static func actions(for session: SessionModel) -> TurnChangesActions {
        let detected = session.state.turns.last?.startedAt.map { TurnDetectedChanges(startedAt: $0, files: files) }
        return TurnChangesActions(review: {}, reviewFile: { _ in }, latestTurnChanges: detected)
    }
}
#endif
