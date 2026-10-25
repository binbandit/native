import Exec
import Foundation
import GitHub

/// gh on paired hosts, for their checkouts' branches (`BranchReference.host`). A host's gh runs
/// there with the host's own login-shell environment, signed-in account and GitHub hostname: no
/// environment or account choice from this Mac goes with it, and this Mac's gh never answers for a
/// host's checkout. Only hosts the remote-hosts wiring installed can be asked.
struct RemoteBranchPullRequests {
    /// One pairing's gh on a host. Installing the host's next pairing replaces it, and what it was
    /// still answering no longer counts.
    struct Source {
        let cli: GitHubCLI
        /// The pull request a branch was made for, read with the host's git (see
        /// `GitHubModel.linkedPullRequest`).
        let linkedPullRequest: @MainActor (BranchReference) async -> URL?
        fileprivate let pairing: Int
    }

    /// Why gh may not run on paired hosts right now (the organization's policy), or `nil`. Asked
    /// before every lookup, so nothing is sent to a host while it says no.
    var refusal: @MainActor () -> String? = { nil }
    private var sources: [RemoteHostID: Source] = [:]
    private var pairings = 0

    mutating func install(
        _ runner: any CommandRunner, on host: RemoteHostID,
        linkedPullRequest: @escaping @MainActor (BranchReference) async -> URL?
    ) {
        pairings += 1
        sources[host] = Source(
            cli: GitHubCLI(environment: [:], runner: HostEnvironmentRunner(base: runner)),
            linkedPullRequest: linkedPullRequest, pairing: pairings)
    }

    /// The gh to ask about `host`'s branches, or why it can't be asked.
    func source(for host: RemoteHostID) -> Result<Source, GitHubError> {
        if let refusal = refusal() { return .failure(.failed(exitCode: -1, refusal)) }
        // Not connected yet, or paired without running commands there.
        guard let source = sources[host] else { return .failure(.offline("Native can't run gh on the task's host.")) }
        return .success(source)
    }

    /// Whether answers from `source` still count: no later pairing with `host` replaced it.
    func isCurrent(_ source: Source, on host: RemoteHostID) -> Bool {
        sources[host]?.pairing == source.pairing
    }
}

/// Runs gh on a host under the host's own PATH. `GitHubCLI` adds the folders gh is usually installed
/// in to the PATH it sends, which suits this Mac's app environment; a host lays what a client sends
/// over its login-shell environment, so that PATH would hide where the host's gh and git live.
private struct HostEnvironmentRunner: CommandRunner {
    let base: any CommandRunner

    func run(_ command: Command) async throws -> CommandResult {
        var command = command
        command.environment["PATH"] = nil
        return try await base.run(command)
    }
}
