import Testing

@testable import ApprovalAnalysis

@Suite struct ApprovalAnalysisTests {
    private let cwd = "/Users/developer/Developer/native/worktrees/fix-stale-build"
    private let home = "/Users/developer"

    private func describe(_ command: String) -> ApprovalCommand {
        ApprovalCommand(command: command, workingDirectory: cwd, homeDirectory: home)
    }

    @Test func derivedDataIsRoutine() {
        let analysis = describe("rm -rf ~/Library/Developer/Xcode/DerivedData/native-bfhqjzxkdyowmrtglcaevpsnui")
        #expect(analysis.risk == .routine)
        #expect(analysis.parts.count == 3)
        #expect(analysis.parts.last?.explanation.contains("outside") == true)
        #expect(analysis.consequence.hasPrefix("Rebuilt on the next build."))
    }

    @Test(arguments: [
        "git push --force origin main", "git push -f origin main", "git push --force-with-lease origin main",
        "git push origin main --force",
    ])
    func remoteHistoryRequiresHold(_ command: String) {
        #expect(describe(command).risk == .irreversible)
    }

    @Test func fixItPreservesExactWhitespace() {
        let command = "git  push --force origin main"
        let analysis = describe(command)
        #expect(analysis.command == command)
        #expect(analysis.suggestedCommand == "git  push --force-with-lease origin main")
        #expect(
            analysis.parts.map { String(Array(command)[$0.range]) } == ["git  push", "--force", "origin main"])
        #expect(describe("git push origin main").risk == .routine)
    }

    @Test(arguments: [
        "./tools/acp-schema-gen --lang swift --strict --out Packages/ACP/Sources/ACP/Generated schema/v2.json",
        "git push --force origin main && rm -rf ~/Developer/native",
        "git push --force origin main; echo done", "git push --force origin main\nrm -rf /tmp/stuff",
        "sudo rm -rf /tmp/stuff", "rm -rf $(pwd)", "rm -rf ~/Library/Developer/Xcode/DerivedData/*",
        "rm -rf \"$HOME/Library/Developer/Xcode/DerivedData/native\"", "git -C other push -f origin main",
        "git push origin +main", "git push --mirror origin", "git push --force origin HEAD:main",
        "rm -rf 'unclosed", "rm -rf '~/Library/Developer/Xcode/DerivedData/native'",
    ])
    func unknownMakesNoClaims(_ command: String) {
        let analysis = describe(command)
        #expect(analysis.risk == .unknown)
        #expect(analysis.parts.isEmpty)
        #expect(analysis.suggestedCommand == nil)
        #expect(analysis.command == command)
    }

    @Test(arguments: [
        "rm -rf ~/Developer/native/Packages/ACP", "rm -rf Packages/ACP",
        "rm -rf ~/Library/Developer/Xcode/DerivedData/../../Source",
        "rm -rf ~/Library/Developer/Xcode/DerivedData/native ~/Developer/native/Packages/ACP",
        "rm -rf ~/Library/Developer/Xcode/DerivedData",
    ])
    func sourceDeletionRequiresHold(_ command: String) {
        #expect(describe(command).risk == .irreversible)
    }

    @Test func quotedPathAndPrefixBoundary() {
        let analysis = describe("rm -rf '/Users/developer/Developer/native/worktrees/fix-stale-build-copy/file name'")
        #expect(analysis.parts.last?.explanation.contains("outside") == true)
        #expect(describe("rm -rf Packages/ACP").parts.last?.explanation.contains("inside") == true)
    }

    @Test func commandDirectoryIsNotTheWorktree() {
        let analysis = ApprovalCommand(
            command: "rm -rf Packages/ACP", workingDirectory: "/Users/developer/Developer/native",
            worktreeDirectory: cwd, homeDirectory: home)
        #expect(analysis.parts.last?.explanation.contains("outside") == true)
    }

    @Test func earlyReleaseAndRepeatedKeysDoNotAllow() {
        var hold = ApprovalHold()
        hold.begin(at: 0)
        hold.begin(at: 0.3)
        #expect(hold.progress(at: 0.3) == 0.5)
        let result1 = !hold.advance(to: 0.59)
        #expect(result1)
        hold.cancel()
        let result2 = !hold.advance(to: 1)
        #expect(result2)
        #expect(hold.state == .idle)
        hold.begin(at: 2)
        let result3 = hold.advance(to: 2.61)
        #expect(result3)
        let result4 = !hold.advance(to: 3)
        #expect(result4)
        hold.cancel()
        #expect(hold.state == .allowed(at: 2.61))
    }

    @Test func accessibleConfirmationExpiresAndOnlyAnswersOnce() {
        var hold = ApprovalHold()
        let result5 = !hold.accessibleActivate(at: 0)
        #expect(result5)
        let result6 = !hold.accessibleActivate(at: 5)
        #expect(result6)
        let result7 = hold.accessibleActivate(at: 6)
        #expect(result7)
        let result8 = !hold.accessibleActivate(at: 6.1)
        #expect(result8)
        var expiring = ApprovalHold()
        let result9 = !expiring.accessibleActivate(at: 0)
        #expect(result9)
        let result10 = !expiring.advance(to: 5)
        #expect(result10)
        #expect(expiring.state == .idle)
    }
}
