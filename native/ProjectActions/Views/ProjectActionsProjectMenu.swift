import SwiftUI

/// The project menu's Run submenu (the sidebar's "…" and its context menu): the project's actions,
/// run in the task in view when it's one of the project's, otherwise quietly in the project's own
/// folder, with a toast when they end.
struct ProjectActionsProjectMenu: View {
    let project: Project
    @Environment(AppModel.self) private var model
    @Environment(ProjectActionRunner.self) private var runner

    var body: some View {
        let target = target
        Menu("Run") {
            if target.session == nil {
                Text("In \(project.name)'s folder, in the background")
            }
            ProjectActionsMenuContent(target: target)
        }
        .labelStyle(.titleAndIcon)
        .onAppear { runner.store.refresh(project) }
    }

    private var target: ProjectActionTarget {
        let session = model.selection.flatMap { key in
            model.catalog.lookup(key)?.project == project.id ? model.session(key) : nil
        }
        return ProjectActionTarget(project: project, session: session)
    }
}
