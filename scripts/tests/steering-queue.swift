import ACP
import Foundation

@testable import Native

/// Exercises the in-app model with preview services and a /dev/null ACP connection. No agent runs.
@main
@MainActor
private struct SteeringQueueRegression {
    static func main() async throws {
        let app = AppModel.preview(.empty)
        guard let session = SessionModel.preview(in: app, phase: .prompting) else {
            print("FAIL: couldn't create the in-app session fixture")
            exit(1)
        }
        session.state.appendUserMessage("original turn")
        session.apply(.toolCall(ToolCallUpdate(toolCallId: "sleep", title: "sleep 20", status: .inProgress)))
        let delivery = try await session.submit("local original", .steer)
        guard delivery == .queued, let first = session.queuedPrompts.first, first.waitingForTool == "sleep 20" else {
            print("FAIL: in-app Steer didn't hold for the running tool")
            exit(1)
        }
        session.updateQueued(first.id, text: "local edited")
        guard session.queuedPrompts.first?.text == "local edited" else {
            print("FAIL: the held steer couldn't be edited")
            exit(1)
        }
        session.removeQueued(first.id)
        guard session.queuedPrompts.isEmpty else {
            print("FAIL: the held steer couldn't be removed")
            exit(1)
        }
        _ = try await session.submit("held steer", .steer)
        _ = try await session.submit("ordinary queue", .queue)
        guard let held = session.queuedPrompts.first, let ordinary = session.queuedPrompts.last else {
            print("FAIL: missing pending queue items")
            exit(1)
        }
        session.state.endTurn(.cancelled)
        session.lastStopReason = .cancelled
        session.isStopping = true
        session.phase = .idle
        session.turnDidEnd()
        guard session.queue.isPaused, session.queue.items.allSatisfy({ !$0.steersAfterTools }) else {
            print("FAIL: Stop didn't retain the messages as ordinary paused input")
            exit(1)
        }
        session.moveQueued(ordinary.id, before: held.id)
        session.draft = "resume queue"
        await session.submit(.queue)
        let users = session.state.items.compactMap { item -> String? in
            if case .message(let message) = item, message.role == .user { message.text } else { nil }
        }
        guard users == ["original turn", "ordinary queue"],
            session.queuedPrompts.map(\.text) == ["held steer", "resume queue"],
            session.queue.items.allSatisfy({ !$0.steersAfterTools })
        else {
            print("FAIL: resume bypassed the explicit queue order or carried a steer into the next turn")
            exit(1)
        }
        try await checkUndoAcrossTurn(app)
        try await checkAcknowledgementOwnership(app)
        print("In-app hold, edit, undo, acknowledgement ownership and queue-order checks passed")
    }
    private static func checkUndoAcrossTurn(_ app: AppModel) async throws {
        guard let session = SessionModel.preview(in: app, phase: .prompting) else { exit(1) }
        session.apply(.toolCall(ToolCallUpdate(toolCallId: "sleep", title: "sleep", status: .inProgress)))
        _ = try await session.submit("removed correction", .steer)
        guard let item = session.queuedPrompts.first else { exit(1) }
        let undo = UndoManager()
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        session.removeQueued(item.id, undoManager: undo)
        undo.endUndoGrouping()
        session.phase = .idle
        session.lastStopReason = .cancelled
        session.turnDidEnd()
        session.phase = .prompting
        undo.undo()
        guard session.queue.items.map(\.text) == ["removed correction"],
            session.queue.items.allSatisfy({ !$0.steersAfterTools })
        else {
            print("FAIL: Undo carried a correction into a different turn")
            exit(1)
        }
    }

    private static func checkAcknowledgementOwnership(_ app: AppModel) async throws {
        guard let session = SessionModel.preview(in: app, phase: .idle) else { exit(1) }
        session.isDeliveringSteer = true
        session.queue.append("selected")
        guard let item = session.queuedPrompts.first, session.sendNowRoute == nil else { exit(1) }
        await session.sendQueuedNow(item.id)
        guard session.queue.items.map(\.text) == ["selected"] else { exit(1) }
        session.draft = "draft"
        await session.send()
        guard session.draft == "draft", session.phase == .idle else { exit(1) }
        session.queue.pause()
        let delivery = try await session.submit("direct", .queue)
        guard delivery == .queued, session.phase == .idle, !session.queue.isPaused,
            session.queue.items.map(\.text) == ["selected", "direct"]
        else { exit(1) }
        do {
            _ = try await session.runHiddenCommand("/context")
            print("FAIL: a hidden command bypassed the steering acknowledgement")
            exit(1)
        } catch SessionModel.SendError.busy {
            // The caller can retry after the outstanding acknowledgement.
        }
    }

}
