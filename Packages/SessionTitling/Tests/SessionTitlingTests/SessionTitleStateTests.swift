import Foundation
import Testing

@testable import SessionTitling

@Suite("Session titles")
struct SessionTitleStateTests {
    let request = SessionTitleRequest(projectName: "native", prompt: "Fix the flaky login test in CI please")

    @Test("The user's title wins over a generated one, and clearing it goes back to the automatic one")
    func userTitleWins() {
        var state = SessionTitleState()
        state.begin(request)
        let renamed = state.rename(to: "  Login fix  ")
        let accepted = state.accept(generated: "Fix flaky login test")
        #expect(renamed && accepted)
        #expect(state.displayTitle(agentTitle: "codex session") == "Login fix")
        let cleared = state.rename(to: "")
        #expect(cleared)
        #expect(state.displayTitle(agentTitle: "codex session") == "Fix flaky login test")
        let clearedAgain = state.rename(to: nil)
        #expect(!clearedAgain)
    }

    @Test("The first generated title stays")
    func firstGeneratedWins() {
        var state = SessionTitleState()
        state.begin(request)
        let first = state.accept(generated: "Fix flaky login test.")
        let second = state.accept(generated: "Something else")
        #expect(first && !second)
        #expect(state.generated == "Fix flaky login test")
        #expect(state.request == nil && state.progress == nil && !state.wantsTitle)
    }

    @Test("A task waiting for a title is named from its first message, including while it's generated")
    func fallback() {
        var state = SessionTitleState()
        state.begin(request)
        #expect(state.displayTitle(agentTitle: nil) == "Fix the flaky login test in CI please")
        state.waitForClient()
        #expect(state.displayTitle(agentTitle: nil) == "Fix the flaky login test in CI please")
        // The agent's own title comes first.
        #expect(state.displayTitle(agentTitle: "Login test") == "Login test")
        state.fail()
        #expect(state.fallback == "Fix the flaky login test in CI please")
        let accepted = state.accept(generated: "Fix login test")
        #expect(accepted && state.fallback == nil)
    }

    @Test("Placeholder agent titles count as none")
    func placeholderAgentTitles() {
        #expect(SessionTitleRules.meaningful("New session - 2026-10-17T14:19:55.251Z") == nil)
        #expect(SessionTitleRules.meaningful("Refactor the parser") == "Refactor the parser")
    }

    @Test("A long first message is cut after a few words")
    func longFallback() {
        let title = SessionTitleRules.fallback(
            from: "\n  please refactor the session store so it keeps titles across launches and restarts\nmore")
        #expect(title == "Please refactor the session store so it keeps…")
        #expect(SessionTitleRules.fallback(from: "  \n ") == nil)
    }

    @Test("A model's answer is tidied into one capitalized line")
    func cleaned() {
        #expect(SessionTitleRules.cleaned("  \"add retry to uploads\".\nExtra") == "Add retry to uploads")
        #expect(SessionTitleRules.cleaned(" ... ") == nil)
    }

    @Test("A message with only attachments is titled from what it attaches")
    func attachmentsOnly() {
        let request = SessionTitleRequest(
            firstMessage: "", attachmentNames: ["crash.log", "screen.png"], in: URL(filePath: "/tmp/native"))
        #expect(request.prompt == "crash.log, screen.png")
        #expect(request.projectName == "native")
    }

    @Test("An unusable first message leaves the next one eligible; an attempt is retried only once")
    func retryDecision() {
        var state = SessionTitleState()
        let empty = state.beginIfNeeded(SessionTitleRequest(projectName: "native", prompt: "   "))
        let first = state.beginIfNeeded(request)
        let inFlight = state.beginIfNeeded(request)
        #expect(!empty && first && !inFlight)
        state.fail()
        let retry = state.beginIfNeeded(SessionTitleRequest(projectName: "native", prompt: "another message"))
        #expect(retry)
        #expect(state.request?.prompt == request.prompt)
        #expect(state.retryCount == 1)
        state.fail()
        let exhausted = state.beginIfNeeded(request)
        #expect(!exhausted)
        #expect(state.fallback != nil)
    }

    @Test("A manual rename blocks a retry and undo restores eligibility")
    func renamedRetry() {
        var state = SessionTitleState()
        state.begin(request)
        state.waitForClient()
        state.rename(to: "My title")
        let renamed = state.beginIfNeeded(request)
        #expect(!renamed)
        #expect(state.displayTitle(agentTitle: nil) == "My title")
        state.rename(to: nil)
        let undone = state.beginIfNeeded(request)
        #expect(undone)
        state.accept(generated: "Login fix")
        let titled = state.beginIfNeeded(request)
        #expect(!titled)
    }

    @Test("Replaying the same logical prompt cannot spend the next-message retry")
    func replayDoesNotSpendRetry() {
        var state = SessionTitleState()
        let id = UUID()
        state.begin(request, promptID: id)
        state.fail()
        let resend = state.beginIfNeeded(request, promptID: id)
        let appRetry = state.beginIfNeeded(request, allowsRetry: false)
        #expect(!resend && !appRetry && state.retryCount == 0)
        // Identical text is still a new message when the user sends it again.
        let nextMessage = state.beginIfNeeded(request, promptID: UUID())
        #expect(nextMessage && state.retryCount == 1)
    }
}

@Suite("Title instructions")
struct SessionTitleInstructionsTests {
    @Test("A project's own instructions replace the global ones, and the organization's replace both")
    func precedence() {
        let project = "/Users/me/code/app"
        var instructions = SessionTitleInstructions(global: "Global", projects: [project: "Project"])
        #expect(instructions.addition(in: URL(filePath: "/Users/me/code/app/sub"))?.text == "Project")
        #expect(instructions.addition(in: URL(filePath: "/Users/me/other"))?.text == "Global")
        instructions.managed = ""
        #expect(instructions.addition(in: URL(filePath: project)) == nil)
    }
}
