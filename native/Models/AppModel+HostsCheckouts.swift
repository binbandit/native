import ACP
import Exec
import Foundation
import Git
import NativeHostClient
import NativeHostProtocol
import NativeLink
import os

// Which paired host has a checkout of which project, found by repository rather than by folder,
// and cloning a project onto a host that has none (`docs/durability.md`, "Host identity and many
// hosts"). Commands on a host go through its `RemoteCommandRunner`, which needs the pairing's
// `runCommands` grant.
extension AppModel {
    /// Reads which repository each of this Mac's projects is a checkout of, for the ones not read yet.
    func identifyProjects() async {
        #if os(macOS)
        let git = Git(environment: await shellEnvironment())
        for project in projects.all where project.remoteURL == nil {
            guard let repository = await ProjectRepository.read(at: project.path, with: git) else { continue }
            projects.update(project.id) { project in
                project.repository = repository.identity
                project.remoteURL = repository.remoteURL
            }
        }
        #endif
    }

    /// Finds `host`'s checkouts of this Mac's projects among the folders it lists as projects
    /// (`_native/projects/list`): a folder whose remote names the same repository is that project's
    /// checkout there. Checkouts the user set by hand are left alone.
    func findCheckouts(on host: RemoteHost) async {
        guard let client = host.client, host.isOnline, host.paired.grants.runCommands else { return }
        await identifyProjects()
        let unplaced = projects.all.filter { project in
            project.repository != nil && project.checkoutPath(on: .remote(host.id)) == nil
        }
        guard let listed = try? await client.projects() else { return }
        host.worktreesFolder = listed.worktreesFolder
        guard !unplaced.isEmpty else { return }
        let git = Git.onHost(client)
        for folder in listed.projects {
            guard let repository = await ProjectRepository.read(at: folder.path, with: git) else { continue }
            for project in unplaced
            where project.repository == repository.identity
                && projects.project(project.id)?.checkoutPath(
                    on: .remote(host.id)) == nil
            {
                setCheckout(folder.path, of: project.id, on: host.id)
            }
        }
    }

    /// `host`'s task workspaces (worktrees made with git there), asking the host where they go the
    /// first time. Nil without the `runCommands` grant, or before the app's wiring set them up.
    func taskWorkspaces(on host: RemoteHost) async -> (any TaskWorkspaceProvider)? {
        if let existing = host.taskWorkspaces { return existing }
        guard let client = host.client, host.paired.grants.runCommands, let make = hosts.makeTaskWorkspaces else {
            return nil
        }
        if host.worktreesFolder == nil {
            host.worktreesFolder = try? await client.projects().worktreesFolder
        }
        guard let folder = host.worktreesFolder else { return nil }
        let provider = make(client, URL(filePath: folder, directoryHint: .isDirectory))
        host.taskWorkspaces = provider
        return provider
    }

    /// Clones `project` onto `host` beside its other projects (or into `~/Developer` when it has
    /// none), records the checkout and returns its folder there. A folder already holding a checkout
    /// of the same repository is used as it is.
    func cloneProject(_ projectID: Project.ID, onto host: RemoteHost) async throws -> String {
        guard let project = projects.project(projectID), let remoteURL = project.remoteURL else {
            throw RemoteCheckoutError.noRemote
        }
        guard let client = host.client, host.isOnline else { throw RemoteCheckoutError.offline(host.name) }
        guard host.paired.grants.runCommands else { throw RemoteCheckoutError.notAllowed(host.name) }
        let listed = try await client.projects()
        var parent = listed.cloneFolder
        if parent == nil { parent = try await Self.developerFolder(on: client) }
        guard let parent else { throw RemoteCheckoutError.noFolder(host.name) }
        let folder = "\(parent)/\(project.folderName)"
        let git = Git.onHost(client)
        let added = try await client.addProject(folder, create: true)
        let path = added.projects.first { SessionFolder.isSame($0.path, folder) }?.path ?? folder
        if let existing = await ProjectRepository.read(at: path, with: git) {
            guard existing.identity == project.repository else {
                throw RemoteCheckoutError.occupied(path, host.name)
            }
        } else {
            let runner = RemoteCommandRunner(client: client)
            let result = try await runner.run(
                Command("git", ["clone", "--", remoteURL, "."], in: path, environment: [:]))
            guard result.exitCode == 0 else {
                // A folder made for the clone shouldn't stay listed as a project there.
                _ = try? await client.removeProject(path)
                let output = String(decoding: result.standardError, as: UTF8.self)
                throw RemoteCheckoutError.cloneFailed(output.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        setCheckout(path, of: project.id, on: host.id)
        return path
    }
}

extension AppModel {
    /// Uses a folder already on `host` as `project`'s checkout there (one cloned by hand, say):
    /// listed as a project on the host, so its commands may run there, and checked to be the same
    /// repository when the project has one.
    func useFolder(_ path: String, of projectID: Project.ID, on host: RemoteHost) async throws {
        guard let project = projects.project(projectID) else { return }
        guard let client = host.client, host.isOnline else { throw RemoteCheckoutError.offline(host.name) }
        guard host.paired.grants.runCommands else { throw RemoteCheckoutError.notAllowed(host.name) }
        let added = try await client.addProject(path)
        let resolved = added.projects.first { SessionFolder.isSame($0.path, path) }?.path ?? path
        if let identity = project.repository {
            guard await ProjectRepository.read(at: resolved, with: Git.onHost(client))?.identity == identity else {
                throw RemoteCheckoutError.occupied(resolved, host.name)
            }
        }
        setCheckout(resolved, of: project.id, on: host.id)
    }

    /// `Developer` in the home folder of the host's user, for a host whose projects and worktrees
    /// don't say where projects go.
    fileprivate static func developerFolder(on client: NativeHostClient) async throws -> String? {
        let result = try await RemoteCommandRunner(client: client).run(Command("printenv", ["HOME"], environment: [:]))
        let home = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.succeeded && home.hasPrefix("/") ? "\(home)/Developer" : nil
    }
}

/// Why a project couldn't be put on a paired host, worded for the starting task's failure.
enum RemoteCheckoutError: LocalizedError {
    case noRemote
    case offline(String)
    case notAllowed(String)
    case noFolder(String)
    case occupied(String, String)
    case cloneFailed(String)

    var errorDescription: String? {
        switch self {
        case .noRemote: "This project has no remote to clone from."
        case .offline(let host): "\(host) isn't connected. Native keeps trying; retry once it's back."
        case .notAllowed(let host):
            "\(host) was paired without running commands, so Native can't clone onto it. Pair it again to allow that."
        case .noFolder(let host): "Native couldn't tell where projects go on \(host)."
        case .occupied(let path, let host):
            "\(path) on \(host) holds something other than this project. Move it aside there, or choose this project's own folder on \(host)."
        case .cloneFailed(let output): output.isEmpty ? "git clone failed." : "git clone failed: \(output)"
        }
    }
}
