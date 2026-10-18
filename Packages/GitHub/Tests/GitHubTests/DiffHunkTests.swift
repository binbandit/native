import Testing

@testable import GitHub

struct DiffHunkTests {
    let patch = """
        @@ -10,6 +10,7 @@ func run() error {
         	a := 1
        -	b := 2
        +	b := 3
        +	c := 4
         	return nil
        \\ No newline at end of file
        @@ -40,2 +41,2 @@
        -old
        +new
        """

    @Test func numbersEachSide() throws {
        let hunks = DiffHunk.parse(patch)
        #expect(hunks.count == 2)
        let first = try #require(hunks.first)
        #expect(first.section == "func run() error {")
        #expect(first.lines.map(\.kind) == [.context, .removed, .added, .added, .context, .noNewline])
        #expect(first.lines[0].oldNumber == 10)
        #expect(first.lines[0].newNumber == 10)
        #expect(first.lines[1].oldNumber == 11)
        #expect(first.lines[1].newNumber == nil)
        #expect(first.lines[2].newNumber == 11)
        #expect(first.lines[3].newNumber == 12)
        #expect(first.lines[4].oldNumber == 12)
        #expect(first.lines[4].newNumber == 13)
        #expect(first.lines[2].text == "\tb := 3")
        #expect(hunks[1].newStart == 41)
        #expect(hunks[1].lines[1].newNumber == 41)
    }

    @Test func anchorsPickTheSide() throws {
        let hunk = try #require(DiffHunk.parse(patch).first)
        #expect(hunk.lines[1].anchor?.side == .left)
        #expect(hunk.lines[1].anchor?.line == 11)
        #expect(hunk.lines[2].anchor?.side == .right)
        #expect(hunk.lines[5].anchor == nil)
        #expect(hunk.index(side: .left, line: 11) == 1)
        #expect(hunk.index(side: .right, line: 12) == 3)
        #expect(hunk.index(side: .right, line: 99) == nil)
    }

    @Test func excerptKeepsMarkers() throws {
        let hunk = try #require(DiffHunk.parse(patch).first)
        #expect(hunk.excerpt(1...2) == "-\tb := 2\n+\tb := 3")
    }

    @Test func malformedHeaderStopsTheParse() {
        #expect(DiffHunk.parse("@@ nonsense @@\n+a").isEmpty)
        #expect(DiffHunk.parse("").isEmpty)
    }

    @Test func singleLineRangesAreNotRanges() {
        let anchor = ReviewAnchor(
            path: "a.swift", side: .right, line: 4, startLine: 4, startSide: .right)
        #expect(anchor.startLine == nil)
        #expect(anchor.lineDescription == "line 4")
        #expect(
            ReviewAnchor(path: "a", side: .right, line: 9, startLine: 7).lineDescription == "lines 7–9")
    }

    @Test func generatedFiles() {
        #expect(GeneratedFiles.isGenerated("package-lock.json"))
        #expect(GeneratedFiles.isGenerated("web/yarn.lock"))
        #expect(GeneratedFiles.isGenerated("Sources/App/Model.generated.swift"))
        #expect(GeneratedFiles.isGenerated("app/dist/bundle.js"))
        #expect(GeneratedFiles.isGenerated("native.xcodeproj/project.pbxproj"))
        #expect(!GeneratedFiles.isGenerated("Sources/App/Model.swift"))
        #expect(!GeneratedFiles.isGenerated("distance.go"))
    }

    @Test func missingPatches() {
        #expect(
            FilePatch(path: "logo.png", status: "added", additions: 0, deletions: 0, patch: nil)
                .missingPatchReason == .binary)
        #expect(
            FilePatch(path: "big.json", status: "modified", additions: 9000, deletions: 3, patch: nil)
                .missingPatchReason == .tooLarge)
        #expect(
            FilePatch(
                path: "b.swift", previousPath: "a.swift", status: "renamed", additions: 0, deletions: 0,
                patch: nil
            )
            .missingPatchReason == .renamedOnly)
    }

    @Test func suggestions() {
        let body = "Prefer a constant:\n```suggestion\nlet b = 3\n```\nThanks!"
        #expect(
            SuggestionBlock.segments(of: body) == [
                .markdown("Prefer a constant:"), .suggestion("let b = 3"), .markdown("Thanks!"),
            ])
        #expect(SuggestionBlock.segments(of: "````suggestion\n````") == [.suggestion("")])
        #expect(
            SuggestionBlock.segments(of: "```swift\nlet a = 1\n```") == [
                .markdown("```swift\nlet a = 1\n```")
            ])
        #expect(SuggestionBlock.fence("x") == "```suggestion\nx\n```")
    }
}
