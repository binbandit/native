import Foundation
import Testing

@testable import Git

@Suite("Parsing git's -z output")
struct ParsingTests {
    @Test func statusHeadersAndEntries() throws {
        // Captured from `git status --porcelain=v2 --branch -z --untracked-files=all`.
        let output = [
            "# branch.oid 1f2e3d4c5b6a79881f2e3d4c5b6a79881f2e3d4c",
            "# branch.head feature/git",
            "# branch.upstream origin/feature/git",
            "# branch.ab +2 -1",
            "1 M. N... 100644 100644 100644 aaaaaaa bbbbbbb Sources/App.swift",
            "1 .M N... 100644 100644 100644 aaaaaaa aaaaaaa docs/read me.md",
            "1 MM N... 100644 100644 100644 aaaaaaa ccccccc both.txt",
            "2 R. N... 100644 100644 100644 aaaaaaa aaaaaaa R100 new name/Résumé ✓.txt",
            "old name/resume.txt",
            "u UU N... 100644 100644 100644 100644 aaaaaaa bbbbbbb ccccccc conflict.swift",
            "1 .D S... 160000 160000 000000 aaaaaaa aaaaaaa vendor/lib",
            "? untracked file 日本.txt",
            "",
        ].joined(separator: "\0")

        let (branch, changes) = try StatusParser.parse(output)

        #expect(branch.head == .branch("feature/git"))
        #expect(branch.commit == "1f2e3d4c5b6a79881f2e3d4c5b6a79881f2e3d4c")
        #expect(branch.upstream == "origin/feature/git")
        #expect(branch.ahead == 2)
        #expect(branch.behind == 1)
        #expect(!branch.isUpstreamGone)

        #expect(
            changes == [
                FileChange(path: "Sources/App.swift", kind: .modified, area: .staged),
                FileChange(path: "docs/read me.md", kind: .modified, area: .unstaged),
                FileChange(path: "both.txt", kind: .modified, area: .staged),
                FileChange(path: "both.txt", kind: .modified, area: .unstaged),
                FileChange(
                    path: "new name/Résumé ✓.txt", originalPath: "old name/resume.txt", kind: .renamed, area: .staged),
                FileChange(path: "conflict.swift", kind: .conflicted, area: .conflicted),
                FileChange(path: "vendor/lib", kind: .deleted, area: .unstaged, isSubmodule: true),
                FileChange(path: "untracked file 日本.txt", kind: .untracked, area: .untracked),
            ])
    }

    @Test func detachedUnbornAndGoneUpstream() throws {
        let detached = try StatusParser.parse("# branch.oid abcdef1234567\0# branch.head (detached)\0").branch
        #expect(detached.isDetached)
        #expect(detached.displayName == "abcdef1")

        let unborn = try StatusParser.parse("# branch.oid (initial)\0# branch.head main\0").branch
        #expect(unborn.isUnborn)
        #expect(unborn.name == "main")

        let gone = try StatusParser.parse("# branch.oid abc\0# branch.head topic\0# branch.upstream origin/topic\0")
            .branch
        #expect(gone.isUpstreamGone)
    }

    @Test func numstatWithRenamesBinariesAndOddPaths() {
        let output = [
            "3\t1\tSources/App.swift",
            "-\t-\tAssets/icon.png",
            "10\t0\t", "old dir/file.txt", "new dir/fïle with spaces.txt",
            "2\t2\tpath\twith tab.txt",
            "",
        ].joined(separator: "\0")

        let stats = NumstatParser.parse(output)

        #expect(stats["Sources/App.swift"] == LineStats(additions: 3, deletions: 1))
        #expect(stats["Assets/icon.png"] == LineStats(isBinary: true))
        #expect(stats["new dir/fïle with spaces.txt"] == LineStats(additions: 10))
        #expect(stats["old dir/file.txt"] == nil)
        #expect(stats["path\twith tab.txt"] == LineStats(additions: 2, deletions: 2))
    }

    @Test func worktreeList() {
        let output = [
            "worktree /Users/me/repo", "HEAD 1111111111111111111111111111111111111111", "branch refs/heads/main", "",
            "worktree /Users/me/.native/worktrees/repo/fix bug", "HEAD 2222222222222222222222222222222222222222",
            "branch refs/heads/native/fix-bug", "locked", "",
            "worktree /tmp/detached", "HEAD 3333333333333333333333333333333333333333", "detached",
            "prunable gitdir file points to non-existent location", "",
        ].joined(separator: "\0")

        let worktrees = WorktreeParser.parse(output)

        #expect(worktrees.map(\.path.lastPathComponent) == ["repo", "fix bug", "detached"])
        #expect(worktrees.map(\.isMain) == [true, false, false])
        #expect(worktrees[0].branch == "main")
        #expect(worktrees[1].branch == "native/fix-bug")
        #expect(worktrees[1].isLocked)
        #expect(worktrees[2].isDetached)
        #expect(worktrees[2].isPrunable)
        #expect(worktrees[2].branch == nil)
    }

    @Test func branchList() {
        let line = { (fields: [String]) in fields.joined(separator: "\0") }
        let output = [
            line(["refs/heads/main", "main", "aaa", "origin/main", "*", "1700000000", "/Users/me/repo", ""]),
            line(["refs/remotes/origin/HEAD", "origin", "aaa", "", " ", "1700000000", "", "refs/remotes/origin/main"]),
            line(["refs/remotes/origin/main", "origin/main", "aaa", "", " ", "1700000000", "", ""]),
            line(["refs/heads/topic", "topic", "bbb", "", " ", "1690000000", "", ""]),
        ].joined(separator: "\n")

        let branches = BranchParser.parse(output)

        #expect(branches.map(\.name) == ["main", "topic", "origin/main"])
        #expect(branches[0].isCurrent)
        #expect(branches[0].upstream == "origin/main")
        #expect(branches[0].worktreePath?.path(percentEncoded: false) == "/Users/me/repo/")
        #expect(branches[2].isRemote)
        #expect(branches[1].committerDate == Date(timeIntervalSince1970: 1_690_000_000))
    }

    @Test(arguments: [
        ("Fix the login bug!", "fix-the-login-bug"),
        ("  Café: déjà vu  ", "cafe-deja-vu"),
        ("日本語", "task"),
        ("feature/Git Support", "feature-git-support"),
    ])
    func worktreeSlugs(title: String, slug: String) {
        #expect(Worktree.slug(title) == slug)
    }

    @Test func changeClassifierKeepsOnlyRelevantGitPaths() {
        let classifier = ChangeClassifier(root: "/r", gitDirectory: "/r/.git", commonDirectory: "/r/.git")

        let change = classifier.classify([
            "/r/Sources/App.swift",
            "/r/.git/objects/ab/cdef",
            "/r/.git/index.lock",
            "/r/vendor/sub/.git/index",
            "/r2/elsewhere.txt",
        ])
        #expect(change.paths == ["Sources/App.swift"])
        #expect(!change.gitStateChanged)

        #expect(classifier.classify(["/r/.git/index"]).gitStateChanged)
        #expect(classifier.classify(["/r/.git/HEAD"]).gitStateChanged)
        #expect(classifier.classify(["/r/.git/refs/heads/main"]).gitStateChanged)
        #expect(!classifier.classify(["/r/.git/refs/heads/main.lock"]).gitStateChanged)
    }

    @Test func linkedWorktreeWatchesItsGitDirectories() {
        let classifier = ChangeClassifier(root: "/wt", gitDirectory: "/r/.git/worktrees/wt", commonDirectory: "/r/.git")

        #expect(classifier.watchedPaths == ["/wt", "/r/.git/worktrees/wt", "/r/.git"])
        #expect(classifier.classify(["/r/.git/worktrees/wt/index"]).gitStateChanged)
        #expect(classifier.classify(["/r/.git/refs/remotes/origin/wt"]).gitStateChanged)
        #expect(classifier.classify(["/wt/.git"]).isEmpty)
    }

    @Test func errorSummaryDropsPrefixesAndHints() {
        let stderr =
            "hint: Updates were rejected\nerror: failed to push some refs to 'origin'\nhint: try pulling first\n"
        #expect(GitError.summarize(stderr) == "failed to push some refs to 'origin'")
    }

    @Test(arguments: [
        (
            "push",
            "To github.com:me/repo.git\n ! [rejected]        main -> main (fetch first)\nerror: failed to push some refs\nhint: Updates were rejected because the remote contains work",
            GitFailure.pushRejected
        ),
        ("push", " ! [remote rejected] main -> main (protected branch hook declined)", GitFailure.remoteRefused),
        (
            "push", "fatal: Could not read from remote repository.\ngit@github.com: Permission denied (publickey).",
            GitFailure.authenticationFailed
        ),
        (
            "push", "fatal: unable to access 'https://github.com/me/repo/': Could not resolve host: github.com",
            GitFailure.networkUnavailable
        ),
        (
            "push",
            "remote: Invalid username or token.\nfatal: Authentication failed for 'https://github.com/me/repo.git/'",
            GitFailure.authenticationFailed
        ),
        (
            "pull", "hint: You have divergent branches and need to specify how to reconcile them.",
            GitFailure.divergentBranches
        ),
        (
            "pull",
            "CONFLICT (content): Merge conflict in a.txt\nAutomatic merge failed; fix conflicts and then commit the result.",
            GitFailure.conflicts
        ),
        (
            "pull", "error: Your local changes to the following files would be overwritten by merge:\n\ta.txt",
            GitFailure.localChangesWouldBeOverwritten
        ),
        ("commit", "error: Committing is not possible because you have unmerged files.", GitFailure.unmergedFiles),
        ("commit", "On branch main\nnothing to commit, working tree clean", GitFailure.nothingToCommit),
        ("commit", "pre-commit: swiftformat found 3 issues", GitFailure.hookFailed),
        (
            "add",
            "fatal: Unable to create '/r/.git/index.lock': File exists.\n\nAnother git process seems to be running",
            GitFailure.repositoryLocked
        ),
        ("status", "fatal: something new", GitFailure.other),
    ])
    func classifiesFailures(command: String, stderr: String, failure: GitFailure) {
        #expect(GitError.failed(arguments: [command], status: 1, stderr: stderr).failure == failure)
    }
}
