import Foundation
import Testing

@testable import Git

@Suite("Task branches, worktree setup and commit plans")
struct TaskWorkspaceTests {
    // MARK: - Naming

    @Test(arguments: [
        ("brayden", "brayden/"),
        ("/team//Brayden Ellis/", "team/brayden-ellis/"),
        ("", ""),
        ("//", ""),
    ])
    func normalizesPrefixes(raw: String, prefix: String) {
        #expect(BranchNaming.normalizedPrefix(raw) == prefix)
    }

    @Test func provisionalCodesEndInADigit() {
        for _ in 0..<50 {
            let code = BranchNaming.provisionalCode()
            #expect(code.count == 5)
            #expect(code.last?.isNumber == true)
            #expect(code.allSatisfy { $0.isLowercase || $0.isNumber })
        }
    }

    @Test func patternsMatchLikeGitignore() {
        let patterns = FilePatterns(patterns: [".env*", "config/*.json"])
        #expect(patterns.matches(".env"))
        #expect(patterns.matches(".env.local"))
        #expect(patterns.matches("apps/web/.env.development"))
        #expect(patterns.matches("config/secrets.json"))
        #expect(!patterns.matches("apps/config/secrets.json"))
        #expect(!patterns.matches("environment.ts"))
    }

    // MARK: - Provisional branches

    @Test func renamesAProvisionalBranchFromTheTitle() async throws {
        let test = try await TestRepository.make()
        defer { test.remove() }
        let repository = try await test.repository
        try await test.git("branch", "brayden/fix-login-bug")

        let provisional = try await repository.uniqueBranchName("brayden/" + "ab3c4")
        try await repository.createAndSwitchBranch(provisional)
        try await repository.markProvisional(provisional)
        #expect(try await repository.isProvisional(provisional))

        let renamed = try await repository.renameProvisionalBranch(provisional, title: "Fix login bug")

        #expect(renamed == "brayden/fix-login-bug-2")
        #expect(try await repository.status().branch.name == "brayden/fix-login-bug-2")
        // Renamed once; later titles leave it alone.
        #expect(try await repository.isProvisional("brayden/fix-login-bug-2") == false)
        #expect(try await repository.renameProvisionalBranch("brayden/fix-login-bug-2", title: "Other") == nil)
    }

    @Test func leavesPushedOrUnmarkedBranchesAlone() async throws {
        let test = try await TestRepository.make()
        defer { test.remove() }
        let repository = try await test.repository
        try await repository.createAndSwitchBranch("mine")
        #expect(try await repository.renameProvisionalBranch("mine", title: "Anything") == nil)

        let remote = test.folder.deletingLastPathComponent().appending(path: "origin.git", directoryHint: .isDirectory)
        try await test.git("init", "--quiet", "--bare", "--initial-branch=main", remote.path(percentEncoded: false))
        try await test.git("remote", "add", "origin", remote.path(percentEncoded: false))
        try await repository.createAndSwitchBranch("pq7r2")
        try await repository.markProvisional("pq7r2")
        try await repository.push()

        #expect(try await repository.isPublished("pq7r2"))
        #expect(try await repository.renameProvisionalBranch("pq7r2", title: "Too late") == nil)
    }

    @Test func archivesAndRestoresBranches() async throws {
        let test = try await TestRepository.make()
        defer { test.remove() }
        let repository = try await test.repository
        try await test.git("checkout", "--quiet", "-b", "work")
        try test.write("work.txt", "work\n")
        try await repository.commit(message: "Work", files: try await repository.status().changes)
        let tip = try await test.git("rev-parse", "work")
        try await test.git("checkout", "--quiet", "main")

        let reference = try await repository.archiveBranch("work")

        #expect(reference == "refs/native-archived-branches/work")
        #expect(try await repository.branches(includingRemote: false).map(\.name) == ["main"])
        try await repository.restoreArchivedBranch("work")
        #expect(try await test.git("rev-parse", "work") == tip)
    }

    // MARK: - Worktree setup

    @Test func copiesIgnoredEnvFilesIntoANewWorktree() async throws {
        let test = try await TestRepository.make()
        defer { test.remove() }
        let repository = try await test.repository
        try test.write(".gitignore", ".env*\nnode_modules/\n")
        try await repository.commit(message: "Ignore", files: try await repository.status().changes)
        try test.write(".env", "SECRET=1\n")
        try test.write("apps/web/.env.local", "LOCAL=1\n")
        try test.write("node_modules/pkg/index.js", "x\n")
        let location = test.folder.deletingLastPathComponent().appending(path: "worktrees", directoryHint: .isDirectory)
        let worktree = try await repository.createWorktree(forTask: "Env", in: location)

        let copied = try await repository.copyIgnoredFiles(matching: [".env*"], to: worktree.path)

        #expect(Set(copied) == [".env", "apps/web/.env.local"])
        #expect(
            try String(contentsOf: worktree.path.appending(path: "apps/web/.env.local"), encoding: .utf8) == "LOCAL=1\n"
        )
        #expect(
            !FileManager.default.fileExists(
                atPath: worktree.path.appending(path: "node_modules").path(percentEncoded: false)))
    }

    @Test func runsSetupScriptsAndReportsFailuresAndTimeouts() async throws {
        let test = try await TestRepository.make()
        defer { test.remove() }
        let repository = try await test.repository

        let success = try await repository.runSetupScript(
            "echo \"setting up $NATIVE_WORKSPACE_NAME\"; pwd", environment: ["NATIVE_WORKSPACE_NAME": "demo"],
            timeout: .seconds(10))
        #expect(success.succeeded)
        #expect(success.output.contains("setting up demo"))
        #expect(success.output.contains(test.folder.lastPathComponent))

        let failure = try await repository.runSetupScript(
            "echo nope >&2; exit 3", environment: [:], timeout: .seconds(10))
        #expect(failure.exitCode == 3)
        #expect(failure.output.contains("nope"))

        let slow = try await repository.runSetupScript("sleep 5", environment: [:], timeout: .milliseconds(300))
        #expect(slow.timedOut)
    }

    // MARK: - Commit plans

    @Test func reconcilesAProposedPlanWithTheRealChanges() {
        let plan = CommitPlan.reconciling(
            [
                (message: "feat: parser", paths: ["Sources/Parser.swift", "Sources/Ghost.swift"]),
                (message: "test: parser", paths: ["Tests/ParserTests.swift", "Sources/Parser.swift"]),
                (message: "  ", paths: ["README.md"]),
            ],
            changedPaths: ["Sources/Parser.swift", "Tests/ParserTests.swift", "README.md", "Package.swift"],
            leftoverMessage: "chore: other changes"
        )

        #expect(plan.groups.map(\.message) == ["feat: parser", "test: parser", "chore: other changes"])
        #expect(
            plan.groups.map(\.paths) == [
                ["Sources/Parser.swift"], ["Tests/ParserTests.swift"], ["README.md", "Package.swift"],
            ])
    }

    @Test func groupsByTopLevelFolder() {
        let plan = CommitPlan.byFolder(["Sources/A.swift", "README.md", "Sources/B.swift", "Tests/T.swift"])
        #expect(
            plan.groups.map(\.paths) == [["Sources/A.swift", "Sources/B.swift"], ["README.md"], ["Tests/T.swift"]])
    }

    @Test func commitsAPlanInOrderAndUndoesIt() async throws {
        let test = try await TestRepository.make()
        defer { test.remove() }
        let repository = try await test.repository
        let before = try await test.git("rev-parse", "HEAD")
        try test.write("Sources/Parser.swift", "parse\n")
        try test.write("Tests/ParserTests.swift", "test\n")
        try test.write("notes.txt", "keep me uncommitted\n")
        try test.write("README.md", "# Staged\n")
        try await repository.stage(["README.md"])
        let changes = try await repository.status().changes
        let plan = CommitPlan(groups: [
            .init(message: "feat: parser", paths: ["Sources/Parser.swift", "README.md"]),
            .init(message: "test: parser tests", paths: ["Tests/ParserTests.swift"]),
        ])

        let (receipt, failure) = try await repository.commit(plan, changes: changes)

        #expect(failure == nil)
        #expect(receipt.commits.count == 2)
        #expect(try await repository.recentCommitSubjects(limit: 2) == ["test: parser tests", "feat: parser"])
        #expect(try await repository.status().untracked.map(\.path) == ["notes.txt"])

        try await repository.undo(receipt)

        #expect(try await test.git("rev-parse", "HEAD") == before)
        let status = try await repository.status()
        #expect(status.staged.map(\.path) == ["README.md"])
        #expect(Set(status.untracked.map(\.path)) == ["notes.txt", "Sources/Parser.swift", "Tests/ParserTests.swift"])
        #expect(try test.read("Sources/Parser.swift") == "parse\n")
    }

    @Test func refusesToUndoOnceTheBranchMoved() async throws {
        let test = try await TestRepository.make()
        defer { test.remove() }
        let repository = try await test.repository
        try test.write("a.txt", "a\n")
        let (receipt, _) = try await repository.commit(
            CommitPlan(groups: [.init(message: "A", paths: ["a.txt"])]), changes: try await repository.status().changes)
        try test.write("b.txt", "b\n")
        try await repository.commit(message: "B", files: try await repository.status().changes)

        await #expect(throws: GitError.self) { try await repository.undo(receipt) }
    }

    @Test func stopsAtAFailingCommitAndCanUndoWhatItMade() async throws {
        let test = try await TestRepository.make()
        defer { test.remove() }
        let repository = try await test.repository
        try test.write("a.txt", "a\n")
        try test.write("b.txt", "b\n")
        // A commit-msg hook that rejects the second message.
        try test.write(
            ".git/hooks/commit-msg", "#!/bin/sh\ngrep -q '^B' \"$1\" && { echo 'no B commits' >&2; exit 1; }\nexit 0\n")
        chmod(test.folder.appending(path: ".git/hooks/commit-msg").path(percentEncoded: false), 0o755)
        let plan = CommitPlan(groups: [.init(message: "A", paths: ["a.txt"]), .init(message: "B", paths: ["b.txt"])])

        let (receipt, failure) = try await repository.commit(plan, changes: try await repository.status().changes)

        #expect(receipt.commits.count == 1)
        #expect(failure?.failure == .hookFailed)
        try await repository.undo(receipt)
        #expect(Set(try await repository.status().untracked.map(\.path)) == ["a.txt", "b.txt"])
    }
}
