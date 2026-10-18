import Foundation

/// The folder Open In acts on: a project's, or a task's worktree. It's on this Mac, or on a remote
/// Native host, where only apps that can reach a folder over SSH apply (`OpenInTarget.remote`).
nonisolated enum OpenInLocation: Hashable, Sendable {
    case local(URL)
    /// `host` is the SSH destination, as `ssh` takes it.
    case remote(host: String, path: String)

    /// The folder of a project (or one of its tasks) on `host`.
    @MainActor
    init(folder: URL, host: HostID) {
        self =
            host == .local
            ? .local(folder) : .remote(host: host.rawValue, path: folder.path(percentEncoded: false))
    }

    /// What Copy Path copies.
    var path: String {
        switch self {
        case .local(let folder): folder.path(percentEncoded: false)
        case .remote(_, let path): path
        }
    }
}
