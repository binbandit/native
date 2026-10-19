import Foundation
import Testing

@testable import GitHub

@Suite("Opening a pull request in a local checkout")
struct LocalCheckoutTests {
    // MARK: - Remotes

    @Test(arguments: [
        "https://github.com/sindresorhus/slugify",
        "https://github.com/sindresorhus/slugify.git",
        "https://github.com/sindresorhus/slugify/",
        "https://github.com/SindreSorhus/Slugify.git",
        "http://github.com/sindresorhus/slugify",
        "https://x-access-token:secret@github.com/sindresorhus/slugify.git",
        "git@github.com:sindresorhus/slugify.git",
        "git@github.com:sindresorhus/slugify",
        "github.com:sindresorhus/slugify.git",
        "ssh://git@github.com/sindresorhus/slugify.git",
        "ssh://git@ssh.github.com:443/sindresorhus/slugify.git",
        "git://github.com/sindresorhus/slugify.git",
        "  https://www.github.com/sindresorhus/slugify.git\n",
    ])
    func remoteSpellingsNameTheSameRepository(url: String) throws {
        let repository = try #require(RemoteRepository(remoteURL: url))
        #expect(repository == RemoteRepository(owner: "sindresorhus", name: "slugify"))
        #expect(repository.host == "github.com")
    }

    @Test(arguments: [
        "/Users/someone/code/slugify", "../slugify", "file:///Users/someone/slugify.git",
        "https://gitlab.com/group/subgroup/project.git", "https://github.com/sindresorhus",
    ])
    func localPathsAndOtherShapesAreNotRepositories(url: String) {
        #expect(RemoteRepository(remoteURL: url) == nil)
    }

    @Test func sshAliasesMatchLooselyAndOtherHostsNotAtAll() throws {
        let repository = RemoteRepository(owner: "sindresorhus", name: "slugify")
        let alias = try #require(RemoteRepository(remoteURL: "git@github-work:sindresorhus/slugify.git"))
        let suffixed = try #require(RemoteRepository(remoteURL: "git@github.com-personal:sindresorhus/slugify.git"))
        let enterprise = try #require(RemoteRepository(remoteURL: "git@ghe.example.com:sindresorhus/slugify.git"))

        #expect(repository.match(alias) == .aliasedHost)
        #expect(repository.match(suffixed) == .aliasedHost)
        #expect(repository.match(enterprise) == nil)
        #expect(enterprise.description == "ghe.example.com/sindresorhus/slugify")
        #expect(repository.match(RemoteRepository(owner: "sindresorhus", name: "slugify-cli")) == nil)
    }

    @Test func newRemotesAuthenticateLikeTheProjectsOwn() {
        let fork = RemoteRepository(owner: "AmineYagoub", name: "slugify")
        #expect(fork.remoteURL(like: "git@github.com:sindresorhus/slugify.git") == "git@github.com:AmineYagoub/slugify.git")
        #expect(fork.remoteURL(like: "ssh://git@github.com/sindresorhus/slugify") == "git@github.com:AmineYagoub/slugify.git")
        #expect(fork.remoteURL(like: "https://github.com/sindresorhus/slugify.git") == "https://github.com/AmineYagoub/slugify.git")
        #expect(fork.remoteURL(like: nil) == "https://github.com/AmineYagoub/slugify.git")
    }

    // MARK: - Finding the project

    @Test func aCheckoutOfTheBaseRepositoryBeatsOneOfTheFork() {
        let base = RemoteRepository(owner: "sindresorhus", name: "slugify")
        let fork = RemoteRepository(owner: "AmineYagoub", name: "slugify")
        let candidates = [
            PullRequestProjectMatch.Candidate(id: "unrelated", remotes: [GitRemote(name: "origin", url: "git@github.com:sindresorhus/ky.git")]),
            PullRequestProjectMatch.Candidate(id: "fork", remotes: [GitRemote(name: "origin", url: "https://github.com/amineyagoub/slugify")]),
            PullRequestProjectMatch.Candidate(
                id: "base",
                remotes: [
                    GitRemote(name: "mine", url: "git@github.com:binbandit/slugify.git"),
                    GitRemote(name: "upstream", url: "git@github.com:sindresorhus/slugify.git"),
                ]),
        ]

        let match = PullRequestProjectMatch.best(base: base, head: fork, among: candidates)

        #expect(match?.id == "base")
        #expect(match?.kind == .repository)
        #expect(PullRequestProjectMatch.best(base: base, head: fork, among: Array(candidates.prefix(2)))?.kind == .fork)
        #expect(PullRequestProjectMatch.best(base: base, head: fork, among: Array(candidates.prefix(1))) == nil)
    }

    @Test func equalMatchesKeepTheSidebarsOrderAndAliasesComeLast() {
        let base = RemoteRepository(owner: "sindresorhus", name: "slugify")
        let candidates = [
            PullRequestProjectMatch.Candidate(id: 1, remotes: [GitRemote(name: "origin", url: "git@github-work:sindresorhus/slugify.git")]),
            PullRequestProjectMatch.Candidate(id: 2, remotes: [GitRemote(name: "origin", url: "https://github.com/sindresorhus/slugify")]),
            PullRequestProjectMatch.Candidate(id: 3, remotes: [GitRemote(name: "origin", url: "git@github.com:sindresorhus/slugify")]),
        ]

        #expect(PullRequestProjectMatch.best(base: base, head: nil, among: candidates)?.id == 2)
        #expect(PullRequestProjectMatch.best(base: base, head: nil, among: [candidates[0]])?.kind == .repositoryAliased)
    }

    // MARK: - Branch names

    @Test(arguments: [
        (78, "Add `maxLength` option", "pr-78-add-maxlength-option"),
        (14665, "Refreshable tokens: rename `--short-lived` flag to `--expiring`", "pr-14665-refreshable-tokens-rename-short"),
        (12, "Crème brûlée für Ärger 🎉", "pr-12-creme-brulee-fur-arger"),
        (3, "🎉🎉🎉", "pr-3"),
        (4, "Supercalifragilisticexpialidociousandthensomemore", "pr-4-supercalifragilisticexpialidociousa"),
    ])
    func branchesAreReadableAndCutBetweenWords(number: Int, title: String, branch: String) {
        let name = PullRequestTaskBranch.name(number: number, title: title)
        #expect(name == branch)
        #expect(name.count <= 40)
    }

    // MARK: - Checkout plans

    @Test func aForkTheViewerCantPushToComesFromTheReadOnlyPullRef() throws {
        let pullRequest = try Fixtures.decode(PullRequestDetails.self, from: "pr-view-details-fork")
        let remotes = [GitRemote(name: "origin", url: "https://github.com/sindresorhus/slugify.git")]

        let plan = PullRequestCheckoutPlan(pullRequest, remotes: remotes, viewer: "binbandit", permission: .read)

        #expect(plan.source == .pullRef(remote: "origin", number: 78))
        #expect(plan.branch == "pr-78-add-maxlength-option")
        #expect(plan.fetchRefspec(into: "pr-78-add-maxlength-option-2") == "refs/pull/78/head:refs/heads/pr-78-add-maxlength-option-2")
        #expect(plan.upstream == nil)
        #expect(plan.pushCommand == nil)
    }

    @Test func aForkTheViewerCanPushToGetsARemoteSpelledLikeTheProjects() throws {
        let pullRequest = try Fixtures.decode(PullRequestDetails.self, from: "pr-view-details-fork")
        let remotes = [GitRemote(name: "origin", url: "git@github.com:sindresorhus/slugify.git")]

        // Maintainers may push because the author allows it; the author always may.
        let maintainer = PullRequestCheckoutPlan(pullRequest, remotes: remotes, viewer: "sindresorhus", permission: .admin)
        let author = PullRequestCheckoutPlan(pullRequest, remotes: remotes, viewer: "amineyagoub", permission: .read)

        let expected = PullRequestCheckoutPlan.Source.newRemote(
            name: "AmineYagoub", url: "git@github.com:AmineYagoub/slugify.git", branch: "feat/max-length")
        #expect(maintainer.source == expected)
        #expect(author.source == expected)
        #expect(maintainer.fetchRefspec(into: "pr-78") == "+refs/heads/feat/max-length:refs/remotes/AmineYagoub/feat/max-length")
        #expect(maintainer.upstream?.remote == "AmineYagoub")
        #expect(maintainer.upstream?.branch == "feat/max-length")
        #expect(maintainer.pushCommand == "git push AmineYagoub HEAD:feat/max-length")
    }

    @Test func anExistingRemoteForTheForkIsUsedAndANewOneNeverCollides() throws {
        let pullRequest = try Fixtures.decode(PullRequestDetails.self, from: "pr-view-details-fork")
        let existing = PullRequestCheckoutPlan(
            pullRequest,
            remotes: [
                GitRemote(name: "origin", url: "https://github.com/sindresorhus/slugify.git"),
                GitRemote(name: "amine", url: "https://github.com/AmineYagoub/slugify"),
            ], viewer: "someone", permission: .read)
        #expect(existing.source == .remote(name: "amine", branch: "feat/max-length"))

        let taken = PullRequestCheckoutPlan(
            pullRequest,
            remotes: [
                GitRemote(name: "origin", url: "https://github.com/sindresorhus/slugify.git"),
                GitRemote(name: "AmineYagoub", url: "https://github.com/AmineYagoub/other.git"),
            ], viewer: "AmineYagoub", permission: nil)
        #expect(taken.fetchRemote == "AmineYagoub-slugify")
    }

    @Test func aBranchInTheBaseRepositoryIsTrackedOnItsRemote() throws {
        let pullRequest = try Fixtures.decode(PullRequestDetails.self, from: "pr-view-details-same-repository")
        let plan = PullRequestCheckoutPlan(
            pullRequest,
            remotes: [
                GitRemote(name: "fork", url: "git@github.com:binbandit/cli.git"),
                GitRemote(name: "origin", url: "git@github.com:cli/cli.git"),
            ], viewer: "binbandit", permission: .read)

        #expect(plan.source == .remote(name: "origin", branch: "babakks/refresh-token-rename-flag-to-expiring"))
        #expect(plan.pushCommand == "git push origin HEAD:babakks/refresh-token-rename-flag-to-expiring")
    }

    @Test func aDeletedForkStillChecksOutFromGitHubsCopy() throws {
        var pullRequest = try Fixtures.decode(PullRequestDetails.self, from: "pr-view-details-fork")
        pullRequest.headRepository = nil
        // A checkout of the fork only: the base repository is fetched by URL.
        let plan = PullRequestCheckoutPlan(
            pullRequest, remotes: [GitRemote(name: "origin", url: "git@github.com:binbandit/slugify.git")],
            viewer: "binbandit", permission: nil)

        #expect(plan.source == .pullRef(remote: "git@github.com:sindresorhus/slugify.git", number: 78))
    }

    // MARK: - Decoding

    @Test func detailsSayWhereTheHeadLives() throws {
        let fork = try Fixtures.decode(PullRequestDetails.self, from: "pr-view-details-fork")
        #expect(fork.headRepository == RemoteRepository(owner: "AmineYagoub", name: "slugify"))
        #expect(fork.baseRepository == RemoteRepository(owner: "sindresorhus", name: "slugify"))
        #expect(fork.isCrossRepository)
        #expect(fork.maintainerCanModify)
        #expect(fork.headRefOid == "9f31d620a761e3a6c5dcea2766c98d9044d1b9c1")
        #expect(fork.author == "AmineYagoub")

        let sameRepository = try Fixtures.decode(PullRequestDetails.self, from: "pr-view-details-same-repository")
        #expect(sameRepository.headRepository == sameRepository.baseRepository)
        #expect(sameRepository.reviews.map(\.state) == [.commented, .approved])
        #expect(sameRepository.reviews.first?.author == "copilot-pull-request-reviewer")
    }

    @Test func aDeletedForkDecodesWithoutAHeadRepository() throws {
        let json = #"""
            {"number":5,"title":"Fix","body":"","url":"https://github.com/o/r/pull/5","state":"OPEN","isDraft":false,
             "author":{"login":"ghost"},"baseRefName":"main","headRefName":"fix","headRefOid":"abc",
             "headRepository":null,"headRepositoryOwner":{"login":"ghost"},"isCrossRepository":true,
             "maintainerCanModify":false,"reviews":[]}
            """#
        let pullRequest = try GitHubJSON.decode(PullRequestDetails.self, from: Data(json.utf8))
        #expect(pullRequest.headRepository == nil)
        #expect(pullRequest.baseRepository == RemoteRepository(owner: "o", name: "r"))
    }

    @Test func detailsAndClonesAreOneGhCallEach() async throws {
        let runner = FakeRunner { command in
            command.arguments.first == "pr"
                ? FakeRunner.success(try Fixtures.data("pr-view-details-fork")) : FakeRunner.success(Data())
        }
        let cli = GitHubCLI(environment: ["PATH": "/usr/bin"], runner: runner)
        let reference = try #require(URL(string: "https://github.com/sindresorhus/slugify/pull/78/files").flatMap(PullRequestReference.init(url:)))

        let details = try await cli.pullRequestDetails(reference)
        try await cli.clone(RemoteRepository(owner: "sindresorhus", name: "slugify"), to: URL(filePath: "/tmp/x/../slugify"))

        #expect(details.number == 78)
        let view = try #require(runner.commands.first)
        #expect(Array(view.arguments.prefix(4)) == ["pr", "view", "78", "--json"])
        #expect(view.arguments.last == "--repo=sindresorhus/slugify")
        #expect(runner.commands.last?.arguments == ["repo", "clone", "sindresorhus/slugify", "/tmp/slugify"])
        #expect(GitHubCommand.clone(RemoteRepository(owner: "o", name: "r"), to: URL(filePath: "/tmp/r")).isMutating)
    }

    // MARK: - Existing tasks

    @Test func theTaskForAPullRequestIsFoundHoweverItsLinkIsSpelled() throws {
        let reference = try #require(URL(string: "https://github.com/sindresorhus/slugify/pull/78").flatMap(PullRequestReference.init(url:)))
        let candidates = [
            PullRequestTaskMatch.Candidate(id: "other", link: URL(string: "https://github.com/sindresorhus/slugify/pull/77")),
            PullRequestTaskMatch.Candidate(id: "plain", link: nil),
            PullRequestTaskMatch.Candidate(
                id: "archived", link: URL(string: "https://github.com/sindresorhus/slugify/pull/78"), isArchived: true,
                updatedAt: .now),
            PullRequestTaskMatch.Candidate(
                id: "older", link: URL(string: "https://github.com/SindreSorhus/Slugify/pull/78/files"),
                updatedAt: .distantPast),
            PullRequestTaskMatch.Candidate(
                id: "newer", link: URL(string: "https://github.com/sindresorhus/slugify/pull/78#discussion_r1"),
                updatedAt: Date(timeIntervalSince1970: 1_000)),
        ]

        #expect(PullRequestTaskMatch.existing(for: reference, among: candidates)?.id == "newer")
        #expect(PullRequestTaskMatch.existing(for: reference, among: Array(candidates.prefix(3)))?.id == "archived")
        #expect(PullRequestTaskMatch.existing(for: reference, among: Array(candidates.prefix(2))) == nil)
    }

    @Test func aTaskNeedsUpdatingUntilItHasThePullRequestsHead() {
        #expect(PullRequestTaskMatch.headState(hasHeadCommit: true, containsHeadCommit: true) == .current)
        // Pushed since: not fetched yet.
        #expect(PullRequestTaskMatch.headState(hasHeadCommit: false, containsHeadCommit: false) == .moved)
        // Fetched (or rewritten) but not in the task's history.
        #expect(PullRequestTaskMatch.headState(hasHeadCommit: true, containsHeadCommit: false) == .moved)
    }

    // MARK: - The brief

    @Test func theBriefSaysWhatTheAgentIsWorkingOnAndHowToPush() throws {
        let pullRequest = try Fixtures.decode(PullRequestDetails.self, from: "pr-view-details-fork")
        let brief = PullRequestTaskBrief(
            pullRequest: pullRequest, branch: "pr-78-add-maxlength-option",
            pushCommand: "git push AmineYagoub HEAD:feat/max-length")
        let text = brief.markdown

        #expect(brief.fileName == "pull-request-78.md")
        #expect(text.hasPrefix("# Pull request #78: Add `maxLength` option\n"))
        #expect(text.contains("https://github.com/sindresorhus/slugify/pull/78"))
        #expect(text.contains("Merges `AmineYagoub:feat/max-length` into `main`, head commit 9f31d62"))
        #expect(text.contains("`git push AmineYagoub HEAD:feat/max-length`"))
        #expect(text.contains("## Description\n\nAdds a `maxLength` option"))
        #expect(!text.contains("## Reviews"))

        let readOnly = PullRequestTaskBrief(pullRequest: pullRequest, branch: "pr-78", pushCommand: nil, includesReviews: true)
        #expect(readOnly.markdown.contains("can't push to the pull request"))
        #expect(readOnly.markdown.contains("No reviews or open review comments yet."))
    }

    @Test func reviewsAndOpenConversationsAreQuotedWhenAsked() throws {
        let pullRequest = try Fixtures.decode(PullRequestDetails.self, from: "pr-view-details-same-repository")
        let threads = [
            ReviewThread(
                id: "1", path: "pkg/cmd/auth/login.go", line: 42, startLine: 40,
                comments: [
                    ReviewComment(id: "c1", author: "alice", body: "Rename this too?", createdAt: .now),
                    ReviewComment(id: "c2", author: "bob", body: "Yes.\nAnd the help text.", createdAt: .now),
                ]),
            ReviewThread(
                id: "2", path: "done.go", isResolved: true, line: 1,
                comments: [ReviewComment(id: "c3", author: "carol", body: "Resolved already", createdAt: .now)]),
        ]
        let text = PullRequestTaskBrief(
            pullRequest: pullRequest, branch: "pr-14665", pushCommand: nil, threads: threads, includesReviews: true
        ).markdown

        #expect(text.contains("@copilot-pull-request-reviewer commented:\n\n> "))
        // An approval without a body has nothing to quote.
        #expect(!text.contains("@williammartin"))
        #expect(text.contains("#### `pkg/cmd/auth/login.go`, lines 40-42\n\n@alice:\n> Rename this too?\n\n@bob:\n> Yes.\n> And the help text."))
        #expect(!text.contains("Resolved already"))
        // GitHub's HTML in bot reviews reads as Markdown.
        #expect(!text.contains("<picture>"))
    }
}
