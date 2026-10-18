import Testing

@testable import GitHub

@Suite struct ReviewLineSelectionTests {
    // Lines 0-1 context, 2-3 removed, 4-6 added, 7 context, then "\ No newline".
    let hunk = DiffHunk.parse(
        """
        @@ -10,6 +10,7 @@ func run()
         let a = 1
         let b = 2
        -let c = 3
        -let d = 4
        +let c = 30
        +let d = 40
        +let e = 50
         return a
        \\ No newline at end of file
        """
    )[0]

    @Test func startsOnOneLine() throws {
        let selection = try #require(ReviewLineSelection(path: "a.swift", hunk: hunk, line: 4))
        #expect(selection.lines == 4...4)
        #expect(selection.anchor == ReviewAnchor(path: "a.swift", side: .right, line: 12))
        #expect(selection.limit == nil)
    }

    @Test func noCommentOnTheNoNewlineMarker() {
        #expect(ReviewLineSelection(path: "a.swift", hunk: hunk, line: 8) == nil)
    }

    @Test func extendsDownAndUpOnOneSide() throws {
        var selection = try #require(ReviewLineSelection(path: "a.swift", hunk: hunk, line: 4))
        selection.extend(to: 6)
        #expect(selection.lines == 4...6)
        #expect(selection.anchor == ReviewAnchor(path: "a.swift", side: .right, line: 14, startLine: 12))
        // Upward, it skips the removed lines between and reaches the context above them.
        selection.extend(to: 1)
        #expect(selection.lines == 1...4)
        #expect(selection.anchor == ReviewAnchor(path: "a.swift", side: .right, line: 12, startLine: 11))
        #expect(selection.limit == nil)
    }

    @Test func stopsAtTheOtherSide() throws {
        var selection = try #require(ReviewLineSelection(path: "a.swift", hunk: hunk, line: 5))
        selection.extend(to: 3)
        #expect(selection.lines == 4...5)
        #expect(selection.limit == .otherSide)
        // A removed line keeps to removed lines.
        var removed = try #require(ReviewLineSelection(path: "a.swift", hunk: hunk, line: 2))
        removed.extend(to: 3)
        #expect(removed.anchor == ReviewAnchor(path: "a.swift", side: .left, line: 13, startLine: 12, startSide: .left))
        removed.extend(to: 5)
        #expect(removed.lines == 2...3)
        #expect(removed.limit == .otherSide)
    }

    @Test func clampsToTheHunk() throws {
        var selection = try #require(ReviewLineSelection(path: "a.swift", hunk: hunk, line: 6))
        selection.extend(to: 40)
        #expect(selection.lines == 6...7)
        #expect(selection.limit == .hunkEdge)
        selection.extend(to: -3)
        #expect(selection.lines == 0...6)
        #expect(selection.limit == .hunkEdge)
    }

    @Test func pullingBackClearsTheLimitAndCancelsToOneLine() throws {
        var selection = try #require(ReviewLineSelection(path: "a.swift", hunk: hunk, line: 4))
        selection.extend(to: 40)
        selection.extend(to: 5)
        #expect(selection.limit == nil)
        selection.extend(to: 4)
        #expect(selection.lines == 4...4)
        #expect(selection.anchor.startLine == nil)
    }
}
