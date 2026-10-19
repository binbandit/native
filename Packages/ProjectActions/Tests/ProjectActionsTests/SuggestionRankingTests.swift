import Foundation
import Testing

@testable import ProjectActions

/// How suggestions from several ecosystems are ordered, deduplicated and hidden.
struct SuggestionRankingTests {
    private func mixed() throws -> [ProjectSuggestion] {
        let url = try #require(Bundle.module.url(forResource: "Fixtures/mixed", withExtension: nil))
        return ProjectDetector.suggestions(in: url)
    }

    @Test func ordersByRoleThenSource() throws {
        let visible = ProjectSuggestion.visible(try mixed(), existing: [], dismissed: [])
        #expect(
            visible.map(\.command) == [
                "bun install",
                // The justfile's own recipe comes before the ecosystems' for the same role.
                "just test", "bun run test", "cargo test",
                "bun run dev",
                "bun run build", "cargo build",
                "cargo clippy",
                "just fmt",
            ])
    }

    @Test func hidesWhatIsAlreadyAddedOrDismissed() throws {
        // Spacing doesn't make a different command.
        let added = ProjectAction(name: "Tests", command: "bun  run   test")
        let visible = ProjectSuggestion.visible(try mixed(), existing: [added], dismissed: ["cargo clippy"])
        #expect(!visible.contains { $0.command == "bun run test" })
        #expect(!visible.contains { $0.command == "cargo clippy" })
        #expect(visible.contains { $0.command == "cargo test" })
    }

    @Test func dropsTheSameCommandFoundTwice() {
        let detected = [
            ProjectSuggestion(name: "Test", command: "make test", role: .test, source: .makefile),
            ProjectSuggestion.named("test", command: "make  test", source: .makefile),
        ]
        #expect(ProjectSuggestion.visible(detected, existing: [], dismissed: []).count == 1)
    }

    @Test func addingNamesAroundExistingActions() {
        let existing = [ProjectAction(name: "Test", command: "just test")]
        let suggestion = ProjectSuggestion(name: "Test", command: "cargo test", role: .test, source: .cargo)
        let action = suggestion.action(among: existing)
        #expect(action.name == "Test 2")
        #expect(action.command == "cargo test" && action.icon == "checkmark.seal")
        #expect(!action.id.isFromRepository)
    }
}
