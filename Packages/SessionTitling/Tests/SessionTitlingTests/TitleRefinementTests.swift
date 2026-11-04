import Foundation
import Testing

@testable import SessionTitling

@Suite("Title refinement")
struct TitleRefinementTests {
    let request = SessionTitleRequest(projectName: "native", prompt: "fix the build")
    let outcome = "Fixed actor isolation in SessionModel"

    @Test("A generated title stays through the first outcome and later turns", arguments: [false, true])
    func generatedTitleStays(slowInitial: Bool) {
        var state = SessionTitleState()
        state.begin(request)
        if slowInitial { state.finishFirstTurn(outcome: outcome) }
        let initialAccepted = state.accept(generated: "Fix build")
        #expect(initialAccepted)
        state.finishFirstTurn(outcome: outcome)
        #expect(state.generated == "Fix build")
        #expect(state.request == nil && state.progress == nil && state.refinementCount == 0)
        let laterTurnIgnored = !state.beginIfNeeded(SessionTitleRequest(projectName: "native", prompt: "Now fix tests"))
        #expect(laterTurnIgnored)
        state.finishFirstTurn(outcome: "Fixed tests")
        let refinementIgnored = !state.accept(generated: "Fix SessionModel isolation", revision: 1)
        #expect(refinementIgnored)
        let duplicateIgnored = !state.accept(generated: "Fix tests")
        #expect(duplicateIgnored)
        #expect(state.displayTitle(agentTitle: "Changed agent title") == "Fix build")
    }

    @Test("Only the temporary fallback is replaced, once")
    func fallbackIsReplacedOnce() {
        var state = SessionTitleState()
        state.begin(request)
        #expect(state.displayTitle(agentTitle: nil) == "Fix the build")
        state.finishFirstTurn(outcome: outcome)
        #expect(state.generated == nil && state.fallback == "Fix the build")
        #expect(state.request?.firstTurnOutcome == outcome)
        let initialAccepted = state.accept(generated: "Fix SessionModel isolation")
        #expect(initialAccepted)
        #expect(state.fallback == nil && state.request == nil && state.progress == nil)
        let duplicateIgnored = !state.accept(generated: "Another title")
        #expect(duplicateIgnored)
        #expect(state.displayTitle(agentTitle: nil) == "Fix SessionModel isolation")
    }

    @Test("A user rename always wins over a pending title", arguments: [false, true])
    func manualRename(beforeGeneration: Bool) {
        var state = SessionTitleState()
        state.begin(request)
        if beforeGeneration { state.rename(to: "Mine") }
        let initialAccepted = state.accept(generated: "Fix build")
        #expect(initialAccepted)
        if !beforeGeneration { state.rename(to: "Mine") }
        state.finishFirstTurn(outcome: outcome)
        let refinementIgnored = !state.accept(generated: "Fix SessionModel isolation", revision: 1)
        #expect(refinementIgnored)
        #expect(state.displayTitle(agentTitle: "Agent title") == "Mine")
        state.rename(to: nil)
        #expect(state.displayTitle(agentTitle: nil) == "Fix build")
        #expect(state.request == nil && state.progress == nil)
    }

    @Test(
        "A restored pending refinement is retired",
        arguments: [SessionTitleState.Progress.waitingForClient, .generating, .failed])
    func restoredRefinement(progress: SessionTitleState.Progress) {
        var state = SessionTitleState(
            generated: "Fix build", request: request, progress: progress,
            refinementCount: 1, firstTurnFinished: true)
        #expect(state.request == nil && state.progress == nil)
        #expect(state.refinementCount == 1 && state.firstTurnFinished)
        let refinementIgnored = !state.accept(generated: "Fix SessionModel isolation", revision: 1)
        #expect(refinementIgnored)
        #expect(state.displayTitle(agentTitle: nil) == "Fix build")
    }

    @Test("A pre-refinement store's manual title also blocks refinement after undo")
    func restoredRename() {
        var state = SessionTitleState(user: "Mine", generated: "Fix build", request: request)
        state.rename(to: nil)
        state.finishFirstTurn(outcome: outcome)
        #expect(state.wasRenamed && state.refinementCount == 0)
        let refinementIgnored = !state.accept(generated: "Fix SessionModel isolation", revision: 1)
        #expect(refinementIgnored)
        #expect(state.generated == "Fix build")
    }

    @Test(
        "Generic categories are weak even when they fit the word limit",
        arguments: ["Run shell command", "Update docs", "Improve performance", "Fix memory leak", "Fix failing test"])
    func genericCategories(title: String) {
        #expect(SessionTitleRules.isWeak(title))
    }

    @Test("Empty outcomes and later turns do not create a refinement")
    func emptyOutcome() {
        var state = SessionTitleState()
        state.begin(request)
        state.accept(generated: "Fix build")
        state.finishFirstTurn(outcome: "")
        state.finishFirstTurn(outcome: outcome)
        #expect(state.refinementCount == 0 && state.generated == "Fix build")
    }

    @Test("Pasted secrets and locations cannot enter titles or disambiguating suffixes")
    func privacy() {
        let text =
            "Authorization: Bearer fixture-secret\napi_key=fixture_secret\nFix /Users/fixture/private/release.py after https://example.invalid/private"
        let prepared = SessionTitleInput.prepared(text)
        #expect(!prepared.contains("fixture") && !prepared.contains("/Users") && !prepared.contains("https:"))
        #expect(prepared.contains("release.py"))
        #expect(!SessionTitleInput.isSafeTitle("Fix /Users/fixture/private/release.py"))
        #expect(SessionTitleInput.isSafeTitle("Fix release.py"))
        let distinct = SessionTitleRules.distinct("Fix build", from: ["Fix build"], prompt: text)
        #expect(!distinct.contains("fixture") && !distinct.contains("/Users"))
    }

    @Test("A verbose answer falls back to a complete short phrase")
    func verboseAnswer() {
        let request = SessionTitleRequest(
            projectName: "dashboard",
            prompt: "The search box drops focus after each keystroke. Fix it in the React customer list.")
        let title = SessionTitleRules.automatic("Fix search box focus loss in React customer list", from: request)
        #expect(title == "The search box drops focus")
    }

    @Test("Credential assignments, quoted passphrases and private-key blocks are removed locally")
    func credentialFormats() {
        let text = """
            AWS_ACCESS_KEY_ID=AKIA0000000000000000
            DB_PASSWORD="synthetic multi word passphrase"
            -----BEGIN PRIVATE KEY-----
            synthetic key material
            -----END PRIVATE KEY-----
            Fix payment header logging
            """
        #expect(SessionTitleInput.prepared(text) == "Fix payment header logging")
        #expect(!SessionTitleInput.isSafeTitle("Use AKIA0000000000000000"))
    }

    @Test("A request after a long log is retained, bounded and treated as context")
    func longLog() {
        let text = String(repeating: "error at fixture\n", count: 500) + "Fix checkout discounts"
        let prepared = SessionTitleInput.prepared(text)
        #expect(prepared.count <= 2_000 && prepared.hasSuffix("Fix checkout discounts"))
        let request = SessionTitleRequest(projectName: "shop", prompt: text, firstTurnOutcome: "Fixed checkout state")
        #expect(request.modelPrompt.contains("Fix checkout discounts"))
        #expect(request.modelPrompt.contains("First turn outcome (context only)"))
    }
}
