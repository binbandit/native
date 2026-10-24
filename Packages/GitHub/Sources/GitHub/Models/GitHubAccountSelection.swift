import Foundation

/// Native's choices, keyed by host. Only logins are persisted; credentials stay with gh.
public struct GitHubAccountSelection: Sendable, Equatable {
    public var logins: [String: String]

    public init(logins: [String: String] = [:]) {
        self.logins = logins
    }

    /// A removed choice stays unavailable until the user chooses another account. Never silently
    /// perform a write as gh's active account after the selected account has been signed out.
    public func accounts(in status: AuthStatus) -> [AuthStatus.Account] {
        Set(status.hosts.keys).union(logins.keys).sorted {
            ($0 == "github.com" ? 0 : 1, $0) < ($1 == "github.com" ? 0 : 1, $1)
        }.compactMap { host in
            if let login = logins[host] {
                return status.hosts[host]?.first { $0.login == login }
                    ?? AuthStatus.Account(host: host, login: login, active: false, state: .error)
            }
            return status.hosts[host]?.first(where: \.active)
        }
    }

    /// Remember gh's discovered defaults so requests can reject an account changed since refresh.
    /// gh owns credential selection; this check cannot lock its configuration. Environment-only
    /// credentials already belong to the captured environment and have no stored user token.
    public func includingDefaults(from status: AuthStatus) -> Self {
        var result = self
        for account in accounts(in: status) {
            if ["GH_TOKEN", "GITHUB_TOKEN", "GH_ENTERPRISE_TOKEN", "GITHUB_ENTERPRISE_TOKEN"].contains(
                account.tokenSource ?? "")
            {
                result.logins[account.host] = nil
                continue
            }
            if result.logins[account.host] == nil { result.logins[account.host] = account.login }
        }
        return result
    }

    public func availability(in status: AuthStatus) -> GitHubAvailability {
        let accounts = accounts(in: status)
        let working = accounts.filter { $0.active && $0.state == .success }
        if !working.isEmpty { return .ready(accounts: working) }
        if !accounts.isEmpty, accounts.allSatisfy({ $0.state == .timeout }) { return .offline }
        return .notAuthenticated
    }

}
