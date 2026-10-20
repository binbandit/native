import ACP
import Foundation
import NativeHostProtocol

// Who may run commands and read files on this host, and where (docs/durability.md, "What a client
// may do"): clients with the `runCommands` grant, inside the host's projects, its sessions' folders
// and its task worktrees. `HostCore+Exec.swift` and the file requests both go through here.
extension HostCore {
    /// Refuses a client without the `runCommands` grant. `action` finishes "This device isn't allowed
    /// to …".
    func requireCommandsGrant(_ client: ClientLink, to action: String) throws {
        guard client.grants.runCommands else { throw HostError.notAuthorized(action) }
    }

    /// Everywhere clients may reach right now.
    var projectPaths: ProjectPaths {
        let projects = (try? store.projects().map(\.path)) ?? []
        return ProjectPaths(roots: projects + sessions.values.map(\.record.cwd) + [worktreesFolder])
    }

    /// `path` resolved (symbolic links included) for a client with the grant, when it's inside one
    /// of the host's projects, sessions' folders or task worktrees.
    func projectPath(_ path: String, for client: ClientLink, to action: String) throws -> String {
        try requireCommandsGrant(client, to: action)
        do {
            return try projectPaths.resolve(path)
        } catch .notAbsolute {
            throw RPCError(code: -32602, message: "Paths on a host are absolute; \(path) isn't.")
        } catch .outsideProjects {
            throw HostError.outsideProjects(path)
        }
    }

    /// Refuses a session request that would start commands of the client's choosing (a stdio MCP
    /// server, agent options in `_meta`) from a client that may not run commands.
    func requireCommandsGrant(_ client: ClientLink, forSession mcpServers: [JSONValue], meta: JSONValue?) throws {
        guard HostProtocol.sessionRequestRunsCommands(mcpServers: mcpServers, meta: meta) else { return }
        try requireCommandsGrant(client, to: "start MCP servers or pass agent options")
    }

    // MARK: - Task worktrees

    /// Where task worktrees go here: `~/.native/worktrees`, unless the Mac app on this machine moved
    /// them (`SyncAgentsParams.worktreesFolder`).
    var worktreesFolder: String {
        if let folder = try? store.meta(MetaKey.worktreesFolder) { return folder }
        return FileManager.default.homeDirectoryForCurrentUser.appending(path: ".native/worktrees")
            .path(percentEncoded: false)
    }

    /// Only the local app says where its worktrees are (`agents/sync` is local only).
    func setWorktreesFolder(_ folder: String) throws {
        guard folder.hasPrefix("/") else { return }
        if folder != (try store.meta(MetaKey.worktreesFolder)) {
            try store.setMeta(MetaKey.worktreesFolder, folder)
        }
    }

    // MARK: - Projects

    func listProjects(for client: ClientLink) throws -> HostProjectList {
        try requireCommandsGrant(client, to: "see this host's projects")
        return HostProjectList(projects: try store.projects(), worktreesFolder: worktreesFolder)
    }

    func addProject(_ params: AddProjectParams, for client: ClientLink) throws -> HostProjectList {
        try requireCommandsGrant(client, to: "add projects")
        guard params.path.hasPrefix("/") else {
            throw RPCError(code: -32602, message: "Paths on a host are absolute; \(params.path) isn't.")
        }
        if params.create {
            try FileManager.default.createDirectory(atPath: params.path, withIntermediateDirectories: true)
        }
        var isFolder: ObjCBool = false
        guard let path = ProjectPaths.resolvedPath(params.path),
            FileManager.default.fileExists(atPath: path, isDirectory: &isFolder), isFolder.boolValue
        else { throw RPCError(code: -32602, message: "\(params.path) isn't a folder on this host.") }
        let home = ProjectPaths.resolvedPath(
            FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false))
        guard path != "/", path != home else {
            throw RPCError(
                code: -32602,
                message: "\(params.path) holds everything on this host; add the project's own folder instead.")
        }
        try store.addProject(HostProject(path: path, addedAt: .now))
        return try listProjects(for: client)
    }

    func removeProject(_ params: RemoveProjectParams, for client: ClientLink) throws -> HostProjectList {
        try requireCommandsGrant(client, to: "remove projects")
        // The folder may be gone already, so it's removed as given as well as resolved.
        for path in Set([params.path, ProjectPaths.resolvedPath(params.path)].compactMap(\.self)) {
            try store.removeProject(path)
        }
        return try listProjects(for: client)
    }
}
