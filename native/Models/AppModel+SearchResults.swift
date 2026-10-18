import ACP
import Foundation

// Opening a task that search found, which may be one the sidebar doesn't list yet: a session from an
// agent's own history that `session/list` hasn't reported, or one in a folder that isn't a project.
extension AppModel {
    /// Selects the session, listing it under its project first when the sidebar doesn't have it,
    /// and adding the project when Native doesn't have that either.
    func showSearchedSession(_ key: SessionKey, cwd: String, title: String?, projectFolder: String) {
        if !catalog.contains(key) {
            let folder = URL(filePath: projectFolder, directoryHint: .isDirectory)
            let project =
                projects.all.first { $0.path == projectFolder }
                ?? projects.all.first { cwd == $0.path || cwd.hasPrefix($0.path + "/") }
                ?? projects.add(folder)
            catalog.add(SessionInfo(sessionId: key.id, cwd: cwd, title: title), for: key.agent, in: project.id)
        }
        selection = key
    }

    /// The session once it's open and its history has loaded, or nil if that doesn't happen within
    /// `timeout` (the agent can't start, say, which the session's own view explains).
    func loadedSession(_ key: SessionKey, timeout: Duration = .seconds(30)) async -> SessionModel? {
        await withTaskGroup(of: SessionModel?.self) { group in
            group.addTask { @MainActor in
                for await phase in Observations({ self.sessions.session(key)?.phase }) {
                    if let phase, phase != .loading {
                        return self.sessions.session(key)
                    }
                }
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let session = await group.next() ?? nil
            group.cancelAll()
            return session
        }
    }
}
