import Foundation

/// Where a branch's own work begins: the commit it left the default branch at, or, on the default
/// branch, its upstream.
public struct BranchBase: Hashable, Sendable {
    public var commit: String
    /// What it's compared with, as git names it: `origin/main`, `main`.
    public var name: String

    public init(commit: String, name: String) {
        self.commit = commit
        self.name = name
    }
}
