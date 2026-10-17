import Testing

@testable import GitHub

struct DraftPromptTests {
    let commits = """
        a1b2c3d fix(ui): restore pointer cursor on alert dialog buttons

        Buttons in alert dialogs lost their pointer cursor after the theme refactor.
        """

    @Test func smallMaterialIsIncludedWhole() {
        let prompt = PullRequestDraftPrompt(
            head: "fix-button-cursors", base: "main", commits: commits, diff: "--- a/x\n+++ b/x\n+cursor: pointer;")
        let text = prompt.text(characterBudget: 4_000)

        #expect(text.hasPrefix("Branch: fix-button-cursors (into main)"))
        #expect(text.contains("Buttons in alert dialogs lost their pointer cursor"))
        #expect(text.contains("+cursor: pointer;"))
        #expect(!text.contains("truncated"))
    }

    @Test func largeDiffsAreCutToTheBudget() {
        let diff = (0..<5_000).map { "+line \($0)" }.joined(separator: "\n")
        let text = PullRequestDraftPrompt(head: "big", commits: commits, diff: diff).text(characterBudget: 3_000)

        #expect(text.count <= 3_000)
        #expect(text.contains("restore pointer cursor"))
        #expect(text.hasSuffix("[…truncated]"))
    }

    @Test func commitsGetTheWholeBudgetWithoutADiff() {
        let manyCommits = (0..<500).map { "abc\($0) change number \($0)" }.joined(separator: "\n")
        let text = PullRequestDraftPrompt(head: "h", commits: manyCommits).text(characterBudget: 2_000)

        #expect(text.count <= 2_000)
        #expect(text.count > 1_800)
        #expect(!text.contains("Diff:"))
    }

    @Test func trimCutsAtALineBreak() {
        #expect(PullRequestDraftPrompt.trim("one\ntwo\nthree", to: 100) == "one\ntwo\nthree")
        #expect(PullRequestDraftPrompt.trim("alpha\nbeta\ngamma delta epsilon", to: 25) == "alpha\nbeta\n[…truncated]")
    }

    @Test func templateIsPassedAlong() {
        let text = PullRequestDraftPrompt(head: "h", commits: "c", template: "## Summary\n\n## Testing").text(
            characterBudget: 2_000)
        #expect(text.contains("Follow this pull request template:\n## Summary"))
    }
}
