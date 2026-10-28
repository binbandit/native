import Foundation
import GitHub
import Observation

/// Account discovery and presentation are separate from inbox loading, so an unavailable avatar
/// or an offline search never makes the sidebar wait or loses a known identity.
@Observable
final class GitHubAccountsModel {
    static let selectionKey = "github.selectedAccounts"
    private(set) var selection: GitHubAccountSelection
    private(set) var status: AuthStatus?
    private(set) var error: GitHubError?
    private(set) var isLoading = false
    private(set) var switchingTo: String?
    private(set) var switchFailure: String?
    private(set) var preferredHost: String?
    private(set) var profiles: [String: GitHubUser] = [:]
    private(set) var avatars: [String: Data] = [:]
    var showsSignIn = false
    var copiedCommand = false
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var profileTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        preferredHost = defaults.string(forKey: "github.displayedHost")
        selection = .init(logins: defaults.dictionary(forKey: Self.selectionKey) as? [String: String] ?? [:])
        if let data = defaults.data(forKey: "github.accountProfiles"),
            let saved = try? JSONDecoder().decode([String: GitHubUser].self, from: data)
        {
            profiles = saved
        }
    }

    var accounts: [AuthStatus.Account] {
        guard let status else { return [] }
        return status.hosts.keys.sorted {
            ($0 == "github.com" ? 0 : 1, $0) < ($1 == "github.com" ? 0 : 1, $1)
        }.flatMap { status.hosts[$0] ?? [] }
    }

    var selectedAccounts: [AuthStatus.Account] {
        if let status { return selection.accounts(in: status) }
        return selection.logins.sorted { $0.key < $1.key }.map {
            AuthStatus.Account(host: $0.key, login: $0.value, active: false, state: nil)
        }
    }

    var processSelection: GitHubAccountSelection {
        status.map { selection.includingDefaults(from: $0) } ?? selection
    }

    var current: AuthStatus.Account? {
        selectedAccounts.first { $0.host == preferredHost } ?? selectedAccounts.first
    }

    func isSelected(_ account: AuthStatus.Account) -> Bool {
        selectedAccounts.contains { $0.host == account.host && $0.login == account.login }
    }

    func key(_ account: AuthStatus.Account) -> String { "\(account.host)/\(account.login)" }
    func profile(_ account: AuthStatus.Account) -> GitHubUser? { profiles[key(account)] }
    func avatar(_ account: AuthStatus.Account) -> Data? { avatars[key(account)] }
    func name(_ account: AuthStatus.Account) -> String {
        let name = profile(account)?.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? account.login : name
    }

    var title: String {
        if let current { return name(current) }
        if case .notInstalled = error { return "Install GitHub CLI" }
        if isLoading || status == nil && error == nil { return "Checking GitHub…" }
        if case .offline = error { return "GitHub is offline" }
        if case .timedOut = error { return "GitHub is offline" }
        return "Sign in to GitHub"
    }

    var guidance: String? {
        if switchingTo != nil { return "Switching account…" }
        if let switchFailure { return switchFailure }
        if status != nil, let current, !current.active, current.state != .error {
            return
                "GitHub CLI manages this account. Activate @\(current.login) with gh auth switch in a terminal, then check accounts."
        }
        if current?.state == .error { return "Sign-in expired or removed. Sign in again, or choose another account." }
        if case .notInstalled = error { return "Install GitHub CLI in a terminal, then check again." }
        if case .offline = error {
            return "GitHub can't be reached. Your account is kept; check again when you're online."
        }
        if case .timedOut = error { return "GitHub didn't respond. Your account is kept; try again." }
        if let error { return error.localizedDescription }
        if accounts.isEmpty, !isLoading { return "Sign in with GitHub CLI in a terminal, then check again." }
        if selectedAccounts.contains(where: { $0.state == .timeout }) {
            return "GitHub is offline. Showing your saved account."
        }
        return nil
    }

    func load(using cli: GitHubCLI) async {
        guard !isLoading else { return }
        isLoading = true
        switchFailure = nil
        defer { isLoading = false }
        do {
            status = try await cli.authStatus()
            if preferredHost == nil { preferredHost = cli.host ?? cli.environment["GH_HOST"] }
            error = nil
            loadProfiles(using: cli)
        } catch {
            self.error = error
        }
    }

    /// Confirm identity before remembering it. Failure leaves the previous choice intact.
    func select(_ account: AuthStatus.Account, using cli: GitHubCLI) async -> Bool {
        guard switchingTo == nil else { return false }
        guard account.active else {
            switchFailure =
                "Activate @\(account.login) on \(account.host) with gh auth switch in a terminal, then check accounts."
            return false
        }
        switchingTo = key(account)
        switchFailure = nil
        error = nil
        defer { switchingTo = nil }
        var next = selection
        next.logins[account.host] = account.login
        do {
            let credentials = status.map { next.includingDefaults(from: $0) } ?? next
            let user = try await cli.selecting(credentials).targeting(host: account.host).currentUser()
            guard user.login.caseInsensitiveCompare(account.login) == .orderedSame else {
                switchFailure =
                    "GitHub returned a different account. Your choice was kept. Sign in again, then check accounts."
                return false
            }
            profiles[key(account)] = user
            selection = next
            preferredHost = account.host
            defaults.set(account.host, forKey: "github.displayedHost")
            defaults.set(next.logins, forKey: Self.selectionKey)
            if var entries = status?.hosts[account.host],
                let index = entries.firstIndex(where: { $0.login == account.login })
            {
                entries[index].state = .success
                status?.hosts[account.host] = entries
            }
            return true
        } catch {
            let retained = current.map { " Still using \(name($0))." } ?? ""
            let recovery =
                if case .notAuthenticated = error {
                    " \(error.localizedDescription)"
                } else {
                    " \(error.localizedDescription) Try again when GitHub is available."
                }
            switchFailure = "Couldn't switch to @\(account.login)." + retained + recovery
            return false
        }
    }

    func recordFailure(_ error: GitHubError) {
        switch error {
        case .notAuthenticated, .notInstalled, .offline, .timedOut: self.error = error
        default: break
        }
    }

    var signOutCommand: String { "gh auth logout" }
    func copySignOutCommand() { DSPasteboard.copy(signOutCommand) }

    func addAccount() { showsSignIn = true; copiedCommand = false }
    var signInCommand: String { error == .notInstalled ? "brew install gh" : "gh auth login" }
    func copySignInCommand() { DSPasteboard.copy(signInCommand); copiedCommand = true }

    private func loadProfiles(using cli: GitHubCLI) {
        profileTask?.cancel()
        let accounts = accounts
        profileTask = Task { [weak self] in
            for account in accounts {
                guard let self, !Task.isCancelled else { return }
                let key = key(account)
                // Read the public profile through the user's gh, without switching to each account.
                if let data = try? await cli.targeting(host: account.host).run(.userProfile(login: account.login)),
                    let user = try? JSONDecoder().decode(GitHubUser.self, from: data)
                {
                    profiles[key] = user
                }
                if let url = profiles[key]?.avatarURL, let data = await GitHubAvatarCache.shared.image(at: url) {
                    avatars[key] = data
                }
            }
            guard let self, !Task.isCancelled else { return }
            if let data = try? JSONEncoder().encode(profiles) { defaults.set(data, forKey: "github.accountProfiles") }
        }
    }
}

#if DEBUG
extension GitHubAccountsModel {
    func configurePreview(
        status: AuthStatus?, error: GitHubError?, profiles: [String: GitHubUser], avatars: [String: Data] = [:]
    ) {
        self.status = status
        self.error = error
        self.profiles = profiles
        self.avatars = avatars
    }
}
#endif
