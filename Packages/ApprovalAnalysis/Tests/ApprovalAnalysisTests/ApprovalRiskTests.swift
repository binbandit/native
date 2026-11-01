import Testing

@testable import ApprovalAnalysis

/// Which asks hold. Command lines are the ones agents sent in real sessions (Claude Code's Bash tool
/// and Codex's shell), so a routine day of building and pushing never asks for a hold.
@Suite struct ApprovalRiskTests {
    private let worktree = "/Users/developer/.native/worktrees/native/fix-flaky-tests"

    private func describe(_ command: String) -> ApprovalCommand {
        ApprovalCommand(command: command, workingDirectory: worktree, homeDirectory: "/Users/developer")
    }

    @Test(arguments: [
        "swift test --package-path Packages/ACP --filter PermissionRequestTests", "swift test", "swift build",
        "swift test --filter ChildApprovalTests", "npm test", "pnpm build", "cargo test --workspace",
        "git push origin fix/flaky-tests", "git push -u origin fix/flaky-tests", "git push",
        "git commit -m 'fix(acp): wait for the permission reply'", "git add -A", "git switch -c fix/flaky-tests",
        "git fetch --prune origin", "git pull --rebase origin main", "git reset HEAD~1",
    ])
    func everydayWorkIsRoutine(_ command: String) {
        let analysis = describe(command)
        #expect(analysis.risk == .routine, "\(command)")
        #expect(!analysis.consequence.localizedCaseInsensitiveContains("not been inspected"))
        #expect(!analysis.consequence.localizedCaseInsensitiveContains("cannot undo"))
    }

    @Test func testsSayWhereTheyStay() {
        let analysis = describe("swift test --package-path Packages/ACP --filter PermissionRequestTests")
        #expect(analysis.consequence == "Runs from the worktree. Builds and executes project code.")
        #expect(analysis.parts.allSatisfy { !$0.destructive })
        let outside = ApprovalCommand(
            command: "swift test", workingDirectory: "/Users/developer/Developer/kite", worktreeDirectory: worktree)
        #expect(outside.consequence == "Runs from kite. Builds and executes project code.")
    }

    @Test(arguments: [
        "git push --force origin main", "git push -f origin main", "git push --force-with-lease origin main",
        "git push origin +main", "git push origin :old-topic", "git push --delete origin old-topic",
        "rm -rf ~/Developer/native/Packages/ACP", "rm -rf build", "git reset --hard origin/main", "git clean -fdx",
        "git branch -D old-topic", "git stash drop", "npm publish", "cargo publish", "gh pr merge 42 --squash",
        "kill -9 4242", "sudo rm /etc/hosts",
        "docker rmi local-only-image", "docker compose down", "docker rm stopped-container",
    ])
    func irreversibleWorkHolds(_ command: String) {
        #expect(describe(command).risk == .irreversible, "\(command)")
    }

    @Test func onlyTheForceIsMarked() {
        let command = "git push --force origin main"
        let analysis = describe(command)
        let marked = analysis.parts.filter(\.destructive).map { String(Array(command)[$0.range]) }
        #expect(marked == ["--force"])
        #expect(
            analysis.consequence == "Can't be undone from here. Commits it replaces may survive in other clones.")
        #expect(analysis.headline == "overwrite refs on origin")
        #expect(describe("git push origin +main").parts.filter(\.destructive).count == 1)
    }

    @Test(arguments: [
        "./tools/acp-schema-gen --lang swift --strict --out Packages/ACP/Sources/ACP/Generated schema/v2.json",
        "internal-check --workspace .", "python3 -m unittest", "swift test && git push --force origin main",
        "git push --force origin main; echo done", "make -C build clean all 2>&1 | tail",
    ])
    func unknownCommandsMakeNoClaimsAndDoNotHold(_ command: String) {
        let analysis = describe(command)
        #expect(analysis.risk == .unknown)
        #expect(analysis.parts.isEmpty)
        #expect(analysis.consequence.contains("makes no claims"))
        #expect(!analysis.consequence.contains("undone"))
    }
}

@Suite struct GitPushTargetTests {
    private func target(_ command: String) -> GitPushTarget? {
        ApprovalCommand(command: command, workingDirectory: "/repo").pushTarget
    }

    @Test(arguments: [
        ("git push --force origin main", "overwrite refs on origin"),
        ("git push --force origin main:main", "overwrite main on origin"),
        ("git push origin +main", "overwrite refs on origin"),
        ("git push origin HEAD:refs/heads/release", "push release to origin"),
        ("git push origin :old-topic", "delete old-topic on origin"),
        ("git push --delete origin old-topic", "delete old-topic on origin"),
        ("git push -u origin fix/flaky", "push commits to origin"),
        ("git push --force", "overwrite refs on its remote"),
        ("git push origin", "push commits to origin"),
    ])
    func headlineNamesTheConsequence(command: String, headline: String) {
        #expect(target(command)?.headline(place: nil) == headline)
    }

    @Test func placeAndMarkingReplaceTheRemoteName() {
        let force = target("git push --force origin main:main")
        #expect(force?.headline(place: "github.com", marking: { "`\($0)`" }) == "overwrite `main` on github.com")
        #expect(force?.source == "main")
        #expect(target("git push origin HEAD:release")?.source == "HEAD")
        #expect(
            target("git push --force origin HEAD")?.headline(place: "github.com", destination: "feature")
                == "overwrite feature on github.com")
    }

    @Test(arguments: ["git push --all origin", "git push --tags", "git push --mirror origin", "git push origin a b"])
    func manyBranchesHaveNoTarget(_ command: String) {
        #expect(target(command) == nil)
    }

    @Test(arguments: ["git push --force origin HEAD", "git push --force origin main"])
    func sourceOnlyDestinationsNeedRepositoryContext(_ command: String) {
        #expect(target(command)?.branch == nil)
        #expect(target(command)?.source != nil)
    }

    @Test func targetIsOneAnnotation() {
        let command = "git push --force origin main"
        let analysis = ApprovalCommand(command: command, workingDirectory: "/repo")
        #expect(analysis.parts.map { String(Array(command)[$0.range]) } == ["git push", "--force", "origin main"])
        let described = analysis.describingPushTarget("main on github.com · binbandit/native")
        #expect(described.parts.last?.explanation == "main on github.com · binbandit/native")
    }
}
