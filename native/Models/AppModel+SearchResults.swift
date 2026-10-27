import ACP
import Foundation

// Opening a task that search found, which may be one the sidebar doesn't list yet: a session from an
// agent's own history that `session/list` hasn't reported, or one in a folder that isn't a project.
extension AppModel {
    /// Selects the session, listing it under its project first when the sidebar doesn't have it,
    /// and adding the project when Native doesn't have that either. A feature that claims the
    /// session (`searchedSessionOpeners`) opens it instead, and the sidebar is left alone.
    @discardableResult
    func showSearchedSession(_ key: SessionKey, cwd: String, title: String?, projectFolder: String) async -> Bool {
        if searchedSessionOpeners.contains(where: { $0(key, cwd) }) { return true }
        if !catalog.contains(key) {
            let folder = URL(filePath: projectFolder, directoryHint: .isDirectory)
            let project: Project
            if let existing = projects.all.first(where: { SessionFolder.isSame($0.path, projectFolder) })
                ?? projects.all.first(where: { SessionFolder.contains($0.path, cwd) })
            {
                project = existing
            } else {
                guard let admitted = await admittedProjectFolder(folder) else { return false }
                project = projects.add(admitted)
            }
            catalog.add(SessionInfo(sessionId: key.id, cwd: cwd, title: title), for: key.agent, in: project.id)
        }
        selection = key
        return true
    }

    /// The session once it's open and its history has loaded, or nil if that doesn't happen within
    /// `timeout` (the agent can't start, say, which the session's own view explains).
    func loadedSession(_ key: SessionKey, timeout: Duration = .seconds(30)) async -> SessionModel? {
        let waiter = Task {
            for await phase in Observations({ self.sessions.session(key)?.phase }) {
                if let phase, phase != .loading {
                    return self.sessions.session(key)
                }
            }
            return nil
        }
        let timer = Task {
            try? await Task.sleep(for: timeout)
            waiter.cancel()
        }
        defer { timer.cancel() }
        return await waiter.value
    }
}
