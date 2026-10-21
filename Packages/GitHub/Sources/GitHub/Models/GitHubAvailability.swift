import Foundation

/// Whether GitHub features can be used, and if not, what the user has to do about it.
public enum GitHubAvailability: Sendable, Hashable {
    /// gh isn't on the PATH.
    case notInstalled
    /// gh is installed but holds no working login.
    case notAuthenticated
    /// gh couldn't reach any host to check its logins.
    case offline
    /// Signed in. The selected (otherwise gh-active) account per host with a working token, github.com first.
    case ready(accounts: [AuthStatus.Account])
}
