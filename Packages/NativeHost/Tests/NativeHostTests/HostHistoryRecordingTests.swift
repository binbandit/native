import Foundation
import NativeHostProtocol
import Testing

@testable import ACP
@testable import NativeHost

/// Where an interrupted turn's work starts in a replay, and how a turn's items are settled before
/// they're recorded: the history is append-only, so what's written first has to be right.
struct HostHistoryRecordingTests {
    private func message(_ role: TranscriptMessage.Role, _ text: String) -> TranscriptItem {
        .message(TranscriptMessage(role: role, text: text))
    }

    @Test("A later steer that quotes the interrupted message doesn't move the boundary past earlier work")
    func steerQuotingThePrompt() throws {
        let items = [
            message(.user, "earlier"), message(.agent, "done earlier"), message(.user, "fix tests"),
            message(.agent, "work before steering"), message(.user, "also fix tests on iOS"),
            message(.agent, "work after steering"),
        ]
        let work = try #require(HostCore.interruptedWork(of: "fix tests", in: items))
        #expect(Array(work) == Array(items[3...]))
    }

    @Test("A recovery prompt interrupted again is found as the notice it replays as")
    func recoveryNotice() throws {
        let prompt = RecoveryPlanner.interruptionPrompt(cause: .agentStopped)
        var notice = TranscriptNotice(text: "This turn was interrupted.", isError: false, isRecovery: true)
        notice.sentToAgent = prompt
        let items = [
            message(.user, "fix tests"), message(.agent, "first attempt"), .notice(notice),
            message(.agent, "second attempt"),
        ]
        let work = try #require(HostCore.interruptedWork(of: prompt, in: items))
        #expect(work.count == 1)
        #expect(work.first.flatMap { if case .message(let reply) = $0 { reply.text } else { nil } } == "second attempt")
        #expect(HostCore.interruptedWork(of: "never sent", in: items) == nil)
    }

    @Test("A call still open when the turn ends is recorded as the ending settles it")
    func settlesOpenCalls() throws {
        var state = SessionState()
        state.appendUserMessage("run the tests")
        let update =
            #"{"sessionUpdate":"tool_call","toolCallId":"t1","title":"swift test","kind":"execute","status":"in_progress"}"#
        state.apply(try JSONDecoder().decode(SessionUpdate.self, from: Data(update.utf8)))
        func status(_ ending: String) -> ToolCallStatus? {
            guard case .toolCall(let call)? = HostCore.settledItems(state, from: 1, ending: ending).first else {
                return nil
            }
            return call.status
        }
        #expect(status("cancelled") == .cancelled)
        #expect(status("end_turn") == .unreported)
    }
}
