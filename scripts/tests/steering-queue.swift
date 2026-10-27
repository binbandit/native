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
        print("In-app hold, edit, removal and queue-order checks passed")
    }
}
