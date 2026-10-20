import Foundation

// The folders a host's projects live in. Clients with the `runCommands` grant run commands and read
// files only inside them, a session's folder, or the host's task worktrees (docs/durability.md,
// "What a client may do"). A project is listed before anything runs in it, so a client can look at
// a checkout on the host (its branches, say) before starting a task there.

extension HostProtocol.Method {
    public static let listProjects = "_native/projects/list"
    public static let addProject = "_native/projects/add"
    public static let removeProject = "_native/projects/remove"
}

public struct HostProject: Codable, Hashable, Sendable {
    /// Absolute, with symbolic links resolved on the host.
    public var path: String
    public var addedAt: Date

    public init(path: String, addedAt: Date) {
        self.path = path
        self.addedAt = addedAt
    }
}

/// What `projects/list`, `add` and `remove` answer with.
public struct HostProjectList: Codable, Hashable, Sendable {
    public var projects: [HostProject]
    /// Where task worktrees go on this host (`~/.native/worktrees` in its user's home folder unless
    /// the Mac app there moved them). Clients reach what's inside like a project, and make a remote
    /// project's task worktrees here.
    public var worktreesFolder: String

    public init(projects: [HostProject], worktreesFolder: String) {
        self.projects = projects
        self.worktreesFolder = worktreesFolder
    }
}

/// Adds a folder as a project; adding one that's listed already changes nothing. The filesystem's
/// root and the home folder itself are refused: a project is one folder, not everything.
public struct AddProjectParams: Codable, Sendable {
    /// Absolute, on the host.
    public var path: String
    /// Make the folder (and any above it) if it isn't there yet, for a project about to be cloned.
    public var create: Bool

    public init(path: String, create: Bool = false) {
        self.path = path
        self.create = create
    }
}

/// Stops listing a folder as a project. Nothing on disk changes.
public struct RemoveProjectParams: Codable, Sendable {
    public var path: String

    public init(path: String) {
        self.path = path
    }
}
