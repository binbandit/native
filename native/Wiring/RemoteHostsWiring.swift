import Foundation
import Git
import GitHub
import NativeHostClient
import Observation

/// Gives paired hosts' tasks the same workspaces and git as this Mac's: each host gets a store whose
/// git runs on the host and keeps worktrees where the host says (`HostProjectList.worktreesFolder`),
/// with the Git feature's worktree per task and the host's task scripts run there too. Archiving and
/// deleting go through `DeviceTaskWorkspaces`, which picks the device by folder; everything that
/// reads a task (the changes inspector, branch and diff badges) selects its host by session identity
/// through `GitStore.sessionStore`. A pathname alone always stays local.
enum RemoteHostsWiring {
    /// Wraps this Mac's task workspaces in `DeviceTaskWorkspaces` (kept by `model.hosts`, since
    /// `AppModel.taskWorkspaces` is weak) and teaches `model.hosts` to make each host's. Nothing
    /// changes while remote hosts are off.
    static func connect(model: AppModel, local: any TaskWorkspaceProvider, git: GitStore, gitHub: GitHubModel) {
        guard RemoteHosts.isEnabled else { return }
        let devices = DeviceTaskWorkspaces(local: local, model: model)
        model.hosts.deviceWorkspaces = devices
        model.taskWorkspaces = devices
        let settings = git.settings
        let stores = RemoteHostGitStores()
        model.hosts.makeTaskWorkspaces = { client, worktreesFolder in
            let store = GitStore(
                environment: { [:] }, settings: settings, worktreesFolder: worktreesFolder, isLocal: false,
                makeGit: { _ in Git.onHost(client) })
            stores.byClient[ObjectIdentifier(client)] = store
            let scripts = TaskScriptCenter(settings: TaskScriptSettings(), runner: RemoteCommandRunner(client: client))
            return GitTaskWorkspaceProvider(git: store, gitHub: gitHub, scripts: scripts)
        }
        git.sessionStore = { [weak model, weak git] session in
            guard let model else { return nil }
            // A loaded session retains its client even after its pairing is removed.
            if let client = model.sessions.session(session)?.host?.client {
                if client === model.runtimes.host { return git }
                return stores.byClient[ObjectIdentifier(client)]
            }
            guard case .remote(let id) = model.device(of: session) else { return git }
            guard let client = model.hosts.host(id)?.client else { return nil }
            return stores.byClient[ObjectIdentifier(client)]
        }
    }
}

/// Each paired host's git store, by its client, once the host has said where its worktrees go.
@Observable
private final class RemoteHostGitStores {
    var byClient: [ObjectIdentifier: GitStore] = [:]
}
