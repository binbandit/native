import Testing

@testable import SessionTitling

@Suite("Sentence case")
struct SentenceCaseTests {
    @Test(
        "Title Case becomes sentence case; sentence case stays",
        arguments: [
            ("Run Tests and Fix Failures", "Run tests and fix failures"),
            ("Add sentence to contributing", "Add sentence to contributing"),
            ("Add Follow-Up Queue for Steering", "Add follow-up queue for steering"),
            ("Fix Login Bug", "Fix login bug"),
            ("run tests and fix failures", "Run tests and fix failures"),
        ])
    func titleCase(title: String, expected: String) {
        #expect(SessionTitleRules.sentenceCase(title) == expected)
    }

    @Test(
        "Acronyms, mixed-case names, code, file names and well-known names keep their case",
        arguments: [
            ("Update README and API Docs", "Update README and API docs"),
            ("Fix `kt` Save in SwiftUI View", "Fix `kt` save in SwiftUI view"),
            ("iOS Build Fails on CI", "iOS build fails on CI"),
            ("Rename Main.swift to App.swift", "Rename Main.swift to App.swift"),
            ("Add Swift Package Support", "Add Swift package support"),
            ("Explain What I Changed", "Explain what I changed"),
        ])
    func keepsNames(title: String, expected: String) {
        #expect(SessionTitleRules.sentenceCase(title) == expected)
    }

    @Test("Words the first message capitalizes mid-sentence keep their capital; ones starting a sentence don't")
    func namesFromTheMessage() {
        let source = "The build broke on Linux after the Fastlane update. Then the tests hung"
        #expect(
            SessionTitleRules.sentenceCase("Fix Linux Build After Fastlane Update", keeping: source)
                == "Fix Linux build after Fastlane update")
        #expect(SessionTitleRules.sentenceCase("Then Fix the Tests", keeping: source) == "Then fix the tests")
    }

    @Test("Generated and agent titles are normalized; the user's never are")
    func whereItApplies() {
        var state = SessionTitleState()
        state.begin(SessionTitleRequest(projectName: "native", prompt: "make the Kite saves faster"))
        _ = state.accept(generated: "Speed Up Kite Saves")
        #expect(state.generated == "Speed up Kite saves")
        _ = state.rename(to: "Speed Up Kite Saves")
        #expect(state.displayTitle(agentTitle: nil) == "Speed Up Kite Saves")
        #expect(
            SessionTitleRules.display(user: nil, generated: nil, agent: "Run Tests and Fix Failures")
                == "Run tests and fix failures")
        #expect(SessionTitleRules.cleaned("iOS crash on launch.") == "iOS crash on launch")
    }
}
