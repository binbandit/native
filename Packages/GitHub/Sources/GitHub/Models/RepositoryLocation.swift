import Foundation

/// Where a command finds its repository.
public enum RepositoryLocation: Sendable, Hashable {
    /// A local checkout; gh resolves the repository from the folder's git remotes. Commands that
    /// touch the working tree (checkout, create) need one.
    case directory(URL)
    /// `owner/name`, or `host/owner/name` on another host, passed as `--repo`.
    case remote(String)
}
