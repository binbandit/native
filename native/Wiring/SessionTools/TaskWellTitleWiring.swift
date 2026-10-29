import Git
import NativePolicy
import SwiftUI

/// The well's title, from the task's own model, its checkout and the organization's policy.
/// Renaming goes through `AppModel.rename`, so ⌘Z and the sidebar see the same title.
struct TaskWellTitleWiring: View {
    let session: SessionModel
    @Bindable var tools: SessionToolsScreenModel
    /// The title's width shown whole, so the toolbar can make room for it.
    var reportsIdealWidth: (CGFloat) -> Void = { _ in }
    @Environment(AppModel.self) private var app
    @Environment(GitStore.self) private var git
    @Environment(PolicyCenter.self) private var policy
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        TaskWellTitle(
            facts: facts, isPresented: $tools.showsTitle, reportsIdealWidth: reportsIdealWidth,
            moveToProject: session.isProjectless ? { app.requestMoveToProject(session.key) } : nil
        ) { title in
            app.rename(session.key, to: title, undoManager: undoManager)
        }
        .onChange(of: tools.showsTitle) { _, isShown in
            if isShown { tools.showsWell = false }
        }
    }

    private var facts: TaskWellTitleFacts {
        let device = app.device(of: session.key)
        let isWorkerManaged = !policy.policy.managedKeys.isDisjoint(with: PolicyCenter.taskWorkerKeys)
        return TaskWellTitleFacts(
            title: session.displayTitle, project: app.projectName(of: session),
            branch: session.isProjectless ? nil : git.model(for: session.cwd, session: session.key).branchName,
            isProjectFolder: app.offersProjectFolderTasks && app.usesProjectFolder(session.key),
            machine: device.isRemote ? app.deviceName(device) : nil, agent: session.agentName,
            model: ComposerSettings(session.configOptions).model?.shortModelName,
            isWorkerManaged: isWorkerManaged,
            management: isWorkerManaged ? policy.managementLine : nil)
    }
}

extension AppModel {
    /// The project a task belongs to, by its own name rather than its worktree's folder.
    func projectName(of session: SessionModel) -> String {
        guard let id = catalog.lookup(session.key)?.project else { return session.cwd.lastPathComponent }
        // A task of an archived project can still be opened from the archive.
        return projectName(for: session.key, in: id) ?? session.cwd.lastPathComponent
    }
}

extension GitRepositoryModel {
    /// The checked-out branch, or nil outside a repository or on a detached head.
    var branchName: String? {
        guard case BranchStatus.Head.branch(let name)? = branch?.head else { return nil }
        return name
    }
}
