import SwiftUI

// Temporary: keeps `HomeDetail`'s call sites from before projects compiling until it moves to the
// `HomeView(agents:projects:project:...)` and `HomeWelcomeView(agents:...)` API. Delete with that change.

extension HomeView where ProjectID == URL {
    init(
        folder: URL,
        agents: [HomeAgent<AgentID>],
        recentTasks: [HomeTask<TaskID>],
        recentFolders: [URL],
        onNewTask: @escaping (AgentID) -> Void,
        onOpenFolder: @escaping () -> Void,
        onOpenRecent: @escaping (URL) -> Void,
        onSelectTask: @escaping (TaskID) -> Void
    ) {
        self.init(
            agents: agents,
            projects: recentFolders.map { HomeProject(id: $0, name: $0.lastPathComponent, url: $0) },
            project: .constant(folder),
            recentTasks: recentTasks,
            onNewTask: { agent, _ in onNewTask(agent) },
            onAddProject: onOpenFolder,
            onSelectTask: onSelectTask
        )
    }
}

extension HomeWelcomeView where AgentID == String {
    init(recentFolders: [URL], openFolderShortcut: KeyboardShortcut?, onOpenFolder: @escaping () -> Void, onOpenRecent: @escaping (URL) -> Void) {
        self.init(agents: [], addProjectShortcut: openFolderShortcut, onAddProject: onOpenFolder)
    }
}
