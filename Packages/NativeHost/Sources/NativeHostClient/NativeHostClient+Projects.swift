import Foundation
import NativeHostProtocol

// The folders a host's projects live in, where `RemoteCommandRunner` and the file requests may
// reach. All take the `runCommands` grant.
extension NativeHostClient {
    /// The host's projects, and where its task worktrees go.
    public func projects() async throws -> HostProjectList {
        try await call(HostProtocol.Method.listProjects, EmptyMessage())
    }

    /// Lists a folder on the host as a project; `create` makes it first, for a clone.
    public func addProject(_ path: String, create: Bool = false) async throws -> HostProjectList {
        try await call(HostProtocol.Method.addProject, AddProjectParams(path: path, create: create))
    }

    /// Stops listing a folder as a project; nothing on the host's disk changes.
    public func removeProject(_ path: String) async throws -> HostProjectList {
        try await call(HostProtocol.Method.removeProject, RemoveProjectParams(path: path))
    }
}
