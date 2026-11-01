import Foundation
import Testing

@testable import SessionTitling

@Suite("Title refinement")
struct TitleRefinementTests {
    let request = SessionTitleRequest(projectName: "native", prompt: "fix the build")
    let outcome = "Fixed actor isolation in SessionModel"

    @Test("A weak title gets one refinement, and late answers cannot replace it")
    func onceOnly() {
        var state = SessionTitleState()
        state.begin(request)
        let accepted1 = state.accept(generated: "Fix build")
        #expect(accepted1)
        state.finishFirstTurn(outcome: outcome)
        #expect(state.refinementCount == 1)
        #expect(state.request?.firstTurnOutcome == outcome)
        let accepted2 = !state.accept(generated: "Late initial answer")
        #expect(accepted2)
        let accepted3 = state.accept(generated: "Fix SessionModel isolation", revision: 1)
        #expect(accepted3)
        let accepted4 = !state.accept(generated: "Another title", revision: 1)
        #expect(accepted4)
        state.finishFirstTurn(outcome: "Something else")
        #expect(state.generated == "Fix SessionModel isolation")
        #expect(state.request == nil)
    }

    @Test("A first turn that finishes before the title still refines once")
    func slowInitial() {
        var state = SessionTitleState()
        state.begin(request)
        state.finishFirstTurn(outcome: outcome)
        #expect(state.refinementCount == 0)
        let accepted5 = state.accept(generated: "Fix build")
        #expect(accepted5)
        #expect(state.refinementCount == 1 && state.progress == .generating)
    }

    @Test("A specific initial title stays, and a weak refinement never replaces a weak title")
    func qualityGate() {
        var state = SessionTitleState()
        state.begin(SessionTitleRequest(projectName: "native", prompt: "Fix SessionModel isolation"))
        state.accept(generated: "Fix SessionModel isolation")
        state.finishFirstTurn(outcome: outcome)
        #expect(state.refinementCount == 0 && state.request == nil)
        var weak = SessionTitleState()
        weak.begin(request)
        weak.accept(generated: "Fix build")
        weak.finishFirstTurn(outcome: outcome)
        let accepted6 = weak.accept(generated: "Fix tests", revision: 1)
        #expect(accepted6)
        #expect(weak.generated == "Fix build" && weak.request == nil)
        let accepted7 = !weak.accept(generated: "Fix SessionModel isolation", revision: 1)
        #expect(accepted7)
    }

    @Test("A manual rename and its undo block automatic refinement", arguments: [false, true])
    func manualRename(beforeOutcome: Bool) {
        var state = SessionTitleState()
        state.begin(request)
        state.accept(generated: "Fix build")
        if beforeOutcome { state.rename(to: "Mine") }
        state.finishFirstTurn(outcome: outcome)
        if !beforeOutcome { state.rename(to: "Mine") }
        state.rename(to: nil)
        let accepted8 = !state.accept(generated: "Fix SessionModel isolation", revision: 1)
        #expect(accepted8)
        #expect(state.generated == "Fix build")
    }

    @Test("A pre-refinement store's manual title also blocks refinement after undo")
    func restoredRename() {
        var state = SessionTitleState(user: "Mine", generated: "Fix build", request: request)
        state.rename(to: nil)
        state.finishFirstTurn(outcome: outcome)
        #expect(state.wasRenamed && state.refinementCount == 0)
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
