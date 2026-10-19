import Foundation
import Testing

@testable import GitHub

/// What a private question about a pull request goes out with: a real pull request whole, and the
/// budget rules for ones too large to send.
struct AskContextTests {
    let reference = PullRequestReference(owner: "binbandit", name: "oh-fx", number: 952)

    /// cli/cli#14569 as gh returned it: the page query (eight files) and the REST patches of six.
    @Test func realPullRequestGoesWholeAsFarAsItLoaded() throws {
        let reference = PullRequestReference(owner: "cli", name: "cli", number: 14569)
        let page = try #require(
            try PullRequestPage.decode(Fixtures.data("pr-page-review-threads"), reference: reference))
        let patches = try Fixtures.decode([FilePatch].self, from: "pr-files")
        let source = PullRequestAskSource(
            page: page, files: page.files, patches: Dictionary(uniqueKeysWithValues: patches.map { ($0.path, $0) }))

        let context = PullRequestAskContext(source)

        #expect(context.inclusion.filesInDiff == 6)
        #expect(context.inclusion.threads == 14)
        #expect(
            context.inclusion.leftOut == ["Native didn't load the diffs of 2 files; the agent can ask gh for them."])
        #expect(context.text.hasPrefix("# cli/cli#14569: \(page.title)"))
        #expect(context.text.contains("## Review threads (14, 1 unresolved)"))
        #expect(
            context.text.contains(
                "diff --git a/pkg/cmd/issue/artifact/artifact.go b/pkg/cmd/issue/artifact/artifact.go"))
        #expect(context.text.contains("@BagToad"))
        let paths = context.workspace.map(\.path)
        #expect(paths.prefix(2) == ["PULL_REQUEST.md", "changes.diff"])
        #expect(paths.contains("diff/pkg/cmd/issue/artifact/shared/shared.go.diff"))
        #expect(paths.count == 8)
    }

    @Test func smallPullRequestSummarySaysItsAll() {
        let source = source(
            files: [file("a.swift", lines: 3), file("b.swift", lines: 2)],
            comments: [comment("Looks close"), comment("Rebased")],
            threads: [thread("a.swift")])

        let context = PullRequestAskContext(source)

        #expect(context.inclusion.isWhole)
        #expect(
            context.inclusion.summary
                == "The description, 2 comments, 1 review thread and the whole diff (2 files, +5 -5).")
        #expect(context.inclusion.leftOut.isEmpty)
    }

    @Test func largeDiffSendsAnOutlineAndTheDiscussedFilesFirst() {
        var files = (0..<50).map { file("src/file\($0).swift", lines: 120) }
        files[40].path = "src/discussed.swift"
        let source = source(files: files, threads: [thread("src/discussed.swift")])

        let context = PullRequestAskContext(source, budget: budget(total: 30_000))

        let inline = context.inclusion.filesInDiff
        #expect(inline > 0 && inline < 50)
        #expect(context.text.contains("## Diff (\(inline) of the files; the rest are in `diff/` and `changes.diff`)"))
        // Every file is still named, with its size.
        #expect(context.text.contains("- `src/file49.swift` (modified, +120 -120)"))
        // The discussed file leads the diff, ahead of the ones listed before it.
        let diff = context.text.range(of: "## Diff").map { String(context.text[$0.lowerBound...]) } ?? ""
        #expect(
            diff.range(of: "src/discussed.swift").map {
                $0.lowerBound < (diff.range(of: "src/file0.swift")?.lowerBound ?? diff.endIndex)
            } == true)
        #expect(context.text.count <= 30_000 + 200)
        #expect(context.inclusion.summary.contains("the diff of \(inline) of 50 files"))
        #expect(context.inclusion.leftOut.contains { $0.hasPrefix("Diffs of \(50 - inline) files didn't fit") })
        // The saved copy has every diff.
        #expect(context.workspace.count == 2 + 50)
    }

    @Test func generatedAndOversizedDiffsWaitInTheSavedCopy() {
        let source = source(files: [
            file("package-lock.json", lines: 40), file("Huge.swift", lines: 900), file("Small.swift", lines: 30),
            file("Other.swift", lines: 600),
        ])

        let context = PullRequestAskContext(source, budget: budget(total: 40_000, filePatch: 20_000))

        let diff = context.text.range(of: "## Diff").map { String(context.text[$0.lowerBound...]) } ?? ""
        #expect(diff.contains("Small.swift"))
        #expect(!diff.contains("package-lock.json"))
        #expect(!diff.contains("Huge.swift"))
        #expect(context.text.contains("- `package-lock.json` (modified, +40 -40; generated)"))
        #expect(context.workspace.contains { $0.path == "diff/Huge.swift.diff" })
    }

    @Test func conversationKeepsTheNewestComments() {
        let comments = (1...20).map { comment("Comment \($0) " + String(repeating: "x", count: 900)) }
        let source = source(files: [file("a.swift", lines: 1)], comments: comments)

        let context = PullRequestAskContext(source, budget: budget(conversation: 5_000))

        #expect(context.inclusion.comments == 5)
        #expect(context.text.contains("(15 earlier comments are in PULL_REQUEST.md.)"))
        #expect(!context.text.contains("Comment 15 "))
        #expect(
            context.text.range(of: "Comment 16 ")?.lowerBound ?? context.text.endIndex
                < context.text.range(of: "Comment 20 ")?.lowerBound ?? context.text.startIndex)
        #expect(
            context.inclusion.leftOut.first == "15 earlier comments didn't fit; the agent has them in its saved copy.")
        let saved = context.workspace.first { $0.path == "PULL_REQUEST.md" }?.contents ?? ""
        #expect(saved.contains("Comment 1 ") && saved.contains("Comment 20 "))
    }

    @Test func longTextIsCutAtALineAndSaidSo() {
        let body = (1...400).map { "Line \($0) of a long description." }.joined(separator: "\n")
        var source = source(
            files: [file("a.swift", lines: 1)], comments: [comment(String(repeating: "y", count: 5_000))])
        source.body = body

        let context = PullRequestAskContext(source, budget: budget(description: 1_000, comment: 500))

        #expect(context.inclusion.descriptionTrimmed)
        #expect(context.inclusion.summary.hasPrefix("The start of the description, 1 comment"))
        #expect(context.text.contains("Line 1 of a long description.\n"))
        #expect(!context.text.contains("Line 400 of"))
        #expect(context.text.contains("[…truncated]"))
        let saved = context.workspace.first { $0.path == "PULL_REQUEST.md" }?.contents ?? ""
        #expect(saved.contains("Line 400 of"))
    }

    @Test func unresolvedThreadsComeFirstAndGoFirst() {
        let threads = [
            thread("resolved.swift", resolved: true, note: String(repeating: "r", count: 600)),
            thread("open.swift", note: String(repeating: "o", count: 600)),
        ]
        let source = source(files: [file("open.swift", lines: 1)], threads: threads)

        let context = PullRequestAskContext(source, budget: budget(threads: 800))

        #expect(context.inclusion.threads == 1)
        #expect(context.text.contains("### `open.swift:10` (unresolved)"))
        #expect(!context.text.contains("resolved.swift:10"))
        #expect(context.text.contains("(1 more thread didn't fit here; they're in PULL_REQUEST.md.)"))
    }

    @Test func filesWithoutADiffSayWhy() {
        let files = [
            file("logo.png", lines: 0, diff: .missing(.binary)),
            file("big.sql", lines: 9_000, diff: .missing(.tooLarge)),
            file("later.swift", lines: 4, diff: .notLoaded),
            file("a.swift", lines: 2),
        ]
        let context = PullRequestAskContext(source(files: files, filesTotal: 6))

        #expect(context.text.contains("- `logo.png` (modified, +0 -0; binary, no diff)"))
        #expect(context.text.contains("- `big.sql` (modified, +9000 -9000; GitHub doesn't show its diff (too large))"))
        #expect(context.text.contains("- `later.swift` (modified, +4 -4; diff not loaded)"))
        #expect(context.text.contains("- …and 2 more that Native didn't load"))
        #expect(
            context.inclusion.leftOut == [
                "Native didn't load the diffs of 3 files; the agent can ask gh for them."
            ])
        #expect(context.inclusion.summary.hasSuffix("the diff of 1 of 6 files (+9006 -9006)."))
    }

    @Test func savedPathsNeverLeaveTheFolder() {
        #expect(PullRequestAskWorkspaceFile.safePath("../../etc/passwd") == "etc/passwd")
        #expect(PullRequestAskWorkspaceFile.safePath("./src//a.swift") == "src/a.swift")
        #expect(PullRequestAskWorkspaceFile.safePath("/abs/x") == "abs/x")
        #expect(PullRequestAskWorkspaceFile.safePath("..") == nil)
    }

    @Test func fencesOutlastBackticksInside() {
        #expect(PullRequestAskContext.fenced("a\n````\nb", language: "diff") == "`````diff\na\n````\nb\n`````")
        #expect(PullRequestAskContext.fenced("plain", language: "diff") == "```diff\nplain\n```")
    }

    @Test func renamesAndAddsReadAsGitDiffs() {
        var renamed = file("new/name.swift", lines: 1)
        renamed.previousPath = "old/name.swift"
        renamed.changeType = .renamed
        var added = file("fresh.swift", lines: 1)
        added.changeType = .added

        #expect(
            PullRequestAskContext.diff(of: renamed).hasPrefix(
                "diff --git a/old/name.swift b/new/name.swift\n--- a/old/name.swift\n+++ b/new/name.swift\n@@"))
        #expect(
            PullRequestAskContext.diff(of: added).hasPrefix("diff --git a/fresh.swift b/fresh.swift\n--- /dev/null\n"))
    }

    // MARK: - Fixtures

    private func source(
        files: [PullRequestAskSource.File], comments: [PullRequestAskSource.Comment] = [],
        threads: [PullRequestAskSource.Thread] = [], filesTotal: Int? = nil
    ) -> PullRequestAskSource {
        PullRequestAskSource(
            reference: reference, title: "Keep generations pending", author: "binbandit", headRefName: "ai/pending",
            headRefOid: "0123456789abcdef0123456789abcdef01234567", body: "Why and how.", comments: comments,
            threads: threads, files: files, filesTotal: filesTotal)
    }

    private func file(
        _ path: String, lines: Int, diff: PullRequestAskSource.File.Diff? = nil
    ) -> PullRequestAskSource.File {
        let patch =
            "@@ -1,\(lines) +1,\(lines) @@\n"
            + (0..<lines).map { "-old line \($0) of \(path)\n+new line \($0) of \(path)" }.joined(separator: "\n")
        return PullRequestAskSource.File(path: path, additions: lines, deletions: lines, diff: diff ?? .patch(patch))
    }

    private func comment(_ body: String) -> PullRequestAskSource.Comment {
        PullRequestAskSource.Comment(author: "reviewer", body: body)
    }

    private func thread(
        _ path: String, resolved: Bool = false, note: String = "Is this right?"
    ) -> PullRequestAskSource.Thread {
        PullRequestAskSource.Thread(
            path: path, line: 10, isResolved: resolved, notes: [.init(author: "reviewer", body: note)])
    }

    private func budget(
        total: Int = 80_000, description: Int = 8_000, comment: Int = 3_000, conversation: Int = 16_000,
        threads: Int = 16_000, filePatch: Int = 16_000
    ) -> PullRequestAskContext.Budget {
        PullRequestAskContext.Budget(
            total: total, description: description, comment: comment, conversation: conversation, threadNote: 1_500,
            threads: threads, listedFiles: 300, filePatch: filePatch)
    }
}
