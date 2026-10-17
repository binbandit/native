import Foundation
import NativeHostProtocol
import Testing

@testable import NativeHost

@Suite("Recovery decisions")
struct RecoveryPlannerTests {
    @Test("A prompt the agent recorded is resumed, never replayed")
    func resumeWhenReceived() {
        #expect(
            RecoveryPlanner.decide(prompt: "Fix the build", attempts: 0, replayedUserMessages: ["Hi", "Fix the build"])
                == .resume)
    }

    @Test("A prompt missing from the agent's transcript is sent again")
    func resendWhenMissing() {
        #expect(RecoveryPlanner.decide(prompt: "Fix the build", attempts: 0, replayedUserMessages: ["Hi"]) == .resend)
        #expect(RecoveryPlanner.decide(prompt: "Fix the build", attempts: 0, replayedUserMessages: []) == .resend)
    }

    @Test("A prompt followed by the agent's own interruption marker still counts as received")
    func interruptionMarker() {
        let replay = ["Earlier task", "Write rows 1 through 500", "[Request interrupted by user]"]
        #expect(
            RecoveryPlanner.decide(prompt: "Write rows 1 through 500", attempts: 0, replayedUserMessages: replay)
                == .resume)
    }

    @Test("An identical prompt from several turns back doesn't mean this one arrived")
    func onlyRecentMessages() {
        let replay = ["continue", "one", "two", "three"]
        #expect(RecoveryPlanner.decide(prompt: "continue", attempts: 0, replayedUserMessages: replay) == .resend)
    }

    @Test("Agents that wrap the prompt when they store it still count as having it")
    func wrappedPrompt() {
        #expect(
            RecoveryPlanner.agentReceived(
                "Fix the build", replayedUserMessages: ["<context>…</context>\nFix the build\n"]))
    }

    @Test("A turn that keeps failing pauses instead of looping")
    func pausesAfterRepeatedFailures() {
        #expect(
            RecoveryPlanner.decide(prompt: "x", attempts: RecoveryPlanner.maximumAttempts, replayedUserMessages: ["x"])
                == .pause)
    }

    @Test("A boot since the last run means the Mac restarted")
    func cause() {
        let boot = Date(timeIntervalSince1970: 1_000)
        #expect(
            RecoveryPlanner.cause(previousBoot: boot, currentBoot: boot.addingTimeInterval(3_600)) == .systemRestarted)
        #expect(RecoveryPlanner.cause(previousBoot: boot, currentBoot: boot.addingTimeInterval(0.2)) == .hostStopped)
        #expect(RecoveryPlanner.cause(previousBoot: nil, currentBoot: boot) == .hostStopped)
    }

    @Test("What the user reads says what happened and what Native did")
    func sentences() {
        let at = Date(timeIntervalSince1970: 0)
        let format: (Date) -> String = { _ in "2:14 PM" }
        #expect(
            RecoveryNote(cause: .agentStopped, action: .resumed, agentName: "Claude Code", interruptedAt: at).sentence(
                formattingTime: format)
                == "Claude Code stopped unexpectedly at 2:14 PM. Native restarted Claude Code and asked it to pick up where it left off."
        )
        #expect(
            RecoveryNote(cause: .systemRestarted, action: .resent, agentName: "Codex", interruptedAt: at).sentence(
                formattingTime: format)
                == "Your Mac restarted at 2:14 PM while Codex was working. Your message hadn't reached Codex yet, so Native sent it again."
        )
    }
}
