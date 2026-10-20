import Exec
import Foundation
import Git
import GitHub
import NativeHostClient

/// Which repository a checkout is, so checkouts on different devices are one project: the hosted
/// repository its remote names ("github.com/owner/name"), however that remote is spelled there
/// (`GitHub.RemoteRepository` reads every spelling git takes).
nonisolated struct ProjectRepository: Hashable, Sendable {
    /// Lowercased "host/owner/name".
    let identity: String
    /// The remote's URL as the checkout has it, to clone from.
    let remoteURL: String

    init?(remoteURL: String) {
        guard let repository = RemoteRepository(remoteURL: remoteURL) else { return nil }
        identity = "\(repository.host)/\(repository.owner)/\(repository.name)".lowercased()
        self.remoteURL = remoteURL
    }

    /// The checkout at `folder`'s repository, from its `origin` (or its first remote), with `git` on
    /// whichever machine `git`'s runner reaches. Nil for a folder that isn't a checkout of a hosted
    /// repository.
    static func read(at folder: String, with git: Git) async -> ProjectRepository? {
        guard let repository = try? await git.repository(at: URL(filePath: folder, directoryHint: .isDirectory)),
            let remotes = try? await repository.remoteURLs(),
            let remote = remotes.first(where: { $0.name == "origin" }) ?? remotes.first
        else { return nil }
        return ProjectRepository(remoteURL: remote.url)
    }
}

extension Git {
    /// Git on a paired host: its commands run there (`RemoteCommandRunner`) with the host's own
    /// login-shell environment, nothing of this Mac's, and it watches through the host's change
    /// feed (`_native/fs/watch`).
    nonisolated static func onHost(_ client: NativeHostClient) -> Git {
        Git(
            environment: [:], runner: RemoteCommandRunner(client: client),
            monitor: HostRepositoryMonitor { folder in
                RemoteFiles(client: client).changes(under: folder).map {
                    HostRepositoryMonitor.Batch(paths: $0.paths, isOverflow: $0.isOverflow)
                }
            })
    }
}
