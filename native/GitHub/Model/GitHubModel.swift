import Exec
import GitHub
import Network
import Observation

/// GitHub through the user's own `gh`: whether it's usable, their open pull requests across
/// repositories, and the pull request behind each task's branch. One instance lives for the app's
/// lifetime; `keepFresh()` keeps it current while the app runs.
@Observable
final class GitHubModel {
    /// `nil` until the first check; then whether gh is installed and signed in.
    private(set) var availability: GitHubAvailability?
    /// The last inbox that loaded. Kept through later failures, so the list stays useful offline.
    private(set) var inbox: PullRequestInbox?
    /// Why the last refresh failed; cleared by the next success.
    private(set) var lastError: GitHubError?
    private(set) var isRefreshing = false
    private(set) var schedule = RefreshSchedule()
    var filter = PullRequestFilter()
    var collapsedGroups: Set<PullRequestGroup.ID> = []
    /// Whether the pull request list is on screen, which refreshes it more often.
    var isWatching = false {
        didSet { wakeRefreshLoop() }
    }

    /// Pull requests behind task branches, for badges.
    private(set) var branchPullRequests: [BranchReference: BranchPullRequest] = [:]
    @ObservationIgnored var branchLookupsInFlight: Set<BranchReference> = []

    /// The pull request the user asked to open as a task, while they confirm or it's being set up.
    var openAsTaskCandidate: PullRequestSummary?
    private(set) var openingAsTask: URL?
    /// Checks a pull request out into a fresh worktree and starts a task there. Set by the app,
    /// which owns worktrees and tasks; "Open as Task" is hidden while it's `nil`.
    @ObservationIgnored var openAsTask: (@MainActor (PullRequestSummary) async throws -> Void)?

    /// The branch the Create Pull Request sheet is showing, if any.
    var createRequest: CreatePullRequestRequest?

    var actionError: String?

    /// Where clicking a pull request goes (Settings › GitHub).
    var pullRequestOpening = GitHubPullRequestOpening.stored {
        didSet { UserDefaults.standard.set(pullRequestOpening.rawValue, forKey: GitHubPullRequestOpening.defaultsKey) }
    }
    /// The pull request page on screen, inside the Pull Requests pane.
    var presentedPullRequest: PullRequestReference?
    /// Pages opened this run, so going back and forth doesn't reload them.
    @ObservationIgnored var pages: [PullRequestReference: PullRequestPageModel] = [:]
    /// Starts a task about lines of a pull request, or sends them to the task on screen. Set by the
    /// app, which owns tasks; "Ask an Agent" is hidden while it's `nil`.
    @ObservationIgnored var askAgent: (@MainActor (ReviewAgentPrompt, GitHubAgentDestination) async throws -> Void)?
    /// Whether a task is on screen to send to, for "Send to Current Task".
    @ObservationIgnored var hasCurrentTask: @MainActor () -> Bool = { false }
    /// Opens web links; the platform's browser unless a test swaps it.
    @ObservationIgnored var openExternally: @MainActor (URL) -> Void = { PlatformURLOpener.open($0) }

    @ObservationIgnored private let pathMonitor = NWPathMonitor()
    @ObservationIgnored private var isOnline = true
    @ObservationIgnored private let environment: @MainActor (_ refresh: Bool) async -> [String: String]
    @ObservationIgnored private let runner: any CommandRunner
    @ObservationIgnored private var cachedCLI: GitHubCLI?
    /// The refresh loop's wait for the next refresh; cancelling it wakes the loop early.
    @ObservationIgnored private var refreshWait: Task<Void, Never>?

    /// - Parameters:
    ///   - environment: The login-shell environment of the machine gh runs on; `true` reads it again.
    ///   - runner: Runs gh on the machine that hosts the projects.
    init(
        environment: @escaping @MainActor (_ refresh: Bool) async -> [String: String],
        runner: any CommandRunner
    ) {
        self.environment = environment
        self.runner = runner
    }

    #if os(macOS)
    /// gh on this Mac.
    convenience init(environment: @escaping @MainActor (_ refresh: Bool) async -> [String: String]) {
        self.init(environment: environment, runner: LocalCommandRunner())
    }
    #endif

    var canOpenAsTask: Bool {
        openAsTask != nil
    }

    /// The signed-in login, to leave the user's own name off their pull requests.
    var currentLogin: String? {
        if case .ready(let accounts) = availability { accounts.first?.login } else { nil }
    }

    /// Pull requests waiting on the user's review, for the sidebar count.
    var reviewRequestCount: Int {
        inbox?.reviewRequested.count ?? 0
    }

    // MARK: - Refreshing

    /// Refreshes on schedule, and when the user comes back to the app, until cancelled. Run it once,
    /// from the app's root view. Between refreshes it sleeps until the next one is due, so an idle
    /// app doesn't wake for it: gh runs at most every two minutes while the list is visible and
    /// every ten otherwise, and coming back to the app or opening the list wakes it early.
    func keepFresh() async {
        watchNetwork()
        let activation = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.wakeRefreshLoop() }
        }
        defer {
            pathMonitor.cancel()
            NotificationCenter.default.removeObserver(activation)
        }
        var wasActive = NSApplication.shared.isActive
        while !Task.isCancelled {
            let isActive = NSApplication.shared.isActive
            let returned = isActive && !wasActive
            wasActive = isActive
            let activity: RefreshSchedule.Activity = isWatching && isActive ? .watching : .background
            if (returned && schedule.refreshesOnReturn(at: .now)) || schedule.isDue(activity, at: .now) {
                await refresh()
                refreshBranches(olderThan: returned ? 0 : Self.branchMaxAge)
            }
            let delay = max(schedule.nextRefresh(activity).timeIntervalSinceNow, 1)
            let wait = Task { try? await Task.sleep(for: .seconds(delay), tolerance: .seconds(delay / 10)) }
            refreshWait = wait
            await withTaskCancellationHandler { await wait.value } onCancel: { wait.cancel() }
        }
    }

    private func wakeRefreshLoop() {
        refreshWait?.cancel()
    }

    /// Retries as soon as the network comes back, rather than waiting out the backoff.
    private func watchNetwork() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let isOnline = path.status == .satisfied
            Task { @MainActor in self?.networkChanged(isOnline: isOnline) }
        }
        pathMonitor.start(queue: DispatchQueue(label: "Native.GitHub.network", qos: .utility))
    }

    private func networkChanged(isOnline: Bool) {
        defer { self.isOnline = isOnline }
        guard isOnline, !self.isOnline else { return }
        switch lastError {
        case .offline, .timedOut: Task { await refresh() }
        default: break
        }
    }

    /// Refreshes now if the list is due, e.g. when it appears.
    func refreshIfDue() async {
        if schedule.isDue(.watching, at: .now) {
            await refresh()
        }
    }

    /// Re-checks gh and reloads the inbox. `rereadEnvironment` picks up a gh installed or a PATH
    /// changed since launch.
    func refresh(rereadEnvironment: Bool = false) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let cli = await cli(rereadEnvironment: rereadEnvironment || availability == .notInstalled)
        do {
            let accounts = try await readyAccounts(cli)
            var inboxes: [PullRequestInbox] = []
            for account in accounts {
                inboxes.append(try await cli.targeting(host: account.host).inbox())
            }
            inbox = .merging(inboxes)
            lastError = nil
            schedule.recordSuccess(at: .now)
        } catch {
            await recordFailure(error, cli: cli)
        }
    }

    /// The signed-in accounts, checking with gh only until it has worked once: after that, a failed
    /// search reports a lost login just as well, and skips a network round trip per refresh.
    private func readyAccounts(_ cli: GitHubCLI) async throws(GitHubError) -> [AuthStatus.Account] {
        if case .ready(let accounts) = availability {
            return accounts
        }
        let availability = try await cli.availability()
        self.availability = availability
        switch availability {
        case .ready(let accounts): return accounts
        case .notInstalled: throw .notInstalled
        case .notAuthenticated: throw .notAuthenticated("")
        case .offline: throw .offline("")
        }
    }

    private func recordFailure(_ error: GitHubError, cli: GitHubCLI) async {
        lastError = error
        switch error {
        case .notInstalled:
            availability = .notInstalled
        case .notAuthenticated:
            availability = .notAuthenticated
            inbox = nil
        default:
            break
        }
        var resetsAt: Date?
        if case .rateLimited = error {
            // `gh api rate_limit` costs nothing, even while limited.
            resetsAt = try? await cli.rateLimit().exhaustedUntil
        }
        schedule.recordFailure(error, at: .now, rateLimitResetsAt: resetsAt)
    }

    func cli(rereadEnvironment: Bool = false) async -> GitHubCLI {
        if let cachedCLI, !rereadEnvironment {
            return cachedCLI
        }
        let cli = GitHubCLI(environment: await environment(rereadEnvironment), runner: runner)
        cachedCLI = cli
        return cli
    }

    // MARK: - Opening as a task

    func confirmOpenAsTask() async {
        guard let pullRequest = openAsTaskCandidate, let openAsTask else { return }
        openAsTaskCandidate = nil
        openingAsTask = pullRequest.url
        defer { openingAsTask = nil }
        do {
            try await openAsTask(pullRequest)
        } catch {
            actionError = "Couldn't open \(pullRequest.reference) as a task: \(error.localizedDescription)"
        }
    }

    // MARK: - Branches

    /// How long a branch's pull request is trusted. Each lookup is one `gh pr list --head` call, so
    /// results are cached and shared by every badge showing the same branch.
    static let branchMaxAge: TimeInterval = 120

    func pullRequest(for branch: BranchReference) -> PullRequestSummary? {
        branchPullRequests[branch]?.pullRequest
    }

    /// Loads the branch's pull request unless a result younger than `maxAge` is cached.
    func loadPullRequest(for branch: BranchReference, maxAge: TimeInterval = branchMaxAge) async {
        if let cached = branchPullRequests[branch], Date.now.timeIntervalSince(cached.fetchedAt) < maxAge {
            return
        }
        guard !branchLookupsInFlight.contains(branch) else { return }
        // Without gh or a login there's nothing to show, and the list explains why.
        if availability == .notInstalled || availability == .notAuthenticated { return }

        branchLookupsInFlight.insert(branch)
        defer { branchLookupsInFlight.remove(branch) }
        let cli = await cli()
        do {
            let pullRequest = try await cli.pullRequest(forBranch: branch.branch, in: .directory(branch.directory))
            branchPullRequests[branch] = BranchPullRequest(
                pullRequest: pullRequest.map(PullRequestSummary.init), fetchedAt: .now)
        } catch .notARepository, .notFound {
            branchPullRequests[branch] = BranchPullRequest(pullRequest: nil, fetchedAt: .now)
        } catch {
            // Keep showing what was there; the next refresh tries again.
            if var cached = branchPullRequests[branch] {
                cached.fetchedAt = .now
                branchPullRequests[branch] = cached
            }
        }
    }

    /// Forgets a branch's result so its badge reloads, e.g. after a push or a new pull request.
    func invalidate(_ branch: BranchReference) {
        branchPullRequests[branch] = nil
        Task { await loadPullRequest(for: branch) }
    }

    /// Reloads every badge whose result is older than `age`.
    func refreshBranches(olderThan age: TimeInterval) {
        let stale = branchPullRequests.filter { Date.now.timeIntervalSince($0.value.fetchedAt) >= age }.keys
        for branch in stale {
            Task { await loadPullRequest(for: branch, maxAge: age) }
        }
    }
}

#if DEBUG
extension GitHubModel {
    /// Shows fixed data and never runs gh, for previews and render checks.
    static func preview(
        inbox: PullRequestInbox? = nil,
        availability: GitHubAvailability? = .ready(accounts: [
            AuthStatus.Account(host: "github.com", login: "binbandit", active: true, state: .success)
        ]),
        error: GitHubError? = nil,
        branches: [BranchReference: PullRequestSummary] = [:]
    ) -> GitHubModel {
        let model = GitHubModel(environment: { _ in [:] }, runner: NoCommandRunner())
        model.cachedCLI = GitHubCLI(environment: [:], runner: NoCommandRunner())
        model.inbox = inbox
        model.availability = availability
        model.schedule.recordSuccess(at: .now)
        model.lastError = error
        model.branchPullRequests = branches.mapValues { BranchPullRequest(pullRequest: $0, fetchedAt: .distantFuture) }
        return model
    }
}

/// Runs nothing, as if gh weren't installed, so previews never touch GitHub.
private struct NoCommandRunner: CommandRunner {
    func run(_ command: Command) async throws -> CommandResult {
        throw CommandError.notFound(command.executable)
    }
}
#endif
