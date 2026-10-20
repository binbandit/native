#if DEBUG
import ACP
import Foundation

/// The app for previews: the built-in agents' definitions (never started, so no process runs), and
/// projects and tasks kept in memory (`PreviewUserDefaults`, no catalog file), so a preview never
/// reads or changes the user's data.
extension AppModel {
    enum PreviewContent {
        /// No projects yet, as on first launch.
        case empty
        /// Three projects with tasks in every state (`AppPreviewFixtures`).
        case populated
    }

    static func preview(_ content: PreviewContent = .populated) -> AppModel {
        let app = AppModel(
            plugins: PluginRegistry(builtIns: [BuiltInPlugins.claudeCode, BuiltInPlugins.codex, BuiltInPlugins.cursor]),
            defaults: PreviewUserDefaults(), catalogURL: nil)
        _ = app.runtimes.sync()
        if content == .populated {
            app.addPreviewTasks()
        }
        return app
    }

    /// The project at `index` in `AppPreviewFixtures.projectFolders`.
    func previewProject(_ index: Int = 0) -> Project? {
        projects.all.indices.contains(index) ? projects.all[index] : nil
    }

    private func addPreviewTasks() {
        let added = AppPreviewFixtures.projectFolders.map {
            projects.add(URL(filePath: $0, directoryHint: .isDirectory))
        }
        for task in AppPreviewFixtures.tasks {
            let project = added[task.project]
            let date = Date.now.addingTimeInterval(-task.minutesAgo * 60)
            let info = SessionInfo(sessionId: SessionID(task.id), cwd: project.path, title: task.title, updatedAt: date)
            let agent = AgentDefinition.ID(rawValue: task.agent)
            catalog.add(info, for: agent, in: project.id)
            let key = SessionKey(agent: agent, id: SessionID(task.id))
            switch task.state {
            case .idle:
                break
            case .working:
                SessionModel.preview(in: self, agent: task.agent, id: task.id, cwd: project.path, title: task.title)?
                    .previewRunningTurn(task.title)
            case .needsPermission:
                SessionModel.preview(in: self, agent: task.agent, id: task.id, cwd: project.path, title: task.title)?
                    .previewPermissionRequest()
            case .doneUnread:
                SessionModel.preview(in: self, agent: task.agent, id: task.id, cwd: project.path, title: task.title)?
                    .previewExchange(task.title, reply: "Done. Titles now come from the first prompt.")
                unread.set(key, unread: true)
            case .failed:
                SessionModel.preview(
                    in: self, agent: task.agent, id: task.id, cwd: project.path, title: task.title, phase: .disconnected
                )
            case .pinned:
                ordering.pin(key)
            case .archived:
                archivedSessions.set(key, archived: true)
            }
        }
    }
}
#endif
