import ACP
import Git
import SwiftUI

/// The trailing indicators of a sidebar task row, from the features that know about the task: its
/// pull request, its working tree's state against its branch, and its context usage. One line,
/// each part showing only when it has something to say.
struct AppTaskRowAccessory: View {
    let summary: SessionSummary

    @Environment(AppModel.self) private var model
    @Environment(GitStore.self) private var git

    var body: some View {
        let folder = URL(filePath: summary.info.cwd, directoryHint: .isDirectory)
        let device = model.device(of: summary.id)
        HStack(spacing: DS.Space.xs) {
            if case .remote(let id) = device, let host = model.hosts.host(id) {
                HostDeviceBadge(
                    name: host.name, look: HostLookStore.shared.look(for: device, named: host.name),
                    availability: host.availability)
            }
            // The session identifies the machine even when checkout paths are identical.
            if hasOwnCheckout(folder) {
                let repository = git.model(for: folder, session: summary.id)
                if !device.isRemote, let branch = repository.branch?.name {
                    TaskPullRequestBadge(directory: folder, branch: branch)
                }
                GitBranchBadge.Live(model: repository, font: .dsMicro, style: .compact)
            }
            SessionContextUsage(summary: summary)
        }
    }

    /// Tasks running in the project folder share its checkout, so every one of them would repeat
    /// the same branch state; only a task with its own worktree says something about itself.
    private func hasOwnCheckout(_ folder: URL) -> Bool {
        guard let project = model.projects.project(summary.project) else { return false }
        return !SessionFolder.isSame(folder.folderPath, project.path)
    }
}
