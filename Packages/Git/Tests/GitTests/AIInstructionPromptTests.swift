import AIInstructions
import Foundation
import Testing

@testable import Git

/// The user's AI instructions for branch names, commit messages and commit grouping: added after
/// Native's rules, which stay whole so what the model writes still parses.
@Suite("AI instructions in git prompts")
struct AIInstructionPromptTests {
    let conventional = CommitStyle(subjects: ["feat(web): add search", "fix(web): keep scroll"])

    // MARK: - Commit messages

    @Test func commitMessagesKeepTheRepositorysConventionAndAddTheUsers() throws {
        let addition = try #require(AIInstructionAddition("Write in the imperative, no emoji."))
        let text = CommitPrompts.message(style: conventional, adding: addition)
        let builtIn = CommitPrompts.message(style: conventional, adding: nil)

        #expect(text.hasPrefix(builtIn))
        #expect(builtIn.contains("Subjects use Conventional Commits: \"type(scope): summary\""))
        #expect(builtIn.contains("Scopes this repository uses: web."))
        #expect(builtIn.contains("Never invent details."))
        #expect(text.hasSuffix("<user_instructions>\nWrite in the imperative, no emoji.\n</user_instructions>"))
    }

    @Test func freeformRepositoriesStayFreeform() {
        let text = CommitPrompts.message(style: CommitStyle(subjects: ["Add sidebar", "Update docs"]), adding: nil)
        #expect(text.contains("no type prefix"))
        #expect(!text.contains("Conventional Commits"))
    }

    // MARK: - Smart commits

    @Test func commitPlansTakeBothTheMessageAndGroupingInstructions() throws {
        let messages = try #require(AIInstructionAddition("Past tense."))
        let grouping = try #require(AIInstructionAddition("Keep migrations in their own commit."))
        let text = CommitPrompts.plan(style: conventional, messages: messages, grouping: grouping)
        let builtIn = CommitPrompts.plan(style: conventional, messages: nil, grouping: nil)

        #expect(text.hasPrefix(builtIn))
        #expect(builtIn.contains("Every file goes in exactly one commit."))
        #expect(builtIn.contains("Subjects use Conventional Commits"))
        let messageRange = try #require(text.range(of: "about commit messages."))
        let groupingRange = try #require(text.range(of: "about how to split the changes."))
        #expect(messageRange.upperBound < groupingRange.lowerBound)
        #expect(text.contains("Past tense."))
        #expect(text.hasSuffix("Keep migrations in their own commit.\n</user_instructions>"))
    }

    // MARK: - Branch names

    @Test func branchInstructionsKeepTheRequiredCharactersAndTheConfiguredPrefix() throws {
        let addition = try #require(AIInstructionAddition("Prefix with brayden/ and use under 4 words."))
        let text = BranchNaming.suggestionInstructions(prefix: "binbandit/", adding: addition)

        #expect(text.hasPrefix(BranchNaming.suggestionInstructions(prefix: "binbandit/", adding: nil)))
        #expect(text.contains("Required: only ASCII letters, digits, hyphens, and slashes between parts."))
        #expect(text.contains("start with binbandit/, then"))
        #expect(text.contains("Prefix with brayden/ and use under 4 words."))
        #expect(!BranchNaming.suggestionInstructions(prefix: "", adding: nil).contains("start with"))
    }

    @Test(arguments: [
        ("brayden/add-dark-mode", "brayden/add-dark-mode"),
        ("`ABC-123-fix-login`", "ABC-123-fix-login"),
        ("Branch: Fix the login page!", "Branch-Fix-the-login-page"),
        ("refs/heads/team//x..y.lock", "team/x.y"),
        ("feature/naïve café\nmore text", "feature/na-ve-caf"),
        ("--/..//", nil),
    ])
    func suggestionsBecomeNamesGitAccepts(suggestion: String, name: String?) {
        #expect(BranchNaming.name(fromSuggestion: suggestion) == name)
    }

    @Test func longSuggestionsAreCapped() throws {
        let name = try #require(BranchNaming.name(fromSuggestion: String(repeating: "word-", count: 40)))
        #expect(name.count <= BranchNaming.suggestionLimit)
        #expect(!name.hasSuffix("-"))
    }

    @Test func renamesAProvisionalBranchToASuggestedName() async throws {
        let test = try await TestRepository.make()
        defer { test.remove() }
        let repository = try await test.repository
        try await repository.createAndSwitchBranch("binbandit/ab3c4")
        try await repository.markProvisional("binbandit/ab3c4")

        #expect(try await repository.isRenamableProvisional("binbandit/ab3c4"))
        let renamed = try await repository.renameProvisionalBranch("binbandit/ab3c4", to: "brayden/add-dark-mode")

        #expect(renamed == "brayden/add-dark-mode")
        #expect(try await repository.isRenamableProvisional("brayden/add-dark-mode") == false)
    }
}
