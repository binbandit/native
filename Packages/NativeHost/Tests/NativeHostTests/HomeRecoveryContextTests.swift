import ACP
import Foundation
import NativeHostProtocol
import Testing

@Suite struct HomeRecoveryContextTests {
    @Test(arguments: [RecoveryNote.Action.resumed, .resent, .paused, .failed])
    func liveRecoveryRemainsVisibleAfterFailure(_ action: RecoveryNote.Action) {
        var mirror = SessionMirror()
        mirror.apply(HostEvent(seq: 1, payload: .prompt(PromptEcho(text: "Build the app"))))
        let note = RecoveryNote(
            cause: .agentStopped, action: action, agentName: "Fixture Agent",
            interruptedAt: Date(timeIntervalSince1970: 1_800_000_000), problem: "Fixture startup failure")
        mirror.apply(HostEvent(seq: 2, payload: .recovered(note)))
        mirror.apply(HostEvent(seq: 3, payload: .turnEnded(stopReason: "error")))
        #expect(TurnFailureContext(state: mirror.state).recovery == note.sentence())
    }

    @Test func aLaterTurnDoesNotClaimAnEarlierHostRecovery() {
        var mirror = SessionMirror()
        mirror.apply(HostEvent(seq: 1, payload: .prompt(PromptEcho(text: "Earlier work"))))
        let note = RecoveryNote(
            cause: .agentStopped, action: .paused, agentName: "Fixture Agent", interruptedAt: .now)
        mirror.apply(HostEvent(seq: 2, payload: .recovered(note)))
        mirror.apply(HostEvent(seq: 3, payload: .prompt(PromptEcho(text: "Different work"))))
        #expect(TurnFailureContext(state: mirror.state).recovery == nil)
    }
}
