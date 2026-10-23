import Exec
import Foundation
import GitHub
import Network
import Observation

/// GitHub through the user's own `gh`: whether it's usable, their open pull requests across
/// repositories, and the pull request behind each task's branch. One instance lives for the app's
/// lifetime; `keepFresh()` keeps it current while the app runs.
@Observable
final class GitHubModel {
    let accounts: GitHubAccountsModel
    @ObservationIgnored private(set) var accountRevision = 0

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
    var branchPullRequests: [BranchReference: BranchPullRequest] = [:]
    @ObservationIgnored var branchLookupsInFlight: Set<BranchReference> = []

    /// Opens a pull request as a task: the app's Open as Task sheet takes it from there (which
    /// project, cloning it, the worktree, the task). Set by the app, which owns worktrees and
    /// tasks; "Open as Task" is hidden while it's `nil`.
    @ObservationIgnored var openAsTask: (@MainActor (PullRequestSummary) -> Void)?

    /// The branch the Create Pull Request sheet is showing, if any.
    var createRequest: CreatePullRequestRequest?

    var actionError: String?

    /// The pull request being merged from the list, through its page's merge sheet.
    var mergeRequest: PullRequestReference?
    /// The pull request whose quick comment box is open in the list.
    var commentingOn: URL?
    /// Quick comments being written in the list, by pull request.
    var quickComments: [URL: String] = [:]
    /// What's happening to each pull request the list acted on: working, done or failed.
    var rowActivity: [URL: PullRequestRowActivity] = [:]
    /// The list's undo for its last close or reopen.
    var undo: UndoToastItem?

    /// Where clicking a pull request goes (Settings › GitHub).
    var pullRequestOpening = GitHubPullRequestOpening.stored {
        didSet { UserDefaults.standard.set(pullRequestOpening.rawValue, forKey: GitHubPullRequestOpening.defaultsKey) }
    }
    /// The pull request page on screen, inside the Pull Requests pane.
    var presentedPullRequest: PullRequestReference? {
        didSet { if presentedPullRequest != nil { pageRequests += 1 } }
    }
    /// Counts requests to show a page, so the window brings the Pull Requests pane forward even
    /// when the page asked for is the one it left there (the user went to a task since).
    private(set) var pageRequests = 0
    /// Pages opened this run, so going back and forth doesn't reload them.
    @ObservationIgnored var pages: [PullRequestReference: PullRequestPageModel] = [:]
    /// Starts a task about lines of a pull request, or sends them to the task on screen. Set by the
    /// app, which owns tasks; "Ask an Agent" is hidden while it's `nil`.
    @ObservationIgnored var askAgent: (@MainActor (ReviewAgentPrompt, GitHubAgentDestination) async throws -> Void)?
    /// Opens the private "Ask about this pull request" conversation for a pull request (its page's
    /// panel). Set by that feature; its entry points (the page header, a row's menu) are hidden
    /// while it's `nil`.
    @ObservationIgnored var askAboutPullRequest: (@MainActor (PullRequestReference) -> Void)?
    /// The pull request a branch was made for, when the branch itself says (a task opened from a
    /// pull request names its branch after the task, so gh can't find it by name). Set by the app,
    /// which reads git; badges fall back to gh's lookup by branch while it's `nil` or says nothing.
    @ObservationIgnored var linkedPullRequest: (@MainActor (BranchReference) async -> URL?)?
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
        runner: any CommandRunner,
        defaults: UserDefaults = .standard
    ) {
        accounts = GitHubAccountsModel(defaults: defaults)
        self.environment = environment
        self.runner = runner
        // `-gitHubOpenPullRequest <url>` opens a pull request's page at launch, for checks and links.
        if let link = UserDefaults.standard.string(forKey: "gitHubOpenPullRequest"), let url = URL(string: link),
            let reference = PullRequestReference(url: url)
        {
            open(reference, tab: PullRequestPageModel.Tab(url: url))
        }
    }

    #if os(macOS)
    /// gh on this Mac.
    convenience init(environment: @escaping @MainActor (_ refresh: Bool) async -> [String: String]) {
        var runner: any CommandRunner = LocalCommandRunner()
        #if DEBUG
        // `-gitHubDryRunWrites YES` answers merges, closes and comments without sending them, so
        // their flows can be checked against real pull requests.
        if UserDefaults.standard.bool(forKey: GitHubDryRunRunner.enabledKey) {
            runner = GitHubDryRunRunner(base: runner)
        }
        if let value = UserDefaults.standard.string(forKey: "gitHubAccountFixture"),
            let state = GitHubAccountPreviewFixtures.State(rawValue: value)
        {
            runner = GitHubAccountFixtureRunner(state: state)
        }

        #endif
        self.init(environment: environment, runner: runner)
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
    /// app doesn't wake for it: gh runs at most every two minutes while the list is visible, every
    /// ten while a window shows, and not at all while none does. Coming back to the app, a window
    /// showing again or opening the list wakes it early.
    func keepFresh() async {
        watchNetwork()
        // Coming back to Native, or its windows coming into view, wakes the loop early.
        let observers =
            ([PlatformApplication.didBecomeActiveNotification] + PlatformApplication.visibilityNotifications)
            .map { name in
                NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.wakeRefreshLoop() }
                }
            }
        defer {
            pathMonitor.cancel()
            observers.forEach(NotificationCenter.default.removeObserver)
        }
        var wasActive = PlatformApplication.isActive
        var wasVisible = PlatformApplication.isVisible
        while !Task.isCancelled {
            let isActive = PlatformApplication.isActive
            let isVisible = PlatformApplication.isVisible
            let returned = (isActive && !wasActive) || (isVisible && !wasVisible)
            wasActive = isActive
            wasVisible = isVisible
            let activity: RefreshSchedule.Activity = isWatching && isActive ? .watching : .background
            // Nobody sees the badges and counts while no window shows, so nothing refreshes then.
            if isVisible,
                (returned && schedule.refreshesOnReturn(at: .now)) || schedule.isDue(activity, at: .now)
            {
                await refresh()
                refreshBranches(olderThan: returned ? 0 : Self.branchMaxAge)
            }
            // Hidden, it sleeps until a window shows again (a notification wakes it), not on a timer.
            let delay = isVisible ? max(schedule.nextRefresh(activity).timeIntervalSinceNow, 1) : 24 * 60 * 60
            let wait = Task { _ = try? await Task.sleep(for: .seconds(delay), tolerance: .seconds(delay / 10)) }
            refreshWait = wait
            await withTaskCancellationHandler {
                await wait.value
            } onCancel: {
                wait.cancel()
            }
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
        guard !isRefreshing, accounts.switchingTo == nil else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let discoveryCLI = await cli(rereadEnvironment: rereadEnvironment || availability == .notInstalled)
        let previous = accounts.selectedAccounts.map(accounts.key)
        await accounts.load(using: discoveryCLI)
        if !previous.isEmpty, previous != accounts.selectedAccounts.map(accounts.key) {
            clearAccountCaches()
        }
        let cli = await cli()
        do {
            let accounts = try readyAccounts()
            var inboxes: [PullRequestInbox] = []
            for account in accounts {
                inboxes.append(try await cli.targeting(host: account.host).inbox())
            }
            inbox = .merging(inboxes)
            lastError = nil
            schedule.recordSuccess(at: .now)
            refreshBranches(olderThan: Self.branchMaxAge)
        } catch {
            await recordFailure(error, cli: cli)
        }
    }

    /// Account discovery also refreshes the footer, including logins added outside Native.
    private func readyAccounts() throws(GitHubError) -> [AuthStatus.Account] {
        if let error = accounts.error { throw error }
        let availability = accounts.selection.availability(in: accounts.status ?? AuthStatus(hosts: [:]))
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
        accounts.recordFailure(error)
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
            return cachedCLI.selecting(accounts.processSelection)
        }
        let cli = GitHubCLI(environment: await environment(rereadEnvironment), runner: runner)
        cachedCLI = cli
        return cli.selecting(accounts.processSelection)
    }

    var canSwitchAccount: Bool {
        !isRefreshing && accounts.switchingTo == nil && !pages.values.contains { !$0.busy.isEmpty }
            && !rowActivity.values.contains { if case .working = $0 { true } else { false } }
    }

    func selectAccount(_ account: AuthStatus.Account) async {
        if let current = accounts.current, accounts.key(current) == accounts.key(account) {
            return
        }
        guard canSwitchAccount else { return }
        let cli = await cli()
        guard canSwitchAccount, await accounts.select(account, using: cli) else { return }
        clearAccountCaches()
        await refresh()
    }

    private func clearAccountCaches() {
        accountRevision += 1
        availability = nil
        inbox = nil
        for branch in branchPullRequests.keys {
            branchPullRequests[branch] = BranchPullRequest(pullRequest: nil, fetchedAt: .distantPast)
        }
        branchLookupsInFlight = []
        pages = [:]
        presentedPullRequest = nil
        mergeRequest = nil
        undo = nil
        rowActivity = [:]
    }

    func reportAuthenticationFailure() {
        availability = .notAuthenticated
        accounts.recordFailure(.notAuthenticated("Sign in again, or choose another GitHub account."))
    }

    func checkAccounts() async {
        guard canSwitchAccount else { return }
        availability = nil
        await refresh(rereadEnvironment: true)
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
        let model = GitHubModel(environment: { _ in [:] }, runner: NoCommandRunner(), defaults: PreviewUserDefaults())
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
