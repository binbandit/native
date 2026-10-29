import Foundation

// The projects in the sidebar: adding, focusing, removing (with undo) and reordering them.
extension AppModel {
    /// Opens a folder as a project, or finds it if it's open already, and lists its sessions.
    func addProject(_ url: URL) async {
        guard let url = await admittedProjectFolder(url) else { return }
        _ = await addProject(url, focus: true)
    }

    /// Quick Entry adds a folder without replacing the task behind its panel.
    func addProject(_ url: URL, focus: Bool) async -> Project {
        let project = projects.add(url)
        if focus { focusProject(project.id) }
        // Agents that are parked list it once they've started (starting lists every project).
        for runtime in agents where runtime.status == .idle && !catalog.hasListed(runtime.agent.id, in: project.id) {
            Task { await ensureRunning(runtime.agent.id) }
        }
        await refreshSessions(in: project)
        return project
    }

    /// Shows a project's home: no session selected, and new sessions go to that project.
    func focusProject(_ id: Project.ID) {
        focusedProjectID = id
        selection = nil
    }

    /// Closes a project in the sidebar (its sessions stay with the agents). With an undo manager,
    /// ⌘Z puts it back in its place with the order the user gave its sessions.
    func removeProject(_ id: Project.ID, undoManager: UndoManager? = nil) {
        guard let index = projects.all.firstIndex(where: { $0.id == id }) else { return }
        let project = projects.all[index]
        let order = ordering.order(in: id)
        if let selection, catalog.lookup(selection)?.project == id {
            self.selection = nil
        }
        projects.remove(id)
        catalog.remove(project: id)
        ordering.forget(id)
        undoManager?.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated {
                model.restoreProject(project, at: index, order: order, undoManager: undoManager)
            }
        }
        undoManager?.setActionName("Remove Project")
    }

    private func restoreProject(_ project: Project, at index: Int, order: [SessionKey]?, undoManager: UndoManager?) {
        projects.restore(project, at: index)
        ordering.restore(order, in: project.id)
        undoManager?.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated {
                model.removeProject(project.id, undoManager: undoManager)
            }
        }
        undoManager?.setActionName("Remove Project")
        Task { await refreshSessions(in: project) }
    }

    /// Names a project in Native, open or archived; the folder keeps its own name. Nil, blank or the
    /// folder's name goes back to the folder's. ⌘Z puts the previous name back.
    func renameProject(_ id: Project.ID, to name: String?, undoManager: UndoManager? = nil) {
        guard let project = projects.project(id) ?? projects.archived.first(where: { $0.id == id }) else { return }
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = trimmed?.isEmpty == false && trimmed != project.folderName ? trimmed : nil
        guard displayName != project.displayName else { return }
        projects.rename(id, to: displayName)
        undoManager?.registerUndo(withTarget: self) { model in
            MainActor.assumeIsolated {
                model.renameProject(id, to: project.displayName, undoManager: undoManager)
            }
        }
        undoManager?.setActionName("Rename Project")
    }

    func moveProjects(fromOffsets source: IndexSet, toOffset destination: Int) {
        projects.move(fromOffsets: source, toOffset: destination)
    }

    /// The project new sessions go to unless the user picks one: the selected session's, else the first.
    var currentProject: Project? {
        if let selection, let listed = catalog.lookup(selection)?.project ?? startingTask(selection)?.project,
            let project = projects.project(listed)
        {
            return project.isNoProject ? nil : project
        }
        return focusedProjectID.flatMap(projects.project).flatMap { $0.isNoProject ? nil : $0 }
    }
}
