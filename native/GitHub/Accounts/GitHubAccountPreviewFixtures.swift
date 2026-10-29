#if DEBUG
import Exec
import Foundation
import GitHub

nonisolated enum GitHubAccountPreviewFixtures {
    enum State: String, CaseIterable, Identifiable {
        case loading, single, multiple, signedOut, missing, expired, offline, longName, loginOnly, failedSwitch,
            switchable
        var id: Self { self }
    }

    static let first = AuthStatus.Account(host: "github.com", login: "alex-morgan", active: true, state: .success)
    static let second = AuthStatus.Account(host: "github.com", login: "alex-work", active: false, state: .success)
    static let profiles = [
        "github.com/alex-morgan": GitHubUser(login: "alex-morgan", name: "Alex Morgan"),
        "github.com/alex-work": GitHubUser(login: "alex-work", name: "Alex at Work"),
    ]

    @MainActor static func model(_ state: State) -> GitHubModel {
        let defaults = PreviewUserDefaults()
        if state == .switchable {
            defaults.set(["github.com": first.login], forKey: GitHubAccountsModel.selectionKey)
        }
        let model = GitHubModel(
            environment: { _ in [:] }, runner: GitHubAccountFixtureRunner(state: state), defaults: defaults)
        var profileData = profiles
        if state == .longName {
            profileData["github.com/alex-morgan"] = GitHubUser(login: "alex-morgan", name: "Alexandra Morgan-Williams")
        }
        if state == .loginOnly {
            profileData["github.com/alex-morgan"] = GitHubUser(login: "alex-morgan", name: "  ")
        }
        model.accounts.configurePreview(
            status: status(state), error: error(state), profiles: profileData,
            avatars: state == .multiple || state == .switchable
                ? ["github.com/alex-morgan": avatarData].compactMapValues { $0 } : [:])
        return model
    }

    /// Authored portrait data exercises the cached-image path without contacting an avatar server.
    static let avatarData = Data(
        base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAAAn0lEQVR4nO3XsRHAIAwEQYqjWpq0O7CReHgYLlCKbhMGSq31OXmKOwCAOwCAOwCAOwCA+sDW2udsDfiLn4GQAXrj1QgJIBqvRADIxqsQAAAAGDxgBKHYDSCLUO3lLRRFqPfxH3APAPdwjR79lBiNVyBSAFW4AhIGzIrPIu4CzI7PILoBq+KjiDsAq+MjCADbA1zxvQgAAAAA2BzgRPS0vQ6IlkLDoYLEAAAAAElFTkSuQmCC"
    )

    static func status(_ state: State) -> AuthStatus? {
        switch state {
        case .loading, .missing: return nil
        case .signedOut: return AuthStatus(hosts: [:])
        case .switchable:
            var previous = first
            previous.active = false
            var next = second
            next.active = true
            return AuthStatus(hosts: ["github.com": [previous, next]])
        case .multiple, .failedSwitch: return AuthStatus(hosts: ["github.com": [first, second]])
        default:
            var account = first
            if state == .expired { account.state = .error }
            if state == .offline { account.state = .timeout }
            return AuthStatus(hosts: ["github.com": [account]])
        }
    }

    static func error(_ state: State) -> GitHubError? {
        switch state {
        case .missing: .notInstalled
        case .offline: .offline("")
        default: nil
        }
    }
}

/// Inert account states for isolated UI checks. Every command is answered locally, never delegated
/// to real gh. The account choice still travels through Native's account-checking path.
nonisolated struct GitHubAccountFixtureRunner: CommandRunner {
    let state: GitHubAccountPreviewFixtures.State

    func run(_ command: Command) async throws -> CommandResult {
        if state == .missing { throw CommandError.notFound("gh") }
        let arguments = command.arguments
        if arguments.starts(with: ["auth", "status"]) {
            let accounts = GitHubAccountPreviewFixtures.status(state)?.hosts["github.com"] ?? []
            let rows = accounts.map { account in
                [
                    "host": account.host, "login": account.login, "active": account.active,
                    "state": account.state?.rawValue ?? "SUCCESS",
                ] as [String: Any]
            }
            return success(
                try JSONSerialization.data(withJSONObject: ["hosts": rows.isEmpty ? [:] : ["github.com": rows]]))
        }
        if state == .offline { return failure("error connecting to api.github.com") }
        if state == .expired { return failure("HTTP 401: Bad credentials") }
        if arguments.starts(with: ["api", "user"]) || arguments.contains(where: { $0.hasPrefix("users/") }) {
            let login =
                arguments.first(where: { $0.hasPrefix("users/") })?.replacingOccurrences(of: "users/", with: "")
                ?? (state == .switchable ? "alex-work" : "alex-morgan")
            if state == .failedSwitch, login == "alex-work" { return failure("HTTP 401: Bad credentials") }
            return success(
                try JSONEncoder().encode(
                    GitHubAccountPreviewFixtures.profiles["github.com/\(login)"] ?? GitHubUser(login: login)))
        }
        if arguments.first == "search" { return success(Data("[]".utf8)) }
        throw CommandError.notFound("fixture command")
    }

    private func success(_ data: Data) -> CommandResult {
        CommandResult(exitCode: 0, standardOutput: data, standardError: Data())
    }

    private func failure(_ message: String) -> CommandResult {
        CommandResult(exitCode: 1, standardOutput: Data(), standardError: Data(message.utf8))
    }
}
#endif
