import Foundation
import Git
import GitHub
import NativeHostClient

/// Gives paired hosts' tasks the same workspaces and git as this Mac's: each host gets a store whose
/// git runs on the host and keeps worktrees where the host says (`HostProjectList.worktreesFolder`),
/// with the Git feature's worktree per task and the host's task scripts run there too. Archiving and
/// deleting go through `DeviceTaskWorkspaces`, which picks the device by folder; everything that
/// reads a folder (the changes inspector, branch and diff badges) goes to its host's store through
/// `GitStore.hostStore`.
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
                environment: { [:] }, settings: settings, worktreesFolder: worktreesFolder,
                makeGit: { _ in Git.onHost(client) })
            stores.byClient[ObjectIdentifier(client)] = store
            let scripts = TaskScriptCenter(settings: TaskScriptSettings(), runner: RemoteCommandRunner(client: client))
            return GitTaskWorkspaceProvider(git: store, gitHub: gitHub, scripts: scripts)
        }
        git.hostStore = { [weak model] folder in
            guard let client = model?.remoteHost(holding: folder)?.client else { return nil }
            return stores.byClient[ObjectIdentifier(client)]
        }
    }
}

/// Each paired host's git store, by its client, once the host has said where its worktrees go.
private final class RemoteHostGitStores {
    var byClient: [ObjectIdentifier: GitStore] = [:]
}
