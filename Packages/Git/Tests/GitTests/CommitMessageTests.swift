import Foundation
@testable import Git
import Testing

@Suite("Commit message helpers")
struct CommitMessageTests {
    @Test func detectsConventionalHistoryAndScopes() {
        let style = CommitStyle(subjects: [
            "feat(web): new threads no longer spike CPU",
            "fix(web): keep scroll position",
            "fix(composer)!: drop legacy shortcuts",
            "chore: bump deps",
            "Merge branch 'main'",
        ])
        #expect(style.isConventional)
        #expect(style.commonScopes == ["web", "composer"])
        #expect(style.examples.count == 5)
    }

    @Test func freeformHistoryStaysFreeform() {
        let style = CommitStyle(subjects: ["Add sidebar", "Fix: typo in README", "Update docs", "Refactor model"])
        #expect(!style.isConventional)
    }

    @Test func emptyHistoryDefaultsToConventional() {
        #expect(CommitStyle(subjects: []).isConventional)
    }

    @Test func trimmingDropsNoiseAndKeepsEveryFile() {
        let big = (1...200).map { "+line \($0)" }.joined(separator: "\n")
        let patch = """
        diff --git a/small.txt b/small.txt
        index 123..456 100644
        --- a/small.txt
        +++ b/small.txt
        @@ -1 +1 @@
        -old
        +new
        diff --git a/big.txt b/big.txt
        new file mode 100644
        --- /dev/null
        +++ b/big.txt
        @@ -0,0 +1,200 @@
        \(big)

        """

        let trimmed = PatchTrimmer.trim(patch, toCharacters: 400)

        #expect(trimmed.count <= 400 + 30)
        #expect(trimmed.contains("diff --git a/small.txt b/small.txt\n@@ -1 +1 @@\n-old\n+new\n"))
        #expect(trimmed.contains("diff --git a/big.txt b/big.txt"))
        #expect(trimmed.contains("more lines]"))
        #expect(!trimmed.contains("index 123"))
        #expect(!trimmed.contains("+++ b/"))
    }

    @Test func smallPatchesOnlyLoseNoise() {
        let patch = "diff --git a/a b/a\nindex 1..2 100644\n--- a/a\n+++ b/a\n@@ -1 +1 @@\n-x\n+y\n"
        #expect(PatchTrimmer.trim(patch, toCharacters: 10_000) == "diff --git a/a b/a\n@@ -1 +1 @@\n-x\n+y\n")
    }
}
